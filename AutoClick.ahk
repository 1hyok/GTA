#Requires AutoHotkey v2.0

#Include ClickMouse.ahk

; 전역 변수
isRunning := false

; 창 활성화
WinActivate("Grand Theft Auto V")

; F7: 시작/일시정지/재개
F7:: {
    global isRunning
    WinActivate("Grand Theft Auto V")
    
    if (!isRunning) {
        isRunning := true
        ToolTip("Auto Click 시작", 0, 0)
        SetTimer(HideToolTip, 1000)
        SetTimer(DoClick, 200)  ; 200ms마다 클릭
    } else {
        isRunning := false
        ToolTip("Auto Click 중지", 0, 0)
        SetTimer(HideToolTip, 1000)
        SetTimer(DoClick, 0)  ; 타이머 중지
    }
}

; F9: 스크립트 종료
F9:: {
    ToolTip("스크립트 종료", 0, 0)
    SetTimer(HideToolTip, 1000)
    ExitApp
}

; 클릭 타이머 함수
DoClick() {
    ClickMouse("Left", 1)
}

; 툴팁 제거 함수
HideToolTip() {
    ToolTip()
    SetTimer(HideToolTip, 0)
}