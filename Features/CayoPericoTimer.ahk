; === 카요 페리코 쿨타임 타이머 변수 ===
global cayoTimerRunning := false
global cayoTimerStartTime := 0
global cayoEndTime := ""
global cayoAlertActive := false

ToggleCayoPericoTimer() {
    global cayoTimerRunning, cayoTimerStartTime, cayoEndTime, cayoAlertActive, config
    
    cayoCooldownMinutes := config["Settings"]["CayoCooldownMinutes"]
    
    ; 알림 활성 상태면 알림만 끄기
    if (cayoAlertActive) {
        cayoAlertActive := false
        SetTimer(ShowCayoTimerAlert, 0)
        ToolTip("")
        ShowTooltip("카요 페리코 알림 중지")
        return
    }
    
    if (!cayoTimerRunning) {
        cayoTimerRunning := true
        cayoTimerStartTime := A_TickCount
        cayoAlertActive := false
        
        ; 종료 시각 계산
        endDateTime := DateAdd(A_Now, cayoCooldownMinutes, "Minutes")
        cayoEndTime := FormatTime(endDateTime, "HH:mm")
        
        ShowTooltip("🏝️ 카요 페리코 쿨타임 시작`n완료 예정: " cayoEndTime, 2000)
        SetTimer(CheckCayoCooldown, 300000)  ; 5초마다 체크
        SetTimer(ShowCayoEndTime, 0)       ; 즉시 한 번 실행
        SetTimer(ShowCayoEndTime, 300000)    ; 5초마다 갱신
    } else {
        cayoTimerRunning := false
        cayoAlertActive := false
        SetTimer(CheckCayoCooldown, 0)
        SetTimer(ShowCayoTimerAlert, 0)
        SetTimer(ShowCayoEndTime, 0)
        elapsed := Round((A_TickCount - cayoTimerStartTime) / 60000, 1)
        ShowTooltip("🏝️ 카요 페리코 타이머 중지 (경과: " elapsed "분)", 2000)
        ToolTip("")
    }
}

CheckCayoCooldown() {
    global cayoTimerRunning, cayoTimerStartTime, cayoAlertActive, config
    
    if (!cayoTimerRunning)
        return
    
    cayoCooldownMinutes := config["Settings"]["CayoCooldownMinutes"]
    elapsed := (A_TickCount - cayoTimerStartTime) / 60000
    
    if (elapsed >= cayoCooldownMinutes) {
        cayoTimerRunning := false
        cayoAlertActive := true
        SetTimer(CheckCayoCooldown, 0)
        SetTimer(ShowCayoEndTime, 0)
        
        ; 설정된 키 가져기
        cayoTimerKey := config["Hotkeys"]["CayoPericoTimer"]
        
        ; 트레이 알림
        TrayTip("🏝️ 카요 페리코 쿨타임 완료!", cayoTimerKey " 눌러 확인하세요", "Iconi")
        
        ; 반복 알림 시작
        SetTimer(ShowCayoTimerAlert, 1000)
    }
}

ShowCayoEndTime() {
    global cayoTimerRunning, cayoEndTime
    
    if (!cayoTimerRunning) {
        SetTimer(ShowCayoEndTime, 0)
        ToolTip("")
        return
    }
    
    currentTime := FormatTime(A_Now, "HH:mm")
    ToolTip("🏝️ 카요 페리코 쿨타임`n완료 예정: " cayoEndTime "`n현재 시각: " currentTime, 10, 50)
}

ShowCayoTimerAlert() {
    global cayoAlertActive, config
    
    if (!cayoAlertActive) {
        SetTimer(ShowCayoTimerAlert, 0)
        ToolTip("")
        return
    }
    
    static toggle := false
    toggle := !toggle
    
    if (toggle) {
        cayoTimerKey := config["Hotkeys"]["CayoPericoTimer"]
        ToolTip("🏝️⏰🏝️ 카요 페리코 준비 완료! " cayoTimerKey "로 확인 🏝️⏰🏝️", 10, 10)
        SoundBeep(1500, 200)
    } else {
        ToolTip("")
    }
}