//%attributes = {"invisible":true,"preemptive":"capable"}
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