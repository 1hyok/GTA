#Requires AutoHotkey v2.0
#SingleInstance Off
; 실제 입력 없이 세션 화면 guard 를 확인한다. PressKey·TemplateSeen·포커스는 아래 stub 만 사용한다.
#Include %A_ScriptDir%\..\..\Features\SessionSwitch.ahk
#Include %A_ScriptDir%\SessionGuard.ahk
global config := Map("Settings", Map("SessionMenuDelay", 0))
global gAbort := false, active := true, allowed := Map(), sent := [], afterPress := "", abortOnRead := false
global gSessionInputGuard := SessionScreenSeen
try {
    RunTests()
    FileAppend("session guard tests: PASS (10 cases, no real input)`n", "*")
    ExitApp(0)
} catch as err {
    FileAppend("session guard tests: FAIL " err.Message "`n", "*")
    ExitApp(1)
}

IsGTAActive() {
    global active
    return active
}
TemplateSeen(folder, name, area := "") {
    global allowed, gAbort, abortOnRead
    if (abortOnRead)
        gAbort := true
    return allowed.Has(name) && allowed[name]
}
PressKey(key, count := 1, delay := 0) {
    global sent, allowed, afterPress
    sent.Push(key)
    if (afterPress != "") {
        allowed.Clear()
        allowed[afterPress] := true
    }
}
MacroLog(*) {
}
ShowTooltip(*) {
}
Reset() {
    global gAbort, active, allowed, sent, afterPress, abortOnRead, gSessionInputGuard
    gAbort := false, active := true, allowed := Map(), sent := [], afterPress := "", abortOnRead := false
    gSessionInputGuard := SessionScreenSeen
}
Check(ok, message) {
    if (!ok)
        throw Error(message)
}
RunTests() {
    global gAbort, active, allowed, sent, afterPress, abortOnRead, SESSION_TABS_AREA, gSessionInputGuard
    Reset()
    Check(!SessionStep("Enter", 1, 0, "pause_online_selected", SESSION_TABS_AREA) && sent.Length = 0, "missing template sent Enter")
    Reset()
    allowed["pause_online_selected"] := true
    Check(SessionStep("Enter", 1, 0, "pause_online_selected", SESSION_TABS_AREA) && sent.Length = 1 && sent[1] = "Enter", "verified Enter was not sent once")
    Reset()
    allowed["pause_online_list"] := true, allowed["pause_online_selected"] := true, afterPress := "unknown"
    Check(!SessionStep("Up", 2, 0, "pause_online_list", []) && sent.Length = 1, "second key bypassed repeated screen guard")
    Reset()
    allowed["pause_online_list"] := true
    Check(!SessionStep("Up", 1, 0, "pause_online_list", []) && sent.Length = 0, "white row without ONLINE tab sent a key")
    Reset()
    allowed["pause_online_selected"] := true, abortOnRead := true
    Check(!SessionStep("Enter", 1, 0, "pause_online_selected", []) && sent.Length = 0, "End during image check sent key")
    Reset()
    allowed["invite_only"] := true, afterPress := "find_new_session"
    Check(SessionSelectTitle("Up", "find_new_session", 2, 0) && sent.Length = 1, "known-title fallback failed")
    Reset()
    Check(!SessionSelectTitle("Down", "invite_only", 2, 0) && sent.Length = 0, "unknown list sent direction")
    Reset()
    Check(!SessionConfirmQuit(0) && sent.Length = 0, "unknown confirmation sent key")
    Reset()
    allowed["quit_this_session"] := true
    Check(SessionConfirmQuit(0) && sent.Length = 1 && sent[1] = "Enter", "verified quit-this-session was not accepted")
    Reset()
    gSessionInputGuard := false
    Check(SessionStep("Up", 1, 0) && sent.Length = 1, "optional hook changed existing default step behavior")
}
