; === 디스코드 오버레이(DiscordChatHUD) 함께 띄우기 ===
; DiscordChatHUD 는 남이 만든 별도 프로그램이다(실행 파일만 배포, hud.wukwookoock.online). Main 을 켜면 같이 띄워 따로 실행할 필요를 없앤다.
; 이미 떠 있으면(HUD 본체나 설정·로그인 창) 건드리지 않는다. 경로가 비었거나 파일이 없으면 아무것도 안 한다.
; 띄우면 시작 때 자동 업데이트·로그인 창이 GTA 포커스를 가져간다(1003 19:55 실측: 업데이트 뒤 설정 창이 떠 수익 작업이 중단됐다).
; GTA 가 앞이었으면 1분 동안 HUD 창이 앞으로 올 때마다 GTA 를 다시 앞으로 가져온다. 로그인 창은 작업 표시줄에 남는다.
StartDiscordHUD() {
    global config, GTA_WIN
    path := config["Settings"]["DiscordHUDPath"]
    if (path = "")
        return false
    path := StrReplace(path, "%LOCALAPPDATA%", EnvGet("LOCALAPPDATA"))
    if (!FileExist(path))
        return false
    if (ProcessExist("DiscordChatHUD.exe") || ProcessExist("DiscordChatHUD_Config.exe"))
        return false
    SplitPath(path, , &dir)
    gtaWasActive := WinExist(GTA_WIN) && WinActive(GTA_WIN)
    try Run('"' path '"', dir)
    catch as e {
        MacroLog("hud", "디코 오버레이 실행 실패: " e.Message)
        return false
    }
    MacroLog("hud", "디코 오버레이 실행: " path)
    if (gtaWasActive)
        DiscordHUDKeepGTAFront(A_TickCount + 60000)
    return true
}

DiscordHUDKeepGTAFront(deadline) {
    global GTA_WIN
    static loginNoticed := false
    ; 로그인 창(제목 "계정 연결")이 뜨면 GTA 뒤로 숨기 전에 한 번 알린다(1003 20:22 실측: 강제 종료 뒤 새로 띄우자 다시 로그인을 물었다).
    if (!loginNoticed && WinExist("계정 연결 ahk_exe DiscordChatHUD.exe")) {
        loginNoticed := true
        MacroLog("hud", "디코 오버레이가 로그인을 기다림")
        ShowTooltip("💬 디코 오버레이 로그인 필요: 작업 표시줄의 DiscordChatHUD 창", 8000)
    }
    if (A_TickCount >= deadline || !WinExist(GTA_WIN))
        return
    if (WinActive("ahk_exe DiscordChatHUD.exe") || WinActive("ahk_exe DiscordChatHUD_Config.exe")) {
        WinActivate(GTA_WIN)
        MacroLog("hud", "디코 오버레이 창이 앞으로 와서 GTA 를 다시 앞으로")
    }
    SetTimer(() => DiscordHUDKeepGTAFront(deadline), -500)
}

; 입력 감시가 붙은 매크로의 MCT 조작 동안만 HUD 본체를 숨긴다. 수동 MCT·사업장 PC는 숨김 사유가 아니다.
; 정상 종료/재시작은 복원하지만 강제 프로세스 종료는 OnExit를 실행하지 않으므로 복원을 보장하지 않는다.
global gDiscordHUDMCTOpen := false
global gDiscordHUDOwned := Map()
global gDiscordHUDError := ""

DiscordHUDVisibilityInit() {
    OnExit(DiscordHUDVisibilityExit)
    SetTimer(DiscordHUDVisibilityTick, 1000, -10)
    DiscordHUDVisibilityTick()
}

DiscordHUDVisibilityWanted() {
    global gDiscordHUDMCTOpen
    return gDiscordHUDMCTOpen && DiscordHUDMCTAllowed()
}

; 화면만 떠 있는 것은 숨김 사유가 아니다. MCT 진입/정리 호출도 활동 중인 매크로 안에서만 허용한다.
DiscordHUDMCTAllowed() {
    global gEarnBusy, gEarnGuardArmed, gAbort, gEarnUserAbort
    return IsSet(gEarnBusy) && gEarnBusy && IsSet(gEarnGuardArmed) && gEarnGuardArmed
        && !(IsSet(gAbort) && gAbort) && !(IsSet(gEarnUserAbort) && gEarnUserAbort) && IsGTAActive()
}

DiscordHUDMCTSet(open) {
    global gDiscordHUDMCTOpen
    previous := gDiscordHUDMCTOpen
    gDiscordHUDMCTOpen := open && DiscordHUDMCTAllowed()
    try DiscordHUDVisibilitySync(DiscordHUDVisibilityWanted())
    catch as err {
        ; 복원 실패여도 확인된 닫힘은 보존해야 타이머가 복원을 재시도한다.
        if (open)
            gDiscordHUDMCTOpen := previous
        throw err
    }
    return true
}

; 입력 중단/guard 종료에서 동기 복원한다. 창 복원 실패가 게임 키 해제·중단·잠금 해제를 막지 않게 한다.
DiscordHUDMCTStop() {
    global gDiscordHUDMCTOpen
    gDiscordHUDMCTOpen := false
    DiscordHUDVisibilityTick()  ; 실패를 기록하고 소유권을 보존해 다음 tick에서 재시도한다.
}

; 기존 화면 판독 결과를 소비한다. 실패한 판독은 닫힘 증거가 아니며 결제 전 재숨김 실패는 호출자에게 전파한다.
DiscordHUDMCTObserved(name, seen) {
    global gDiscordHUDMCTOpen
    if (!seen)
        return false
    if (name = "mct_seated" || name = "mct_sit" || name = "mct_terrorbyte")
        DiscordHUDMCTSet(false)
    else if (name = "mct_title" || (gDiscordHUDMCTOpen
        && RegExMatch(name, "^(mct_(need_ceo|bunker_card|nightclub_card)|bunker_(page|entry|resupply|buy|confirm|pending)|nc_(dj_menu|home|popularity_home)|dj_(solomun|confirm_solomun|confirm_tale)|warehouse_title)$")))
        DiscordHUDMCTSet(true)
    return true
}

DiscordHUDVisibilityTick() {
    global gDiscordHUDError, gDiscordHUDMCTOpen, gDiscordHUDOwned
    try {
        if (!gDiscordHUDOwned.Count && !ProcessExist("DiscordChatHUD.exe"))
            return
        ; 유휴 화면을 스캔해 새로 숨기지 않는다. 중단된 MCT는 화면이 남아 있어도 사용자의 소유다.
        if (!DiscordHUDMCTAllowed())
            gDiscordHUDMCTOpen := false
        DiscordHUDVisibilitySync(DiscordHUDVisibilityWanted())
        gDiscordHUDError := ""
    } catch as err {
        if (gDiscordHUDError != err.Message)
            MacroLog("hud", "HUD 가시성 적용 실패 (재시도): " err.Message)
        gDiscordHUDError := err.Message
    }
}

DiscordHUDVisibilityExit(*) {
    try DiscordHUDVisibilitySync(false)
    catch as err
        MacroLog("hud", "종료 시 HUD 복원 미확인: " err.Message)
}

DiscordHUDVisibilitySame(a, b) => IsObject(a) && IsObject(b)
    && a.hwnd = b.hwnd && a.pid = b.pid && a.created = b.created && a.title = b.title

DiscordHUDVisibilitySync(hide) {
    global gDiscordHUDOwned
    previousCritical := A_IsCritical
    Critical "On"
    try {
        stale := []
        for hwnd, saved in gDiscordHUDOwned {
            current := DiscordHUDWindowRead(hwnd)
            if (!DiscordHUDVisibilitySame(saved, current)) {
                stale.Push(hwnd)
                continue
            }
            if (hide) {
                ; GTA 재전면화나 HUD 자체 동작으로 다시 표시되면 소유권을 유지한 채 다시 숨긴다.
                if (current.visible && !DiscordHUDWindowVisible(hwnd, false))
                    throw Error("소유한 HUD를 다시 숨기지 못함")
            } else {
                if (!current.visible && !DiscordHUDWindowVisible(hwnd, true))
                    throw Error("HUD 원상복구 미확인")
                if (!current.visible)
                    MacroLog("hud", "MCT 화면 보호 종료: HUD 복원 hwnd=" hwnd " pid=" current.pid)
                stale.Push(hwnd)
            }
        }
        for hwnd in stale
            gDiscordHUDOwned.Delete(hwnd)
        if (!hide)
            return
        for hwnd in DiscordHUDWindowList() {
            if (gDiscordHUDOwned.Has(hwnd))
                continue
            current := DiscordHUDWindowRead(hwnd)
            if (!IsObject(current) || !current.visible || current.minimized)
                continue
            ; 실패/예외 이후에도 원래 visible이었던 이 창의 복원 책임은 남긴다.
            gDiscordHUDOwned[hwnd] := current
            if (!DiscordHUDWindowVisible(hwnd, false))
                throw Error("HUD 숨김 미확인. 화면 판독을 시작하지 않음")
            MacroLog("hud", "MCT 화면 보호: HUD 숨김 hwnd=" hwnd " pid=" current.pid)
        }
    } finally {
        Critical previousCritical
    }
}

; 창 조회/가시성 변경을 분리해 회귀 검사는 실제 창 API 없이 실행한다.
DiscordHUDWindowList() {
    previousHidden := A_DetectHiddenWindows
    DetectHiddenWindows true
    try return WinGetList("ahk_exe DiscordChatHUD.exe")
    finally DetectHiddenWindows previousHidden
}

DiscordHUDWindowRead(hwnd) {
    if (!DllCall("IsWindow", "ptr", hwnd))
        return false
    previousHidden := A_DetectHiddenWindows
    DetectHiddenWindows true
    try {
        title := WinGetTitle("ahk_id " hwnd)
        if (title != "DiscordChatHUD C#" || WinGetProcessName("ahk_id " hwnd) != "DiscordChatHUD.exe")
            return false
        pid := WinGetPID("ahk_id " hwnd)
        process := DllCall("OpenProcess", "uint", 0x1000, "int", false, "uint", pid, "ptr")
        if (!process)
            throw Error("HUD 프로세스 식별 실패")
        try {
            created := Buffer(8), exited := Buffer(8), kernel := Buffer(8), user := Buffer(8)
            if (!DllCall("GetProcessTimes", "ptr", process, "ptr", created, "ptr", exited, "ptr", kernel, "ptr", user))
                throw Error("HUD 프로세스 생성 시각 확인 실패")
            return {hwnd: hwnd, pid: pid, created: NumGet(created, 0, "uint64"), title: title,
                visible: !!DllCall("IsWindowVisible", "ptr", hwnd), minimized: !!DllCall("IsIconic", "ptr", hwnd)}
        } finally {
            DllCall("CloseHandle", "ptr", process)
        }
    } finally {
        DetectHiddenWindows previousHidden
    }
}

DiscordHUDWindowVisible(hwnd, visible) {
    ; SW_SHOWNOACTIVATE는 포커스를 가져오지 않는다. 비동기 호출의 접수와 실제 반영을 구분한다.
    DllCall("ShowWindowAsync", "ptr", hwnd, "int", visible ? 8 : 0)
    Loop 10 {
        if (!DllCall("IsWindow", "ptr", hwnd))
            return false
        if (!!DllCall("IsWindowVisible", "ptr", hwnd) = visible)
            return true
        Sleep 10
    }
    return false
}
