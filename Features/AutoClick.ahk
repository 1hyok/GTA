; === 자동 클릭 변수 ===
global clickRunning := false

ToggleAutoClick() {
    global clickRunning, config
    
    if (!IsGTAActive())
        return
    
    clickDelay := config["Settings"]["ClickDelay"]
    
    if (!clickRunning) {
        clickRunning := true
        ShowTooltip("자동 클릭 시작 (간격: " clickDelay "ms)")
        DoClick()
        SetTimer(DoClick, clickDelay)
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