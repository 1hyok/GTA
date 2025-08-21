; === 이동 관련 변수 ===
global wRunning := false
global shiftWRunning := false
global wCtrlRunning := false  ; 변수명 변경

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

ToggleWalkWithCtrl() {
    global wCtrlRunning, config
    
    if (!IsGTAActive())
        return
    
    ctrlInterval := config["Settings"]["CtrlInterval"]  ; 설정값 가져오기
    
    if (!wCtrlRunning) {
        wCtrlRunning := true
        Send("{w down}")
        SetTimer(PressLCtrl, ctrlInterval)  ; 설정값 사용
        ShowTooltip("W키 + LCtrl 시작 (간격: " ctrlInterval "ms)")
    } else {
        wCtrlRunning := false
        Send("{w up}")
        SetTimer(PressLCtrl, 0)
        ShowTooltip("W키 + LCtrl 중지")
    }
}

PressLCtrl() {  ; 함수명 변경
    global wCtrlRunning
    
    if (!wCtrlRunning || !IsGTAActive())
        return
    
    PressKey("LCtrl")  ; Numpad5 → LCtrl로 변경
}