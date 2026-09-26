; === 단축키 관리 모듈 ===
; 액션 표 한 줄 + Config.ini [Hotkeys] 한 줄로 기능이 붙는다. 액션의 속성:
;   id      : [Hotkeys] 의 키 이름
;   label   : 도움말·툴팁에 보이는 이름
;   fn      : 실행할 함수
;   feature : [Features] 플래그 이름. 0 이면 등록하지 않는다 (없으면 항상 등록)
;   confirm : true 면 ConfirmWindowMs 안에 두 번 눌러야 실행 (세션 이동처럼 되돌리기 어려운 것)
;   global  : true 면 게임 밖에서도 잡는다 (종료만)
;   state   : 도움말에 붙일 현재 상태 문자열을 돌려주는 함수
; 게임 키는 전부 GTA 창이 앞일 때만 잡힌다. 밖에서는 F키·넘패드가 원래대로 동작한다.
global gActions := []
global gKeyTable := Map()   ; 등록된 키 -> 액션 id (도움말·중복 검사)
global gArmed := Map()      ; confirm 액션의 첫 번째 누름 시각

; NumLock 이 꺼지면 넘패드 숫자가 이 이름으로 들어오므로 둘 다 등록한다. NumpadDiv·NumpadMult 는 영향이 없다.
global NUMLOCK_ALIAS := Map("Numpad0", "NumpadIns", "Numpad1", "NumpadEnd", "Numpad2", "NumpadDown",
    "Numpad3", "NumpadPgDn", "Numpad4", "NumpadLeft", "Numpad5", "NumpadClear", "Numpad6", "NumpadRight",
    "Numpad7", "NumpadHome", "Numpad8", "NumpadUp", "Numpad9", "NumpadPgUp", "NumpadDot", "NumpadDel")

; * (수식어 무시) 를 붙이지 않는 키. F4 는 Alt+F4(게임 종료)가 그대로 통과해야 하고,
; F5 는 gta-turbo.ps1 이 보내는 Ctrl+Shift+F5 를 가로채면 안 되며, Pause 는 Ctrl+Pause(Break)를 남겨 둔다.
global NO_STAR_KEYS := Map("F4", 1, "F5", 1, "Pause", 1)

RegisterActions() {
    global gActions
    gActions := []
    gActions.Push({id: "ClawAttempt", label: "인형 1판", fn: (*) => ClawAttempt(), feature: "ClawMachine"})
    gActions.Push({id: "ClawLoop", label: "인형 반복", fn: (*) => ToggleClawLoop(), feature: "ClawMachine", state: (*) => clawLoopRunning ? "켜짐 " clawTries "판" : ""})
    gActions.Push({id: "AntiAFK", label: "AFK 방지", fn: (*) => ToggleAntiAFK(), feature: "AntiAFK", state: (*) => afkOn ? "켜짐" : "꺼짐"})
    gActions.Push({id: "InviteOnlySession", label: "초대 전용 세션", fn: (*) => JoinInviteOnlySession(), feature: "SessionSwitch", confirm: true})
    gActions.Push({id: "Walk", label: "걷기", fn: (*) => ToggleWalk(), feature: "Movement", state: (*) => wRunning ? "켜짐" : ""})
    gActions.Push({id: "Run", label: "달리기", fn: (*) => ToggleRun(), feature: "Movement", state: (*) => shiftWRunning ? "켜짐" : ""})
    gActions.Push({id: "AutoClick", label: "자동 클릭", fn: (*) => ToggleAutoClick(), feature: "AutoClick", state: (*) => clickRunning ? "켜짐" : ""})
    gActions.Push({id: "WalkCtrl", label: "벨럼", fn: (*) => ToggleVellumDriving(), feature: "Movement", state: (*) => vellumDrivingRunning ? "켜짐" : ""})
    gActions.Push({id: "RegisterCEO", label: "CEO 등록", fn: (*) => RegisterCEO(), feature: "MenuMacros"})
    gActions.Push({id: "RegisterMC", label: "MC 등록", fn: (*) => RegisterMC(), feature: "MenuMacros"})
    gActions.Push({id: "CayoPericoTimer", label: "카요 타이머", fn: (*) => ToggleCayoPericoTimer(), feature: "Timer", state: (*) => cayoTimerRunning ? "켜짐" : ""})
    gActions.Push({id: "Snack", label: "스낵", fn: (*) => EatSnack(), feature: "MenuMacros"})
    gActions.Push({id: "Help", label: "도움말", fn: (*) => HelpKey()})   ; 두 번 누르면 설정 창
    gActions.Push({id: "StopAll", label: "전체 멈춤", fn: (*) => StopAll("hotkey")})
    gActions.Push({id: "Exit", label: "종료", fn: (*) => ExitAll(), global: true, confirm: true})   ; 전역이라 노트북 Fn+P/Fn+B(Pause) 오타로 꺼지지 않게 두 번 누름
    gActions.Push({id: "TeleportMC1", label: "CEO 재등록 텔레포트", fn: (*) => TeleportMC("CEO"), feature: "Teleport", confirm: true})
    gActions.Push({id: "TeleportMC2", label: "MC 재등록 텔레포트", fn: (*) => TeleportMC("MC"), feature: "Teleport", confirm: true})
    gActions.Push({id: "TeleportAltF4", label: "작텔(Alt+F4)", fn: (*) => TeleportAltF4(), feature: "AltF4Teleport", confirm: true})
    gActions.Push({id: "CasinoFingerprint", label: "지문 해킹", fn: (*) => ExecuteCasinoFingerprint(), feature: "CasinoFingerprint"})
}

SetupHotkeys() {
    global config, gActions, gKeyTable, GTA_WIN, NUMLOCK_ALIAS, NO_STAR_KEYS

    RegisterActions()
    gKeyTable := Map()
    for action in gActions {
        if (action.HasProp("feature") && !config["Features"].Get(action.feature, 0))
            continue
        ; 쉼표로 키를 여러 개 둘 수 있다 (예: ClawLoop=NumpadMult,F4)
        for key in StrSplit(config["Hotkeys"].Get(action.id, ""), ",", " `t") {
            if (key = "")
                continue
            for name in (NUMLOCK_ALIAS.Has(key) ? [key, NUMLOCK_ALIAS[key]] : [key]) {
                if (gKeyTable.Has(name)) {
                    MacroLog("hotkey", "중복 " name ": " gKeyTable[name] " 가 이미 써서 " action.id " 는 건너뜀")
                    continue
                }
                if (action.HasProp("global") && action.global)
                    HotIf()
                else
                    HotIfWinActive(GTA_WIN)
                prefix := NO_STAR_KEYS.Has(name) ? "$" : "*$"
                try {
                    Hotkey(prefix name, Dispatch.Bind(action, name))
                    gKeyTable[name] := action.id
                } catch as e {
                    MacroLog("hotkey", "등록 실패 " action.id "=" name " : " e.Message)
                }
            }
        }
    }
    HotIf()
}

; 핫키 스레드 진입점. confirm 액션은 ConfirmWindowMs 안에 두 번 눌러야 실행한다.
Dispatch(action, key, *) {
    global gArmed, config

    if (action.HasProp("confirm") && action.confirm) {
        windowMs := config["Settings"]["ConfirmWindowMs"]
        if (!(gArmed.Has(action.id) && A_TickCount - gArmed[action.id] <= windowMs)) {
            gArmed[action.id] := A_TickCount
            ShowTooltip(action.label ": " Round(windowMs / 1000) "초 안에 한 번 더 누르면 실행", windowMs)
            ; 키를 누르고 있어서 생기는 자동 반복이 두 번째 누름으로 세지지 않게 뗄 때까지 기다린다.
            KeyWait(key, "T" (windowMs / 1000))
            if (GetKeyState(key, "P"))
                gArmed.Delete(action.id)
            return
        }
        gArmed.Delete(action.id)
    }

    action.fn.Call()
    ; 토글이 자동 반복으로 켜졌다 바로 꺼지지 않게 뗄 때까지 기다린다 (같은 핫키의 추가 누름은 그동안 무시된다).
    KeyWait(key, "T2")
}

; 액션 id 에 등록된 키를 표시용 이름으로 돌려준다. 없으면 "(키 없음)".
KeyLabelFor(id) {
    global config, gKeyTable
    names := ""
    for key in StrSplit(config["Hotkeys"].Get(id, ""), ",", " `t") {
        if (key != "" && gKeyTable.Has(key) && gKeyTable[key] = id)
            names .= (names = "" ? "" : ",") DisplayKey(key)
    }
    return names = "" ? "(키 없음)" : names
}

DisplayKey(key) {
    static names := Map("NumpadDiv", "Num/", "NumpadMult", "Num*", "NumpadAdd", "Num+", "NumpadSub", "Num-",
        "NumpadDot", "Num.", "NumpadEnter", "NumEnter")
    if (names.Has(key))
        return names[key]
    if (SubStr(key, 1, 6) = "Numpad" && StrLen(key) = 7)
        return "Num" SubStr(key, 7)
    return key
}

SetupTrayMenu() {
    A_IconTip := "GTA 매크로"
    tray := A_TrayMenu
    tray.Insert("1&", "종료", (*) => ExitAll())
    tray.Insert("1&", "전체 멈춤", (*) => StopAll("tray"))
    tray.Insert("1&", "AFK 방지 켜기/끄기", (*) => ToggleAntiAFK())
    tray.Insert("1&", "단축키 보기", (*) => ShowHelp())
    tray.Insert("1&", "설정 창 열기", (*) => OpenPanel())
    tray.Insert("6&")
    tray.Default := "설정 창 열기"   ; 트레이 아이콘 더블클릭으로도 열린다
}
