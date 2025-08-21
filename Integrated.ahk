#Requires AutoHotkey v2.0
#SingleInstance Force
#Include PressKey.ahk
#Include ClickMouse.ahk

; ================================
; GTA Online 통합 매크로 스크립트
; ================================
; F4/F5: 텔레포트 (모사 해체 → 휴대폰 빠참 → 모사 설립)
; F6: 텔레포트 (Enter → Alt+F4 → 35초 대기 → ESC)
; F7: 자동 클릭
; F8: W키 홀드 (이동)
; F9: Shift+W 홀드 (빠른 이동)
; F12: 종료
; ================================

; === 전역 변수 ===
; 키 홀드
wRunning := false
shiftWRunning := false

; 텔레포트 F6 (Alt+F4 방식)
teleportRunning := false
teleportPaused := false
teleportStep := 0
waitCounter := 0

; 텔레포트 F4/F5 (모사 방식)
mocaRunning := false
keyPressed := ""

; 자동 클릭
clickRunning := false
CLICK_DELAY := 1

; === 키 홀드 (수정) ===
F8:: {
    global wRunning
    
    if (!wRunning) {
        wRunning := true
        WinActivate("Grand Theft Auto V")
        Send("{w down}")
        ToolTip("걷기 시작", 0, 0)
        SetTimer(HideToolTip, 1000)
    } else {
        wRunning := false
        Send("{w up}")
        ToolTip("걷기 중지", 0, 0)
        SetTimer(HideToolTip, 1000)
    }
}

F9:: {
   global shiftWRunning
   
   if (!shiftWRunning) {
       shiftWRunning := true
       WinActivate("Grand Theft Auto V")
       Send("{Shift down}{w down}")
       ToolTip("뛰기 시작", 0, 0)
       SetTimer(HideToolTip, 1000)
   }
}

+F9:: {
   global shiftWRunning
   
   if (shiftWRunning) {
       shiftWRunning := false
       Send("{w up}{Shift up}")
       ToolTip("뛰기 중지", 0, 0)
       SetTimer(HideToolTip, 1000)
   }
}

; === 텔레포트 (Alt+F4 방식) ===
F6:: {
   global teleportRunning, teleportPaused, teleportStep, waitCounter
   
   if (!teleportRunning) {
       ; 텔레포트 시작
       WinActivate("Grand Theft Auto V")
       teleportRunning := true
       teleportPaused := false
       teleportStep := 1
       waitCounter := 0
       SetTimer(TeleportScript, 100)
   }
   else if (!teleportPaused) {
       ; 일시정지
       teleportPaused := true
       ToolTip("텔레포트 일시정지", 0, 30)
   }
   else {
       ; 재개 (처음부터)
       WinActivate("Grand Theft Auto V")
       teleportPaused := false
       teleportStep := 1
       waitCounter := 0
       ToolTip("")
   }
}

; === 텔레포트 (모사 방식) ===
F4:: {
   global mocaRunning, keyPressed
   
   mocaRunning := !mocaRunning
   keyPressed := "F4"
   
   if (mocaRunning) {
       WinActivate("Grand Theft Auto V")
       MocaTeleport()
   }
}

F5:: {
   global mocaRunning, keyPressed
   
   mocaRunning := !mocaRunning
   keyPressed := "F5"
   
   if (mocaRunning) {
       WinActivate("Grand Theft Auto V")
       MocaTeleport()
   }
}

; === 자동 클릭 ===
F7:: {
   global clickRunning, CLICK_DELAY
   WinActivate("Grand Theft Auto V")
   
   if (!clickRunning) {
       clickRunning := true
       ToolTip("자동 클릭 시작 (간격: " CLICK_DELAY "ms)", 0, 0)
       SetTimer(HideToolTip, 1000)
       DoClick()
       SetTimer(DoClick, CLICK_DELAY)
   } else {
       clickRunning := false
       ToolTip("자동 클릭 중지", 0, 0)
       SetTimer(HideToolTip, 1000)
       SetTimer(DoClick, 0)
   }
}

; === 종료 ===
F12:: {
   global teleportRunning, mocaRunning, clickRunning, wRunning, shiftWRunning
   
   ; 모든 스크립트 중지
   teleportRunning := false
   mocaRunning := false
   clickRunning := false
   
   ; 키 홀드 해제
   if (wRunning) {
       Send("{w up}")
       wRunning := false
   }
   if (shiftWRunning) {
       Send("{w up}")
       Send("{Shift up}")
       shiftWRunning := false
   }
   
   ; 모든 타이머 중지
   SetTimer(TeleportScript, 0)
   SetTimer(DoClick, 0)
   SetTimer(HideToolTip, 0)
   
   ToolTip("")
   ExitApp()
}

; === 함수들 ===
TeleportScript() {
   global teleportRunning, teleportPaused, teleportStep, waitCounter
   
   if (!teleportRunning) {
       SetTimer(TeleportScript, 0)
       ToolTip("")
       return
   }
   
   if (teleportPaused)
       return
   
   if (teleportStep = 3) {
       seconds := Round(waitCounter / 10, 1)
       remaining := 35 - seconds
       ToolTip("텔레포트 대기 중: " seconds " / 35초`n남은 시간: " remaining "초", A_ScreenWidth//2 - 100, A_ScreenHeight//2)
   } else if (teleportStep != 5) {
       ToolTip("텔레포트 Step: " teleportStep, 0, 0)
   }
   
   switch teleportStep {
       case 1:
           PressKey("Enter")
           teleportStep++
           
       case 2:
           Send("{Alt down}")
           Sleep(25)
           PressKey("F4")
           Send("{Alt up}")
           teleportStep++
           waitCounter := 0
           
       case 3:
           waitCounter++
           if (waitCounter >= 350) {
               teleportStep++
               ToolTip("")
           }
           
       case 4:
           PressKey("Esc")
           teleportStep++
           
       case 5:
           teleportRunning := false
           teleportPaused := false
           teleportStep := 0
           waitCounter := 0
           SetTimer(TeleportScript, 0)
           ToolTip("")
   }
}

MocaTeleport() {
   global mocaRunning, keyPressed
   
   if (!mocaRunning)
       return
   
   ; 모사 해체
   PressKey("m")
   PressKey("Enter")
   PressKey("Up")
   PressKey("Enter")

   ; 휴대폰 빠참
   PressKey("Up")
   Sleep(500)
   PressKey("Right", 2)
   PressKey("Enter")
   PressKey("Up")
   PressKey("Enter", 3)
   
   ; 모사 설립 (F4는 Down 1번, F5는 Down 2번)
   Sleep(1000)
   PressKey("m")
   
   if (keyPressed = "F4") {
       PressKey("Down", 1)
   } else if (keyPressed = "F5") {
       PressKey("Down", 2)
   }
   
   PressKey("Enter")
   PressKey("Down")
   PressKey("Enter", 2)
   
   mocaRunning := false
}

DoClick() {
   ClickMouse("Left", 1)
}

HideToolTip() {
   ToolTip()
   SetTimer(HideToolTip, 0)
}