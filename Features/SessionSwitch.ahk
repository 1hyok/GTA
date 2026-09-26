; === 초대 전용 세션으로 이동 ===
; 일시정지 메뉴(P) → ONLINE → Find New Session → Invite Only Session → 확인창 OK
; ONLINE 목록은 상황마다 길이가 다르다: 게임을 켠 방식에 따라 Quit to Story Mode 아래에 Quit to Main Menu·Quit Game 이 더 붙고,
; 그때는 목록이 스크롤돼 줄 높이가 달라진다(0926 15:52·16:00 실측: 줄 높이로 판정하다 Quit to Story Mode 에서 Enter 가 나감).
; 그래서 줄 높이가 아니라 오른쪽 칸의 큰 제목 글자(Find New Session / Invite Only Session)를 템플릿(Images\Session\<해상도>)으로 찾고,
; 제목이 맞을 때만 Enter 를 보낸다. 마지막 Enter 앞에서는 확인창 문구가 "quit this session" 인지 보고, 아니면 Backspace(취소)로 빠진다.
; Esc 는 쓰지 않는다: Rockstar 런처·스팀 Big Picture 가 앞에 있으면 종료 확인으로 받는다. 일시정지 메뉴는 P 로 연다.
; 단계마다 GTA 가 앞인지와 전체 멈춤 신호를 보고, 아니면 남은 키를 보내지 않는다. 성공하면 true (수익 자동화가 이 값을 본다).

; 오른쪽 칸 제목 글자 영역 / 가운데 확인창 문구 영역 (클라이언트 비율)
global SESSION_TITLE_AREA := [0.38, 0.24, 0.84, 0.36]
global SESSION_DIALOG_AREA := [0.33, 0.50, 0.67, 0.57]

JoinInviteOnlySession() {
    global config, gAbort

    if (!IsGTAActive())
        return false

    gAbort := false
    delay := config["Settings"]["SessionMenuDelay"]

    ok := SessionStep("p", 1, delay * 3)
       && SessionStep("e", 1, delay)
       && SessionStep("Enter", 1, delay * 2)
       && SessionSelectTitle("Up", "find_new_session", 20, delay)
       && SessionStep("Enter", 1, delay)
       && SessionSelectTitle("Down", "invite_only", 8, delay)
       && SessionStep("Enter", 1, delay * 2)
       && SessionConfirmQuit(delay)
    if (ok)
        ShowTooltip("🔒 초대 전용 세션으로 이동 중", 2000)
    else
        ShowTooltip("세션 이동 중단: 메뉴 제목을 확인하지 못했거나 창 포커스·전체 멈춤. 열린 게임 메뉴는 직접 닫으세요", 5000)
    MacroLog("session", ok ? "invite-only ok" : "invite-only 중단")
    return ok
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

; key 를 한 번씩 누르며 오른쪽 칸 제목이 name 템플릿과 맞을 때까지 최대 maxPress 번. 못 찾으면 false (Enter 를 보내지 않게).
; 목록에 들어간 직후 첫 키가 씹히는 일이 잦아(0926) 누른 횟수가 아니라 제목으로 판정한다. 한도는 목록(최대 17줄)을 한 바퀴 넘게 도는 값이다
; (0926 17:02 실측: 한도 8 로는 키가 몇 번 씹히면 Find New Session 에 못 닿고 멈췄다).
SessionSelectTitle(key, name, maxPress, delay) {
    global SESSION_TITLE_AREA
    if (TemplateSeen("Session", name, SESSION_TITLE_AREA))
        return true
    Loop maxPress {
        if (!SessionStep(key, 1, delay))
            return false
        if (TemplateSeen("Session", name, SESSION_TITLE_AREA))
            return true
    }
    MacroLog("session", key " x" maxPress " 로 제목 " name " 을(를) 찾지 못함")
    return false
}

; 마지막 확인창이 "quit this session" 이면 Enter(OK). 다른 창(스토리 모드로 나가기 등)이면 Backspace(취소)로 빠지고 false.
SessionConfirmQuit(delay) {
    global SESSION_DIALOG_AREA, gAbort
    deadline := A_TickCount + 3000
    while (A_TickCount < deadline) {
        if (gAbort || !IsGTAActive())
            return false
        if (TemplateSeen("Session", "quit_this_session", SESSION_DIALOG_AREA))
            return SessionStep("Enter", 1, 0)
        Sleep(150)
    }
    MacroLog("session", "확인창 문구가 quit this session 이 아님 → Backspace 로 취소")
    SessionStep("Backspace", 1, delay)
    return false
}
