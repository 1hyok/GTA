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
    ; 모든 타이머 중지 (함수로 존재하는 것만)
    SetTimer(() => ToolTip(), 0)
    
    ; 키 해제
    try {
        Send("{w up}")
        Send("{Shift up}")
    }
    
    ToolTip("")
    ExitApp()
}