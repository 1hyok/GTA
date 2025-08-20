#Requires AutoHotkey v2.0
#SingleInstance Force

macroRunning := false

F4:: {
    global macroRunning
    
    macroRunning := !macroRunning
    
    if (macroRunning) {
        WinActivate("Grand Theft Auto V")
        Sleep(1000)
        RunMacro()
    }
}

Esc:: {
    global macroRunning
    macroRunning := false
    ExitApp()
}

; 키 누르기 함수
PressKey(key, count := 1) {
    ; 딜레이 설정 (ms)
    keyHoldTime := 25    ; 키 누르고 있는 시간
    betweenDelay := 100   ; 키 사이 간격
    
    Loop count {
        Send("{" key " down}")
        Sleep(keyHoldTime)
        Send("{" key " up}")
        if (A_Index < count) ; 마지막이 아니면 딜레이
            Sleep(betweenDelay)
    }
    Sleep(betweenDelay)
}

RunMacro() {
    global macroRunning
    
    if (!macroRunning)
        return
    
    ;모사 해체
    PressKey("m")
    PressKey("Enter")
    PressKey("Up")
    PressKey("Enter")

    ;휴대폰 빠참
    PressKey("Up")
    Sleep(500)
    PressKey("Right", 2)
    PressKey("Enter")
    PressKey("Up")
    PressKey("Enter", 3)
    
    ;모사 설립
    Sleep(500)
    PressKey("m")
    PressKey("Down", 2)
    PressKey("Enter")
    PressKey("Down")
    PressKey("Enter", 2)
    
    macroRunning := false
}