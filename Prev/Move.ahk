#Requires AutoHotkey v2.0

; 전역 변수
isRunning := false
isShiftWRunning := false

; 창 활성화 함수
ActivateGTA() {
   WinActivate("Grand Theft Auto V")
}

; F12로 종료
F12::ExitApp

; F8로 W키 시작/중지
F8:: {
   global isRunning
   
   if (!isRunning) {
       ; 시작 - W키 누르고 있기
       isRunning := true
       ActivateGTA()
       Send("{w down}")
   } else {
       ; 중지 - W키 떼기
       isRunning := false
       Send("{w up}")
   }
}

; F9로 Shift+W 시작/중지
F9:: {
   global isShiftWRunning
   
   if (!isShiftWRunning) {
       ; 시작 - Shift+W 누르고 있기
       isShiftWRunning := true
       ActivateGTA()
       Send("{Shift down}")
       Send("{w down}")
   } else {
       ; 중지 - Shift+W 떼기
       isShiftWRunning := false
       Send("{w up}")
       Send("{Shift up}")
   }
}