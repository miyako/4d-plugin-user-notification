![version](https://img.shields.io/badge/version-18%2B-EB8E5F)
![platform](https://img.shields.io/static/v1?label=platform&message=mac-intel%20|%20mac-arm&color=blue)
[![license](https://img.shields.io/github/license/miyako/4d-plugin-user-notification)](LICENSE)
![downloads](https://img.shields.io/github/downloads/miyako/4d-plugin-user-notification/total)

**Note**: for v17 and earlier, move `manifest.json` to `Contents`

4d-plugin-user-notification
===========================

Send Mac OS X Mountain Lion Local User Notification from 4D.

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
