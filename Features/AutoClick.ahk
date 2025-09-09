; === 자동 클릭 변수 ===
global clickRunning := false

ToggleAutoClick() {
    global clickRunning, config
    
    if (!IsGTAActive())
        return
    
    clickInterval := config["Settings"]["ClickInterval"]
    
    if (!clickRunning) {
        clickRunning := true
        ShowTooltip("자동 클릭 시작 (간격: " clickInterval "ms)")
        DoClick()
        SetTimer(DoClick, clickInterval)
    } else {
        clickRunning := false
        ShowTooltip("자동 클릭 중지")
        SetTimer(DoClick, 0)
    }
}

DoClick() {
    if (IsGTAActive()) {
        ClickMouse("Left", 1)
    }
}