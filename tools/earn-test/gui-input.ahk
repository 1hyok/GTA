#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
#Include %A_ScriptDir%\..\..\Core\Common.ahk

; GUI 작업 하나가 소유하는 입력 수신기. Main/AFK, 전면화, 자동 동작은 실행하지 않는다.
; 실행: gui-input.ahk <새 세션 디렉터리> <세션 토큰>
; 입력 없는 검증: gui-input.ahk --self-test
; command.txt: token|sequence|UTC yyyyMMddHHmmss|tap/hold/look/click/wheel/navigate/stop|arg1|arg2
; 한 번에 명령 하나. 확인된 탐색 구간은 navigate로 묶고 분기·확정·구간 결과에서 화면을 확인한다.
global giDir := "", giToken := "", giSeq := 0, giActiveSeq := 0
global giHeld := "", giArmed := false, giStopping := false, giMutex := 0
global giStart := 0, giHwnd := 0, giExitMessage := "normal"
global giNavStarted := 0, giNavTotal := 0, giNavCompleted := 0

if (A_Args.Length = 1 && A_Args[1] = "--self-test") {
    try {
        GuiInputSelfTest()
        ExitApp(0)
    } catch as err {
        FileAppend("FAIL " err.Message " line=" err.Line "`n", "*")
        ExitApp(1)
    }
}
if (A_Args.Length != 2) {
    FileAppend("usage: gui-input.ahk <new-session-directory> <token> | --self-test`n", "*")
    ExitApp(2)
}
giDir := RTrim(A_Args[1], "\/")
giToken := A_Args[2]
if (!RegExMatch(giDir, "i)^[a-z]:\\") || !RegExMatch(giToken, "^[A-Za-z0-9_-]{8,64}$")) {
    FileAppend("absolute local directory and 8-64 character session token required`n", "*")
    ExitApp(2)
}
if (!DirExist(giDir) || FileExist(giDir "\state.txt") || FileExist(giDir "\command.txt")) {
    FileAppend("create a fresh session directory before starting`n", "*")
    ExitApp(2)
}

OnExit(GuiInputExit)
OnError(GuiInputError)
giMutex := DllCall("CreateMutexW", "ptr", 0, "int", 0, "str", "Local\GtaGuiInput", "ptr")
if (!giMutex || A_LastError = 183)
    GuiInputQuit("another gui-input receiver is running", 3)
SetStoreCapsLockMode(false)
A_MenuMaskKey := "vkE8"
SendMode("Event")
SetKeyDelay(-1, -1)
Thread("Interrupt", 0)
InstallKeybdHook()
InstallMouseHook()
Hotkey("~*End", (*) => GuiInputQuit("End", 1))
giStart := DllCall("GetTickCount64", "uint64")
giHwnd := IsGTAActive()
if (!giHwnd)
    GuiInputQuit("GTA must already be foreground; no activation attempted", 3)
GuiInputState("waiting", "initial physical idle: 8000ms, limit: 60000ms")
; Observe at least 8 seconds after installing both hooks. Do not infer old physical state.
while (DllCall("GetTickCount64", "uint64") - giStart < 8000 || A_TimeIdlePhysical < 8000) {
    if (!IsGTAActive() || WinActive("A") != giHwnd)
        GuiInputQuit("focus left GTA during preparation", 1)
    if (DllCall("GetTickCount64", "uint64") - giStart >= 60000)
        GuiInputQuit("initial physical idle timeout", 3)
    Sleep(10)
}
giArmed := true
SetTimer(GuiInputGuard, 10)
GuiInputGuard()
GuiInputState("ready")
Loop {
    GuiInputGuard()
    if (!FileExist(giDir "\command.txt")) {
        Sleep(10)
        continue
    }
    giRaw := FileRead(giDir "\command.txt", "UTF-8")
    FileDelete(giDir "\command.txt")
    try giCommand := GuiInputParse(giRaw, giToken, giSeq, A_NowUTC)
    catch as err {
        GuiInputWrite(giDir "\rejected.txt", err.Message)
        GuiInputQuit("rejected command: " err.Message, 4)
    }
    giSeq := giCommand.seq
    giActiveSeq := giCommand.seq
    GuiInputState("busy", giCommand.op)
    GuiInputGuard()
    if (giCommand.op = "stop") {
        GuiInputResult("ok", "stopped")
        GuiInputQuit("stop command", 0)
    }
    if (giCommand.op = "tap")
        GuiInputKey(giCommand.a = "Caps" ? "CapsLock" : giCommand.a, 100)
    else if (giCommand.op = "hold")
        GuiInputKey(giCommand.a, giCommand.b)
    else if (giCommand.op = "click")
        GuiInputClick(giCommand.a, giCommand.b)
    else if (giCommand.op = "wheel")
        GuiInputWheel(giCommand.a)
    else if (giCommand.op = "navigate")
        GuiInputNavigate(giCommand.a, giCommand.b)
    else {
        for giDelta in GuiInputLookSteps(giCommand.a, giCommand.b) {
            GuiInputGuard()
            DllCall("mouse_event", "uint", 1, "int", giDelta[1], "int", giDelta[2], "uint", 0, "uptr", 0)
            GuiInputWait(15)
        }
    }
    GuiInputGuard()
    GuiInputResult("ok", giCommand.op " completed")
    GuiInputState("ready")
}

; Also satisfies Core/Common.ahk's ExitAll reference. It never starts another macro.
StopAll(*) => GuiInputQuit("StopAll", 1)

GuiInputParse(raw, token, previous, now) {
    if (StrLen(raw) > 256 || !RegExMatch(raw, "^[A-Za-z0-9_|-]+$") || InStr(raw, "`n") || InStr(raw, "`r"))
        throw Error("one short command line required")
    fields := StrSplit(raw, "|")
    if (fields.Length != 6 || fields[1] !== token)
        throw Error("session or field count mismatch")
    if (!RegExMatch(fields[2], "^[1-9][0-9]{0,8}$") || Integer(fields[2]) != previous + 1)
        throw Error("sequence must be exactly previous + 1")
    if (!RegExMatch(fields[3], "^[0-9]{14}$"))
        throw Error("invalid UTC timestamp")
    age := DateDiff(now, fields[3], "Seconds")
    if (age < 0 || age > 5)
        throw Error("command expired or timestamp is in the future")
    op := fields[4], a := fields[5], b := fields[6]
    if (op = "tap") {
        if (!RegExMatch(a, "^(P|M|E|Enter|Backspace|Up|Down|Left|Right|PgDn|PgUp|Caps|Space|LCtrl|RButton)$") || b != "0")
            throw Error("tap key is not allowed")
    } else if (op = "hold") {
        if (!RegExMatch(a, "^[WASD]$") || !RegExMatch(b, "^[1-9][0-9]{0,4}$") || Integer(b) > 15000)
            throw Error("hold requires W/A/S/D and 1-15000ms")
        b := Integer(b)
    } else if (op = "look") {
        if (!RegExMatch(a, "^-?[0-9]{1,5}$") || !RegExMatch(b, "^-?[0-9]{1,5}$"))
            throw Error("look requires integer dx and dy")
        a := Integer(a), b := Integer(b)
        if ((a = 0 && b = 0) || Sqrt(a*a + b*b) > 10000)
            throw Error("look distance must be 1-10000 units")
    } else if (op = "click") {
        if (!RegExMatch(a, "^-?[0-9]{1,5}$") || !RegExMatch(b, "^-?[0-9]{1,5}$"))
            throw Error("click requires integer physical screen x and y")
        a := Integer(a), b := Integer(b)
        if (Abs(a) > 65535 || Abs(b) > 65535)
            throw Error("click coordinate is out of range")
    } else if (op = "wheel") {
        if (!RegExMatch(a, "^-?[1-5]$") || b != "0")
            throw Error("wheel requires -5..-1 or 1..5 ticks and zero arg2")
        a := Integer(a)
    } else if (op = "navigate") {
        if (!RegExMatch(a, "^(Up|Down|Left|Right|PgDn|PgUp)(_(Up|Down|Left|Right|PgDn|PgUp)){0,19}$"))
            throw Error("navigate requires 1-20 navigation keys; confirmation and back keys are forbidden")
        if (!RegExMatch(b, "^[1-5][0-9]{2}$") || Integer(b) < 150 || Integer(b) > 500)
            throw Error("navigate delay must be 150-500ms")
        b := Integer(b)
    } else if (op != "stop" || a != "0" || b != "0")
        throw Error("unknown operation or stop arguments")
    return {seq: Integer(fields[2]), op: op, a: a, b: b}
}

GuiInputLookSteps(dx, dy) {
    steps := [], count := Max(1, Ceil(Sqrt(dx*dx + dy*dy) / 18))
    px := 0, py := 0
    Loop count {
        x := Round(dx * A_Index / count), y := Round(dy * A_Index / count)
        steps.Push([x - px, y - py])
        px := x, py := y
    }
    return steps
}

GuiInputGuard(*) {
    global giArmed, giStopping, giStart, giHwnd
    if (giStopping)
        return
    if (!IsGTAActive() || WinActive("A") != giHwnd)
        GuiInputQuit("GTA focus lost", 1)
    if (giArmed && A_TimeIdlePhysical < 8000)
        GuiInputQuit("physical user input detected", 1)
    if (DllCall("GetTickCount64", "uint64") - giStart >= 25 * 60000)
        GuiInputQuit("25 minute session timeout", 124)
}

GuiInputWait(ms) {
    deadline := DllCall("GetTickCount64", "uint64") + ms
    Loop {
        GuiInputGuard()
        remaining := deadline - DllCall("GetTickCount64", "uint64")
        if (remaining <= 0)
            return
        Sleep(Min(10, remaining))
    }
}

GuiInputKey(key, ms) {
    global giHeld
    GuiInputGuard()
    giHeld := key
    try {
        SendEvent("{Blind}{" key " down}")
        GuiInputWait(ms)
    } finally {
        GuiInputRelease()
    }
}

; A bounded selection-only route. The caller verifies its final screen before
; sending a separate confirmation. Every key and inter-key wait keep the guard.
GuiInputNavigate(joinedKeys, delayMs) {
    global giNavStarted, giNavTotal, giNavCompleted
    keys := StrSplit(joinedKeys, "_")
    giNavStarted := DllCall("GetTickCount64", "uint64")
    giNavTotal := keys.Length
    giNavCompleted := 0
    try {
        for index, key in keys {
            GuiInputGuard()
            GuiInputKey(key, 100)
            giNavCompleted++
            if (index < keys.Length)
                GuiInputWait(delayMs)
        }
    } finally {
        GuiInputRelease()
    }
}

GuiInputPointInside(x, y, left, top, width, height) {
    return width > 0 && height > 0 && x >= left && y >= top && x < left + width && y < top + height
}

; Parent supplies physical screen pixels read from the current screenshot.
; Recheck bounds and actual cursor position after moving, before pressing LButton.
GuiInputClick(x, y) {
    global giHwnd
    GuiInputGuard()
    previousDpi := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    if (!previousDpi)
        throw Error("could not use physical screen coordinates")
    try {
        WinGetClientPos(&left, &top, &width, &height, "ahk_id " giHwnd)
        if (!GuiInputPointInside(x, y, left, top, width, height))
            throw Error("click is outside GTA client area")
        GuiInputGuard()
        if (!DllCall("SetCursorPos", "int", x, "int", y))
            throw Error("SetCursorPos failed")
        GuiInputWait(50)
        cursor := Buffer(8, 0)
        if (!DllCall("GetCursorPos", "ptr", cursor))
            throw Error("GetCursorPos failed")
        if (NumGet(cursor, 0, "int") != x || NumGet(cursor, 4, "int") != y)
            throw Error("cursor did not reach requested physical position")
        WinGetClientPos(&left, &top, &width, &height, "ahk_id " giHwnd)
        if (!GuiInputPointInside(x, y, left, top, width, height))
            throw Error("GTA client moved before click")
        GuiInputKey("LButton", 100)
    } finally {
        DllCall("SetThreadDpiAwarenessContext", "ptr", previousDpi, "ptr")
    }
}

; Positive ticks scroll up, negative ticks down. Never move the cursor here.
GuiInputWheel(ticks) {
    global giHwnd
    Loop Abs(ticks) {
        GuiInputGuard()
        previousDpi := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
        if (!previousDpi)
            throw Error("could not use physical cursor coordinates")
        try {
            cursor := Buffer(8, 0)
            if (!DllCall("GetCursorPos", "ptr", cursor))
                throw Error("GetCursorPos failed before wheel")
            WinGetClientPos(&left, &top, &width, &height, "ahk_id " giHwnd)
            if (!GuiInputPointInside(NumGet(cursor, 0, "int"), NumGet(cursor, 4, "int"), left, top, width, height))
                throw Error("wheel cursor is outside GTA client area")
            GuiInputGuard()
            SendEvent(ticks > 0 ? "{Blind}{WheelUp}" : "{Blind}{WheelDown}")
        } finally {
            DllCall("SetThreadDpiAwarenessContext", "ptr", previousDpi, "ptr")
        }
        GuiInputWait(50)
    }
}

GuiInputRelease() {
    global giHeld
    if (giHeld = "")
        return
    key := giHeld
    giHeld := ""
    ; Release only this receiver's key; never sweep another macro's keys.
    if (!GetKeyState(key, "P"))
        SendEvent("{Blind}{" key " up}")
}

GuiInputWrite(path, value) {
    temporary := path ".tmp"
    outputHandle := FileOpen(temporary, "w", "UTF-8-RAW")
    outputHandle.Write(value)
    outputHandle.Close()
    FileMove(temporary, path, 1)
}

GuiInputState(state, message := "") {
    global giDir, giToken, giSeq
    clean := RegExReplace(message, "[|\r\n]", " ")
    GuiInputWrite(giDir "\state.txt", giToken "|" DllCall("GetCurrentProcessId") "|" state "|" giSeq "|" A_NowUTC "|" clean)
}

GuiInputResult(status, message) {
    global giDir, giToken, giActiveSeq, giNavStarted, giNavTotal, giNavCompleted
    if (!giActiveSeq)
        return
    if (giNavStarted) {
        elapsed := DllCall("GetTickCount64", "uint64") - giNavStarted
        message .= " keys=" giNavCompleted "/" giNavTotal " elapsed_ms=" elapsed
        GuiInputWrite(giDir "\navigate-" giActiveSeq ".log", A_NowUTC " " status " " message)
        giNavStarted := 0
    }
    clean := RegExReplace(message, "[|\r\n]", " ")
    GuiInputWrite(giDir "\result-" giActiveSeq ".txt", giToken "|" giActiveSeq "|" status "|" A_NowUTC "|" clean)
    giActiveSeq := 0
}

GuiInputQuit(message, code) {
    global giStopping, giExitMessage
    giStopping := true
    giExitMessage := message
    GuiInputRelease()
    try GuiInputResult("aborted", message)
    try GuiInputState("stopped", message)
    ExitApp(code)
}

GuiInputExit(reason, code) {
    global giMutex, giStopping, giExitMessage
    message := giStopping ? giExitMessage : "process exit: " reason " code=" code
    giStopping := true
    try GuiInputRelease()
    try GuiInputResult("aborted", message)
    try GuiInputState("stopped", message)
    if (giMutex)
        DllCall("CloseHandle", "ptr", giMutex)
}

GuiInputError(err, mode) {
    GuiInputQuit("error: " err.Message " line=" err.Line, 2)
    return true
}

GuiInputSelfTest() {
    token := "parser-test", now := "20260927120010", prefix := token "|1|20260927120010|"
    good := ["tap|Enter|0", "tap|Caps|0", "tap|PgDn|0", "tap|PgUp|0", "hold|W|15000", "hold|D|1", "look|-10000|0", "look|3|-4", "click|960|540", "click|-2560|0", "click|65535|-65535", "wheel|-5|0", "wheel|5|0", "wheel|-1|0", "wheel|1|0", "stop|0|0"]
    good.Push("tap|LCtrl|0", "tap|RButton|0")
    bad := ["tap|Esc|0", "tap|F9|0", "tap|W|0", "tap|Enter|1", "hold|E|100", "hold|W|15001", "hold|A|0", "hold|S|-1", "hold|D|1.5", "look|0|0", "look|10000|1", "look|1e3|0", "click|1.5|0", "click|0|1e3", "click|65536|0", "click|0|-65536", "wheel|0|0", "wheel|6|0", "wheel|-6|0", "wheel|1.5|0", "wheel|1|1", "stop|1|0", "run|0|0", "tap|Enter|0|extra", "tap|Enter|0`n"]
    bad.Push("tap|LCtrl|1", "tap|RButton|100", "tap|lctrl|0", "tap|rbutton|0",
        "tap|Ctrl|0", "tap|RCtrl|0", "hold|LCtrl|100", "hold|RButton|100")
    cases := 0
    for command in good {
        GuiInputParse(prefix command, token, 0, now)
        cases++
    }
    for command in bad {
        GuiInputExpectReject(prefix command, token, 0, now)
        cases++
    }
    navigation20 := "Up_Down_Left_Right_PgDn_PgUp_Up_Down_Left_Right_PgDn_PgUp_Up_Down_Left_Right_PgDn_PgUp_Up_Down"
    for command in ["navigate|Up|150", "navigate|PgUp_PgDn|200", "navigate|" navigation20 "|500"] {
        parsed := GuiInputParse(prefix command, token, 0, now)
        if (parsed.op != "navigate" || parsed.b < 150 || parsed.b > 500)
            throw Error("navigation command did not retain its delay")
        cases++
    }
    for command in ["navigate||200", "navigate|_Up|200", "navigate|Up_|200", "navigate|Up__Down|200", "navigate|up|200", "navigate|" navigation20 "_Up|200", "navigate|Up|149", "navigate|Up|501", "navigate|Up|0150", "navigate|Up|1e2", "navigate|Up|200|extra"] {
        GuiInputExpectReject(prefix command, token, 0, now)
        cases++
    }
    for forbidden in ["Enter", "Space", "Backspace", "Esc", "E", "P", "M", "Caps", "W", "F4", "LButton", "LCtrl", "RButton"] {
        GuiInputExpectReject(prefix "navigate|Up_" forbidden "_Down|200", token, 0, now)
        cases++
    }
    for raw in [token "|1|20260927120004|navigate|Up|200", token "|1|20260927120011|navigate|Up|200", token "|2|20260927120010|navigate|Up|200"] {
        GuiInputExpectReject(raw, token, 0, now)
        cases++
    }
    GuiInputParse(token "|1|20260927120005|navigate|Up|200", token, 0, now)
    GuiInputExpectReject(prefix "navigate|Up|200", token, 1, now)
    cases += 2
    for raw in [token "|1|20260927120004|tap|P|0", token "|1|20260927120011|tap|P|0", token "|1|20269927120010|tap|P|0", "wrong|1|20260927120010|tap|P|0", token "|2|20260927120010|tap|P|0"] {
        GuiInputExpectReject(raw, token, 0, now)
        cases++
    }
    GuiInputExpectReject(prefix "tap|P|0", token, 1, now)
    cases++
    for vector in [[10000, 0], [-10000, 0], [3, -4], [7071, 7071], [1, 1], [-9000, -4000]] {
        x := 0, y := 0
        for delta in GuiInputLookSteps(vector[1], vector[2]) {
            if (Sqrt(delta[1]*delta[1] + delta[2]*delta[2]) > 20)
                throw Error("look step exceeds 20 units")
            x += delta[1], y += delta[2]
        }
        if (x != vector[1] || y != vector[2])
            throw Error("look displacement does not match command")
        cases++
    }
    for pointCase in [[0, 0, 0, 0, 1920, 1080, true], [1919, 1079, 0, 0, 1920, 1080, true], [1920, 540, 0, 0, 1920, 1080, false], [960, 1080, 0, 0, 1920, 1080, false], [-1, 0, 0, 0, 1920, 1080, false], [-2560, 0, -2560, 0, 2560, 1600, true], [0, 0, -2560, 0, 2560, 1600, false], [0, 0, 0, 0, 0, 1080, false]] {
        if (GuiInputPointInside(pointCase[1], pointCase[2], pointCase[3], pointCase[4], pointCase[5], pointCase[6]) != pointCase[7])
            throw Error("client area boundary check failed")
        cases++
    }
    FileAppend("PASS gui-input parser, bounded navigation, look steps and click bounds cases=" cases " (no hooks or game input)`n", "*")
}

GuiInputExpectReject(raw, token, previous, now) {
    try {
        GuiInputParse(raw, token, previous, now)
    } catch {
        return
    }
    throw Error("parser accepted invalid command: " raw)
}
