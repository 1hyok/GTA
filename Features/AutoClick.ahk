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
    global clickRunning
    
    if (!IsGTAActive() || !clickRunning) {
        StopAutoClick()
        return
    }
    
    ; 아무 키가 눌렸는지 체크
    if (IsAnyKeyPressed()) {
        StopAutoClick()
        ShowTooltip("키 입력으로 자동 클릭 중지")
        return
    }
    
    ClickMouse("Left", 1)
}

; 자동 클릭 중지 함수
StopAutoClick() {
    global clickRunning
    clickRunning := false
    SetTimer(DoClick, 0)
}

; 아무 키가 눌렸는지 체크하는 함수
IsAnyKeyPressed() {
    ; 주요 키들 체크
    keys := ["Space", "Escape", "Tab", "Shift", "Ctrl", "Alt", 
             "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
             "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
             "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
             "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
             "Up", "Down", "Left", "Right", "Enter", "Backspace", "Delete", "Home", "End",
             "PgUp", "PgDn", "Insert"]
    
    for key in keys {
        if (GetKeyState(key, "P"))
            return true
    }
    return false
}