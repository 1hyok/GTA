#Requires AutoHotkey v2.0

; 마우스 클릭 함수
ClickMouse(button := "Left", count := 1) {
    global config
    
    ; Config에서 클릭 딜레이 값 읽기
    clickHoldTime := config["Settings"]["ClickHoldTime"]
    clickInterval := config["Settings"]["ClickInterval"]
    
    Loop count {
        Click(button " Down")
        Sleep(clickHoldTime)
        Click(button " Up")
        if (A_Index < count) ; 마지막이 아니면 딜레이
            Sleep(clickInterval)
    }
    Sleep(clickInterval)
}