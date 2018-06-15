4d-plugin-user-notification
===========================

Send Mac OS X Mountain Lion Local User Notification from 4D.

### Platform

| carbon | cocoa | win32 | win64 |
|:------:|:-----:|:---------:|:---------:|
|<img src="https://cloud.githubusercontent.com/assets/1725068/22371562/1b091f0a-e4db-11e6-8458-8653954a7cce.png" width="24" height="24" />|<img src="https://cloud.githubusercontent.com/assets/1725068/22371562/1b091f0a-e4db-11e6-8458-8653954a7cce.png" width="24" height="24" />|||

### Releases

[1.3](https://github.com/miyako/4d-plugin-user-notification/releases/tag/1.3)

![preemption xx](https://user-images.githubusercontent.com/1725068/41327179-4e839948-6efd-11e8-982b-a670d511e04f.png)

[1.2](https://github.com/miyako/4d-plugin-user-notification/releases/tag/1.2)

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
