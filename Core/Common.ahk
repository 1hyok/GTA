; === 공통 함수 ===
IsGTAActive() {
    return WinActive("Grand Theft Auto V")
}

ShowTooltip(text, duration := 1000) {
    ToolTip(text, 0, 0)
    SetTimer(() => ToolTip(), duration)
}

; 모든 기능 종료
ExitAll() {
    ; 모든 타이머 중지
    SetTimer(() => ToolTip(), 0)
    SetTimer(CheckCayoCooldown, 0)
    SetTimer(ShowCayoTimerAlert, 0)
    SetTimer(ShowCayoEndTime, 0)  ; 새로 추가된 타이머
    SetTimer(DoClick, 0)
    SetTimer(PressLCtrlForVellum, 0)
    SetTimer(ShowAltF4Progress, 0)
    
    ; 키 해제
    try {
        Send("{w up}")
        Send("{Shift up}")
    }
    
    ToolTip("")
    ExitApp()
}