![version](https://img.shields.io/badge/version-17%2B-3E8B93)
![platform](https://img.shields.io/static/v1?label=platform&message=mac-intel%20|%20mac-arm&color=blue)
[![license](https://img.shields.io/github/license/miyako/4d-plugin-user-notification)](LICENSE)
![downloads](https://img.shields.io/github/downloads/miyako/4d-plugin-user-notification/total)

# 4d-plugin-user-notification

Sends macOS local user notifications (banners and alerts in Notification Center) from 4D, and calls a 4D project method back when a notification is delivered or clicked. It drives Apple's `NSUserNotificationCenter` API. Notifications are shown on behalf of the 4D application itself. All text is passed as `Text`; the plugin returns no pictures or blobs.

| Command | Returns | Purpose |
|---|---|---|
| [`NOTIFICATION Get mode`](#notification-get-mode) | `Longint` | Read whether notifications are always displayed or left to the system |
| [`NOTIFICATION SET MODE`](#notification-set-mode) | — | Choose between "always display" and "system decides" |
| [`NOTIFICATION SET METHOD`](#notification-set-method) | — | Register the callback method and start listening for events |
| [`NOTIFICATION Get method`](#notification-get-method) | `Text` | Read the registered callback method name |
| [`DELIVER NOTIFICATION`](#deliver-notification) | — | Show a notification now |
| [`SCHEDULE NOTIFICATION`](#schedule-notification) | — | Show a notification at a given date, time and time zone |

**Platforms:** macOS only (Intel and Apple Silicon), 4D v17 or later. The source is Objective-C++ and has no Windows implementation.

---

## Requirements & platform notes

- **macOS 10.8 or later.** [`DELIVER NOTIFICATION`](#deliver-notification) and [`SCHEDULE NOTIFICATION`](#schedule-notification) do nothing on earlier versions.
- **Apple has deprecated `NSUserNotification`** (since macOS 10.14) in favor of the UserNotifications framework. The source does not use the newer API. Test on every macOS version you ship to.
- **Failure is silent.** The plugin never raises a 4D error. Invalid input is ignored, replaced by a default, or produces no notification (see [Error handling & troubleshooting](#error-handling--troubleshooting)).
- **Callbacks only work after [`NOTIFICATION SET METHOD`](#notification-set-method).** Without a registered method you can still show notifications, but you receive no events, and [`NOTIFICATION SET MODE`](#notification-set-mode) has no effect (see [Display mode](#display-mode)).
- **Thread safety**, from the plugin's manifest:

| Command | Preemptive-safe |
|---|---|
| [`NOTIFICATION Get mode`](#notification-get-mode) | Yes |
| [`NOTIFICATION SET MODE`](#notification-set-mode) | Yes |
| [`NOTIFICATION SET METHOD`](#notification-set-method) | **No** — call it from a cooperative process |
| [`NOTIFICATION Get method`](#notification-get-method) | Yes |
| [`DELIVER NOTIFICATION`](#deliver-notification) | Yes |
| [`SCHEDULE NOTIFICATION`](#schedule-notification) | Yes |

- **Constants.** The samples use the 4D constants `Notification system decides`, `Notification display always` and `Notification default sound`. Their numeric/text values live in the plugin's constants resource, which was not available when this reference was written. Use the constants, not literal values. Where this document states a value, it is read from the plugin's C++ source and marked as such.
- **Revised source.** Items marked *(revised source)* describe behavior of the corrected `4DPlugin.cpp` delivered with this reference. They are true once that source is built, not necessarily of the binary you have installed.

### Display mode

macOS normally does not show a banner while the notifying application is frontmost. When a listener is registered, the plugin answers that question itself, based on the mode:

| Constant | Effect |
|---|---|
| `Notification display always` | Banner is shown even when 4D is frontmost |
| `Notification system decides` | macOS default behavior |

From the source, the stored mode starts at `1`, and any non-zero value means "display always"; `0` means "system decides". This implies `Notification display always` = `1` and `Notification system decides` = `0`, which is inferred, not confirmed against the constants file. Note that the sample `SETUP.4dm` comments `Notification system decides` as the default, whereas the source initializes the stored value to `1`. Until [`NOTIFICATION SET METHOD`](#notification-set-method) has been called, no listener exists and macOS behavior applies regardless of the stored mode. If your behavior depends on it, call [`NOTIFICATION SET MODE`](#notification-set-mode) explicitly.

---

## NOTIFICATION Get mode

### Syntax

```4d
NOTIFICATION Get mode → Longint
```

| Parameter | Type | Description |
|---|---|---|
| Result | Longint | `1` if notifications are displayed always, `0` if the system decides |

### Description

Returns the currently stored display mode (see [Display mode](#display-mode)). Takes no parameters. It reads a stored value only; it does not query macOS.

### Example

```4d
If (NOTIFICATION Get mode=Notification display always)
	// banners will appear even while 4D is frontmost
End if
```

---

## NOTIFICATION SET MODE

### Syntax

```4d
NOTIFICATION SET MODE ( mode )
```

| Parameter | Type | Description |
|---|---|---|
| `mode` | Longint | `Notification display always` or `Notification system decides` |

### Description

Stores the display mode used by the listener when macOS asks whether to present a notification. Any non-zero value is treated as "display always" *(revised source)*; earlier builds assigned the integer straight to a native `BOOL`, which truncates differently on Intel and Apple Silicon for values other than `0`/`1`. Pass the constants.

The setting only has an effect while a listener exists, so call [`NOTIFICATION SET METHOD`](#notification-set-method) too. The command is preemptive-safe.

### Example

From the plugin's own test method (`SETUP.4dm`):

```4d
NOTIFICATION SET MODE(Notification system decides)  //default
NOTIFICATION SET MODE(Notification display always)
```

---

## NOTIFICATION SET METHOD

### Syntax

```4d
NOTIFICATION SET METHOD ( method )
```

| Parameter | Type | Description |
|---|---|---|
| `method` | Text | Name of the project method to call for each notification event |

The manifest declares no result, so nothing is returned to your code.

### Description

Registers the callback method and starts listening. On the first call the plugin installs its notification delegate (on the 4D main process) and starts a hidden process named `$User Notification Listener`. Calling the command again only replaces the method name.

The callback receives six `Text` parameters; see [Callback method](#callback-method). It runs in the listener process, **not** in the process that called this command, so it must be safe to run cooperatively, and anything slow or modal inside it (such as `ALERT`) delays every following event.

When 4D quits, the listener stops and the method name is cleared. Calling this command from the exit process (`$xx`) does nothing.

Events are queued and delivered in order, one at a time. Delivery is polled, so expect up to roughly a second between a notification event and your method running.

If the method name cannot be resolved to a project method, the plugin falls back to `EXECUTE METHOD` with the same name; what 4D does when that name does not exist was not traced. An empty name discards events instead of calling anything *(revised source)*.

Call it from a cooperative process only. It is not preemptive-safe.

### Example

From the plugin's own test method (`Test.4dm`):

```4d
NOTIFICATION SET METHOD("notify")  //cooperative

CALL WORKER:C1389("SETUP"; "SETUP")  //preemptive

CALL WORKER:C1389("SEND"; "SEND")  //preemptive
```

Typical startup (for example in `On Startup`):

```4d
NOTIFICATION SET MODE(Notification display always)
NOTIFICATION SET METHOD("onNotification")
```

---

## NOTIFICATION Get method

### Syntax

```4d
NOTIFICATION Get method → Text
```

| Parameter | Type | Description |
|---|---|---|
| Result | Text | The registered method name, or an empty string if none |

### Description

Returns the name last passed to [`NOTIFICATION SET METHOD`](#notification-set-method). It is empty before registration and after 4D has shut the listener down. Preemptive-safe.

### Example

```4d
If (NOTIFICATION Get method="")
	NOTIFICATION SET METHOD("onNotification")
End if
```

---

## DELIVER NOTIFICATION

### Syntax

```4d
DELIVER NOTIFICATION ( title ; subtitle ; informativeText ; soundName ; userInfo ; actionButtonTitle ; otherButtonTitle )
```

| Parameter | Type | Description |
|---|---|---|
| `title` | Text | Notification title |
| `subtitle` | Text | Notification subtitle |
| `informativeText` | Text | Body text |
| `soundName` | Text | `""` for no sound; `Notification default sound` for the system sound; otherwise the name of a sound |
| `userInfo` | Text | Your own payload, handed back to the callback as `$6`. Must be shorter than 1000 characters, otherwise it is replaced by `""` |
| `actionButtonTitle` | Text | `""` for no action button; otherwise the button's title |
| `otherButtonTitle` | Text | Title of the "other" (dismiss) button; ignored when empty |

All seven parameters are mandatory (the manifest declares seven `Text` parameters), even if empty. The command returns nothing. Parameter names are descriptive; they come from the source and the README.

### Description

Builds a notification and hands it to Notification Center immediately.

- **Sound.** The source tests for the literal `"__DEFAULT__"`, which maps to the system default sound, so `Notification default sound` is presumably that string (inferred). Any other non-empty value is passed to macOS as a sound name, resolved by macOS, not by the plugin.
- **`userInfo`.** It is the only data that survives the round trip to your callback, so use it to identify what the notification refers to (a record ID, a JSON object). The length limit is counted in UTF-16 code units, and exceeding it silently discards the whole string.
- **Buttons.** Per Apple's documentation, action and other buttons only appear when the user has set 4D's notification style to *Alerts*; with banners, they are not shown. This was not tested here.
- **Callbacks.** Delivery triggers a `DeliverNotification` event, and a click triggers an `ActivateNotification` event, if [`NOTIFICATION SET METHOD`](#notification-set-method) has been called.

Preemptive-safe. The command does nothing on macOS earlier than 10.8.

### Example

From the plugin's own test method (`SEND.4dm`):

```4d
$title:="title"
$subtitle:="subtitle"
$informativeText:="informativeText"
$soundName:=""  //no sound
$soundName:=Notification default sound
$userInfo:=String:C10(Current date:C33; ISO date GMT:K1:10; curren time)

DELIVER NOTIFICATION(\
$title; \
$subtitle; \
$informativeText; \
$soundName; \
$userInfo; "action"; "close")
```

The shipped `SEND.4dm` contains the typo `curren time`, which should read `Current time`.

With a structured payload and no sound:

```4d
$payload:=JSON Stringify(New object("type"; "invoice"; "id"; 1042))

DELIVER NOTIFICATION("Invoice paid"; "Customer: ACME"; "Invoice 1042 was paid."; ""; $payload; ""; "")
```

---

## SCHEDULE NOTIFICATION

### Syntax

```4d
SCHEDULE NOTIFICATION ( title ; subtitle ; informativeText ; soundName ; userInfo ; actionButtonTitle ; otherButtonTitle ; deliveryDate ; deliveryTime ; timeZone )
```

| Parameter | Type | Description |
|---|---|---|
| `title` … `otherButtonTitle` | Text | Same as in [`DELIVER NOTIFICATION`](#deliver-notification), parameters 1 to 7 |
| `deliveryDate` | Date | Day on which to deliver |
| `deliveryTime` | Time | Time of day at which to deliver |
| `timeZone` | Text | Time zone name, e.g. `"Europe/Paris"`; `""` or an unknown name means the Mac's current time zone |

All ten parameters are mandatory. The command returns nothing.

### Description

Asks Notification Center to deliver the notification at `deliveryDate` + `deliveryTime`, interpreted on the Gregorian calendar in `timeZone`. The time zone is applied *(revised source)*; earlier builds computed the time zone but never used it, so the Mac's own time zone always applied.

The callback ([`NOTIFICATION SET METHOD`](#notification-set-method)) receives a `DeliverNotification` event when the notification is actually delivered, not when it is scheduled.

Not traced or tested, so verify before relying on them: what macOS does with a date in the past or with an empty (`00/00/00`) date, and how the time-of-day is derived. The plugin passes the time as a number of seconds, and the calculation relies on macOS normalizing that value. There is no command to cancel a scheduled notification or to remove a delivered one.

Preemptive-safe. Does nothing on macOS earlier than 10.8.

### Example

Tomorrow at 09:30 Paris time:

```4d
SCHEDULE NOTIFICATION("Standup"; ""; "Daily standup starts now"; Notification default sound; "standup"; ""; ""; Current date+1; ?09:30:00?; "Europe/Paris")
```

---

## Callback method

The method named in [`NOTIFICATION SET METHOD`](#notification-set-method) is called with six `Text` parameters and no result. It runs in the `$User Notification Listener` process.

| Parameter | Description |
|---|---|
| `$1` | Notification title |
| `$2` | Notification subtitle |
| `$3` | Informative text |
| `$4` | Event type: `DeliverNotification` or `ActivateNotification` |
| `$5` | Activation type (see below); empty for `DeliverNotification` |
| `$6` | The `userInfo` string you supplied (empty if none, or if it was too long) |

| `$5` value | Meaning |
|---|---|
| `ContentsClicked` | The user clicked the notification body |
| `ActionButtonClicked` | The user clicked the action button |
| `ActivationTypeNone` | Activated without a recognized user action |
| `""` | Any other activation type |

### Example

From the plugin's own test method (`notify.4dm`):

```4d
//%attributes = {"invisible":true,"preemptive":"capable"}
C_TEXT:C284($1; $2; $3; $4; $5; $6)

ALERT:C41(\
$1+"\r"+\
$2+"\r"+\
$3+"\r"+\
$4+"\r"+\
$5+"\r"+\
$6)
```

A dispatcher that branches on the event, built on the same parameters. It hands real work to a worker so the listener process stays free:

```4d
C_TEXT($1; $2; $3; $4; $5; $6)

Case of
	: ($4="DeliverNotification")
		// shown to the user

	: ($4="ActivateNotification")
		Case of
			: ($5="ActionButtonClicked")
				CALL WORKER("notifications"; "handleAction"; $6)
			: ($5="ContentsClicked")
				CALL WORKER("notifications"; "handleOpen"; $6)
			Else
				// ActivationTypeNone or another activation type
		End case
End case
```

---

## Error handling & troubleshooting

- **Nothing happens, no error.** The plugin never raises a 4D error. Check the macOS version (10.8 or later) and that notifications are allowed for the 4D application in the system notification settings.
- **No banner while 4D is frontmost.** macOS suppresses it unless a listener is registered and the mode is `Notification display always`. Call [`NOTIFICATION SET METHOD`](#notification-set-method) and [`NOTIFICATION SET MODE`](#notification-set-mode).
- **No callback.** [`NOTIFICATION SET METHOD`](#notification-set-method) was not called, was called from the exit process, or the listener was shut down. [`NOTIFICATION Get method`](#notification-get-method) returns `""` in that case. Make sure the method name is spelled exactly.
- **Callback delayed or missing events.** Events run one at a time in a single process, so a callback that blocks (`ALERT`, long queries) holds back everything behind it. Keep it short and forward work with `CALL WORKER`. Expect up to about a second of latency.
- **`$6` is empty.** The `userInfo` you passed was empty or 1000 characters or longer, and was discarded.
- **Buttons do not appear.** Action/other buttons only show for the *Alerts* notification style; this is Apple behavior and was not verified here.
- **Scheduled time is off by hours.** On builds before the revised source, the `timeZone` parameter was ignored. Rebuild from the revised source, or pass the Mac's own time zone.
- **A parameter error or compile error in the callback.** The callback must declare `$1` to `$6` as `Text`. If the method cannot be found by name, the plugin falls back to `EXECUTE METHOD`, so a wrong name may surface as a 4D error from that command.
- **`NOTIFICATION SET MODE` seems ignored.** It only takes effect once the listener exists ([`NOTIFICATION SET METHOD`](#notification-set-method)).

---

## Quick reference

```4d
// startup
NOTIFICATION SET MODE(Notification display always)
NOTIFICATION SET METHOD("onNotification")    // cooperative process only

// show now
DELIVER NOTIFICATION($title; $subtitle; $text; Notification default sound; $userInfo; "Open"; "Later")

// show later
SCHEDULE NOTIFICATION($title; $subtitle; $text; ""; $userInfo; ""; ""; Current date+1; ?09:30:00?; "Europe/Paris")

// inspect
$mode:=NOTIFICATION Get mode
$method:=NOTIFICATION Get method

// onNotification ($1 title, $2 subtitle, $3 text, $4 event, $5 activation, $6 userInfo)
```
