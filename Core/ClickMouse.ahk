#Requires AutoHotkey v2.0

; 마우스 클릭 함수
ClickMouse(button := "Left", count := 1) {
    ; 딜레이 설정 (ms)
    clickHoldTime := 50    ; 클릭 누르고 있는 시간
    betweenDelay := 150    ; 클릭 사이 간격
    
    Loop count {
        Click(button " Down")
        Sleep(clickHoldTime)
        Click(button " Up")
        if (A_Index < count) ; 마지막이 아니면 딜레이
            Sleep(betweenDelay)
    }
    Sleep(betweenDelay)
}