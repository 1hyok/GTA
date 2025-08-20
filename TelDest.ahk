; GTA Online Auto Script
; 시작/일시정지/재개: F6
; 종료: F9

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include PressKey.ahk

; 전역 변수
isRunning := false
isPaused := false
scriptStep := 0
waitCounter := 0

; F6: 시작/일시정지/재개
F6::
{
    global isRunning, isPaused, scriptStep, waitCounter
    
    if (!isRunning)
    {
        ; 시작
        WinActivate("Grand Theft Auto V")
        isRunning := true
        isPaused := false
        scriptStep := 1
        waitCounter := 0
        SetTimer(RunScript, 100)
    }
    else if (!isPaused)
    {
        ; 일시정지
        isPaused := true
        ToolTip("일시정지됨", 0, 30)
    }
    else
    {
        ; 재개 (처음부터)
        WinActivate("Grand Theft Auto V")
        isPaused := false
        scriptStep := 1
        waitCounter := 0
        ToolTip("")
    }
}

; F9: 종료
F9::
{
    global isRunning
    isRunning := false
    SetTimer(RunScript, 0)
    ToolTip("")
    ExitApp()
}

; 메인 스크립트 함수
RunScript()
{
    global isRunning, isPaused, scriptStep, waitCounter
    
    ; 종료 체크
    if (!isRunning) {
        SetTimer(RunScript, 0)
        ToolTip("")
        return
    }
    
    ; 일시정지 체크
    if (isPaused)
        return
    
    ; 상태 표시
    if (scriptStep = 3) {
        ; 35초 대기 중일 때만 큰 표시
        seconds := Round(waitCounter / 10, 1)
        remaining := 35 - seconds
        ToolTip("대기 중: " seconds " / 35초`n남은 시간: " remaining "초", A_ScreenWidth//2 - 100, A_ScreenHeight//2)
    } else if (scriptStep != 5) {  ; Step 5는 툴팁 표시 안 함
        ToolTip("Step: " scriptStep, 0, 0)
    }
    
    ; 스텝별 실행
    switch scriptStep {
        case 1:  ; 엔터
            PressKey("Enter")
            scriptStep++
            
        case 2:  ; Alt+F4
            Send("{Alt down}")
            Sleep(25)
            PressKey("F4")
            Send("{Alt up}")
            scriptStep++
            waitCounter := 0
            
        case 3:  ; 35초 대기
            waitCounter++
            if (waitCounter >= 350) {
                scriptStep++
                ToolTip("")  ; 대기 끝나면 툴팁 제거
            }
            
        case 4:  ; ESC
            PressKey("Esc")
            scriptStep++
            
        case 5:  ; 완료
            isRunning := false
            isPaused := false
            scriptStep := 0
            waitCounter := 0
            SetTimer(RunScript, 0)
            ToolTip("")  ; 즉시 툴팁 제거
    }
}