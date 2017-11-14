4d-plugin-user-notification
===========================

Send Mac OS X Mountain Lion Local User Notification from 4D.

### Platform

| carbon | cocoa | win32 | win64 |
|:------:|:-----:|:---------:|:---------:|
|<img src="https://cloud.githubusercontent.com/assets/1725068/22371562/1b091f0a-e4db-11e6-8458-8653954a7cce.png" width="24" height="24" />|<img src="https://cloud.githubusercontent.com/assets/1725068/22371562/1b091f0a-e4db-11e6-8458-8653954a7cce.png" width="24" height="24" />|||

## Commands

```c
// --- Notification Center
NOTIFICATION_Get_mode
NOTIFICATION_SET_MODE
NOTIFICATION_SET_METHOD
NOTIFICATION_Get_method

// --- Notification
DELIVER_NOTIFICATION
SCHEDULE_NOTIFICATION
```

## Examples

```
NOTIFICATION SET METHOD ("notify")  //receives 6 text arguments

$title:="title"
$subtitle:="subtitle"
$informativeText:="informativeText"

NOTIFICATION SET MODE (Notification system decides)  //default
NOTIFICATION SET MODE (Notification dislay always)

$soundName:=""  //no sound
$soundName:=Notification default sound

DELIVER NOTIFICATION (\
$title;\
$subtitle;\
$informativeText;\
$soundName;\
$userInfo;"action";"close")
```
