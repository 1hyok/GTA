MocaTeleport() {
    global mocaRunning, keyPressed, config
    
    if (!mocaRunning || !IsGTAActive())
        return
    
    phoneOpenDelay := config["Settings"]["PhoneOpenDelay"]
    phoneNavDelay := config["Settings"]["PhoneNavigationDelay"]
    menuDelay := config["Settings"]["InteractionMenuDelay"]
    phoneToMenuDelay := config["Settings"]["PhoneToMenuDelay"]
    
    ; 모사 해체
    PressKey("m")
    Sleep(menuDelay)
    PressKey("Enter")
    Sleep(menuDelay)
    PressKey("Up")
    Sleep(menuDelay)
    PressKey("Enter")
    Sleep(menuDelay)

    ; 휴대폰 빠참
    PressKey("Up")  ; 휴대폰 열기
    Sleep(phoneOpenDelay)
    PressKey("Right", 2, phoneNavDelay)
    Sleep(phoneNavDelay)  ; ← 추가
    PressKey("Enter")
    Sleep(phoneNavDelay)
    PressKey("Up")
    Sleep(phoneNavDelay)
    PressKey("Enter", 3, phoneNavDelay)
    Sleep(phoneNavDelay)  ; ← 추가
    
    ; 모사 설립
    Sleep(phoneToMenuDelay)
    PressKey("m")
    Sleep(menuDelay)
    
    if (keyPressed = "F4") {
        PressKey("Down", 1, menuDelay)
        Sleep(menuDelay)  ; ← 추가
    } else if (keyPressed = "F5") {
        PressKey("Down", 2, menuDelay)
        Sleep(menuDelay)  ; ← 추가
    }
    
    PressKey("Enter")
    Sleep(menuDelay)
    PressKey("Down")
    Sleep(menuDelay)
    PressKey("Enter", 2, menuDelay)
    ; 마지막이니까 Sleep 불필요
    
    mocaRunning := false
}