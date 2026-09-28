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
;   1920x1080 은 tools\build-jobwarp-templates.ps1 이 docs\evidence\2026-09-27-jobwarp\(저택 안)과 2026-09-28-jobwarp-outdoor\(실외 밤·동틀 녘·낮)
;   실측 화면을 상태마다 여러 장 겹쳐 뜨고, 같은 스크립트가 모든 원본에 대 보는 시험까지 한다(-TestOnly).
;   상호작용 메뉴(왼쪽 위): m_securo·m_securo_sel(CEO 맨 위 줄 SecuroServ CEO) / m_retire_sel(CEO 하위 메뉴 맨 아래 Retire)
;                           m_boss·m_boss_sel(Register as a Boss) / m_ceo_sel(SecuroServ CEO) / m_start_org_sel(Start an Organization)
;                           m_sub_boss·m_sub_securo(하위 메뉴 제목 REGISTER AS A BOSS·SECUROSERV, 메뉴가 열려 있는지 볼 때 m_title 과 같이 쓴다)
;   MC 쪽(m_mc·m_mc_sel·m_mc_disband_sel·m_mcpres_sel·m_start_mc_sel, MC 하위 메뉴 제목)은 아직 없다. JobWarpBossRole=MC 나 MC 상태에서는 그 단계에서 멈춘다.
;   폰(오른쪽 아래): ph_quickjoin_sel(홈 화면에서 Quick Join 앱이 골라진 상태) / qj_random_sel / qj_alone_sel / qj_yes_sel, 각각 어두운 폰용 대체 *_dim(JW_ALT)
;   메뉴 제목 확인은 수익 자동화가 이미 가진 Images\Earn\<해상도>\m_title.png 를 같이 쓴다.
; _sel 은 선택(흰 바탕·폰은 파란 바탕) 줄, 접미사 없는 것은 선택 안 된 줄이다. 원본마다 값이 갈리는 칸(반 픽셀 어긋난 글자 가장자리, 뒤 배경이 비치는 칸)은
; FF00FF(투명)로 뜨고, 선택 안 된 Register as a Boss(m_boss)만 흰 글자 속 + 회색 바탕 칸으로 떠서 허용 오차 70 으로 찾는다(JW_VARIATION, 까닭은 스크립트 머리말).
; "SecuroServ CEO" 선택 줄은 등록 하위 메뉴와 CEO 메인 메뉴에서 글자·자리가 같아, m_ceo_sel·m_securo_sel·m_securo 는 바로 위 제목 줄까지 같이 떴다.
;
; 0928 실측(1920x1080, 실외 Vinewood 길가, 밤·동틀 녘·흐린 낮): 실외에서 F11 이 "보스 상태를 모름"·"해제 뒤 Register as a Boss 가 안 보임" 으로 멈춘 까닭은
;   배경이 아니라 줄 자리였다. 메뉴 줄 간격이 37.5px 라 짝수 번째 줄은 반 픽셀 아래에 그려지는데, 실외 해제 상태는 Quick GPS → Register as a Boss(2번째)라
;   저택 안(3번째 줄)에서 뜬 m_boss·m_boss_sel 이 글자 가장자리에서 다 틀렸다. 폰의 Alone 도 세션에 친구가 없으면 Random 안에 한 줄뿐(1번째 줄)이라 같은 일이 난다.
;   메뉴 제목 줄(m_title·m_sub_*)은 불투명이라 실외에서도 차이 0 이었다. 선택 안 된 줄 바탕은 약 60% 불투명한 검정이라 뒤 배경이 0.35~0.41 배로 비치고,
;   폰 화면은 장면 밝기에 따라 통째로 어두워진다(저택 안 1.0, 동틀 녘 약 0.87, 흐린 낮 약 0.93).
;
; 0927 실측(1920x1080, 저택 안):
;   메뉴 맨 위 줄은 자리마다 다르다. 저택 안 해제 상태는 Mansion Management → Quick GPS → Register as a Boss(3번째), CEO 면 SecuroServ CEO 가 맨 위로 온다.
;   메뉴는 열 때마다 맨 위 줄에 커서가 있다. 하위 메뉴에서 M 한 번이면 전체가 닫힌다. Retire·Start an Organization 은 확인 창 없이 되고 게임이 메뉴를 닫는다.
;   앉아 있다 일어나는 동안 Register as a Boss 줄이 잠깐 빠졌다(12줄 → 11줄 → 12줄). 그래서 보스 상태 판정은 잠깐 기다려 다시 본다.
;   폰 홈은 두 쪽이다. Quick Join 은 2쪽 첫 칸(2쪽은 Quick Join·Settings 두 칸)이고 1쪽 3x3 은 Email·Messages·Contacts / (파란 > 아이콘)·Job List·Vinewood Club / Snapmatic·Internet·SecuroServ.
;   1쪽 오른쪽 끝 칸(어느 줄이든)에서 Right 면 2쪽 Quick Join, 2쪽에서 Right 는 두 칸 사이를 돈다. 그래서 Right 만 눌러도 어디서 시작하든 3번 안에 닿는다.
;   Quick Join 목록은 늘 맨 위(Series Modes)에서 열리고 Random 은 맨 아래라 Up 한 번. Random 안은 Friends in Session·Alone 두 줄이라 Down 한 번.
;   Alone 에 Enter 면 폰 안에 "Are you sure?" 한 줄이 이미 골라진 채로 뜬다(화면 가운데 알림이 아니다). Backspace 는 확인 줄에서 Quick Join 목록 맨 위로 돌아간다.
;   F11 실제 시험(23:12): Yes 에 Enter 하면 폰이 저절로 내려가고 화면에 Looking For Job 문구는 안 보였다. Yes 뒤 약 3.5초에 Start an Organization,
;   약 7초에 "퀵 조인 준비 ok". 그 뒤 95초 동안 작업 로비로 끌려가지 않았다(검색이 등록으로 끝났다는 표시가 화면에 따로 뜨지는 않는다).

; 설정 기본값. ConfigLoader 는 기본값 표에 있는 키만 Config.ini 에서 읽으므로, BotWarp.ahk 처럼 LoadConfig() 앞(이 파일은 TeleportBase.ahk 끝에서 포함된다)에 표에 더한다.
; 0927 실측: 이것 없이 JobWarpQuickJoin=1 로 두고 F11 두 번을 보냈더니 값이 0 으로 읽혀 퀵 조인 준비 대신 곧바로 Alt+F4 작텔(Space·Enter·Alt+F4)이 돌았다.
JobWarpAddDefaults()
JobWarpAddDefaults() {
    global CONFIG_DEFAULTS
    for key, value in Map("JobWarpQuickJoin", 0, "JobWarpBossRole", "CEO", "JobWarpArmMaxMin", 30,
        "JobWarpRetireWaitMs", 2500, "JobWarpRegisterWaitMs", 2500)
        CONFIG_DEFAULTS["Settings"][key] := value
}

global gJobWarpArmed := false     ; 1단계를 마치고 2단계(F11 두 번)를 기다리는 중
global gJobWarpArmedAt := 0
global gQuickJoinRunning := false
global gQuickJoinFail := ""       ; 1단계가 멈춘 까닭 (오버레이·툴팁)

global JW_MENU_AREA := [0, 0, 0.27, 0.55]
; 폰 화면은 1920x1080 에서 x 1600~1870, y 645~1080 에 선다(0928 실외 캡처). 영역을 넓게 잡으면 없는 템플릿을 찾는 데 한 번에 약 1초가 걸려
; 폰 둘레만 남겼다(0928 계측: 폰 열기·앱 찾기가 전체 1단계의 절반)
global JW_PHONE_AREA := [0.8, 0.55, 1, 1]
; 템플릿마다 ImageSearch 허용 오차(없는 이름은 40). tools\build-jobwarp-templates.ps1 의 $variation 과 같아야 한다.
; m_boss 의 바탕 칸은 회색 55 라 70 이면 0~125 를 받는다: 뒤가 어두운 실내(바탕 0)부터 하얀 하늘(바탕 약 105)까지 맞고, 선택 줄의 밝은 바탕(192 이상)은 떨어진다
global JW_VARIATION := Map("m_boss", 70)
; 폰 템플릿은 값을 0.82 배로 낮춘 대체(_dim)를 하나 더 두고 둘 중 하나가 보이면 찾은 것으로 친다. 폰 화면은 3D 로 그려져 장면에 따라 통째로 어두워지는데
; (0928 실측 저택 안 1.0, 동틀 녘 0.87, 흐린 낮 0.93) 한 장으로는 *40 안에서 약 0.83 까지만 덮어서다. 대체까지 선형 밝기 모의로 약 0.65 까지 덮는다
global JW_ALT := Map("ph_quickjoin_sel", "ph_quickjoin_sel_dim", "qj_random_sel", "qj_random_sel_dim",
    "qj_alone_sel", "qj_alone_sel_dim", "qj_yes_sel", "qj_yes_sel_dim")

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
    JWLap("")
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
    MacroLog("jobwarp", JWLap("끝"))
    return ok
}

; 단계별 소요(ms). JWLap("") 로 시작하고, 단계 끝마다 이름을 넘기고, JWLap("끝") 이 "총 N ms: 단계 ms · ..." 한 줄을 돌려준다
JWLap(step) {
    static t0 := 0, at := 0, laps := ""
    now := A_TickCount
    if (step = "") {
        t0 := at := now, laps := ""
        return ""
    }
    if (step = "끝")
        return "소요 총 " (now - t0) "ms:" laps
    laps .= " " step " " (now - at)
    at := now
    return ""
}

; --- 보스 해제: 메뉴에 Register as a Boss 줄이 보이면 이미 해제, 맨 위가 SecuroServ CEO 면 Retire, Motorcycle Club 이면 Disband Club ---
JWRetireBoss() {
    global config, JW_MENU_AREA
    if (!JWMenuOpen())
        return false
    JWLap("메뉴열기")
    ; 앉았다 일어나는 동안처럼 Register as a Boss 줄이 잠깐 빠질 때가 있어(0927 실측) 바로 "모름" 으로 멈추지 않고 조금 기다려 다시 본다
    state := ""
    deadline := A_TickCount + 2000
    Loop {
        if (JWSeen("m_boss_sel", JW_MENU_AREA) || JWSeen("m_boss", JW_MENU_AREA))
            state := "free"
        else if (JWSeen("m_securo_sel", JW_MENU_AREA) || JWSeen("m_securo", JW_MENU_AREA))
            state := "ceo"
        else if (JWSeen("m_mc_sel", JW_MENU_AREA) || JWSeen("m_mc", JW_MENU_AREA))
            state := "mc"
        if (state != "" || A_TickCount >= deadline)
            break
        if (!JWSleep(200))
            return false
    }
    JWLap("보스판정")
    if (state = "free")
        return JWMenuClose() && !JWLap("메뉴닫기")
    if (state = "ceo") {
        top := "m_securo_sel", bottom := "m_retire_sel", label := "CEO Retire"
    } else if (state = "mc") {
        top := "m_mc_sel", bottom := "m_mc_disband_sel", label := "MC Disband Club"
    } else {
        return JWFail("보스 상태를 모름 (메뉴에 Register as a Boss·SecuroServ CEO·Motorcycle Club 어느 줄도 안 보임)")
    }
    if (!JWSelectRow(top, JW_MENU_AREA, "Up", 4) || !JWPress("Enter"))
        return JWFail(label ": 맨 위 줄을 고르지 못함")
    ; 해제 줄은 하위 메뉴 맨 아래라 Up 으로 한 바퀴 돌아간다 (CEO 는 Hire Associates 에서 Up 한 번이면 Retire, 0927 실측)
    if (!JWSelectRow(bottom, JW_MENU_AREA, "Up", 12))
        return JWFail(label ": 해제 줄을 찾지 못함 (임무 중이면 해제가 막힌다)")
    if (!JWPress("Enter"))
        return false
    JWLap("해제")
    if (!JWSleep(config["Settings"].Get("JobWarpRetireWaitMs", 2500)))
        return false
    ; 해제됐는지 메뉴로 확인한다
    if (!JWReopenMenu())
        return false
    if (!(JWWaitSeen("m_boss_sel", JW_MENU_AREA, 2000) || JWSeen("m_boss", JW_MENU_AREA)))
        return JWFail(label ": 해제 뒤 메뉴에 Register as a Boss 가 안 보임")
    JWLap("해제확인")
    return JWMenuClose() && !JWLap("메뉴닫기")
}

; --- 폰: Up 으로 열고 Quick Join 앱 → Random → Alone → Yes ---
; 폰 홈은 마지막으로 고른 앱을 기억하므로 칸 수로 가지 않는다. Quick Join 은 홈 2쪽 첫 칸이고, 1쪽 오른쪽 끝 칸에서 Right 면 거기로 넘어가며
; 2쪽에서 Right 는 Quick Join·Settings 사이를 돈다(0927 실측). 그래서 Right 만 누르면 어디서 시작하든 3번 안에 닿는다. 씹힐 몫까지 6번.
JWPhoneQuickJoin() {
    global config, JW_PHONE_AREA
    s := config["Settings"]
    if (!JWPress("Up"))
        return false
    ; 폰이 뜨는 동안 기다리되, Quick Join 이 이미 골라져 있으면 바로 넘어간다
    ; 폰은 열 때 1쪽에서 시작해 Quick Join(2쪽)이 처음부터 보일 일이 드물다. 폴링하면 폰 영역 검색(대체 템플릿까지 두 번)이 겹쳐
    ; 1초 대기가 2.3초가 됐다(0928 계측). 고정으로 기다린 뒤 한 번만 본다
    if (!JWSleep(s.Get("PhoneOpenDelay", 1000) - 300))
        return false
    found := JWSeen("ph_quickjoin_sel", JW_PHONE_AREA)
    JWLap("폰열기")
    Loop 6 {
        if (found)
            break
        if (!JWPress("Right", s.Get("PhoneControlDelay", 150) + 50))
            return false
        found := JWSeen("ph_quickjoin_sel", JW_PHONE_AREA)
    }
    if (!found)
        return JWFail("폰: Quick Join 앱을 찾지 못함")
    ; 다음 줄은 아래에서 선택 줄이 보일 때까지 기다리므로 Enter 뒤 고정 대기는 짧게 둔다
    if (!JWPress("Enter", 150))
        return false
    JWLap("앱찾기")
    ; 목록에 들어간 직후 첫 키가 씹히는 일이 잦아 누른 횟수가 아니라 선택 줄로 판정한다
    ; 목록은 맨 위에서 열려 Random(맨 아래)은 Up, Alone 은 Friends in Session 다음 줄이라 Down. Yes 는 폰 안의 "Are you sure?" 한 줄이 이미 골라진 채로 뜬다(0927 실측)
    for step in [["qj_random_sel", "Up", 8, "Random"], ["qj_alone_sel", "Down", 6, "Alone"], ["qj_yes_sel", "Down", 3, "Yes"]] {
        ; Random 은 목록 맨 아래라 처음부터 보일 일이 없어 오래 기다리지 않는다(0928 계측: 1.5초 그대로 버려짐)
        if (!JWWaitSeen(step[1], JW_PHONE_AREA, step[4] = "Random" ? 300 : 1500) && !JWSelectRow(step[1], JW_PHONE_AREA, step[2], step[3], false))
            return JWFail("폰: " step[4] " 줄을 찾지 못함")
        if (!JWPress("Enter", 150))
            return false
        JWLap(step[4])
    }
    MacroLog("jobwarp", "퀵 조인 검색 시작 (Yes)")
    return true
}

; --- 보스 등록: M → Register as a Boss → SecuroServ CEO / Motorcycle Club President → Start ... ---
JWRegisterBoss(role) {
    global config, JW_MENU_AREA, JW_PHONE_AREA
    ; Yes 뒤 폰(확인 줄)이 닫혀야 M 이 먹는다
    deadline := A_TickCount + 3000
    while (A_TickCount < deadline && JWSeen("qj_yes_sel", JW_PHONE_AREA)) {
        if (!JWSleep(150))
            return false
    }
    ; 폰이 닫히는 애니메이션 동안 M 이 씹힌다(0928 계측: 바로 누르면 2.4초 걸림). 조금 기다렸다 누른다
    if (!JWSleep(400))
        return false
    JWLap("폰닫힘")
    if (!JWMenuOpen())
        return false
    JWLap("메뉴열기")
    if (role = "MC")
        sub := "m_mcpres_sel", start := "m_start_mc_sel", top := "m_mc"
    else
        sub := "m_ceo_sel", start := "m_start_org_sel", top := "m_securo"
    if (!JWSelectRow("m_boss_sel", JW_MENU_AREA, "Down", 4) || !JWPress("Enter"))
        return JWFail(role " 등록: Register as a Boss 줄을 찾지 못함")
    JWLap("Register")
    if (!JWSelectRow(sub, JW_MENU_AREA, "Down", 3) || !JWPress("Enter"))
        return JWFail(role " 등록: 보스 종류 줄을 찾지 못함")
    JWLap(role)
    if (!JWSelectRow(start, JW_MENU_AREA, "Down", 3) || !JWPress("Enter"))
        return JWFail(role " 등록: Start 줄을 찾지 못함")
    JWLap("Start")
    if (!JWSleep(config["Settings"].Get("JobWarpRegisterWaitMs", 2500)))
        return false
    JWLap("등록대기")
    ; 등록이 끝나면 게임이 메뉴를 닫는다. 다시 열어 맨 위 줄이 보스 메뉴인지 본다
    if (!JWReopenMenu())
        return false
    ; 메뉴가 닫히자마자 다시 열면 보스 줄이 조금 늦게 뜰 수 있어 2초까지 다시 본다
    if (!(JWWaitSeen(top "_sel", JW_MENU_AREA, 2000) || JWSeen(top, JW_MENU_AREA)))
        return JWFail(role " 등록: 등록 뒤 메뉴 맨 위에 보스 줄이 안 보임")
    JWLap("등록확인")
    return JWMenuClose() && !JWLap("메뉴닫기")
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
    global JW_VARIATION, JW_ALT
    fx := 0, fy := 0
    v := JW_VARIATION.Get(name, 40)
    if (TemplateSeen("JobWarp", name, area, &fx, &fy, v))
        return true
    return JW_ALT.Has(name) && TemplateSeen("JobWarp", JW_ALT[name], area, &fx, &fy, v)
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

; 상호작용 메뉴 제목(INTERACTION MENU)은 수익 자동화의 템플릿을 같이 쓴다. 하위 메뉴에서는 제목 줄이 바뀌어
; 이 기능이 들어가는 하위 메뉴(REGISTER AS A BOSS, SECUROSERV, SECUROSERV CEO)의 제목도 본다
JWMenuIsOpen() {
    global JW_MENU_AREA
    return TemplateSeen("Earn", "m_title", JW_MENU_AREA) || JWSeen("m_sub_boss", JW_MENU_AREA) || JWSeen("m_sub_securo", JW_MENU_AREA)
}

; 해제·등록(Enter) 뒤에는 게임이 메뉴를 스스로 닫는다(0927 실측). 아직 하위 메뉴가 떠 있으면 M 으로 닫고 다시 연다
JWReopenMenu() {
    if (!JWWaitMenu(false, 3000) && !JWMenuClose())
        return false
    return JWMenuOpen()
}

JWMenuOpen() {
    global config
    if (JWMenuIsOpen())
        return true
    ; 폰이 닫히는 중처럼 게임이 M 을 씹을 때가 있어(0928 실측: Yes 직후), 안 열렸을 때만 M 을 다시 보낸다(최대 3번)
    Loop 3 {
        if (!JWPress("m", config["Settings"]["MenuOpenDelay"]))
            return false
        if (JWWaitMenu(true, 800))
            return true
    }
    return JWFail("상호작용 메뉴가 열리지 않음")
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
