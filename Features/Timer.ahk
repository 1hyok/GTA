; === 타이머 변수 ===
global timer48Running := false
global timer48StartTime := 0

Toggle48MinTimer() {
    global timer48Running, timer48StartTime, config
    
    timerMinutes := config["Settings"]["Timer48Minutes"]
    
    if (!timer48Running) {
        timer48Running := true
        timer48StartTime := A_TickCount
        ShowTooltip(timerMinutes "분 타이머 시작")
        SetTimer(Check48Minutes, 60000)  ; 1분마다 체크
    } else {
        timer48Running := false
        SetTimer(Check48Minutes, 0)
        elapsed := Round((A_TickCount - timer48StartTime) / 60000, 1)
        ShowTooltip("타이머 중지 (경과: " elapsed "분)", 2000)
    }
}

Check48Minutes() {
    global timer48Running, timer48StartTime, config
    
    if (!timer48Running)
        return
    
    timerMinutes := config["Settings"]["Timer48Minutes"]
    elapsed := (A_TickCount - timer48StartTime) / 60000
    
    if (elapsed >= timerMinutes) {
        timer48Running := false
        SetTimer(Check48Minutes, 0)
        
        ; 알림
        MsgBox(timerMinutes "분이 지났습니다!", "타이머 알림", "OK Icon!")
        
        ; 사운드
        SoundBeep(1000, 500)
        Sleep(100)
        SoundBeep(1000, 500)
        
        ; 툴팁
        ToolTip("⏰ " timerMinutes "분 완료! ⏰", A_ScreenWidth//2 - 50, A_ScreenHeight//2)
        SetTimer(HideToolTip, 5000)
    }
}