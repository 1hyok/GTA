; === 초대 전용 세션으로 이동 ===
; 일시정지 메뉴 → ONLINE → Find New Session → Invite Only Session → 확인
; Jobs 에서 위로 3칸 올리면 목록 끝에서 돌아 Find New Session 에 선다.

JoinInviteOnlySession() {
    global config

    if (!IsGTAActive())
        return

    delay := config["Settings"]["SessionMenuDelay"]

    PressKey("Esc")
    Sleep(delay * 3)
    PressKey("e")
    Sleep(delay)
    PressKey("Enter")
    Sleep(delay)
    PressKey("Up", 3, delay)
    Sleep(delay)
    PressKey("Enter")
    Sleep(delay)
    PressKey("Down")
    Sleep(delay)
    PressKey("Enter")
    Sleep(delay * 2)
    PressKey("Enter")
    ShowTooltip("🔒 초대 전용 세션으로 이동 중", 2000)
}
