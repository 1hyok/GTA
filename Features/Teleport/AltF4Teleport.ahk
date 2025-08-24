; Alt+F4 텔레포트 실행 함수
ExecuteAltF4Teleport() {
    global config, altF4Running, altF4StartTime
    
    if (!IsGTAActive() || altF4Running)
        return
    
    altF4Running := true
    teleportWaitTime := config["Settings"]["TeleportWaitTime"]
    timerInterval := config["Settings"]["TeleportTimerInterval"]
    keyHoldTime := config["Settings"]["KeyHoldTime"]
    
    ; 시작 시퀀스
    ExecuteAltF4StartSequence(keyHoldTime)
    
    ; 진행 상황 모니터링
    ExecuteAltF4WaitSequence(teleportWaitTime, timerInterval)
    
    ; 완료 시퀀스
    ExecuteAltF4EndSequence()
    
    altF4Running := false
}

; Alt+F4 시작 시퀀스
ExecuteAltF4StartSequence(keyHoldTime) {
    ShowAltF4Message("🚀 Alt+F4 텔레포트 시작")
    
    ShowAltF4Message("⏎ Enter 키 입력...", 300)
    PressKey("Enter")
    
    ShowAltF4Message("🔄 Alt+F4 조합키 실행...", 500)
    Send("{Alt down}{F4 down}")
    Sleep(keyHoldTime)
    Send("{F4 up}{Alt up}")
}

; Alt+F4 대기 시퀀스
ExecuteAltF4WaitSequence(teleportWaitTime, timerInterval) {
    global altF4StartTime
    
    altF4StartTime := A_TickCount
    SetTimer(ShowAltF4Progress, timerInterval)
    Sleep(teleportWaitTime)
    SetTimer(ShowAltF4Progress, 0)
    ToolTip("")
}

; Alt+F4 완료 시퀀스
ExecuteAltF4EndSequence() {
    ShowAltF4Message("🔙 ESC 키로 복귀...", 500)
    PressKey("Escape")
    ShowAltF4Message("✅ Alt+F4 텔레포트 완료!", 2000)
}