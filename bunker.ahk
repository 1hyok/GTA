#Requires AutoHotkey v2.0
#SingleInstance Force

bunkerRunning := false

; === 유틸리티 함수 ===
PressEnter() {
    Send("{Enter down}")
    Sleep(1000)
    Send("{Enter up}")
}

MoveAndEnter(x, y, afterDelay := 5000) {
    MouseMove(x, y, 0)
    Sleep(4000)
    PressEnter()
    Sleep(afterDelay)
}

; === 단축키 ===
F9::{
    global bunkerRunning
    
    if (bunkerRunning) {
        bunkerRunning := false
        SetTimer(BunkerCycle, 0)
        SetTimer(AFKKeeper, 0)
    } else {
        bunkerRunning := true
        BunkerCycle()
    }
}

F12::{
    global bunkerRunning
    bunkerRunning := false
    SetTimer(BunkerCycle, 0)
    SetTimer(AFKKeeper, 0)
    ExitApp
}

; === 메인 사이클 ===
BunkerCycle() {
    global bunkerRunning
    
    if (!bunkerRunning)
        return
    
    ; AFK 방지 일시 정지
    SetTimer(AFKKeeper, 0)
    
    ; 보급품 구입 실행
    WinActivate("Grand Theft Auto V")
    Sleep(5000)
    
    MoveAndEnter(512, 411)     ; 알림창 확인 버튼 눌러 제거
    MoveAndEnter(500, 550)     ; 보급품 구입 버튼
    MoveAndEnter(600, 450)     ; 확인 버튼
    
    ; 보급 완료 후 AFK 방지 시작
    SetTimer(AFKKeeper, 5000)
    
    ; 27분 25초 후 다시 사이클
    SetTimer(BunkerCycle, 1645000)
}

AFKKeeper() {
    global bunkerRunning
    
    if (!bunkerRunning)
        return
    
    MoveAndEnter(512, 411, 2000)    ; 알림창 확인 버튼 눌러 제거
    MoveAndEnter(600, 450, 2000)    ; 보급품 강탈 버튼
    PressEnter()                     ; 추가 Enter
}