; === AFK 방지 (GTA Online idle 킥 방지) ===
; 사용자가 AFKUserIdleSec 초 동안 키보드·마우스를 안 만졌을 때만, AFKIntervalSec 초(±20초) 간격으로
; W 와 S 를 짧게 번갈아 누른다. 누르는 순서를 매번 바꿔 캐릭터가 한쪽으로 밀리지 않게 한다.
; Esc 는 쓰지 않는다: 스팀 Big Picture 가 앞에 있으면 Esc 를 "게임 종료" 확인으로 받는다.
; 인형 뽑기 반복이 돌고 있으면 그 자체가 입력이므로 건너뛴다.
global afkOn := false
global afkFlip := false
global afkNextDue := 0

ToggleAntiAFK(*) {
    global afkOn
    SetAntiAFK(!afkOn)
}

SetAntiAFK(on) {
    global afkOn, afkNextDue, config
    afkOn := on
    afkNextDue := 0
    SetTimer(AntiAFKTick, on ? 5000 : 0)
    key := config["Hotkeys"]["AntiAFK"]
    ShowTooltip(on ? "🟢 AFK 방지 켜짐 (" key ": 끄기)" : "⚪ AFK 방지 꺼짐 (" key ": 켜기)", 2000)
    AFKLog(on ? "on" : "off")
}

AntiAFKTick() {
    global afkOn, afkFlip, afkNextDue, config, clawLoopRunning
    if (!afkOn)
        return
    if (IsSet(clawLoopRunning) && clawLoopRunning)
        return
    if (A_TimeIdle < config["Settings"]["AFKUserIdleSec"] * 1000)
        return
    if (afkNextDue && A_TickCount < afkNextDue)
        return
    if (!WinExist("ahk_exe GTA5_Enhanced.exe"))
        return
    if (!IsGTAActive() && !BringGTAToFront()) {
        AFKLog("skip: GTA 를 앞으로 가져오지 못함")
        afkNextDue := A_TickCount + 30000
        return
    }
    keys := afkFlip ? ["s", "w"] : ["w", "s"]
    idleSec := Round(A_TimeIdle / 1000)
    for k in keys {
        Send("{" k " down}")
        Sleep(150)
        Send("{" k " up}")
        Sleep(250)
    }
    afkFlip := !afkFlip
    afkNextDue := A_TickCount + (config["Settings"]["AFKIntervalSec"] + Random(-20, 20)) * 1000
    AFKLog("tap " keys[1] "," keys[2] " idle=" idleSec "s")
}

; 다른 창이 앞에 있어도 GTA 를 앞으로 가져온다. 일반 WinActivate 는 Windows 가 거부하는 경우가 있어
; 앞 창의 입력 스레드에 잠깐 붙어서 가져온다. Windows 검색 창만 Esc 로 닫는다.
BringGTAToFront() {
    hwnd := WinExist("ahk_exe GTA5_Enhanced.exe")
    if (!hwnd)
        return false
    fg := DllCall("GetForegroundWindow", "ptr")
    try {
        if (WinGetProcessName("ahk_id " fg) ~= "i)^(SearchHost|SearchApp|StartMenuExperienceHost)\.exe$") {
            Send("{Esc}")
            Sleep(400)
            fg := DllCall("GetForegroundWindow", "ptr")
        }
    }
    fgThread := DllCall("GetWindowThreadProcessId", "ptr", fg, "ptr", 0, "uint")
    myThread := DllCall("GetCurrentThreadId", "uint")
    DllCall("AttachThreadInput", "uint", myThread, "uint", fgThread, "int", 1)
    Send("{Alt}")
    DllCall("BringWindowToTop", "ptr", hwnd)
    DllCall("SetForegroundWindow", "ptr", hwnd)
    DllCall("AttachThreadInput", "uint", myThread, "uint", fgThread, "int", 0)
    Sleep(800)
    if (WinActive("ahk_id " hwnd)) {
        AFKLog("GTA 를 앞으로 가져옴")
        return true
    }
    return false
}

AFKLog(msg) {
    try FileAppend(FormatTime(, "HH:mm:ss") " " msg "`n", A_Temp "\gta-afk.log", "UTF-8")
}
