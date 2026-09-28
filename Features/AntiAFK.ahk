; === AFK 방지 (GTA Online idle 킥 방지) ===
; 사용자가 AFKUserIdleSec 초 동안 키보드·마우스를 안 만졌을 때만, AFKIntervalSec 초(±AFKJitterSec) 간격으로
; 일반 모드는 W/S 왕복, MCT 모드는 선택을 바꾸지 않는 상대 마우스 왕복을 보낸다.
; GTA가 앞일 때만 입력한다. 다른 창이 앞이면 물리 입력과, 이 매크로 밖에서 주입된 입력(크롬 원격 데스크톱·computer-use·코덱스 등)이
; 둘 다 AFKRefocusIdleSec 초(기본 300, 0 이면 끔) 넘게 없을 때만 GTA 를 앞으로 가져오고(최소화면 복원), AFKRefocusSettleMs 기다린 뒤
; 같은 입력 판정을 다시 거친다. 그보다 짧으면 누가 자리에 있거나 다른 창을 쓰는 중이라고 보고 포커스를 뺏지 않는다.
; 0928 07:45 예약 작업이 띄운 크롬이 GTA 포커스를 가져간 뒤 입력이 끊겨 07:59 에 15분 방치 킥을 당했다(그 전에는 전면화하지 않고 건너뛰기만 했다).
; 사용자 물리 입력이 생기면 남은 동작을 취소한다.
; 인형 뽑기 반복이나 이동·자동 클릭 토글이 켜져 있으면 그 자체가 입력이므로 건너뛴다 (W 를 떼면 달리기 유지가 풀린다).
global afkOn := false
global afkFlip := false
global afkNextDue := 0
global gAFKBusy := false
global afkRefocusFails := 0      ; 같은 유휴 구간에서 입력까지 못 가고 연달아 실패한 전면화 횟수
global afkRefocusStretch := 0    ; 그 유휴 구간이 시작된 시각(A_TickCount - A_TimeIdlePhysical)
global afkRefocusLastErr := ""   ; 마지막으로 로그에 적은 실패 까닭. 같은 까닭은 다시 적지 않는다
global afkHookTick := 0          ; SetAntiAFK 가 키보드·마우스 훅을 처음 깐 시각(A_TickCount)
global afkSelfFrom := 0          ; 이 매크로가 입력(W/S·마우스 왕복·전면화 중 Alt)을 넣기 시작한 시각
global afkSelfTo := 0            ; 그 입력을 끝낸 시각. 0 이면 아직 넣는 중
global afkSelfBefore := 0        ; 그 구간 직전까지의 마지막 남의 입력 시각

ToggleAntiAFK(*) {
    global afkOn
    SetAntiAFK(!afkOn)
}

SetAntiAFK(on) {
    global afkOn, afkNextDue, afkHookTick
    afkOn := on
    afkNextDue := 0
    if (on) {
        InstallKeybdHook()
        InstallMouseHook()
        if (!afkHookTick)
            afkHookTick := A_TickCount
    }
    SetTimer(AntiAFKTick, on ? 5000 : 0)
    key := KeyLabelFor("AntiAFK")
    ShowTooltip(on ? "🟢 AFK 방지 켜짐 (" key ": 끄기)" : "⚪ AFK 방지 꺼짐 (" key ": 켜기)", 2000)
    AFKLog(on ? "on" : "off")
}

AntiAFKTick() {
    global afkOn, afkFlip, afkNextDue, config, clawLoopRunning, gEarnBusy, gMenuBusy, gAFKBusy, afkRefocusFails, afkRefocusLastErr
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
    if (AFKPhysicalIdleMs() < config["Settings"]["AFKUserIdleSec"] * 1000)
        return
    if (afkNextDue && A_TickCount < afkNextDue)
        return
    if (!WinExist("ahk_exe GTA5_Enhanced.exe"))
        return
    ; 작텔(Alt+F4·스팀 봇·MC)이 도는 중에는 누르지 않는다. 스팀 봇 작텔은 도착까지 최대 90초 입력 없이 기다려 유휴 시간을 넘길 수 있고,
    ; 그때 끼어든 W/S 나 GTA 전면화가 그쪽의 알림 판정·스팀 클릭 사이에 들어간다
    if (IsTeleportRunning())
        return
    idleSec := Round(AFKPhysicalIdleMs() / 1000)
    gAFKBusy := true
    try {
        if (!IsGTAActive()) {
            ; 유휴를 둘로 잰다. 물리 유휴(AFKPhysicalIdleMs)는 SetAntiAFK 가 깐 훅 덕에 주입 입력으로는 줄지 않는다. 사람이 자리에 있으면 짧다.
            ; 크롬 원격 데스크톱으로 쓰는 사람과 computer-use·코덱스 같은 에이전트의 입력은 주입 입력이라 물리 유휴에 안 잡힌다. 그때 GTA 를
            ; 가져오면 그 클릭·타이핑이 게임으로 들어간다(클릭은 사격, T 뒤 글자와 Enter 는 공개 채팅). 그래서 이 매크로 것을 뺀 주입 포함
            ; 유휴(AFKOthersIdleMs)도 기준을 넘어야 한다. 대가: 에이전트가 15분 넘게 쉬지 않고 입력하면 방치 킥을 못 막는다.
            refocusSec := config["Settings"].Get("AFKRefocusIdleSec", 300)
            othersMs := AFKOthersIdleMs()
            if (refocusSec <= 0 || AFKPhysicalIdleMs() < refocusSec * 1000 || othersMs < refocusSec * 1000) {
                AFKLog("skip: GTA 포커스 없음, 전면화하지 않음 (idle=" idleSec "s, 주입 포함 idle=" Round(othersMs / 1000) "s"
                    . (refocusSec > 0 ? ", 기준 " refocusSec "s)" : ", 전면화 꺼짐)"))
                afkNextDue := A_TickCount + 30000
                return
            }
            if (!AFKRefocusGTA(idleSec, othersMs))
                return
            ; 전면화 직후 곧바로 키를 보내지 않는다. 기다리는 사이 사람이 돌아오거나 포커스를 다시 잃으면 이번 차례는 건너뛰고,
            ; 다음 시도는 30초 뒤로 미룬다(5초 틱마다 창을 뺏고 뺏기지 않게)
            afkNextDue := A_TickCount + 30000
            if (!AFKWait(config["Settings"].Get("AFKRefocusSettleMs", 800))) {
                ; 사람이 돌아와 다른 창을 눌렀으면 전면화 실패가 아니다
                if (!IsGTAActive() && AFKPhysicalIdleMs() >= Max(1, config["Settings"]["AFKUserIdleSec"]) * 1000)
                    AFKRefocusFailed("전면화 뒤 포커스를 다시 잃음", idleSec)
                return
            }
        }
        if (!AFKInputAllowed())
            return
        ; MCT 모드에서는 W/S가 목록 선택을 바꾸므로 클릭 없는 상대 마우스 왕복만 보낸다.
        ; 수익 작업이 화면 오류로 멈춰도 AFK 타이머는 살아 있고 이동 키를 보내지 않는다.
        AFKSelfInput(true)
        try {
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
        } finally {
            AFKSelfInput(false)
        }
        jitter := config["Settings"]["AFKJitterSec"]
        afkNextDue := A_TickCount + (config["Settings"]["AFKIntervalSec"] + Random(-jitter, jitter)) * 1000
        AFKLog(action " idle=" idleSec "s")
        afkRefocusFails := 0
        afkRefocusLastErr := ""
    } finally {
        gAFKBusy := false
    }
}

; 물리 유휴와 주입 포함 유휴가 둘 다 AFKRefocusIdleSec 을 넘었을 때만 AntiAFKTick 이 부른다. GTA 를 앞으로 가져오면 true.
; 이 함수가 직접 누르는 키는 앞 창이 입력 도구(TextInputHost)거나 없을 때의 Alt 한 번뿐이다(BringGTAToFront 3차와 같은 조건).
; 다만 AHK 의 WinActivate 는 부드러운 방법이 실패하면 스스로 Alt 를 두 번 누를 수 있다(AHK 소스 기준, 실측 안 함).
; 이 Alt 들은 AFKSelfInput 구간 안에 있어 주입 포함 유휴를 되돌리지 않는다(되돌리면 실패 뒤 재시도가 기준 시간만큼 밀린다).
AFKRefocusGTA(idleSec, othersMs) {
    global GTA_WIN, afkRefocusFails, afkRefocusStretch, afkRefocusLastErr
    ; 그사이 물리 입력이 한 번이라도 있었으면 새 유휴 구간이다. 실패 횟수와 적어 둔 까닭을 비운다.
    stretch := A_TickCount - AFKPhysicalIdleMs()
    if (Abs(stretch - afkRefocusStretch) > 2000) {
        afkRefocusStretch := stretch
        afkRefocusFails := 0
        afkRefocusLastErr := ""
    }
    fgLabel := AFKForegroundLabel()
    gtaHwnd := WinExist(GTA_WIN)
    if (!gtaHwnd)
        return AFKRefocusFailed("GTA 창 없음", idleSec, fgLabel)
    via := ""
    AFKSelfInput(true)
    try {
        if (WinGetMinMax("ahk_id " gtaHwnd) = -1)
            WinRestore("ahk_id " gtaHwnd)
        WinActivate("ahk_id " gtaHwnd)
        activated := WinWaitActive("ahk_id " gtaHwnd, , 2)
        ; 0926 14:49~15:18 에 TextInputHost 가 앞에 있는 동안 전면화가 계속 실패해 방치 킥을 당했다. 그 경우와 앞 창이 없을 때만
        ; Alt 를 한 번 눌렀다 떼고 한 번 더 가져온다. 브라우저·탐색기에서는 Alt 가 메뉴 바를 켜므로 쓰지 않는다.
        if (!activated) {
            fg := WinExist("A")
            fgExe := ""
            if (fg)
                try fgExe := WinGetProcessName("ahk_id " fg)
            if (!fg || fgExe = "TextInputHost.exe") {
                via := " (Alt 보조: " (fg ? fgExe : "앞 창 없음") ")"
                Send("{Alt down}{Alt up}")
                WinActivate("ahk_id " gtaHwnd)
                activated := WinWaitActive("ahk_id " gtaHwnd, , 2)
            }
        }
    } catch as err {
        return AFKRefocusFailed("오류 " err.Message, idleSec, fgLabel)
    } finally {
        AFKSelfInput(false)
    }
    if (!activated || !IsGTAActive())
        return AFKRefocusFailed("2초 안에 앞으로 오지 않음" via, idleSec, fgLabel)
    AFKLog("refocus ok idle=" idleSec "s 주입 포함 idle=" Round(othersMs / 1000) "s 앞 창=" fgLabel via
        . (afkRefocusFails ? " (앞선 실패 " afkRefocusFails "회 뒤)" : ""))
    return true
}

; 물리 입력 유휴(ms). A_TimeIdlePhysical 은 훅을 깐 순간부터 다시 세므로 Main 을 켠 직후에는 실제보다 짧다
; (0928 실측: 133초 비운 뒤 훅을 깔고 1.5초 만에 1531ms). 훅을 깐 뒤 물리 입력을 한 번도 못 봤으면 주입 포함 유휴로 메운다.
; 주입 포함 유휴는 물리 입력도 세므로 실제 물리 유휴보다 길 수 없다. 물리 입력을 본 뒤에는 A_TimeIdlePhysical 만 쓴다
; (이 매크로가 입력하는 구간에 사람이 누른 키는 AFKOthersIdleMs 에서 가려지므로 섞으면 사람 복귀를 놓친다).
AFKPhysicalIdleMs() {
    global afkHookTick
    phys := A_TimeIdlePhysical
    if (afkHookTick && phys >= A_TickCount - afkHookTick - 1000)
        return Max(phys, AFKOthersIdleMs())
    return phys
}

; 이 매크로 밖의 마지막 입력부터 지난 ms. 물리 입력에 더해 원격 데스크톱·에이전트·다른 프로그램이 주입한 입력도 센다
; (A_TimeIdle 은 GetLastInputInfo 값이다). 마지막 입력이 이 매크로가 입력하던 구간(끝난 뒤 500ms 까지) 안이면 그 구간 직전 값으로 센다.
AFKOthersIdleMs() {
    global afkSelfFrom, afkSelfTo, afkSelfBefore
    last := A_TickCount - A_TimeIdle
    if (afkSelfFrom && last >= afkSelfFrom && (!afkSelfTo || last <= afkSelfTo + 500))
        last := afkSelfBefore
    return A_TickCount - last
}

; 이 매크로가 입력을 넣는 구간의 시작(true)과 끝(false). 그 사이 입력은 AFKOthersIdleMs 가 남의 입력으로 세지 않는다.
AFKSelfInput(start) {
    global afkSelfFrom, afkSelfTo, afkSelfBefore
    if (start) {
        afkSelfBefore := A_TickCount - AFKOthersIdleMs()
        afkSelfFrom := A_TickCount
        afkSelfTo := 0
    } else {
        afkSelfTo := A_TickCount
    }
}

; 전면화 실패를 센다. 다음 시도는 30 → 60 → 120초 뒤(그 뒤로 120초 간격)로 미뤄 15분 방치 킥 전에 몇 번 더 해 본다.
; 로그는 유휴 구간의 첫 실패와 까닭이 바뀐 때만 남긴다. 항상 false 를 돌려준다.
AFKRefocusFailed(reason, idleSec, fgLabel := "") {
    global afkNextDue, afkRefocusFails, afkRefocusLastErr
    afkRefocusFails += 1
    waitSec := 30 * 2 ** Min(afkRefocusFails - 1, 2)
    afkNextDue := A_TickCount + waitSec * 1000
    if (afkRefocusFails = 1 || reason != afkRefocusLastErr)
        AFKLog("refocus 실패: " reason " idle=" idleSec "s 앞 창=" (fgLabel = "" ? AFKForegroundLabel() : fgLabel)
            . " (다음 시도 " waitSec "초 뒤, 같은 까닭은 다시 적지 않음)")
    afkRefocusLastErr := reason
    return false
}

; 지금 앞에 있는 창을 "exe / 제목" 으로. 무엇이 GTA 포커스를 가져갔는지 로그로 알 수 있게 한다.
AFKForegroundLabel() {
    fgHwnd := WinExist("A")
    if (!fgHwnd)
        return "없음"
    exe := ""
    try exe := WinGetProcessName("ahk_id " fgHwnd)
    return (exe = "" ? "?" : exe) " / " WinGetTitleSafe(fgHwnd)
}

AFKInputAllowed() {
    global afkOn, config, gEarnBusy, gMenuBusy
    return afkOn && IsGTAActive()
        && AFKPhysicalIdleMs() >= Max(1, config["Settings"]["AFKUserIdleSec"]) * 1000
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
