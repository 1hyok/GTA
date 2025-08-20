#Requires AutoHotkey v2.0
#SingleInstance Force

bunkerRunning := false

F6::{
    global bunkerRunning
    
    if (bunkerRunning) {
        bunkerRunning := false
        SetTimer(BunkerCycle, 0)
        SetTimer(AFKKeeper, 0)
    } else {
        bunkerRunning := true
        BunkerCycle()  ; 바로 시작
    }
}

Esc::{
    global bunkerRunning
    bunkerRunning := false
    SetTimer(BunkerCycle, 0)
    SetTimer(AFKKeeper, 0)
    ExitApp
}

BunkerCycle() {
    global bunkerRunning
    
    if (!bunkerRunning)
        return
    
    ; AFK 방지 일시 정지
    SetTimer(AFKKeeper, 0)
    
    ; 보급품 구입 실행
    WinActivate("Grand Theft Auto V")
    Sleep(5000)
    
    MouseMove(512, 411, 0)  ; 512, 411에서 엔터
    Sleep(4000)  ; 마우스 이동 후 4초 대기
    Send("{Enter down}")
    Sleep(1000)  ; 다시 1초로
    Send("{Enter up}")
    Sleep(5000)
    
    MouseMove(500, 550, 0)  ; 보급품 구입 버튼
    Sleep(4000)  ; 마우스 이동 후 4초 대기
    Send("{Enter down}")
    Sleep(1000)  ; 다시 1초로
    Send("{Enter up}")
    Sleep(5000)
    
    MouseMove(600, 450, 0)  ; 확인 버튼
    Sleep(4000)  ; 마우스 이동 후 4초 대기
    Send("{Enter down}")
    Sleep(1000)  ; 다시 1초로
    Send("{Enter up}")
    Sleep(5000)
    
    ; 보급 완료 후 28분 동안 AFK 방지 시작
    SetTimer(AFKKeeper, 5000)  ; 5초마다 엔터들
    
    ; 28분 후 다시 보급 사이클 반복
    SetTimer(BunkerCycle, 1645000)  ; 28분에서 35초 뺀 값
}

AFKKeeper() {
    global bunkerRunning
    
    if (!bunkerRunning)
        return
    
    ; 512, 411에서 엔터
    MouseMove(512, 411, 0)
    Sleep(4000)  ; 여기도 4초 대기 추가
    Send("{Enter down}")
    Sleep(1000)
    Send("{Enter up}")
    Sleep(2000)
    
    ; 확인 버튼 위치(600,450)에서 엔터 두 번
    MouseMove(600, 450, 0)
    Sleep(4000)  ; 여기도 4초 대기 추가
    Send("{Enter down}")
    Sleep(1000)
    Send("{Enter up}")
    Sleep(2000)
    
    Send("{Enter down}")
    Sleep(1000)
    Send("{Enter up}")
}
