; === 텔레포트 변수 ===
global teleportRunning := false
global teleportPaused := false
global teleportStep := 0
global waitCounter := 0
global mocaRunning := false
global keyPressed := ""

; Alt+F4 방식 텔레포트
TeleportAltF4() {
    global teleportRunning, teleportPaused, teleportStep, waitCounter
    
    if (!IsGTAActive())
        return
    
    if (!teleportRunning) {
        teleportRunning := true
        teleportPaused := false
        teleportStep := 1
        waitCounter := 0
        SetTimer(TeleportScript, 100)
    }
    else if (!teleportPaused) {
        teleportPaused := true
        ToolTip("텔레포트 일시정지", 0, 30)
    }
    else {
        teleportPaused := false
        teleportStep := 1
        waitCounter := 0
        ToolTip("")
    }
}

TeleportScript() {
    global teleportRunning, teleportPaused, teleportStep, waitCounter
    
    if (!teleportRunning || !IsGTAActive()) {
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

; 모사 방식 텔레포트
TeleportMoca(key) {
    global mocaRunning, keyPressed
    
    if (!IsGTAActive())
        return
    
    mocaRunning := !mocaRunning
    keyPressed := key
    
    if (mocaRunning) {
        MocaTeleport()
    }
}

MocaTeleport() {
    global mocaRunning, keyPressed
    
    if (!mocaRunning || !IsGTAActive())
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
    
    mocaRunning := false
}