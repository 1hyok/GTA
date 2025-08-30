#Requires AutoHotkey v2.0
#SingleInstance Force

; === 전역 변수 ===
global ctrlRunning := false
global config := Map()

; === 설정 로드 ===
LoadConfig()

; === 설정값들 ===
config["ClickInterval"] := 100  ; LCtrl 연타 간격 (ms)
config["KeyHoldTime"] := 50     ; 키 누르는 시간 (ms)
config["ToggleKey"] := "F10"    ; 토글 키
config["ExitKey"] := "F12"      ; 종료 키

; === 단축키 설정 ===
Hotkey(config["ToggleKey"], (*) => ToggleLCtrlSpam())
Hotkey(config["ExitKey"], (*) => ExitApp())

; === 함수들 ===
IsGTAActive() {
    return WinActive("Grand Theft Auto V")
}

ShowTooltip(text, duration := 1000) {
    ToolTip(text, 0, 0)
    SetTimer(() => ToolTip(), duration)
}

ToggleLCtrlSpam() {
    global ctrlRunning, config
    
    if (!IsGTAActive())
        return
    
    if (!ctrlRunning) {
        ctrlRunning := true
        ShowTooltip("LCtrl 연타 시작 (간격: " config["ClickInterval"] "ms)")
        DoLCtrlPress()
        SetTimer(DoLCtrlPress, config["ClickInterval"])
    } else {
        ctrlRunning := false
        ShowTooltip("LCtrl 연타 중지")
        SetTimer(DoLCtrlPress, 0)
    }
}

DoLCtrlPress() {
    if (IsGTAActive()) {
        Send("{LCtrl down}")
        Sleep(config["KeyHoldTime"])
        Send("{LCtrl up}")
    }
}

LoadConfig() {
    ; 기본값 설정 - 실제로는 Config.ini에서 읽어올 수도 있음
}

; === 시작 메시지 ===
ShowTooltip("LCtrl 연타기 시작`n" config["ToggleKey"] ": 토글 | " config["ExitKey"] ": 종료", 2000)