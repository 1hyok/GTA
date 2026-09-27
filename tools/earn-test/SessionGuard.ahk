; 시험 하네스 전용 세션 화면 확인. SessionSwitch.ahk 의 영역 상수와 공용 TemplateSeen 을 사용한다.
; gSessionInputGuard 에 이 함수 또는 사용자 입력 감시를 함께 하는 콜백을 등록한다.
; 실측되지 않은 템플릿은 TemplateSeen 이 false 와 파일 이름을 로그에 남겨 입력을 막는다.
SessionScreenSeen(guard, area) {
    global SESSION_TITLE_AREA, SESSION_TABS_AREA
    if (guard = "game_hud")
        return SessionHudVisible()
    if (guard = "")
        return false
    if (guard = "pause_online_list")
        return (TemplateSeen("Session", "pause_online_selected", SESSION_TABS_AREA)
            && TemplateSeen("Session", guard, [0.16, 0.222, 0.388, 0.83]))
            || TemplateSeen("Session", "find_new_session", SESSION_TITLE_AREA)
            || TemplateSeen("Session", "invite_only", SESSION_TITLE_AREA)
    return TemplateSeen("Session", guard, area)
}

; EarnCore 포함 여부와 무관하게 게임 HUD 의 체력 막대를 확인한다(1920x1080 실측: 0x4C8F4C, y1049~1057).
SessionHudVisible() {
    hwnd := IsGTAActive()
    if (!hwnd)
        return false
    prev := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        CoordMode("Pixel", "Screen")
        return PixelSearch(&fx, &fy, cx + Round(cw * 0.021), cy + Round(ch * 0.972),
            cx + Round(cw * 0.05), cy + Round(ch * 0.978), 0x4C8F4C, 30)
    } finally {
        if (prev)
            DllCall("SetThreadDpiAwarenessContext", "ptr", prev, "ptr")
    }
}
