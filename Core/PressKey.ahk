#Requires AutoHotkey v2.0

; 키 누르기 함수
PressKey(key, count := 1) {
    global config
    
    ; Config에서 딜레이 값 읽기
    keyHoldTime := config["Settings"]["KeyHoldTime"]
    keyInterval := config["Settings"]["KeyInterval"]
    
    Loop count {
        Send("{" key " down}")
        Sleep(keyHoldTime)
        Send("{" key " up}")
        if (A_Index < count) ; 마지막이 아니면 딜레이
            Sleep(keyInterval)
    }
    Sleep(keyInterval)
}