; === F11 작텔 앞단: 퀵 조인 준비 ===
; F11 두 번을 두 단계로 나눈다 (Config [Settings] JobWarpQuickJoin=1 일 때).
;   1단계(준비 안 된 상태에서 F11 두 번): 보스 해제 → 폰 Quick Join → Random → Alone → Yes → 곧바로 보스 등록 → "작텔 준비됨"
;   그 사이 사용자가 직접: 준비 임무(prep) 시작 → 지도에서 작업 아이콘에 커서를 올려 "Start Job (Space)" 가 보이게 한다
;   2단계(준비됨 상태에서 F11 두 번): 기존 Alt+F4 작텔(ExecuteAltF4Teleport). 성공하면 준비 상태를 푼다
; 보스 해제는 임무 시작 전에만 된다(임무 중에는 게임이 막는다). 그래서 1단계는 늘 prep 시작 전에 돈다.
; Looking For Job 은 기다리지 않는다: Yes 까지 눌렸으면 검색은 이미 시작됐고, 바로 등록해야 검색이 작업 로비를 잡기 전에 끝난다.
;
; 옛 CEO/MC 재등록 텔레포트(MCTeleport.ahk)와 같은 순서지만, 칸 수를 세지 않고 키마다 선택된 줄을 템플릿으로 확인한다.
; 0926 옛 방식 사고: 화면을 안 보고 누른 키가 작업 로비에 들어가 로비를 나갔다. 여기서는 확인이 안 되면 그 자리에서 멈추고 더 누르지 않는다.
; 되돌리는 키는 Backspace·M 만 쓴다(Esc 금지: 런처 종료창).
;
; 템플릿: Images\JobWarp\<가로>x<세로>\*.png (없으면 그 단계에서 멈추고 gta-macro.log 에 "템플릿 없음" 이 남는다)
;   상호작용 메뉴(왼쪽 위): m_securo·m_securo_sel(CEO 맨 위 줄) / m_retire_sel(CEO 메뉴 맨 아래 Retire)
;                           m_mc·m_mc_sel(MC 맨 위 줄) / m_mc_disband_sel(MC 메뉴 맨 아래 Disband Club)
;                           m_boss·m_boss_sel(Register as a Boss) / m_ceo_sel(SecuroServ CEO) / m_mcpres_sel(Motorcycle Club President)
;                           m_start_org_sel(Start an Organization) / m_start_mc_sel(Start a Motorcycle Club)
;   폰(오른쪽 아래): ph_quickjoin_sel(홈 화면에서 Quick Join 앱이 골라진 상태) / qj_random_sel / qj_alone_sel / qj_yes_sel
;   메뉴 제목 확인은 수익 자동화가 이미 가진 Images\Earn\<해상도>\m_title.png 를 같이 쓴다.
; _sel 은 선택(흰 바탕) 줄, 접미사 없는 것은 선택 안 된 줄이다. 줄 템플릿은 글자만 남기고 가장자리를 FF00FF(투명)로 뜬다.

global gJobWarpArmed := false     ; 1단계를 마치고 2단계(F11 두 번)를 기다리는 중
global gJobWarpArmedAt := 0
global gQuickJoinRunning := false
global gQuickJoinFail := ""       ; 1단계가 멈춘 까닭 (오버레이·툴팁)

global JW_MENU_AREA := [0, 0, 0.27, 0.55]
global JW_PHONE_AREA := [0.6, 0.3, 1, 1]

; F11 두 번의 진입점 (HotkeyManager 의 TeleportAltF4 액션)
JobWarpKey() {
    global config, gJobWarpArmed, gJobWarpArmedAt
    s := config["Settings"]
    if (!s.Get("JobWarpQuickJoin", 0))
        return ExecuteAltF4Teleport()
    ; 준비해 두고 오래 지나면(다른 세션으로 옮겼거나 prep 를 그만둔 경우) 처음부터 다시 한다
    if (gJobWarpArmed && A_TickCount - gJobWarpArmedAt > s.Get("JobWarpArmMaxMin", 30) * 60000) {
        gJobWarpArmed := false
        MacroLog("jobwarp", "준비 상태가 오래돼 풀림")
    }
    if (!gJobWarpArmed)
        return QuickJoinPrep()
    ok := ExecuteAltF4Teleport()
    if (ok)
        gJobWarpArmed := false
    return ok
}

JobWarpArmedText() {
    global gJobWarpArmed, gQuickJoinRunning
    if (gQuickJoinRunning)
        return "퀵 조인 준비 중"
    return gJobWarpArmed ? "작텔 준비됨 · prep 시작 → 작업 아이콘 → F11 두 번" : ""
}

QuickJoinPrep() {
    global config, gAbort, gQuickJoinRunning, gQuickJoinFail, gJobWarpArmed, gJobWarpArmedAt
    if (!IsGTAActive() || IsTeleportRunning())
        return false
    if (IsSet(gEarnBusy) && gEarnBusy) {
        ShowTooltip("작텔 준비: 수익 자동화가 진행 중", 1500)
        return false
    }
    gAbort := false
    gQuickJoinRunning := true
    gQuickJoinFail := ""
    role := config["Settings"].Get("JobWarpBossRole", "CEO")
    ok := false
    try {
        ShowTooltip("🔁 작텔 준비: 보스 해제 → 퀵 조인 → " role " 등록", 2000)
        ok := JWRetireBoss() && JWPhoneQuickJoin() && JWRegisterBoss(role)
    } finally {
        gQuickJoinRunning := false
        JWMenuClose()
    }
    if (ok) {
        gJobWarpArmed := true
        gJobWarpArmedAt := A_TickCount
        ShowTooltip("✅ 작텔 준비됨: prep 시작 → 지도에서 작업 아이콘에 커서 → F11 두 번", 5000)
    } else {
        ShowTooltip("⚠ 작텔 준비 중단: " (gQuickJoinFail = "" ? "포커스 이탈 또는 전체 멈춤" : gQuickJoinFail) "`n더 누르지 않았습니다", 6000)
    }
    MacroLog("jobwarp", "퀵 조인 준비 " (ok ? "ok" : "중단: " gQuickJoinFail))
    return ok
}

; --- 보스 해제: 맨 위 줄이 Register as a Boss 면 이미 해제, SecuroServ 면 Retire, Motorcycle Club 이면 Disband Club ---
JWRetireBoss() {
    global config, JW_MENU_AREA
    if (!JWMenuOpen())
        return false
    if (JWSeen("m_boss_sel", JW_MENU_AREA) || JWSeen("m_boss", JW_MENU_AREA))
        return JWMenuClose()
    if (JWSeen("m_securo_sel", JW_MENU_AREA) || JWSeen("m_securo", JW_MENU_AREA)) {
        top := "m_securo_sel", bottom := "m_retire_sel", label := "CEO Retire"
    } else if (JWSeen("m_mc_sel", JW_MENU_AREA) || JWSeen("m_mc", JW_MENU_AREA)) {
        top := "m_mc_sel", bottom := "m_mc_disband_sel", label := "MC Disband Club"
    } else {
        return JWFail("보스 상태를 모름 (메뉴 맨 위 줄이 Register as a Boss·SecuroServ·Motorcycle Club 어느 것도 아님)")
    }
    if (!JWSelectRow(top, JW_MENU_AREA, "Up", 4) || !JWPress("Enter"))
        return JWFail(label ": 맨 위 줄을 고르지 못함")
    ; 해제 줄은 하위 메뉴 맨 아래라 Up 으로 한 바퀴 돌아간다
    if (!JWSelectRow(bottom, JW_MENU_AREA, "Up", 12))
        return JWFail(label ": 해제 줄을 찾지 못함 (임무 중이면 해제가 막힌다)")
    if (!JWPress("Enter"))
        return false
    if (!JWSleep(config["Settings"].Get("JobWarpRetireWaitMs", 2500)))
        return false
    ; 해제됐는지 메뉴로 확인한다. 게임이 메뉴를 닫았으면 다시 연다
    if (!JWMenuOpen())
        return false
    if (!(JWSeen("m_boss_sel", JW_MENU_AREA) || JWSeen("m_boss", JW_MENU_AREA)))
        return JWFail(label ": 해제 뒤 메뉴에 Register as a Boss 가 안 보임")
    return JWMenuClose()
}

; --- 폰: Up 으로 열고 Quick Join 앱 → Random → Alone → Yes ---
; 폰 홈은 마지막으로 고른 앱을 기억하므로 칸 수로 가지 않는다. 3x3 격자를 뱀 모양(→→↓←←↓→→)으로 돌면 어디서 시작해도 9칸을 다 본다.
JWPhoneQuickJoin() {
    global config, JW_PHONE_AREA
    s := config["Settings"]
    if (!JWPress("Up"))
        return false
    if (!JWSleep(s.Get("PhoneOpenDelay", 1000)))
        return false
    found := JWSeen("ph_quickjoin_sel", JW_PHONE_AREA)
    for key in ["Right", "Right", "Down", "Left", "Left", "Down", "Right", "Right"] {
        if (found)
            break
        if (!JWPress(key, s.Get("PhoneControlDelay", 150) + 250))
            return false
        found := JWSeen("ph_quickjoin_sel", JW_PHONE_AREA)
    }
    if (!found)
        return JWFail("폰: Quick Join 앱을 찾지 못함")
    if (!JWPress("Enter", 600))
        return false
    ; 목록에 들어간 직후 첫 키가 씹히는 일이 잦아 누른 횟수가 아니라 선택 줄로 판정한다
    ; Yes 확인이 폰 안에 뜨는지 화면 가운데 알림으로 뜨는지 아직 실측하지 않아 Yes 는 화면 전체에서 찾는다
    for step in [["qj_random_sel", "Up", 8, "Random", JW_PHONE_AREA], ["qj_alone_sel", "Down", 6, "Alone", JW_PHONE_AREA], ["qj_yes_sel", "Down", 3, "Yes", [0, 0, 1, 1]]] {
        if (!JWWaitSeen(step[1], step[5], 1500) && !JWSelectRow(step[1], step[5], step[2], step[3], false))
            return JWFail("폰: " step[4] " 줄을 찾지 못함")
        if (!JWPress("Enter", 500))
            return false
    }
    MacroLog("jobwarp", "퀵 조인 검색 시작 (Yes)")
    return true
}

; --- 보스 등록: M → Register as a Boss → SecuroServ CEO / Motorcycle Club President → Start ... ---
JWRegisterBoss(role) {
    global config, JW_MENU_AREA
    ; Yes 뒤 폰(확인 줄)이 닫혀야 M 이 먹는다
    deadline := A_TickCount + 3000
    while (A_TickCount < deadline && JWSeen("qj_yes_sel", [0, 0, 1, 1])) {
        if (!JWSleep(150))
            return false
    }
    if (!JWMenuOpen())
        return false
    if (role = "MC")
        sub := "m_mcpres_sel", start := "m_start_mc_sel", top := "m_mc"
    else
        sub := "m_ceo_sel", start := "m_start_org_sel", top := "m_securo"
    if (!JWSelectRow("m_boss_sel", JW_MENU_AREA, "Down", 4) || !JWPress("Enter"))
        return JWFail(role " 등록: Register as a Boss 줄을 찾지 못함")
    if (!JWSelectRow(sub, JW_MENU_AREA, "Down", 3) || !JWPress("Enter"))
        return JWFail(role " 등록: 보스 종류 줄을 찾지 못함")
    if (!JWSelectRow(start, JW_MENU_AREA, "Down", 3) || !JWPress("Enter"))
        return JWFail(role " 등록: Start 줄을 찾지 못함")
    if (!JWSleep(config["Settings"].Get("JobWarpRegisterWaitMs", 2500)))
        return false
    ; 등록이 끝나면 게임이 메뉴를 닫는다. 다시 열어 맨 위 줄이 보스 메뉴인지 본다
    if (!JWMenuOpen())
        return false
    if (!(JWSeen(top "_sel", JW_MENU_AREA) || JWSeen(top, JW_MENU_AREA)))
        return JWFail(role " 등록: 등록 뒤 메뉴 맨 위에 보스 줄이 안 보임")
    return JWMenuClose()
}

; === 공용 ===
JWFail(reason) {
    global gQuickJoinFail
    gQuickJoinFail := reason
    MacroLog("jobwarp", "멈춤: " reason)
    return false
}

JWAborted() {
    global gAbort
    return gAbort || !IsGTAActive()
}

JWSeen(name, area) {
    return TemplateSeen("JobWarp", name, area)
}

JWPress(key, afterMs := 0) {
    global config
    if (JWAborted())
        return false
    PressKey(key)
    return JWSleep(afterMs ? afterMs : config["Settings"]["MenuControlDelay"] + 150)
}

JWSleep(ms) {
    deadline := A_TickCount + ms
    while (A_TickCount < deadline) {
        if (JWAborted())
            return false
        Sleep(Min(100, Max(1, deadline - A_TickCount)))
    }
    return true
}

JWWaitSeen(name, area, timeoutMs) {
    deadline := A_TickCount + timeoutMs
    Loop {
        if (JWAborted())
            return false
        if (JWSeen(name, area))
            return true
        if (A_TickCount >= deadline)
            return false
        Sleep(150)
    }
}

; key 를 한 번씩 누르며 name(선택된 줄)이 보일 때까지 최대 maxPress 번. 처음부터 보이면 누르지 않는다.
; inMenu 가 true 면 누르기 전마다 상호작용 메뉴가 열려 있는지 본다(닫혔는데 방향키를 보내면 캐릭터·폰이 움직인다)
JWSelectRow(name, area, key, maxPress, inMenu := true) {
    if (JWSeen(name, area))
        return true
    Loop maxPress {
        if (inMenu && !JWMenuIsOpen())
            return JWFail("선택 이동: 상호작용 메뉴 제목을 확인하지 못함")
        if (!JWPress(key))
            return false
        if (JWSeen(name, area))
            return true
    }
    return false
}

; 상호작용 메뉴 제목(INTERACTION MENU)은 수익 자동화의 템플릿을 같이 쓴다
JWMenuIsOpen() {
    global JW_MENU_AREA
    return TemplateSeen("Earn", "m_title", JW_MENU_AREA)
}

JWMenuOpen() {
    global config
    if (JWMenuIsOpen())
        return true
    if (!JWPress("m", config["Settings"]["MenuOpenDelay"]))
        return false
    if (!JWWaitMenu(true, 2500))
        return JWFail("상호작용 메뉴가 열리지 않음")
    return true
}

; 열려 있으면 M 으로 닫고 닫혔는지 본다. 하위 메뉴에서도 M 한 번에 전체가 닫힌다
JWMenuClose() {
    if (!JWMenuIsOpen())
        return true
    if (!JWPress("m", 300))
        return false
    return JWWaitMenu(false, 2500)
}

JWWaitMenu(open, timeoutMs) {
    deadline := A_TickCount + timeoutMs
    Loop {
        if (JWAborted())
            return false
        if (JWMenuIsOpen() = open)
            return true
        if (A_TickCount >= deadline)
            return false
        Sleep(150)
    }
}
