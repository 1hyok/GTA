; === 공통 함수 ===
IsGTAActive() {
    return WinActive("Grand Theft Auto V")
}

ShowTooltip(text, duration := 1000) {
    ; 상태 메시지가 게임 왼쪽 위의 단계 안내와 이미지 검색을 가리지 않게 한다.
    CoordMode("ToolTip", "Screen")
    if (hwnd := IsGTAActive()) {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        ToolTip(text, cx + 20, cy + Max(260, ch - 100))
    } else {
        ToolTip(text, 20, A_ScreenHeight - 100)
    }
    SetTimer(() => ToolTip(), -duration)
}

; 아무 키가 눌렸는지 체크하는 함수 (특정 키 제외)
IsAnyKeyPressed(excludeKeys := []) {
    ; 주요 키들 체크
    keys := ["Space", "Escape", "Tab", "Shift", "Ctrl", "Alt", 
             "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
             "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
             "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
             "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
             "Enter", "BackSpace", "Delete", "Home", "End", "PgUp", "PgDn",
             "Up", "Down", "Left", "Right"]
    
    for key in keys {
        ; 제외할 키 목록에 있는지 체크
        skip := false
        for excludeKey in excludeKeys {
            if (key = excludeKey) {
                skip := true
                break
            }
        }
        
        if (!skip && GetKeyState(key, "P"))
            return true
    }
    return false
}

; 모든 기능 종료
ExitAll() {
    ; 키 해제
    try {
        Send("{w up}")
        Send("{Shift up}")
    }
    
    ToolTip("")
    ExitApp()
}
