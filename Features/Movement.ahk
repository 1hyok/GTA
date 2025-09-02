; === 이동 관련 변수 ===
global wRunning := false
global shiftWRunning := false
global vellumDrivingRunning := false  ; 변수명도 변경

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

ToggleVellumDriving() {  ; 함수명 변경
    global vellumDrivingRunning, config  ; 변수명도 변경
    
    if (!IsGTAActive())
        return
    
    vellumCtrlInterval := config["Settings"]["VellumDrivingCtrlInterval"]
    
    if (!vellumDrivingRunning) {
        vellumDrivingRunning := true
        Send("{w down}")
        SetTimer(PressLCtrlForVellum, vellumCtrlInterval)  ; 함수명도 변경
        ShowTooltip("🛩️ 벨럼 운전 모드 시작 (LCtrl 간격: " vellumCtrlInterval "ms)")
    } else {
        vellumDrivingRunning := false
        Send("{w up}")
        SetTimer(PressLCtrlForVellum, 0)
        ShowTooltip("🛩️ 벨럼 운전 모드 중지")
    }
}

PressLCtrlForVellum() {  ; 함수명 변경
    global vellumDrivingRunning
    
    if (!vellumDrivingRunning || !IsGTAActive())
        return
    
    PressKey("LCtrl")
}