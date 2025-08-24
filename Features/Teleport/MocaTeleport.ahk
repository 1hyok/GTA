; 모카 텔레포트 실행 함수
ExecuteMocaTeleport(key) {
    global mocaRunning, keyPressed, config
    
    if (mocaRunning || !IsGTAActive())
        return
    
    mocaRunning := true
    keyPressed := key
    
    ; 설정값 로드
    phoneOpenDelay := config["Settings"]["PhoneOpenDelay"]
    phoneNavDelay := config["Settings"]["PhoneNavigationDelay"]
    interactionMenuOpenDelay := config["Settings"]["InteractionMenuOpenDelay"]
    menuDelay := config["Settings"]["InteractionMenuDelay"]
    disbandToPhoneDelay := config["Settings"]["DisbandToPhoneDelay"]
    phoneToMenuDelay := config["Settings"]["PhoneToMenuDelay"]
    
    ; 단계 1: 클럽 해체
    ExecuteDisbandSequence(interactionMenuOpenDelay, menuDelay)
    
    ; 단계 2: 세션 이동
    ExecuteSessionChangeSequence(disbandToPhoneDelay, phoneOpenDelay, phoneNavDelay)
    
    ; 단계 3: 보스 등록
    ExecuteBossRegistrationSequence(phoneToMenuDelay, interactionMenuOpenDelay, menuDelay, key)
    
    ShowMocaMessage("🎉 모카 텔레포트 완료!", 2000)
    mocaRunning := false
}

; 클럽 해체 시퀀스
ExecuteDisbandSequence(interactionMenuOpenDelay, menuDelay) {
    ShowMocaMessage("📱 모카 텔레포트 시작", 1500)
    
    ShowMocaMessage("📋 상호작용 메뉴 열기...", 800)
    PressKey("m")
    Sleep(interactionMenuOpenDelay)
    
    ShowMocaMessage("🏍️ 모터사이클 클럽 두목 선택...", 500)
    PressKey("Enter")
    Sleep(menuDelay)
    
    ShowMocaMessage("⬆️ 해체 포커스...", 300)
    PressKey("Up")
    Sleep(menuDelay)
    
    ShowMocaMessage("💥 클럽 해체 중...", 800)
    PressKey("Enter")
    Sleep(menuDelay)
}

; 세션 변경 시퀀스
ExecuteSessionChangeSequence(disbandToPhoneDelay, phoneOpenDelay, phoneNavDelay) {
    ShowMocaMessage("⏳ 해체 완료 대기 중...", disbandToPhoneDelay)
    Sleep(disbandToPhoneDelay)

    ShowMocaMessage("📱 휴대폰 열기...", 800)
    PressKey("Up")
    Sleep(phoneOpenDelay)
    
    ShowMocaMessage("🔍 빠른 참가 선택...", 600)
    PressKey("Right", 2, phoneNavDelay)
    Sleep(phoneNavDelay)
    PressKey("Enter")
    Sleep(phoneNavDelay)
    
    ShowMocaMessage("🎲 랜덤 세션 선택...", 600)
    PressKey("Up")
    Sleep(phoneNavDelay)
    PressKey("Enter", 3, phoneNavDelay)
}

; 보스 등록 시퀀스
ExecuteBossRegistrationSequence(phoneToMenuDelay, interactionMenuOpenDelay, menuDelay, key) {
    global config
    
    ShowMocaMessage("📱➡️📋 세션 이동 후 메뉴 열기...", phoneToMenuDelay)
    Sleep(phoneToMenuDelay)
    PressKey("m")
    Sleep(interactionMenuOpenDelay)
    
    if (key = config["Hotkeys"]["TeleportMoca1"]) {
        ShowMocaMessage("🏢 CEO 등록 준비...", 500)
        PressKey("Down", 1, menuDelay)
        Sleep(menuDelay)
    } else if (key = config["Hotkeys"]["TeleportMoca2"]) {
        ShowMocaMessage("🏍️ MC 회장 등록 준비...", 500)
        PressKey("Down", 2, menuDelay)
        Sleep(menuDelay)
    }
    
    ShowMocaMessage("✅ 보스 등록 중...", 600)
    PressKey("Enter")
    Sleep(menuDelay)
    PressKey("Down")
    Sleep(menuDelay)
    PressKey("Enter", 2, menuDelay)
}