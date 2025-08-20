#Requires AutoHotkey v2.0
#Include PressKey.ahk

; 전역 변수
eToggle := false

; 창 활성화
WinActivate("Grand Theft Auto V")

; E 키 토글
e::
{
   global eToggle
   eToggle := !eToggle
   
   if (eToggle) {
       ; E 연타 시작
       SetTimer(PressEKey, 50)  ; 50ms 간격으로 E 연타
   } else {
       ; E 연타 중지
       SetTimer(PressEKey, 0)
   }
}

; E 키를 누르는 함수
PressEKey() {
   PressKey("e")
}

; 종료 단축키
F9::ExitApp