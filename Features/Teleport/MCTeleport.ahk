; MC 텔레포트 실행 함수. role 은 "CEO" 또는 "MC" (세션 이동 뒤 다시 등록할 보스 종류)
ExecuteMCTeleport(role) {
    global mcRunning, config

    if (mcRunning || !IsGTAActive())
        return

    mcRunning := true
    try {
        ; 설정값 로드
        phoneOpenDelay := config["Settings"]["PhoneOpenDelay"]
        phoneControlDelay := config["Settings"]["PhoneControlDelay"]
        menuOpenDelay := config["Settings"]["MenuOpenDelay"]
        menuControlDelay := config["Settings"]["MenuControlDelay"]
        mcDisbandDelay := config["Settings"]["MCDisbandDelay"]
        phoneCloseDelay := config["Settings"]["PhoneCloseDelay"]

        ; 단계 1: 클럽 해체
        ExecuteDisbandSequence(menuOpenDelay, menuControlDelay)

        ; 단계 2: 세션 이동
        ExecuteSessionChangeSequence(mcDisbandDelay, phoneOpenDelay, phoneControlDelay)

        ; 단계 3: 보스 등록
        ExecuteBossRegistrationSequence(phoneCloseDelay, menuOpenDelay, menuControlDelay, role)

        ShowMCMessage("🎉 MC 텔레포트 완료!", 2000)
    } finally {
        mcRunning := false
    }
}

; 클럽 해체 시퀀스
ExecuteDisbandSequence(menuOpenDelay, menuControlDelay) {
    ShowMCMessage("📱 MC 텔레포트 시작", 1500)

    ShowMCMessage("📋 상호작용 메뉴 열기...", 800)
    PressKey("m")
    Sleep(menuOpenDelay)

    ShowMCMessage("🏍️ 모터사이클 클럽 두목 선택...", 500)
    PressKey("Enter")
    Sleep(menuControlDelay)

    ShowMCMessage("⬆️ 해체 포커스...", 300)
    PressKey("Up")
    Sleep(menuControlDelay)

    ShowMCMessage("💥 클럽 해체 중...", 800)
    PressKey("Enter")
    Sleep(menuControlDelay)
}

; 세션 변경 시퀀스
ExecuteSessionChangeSequence(mcDisbandDelay, phoneOpenDelay, phoneControlDelay) {
    ShowMCMessage("⏳ 해체 완료 대기 중...", mcDisbandDelay)
    Sleep(mcDisbandDelay)

    ShowMCMessage("📱 휴대폰 열기...", 800)
    PressKey("Up")
    Sleep(phoneOpenDelay)

    ShowMCMessage("🔍 빠른 참가 선택...", 600)
    PressKey("Right", 2, phoneControlDelay)
    Sleep(phoneControlDelay)
    PressKey("Enter")
    Sleep(phoneControlDelay)

    ShowMCMessage("🎲 랜덤 세션 선택...", 600)
    PressKey("Up")
    Sleep(phoneControlDelay)
    PressKey("Enter", 3, phoneControlDelay)
}

; 보스 등록 시퀀스
ExecuteBossRegistrationSequence(phoneCloseDelay, menuOpenDelay, menuControlDelay, role) {
    ShowMCMessage("📱➡️📋 세션 이동 후 메뉴 열기...", phoneCloseDelay)
    Sleep(phoneCloseDelay)
    PressKey("m")
    Sleep(menuOpenDelay)

    if (role = "CEO") {
        ShowMCMessage("🏢 CEO 등록 준비...", 500)
        PressKey("Down", 1, menuControlDelay)
        Sleep(menuControlDelay)
    } else if (role = "MC") {
        ShowMCMessage("🏍️ MC 회장 등록 준비...", 500)
        PressKey("Down", 2, menuControlDelay)
        Sleep(menuControlDelay)
    }

    ShowMCMessage("✅ 보스 등록 중...", 600)
    PressKey("Enter")
    Sleep(menuControlDelay)
    PressKey("Down")
    Sleep(menuControlDelay)
    PressKey("Enter", 2, menuControlDelay)
}
