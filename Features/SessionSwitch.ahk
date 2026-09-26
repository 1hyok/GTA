; === 초대 전용 세션으로 이동 ===
; 일시정지 메뉴(P) → ONLINE → Find New Session → Invite Only Session → 확인
; Jobs 에서 위로 3칸 올리면 목록 끝에서 돌아 Find New Session 에 선다. 다만 0926 실측에서 목록에 들어간 직후의 Up 이 씹혀
; 바로 위 "Quit to Story Mode" 에 멈췄다. 거기서 Enter 가 나가면 스토리 모드로 나간다.
; 그래서 Up·Down 을 하나씩 누르며 목표 줄이 선택됐는지(흰 바탕) 화면으로 확인하고, 확인되기 전에는 Enter 를 보내지 않는다.
; Esc 는 쓰지 않는다: Rockstar 런처·스팀 Big Picture 가 앞에 있으면 종료 확인으로 받는다. 일시정지 메뉴는 P 로 연다.
; 단계마다 GTA 가 앞인지와 전체 멈춤 신호를 보고, 아니면 남은 키를 보내지 않는다.

; 1920x1080 실측 줄 높이(창 높이 비율): ONLINE 목록의 Find New Session, Find New Session 하위의 Invite Only Session
global SESSION_ROW_FIND := 0.726
global SESSION_ROW_INVITE := 0.276

JoinInviteOnlySession() {
    global config, gAbort

    if (!IsGTAActive())
        return

    gAbort := false
    delay := config["Settings"]["SessionMenuDelay"]

    ok := SessionStep("p", 1, delay * 3)
       && SessionStep("e", 1, delay)
       && SessionStep("Enter", 1, delay * 2)
       && SessionSelectRow("Up", SESSION_ROW_FIND, 6, delay)
       && SessionStep("Enter", 1, delay)
       && SessionSelectRow("Down", SESSION_ROW_INVITE, 3, delay)
       && SessionStep("Enter", 1, delay * 2)
       && SessionStep("Enter", 1, 0)
    if (ok)
        ShowTooltip("🔒 초대 전용 세션으로 이동 중", 2000)
    else
        ShowTooltip("세션 이동 중단: 메뉴 줄을 확인하지 못했거나 창 포커스·전체 멈춤. 열린 게임 메뉴는 직접 닫으세요", 5000)
    MacroLog("session", ok ? "invite-only ok" : "invite-only 중단")
}

; 키를 count 번 누르고(사이 간격 delay) 마지막에 delay 만큼 쉰다. GTA 가 앞이 아니거나 전체 멈춤이면 false.
SessionStep(key, count, delay) {
    global gAbort
    if (gAbort || !IsGTAActive())
        return false
    PressKey(key, count, delay)
    Sleep(delay)
    return true
}

; key 를 한 번씩 누르며 yPct 높이의 줄이 선택될 때까지 최대 maxPress 번. 못 찾으면 false (Enter 를 보내지 않게).
SessionSelectRow(key, yPct, maxPress, delay) {
    Loop maxPress {
        if (!SessionStep(key, 1, delay))
            return false
        if (SessionRowSelected(yPct))
            return true
    }
    MacroLog("session", key " x" maxPress " 로 줄(" yPct ")을 찾지 못함")
    return false
}

; 일시정지 메뉴 왼쪽 목록에서 yPct 높이의 줄이 선택(흰 바탕 F0F0F0)됐는지. 선택 안 된 줄은 거의 검다(0926 1920x1080 실측).
; 줄 오른쪽의 글자 없는 곳(가로 30~36%)만 본다.
SessionRowSelected(yPct) {
    hwnd := IsGTAActive()
    if (!hwnd)
        return false
    WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
    CoordMode("Pixel", "Screen")
    y := cy + Round(ch * yPct)
    return PixelSearch(&fx, &fy, cx + Round(cw * 0.30), y - 3, cx + Round(cw * 0.36), y + 3, 0xF0F0F0, 20)
}
