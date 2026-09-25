; === 자동 클릭 변수 ===
global clickRunning := false

ToggleAutoClick() {
    global clickRunning, config

    if (!IsGTAActive())
        return

    clickInterval := config["Settings"]["ClickInterval"]

    if (!clickRunning) {
        clickRunning := true
        ShowTooltip("자동 클릭 시작 (간격: " clickInterval "ms) - 아무 키로 중지")
        DoClick()
        SetTimer(DoClick, clickInterval)
    } else {
        clickRunning := false
        ShowTooltip("자동 클릭 중지")
        SetTimer(DoClick, 0)
    }
}

DoClick() {
    global config

    if (!clickRunning || !IsGTAActive()) {
        StopAutoClick()
        return
    }

    ; 자동 클릭 토글 키 자체는 제외하고 체크 (쉼표로 여러 키를 뒀으면 전부)
    if (IsAnyKeyPressed(StrSplit(config["Hotkeys"].Get("AutoClick", ""), ",", " `t"))) {
        StopAutoClick()
        ShowTooltip("키 입력으로 자동 클릭 중지", 1500)
        return
    }

    ClickMouse("Left", 1)
}

; 자동 클릭 중지 함수
StopAutoClick() {
    global clickRunning
    if (clickRunning) {
        clickRunning := false
        SetTimer(DoClick, 0)
    }
}
