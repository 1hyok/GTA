; === 텔레포트 관련 변수 ===
global mocaRunning := false
global keyPressed := ""
global altF4Running := false  ; 이 변수가 없거나 잘못된 위치에 있는 것 같습니다
global altF4StartTime := 0

; 함수명 수정 및 매개변수 추가
TeleportMoca(key) {
    global mocaRunning, keyPressed, config
    
    if (mocaRunning || !IsGTAActive())
        return
    
    mocaRunning := true
    keyPressed := key
    
    phoneOpenDelay := config["Settings"]["PhoneOpenDelay"]
    phoneNavDelay := config["Settings"]["PhoneNavigationDelay"]
    interactionMenuOpenDelay := config["Settings"]["InteractionMenuOpenDelay"]
    menuDelay := config["Settings"]["InteractionMenuDelay"]
    phoneToMenuDelay := config["Settings"]["PhoneToMenuDelay"]
    
    PressKey("m") ; 상호작용 메뉴 열기
    Sleep(interactionMenuOpenDelay)
    PressKey("Enter") ; 모터사이클 클럽 두목 선택
    Sleep(menuDelay)
    PressKey("Up") ; 해체 포커스
    Sleep(menuDelay)
    PressKey("Enter") ; 해체 선택
    Sleep(menuDelay)

    PressKey("Up") ; 휴대폰 열기
    Sleep(phoneOpenDelay)
    PressKey("Right", 2, phoneNavDelay) ; 빠른 참가로 포커스
    Sleep(phoneNavDelay)
    PressKey("Enter") ; 빠른 참가 선택
    Sleep(phoneNavDelay)
    PressKey("Up") ; 랜덤 포커스
    Sleep(phoneNavDelay)
    PressKey("Enter", 3, phoneNavDelay) ; 랜덤 - 세션 - 확실합니까?에 대한 확인
    
    Sleep(phoneToMenuDelay)
    PressKey("m")
    Sleep(interactionMenuOpenDelay)
    
    ; Config.ini의 실제 키 값과 비교하도록 수정
    if (keyPressed = config["Hotkeys"]["TeleportMoca1"]) {  ; F4 → F1
        PressKey("Down", 1, menuDelay)
        Sleep(menuDelay)
    } else if (keyPressed = config["Hotkeys"]["TeleportMoca2"]) {  ; F5 → F2
        PressKey("Down", 2, menuDelay)
        Sleep(menuDelay)
    }
    
    PressKey("Enter") ; 보스 등록 선택
    Sleep(menuDelay)
    PressKey("Down") ; 모터 사이클 클럽 두목 포커스
    Sleep(menuDelay)
    PressKey("Enter", 2, menuDelay) ; 모터사이클 클럽 두목 - 모터사이클 클럽 설립
    
    mocaRunning := false
}

; Alt+F4 텔레포트 함수
TeleportAltF4() {
    global config, altF4Running, altF4StartTime
    
    if (!IsGTAActive())
        return
    
    if (altF4Running)
        return
    
    altF4Running := true
    teleportWaitTime := config["Settings"]["TeleportWaitTime"]
    timerInterval := config["Settings"]["TeleportTimerInterval"]
    keyHoldTime := config["Settings"]["KeyHoldTime"]
    
    ShowTooltip("Alt+F4 텔레포트 시작")
    
    ; Enter 키 먼저
    PressKey("Enter")
    Sleep(100)
    
    ; Alt+F4 조합키 직접 처리
    Send("{Alt down}{F4 down}")
    Sleep(keyHoldTime)
    Send("{F4 up}{Alt up}")
    
    ; 진행 상황 타이머 시작
    altF4StartTime := A_TickCount
    SetTimer(ShowAltF4Progress, timerInterval)
    
    ; 대기
    Sleep(teleportWaitTime)
    
    ; 타이머 중지
    SetTimer(ShowAltF4Progress, 0)
    ToolTip("")
    
    ; ESC 키
    PressKey("Escape")
    
    ShowTooltip("Alt+F4 텔레포트 완료", 2000)
    altF4Running := false
}

; Alt+F4 텔레포트 진행 상황 표시
ShowAltF4Progress() {
    global config, altF4StartTime, altF4Running
    
    if (!altF4Running) {
        SetTimer(ShowAltF4Progress, 0)
        return
    }
    
    teleportWaitTime := config["Settings"]["TeleportWaitTime"]
    elapsed := A_TickCount - altF4StartTime
    remaining := (teleportWaitTime - elapsed) / 1000
    
    if (remaining <= 0) {
        SetTimer(ShowAltF4Progress, 0)
        return
    }
    
    remainingSec := Round(remaining, 1)
    progressBar := ""
    
    progressPercent := (elapsed / teleportWaitTime) * 100
    barLength := 20
    filledLength := Round(progressPercent / 100 * barLength)
    
    Loop filledLength
        progressBar .= "█"
    Loop (barLength - filledLength)
        progressBar .= "░"
    
    ToolTip("Alt+F4 텔레포트 진행중`n" . progressBar . "`n남은 시간: " . remainingSec . "초", 10, 10)
}