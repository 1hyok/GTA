; === 텔레포트 관련 변수 ===
global mocaRunning := false
global keyPressed := ""  ; 변수 선언 추가

; 함수명 수정 및 매개변수 추가
TeleportMoca(key) {
    global mocaRunning, keyPressed, config
    
    if (mocaRunning || !IsGTAActive())
        return
    
    mocaRunning := true
    keyPressed := key  ; 매개변수 값 할당
    
    phoneOpenDelay := config["Settings"]["PhoneOpenDelay"]
    phoneNavDelay := config["Settings"]["PhoneNavigationDelay"]
    menuDelay := config["Settings"]["InteractionMenuDelay"]
    phoneToMenuDelay := config["Settings"]["PhoneToMenuDelay"]
    
    PressKey("m") ;상호 작용 메뉴 열기
    Sleep(menuDelay)
    PressKey("Enter") ; 모터사이클 클럽 두목 선택
    Sleep(menuDelay)
    PressKey("Up") ; 해체 포커스
    Sleep(menuDelay)
    PressKey("Enter") ; 해체 선택
    Sleep(menuDelay)

    PressKey("Up") ;휴대폰 열기
    Sleep(phoneOpenDelay)
    PressKey("Right", 2, phoneNavDelay) ; 빠른 참가로 포커스
    Sleep(phoneNavDelay)
    PressKey("Enter") ; 빠른 참가 선택
    Sleep(phoneNavDelay)
    PressKey("Up") ; 랜덤 포커스
    Sleep(phoneNavDelay)
    PressKey("Enter", 3, phoneNavDelay) ; 랜덤 - 세션 - 확실합니까?에 대한 확인 각각 선택
    Sleep(phoneNavDelay)
    
    Sleep(phoneToMenuDelay)
    PressKey("m")
    Sleep(menuDelay)
    
    ;보스 등록 포커스
    if (keyPressed = "F4") {
        PressKey("Down", 1, menuDelay)
        Sleep(menuDelay)
    } else if (keyPressed = "F5") {
        PressKey("Down", 2, menuDelay)
        Sleep(menuDelay)
    }
    
    PressKey("Enter") ; 보스 등록 선택
    Sleep(menuDelay)
    PressKey("Down") ; 모터 사이클 클럽 두목 포커스
    Sleep(menuDelay)
    PressKey("Enter", 2, menuDelay) ; 모터사이클 클럽 두목 - 모터사이클 클럽 설립 각각 선택
    
    mocaRunning := false
}

; Alt+F4 텔레포트 함수도 추가해야 합니다
TeleportAltF4() {
    ; Alt+F4 텔레포트 기능 구현
    ShowTooltip("Alt+F4 텔레포트 실행")
}