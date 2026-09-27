; === 초대 전용 세션으로 이동 ===
; 일시정지 메뉴(P) → ONLINE → Find New Session → Invite Only Session → 확인창 OK
; ONLINE 목록은 상황마다 길이가 다르다: 게임을 켠 방식에 따라 Quit to Story Mode 아래에 Quit to Main Menu·Quit Game 이 더 붙고,
; 그때는 목록이 스크롤돼 줄 높이가 달라진다(0926 15:52·16:00 실측: 줄 높이로 판정하다 Quit to Story Mode 에서 Enter 가 나감).
; 그래서 줄 높이가 아니라 오른쪽 칸의 큰 제목 글자(Find New Session / Invite Only Session)를 템플릿(Images\Session\<해상도>)으로 찾고,
; 제목이 맞을 때만 Enter 를 보낸다. 마지막 Enter 앞에서는 확인창 문구가 "quit this session" 인지 보고, 아니면 추가 입력 없이 멈춘다.
; Esc 는 쓰지 않는다: Rockstar 런처·스팀 Big Picture 가 앞에 있으면 종료 확인으로 받는다. 일시정지 메뉴는 P 로 연다.
; 단계마다 GTA 가 앞인지와 전체 멈춤 신호를 보고, 아니면 남은 키를 보내지 않는다. 성공하면 true (수익 자동화가 이 값을 본다).

; 오른쪽 칸 제목 글자 영역 / 가운데 확인창 문구 영역 (클라이언트 비율)
global SESSION_TITLE_AREA := [0.38, 0.24, 0.84, 0.36]
global SESSION_DIALOG_AREA := [0.33, 0.50, 0.67, 0.57]
; 시험 하네스는 gSessionInputGuard 콜백을 등록해 시작과 목록 탐색도 화면으로 확인한다.
; Main 의 기존 세션 이동은 콜백 없이 동작한다. 새 템플릿 실측 전에는 시험 경로만 입력을 막는다.
global SESSION_TABS_AREA := [0, 0, 1, 0.25]
global SESSION_LIST_AREA := [0.1, 0.15, 0.9, 0.95]

; resetAbort: 단축키·설정 창에서 부를 때는 새 시퀀스라 전체 멈춤 신호를 지우고 시작한다. 수익 자동화가 이동 중에 부를 때는 false 로 넘겨 End 를 삼키지 않는다
JoinInviteOnlySession(resetAbort := true) {
    global config, gAbort, SESSION_TABS_AREA, SESSION_TITLE_AREA

    if (!IsGTAActive())
        return false

    if (resetAbort)
        gAbort := false
    else if (gAbort)
        return false
    delay := config["Settings"]["SessionMenuDelay"]

    ok := SessionStep("p", 1, delay * 3, "game_hud")
       && SessionStep("e", 1, delay, "pause_map_selected", SESSION_TABS_AREA)
       && SessionStep("Enter", 1, delay * 2, "pause_online_selected", SESSION_TABS_AREA)
       && SessionSelectTitle("Up", "find_new_session", 20, delay)
       && SessionStep("Enter", 1, delay, "find_new_session", SESSION_TITLE_AREA)
       && SessionSelectTitle("Down", "invite_only", 8, delay)
       && SessionStep("Enter", 1, delay * 2, "invite_only", SESSION_TITLE_AREA)
       && SessionConfirmQuit(delay)
    if (ok)
        ShowTooltip("🔒 초대 전용 세션으로 이동 중", 2000)
    else
        ShowTooltip("세션 이동 중단: 화면 확인 실패 또는 포커스·전체 멈춤. 추가 입력을 보내지 않았습니다", 5000)
    MacroLog("session", ok ? "invite-only ok" : "invite-only 중단")
    return ok
}

; 키마다 선택적 화면 확인 콜백을 적용하고 delay 만큼 쉰다. 콜백이 false 면 키를 보내지 않는다.
SessionStep(key, count, delay, guard := "", area := "") {
    global gAbort, gSessionInputGuard
    Loop count {
        if (gAbort || !IsGTAActive())
            return false
        if (IsSet(gSessionInputGuard) && IsObject(gSessionInputGuard) && !gSessionInputGuard.Call(guard, area)) {
            MacroLog("session", "입력 중단: " key " 직전 화면 " guard " 을(를) 확인하지 못함")
            return false
        }
        ; 화면 판정 중 End·포커스 변경이 있었으면 이전 판정으로 진행하지 않는다.
        if (gAbort || !IsGTAActive())
            return false
        PressKey(key)
        Sleep(delay)
    }
    return !gAbort && IsGTAActive()
}

; key 를 한 번씩 누르며 오른쪽 칸 제목이 name 템플릿과 맞을 때까지 최대 maxPress 번. 못 찾으면 false (Enter 를 보내지 않게).
; 목록에 들어간 직후 첫 키가 씹히는 일이 잦아(0926) 누른 횟수가 아니라 제목으로 판정한다. 한도는 목록(최대 17줄)을 한 바퀴 넘게 도는 값이다
; (0926 17:02 실측: 한도 8 로는 키가 몇 번 씹히면 Find New Session 에 못 닿고 멈췄다).
SessionSelectTitle(key, name, maxPress, delay) {
    global SESSION_TITLE_AREA, SESSION_LIST_AREA
    if (TemplateSeen("Session", name, SESSION_TITLE_AREA))
        return true
    Loop maxPress {
        if (!SessionStep(key, 1, delay, "pause_online_list", SESSION_LIST_AREA))
            return false
        if (TemplateSeen("Session", name, SESSION_TITLE_AREA))
            return true
    }
    MacroLog("session", key " x" maxPress " 로 제목 " name " 을(를) 찾지 못함")
    return false
}

; 마지막 확인창이 "quit this session" 이면 Enter(OK). 다른 창이면 추가 입력 없이 false.
SessionConfirmQuit(delay) {
    global SESSION_DIALOG_AREA, gAbort
    deadline := A_TickCount + 3000
    while (A_TickCount < deadline) {
        if (gAbort || !IsGTAActive())
            return false
        if (TemplateSeen("Session", "quit_this_session", SESSION_DIALOG_AREA))
            return SessionStep("Enter", 1, 0, "quit_this_session", SESSION_DIALOG_AREA)
        Sleep(150)
    }
    MacroLog("session", "확인창 문구가 quit this session 이 아님 → 추가 입력 없이 중단")
    return false
}
