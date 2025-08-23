#Requires AutoHotkey v2.0
#SingleInstance Force

; === 코어 모듈 로드 ===
#Include Core\PressKey.ahk
#Include Core\Common.ahk

global bunkerRunning := false
global afkTimerActive := false

; 토글 키
F9::{
    global bunkerRunning, afkTimerActive
    
    if (!IsGTAActive())
        return
    
    if (bunkerRunning) {
        bunkerRunning := false
        afkTimerActive := false
        SetTimer(BunkerCycle, 0)
        SetTimer(AFKKeeper, 0)
        ShowTooltip("벙커 자동화 중지")
    } else {
        bunkerRunning := true
        ShowTooltip("벙커 자동화 시작")
        BunkerCycle()  ; 바로 시작
    }
}

; 종료 키 (F12 또는 다른 키로 변경 권장)
F12::{
    global bunkerRunning, afkTimerActive
    bunkerRunning := false
    afkTimerActive := false
    SetTimer(BunkerCycle, 0)
    SetTimer(AFKKeeper, 0)
    ShowTooltip("벙커 자동화 종료")
    Sleep(1000)
    ExitApp()
}

BunkerCycle() {
    global bunkerRunning, afkTimerActive, config
    
    if (!bunkerRunning || !IsGTAActive())
        return
    
    ; AFK 방지 일시 정지
    afkTimerActive := false
    SetTimer(AFKKeeper, 0)
    
    ShowTooltip("보급품 구입 시작...")
    
    ; 보급품 구입 실행
    Sleep(5000)
    
    ; 첫 번째 엔터 (512, 411)
    MouseMove(512, 411, 0)
    Sleep(4000)
    PressKey("Enter")  ; PressKey 함수 사용
    Sleep(5000)
    
    ; 보급품 구입 버튼 (500, 550)
    MouseMove(500, 550, 0)
    Sleep(4000)
    PressKey("Enter")
    Sleep(5000)
    
    ; 확인 버튼 (600, 450)
    MouseMove(600, 450, 0)
    Sleep(4000)
    PressKey("Enter")
    Sleep(5000)
    
    ShowTooltip("보급 완료! AFK 방지 모드 시작")
    
    ; 28분 동안 AFK 방지 시작
    afkTimerActive := true
    SetTimer(AFKKeeper, 5000)  ; 5초마다
    
    ; 27분 25초 후 다시 보급 사이클 (28분 - 35초)
    SetTimer(() => BunkerCycle(), 1645000, -1)  ; -1로 한 번만 실행
}

AFKKeeper() {
    global bunkerRunning, afkTimerActive
    
    if (!bunkerRunning || !afkTimerActive || !IsGTAActive())
        return
    
    ; 첫 번째 위치에서 엔터 (512, 411)
    MouseMove(512, 411, 0)
    Sleep(4000)
    PressKey("Enter")
    Sleep(2000)
    
    ; 확인 버튼 위치에서 엔터 두 번 (600, 450)
    MouseMove(600, 450, 0)
    Sleep(4000)
    PressKey("Enter", 2, 2000)  ; 2번, 간격 2초
}