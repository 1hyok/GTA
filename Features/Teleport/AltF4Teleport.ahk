; === 새로운 F4 텔레포트 (Enter-Home-Click-Enter연타) ===

; 새로운 F4 텔레포트 실행 함수
ExecuteAltF4Teleport() {
    global config, altF4Running
    
    if (!IsGTAActive() || altF4Running)
        return
    
    altF4Running := true
    
    ; 설정값들
    mouseX := 1600  ; 하드코딩된 X 좌표
    mouseY := 250   ; 첫 번째 Y 좌표
    mouseY2 := 350  ; 두 번째 Y 좌표
    clickToEnterDelay := config["Settings"]["TeleportClickToEnterDelay"]  ; 클릭 후 엔터 연타 전 딜레이
    enterDuration := config["Settings"]["TeleportEnterDuration"]  ; 엔터 연타 최대 지속시간 (ms)
    enterInterval := config["Settings"]["TeleportEnterInterval"]  ; 엔터 간격 (ms)
    
    ShowAltF4Message("🚀 새 F4 텔레포트 시작")
    
    ; 1. Enter 키 입력
    ShowAltF4Message("⏎ Enter 키 입력...", 300)
    PressKey("Enter")
    
    ; 2. Home 키 입력
    ShowAltF4Message("🏠 Home 키 입력...", 300)
    PressKey("Home")
    Sleep(6000)
    
    ; 3. 두 좌표 모두 클릭
    ShowAltF4Message("🖱️ 첫 번째 위치 클릭...", 300)
    Click(mouseX, mouseY)
    Sleep(100)
    
    ShowAltF4Message("🖱️ 두 번째 위치 클릭...", 300)
    Click(mouseX, mouseY2)
    
    ; 4. 클릭 후 대기
    ShowAltF4Message("⏳ 로딩 대기 중...", clickToEnterDelay)
    Sleep(clickToEnterDelay)
    
    ; 5. Enter 연타 (아무 키 입력시까지 또는 최대 시간)
    ShowAltF4Message("🔁 Enter 연타 중... (아무 키로 중지)", 1000)
    
    ; Enter 연타 루프 (시간 제한 포함)
    startTime := A_TickCount
    while ((A_TickCount - startTime) < enterDuration) {
        PressKey("Enter")
        Sleep(enterInterval)
        
        ; 아무 키가 눌렸는지 체크 (Enter 제외)
        if (IsAnyKeyPressed()) {
            ShowAltF4Message("✅ 키 입력으로 중지됨!", 2000)
            altF4Running := false
            return
        }
    }
    
    ShowAltF4Message("⏰ 시간 초과로 중지됨!", 2000)
    altF4Running := false
}

; 아무 키가 눌렸는지 체크하는 함수 (Enter 제외)
IsAnyKeyPressed() {
    ; 주요 키들 체크 (Enter 제외)
    keys := ["Space", "Escape", "Tab", "Shift", "Ctrl", "Alt", 
             "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
             "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
             "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
             "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"]
    
    for key in keys {
        if (GetKeyState(key, "P"))
            return true
    }
    return false
}