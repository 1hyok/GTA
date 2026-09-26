; === 도움말 툴팁 (현재 키맵) ===
; 액션 표와 실제 등록된 키로 만든다. 2번 툴팁이라 상태 툴팁(1번)과 서로 지우지 않는다.
; HelpShowMs 뒤에 닫히고, 다시 누르면 바로 닫힌다. ConfirmWindowMs 안에 두 번 누르면 툴팁을 닫고 설정 창(Panel.ahk)을 연다.
global helpShown := false
global helpLastPress := 0

; 도움말 키의 진입점. 첫 번째는 예전처럼 도움말 토글, ConfirmWindowMs 안의 두 번째는 설정 창 열기. 새 키를 쓰지 않으려고 도움말 키에 얹었다.
HelpKey() {
    global helpLastPress, config
    if (helpLastPress && A_TickCount - helpLastPress <= config["Settings"]["ConfirmWindowMs"]) {
        helpLastPress := 0
        HideHelp()
        OpenPanel()
        return
    }
    helpLastPress := A_TickCount
    ToggleHelp()
}

ToggleHelp() {
    global helpShown
    if (helpShown)
        HideHelp()
    else
        ShowHelp()
}

ShowHelp() {
    global helpShown, config
    text := BuildHelpText()
    CoordMode("ToolTip", "Screen")
    if (hwnd := IsGTAActive()) {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        ToolTip(text, cx + 20, cy + Round(ch * 0.30), 2)
    } else {
        ToolTip(text, 20, Round(A_ScreenHeight * 0.30), 2)
    }
    helpShown := true
    SetTimer(HideHelp, -config["Settings"]["HelpShowMs"])
}

HideHelp() {
    global helpShown
    helpShown := false
    SetTimer(HideHelp, 0)
    ToolTip(, , , 2)
}

BuildHelpText() {
    global gActions, gKeyTable, config
    help := KeyLabelFor("Help")
    text := "GTA 매크로 단축키 (" help " 두 번: 설정 창 | " help " 다시 누르면 닫힘 | 게임 창에서만 동작)"
    count := 0
    for action in gActions {
        keys := ""
        for key in StrSplit(config["Hotkeys"].Get(action.id, ""), ",", " `t") {
            if (key != "" && gKeyTable.Has(key) && gKeyTable[key] = action.id)
                keys .= (keys = "" ? "" : ",") DisplayKey(key)
        }
        if (keys = "")
            continue
        entry := keys (action.HasProp("confirm") && action.confirm ? "×2" : "") " " action.label
        if (action.HasProp("state")) {
            state := ""
            try state := action.state.Call()
            if (state != "")
                entry .= " [" state "]"
        }
        text .= (Mod(count, 3) = 0 ? "`n" : "   |   ") entry
        count += 1
    }
    ; 작텔 두 가지는 키 이름만 봐서는 언제 누르는지 알 수 없어 한 줄 덧붙인다
    if (config["Features"].Get("AltF4Teleport", 0) || config["Features"].Get("BotWarp", 0))
        text .= "`n작텔: 지도에서 작업 블립을 골라 Start Job (Space) 가 보일 때 두 번. 스팀 봇 작텔로 도착한 세션에서는 작업 시작이 막히니 " KeyLabelFor("InviteOnlySession") " 두 번으로 세션을 옮긴 뒤"
    return text
}
