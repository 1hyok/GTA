; === AFK 방지 (GTA Online idle 킥 방지) ===
; 사용자가 AFKUserIdleSec 초 동안 키보드·마우스를 안 만졌을 때만, AFKIntervalSec 초(±AFKJitterSec) 간격으로
; W 와 S 를 짧게 번갈아 누른다. 누르는 순서를 매번 바꿔 캐릭터가 한쪽으로 밀리지 않게 한다.
; 키는 W/S 만 보낸다. Esc 는 스팀 Big Picture 가 앞에 있으면 "게임 종료" 확인으로 받고, Alt 는 앞 창의 메뉴 바를 활성화한다.
; 인형 뽑기 반복이나 이동·자동 클릭 토글이 켜져 있으면 그 자체가 입력이므로 건너뛴다 (W 를 떼면 달리기 유지가 풀린다).
global afkOn := false
global afkFlip := false
global afkNextDue := 0

ToggleAntiAFK(*) {
    global afkOn
    SetAntiAFK(!afkOn)
}

SetAntiAFK(on) {
    global afkOn, afkNextDue
    afkOn := on
    afkNextDue := 0
    SetTimer(AntiAFKTick, on ? 5000 : 0)
    key := KeyLabelFor("AntiAFK")
    ShowTooltip(on ? "🟢 AFK 방지 켜짐 (" key ": 끄기)" : "⚪ AFK 방지 꺼짐 (" key ": 켜기)", 2000)
    AFKLog(on ? "on" : "off")
}

AntiAFKTick() {
    global afkOn, afkFlip, afkNextDue, config, clawLoopRunning
    if (!afkOn)
        return
    if (IsSet(clawLoopRunning) && clawLoopRunning)
        return
    if (AnyInputToggleOn())
        return
    if (A_TimeIdle < config["Settings"]["AFKUserIdleSec"] * 1000)
        return
    if (afkNextDue && A_TickCount < afkNextDue)
        return
    if (!WinExist("ahk_exe GTA5_Enhanced.exe"))
        return
    idleSec := Round(A_TimeIdle / 1000)   ; 앞으로 가져오기 전에 잰다 (가져오는 과정이 유휴 시간을 0 으로 만든다)
    if (!IsGTAActive() && !BringGTAToFront()) {
        AFKLog("skip: GTA 를 앞으로 가져오지 못함")
        afkNextDue := A_TickCount + 30000
        return
    }
    keys := afkFlip ? ["s", "w"] : ["w", "s"]
    for k in keys {
        Send("{" k " down}")
        Sleep(config["Settings"]["AFKTapMs"])
        Send("{" k " up}")
        Sleep(config["Settings"]["AFKGapMs"])
    }
    afkFlip := !afkFlip
    jitter := config["Settings"]["AFKJitterSec"]
    afkNextDue := A_TickCount + (config["Settings"]["AFKIntervalSec"] + Random(-jitter, jitter)) * 1000
    AFKLog("tap " keys[1] "," keys[2] " idle=" idleSec "s")
}

; 다른 창이 앞에 있어도 GTA 를 앞으로 가져온다. 일반 WinActivate 는 Windows 가 거부하는 경우가 있어
; 앞 창의 입력 스레드에 잠깐 붙어서 가져온다. 앞 창에는 키를 보내지 않는다: Windows 검색 창은 포커스를 잃으면 스스로 닫히고,
; 브라우저·탐색기는 Alt 를 받으면 메뉴 바가 활성화된다. 그래도 안 되면 할당되지 않은 가상 키(vkE8) 하나를 눌러 한 번 더 시도한다
; (최근 키 입력이 있어야 전면화를 허용하는 경우 대비. 어느 앱도 vkE8 에 동작을 두지 않는다).
BringGTAToFront() {
    hwnd := WinExist("ahk_exe GTA5_Enhanced.exe")
    if (!hwnd)
        return false
    try {
        if (WinGetMinMax("ahk_id " hwnd) = -1)
            WinRestore("ahk_id " hwnd)
    }
    Loop 2 {
        if (A_Index = 2)
            Send("{vkE8}")
        fg := DllCall("GetForegroundWindow", "ptr")
        fgThread := DllCall("GetWindowThreadProcessId", "ptr", fg, "ptr", 0, "uint")
        myThread := DllCall("GetCurrentThreadId", "uint")
        DllCall("AttachThreadInput", "uint", myThread, "uint", fgThread, "int", 1)
        DllCall("BringWindowToTop", "ptr", hwnd)
        DllCall("SetForegroundWindow", "ptr", hwnd)
        DllCall("AttachThreadInput", "uint", myThread, "uint", fgThread, "int", 0)
        Sleep(800)
        if (WinActive("ahk_id " hwnd)) {
            AFKLog("GTA 를 앞으로 가져옴" (A_Index = 2 ? " (2차 시도)" : ""))
            return true
        }
    }
    ; 3차: 앞 창이 입력 도구(TextInputHost: 이모지·터치 키보드·IME 창)거나 앞 창이 없으면 Alt 를 한 번 눌렀다 떼고 AHK WinActivate 로 가져온다.
    ; 0926 14:49~15:18 에 TextInputHost 가 앞에 있는 동안 1·2차가 계속 실패해 30분 가까이 입력이 끊겼고 게임에서 방치 킥을 당했다.
    ; Alt 는 브라우저·탐색기에서 메뉴 바를 켜므로 이 두 경우에만 쓴다.
    fg := DllCall("GetForegroundWindow", "ptr")
    fgExe := ""
    try fgExe := WinGetProcessName("ahk_id " fg)
    if (!fg || fgExe = "TextInputHost.exe") {
        Send("{Alt down}{Alt up}")
        try WinActivate("ahk_id " hwnd)
        Sleep(800)
        if (WinActive("ahk_id " hwnd)) {
            AFKLog("GTA 를 앞으로 가져옴 (3차: " (fgExe = "" ? "앞 창 없음" : fgExe) ")")
            return true
        }
    }
    AFKLog("앞 창: " (fgExe = "" ? "없음" : fgExe) " / " WinGetTitleSafe(fg))
    return false
}

WinGetTitleSafe(hwnd) {
    t := ""
    try t := WinGetTitle("ahk_id " hwnd)
    return t
}

AFKLog(msg) {
    try FileAppend(FormatTime(, "HH:mm:ss") " " msg "`n", A_Temp "\gta-afk.log", "UTF-8")
}
