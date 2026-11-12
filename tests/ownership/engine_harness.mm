/*
 * Synthetic 4D engine boundary for Notification Center ownership regressions.
 *
 * Links the real plugin source (4DPlugin.cpp), the plugin classes
 * (4D Plugin API/Classes) and the bundled, unmodified 4D Plugin API
 * (4DPluginAPI.c). Only gCall4D is replaced: it models engine-side
 * allocations (Unistrings, handles, pictures) with malloc/free so ASan
 * reports double frees and use-after-free, and keeps a live set of every
 * engine string, handle and picture so leaks are detected exactly.
 *
 * No real notification is ever posted and no authorization is requested:
 * +[NSUserNotificationCenter defaultUserNotificationCenter] is replaced
 * before any test runs by a fake centre that records deliveries and
 * synchronously calls the delegate (synthetic delivery).
 *
 * Engine semantics modelled (SDK contract):
 *  - PA_CreateVariable(eVK_Unistring / eVK_Picture) allocates an empty
 *    engine string / picture (4DPluginAPI.c); PA_SetStringVariable and
 *    PA_SetPictureVariable overwrite the variable shallowly.
 *  - PA_ClearVariable releases what the variable owns.
 *  - PA_ExecuteMethodByID (EX_CALL_BY_PROCID) returns a value owned by the
 *    caller. On error the returned slot is not the caller's: clearing it is
 *    an engine violation.
 *  - EXECUTE METHOD (1007) without "*" returns Undefined.
 *  - Pictures are reference counted: PA_DuplicatePicture(p, 1) retains,
 *    PA_DisposePicture releases one reference.
 *  - Commands that write a picture into an output parameter (READ PICTURE
 *    FILE, CREATE THUMBNAIL) release the picture previously held by that
 *    variable (the most forgiving engine model).
 */

#include "4DPluginAPI.h"
#include "PrivateTypes.h"
#include "EntryPoints.h"
#include "4DPlugin.h"

#import <Foundation/Foundation.h>
#include <objc/runtime.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <map>
#include <set>
#include <string>
#include <vector>

extern "C" Call4DProcPtr gCall4D;
void listener_start(); /* defined in 4DPlugin.cpp, not declared in 4DPlugin.h */

/* ---- fake notification centre (synthetic delivery) ---- */

@interface FakeNotificationCenter : NSObject
@property (assign) id delegate;
@property (retain) NSMutableArray *delivered;
@property (retain) NSMutableArray *scheduled;
- (void)deliverNotification:(NSUserNotification *)notification;
- (void)scheduleNotification:(NSUserNotification *)notification;
@end

@implementation FakeNotificationCenter
- (id)init {
    if((self = [super init])) {
        _delivered = [[NSMutableArray alloc] init];
        _scheduled = [[NSMutableArray alloc] init];
    }
    return self;
}
- (void)deliverNotification:(NSUserNotification *)notification {
    [_delivered addObject:notification];
    id d = self.delegate;
    if([d respondsToSelector:@selector(userNotificationCenter:didDeliverNotification:)])
        [d userNotificationCenter:(NSUserNotificationCenter *)self didDeliverNotification:notification];
}
- (void)scheduleNotification:(NSUserNotification *)notification {
    [_scheduled addObject:notification];
}
@end

static FakeNotificationCenter *g_center = nil;
static id fake_default_center(id, SEL) { return g_center; }

namespace {

typedef std::basic_string<PA_Unichar> u16;

struct Handle { char *data; PA_long32 len; };
struct Pic { int refs; };

std::set<void *> g_strings;
std::set<Handle *> g_handles;
std::set<Pic *> g_pics;

/* method / process model */
const PA_long32 kMethodId = 77;
u16 g_known_method;           /* PA_GetMethodID resolves only this name */
bool g_method_returns_text = false;
bool g_method_fails = false;
PA_Unichar g_error_slot[] = { 'x', 0 }; /* not an engine allocation */
PA_Unichar *g_last_result = nullptr;
int g_method_calls = 0, g_1007_calls = 0, g_new_process = 0, g_killed = 0, g_sleeps = 0;
std::vector<u16> g_args;
bool g_dying = false;
const char *g_process_name = "Design process";

u16 g_read_path, g_convert_type;
int g_transform_op = 0, g_thumb_w = 0, g_thumb_h = 0;

[[noreturn]] void die(const char *msg) {
    fprintf(stderr, "ENGINE VIOLATION: %s\n", msg);
    fflush(stderr);
    abort();
}

u16 to_u16(const char *s) { u16 r; for(; *s; ++s) r.push_back((PA_Unichar)(unsigned char)*s); return r; }

PA_Unistring new_string(const PA_Unichar *src, size_t len) {
    PA_Unichar *buf = (PA_Unichar *)malloc((len + 1) * sizeof(PA_Unichar));
    if(len) memcpy(buf, src, len * sizeof(PA_Unichar));
    buf[len] = 0;
    g_strings.insert(buf);
    PA_Unistring s;
    s.fLength = (PA_long32)len;
    s.fString = buf;
    s.fReserved1 = 0;
    s.fReserved2 = 0;
    return s;
}

void free_string(PA_Unistring *s) {
    if(!s->fString) return;
    if(!g_strings.erase(s->fString)) die("disposed a string the engine does not own");
    free(s->fString);
    s->fString = 0;
    s->fLength = 0;
}

Handle *new_handle(PA_long32 len) {
    Handle *h = (Handle *)malloc(sizeof(Handle));
    h->data = (char *)calloc(1, len ? len : 1);
    h->len = len;
    g_handles.insert(h);
    return h;
}

Handle *checked(PA_Handle ph) {
    Handle *h = (Handle *)ph;
    if(!g_handles.count(h)) die("used an unknown handle");
    return h;
}

void free_handle(Handle *h) {
    if(!h) return;
    checked((PA_Handle)h);
    g_handles.erase(h);
    free(h->data);
    free(h);
}

Pic *new_pic() {
    Pic *p = (Pic *)malloc(sizeof(Pic));
    p->refs = 1;
    g_pics.insert(p);
    return p;
}

Pic *live_pic(PA_Picture pp) {
    Pic *p = (Pic *)pp;
    if(!g_pics.count(p)) die("used a picture the engine does not own");
    return p;
}

void release_pic(PA_Picture pp) {
    if(!pp) return;
    Pic *p = live_pic(pp);
    if(--p->refs == 0) { g_pics.erase(p); free(p); }
}

void clear_var(PA_Variable *v) {
    switch(v->fType) {
        case eVK_Unistring: free_string(&v->uValue.fString); break;
        case eVK_Picture: release_pic(v->uValue.fPicture); v->uValue.fPicture = 0; break;
        case eVK_ArrayUnicode: {
            Handle *h = (Handle *)v->uValue.fArray.fData;
            if(h) {
                PA_Unistring *items = (PA_Unistring *)checked((PA_Handle)h)->data;
                for(PA_long32 i = 0; i <= v->uValue.fArray.fNbElements; ++i) free_string(&items[i]);
                free_handle(h);
            }
            break;
        }
        default: break;
    }
    v->fType = eVK_Undefined;
}

u16 live_text(const PA_Variable &v, const char *what) {
    if(v.fType != eVK_Unistring) die(what);
    if(!g_strings.count(v.uValue.fString.fString)) die("engine received a string it does not own");
    return u16(v.uValue.fString.fString, v.uValue.fString.fLength);
}

void live_picture_var(const PA_Variable &v, const char *what) {
    if(v.fType != eVK_Picture || !v.uValue.fPicture) die(what);
    live_pic(v.uValue.fPicture);
}

PA_long32 longint(const PA_Variable &v, const char *what) {
    if(v.fType != eVK_Longint) die(what);
    return v.uValue.fLongint;
}

void write_picture(PA_Variable *v) {
    if(v->fType == eVK_Picture) release_pic(v->uValue.fPicture);
    else if(v->fType != eVK_Undefined) die("picture output parameter has a non-picture value");
    v->fType = eVK_Picture;
    v->uValue.fPicture = new_pic();
}

void command(EngineBlock *eb) {
    PA_Variable **v = (PA_Variable **)eb->fPtr1;
    PA_long32 n = (PA_long32)eb->fParam2;
    switch(eb->fParam1) {
        case 1007: /* EXECUTE METHOD(method; $1..$6) without "*": returns Undefined */
            if(n != 7) die("EXECUTE METHOD parameter count");
            g_args.clear();
            for(PA_long32 i = 0; i < n; ++i) g_args.push_back(live_text(*v[i], "EXECUTE METHOD parameter is not text"));
            g_1007_calls++;
            break;
        case 678: /* READ PICTURE FILE(path; picture) */
            if(n != 2) die("READ PICTURE FILE parameter count");
            g_read_path = live_text(*v[0], "path parameter is not text");
            write_picture(v[1]);
            break;
        case 1002: /* CONVERT PICTURE(picture; type) */
            if(n != 2) die("CONVERT PICTURE parameter count");
            live_picture_var(*v[0], "CONVERT PICTURE picture");
            g_convert_type = live_text(*v[1], "type parameter is not text");
            break;
        case 988: /* TRANSFORM PICTURE(picture; operator) */
            if(n != 2) die("TRANSFORM PICTURE parameter count");
            live_picture_var(*v[0], "TRANSFORM PICTURE picture");
            g_transform_op = longint(*v[1], "operator is not longint");
            break;
        case 457: /* PICTURE PROPERTIES(picture; width; height) */
            if(n != 3) die("PICTURE PROPERTIES parameter count");
            live_picture_var(*v[0], "PICTURE PROPERTIES picture");
            v[1]->fType = eVK_Longint; v[1]->uValue.fLongint = 640;
            v[2]->fType = eVK_Longint; v[2]->uValue.fLongint = 480;
            break;
        case 679: /* CREATE THUMBNAIL(picture; thumbnail; width; height) */
            if(n != 4) die("CREATE THUMBNAIL parameter count");
            live_picture_var(*v[0], "CREATE THUMBNAIL source");
            g_thumb_w = longint(*v[2], "width is not longint");
            g_thumb_h = longint(*v[3], "height is not longint");
            write_picture(v[1]);
            break;
        default: die("unexpected command");
    }
    eb->fError = 0;
}

/* PA_ExecuteMethodByID: slot 0 is the returned value, slots 1..n the parameters */
void call_by_procid(EngineBlock *eb) {
    if(eb->fParam1 != kMethodId) die("unknown method id");
    PA_Variable *slots = (PA_Variable *)checked(eb->fHandle)->data;
    PA_long32 n = (PA_long32)eb->fParam2;
    if(n != 6) die("listener method parameter count");
    g_args.clear();
    for(PA_long32 i = 1; i <= n; ++i) g_args.push_back(live_text(slots[i], "listener method parameter is not text"));
    g_method_calls++;
    if(g_method_fails) {
        slots[0].fType = eVK_Unistring;
        slots[0].uValue.fString.fString = g_error_slot;
        slots[0].uValue.fString.fLength = 1;
        eb->fError = -1;
        return;
    }
    if(g_method_returns_text) {
        const PA_Unichar r[] = { 'o', 'k', 0 };
        slots[0].fType = eVK_Unistring;
        slots[0].uValue.fString = new_string(r, 2);
        g_last_result = slots[0].uValue.fString.fString;
    }
    eb->fError = 0;
}

void engine(PA_long32 selector, void *p) {
    EngineBlock *eb = (EngineBlock *)p;
    switch(selector) {
        case EX_HANDLE_MANAGER:
            switch(eb->fParam1) {
                case 1: eb->fHandle = (PA_Handle)new_handle((PA_long32)eb->fParam2); eb->fError = 0; return;
                case 2: free_handle((Handle *)eb->fHandle); eb->fError = 0; return;
                case 3: {
                    Handle *h = checked(eb->fHandle);
                    PA_long32 n = (PA_long32)eb->fParam2;
                    h->data = (char *)realloc(h->data, n ? n : 1);
                    if(n > h->len) memset(h->data + h->len, 0, n - h->len);
                    h->len = n; eb->fError = 0; return;
                }
                case 4: eb->fParam2 = checked(eb->fHandle)->len; eb->fError = 0; return;
                case 5: eb->fParam3 = (sLONG_PTR)checked(eb->fHandle)->data; eb->fError = 0; return;
                case 6: checked(eb->fHandle); eb->fError = 0; return;
                default: die("unmodelled handle manager call");
            }
        case EX_CREATE_UNISTRING: {
            const PA_Unichar *s = (const PA_Unichar *)eb->fHandle;
            size_t n = 0; while(s[n]) ++n;
            eb->fUniString1 = new_string(s, n);
            return;
        }
        case EX_SET_UNISTRING: {
            const PA_Unichar *s = (const PA_Unichar *)eb->fHandle;
            size_t n = 0; while(s[n]) ++n;
            free_string(&eb->fUniString1);
            eb->fUniString1 = new_string(s, n);
            return;
        }
        case EX_DISPOSE_UNISTRING: free_string(&eb->fUniString1); return;
        case EX_CLEAR_VARIABLE: clear_var((PA_Variable *)eb->fPtr1); return;
        case EX_YIELD_ABSOLUTE: return;
        case EX_CREATE_PICTURE: eb->fPicture = new_pic(); eb->fError = 0; return;
        case EX_DISPOSE_PICTURE: release_pic(eb->fPicture); return;
        case EX_DUPLICATE_PICTURE:
            if(eb->fParam1 == 0) live_pic(eb->fPicture)->refs++;
            else { live_pic(eb->fPicture); eb->fPicture = new_pic(); }
            return;
        case EX_GET_PICTURE_DATA:
            live_pic(eb->fPicture);
            memset(&eb->fUniString1, 0, sizeof eb->fUniString1);
            eb->fError = -1;
            return;
        case EX_CONVERT_CHARSET_TO_CHARSET: { /* returns the BYTE size written (SDK comment) */
            const char *from = (const char *)eb->fPtr1;
            PA_long32 fromSize = (PA_long32)eb->fParam1, toSize = (PA_long32)eb->fParam3, out = 0;
            if(eb->fParam2 == eVTC_UTF_8 && eb->fParam4 == eVTC_UTF_16) {
                PA_Unichar *to = (PA_Unichar *)eb->fPtr2;
                for(PA_long32 i = 0; i < fromSize && (out + 1) * (PA_long32)sizeof(PA_Unichar) <= toSize; ++i)
                    to[out++] = (unsigned char)from[i];
                eb->fParam3 = out * (PA_long32)sizeof(PA_Unichar);
            } else if(eb->fParam2 == eVTC_UTF_16 && eb->fParam4 == eVTC_UTF_8) {
                const PA_Unichar *f = (const PA_Unichar *)from;
                char *to = (char *)eb->fPtr2;
                for(PA_long32 i = 0; i < fromSize / 2 && out < toSize; ++i) to[out++] = (char)f[i];
                eb->fParam3 = out;
            } else die("unmodelled charset conversion");
            eb->fError = 0;
            return;
        }
        case EX_EXECUTE_COMMAND_BY_ID: command(eb); return;
        case EX_GET_METHOD_ID: {
            u16 name(eb->fUName);
            eb->fParam1 = (!g_known_method.empty() && name == g_known_method) ? kMethodId : 0;
            eb->fError = 0;
            return;
        }
        case EX_CALL_BY_PROCID: call_by_procid(eb); return;
        case EX_GET_PROCESS_INFO: {
            u16 name = to_u16(g_process_name);
            memset(eb->fUString, 0, sizeof eb->fUString);
            memcpy(eb->fUString, name.c_str(), name.size() * sizeof(PA_Unichar));
            eb->fParam2 = 0; eb->fParam3 = 0; eb->fError = 0;
            return;
        }
        case EX_CURRENT_PROCESS_NUMBER: eb->fParam1 = 5; return;
        case EX_NEW_PROCESS: g_new_process++; eb->fParam1 = 9; eb->fError = 0; return;
        case EX_RUN_IN_MAIN_PROCESS: ((PA_RunInMainProcessProcPtr)eb->fPtr1)(eb->fPtr2); return;
        case EX_IS_PROCESS_DYING: eb->fManyToOne = g_dying ? 1 : 0; return;
        case EX_PUT_PROCESS_TO_SLEEP: g_sleeps++; g_dying = true; eb->fError = 0; return;
        case EX_KILL_PROCESS: g_killed++; return;
        default: {
            char msg[64];
            snprintf(msg, sizeof msg, "unmodelled selector %d", (int)selector);
            die(msg);
        }
    }
}

void expect(bool ok, const char *what) {
    if(!ok) {
        fprintf(stderr, "FAIL: %s (live engine strings: %zu, handles: %zu, pictures: %zu)\n",
                what, g_strings.size(), g_handles.size(), g_pics.size());
        exit(1);
    }
}

void expect_nothing_live(const char *what) {
    expect(g_strings.empty(), what);
    expect(g_handles.empty(), what);
    expect(g_pics.empty(), what);
}

/* ---- commands through PluginMain ---- */

void run(PA_long32 cmd, void **params, sLONG_PTR *ret) {
    PluginBlock pb = { (PackagePtr)params, ret, 0 };
    PluginMain(cmd, &pb);
}

/* caller-owned text parameters, as 4D passes them */
struct Texts {
    std::vector<PA_Unistring> s;
    explicit Texts(std::initializer_list<const char *> v) {
        for(const char *c : v) { u16 u = to_u16(c); s.push_back(new_string(u.c_str(), u.size())); }
    }
    ~Texts() { for(auto &x : s) free_string(&x); }
};

void set_method(const char *name) {
    Texts t{ name };
    void *params[1] = { &t.s[0] };
    PA_long32 ret = 0;
    run(3, params, (sLONG_PTR *)&ret); /* NOTIFICATION SET METHOD */
    expect(ret == 1, "SET METHOD returned 1");
}

u16 get_method() {
    PA_Unistring ret = new_string(nullptr, 0);
    PA_Unistring *pret = &ret; /* 4D passes a pointer to a caller-owned result string */
    run(4, nullptr, (sLONG_PTR *)&pret); /* NOTIFICATION Get method */
    u16 r(ret.fString, ret.fLength);
    free_string(&ret);
    return r;
}

void deliver() {
    Texts t{ "Title", "Sub", "Body", "", "info", "", "" };
    void *params[7];
    for(int i = 0; i < 7; ++i) params[i] = &t.s[i];
    run(5, params, nullptr); /* DELIVER NOTIFICATION */
}

void listener_teardown() {
    PA_RunInMainProcess((PA_RunInMainProcessProcPtr)listener_end, nullptr);
}

void check_args(const std::vector<u16> &a) {
    expect(a.size() == 6, "six callback arguments");
    expect(a[0] == to_u16("Title") && a[1] == to_u16("Sub") && a[2] == to_u16("Body"), "title, subtitle, text delivered");
    expect(a[3] == to_u16("DeliverNotification") && a[4].empty() && a[5] == to_u16("info"), "type, activation, userInfo delivered");
}

/* ---- listener tests ---- */

/* Contract 2: eVK_Unistring owners overwritten by a shallow PA_SetStringVariable leak. */
void defect_listener_method_owner_leak() {
    g_known_method = to_u16("notify");
    set_method("notify");
    deliver();
    expect(g_center.delivered.count == 1, "synthetic delivery");
    listenerLoopExecuteMethod();
    expect(g_method_calls == 1, "method called by id");
    check_args(g_args);
    listener_teardown();
    expect_nothing_live("PA_ExecuteMethodByID parameters released");
}

/* Contract 3: the PA_ExecuteMethodByID result is owned by the caller. */
void defect_listener_method_result_leak() {
    g_known_method = to_u16("notify");
    g_method_returns_text = true;
    set_method("notify");
    deliver();
    listenerLoopExecuteMethod();
    expect(g_method_calls == 1, "method called by id");
    expect(!g_strings.count(g_last_result), "returned value released");
    listener_teardown();
}

/* Contract 2 on the EXECUTE METHOD (1007) fallback. */
void defect_listener_execute_method_owner_leak() {
    set_method("unknown_method");
    deliver();
    listenerLoopExecuteMethod();
    expect(g_1007_calls == 1 && g_method_calls == 0, "EXECUTE METHOD fallback used");
    expect(g_args.size() == 7 && g_args[0] == to_u16("unknown_method"), "method name in slot 0");
    check_args(std::vector<u16>(g_args.begin() + 1, g_args.end()));
    listener_teardown();
    expect_nothing_live("EXECUTE METHOD parameters released");
}

/* The listener process end to end: one event delivered, then the loop sleeps and ends. */
void defect_listener_loop_delivery_leak() {
    g_known_method = to_u16("notify");
    g_method_returns_text = true;
    set_method("notify");
    expect(g_new_process == 1, "listener process created");
    deliver();
    listenerLoop();
    expect(g_method_calls == 1 && g_sleeps == 1 && g_killed == 1, "loop executed, slept and ended");
    expect(get_method().empty(), "loop end clears the method");
    expect_nothing_live("listener loop leaves nothing behind");
}

/* Contract 3 gate: on error the returned slot is not the caller's. */
void control_listener_method_error_not_cleared() {
    g_known_method = to_u16("notify");
    g_method_fails = true;
    set_method("notify");
    deliver();
    listenerLoopExecuteMethod();
    expect(g_method_calls == 1, "method called by id");
    listener_teardown();
}

void control_listener_no_method() {
    PA_RunInMainProcess((PA_RunInMainProcessProcPtr)listener_start, nullptr);
    deliver();
    listenerLoopExecuteMethod();
    expect(g_method_calls == 0 && g_1007_calls == 0, "no callback without a method");
    listenerLoopExecuteMethod(); /* empty queue */
    listener_teardown();
    expect_nothing_live("nothing created without a method");
}

void control_set_get_method() {
    set_method("notify");
    expect(get_method() == to_u16("notify"), "method round-trips");
    expect(g_new_process == 1, "one listener process");
    set_method("notify");
    expect(g_new_process == 1, "listener process created once");
    listener_teardown();
    expect_nothing_live("SET/Get method leave nothing behind");
}

void control_set_method_on_exit() {
    g_process_name = "$xx";
    Texts t{ "notify" };
    void *params[1] = { &t.s[0] };
    PA_long32 ret = 7;
    run(3, params, (sLONG_PTR *)&ret);
    expect(ret == 0 && g_new_process == 0, "ignored in the exit process");
}

void control_mode() {
    PA_long32 mode = 0, ret = -1;
    void *params[1] = { &mode };
    run(2, params, nullptr); /* NOTIFICATION SET MODE(0) */
    run(1, nullptr, (sLONG_PTR *)&ret);
    expect(ret == 0, "mode 0");
    mode = 1;
    run(2, params, nullptr);
    run(1, nullptr, (sLONG_PTR *)&ret);
    expect(ret == 1, "mode 1");
    expect_nothing_live("mode commands leave nothing behind");
}

void control_schedule() {
    {
        Texts t{ "Title", "Sub", "Body", "__DEFAULT__", "info", "Open", "Close", "Asia/Tokyo" };
        PA_Date date = { 13, 11, 2026 };
        PA_long32 time = 3600;
        void *params[10];
        for(int i = 0; i < 7; ++i) params[i] = &t.s[i];
        params[7] = &date;
        params[8] = &time;
        params[9] = &t.s[7];
        run(6, params, nullptr); /* SCHEDULE NOTIFICATION */
    }
    expect(g_center.scheduled.count == 1 && g_center.delivered.count == 0, "scheduled, not delivered");
    NSUserNotification *n = g_center.scheduled[0];
    expect([n.title isEqualToString:@"Title"] && [n.actionButtonTitle isEqualToString:@"Open"], "fields set");
    expect([n.deliveryDate timeIntervalSince1970] == 1794499200.0, "2026-11-13 01:00 JST");
    expect_nothing_live("SCHEDULE leaves nothing behind");
}

/* Contract 1/2: ARRAY_TEXT fills the array via PA_SetStringInArray and must not dispose. */
void control_array_text_transfer() {
    {
        ARRAY_TEXT a;
        a.appendUTF16String((const PA_Unichar *)u"", 0);
        a.appendUTF16String((const PA_Unichar *)u"x", 1);
        a.appendUTF16String((const PA_Unichar *)u"yz", 2);
        PA_Variable arr = PA_CreateVariable(eVK_ArrayUnicode);
        void *params[1] = { &arr };
        a.toParamAtIndex((PackagePtr)params, 1);
        expect(arr.uValue.fArray.fNbElements == 2, "two elements");
        expect(g_strings.size() == 3, "array owns three strings");
        ARRAY_TEXT b;
        b.fromParamAtIndex((PackagePtr)params, 1);
        CUTF16String s; b.copyUTF16StringAtIndex(&s, 2);
        expect(s == CUTF16String((const PA_Unichar *)u"yz"), "borrowed read");
        PA_ClearVariable(&arr);
    }
    expect_nothing_live("array strings released with the array");
}

/* ---- C_PICTURE (built, unreachable from any command) ---- */

void with_picture(const std::function<void(C_PICTURE &)> &f) {
    {
        C_PICTURE pic;
        PA_Picture src = PA_CreatePicture(0, 0);
        pic.setPicture(src);
        PA_DisposePicture(src);
        expect(g_pics.size() == 1, "one picture held");
        f(pic);
    }
}

void defect_picture_fromfile_ownership() {
    {
        C_PICTURE pic;
        CUTF8String path((const uint8_t *)"/un-synthetic/does-not-exist.png");
        pic.fromFileAtPath(&path);
        expect(g_read_path == to_u16("/un-synthetic/does-not-exist.png"), "path delivered");
        expect(g_pics.size() == 1, "only the loaded picture is live");
    }
    expect_nothing_live("READ PICTURE FILE parameters and result released");
}

void defect_picture_setbytes_leak() {
    {
        C_PICTURE pic;
        const uint8_t bytes[] = { 1, 2, 3 };
        pic.setBytes(bytes, sizeof bytes);
        expect(g_pics.size() == 1, "only the held picture is live");
    }
    expect_nothing_live("picture created by setBytes released");
}

void defect_picture_createcopy_ownership() {
    with_picture([](C_PICTURE &pic) {
        PA_Picture p = pic.createCopyPNG();
        expect(g_convert_type == to_u16(".png"), "type delivered");
        expect(p == pic.getPicture(), "retained copy returned");
        PA_DisposePicture(p);
    });
    expect_nothing_live("CONVERT PICTURE parameters released");
}

void defect_picture_grayscale_owner_leak() {
    with_picture([](C_PICTURE &pic) {
        PA_Picture p = pic.createGrayScale();
        expect(g_transform_op == 101, "operator delivered");
        PA_DisposePicture(p);
    });
    expect_nothing_live("TRANSFORM PICTURE parameters released");
}

void defect_picture_getsize_owner_leak() {
    with_picture([](C_PICTURE &pic) {
        unsigned int w = 0, h = 0;
        pic.getSize(&w, &h);
        expect(w == 640 && h == 480, "size delivered");
    });
    expect_nothing_live("PICTURE PROPERTIES parameters released");
}

void defect_picture_thumbnail_owner_leak() {
    with_picture([](C_PICTURE &pic) {
        PA_Picture t = pic.createThumbnail(32, 24);
        expect(g_thumb_w == 32 && g_thumb_h == 24, "size delivered");
        expect(t && t != pic.getPicture() && g_pics.count((Pic *)t), "thumbnail handed to the caller");
        PA_DisposePicture(t);
    });
    expect_nothing_live("CREATE THUMBNAIL parameters released");
}

void control_picture_param_return() {
    PA_Picture in = PA_CreatePicture(0, 0);
    PA_Picture out = PA_CreatePicture(0, 0);
    PA_Picture ret = 0;
    {
        C_PICTURE pic;
        void *params[2] = { &in, &out };
        pic.fromParamAtIndex((PackagePtr)params, 1);
        pic.toParamAtIndex((PackagePtr)params, 2);
        pic.setReturn((sLONG_PTR *)&ret);
        expect(out == in && ret == in, "same picture retained");
    }
    PA_DisposePicture(in);
    PA_DisposePicture(out);
    PA_DisposePicture(ret);
    expect_nothing_live("all references balanced");
}

const std::map<std::string, std::function<void()>> kTests = {
    { "defect_listener_method_owner_leak", defect_listener_method_owner_leak },
    { "defect_listener_method_result_leak", defect_listener_method_result_leak },
    { "defect_listener_execute_method_owner_leak", defect_listener_execute_method_owner_leak },
    { "defect_listener_loop_delivery_leak", defect_listener_loop_delivery_leak },
    { "control_listener_method_error_not_cleared", control_listener_method_error_not_cleared },
    { "control_listener_no_method", control_listener_no_method },
    { "control_set_get_method", control_set_get_method },
    { "control_set_method_on_exit", control_set_method_on_exit },
    { "control_mode", control_mode },
    { "control_schedule", control_schedule },
    { "control_array_text_transfer", control_array_text_transfer },
    { "defect_picture_fromfile_ownership", defect_picture_fromfile_ownership },
    { "defect_picture_setbytes_leak", defect_picture_setbytes_leak },
    { "defect_picture_createcopy_ownership", defect_picture_createcopy_ownership },
    { "defect_picture_grayscale_owner_leak", defect_picture_grayscale_owner_leak },
    { "defect_picture_getsize_owner_leak", defect_picture_getsize_owner_leak },
    { "defect_picture_thumbnail_owner_leak", defect_picture_thumbnail_owner_leak },
    { "control_picture_param_return", control_picture_param_return },
};

} // namespace

int main(int argc, char **argv) {
    @autoreleasepool {
        g_center = [[FakeNotificationCenter alloc] init];
        Method m = class_getClassMethod([NSUserNotificationCenter class], @selector(defaultUserNotificationCenter));
        if(!m) die("NSUserNotificationCenter unavailable");
        method_setImplementation(m, (IMP)fake_default_center);
        if((id)[NSUserNotificationCenter defaultUserNotificationCenter] != g_center) die("real notification centre not stubbed");
        gCall4D = (Call4DProcPtr)engine;
        if(argc == 2 && std::string(argv[1]) == "--list") {
            for(auto &t : kTests) printf("%s\n", t.first.c_str());
            return 0;
        }
        if(argc != 2 || !kTests.count(argv[1])) { fprintf(stderr, "usage: %s --list | <test>\n", argv[0]); return 2; }
        kTests.at(argv[1])();
    }
    printf("PASS %s\n", argv[1]);
    return 0;
}
