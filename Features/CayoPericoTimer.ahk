; === 카요 페리코 쿨타임 타이머 변수 ===
global cayoTimerRunning := false
global cayoTimerStartTime := 0
global cayoAlertActive := false

ToggleCayoPericoTimer() {
    global cayoTimerRunning, cayoTimerStartTime, cayoAlertActive, config
    
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
        ShowTooltip("🏝️ 카요 페리코 쿨타임 시작 (" cayoCooldownMinutes "분)")
        SetTimer(CheckCayoCooldown, 1000)  ; 1초마다 체크로 변경
        SetTimer(ShowCayoProgress, 1000)   ; 진행 상황 표시 타이머 추가
    } else {
        cayoTimerRunning := false
        cayoAlertActive := false
        SetTimer(CheckCayoCooldown, 0)
        SetTimer(ShowCayoTimerAlert, 0)
        SetTimer(ShowCayoProgress, 0)     ; 진행 상황 타이머도 중지
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
        SetTimer(ShowCayoProgress, 0)  ; 진행 상황 타이머 중지
        
        ; 설정된 키 가져오기
        cayoTimerKey := config["Hotkeys"]["CayoPericoTimer"]
        
        ; 트레이 알림
        TrayTip("🏝️ 카요 페리코 쿨타임 완료!", cayoTimerKey " 눌러 확인하세요", "Iconi")
        
        ; 반복 알림 시작
        SetTimer(ShowCayoTimerAlert, 1000)
    }
}

ShowCayoProgress() {
    global cayoTimerRunning, cayoTimerStartTime, config
    
    if (!cayoTimerRunning) {
        SetTimer(ShowCayoProgress, 0)
        ToolTip("")
        return
    }
    
    cayoCooldownMinutes := config["Settings"]["CayoCooldownMinutes"]
    elapsed := (A_TickCount - cayoTimerStartTime) / 60000
    remaining := cayoCooldownMinutes - elapsed
    
    if (remaining <= 0) {
        SetTimer(ShowCayoProgress, 0)
        return
    }
    
    ; 진행률 계산
    progressPercent := (elapsed / cayoCooldownMinutes) * 100
    
    ; 진행 바 생성
    barLength := 20
    filledLength := Round(progressPercent / 100 * barLength)
    progressBar := ""
    
    Loop filledLength
        progressBar .= "█"
    Loop (barLength - filledLength)
        progressBar .= "░"
    
    ; 남은 시간 형식화
    remainingHours := Floor(remaining / 60)
    remainingMins := Round(Mod(remaining, 60), 1)
    
    timeDisplay := ""
    if (remainingHours > 0)
        timeDisplay := remainingHours "시간 " remainingMins "분"
    else
        timeDisplay := remainingMins "분"
    
    ; 단계별 메시지
    stageMessage := GetCayoStageMessage(remaining)
    
    ToolTip("🏝️ 카요 페리코 쿨타임`n" 
          . stageMessage . "`n"
          . progressBar . " " . Round(progressPercent, 1) . "%`n"
          . "⏱️ 남은 시간: " . timeDisplay, 10, 50)
}

GetCayoStageMessage(remaining) {
    if (remaining > 40)
        return "😴 긴 휴식 시간..."
    else if (remaining > 20)
        return "⏳ 중간 대기 중..."
    else if (remaining > 10)
        return "🔥 곧 준비 완료!"
    else if (remaining > 5)
        return "🚀 거의 다 왔어!"
    else
        return "🎯 마지막 카운트다운!"
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