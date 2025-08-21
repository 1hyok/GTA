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
    } else {
        shiftWRunning := false
        Send("{w up}{Shift up}")
        ShowTooltip("뛰기 중지")
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
        SetTimer(PressNumpad5, 4000)
        ShowTooltip("W키 + Numpad5 시작")
    } else {
        wNumpadRunning := false
        Send("{w up}")
        SetTimer(PressNumpad5, 0)
        ShowTooltip("W키 + Numpad5 중지")
    }
}

PressNumpad5() {
    global wNumpadRunning
    
    if (!wNumpadRunning || !IsGTAActive())
        return
    
    PressKey("Numpad5")
}