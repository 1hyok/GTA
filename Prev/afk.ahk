#Requires AutoHotkey v2.0
running := false

SendWKey() {
    Send("w")  ; 그냥 이거
}

; F8로 시작/일시정지 토글
F8:: {
    global running
    running := !running
    
    if (running) {
        WinActivate("Grand Theft Auto V")
        SetTimer(SendWKey, 2000)
        TrayTip("실행 중", "F9로 일시정지")
    } else {
        SetTimer(SendWKey, 0)
        TrayTip("일시정지", "F9로 재개")
    }
}

F9:: {
    SetTimer(SendWKey, 0)
    ExitApp()
}