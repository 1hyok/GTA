; === 도움말 툴팁 (현재 키맵) ===
; 액션 표와 실제 등록된 키로 만든다. 2번 툴팁이라 상태 툴팁(1번)과 서로 지우지 않는다.
; HelpShowMs 뒤에 닫히고, 다시 누르면 바로 닫힌다.
global helpShown := false

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
    text := "GTA 매크로 단축키 (" KeyLabelFor("Help") " 다시 누르면 닫힘, 게임 창에서만 동작)"
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
    return text
}
