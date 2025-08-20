#Requires AutoHotkey v2.0
#SingleInstance Force
#Include PressKey.ahk

macroRunning := false
keyPressed := ""  ; 어떤 키가 눌렸는지 저장

F4:: {
    global macroRunning, keyPressed
    
    macroRunning := !macroRunning
    keyPressed := "F4"
    
    if (macroRunning) {
        WinActivate("Grand Theft Auto V")
        RunMacro()
    }
}

F5:: {
    global macroRunning, keyPressed
    
    macroRunning := !macroRunning
    keyPressed := "F5"
    
    if (macroRunning) {
        WinActivate("Grand Theft Auto V")
        RunMacro()
    }
}

F9:: {
    global macroRunning
    macroRunning := false
    ExitApp()
}

RunMacro() {
    global macroRunning, keyPressed
    
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
    Sleep(1000)
    PressKey("m")
    
    ; F4면 Down 1번, F5면 Down 2번
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