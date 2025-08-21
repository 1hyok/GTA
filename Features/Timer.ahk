; === 타이머 변수 ===
global timer48Running := false
global timer48StartTime := 0
global timer48AlertActive := false

Toggle48MinTimer() {
    global timer48Running, timer48StartTime, timer48AlertActive, config
    
    timerMinutes := config["Settings"]["Timer48Minutes"]
    
    ; 알림 활성 상태면 알림만 끄기
    if (timer48AlertActive) {
        timer48AlertActive := false
        SetTimer(ShowTimerAlert, 0)
        ToolTip("")
        ShowTooltip("알림 중지")
        return
    }
    
    if (!timer48Running) {
        timer48Running := true
        timer48StartTime := A_TickCount
        timer48AlertActive := false
        ShowTooltip(timerMinutes "분 타이머 시작")
        SetTimer(Check48Minutes, 60000)  ; 1분마다 체크
    } else {
        timer48Running := false
        timer48AlertActive := false
        SetTimer(Check48Minutes, 0)
        SetTimer(ShowTimerAlert, 0)
        elapsed := Round((A_TickCount - timer48StartTime) / 60000, 1)
        ShowTooltip("타이머 중지 (경과: " elapsed "분)", 2000)
        ToolTip("")
    }
}

Check48Minutes() {
    global timer48Running, timer48StartTime, timer48AlertActive, config
    
    if (!timer48Running)
        return
    
    timerMinutes := config["Settings"]["Timer48Minutes"]
    elapsed := (A_TickCount - timer48StartTime) / 60000
    
    if (elapsed >= timerMinutes) {
        timer48Running := false
        timer48AlertActive := true
        SetTimer(Check48Minutes, 0)
        
        ; 설정된 키 가져오기
        timerKey := config["Hotkeys"]["Timer48"]
        
        ; 트레이 알림
        TrayTip(timerMinutes "분 타이머 완료!", timerKey " 눌러 확인하세요", "Iconi")
        
        ; 반복 알림 시작
        SetTimer(ShowTimerAlert, 1000)
    }
}

ShowTimerAlert() {
    global timer48AlertActive, config
    
    if (!timer48AlertActive) {
        SetTimer(ShowTimerAlert, 0)
        ToolTip("")
        return
    }
    
    static toggle := false
    toggle := !toggle
    
    if (toggle) {
        timerKey := config["Hotkeys"]["Timer48"]
        ToolTip("⏰⏰⏰ " config["Settings"]["Timer48Minutes"] "분 완료! " timerKey "로 확인 ⏰⏰⏰", 10, 10)
        SoundBeep(1500, 200)
    } else {
        ToolTip("")
    }
}