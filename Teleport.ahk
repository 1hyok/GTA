#Requires AutoHotkey v2.0
#SingleInstance Force
#Include PressKey.ahk

; 전역 변수 - 첫 번째 스크립트
isRunning := false
isPaused := false
scriptStep := 0
waitCounter := 0

; 전역 변수 - 두 번째 스크립트
macroRunning := false
keyPressed := ""

; F6: 첫 번째 스크립트 시작/일시정지/재개
F6:: {
   global isRunning, isPaused, scriptStep, waitCounter
   
   if (!isRunning) {
       ; 시작
       WinActivate("Grand Theft Auto V")
       isRunning := true
       isPaused := false
       scriptStep := 1
       waitCounter := 0
       SetTimer(RunScript, 100)
   }
   else if (!isPaused) {
       ; 일시정지
       isPaused := true
       ToolTip("일시정지됨", 0, 30)
   }
   else {
       ; 재개 (처음부터)
       WinActivate("Grand Theft Auto V")
       isPaused := false
       scriptStep := 1
       waitCounter := 0
       ToolTip("")
   }
}

; F4: 두 번째 스크립트 (Down 1번)
F4:: {
   global macroRunning, keyPressed
   
   macroRunning := !macroRunning
   keyPressed := "F4"
   
   if (macroRunning) {
       WinActivate("Grand Theft Auto V")
       RunMacro()
   }
}

; F5: 두 번째 스크립트 (Down 2번)
F5:: {
   global macroRunning, keyPressed
   
   macroRunning := !macroRunning
   keyPressed := "F5"
   
   if (macroRunning) {
       WinActivate("Grand Theft Auto V")
       RunMacro()
   }
}

; F12: 종료
F12:: {
   global isRunning, macroRunning
   isRunning := false
   macroRunning := false
   SetTimer(RunScript, 0)
   ToolTip("")
   ExitApp()
}

; 첫 번째 스크립트 함수
RunScript() {
   global isRunning, isPaused, scriptStep, waitCounter
   
   if (!isRunning) {
       SetTimer(RunScript, 0)
       ToolTip("")
       return
   }
   
   if (isPaused)
       return
   
   if (scriptStep = 3) {
       seconds := Round(waitCounter / 10, 1)
       remaining := 35 - seconds
       ToolTip("대기 중: " seconds " / 35초`n남은 시간: " remaining "초", A_ScreenWidth//2 - 100, A_ScreenHeight//2)
   } else if (scriptStep != 5) {
       ToolTip("Step: " scriptStep, 0, 0)
   }
   
   switch scriptStep {
       case 1:
           PressKey("Enter")
           scriptStep++
           
       case 2:
           Send("{Alt down}")
           Sleep(25)
           PressKey("F4")
           Send("{Alt up}")
           scriptStep++
           waitCounter := 0
           
       case 3:
           waitCounter++
           if (waitCounter >= 350) {
               scriptStep++
               ToolTip("")
           }
           
       case 4:
           PressKey("Esc")
           scriptStep++
           
       case 5:
           isRunning := false
           isPaused := false
           scriptStep := 0
           waitCounter := 0
           SetTimer(RunScript, 0)
           ToolTip("")
   }
}

; 두 번째 스크립트 함수
RunMacro() {
   global macroRunning, keyPressed
   
   if (!macroRunning)
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
   
   ; 모사 설립
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
   
   macroRunning := false
}