#Requires AutoHotkey v2.0

; 키 누르기 함수
PressKey(key, count := 1) {
    ; 딜레이 설정 (ms)
    keyHoldTime := 50    ; 키 누르고 있는 시간
    betweenDelay := 150   ; 키 사이 간격
    
    Loop count {
        Send("{" key " down}")
        Sleep(keyHoldTime)
        Send("{" key " up}")
        if (A_Index < count) ; 마지막이 아니면 딜레이
            Sleep(betweenDelay)
    }
    Sleep(betweenDelay)
}