; === 초대 전용 세션으로 이동 ===
; 일시정지 메뉴(P) → ONLINE → Find New Session → Invite Only Session → 확인
; Jobs 에서 위로 3칸 올리면 목록 끝에서 돌아 Find New Session 에 선다.
; Esc 는 쓰지 않는다: Rockstar 런처·스팀 Big Picture 가 앞에 있으면 종료 확인으로 받는다. 일시정지 메뉴는 P 로 연다.
; 단계마다 GTA 가 앞인지와 전체 멈춤 신호를 보고, 아니면 남은 키를 보내지 않는다.

JoinInviteOnlySession() {
    global config, gAbort

    if (!IsGTAActive())
        return

    gAbort := false
    delay := config["Settings"]["SessionMenuDelay"]

    ok := SessionStep("p", 1, delay * 3)
       && SessionStep("e", 1, delay)
       && SessionStep("Enter", 1, delay)
       && SessionStep("Up", 3, delay)
       && SessionStep("Enter", 1, delay)
       && SessionStep("Down", 1, delay)
       && SessionStep("Enter", 1, delay * 2)
       && SessionStep("Enter", 1, 0)
    ShowTooltip(ok ? "🔒 초대 전용 세션으로 이동 중" : "세션 이동: 중단됨 (창 포커스 또는 전체 멈춤)", 2000)
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
