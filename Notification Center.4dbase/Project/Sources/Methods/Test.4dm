//%attributes = {}
NOTIFICATION SET METHOD("notify")  //cooperative

CALL WORKER:C1389("SETUP"; "SETUP")  //preemptive

CALL WORKER:C1389("SEND"; "SEND")  //preemptive
