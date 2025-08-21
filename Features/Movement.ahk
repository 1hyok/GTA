; === 이동 관련 변수 ===
global wRunning := false
global shiftWRunning := false
global wNumpadRunning := false

ToggleWalk() {
    global wRunning
    
    if (!IsGTAActive())
        return
    
    if (!wRunning) {
        wRunning := true
        Send("{w down}")
        ShowTooltip("걷기 시작")
    } else {
        wRunning := false
        Send("{w up}")
        ShowTooltip("걷기 중지")
    }
}

ToggleRun() {
    global shiftWRunning
    
    if (!IsGTAActive())
        return
    
    if (!shiftWRunning) {
        shiftWRunning := true
        Send("{Shift down}{w down}")
        ShowTooltip("뛰기 시작")
    }
}

StopRun() {
    global shiftWRunning
    
    if (!IsGTAActive())
        return
    
    if (shiftWRunning) {
        shiftWRunning := false
        Send("{w up}{Shift up}")
        ShowTooltip("뛰기 중지")
    }
}

ToggleWalkWithNumpad() {
    global wNumpadRunning
    
    if (!IsGTAActive())
        return
    
    if (!wNumpadRunning) {
        wNumpadRunning := true
        Send("{w down}")
        SetTimer(PressNumpad2, 4000)
        ShowTooltip("W키 + Numpad2 시작")
    } else {
        wNumpadRunning := false
        Send("{w up}")
        SetTimer(PressNumpad2, 0)
        ShowTooltip("W키 + Numpad2 중지")
    }
}

PressNumpad2() {
    global wNumpadRunning
    
    if (!wNumpadRunning || !IsGTAActive())
        return
    
    PressKey("Numpad2")
}