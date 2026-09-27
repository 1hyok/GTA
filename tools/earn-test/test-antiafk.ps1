#Requires -Version 5.1
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$source = Get-Content (Join-Path $PSScriptRoot '..\..\Features\AntiAFK.ahk') -Raw -Encoding UTF8
$functions = @('AntiAFKTick', 'AFKInputAllowed', 'AFKMousePulse') | ForEach-Object { [regex]::Match($source, ('(?ms)^' + $_ + '\(\) \{.*?^\}')).Value }
$production = ($functions -join "`n").Replace('A_TimeIdlePhysical', 'idleMs')
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
Check(events.Length = 0 && !gAFKBusy && afkNextDue > A_TickCount, "no focus stealing")
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
FileAppend("PASS AntiAFK: 15 cases; no game input`n", "*")
ExitApp(0)
Reset() {
    global
    afkOn := true, afkFlip := false, afkNextDue := 0, gAFKBusy := false
    clawLoopRunning := false, gEarnBusy := false, gMenuBusy := false
    idleMs := 60000, focused := true, windowExists := true, teleportBusy := false, interrupt := false, events := []
    config := Map("Settings", Map("AFKUserIdleSec",45,"AFKJitterSec",0,"AFKIntervalSec",200,"AFKTapMs",100,"AFKGapMs",100,"EarnMCTOnly",1))
}
Check(ok, label) {
    if (!ok) {
        FileAppend("FAIL " label "`n", "*")
        ExitApp(1)
    }
}
WinExist(*) => windowExists
IsGTAActive() => focused
IsTeleportRunning() => teleportBusy
AnyInputToggleOn() => false
GetKeyState(*) => false
Send(value) {
    global events
    if (!gAFKBusy)
        throw Error("input without ownership")
    events.Push(value)
}
DllCall(name, args*) {
    global events
    if (name != "mouse_event" || !gAFKBusy)
        throw Error("unexpected native call")
    events.Push(args[4])
}
AFKWait(*) {
    global idleMs
    if (interrupt)
        idleMs := 0
    return AFKInputAllowed()
}
AFKLog(*) {
}
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
        if ($p.ExitCode -ne 0 -or $stderr -or $stdout -ne 'PASS AntiAFK: 15 cases; no game input') {
            throw "exit=$($p.ExitCode) stdout=$stdout stderr=$stderr"
        }
        $stdout
    } finally { $p.Dispose() }
} finally { [Console]::InputEncoding = $previous }
