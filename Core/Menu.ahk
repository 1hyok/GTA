; === 상호작용 메뉴 공통 ===
; M 으로 열고 Down 으로 내려가 Enter 로 고른다. 키를 보내기 전마다 GTA 가 앞인지와 전체 멈춤 신호(gAbort)를 본다.
; 메뉴 항목 순서는 게임 버전·보유 자산·현재 위치(내 부동산 안이면 맨 위에 한 줄 더 붙음)에 따라 달라 칸 수는 Config [Settings] 로 뺀다.
; 게임은 마지막 커서 위치를 기억하므로 칸 수는 맨 위(Quick GPS)에서 센 값이고, 다른 항목에 커서를 두고 닫았다면 한 번은 빗나갈 수 있다.
; 딜레이는 MenuOpenDelay(M 뒤) / MenuControlDelay(키 사이). 각 키는 PressKey 가 KeyHoldTime 만큼 누른다.
global gMenuBusy := false

MenuKey(key, count := 1) {
    global gAbort, config
    Loop count {
        if (gAbort || !IsGTAActive())
            return false
        PressKey(key)
        Sleep(config["Settings"]["MenuControlDelay"])
    }
    return true
}

MenuOpen() {
    global gAbort, config
    if (gAbort || !IsGTAActive())
        return false
    PressKey("m")
    Sleep(config["Settings"]["MenuOpenDelay"])
    return true
}

; 메뉴는 M 으로 토글된다. GTA 가 앞이 아니면 아무것도 보내지 않는다.
MenuClose() {
    if (IsGTAActive())
        PressKey("m")
}

; steps 는 단계별 Down 횟수 배열. 단계 사이에 Enter 한 번, 마지막 단계 뒤에 Enter 를 enterCount 번 누른다.
; 예: [4, 2, 0], 1 = M, Down x4, Enter, Down x2, Enter, Down x0, Enter x1
RunMenuPath(label, steps, enterCount := 1, closeAfter := 1) {
    global gAbort, gMenuBusy
    if (gMenuBusy) {
        ShowTooltip(label ": 다른 메뉴 매크로가 진행 중", 1500)
        return false
    }
    gMenuBusy := true
    gAbort := false
    ok := false
    ; 내 부동산(아케이드·에이전시 등) 안에서는 맨 위에 "… Management" 줄이 한 줄 더 붙어 첫 단계 칸 수가 1 늘어난다 (0926 아케이드 실측)
    steps[1] += config["Settings"]["MenuTopOffset"]
    try {
        if (!MenuOpen())
            return false
        for i, n in steps {
            if (!MenuKey("Down", n))
                return false
            if (i < steps.Length && !MenuKey("Enter"))
                return false
        }
        if (!MenuKey("Enter", enterCount))
            return false
        ok := true
    } finally {
        if (closeAfter)
            MenuClose()
        gMenuBusy := false
        MacroLog("menu", label " " (ok ? "ok" : "중단"))
    }
    return ok
}
