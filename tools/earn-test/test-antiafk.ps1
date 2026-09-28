#Requires -Version 5.1
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$source = Get-Content (Join-Path $PSScriptRoot '..\..\Features\AntiAFK.ahk') -Raw -Encoding UTF8
$functions = @('AntiAFKTick', 'AFKInputAllowed', 'AFKMousePulse', 'AFKRefocusGTA', 'AFKRefocusFailed', 'AFKForegroundLabel',
    'AFKPhysicalIdleMs', 'AFKOthersIdleMs', 'AFKSelfInput') | ForEach-Object {
    $body = [regex]::Match($source, ('(?ms)^' + $_ + '\([^)\r\n]*\) \{.*?^\}')).Value
    if (-not $body) { throw "$_ missing" }
    $body
}
# A_TimeIdlePhysical(훅이 본 물리 입력)은 idleMs, A_TimeIdle(주입 포함 전체 입력)은 AnyIdle() 로 바꿔 끼운다
$production = ($functions -join "`n").Replace('A_TimeIdlePhysical', 'idleMs').Replace('A_TimeIdle', 'AnyIdle()')
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
Reset()
afkOn := false
AntiAFKTick()
Check(events.Length = 0, "disabled")
Reset()
gEarnBusy := true
AntiAFKTick()
Check(events.Length = 0, "earn input owner")
Reset()
gMenuBusy := true
AntiAFKTick()
Check(events.Length = 0, "menu input owner")
Reset()
gAFKBusy := true
AntiAFKTick()
Check(events.Length = 0, "AFK reentry")
Reset()
clawLoopRunning := true
AntiAFKTick()
Check(events.Length = 0, "claw owner")
Reset()
teleportBusy := true
AntiAFKTick()
Check(events.Length = 0, "teleport owner")
Reset()
idleMs := 0
AntiAFKTick()
Check(events.Length = 0, "physical user input")
Reset()
afkNextDue := A_TickCount + 100000
AntiAFKTick()
Check(events.Length = 0, "not due")
Reset()
windowExists := false
AntiAFKTick()
Check(events.Length = 0, "game absent")
Reset()
focused := false
AntiAFKTick()
Check(events.Length = 0 && activations = 0 && !gAFKBusy && afkNextDue > A_TickCount && LogHas("skip: GTA 포커스 없음"), "no focus stealing while idle is short")
Reset()
AntiAFKTick()
Check(events.Length = 2 && events[1] = 2 && events[2] = -2 && !gAFKBusy && afkNextDue > A_TickCount, "MCT mouse only and scheduled")
Reset()
interrupt := true
AntiAFKTick()
Check(events.Length = 1 && !gAFKBusy && afkNextDue = 0, "user interrupts mouse pulse")
Reset()
config["Settings"]["EarnMCTOnly"] := 0
AntiAFKTick()
Check(events.Length = 4 && events[1] = "{w down}" && events[4] = "{s up}" && !gAFKBusy, "walk pair normal mode")
Reset()
config["Settings"]["EarnMCTOnly"] := 0
interrupt := true
AntiAFKTick()
Check(events.Length = 2 && events[2] = "{w up}" && !gAFKBusy, "release on interrupted key hold")
Reset()
config["Settings"]["AFKUserIdleSec"] := 0
idleMs := 0
Check(!AFKInputAllowed(), "zero idle setting still guards physical input")
Reset()
focused := false, idleMs := 301000
config["Settings"]["AFKRefocusSettleMs"] := 650
AntiAFKTick()
Check(activations = 1 && waits.Length && waits[1] = 650 && events.Length = 2 && !gAFKBusy && afkNextDue > A_TickCount + 100000 && LogHas("refocus ok idle=301s"), "refocus after long physical idle then settle and input")
Reset()
focused := false, idleMs := 301000, minimized := true
AntiAFKTick()
Check(restored = 1 && activations = 1 && events.Length = 2, "minimized game restored before activation")
Reset()
focused := false, idleMs := 900000
config["Settings"]["AFKRefocusIdleSec"] := 0
AntiAFKTick()
Check(activations = 0 && events.Length = 0 && afkNextDue > A_TickCount && LogHas("전면화 꺼짐"), "zero refocus setting never activates")
Reset()
focused := false, idleMs := 301000, activateWorks := false
AntiAFKTick()
firstGap := afkNextDue - A_TickCount
afkNextDue := 0
AntiAFKTick()
secondGap := afkNextDue - A_TickCount
afkNextDue := 0
AntiAFKTick()
afkNextDue := 0
AntiAFKTick()
fourthGap := afkNextDue - A_TickCount
Check(activations = 4 && events.Length = 0 && logs.Length = 1 && InStr(logs[1], "refocus 실패: 2초 안에") && !gAFKBusy
    && firstGap > 25000 && firstGap <= 30000 && secondGap > 55000 && secondGap <= 60000 && fourthGap > 115000 && fourthGap <= 120000,
    "failed refocus backs off and logs once")
Reset()
focused := false, idleMs := 400000, activateWorks := false
AntiAFKTick()
afkNextDue := 0
idleMs := 310000   ; 그사이 사람이 만졌다가 다시 비워 유휴 시작 시각이 바뀜
AntiAFKTick()
Check(activations = 2 && logs.Length = 2 && afkRefocusFails = 1 && afkNextDue - A_TickCount <= 30000, "new idle stretch restarts backoff and logging")
Reset()
focused := false, idleMs := 301000, stealBack := true
AntiAFKTick()
Check(activations = 1 && events.Length = 0 && afkRefocusFails = 1 && LogHas("다시 잃음") && afkNextDue - A_TickCount > 25000 && !gAFKBusy, "focus stolen back during settle")
Reset()
focused := false, idleMs := 301000, interrupt := true
AntiAFKTick()
Check(activations = 1 && events.Length = 0 && afkRefocusFails = 0 && afkNextDue - A_TickCount > 25000 && !gAFKBusy, "user returns during settle")
Reset()
focused := false, idleMs := 301000, activateWorks := false
AntiAFKTick()
afkNextDue := 0, activateWorks := true
AntiAFKTick()
Check(events.Length = 2 && afkRefocusFails = 0 && LogHas("앞선 실패 1회 뒤"), "success after failure clears count")
Reset()
focused := false, idleMs := 900000, anyIdleMs := 20000   ; 원격 데스크톱·에이전트가 20초 전에 다른 창에 입력
AntiAFKTick()
Check(activations = 0 && events.Length = 0 && afkNextDue > A_TickCount && LogHas("주입 포함 idle=20s"), "injected input from others blocks refocus")
Reset()
focused := false, idleMs := 301000, activateWorks := false
AntiAFKTick()
ownIgnored := AFKOthersIdleMs() >= 300000   ; 실패한 WinActivate 가 누른 Alt 는 남의 입력이 아니다
afkSelfFrom -= 3000, afkSelfTo -= 3000, anyInjectedAt := A_TickCount, afkNextDue := 0   ; 그 구간이 끝나고 3초 뒤 남이 입력
AntiAFKTick()
Check(ownIgnored && activations = 1 && LogHas("skip: GTA 포커스 없음"), "own Alt ignored, later outside input counted")
Reset()
focused := false, idleMs := 2000, hookExtraMs := 600000, afkHookTick := A_TickCount - 2000   ; Main 재시작 직후, 그 전 10분 비움
AntiAFKTick()
Check(activations = 1 && events.Length = 2 && LogHas("refocus ok idle=602s"), "fresh hook uses whole-input idle")
Reset()
focused := false, idleMs := 2000, hookExtraMs := 600000, afkHookTick := A_TickCount - 2000, interruptAt := 2
AntiAFKTick()
Check(activations = 1 && events.Length = 1 && !gAFKBusy, "fresh hook still sees user return during input")
Reset()
focused := false, idleMs := 301000, activateWorks := false, altRescue := true, frontExe := "TextInputHost.exe"
AntiAFKTick()
Check(activations = 2 && events.Length = 3 && events[1] = "{Alt down}{Alt up}" && LogHas("Alt 보조: TextInputHost.exe"), "input host in front gets one Alt")
Reset()
focused := false, idleMs := 301000, activateWorks := false, altRescue := true, frontExists := false
AntiAFKTick()
Check(activations = 2 && events.Length = 3 && events[1] = "{Alt down}{Alt up}" && LogHas("앞 창 없음"), "no foreground window gets one Alt")
Reset()
focused := false, idleMs := 301000, interrupt := true, stealBack := true
AntiAFKTick()
Check(activations = 1 && events.Length = 0 && afkRefocusFails = 0 && !gAFKBusy, "user returns and clicks elsewhere during settle")
FileAppend("PASS AntiAFK: 30 cases; no game input`n", "*")
ExitApp(0)
Reset() {
    global
    afkOn := true, afkFlip := false, afkNextDue := 0, gAFKBusy := false
    afkRefocusFails := 0, afkRefocusStretch := 0, afkRefocusLastErr := "", GTA_WIN := "fake"
    afkHookTick := 0, afkSelfFrom := 0, afkSelfTo := 0, afkSelfBefore := 0
    clawLoopRunning := false, gEarnBusy := false, gMenuBusy := false
    idleMs := 60000, hookExtraMs := 0, anyIdleMs := 1000000000, anyInjectedAt := 0
    focused := true, windowExists := true, frontExists := true, frontExe := "chrome.exe", teleportBusy := false
    interrupt := false, interruptAt := 0, events := []
    activations := 0, activateWorks := true, altRescue := false, altSent := false, minimized := false, restored := 0, stealBack := false
    logs := [], waits := []
    config := Map("Settings", Map("AFKUserIdleSec",45,"AFKJitterSec",0,"AFKIntervalSec",200,"AFKTapMs",100,"AFKGapMs",100,"EarnMCTOnly",1,
        "AFKRefocusIdleSec",300,"AFKRefocusSettleMs",800))
}
; 전체 입력 유휴(GetLastInputInfo). 물리 입력도 세므로 훅이 본 물리 유휴(+훅 설치 전 유휴)보다 길 수 없고, 주입 입력마다 0 이 된다.
AnyIdle() {
    global
    v := Min(idleMs + hookExtraMs, anyIdleMs)
    return anyInjectedAt ? Min(v, A_TickCount - anyInjectedAt) : v
}
LogHas(text) {
    for line in logs
        if InStr(line, text)
            return true
    return false
}
Check(ok, label) {
    if (!ok) {
        FileAppend("FAIL " label "`n", "*")
        ExitApp(1)
    }
}
WinExist(title := "") => title = "A" ? frontExists : windowExists
IsGTAActive() => focused
IsTeleportRunning() => teleportBusy
AnyInputToggleOn() => false
GetKeyState(*) => false
Send(value) {
    global events, anyInjectedAt, altSent
    if (!gAFKBusy)
        throw Error("input without ownership")
    events.Push(value)
    anyInjectedAt := A_TickCount
    if InStr(value, "Alt")
        altSent := true
}
DllCall(name, args*) {
    global events, anyInjectedAt
    if (name != "mouse_event" || !gAFKBusy)
        throw Error("unexpected native call")
    events.Push(args[4])
    anyInjectedAt := A_TickCount
}
AFKWait(ms) {
    global idleMs, hookExtraMs, focused
    waits.Push(ms)
    if (interrupt || (interruptAt && waits.Length >= interruptAt))
        idleMs := 0, hookExtraMs := 0
    if (stealBack)
        focused := false
    return AFKInputAllowed()
}
AFKLog(msg) {
    logs.Push(msg)
}
WinGetMinMax(*) => minimized ? -1 : 0
WinRestore(*) {
    global restored, minimized
    restored += 1
    minimized := false
}
WinActivate(*) {
    global activations, focused, anyInjectedAt
    if (!gAFKBusy)
        throw Error("activation without ownership")
    activations += 1
    if (activateWorks || (altRescue && altSent))
        focused := true
    else
        anyInjectedAt := A_TickCount   ; AHK 의 WinActivate 는 실패하면 Alt 를 두 번 누른다
}
WinWaitActive(*) => focused
WinGetProcessName(*) => frontExe
WinGetTitleSafe(*) => "about:blank"
'@
$previous = [Console]::InputEncoding
[Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
try {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $AhkPath
    $info.Arguments = '/ErrorStdOut /CP65001 *'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($info)
    try {
        $p.StandardInput.WriteLine($driver + "`n" + $production)
        $p.StandardInput.Close()
        if (-not $p.WaitForExit(10000)) { $p.Kill(); throw 'AFK test timed out' }
        $stdout = $p.StandardOutput.ReadToEnd().Trim()
        $stderr = $p.StandardError.ReadToEnd().Trim()
        if ($p.ExitCode -ne 0 -or $stderr -or $stdout -ne 'PASS AntiAFK: 30 cases; no game input') {
            throw "exit=$($p.ExitCode) stdout=$stdout stderr=$stderr"
        }
        $stdout
    } finally { $p.Dispose() }
} finally { [Console]::InputEncoding = $previous }
