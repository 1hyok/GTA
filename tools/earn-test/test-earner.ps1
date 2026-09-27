#Requires -Version 5.1
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
# Exercise the production scheduler with all window/input/timer dependencies replaced.
$source = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\Earner.ahk') -Raw -Encoding UTF8
$tick = [regex]::Match($source, '(?ms)^EarnTick\(\) \{.*?^\}').Value
if (-not $tick) { throw 'EarnTick missing' }
$guards = @('EarnInputGuardStart', 'EarnInputGuardStop', 'EarnInputWatch', 'EarnInputAllowed') | ForEach-Object { [regex]::Match($source, ('(?ms)^' + $_ + '\(\) \{.*?^\}')).Value }
$production = ($tick + "`n" + ($guards -join "`n")).Replace('A_TimeIdlePhysical', 'idleMs')
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global gEarnOn, gEarnBusy, gEarnDue, gEarnDone, gEarnTasks, gEarnCurrent, gEarnFail, gEarnNextDue, gEarnSoftFails, gEarnRetryIn, gAbort, config, GTA_WIN, afkOn
global calls, releaseCount, stopped, mode, windowExists, focused, otherBusy, activationCount, idleMs, gEarnGuardArmed, timers
Reset()
gEarnOn := false
EarnTick()
Check(calls.Length = 0, "disabled")
Reset()
gEarnBusy := true
EarnTick()
Check(calls.Length = 0, "busy")
Reset()
windowExists := false
EarnTick()
Check(calls.Length = 0, "no game")
Reset()
config["Settings"]["EarnUserIdleSec"] := 1000000000
EarnTick()
Check(calls.Length = 0, "user active")
Reset()
otherBusy := true
EarnTick()
Check(calls.Length = 0, "other macro")
Reset()
gEarnDue["bunker"] := A_TickCount + 300000
gEarnDue["dj"] := A_TickCount + 300000
EarnTick()
Check(calls.Length = 0, "not due")
Reset()
EarnTick()
EarnTick()
EarnTick()
Check(calls.Length = 2 && calls[1] = "bunker" && calls[2] = "dj", "serial and no immediate repeat")
Check(gEarnDone["bunker"] = 1 && gEarnDone["dj"] = 1 && releaseCount = 2, "counts and release")
gEarnDue["bunker"] := A_TickCount - 1
EarnTick()
Check(calls.Length = 3 && gEarnDone["bunker"] = 2, "next cycle")
Reset()
mode := "override"
EarnTick()
Check(gEarnDue["bunker"] > A_TickCount + 299000 && !gEarnNextDue.Has("bunker"), "task override consumed")
Reset()
mode := "retry"
EarnTick()
Check(gEarnOn && gEarnSoftFails["bunker"] = 1 && gEarnDue["bunker"] > A_TickCount + 59000, "soft retry")
gEarnDue["bunker"] := A_TickCount - 1
EarnTick()
Check(!gEarnOn && stopped = 1, "retry exhausted")
Reset()
mode := "fail"
EarnTick()
Check(!gEarnOn && stopped = 1 && releaseCount = 1 && !gEarnBusy, "hard failure")
Reset()
mode := "throw"
EarnTick()
Check(!gEarnOn && releaseCount = 1 && !gEarnBusy && InStr(gEarnFail, "test exception"), "exception releases")
Reset()
mode := "reenter"
EarnTick()
Check(calls.Length = 1 && releaseCount = 1, "reentry blocked")
Reset()
focused := false
EarnTick()
Check(calls.Length = 0 && activationCount = 0 && gEarnDue["bunker"] > A_TickCount + 29000, "focus loss postpones without activation")
Reset()
mode := "physical"
EarnTick()
Check(!gEarnOn && gAbort && stopped = 1 && !gEarnGuardArmed && gEarnDone["bunker"] = 0 && gEarnRetryIn = 0, "physical input stops instead of retry")
Reset()
mode := "focus"
EarnTick()
Check(!gEarnOn && gAbort && !gEarnGuardArmed && gEarnDone["bunker"] = 0, "focus loss stops")
Reset()
mode := "idle-zero"
EarnTick()
Check(!gEarnOn && gAbort, "physical guard still enabled with zero start wait")
Reset()
EarnInputGuardStart()
gAbort := true
Check(!EarnInputAllowed(), "abort stays latched")
EarnInputGuardStop()
Check(!gEarnGuardArmed && timers[timers.Length] = 0, "watch removed")
FileAppend("PASS Earner: 21 cases; no game input`n", "*")
ExitApp(0)

Reset() {
    global
    idleMs := 60000, gEarnGuardArmed := false, timers := []
    gEarnOn := true, gEarnBusy := false, gEarnCurrent := "", gEarnFail := "", gEarnRetryIn := 0, gAbort := false, afkOn := false
    gEarnDue := Map("bunker", A_TickCount - 1, "dj", A_TickCount - 1)
    gEarnDone := Map("bunker", 0, "dj", 0), gEarnNextDue := Map(), gEarnSoftFails := Map()
    gEarnTasks := [{id:"bunker", label:"bunker", on:true, every:300000, fn:RunTask.Bind("bunker")}, {id:"dj", label:"dj", on:true, every:300000, fn:RunTask.Bind("dj")}]
    config := Map("Settings", Map("EarnUserIdleSec", 0, "EarnSoftFailMax", 1), "Features", Map("AntiAFK", 0))
    GTA_WIN := "fake", calls := [], releaseCount := 0, stopped := 0, mode := "ok", windowExists := true, focused := true, otherBusy := false, activationCount := 0
}
RunTask(id) {
    global calls, mode, gEarnNextDue, gEarnRetryIn, idleMs, focused
    calls.Push(id)
    if (mode = "physical" || mode = "idle-zero") {
        idleMs := 0
        EarnInputWatch()
        gEarnRetryIn := 60000
        return true
    }
    if (mode = "focus") {
        focused := false
        EarnInputWatch()
        return true
    }
    if (mode = "override")
        gEarnNextDue[id] := A_TickCount + 300000
    if (mode = "retry") {
        gEarnRetryIn := 60000
        return false
    }
    if (mode = "fail")
        return EarnFail("expected failure")
    if (mode = "throw")
        throw Error("test exception")
    if (mode = "reenter")
        EarnTick()
    return true
}
Check(ok, name) {
    if (!ok) {
        FileAppend("FAIL " name "`n", "*")
        ExitApp(1)
    }
}
WinExist(*) => windowExists
IsGTAActive() => focused
EarnOtherMacroBusy() => otherBusy
BringGTAToFront() {
    global activationCount
    activationCount++
    return false
}
ReleaseHeldKeys() {
    global releaseCount
    releaseCount++
}
EarnFail(reason) {
    global gEarnFail
    gEarnFail := reason
    return false
}
SetEarner(on, *) {
    global gEarnOn, stopped
    gEarnOn := on
    stopped++
}
SetAntiAFK(*) {
    throw Error("unexpected AFK call")
}
SetTimer(fn, period) {
    global timers
    timers.Push(period)
}
EarnLog(*) {
}
ShowTooltip(*) {
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
        if (-not $p.WaitForExit(10000)) { $p.Kill(); throw 'Scheduler test timed out' }
        $stdout = $p.StandardOutput.ReadToEnd().Trim()
        $stderr = $p.StandardError.ReadToEnd().Trim()
        if ($p.ExitCode -ne 0 -or $stderr -or $stdout -ne 'PASS Earner: 21 cases; no game input') {
            throw "exit=$($p.ExitCode) stdout=$stdout stderr=$stderr"
        }
        $stdout
    } finally { $p.Dispose() }
} finally { [Console]::InputEncoding = $previous }
