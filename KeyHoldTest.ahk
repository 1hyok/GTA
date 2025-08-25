#Requires AutoHotkey v2.0
#SingleInstance Force

; Config.ini에서 키홀드타임 읽기
keyHoldTime := IniRead("Config.ini", "Settings", "KeyHoldTime", 50)

; F10 누르면 Up키 한 번 누르기
F10::{
    if (!WinActive("Grand Theft Auto V")) {
        ToolTip("GTA V가 활성화되지 않음")
        SetTimer(() => ToolTip(), 1000)
        return
    }
    
    Send("{Up down}")
    Sleep(keyHoldTime)
    Send("{Up up}")
    
    ToolTip("Up키 누름 (" keyHoldTime "ms)")
    SetTimer(() => ToolTip(), 1000)
}

; 종료
Esc::ExitApp()

; 시작 메시지
ToolTip("F10: Up키 누르기 | ESC: 종료`nKeyHoldTime: " keyHoldTime "ms")
SetTimer(() => ToolTip(), 3000)