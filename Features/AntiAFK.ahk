; === AFK 방지 (GTA Online idle 킥 방지) ===
; 사용자가 AFKUserIdleSec 초 동안 키보드·마우스를 안 만졌을 때만, AFKIntervalSec 초(±AFKJitterSec) 간격으로
; 일반 모드는 W/S 왕복, MCT 모드는 선택을 바꾸지 않는 상대 마우스 왕복을 보낸다.
; GTA가 앞일 때만 입력하며 다른 창을 전면화하지 않는다. 사용자 물리 입력이 생기면 남은 동작을 취소한다.
; 인형 뽑기 반복이나 이동·자동 클릭 토글이 켜져 있으면 그 자체가 입력이므로 건너뛴다 (W 를 떼면 달리기 유지가 풀린다).
global afkOn := false
global afkFlip := false
global afkNextDue := 0
global gAFKBusy := false

ToggleAntiAFK(*) {
    global afkOn
    SetAntiAFK(!afkOn)
}

SetAntiAFK(on) {
    global afkOn, afkNextDue
    afkOn := on
    afkNextDue := 0
    if (on) {
        InstallKeybdHook()
        InstallMouseHook()
    }
    SetTimer(AntiAFKTick, on ? 5000 : 0)
    key := KeyLabelFor("AntiAFK")
    ShowTooltip(on ? "🟢 AFK 방지 켜짐 (" key ": 끄기)" : "⚪ AFK 방지 꺼짐 (" key ": 켜기)", 2000)
    AFKLog(on ? "on" : "off")
}

AntiAFKTick() {
    global afkOn, afkFlip, afkNextDue, config, clawLoopRunning, gEarnBusy, gMenuBusy, gAFKBusy
    if (!afkOn || gAFKBusy)
        return
    if (IsSet(clawLoopRunning) && clawLoopRunning)
        return
    ; 수익 자동화가 메뉴·터미널을 조작하는 동안 W/S 가 끼어들면 선택 줄이 움직인다
    if (IsSet(gEarnBusy) && gEarnBusy)
        return
    if (IsSet(gMenuBusy) && gMenuBusy)
        return
    if (AnyInputToggleOn())
        return
    if (A_TimeIdlePhysical < config["Settings"]["AFKUserIdleSec"] * 1000)
        return
    if (afkNextDue && A_TickCount < afkNextDue)
        return
    if (!WinExist("ahk_exe GTA5_Enhanced.exe"))
        return
    ; 작텔(Alt+F4·스팀 봇·MC)이 도는 중에는 누르지 않는다. 스팀 봇 작텔은 도착까지 최대 90초 입력 없이 기다려 유휴 시간을 넘길 수 있고,
    ; 그때 끼어든 W/S 나 GTA 전면화가 그쪽의 알림 판정·스팀 클릭 사이에 들어간다
    if (IsTeleportRunning())
        return
    idleSec := Round(A_TimeIdlePhysical / 1000)
    gAFKBusy := true
    try {
        if (!IsGTAActive()) {
            AFKLog("skip: GTA 포커스 없음, 전면화하지 않음")
            afkNextDue := A_TickCount + 30000
            return
        }
        if (!AFKInputAllowed())
            return
        ; MCT 모드에서는 W/S가 목록 선택을 바꾸므로 클릭 없는 상대 마우스 왕복만 보낸다.
        ; 수익 작업이 화면 오류로 멈춰도 AFK 타이머는 살아 있고 이동 키를 보내지 않는다.
        if (config["Settings"].Get("EarnMCTOnly", 0)) {
            if (!AFKMousePulse())
                return
            action := "mouse pulse (MCT)"
        } else {
            keys := afkFlip ? ["s", "w"] : ["w", "s"]
            for k in keys {
                if (!AFKInputAllowed())
                    return
                try {
                    Send("{" k " down}")
                    if (!AFKWait(config["Settings"]["AFKTapMs"]))
                        return
                } finally {
                    if (!GetKeyState(k, "P"))
                        Send("{" k " up}")
                }
                if (!AFKWait(config["Settings"]["AFKGapMs"]))
                    return
            }
            afkFlip := !afkFlip
            action := "tap " keys[1] "," keys[2]
        }
        jitter := config["Settings"]["AFKJitterSec"]
        afkNextDue := A_TickCount + (config["Settings"]["AFKIntervalSec"] + Random(-jitter, jitter)) * 1000
        AFKLog(action " idle=" idleSec "s")
    } finally {
        gAFKBusy := false
    }
}

AFKInputAllowed() {
    global afkOn, config, gEarnBusy, gMenuBusy
    return afkOn && IsGTAActive()
        && A_TimeIdlePhysical >= Max(1, config["Settings"]["AFKUserIdleSec"]) * 1000
        && !(IsSet(gEarnBusy) && gEarnBusy) && !(IsSet(gMenuBusy) && gMenuBusy)
        && !IsTeleportRunning() && !AnyInputToggleOn()
}

AFKWait(ms) {
    deadline := A_TickCount + ms
    while (A_TickCount < deadline) {
        if (!AFKInputAllowed())
            return false
        Sleep(Min(25, Max(1, deadline - A_TickCount)))
    }
    return AFKInputAllowed()
}

AFKMousePulse() {
    for dx in [2, -2] {
        if (!AFKInputAllowed())
            return false
        DllCall("mouse_event", "uint", 1, "int", dx, "int", 0, "uint", 0, "uptr", 0)
        if (!AFKWait(100))
            return false
    }
    return true
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
