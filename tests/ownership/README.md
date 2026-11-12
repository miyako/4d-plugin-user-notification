# Ownership regressions

`engine_harness.mm` links the real `4DPlugin.cpp`, the plugin classes and the unchanged bundled `4D Plugin API` with ASan/UBSan. It also replaces the 4D engine (`Call4D`) with a synthetic one. That engine counts live engine strings, handles and reference-counted pictures, and aborts on anything it does not model.

No real notification is posted and no authorization is requested: `+[NSUserNotificationCenter defaultUserNotificationCenter]` is replaced by a fake centre that records notifications and calls the plugin's delegate synchronously.

```sh
tests/ownership/run.sh . fixed                # every test must pass

B=$(mktemp -d); git archive <base-sha> | tar -x -C "$B"
tests/ownership/run.sh "$B" baseline          # named defects must fail, controls pass
```

| Test | Checks |
|---|---|
| `defect_listener_method_owner_leak` | the `PA_ExecuteMethodByID` arguments do not leak empty `eVK_Unistring` owners |
| `defect_listener_method_result_leak` | the value returned by the listener method is released |
| `defect_listener_execute_method_owner_leak` | the `EXECUTE METHOD` (1007) fallback arguments do not leak empty owners |
| `defect_listener_loop_delivery_leak` | `listenerLoop` end to end: deliver, call, sleep, end |
| `defect_picture_*` | `C_PICTURE` ownership (same tests as miyako/4d-plugin-lha) |
| `control_listener_method_error_not_cleared` | the returned value is not cleared when the call fails |
| `control_*` | no-method delivery, `SET`/`Get method`, exit process, mode, `SCHEDULE NOTIFICATION`, `ARRAY_TEXT` transfer, picture parameter/return |

`C_PICTURE` is compiled into the plugin, but no command calls it.

Not covered:
- Windows and a real 4D runtime.
- `CALLBACK_IN_NEW_PROCESS` (compiled out).
