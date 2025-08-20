; GTA Online Auto Script
; 시작/일시정지/재개: F5
; 종료: F9

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include PressKey.ahk

; 전역 변수
isRunning := false
isPaused := false

; F5: 시작/일시정지/재개
F6::
{
    global isRunning, isPaused
    
    if (!isRunning)
    {
        ; 시작
        WinActivate("Grand Theft Auto V")
        isRunning := true
        isPaused := false
        RunScript()
    }
    else if (!isPaused)
    {
        ; 일시정지
        isPaused := true
    }
    else
    {
        ; 재개
        WinActivate("Grand Theft Auto V")
        isPaused := false
        RunScript()
    }
}

; F9: 종료
F9::
{
    global isRunning, isPaused
    isRunning := false
    isPaused := false
    ExitApp()
}

; 메인 스크립트 함수
RunScript()
{
    global isRunning, isPaused
    
    ; 스페이스바 
    PressKey("Space")
    
    ; 엔터
    PressKey("Enter")
    
    ; Alt+F4
    Send("{Alt down}")
    Sleep(25)
    PressKey("F4")
    Send("{Alt up}")
    
    Sleep(35000)
    
    ; ESC
    PressKey("Esc")
    
    ; 실행 완료
    isRunning := false
    isPaused := false
}