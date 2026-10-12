#Requires -Version 5.1
<#
Runs production memory decisions, a Tick clone with stubbed readers/actions, and the real read-only memory readers.
No Main.ahk, no game input, no GTA memory allocation, nothing is closed. The production timer is disabled immediately.
#>
[CmdletBinding()]
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$guard = (Resolve-Path (Join-Path $PSScriptRoot '..\..\Features\MemoryGuard.ahk')).Path
$guardSource = Get-Content -LiteralPath $guard -Raw -Encoding UTF8
$closeGuard = [regex]::Match($guardSource, '(?ms)^MemGuardCloseGame\([^\r\n]*\) \{.*?^\}').Value
if (-not $closeGuard) { throw 'MemGuardCloseGame missing' }
$closeGuard = $closeGuard.Replace('MemGuardCloseGame(', 'FixtureMemGuardCloseGame(').
    Replace('MemGuardLog(', 'FixtureMemGuardLog(').
    Replace('ProcessClose(', 'FixtureProcessClose(').
    Replace('ProcessWaitClose(', 'FixtureProcessWaitClose(')
$tickGuard = [regex]::Match($guardSource, '(?ms)^MemGuardTick\([^\r\n]*\) \{.*?^\}').Value
if (-not $tickGuard) { throw 'MemGuardTick missing' }
$tickGuard = $tickGuard.Replace('MemGuardTick(', 'FixtureMemGuardTick(').
    Replace('ProcessExist(', 'FixtureProcessExist(').
    Replace('MemGuardSystemCommit(', 'FixtureSystemCommit(').
    Replace('MemGuardProcessGB(', 'FixtureProcessGB(').
    Replace('MemGuardDisplayNote(', 'FixtureDisplayNote(').
    Replace('MemGuardLog(', 'FixtureMemGuardLog(').
    Replace('MemGuardCloseGame(', 'FixtureTickClose(')
if ($tickGuard -match '\b(?:ProcessExist|MemGuardSystemCommit|MemGuardProcessGB|MemGuardDisplayNote|MemGuardLog|MemGuardCloseGame)\(' -or
    $closeGuard -match '\b(?:ProcessClose|ProcessWaitClose|MemGuardLog)\(') {
    throw 'Unsafe unstubbed fixture action'
}
$driver = @"
#Requires AutoHotkey v2.0
#NoTrayIcon
#Warn All, StdOut
#Include $guard
SetTimer(MemGuardTick, 0)
global config := Map("Settings", Map()), gEarnOn := false, gEarnBusy := false, GTA_WIN := "ahk_exe none.exe"
global setCalls := 0, setOn := true, setReason := "", releaseCalls := 0, closePID := 0, waitPID := 0
global fixtureMessages := [], fixtureLogs := [], fixturePID := 4242, fixturePct := 0, fixtureGtaGB := 17.5
global fixtureReadable := true, fixtureCloseCalls := 0, fixtureClosePID := 0
EarnLog(msg, *) {
    global fixtureMessages
    fixtureMessages.Push(msg)
}
SetEarner(on, reason := "", *) {
    global setCalls, setOn, setReason
    setCalls++, setOn := on, setReason := reason
}
ReleaseHeldKeys() {
    global releaseCalls
    releaseCalls++
}
FixtureMemGuardLog(msg, *) {
    global fixtureLogs
    fixtureLogs.Push(msg)
}
FixtureProcessClose(pid) {
    global closePID := pid
}
FixtureProcessWaitClose(pid, *) {
    global waitPID := pid
    return false
}
FixtureProcessExist(*) {
    global fixturePID
    return fixturePID
}
FixtureSystemCommit(&used, &limit) {
    global fixturePct, fixtureReadable
    used := fixturePct, limit := 100
    return fixtureReadable
}
FixtureProcessGB(*) {
    global fixtureGtaGB
    return fixtureGtaGB
}
FixtureDisplayNote(*) => "fixture display"
FixtureTickClose(pid, *) {
    global fixtureCloseCalls, fixtureClosePID
    fixtureCloseCalls++, fixtureClosePID := pid
}
FixtureReset() {
    global config, gMemGuardLevel, gMemGuardLastLog, gMemGuardPID, gMemGuardWarning
    global fixtureMessages, fixtureLogs, fixturePID, fixturePct, fixtureGtaGB, fixtureReadable, fixtureCloseCalls, fixtureClosePID
    config := Map("Settings", Map())
    gMemGuardLevel := "ok", gMemGuardLastLog := 0, gMemGuardPID := 0, gMemGuardWarning := "ok"
    fixtureMessages := [], fixtureLogs := [], fixturePID := 4242, fixturePct := 0, fixtureGtaGB := 17.5
    fixtureReadable := true, fixtureCloseCalls := 0, fixtureClosePID := 0
}
FixtureSamples(samples) {
    global fixturePct
    for sample in samples {
        fixturePct := sample
        FixtureMemGuardTick()
    }
}
$closeGuard
$tickGuard
n := 0
Check(MemGuardLevel(50, 10, 80, 92, 25) = "ok", "normal use stays ok")
Check(MemGuardLevel(80, 10, 80, 92, 25) = "warn", "warn threshold is inclusive")
Check(MemGuardLevel(95, 60, 80, 92, 25) = "close", "high commit with big GTA closes")
Check(MemGuardLevel(95, 10, 80, 92, 25) = "warn", "high commit from something else only warns")
Check(MemGuardLevel(95, -1, 80, 92, 25) = "warn", "unreadable GTA memory never closes")
Check(MemGuardLevel(99, 60, 80, 0, 25) = "warn", "close threshold 0 disables closing")
Check(MemGuardLevel(99, 60, 0, 0, 25) = "ok", "both thresholds 0 disable the guard")
gEarnOn := false, gEarnBusy := true
FixtureMemGuardCloseGame(4242, "fixture")
Check(setCalls = 1 && !setOn && setReason = "메모리 보호" && releaseCalls = 1
    && closePID = 4242 && waitPID = 4242, "memory close hard-stops an in-flight manual cleanup before closing GTA")
CheckReaders()
Check(MemGuardWarningLevel(79, 80, 92, "ok") = "ok", "below initial warning threshold stays armed")
Check(MemGuardWarningLevel(80, 80, 92, "ok") = "warn", "first warning is immediate and inclusive")
Check(MemGuardWarningLevel(79, 80, 92, "warn") = "warn", "79 percent retains warning latch")
Check(MemGuardWarningLevel(80, 80, 92, "warn") = "warn", "80 percent retains warning latch")
Check(MemGuardWarningLevel(76, 80, 92, "warn") = "warn", "recovery must reach five points below warning")
Check(MemGuardWarningLevel(75, 80, 92, "warn") = "ok", "75 percent rearms inclusively")
Check(MemGuardWarningLevel(92, 80, 92, "warn") = "high", "critical escalation bypasses existing warning latch")
Check(MemGuardWarningLevel(92, 80, 92, "ok") = "high", "first sample can immediately escalate to high")
Check(MemGuardWarningLevel(90, 80, 92, "high") = "high", "critical latch does not drop at 90 percent")
Check(MemGuardWarningLevel(92, 80, 92, "high") = "high", "critical threshold recrossing stays latched")
Check(MemGuardWarningLevel(75, 80, 92, "high") = "ok", "full recovery rearms critical latch")
Check(MemGuardWarningLevel(99, 80, 0, "ok") = "warn", "disabled close threshold has no high stage")
Check(MemGuardWarningLevel(99, 0, 92, "high") = "ok", "disabled warning clears warning latch")
Check(MemGuardWarningLevel(3, 3, 92, "ok") = "warn", "small positive warning threshold still warns")
Check(MemGuardWarningLevel(1, 3, 92, "warn") = "warn", "small warning threshold recovery floor is zero")
Check(MemGuardWarningLevel(0, 3, 92, "warn") = "ok", "zero recovery floor is reachable")
Check(MemGuardWarningLevel(70, 80, 70, "ok") = "ok", "high stage cannot bypass disabled warning range")

FixtureReset()
FixtureSamples([79, 80, 79, 80, 79, 80])
Check(fixtureMessages.Length = 1 && gMemGuardWarning = "warn", "production tick reduces boundary sequence from three warnings to one")
Check(InStr(fixtureMessages[1], "메모리 경고:") = 1 && !InStr(fixtureMessages[1], "다시 켜"), "warning does not prescribe GTA restart for system commit alone")
Check(fixtureLogs.Length = 6 && InStr(fixtureLogs[3], "ok alert=warn"), "raw level transitions remain logged while alerts stay latched")
FixtureSamples([76, 80])
Check(fixtureMessages.Length = 1, "insufficient recovery does not rearm tick warning")
FixtureSamples([75, 79, 80])
Check(fixtureMessages.Length = 2, "recovery then threshold crossing emits a fresh tick warning")
FixtureSamples([92])
Check(fixtureMessages.Length = 3 && gMemGuardWarning = "high" && InStr(fixtureMessages[3], "메모리 위험:") = 1, "tick escalates immediately above close percentage even with small GTA")
Check(fixtureCloseCalls = 0, "system commit from other processes alone never closes GTA")
FixtureSamples([90, 92, 91, 92])
Check(fixtureMessages.Length = 3, "high-stage boundary oscillation does not repeat warnings")
FixtureSamples([75, 92])
Check(fixtureMessages.Length = 4 && gMemGuardWarning = "high", "full recovery rearms direct critical warning")

FixtureReset()
FixtureSamples([92])
fixtureGtaGB := 25
FixtureSamples([92])
Check(fixtureCloseCalls = 1 && fixtureClosePID = 4242 && fixtureMessages.Length = 1, "newly satisfied GTA close gate overrides an already high alert latch")
FixtureSamples([92])
Check(fixtureCloseCalls = 2, "latched high state never suppresses repeated protective close attempts")
FixtureReset()
fixtureGtaGB := 24.99
FixtureSamples([92])
Check(fixtureCloseCalls = 0 && gMemGuardWarning = "high", "GTA private memory close threshold is not rounded upward")
FixtureReset()
fixtureGtaGB := -1
FixtureSamples([99])
Check(fixtureCloseCalls = 0 && fixtureMessages.Length = 1 && gMemGuardWarning = "high", "unreadable GTA size warns critically without closing")

FixtureReset()
config["Settings"]["MemClosePct"] := 0
fixtureGtaGB := 60
FixtureSamples([99, 79, 99])
Check(fixtureCloseCalls = 0 && fixtureMessages.Length = 1 && gMemGuardWarning = "warn", "disabled protective close stays disabled in tick")
FixtureReset()
config["Settings"]["MemWarnPct"] := 0
fixtureGtaGB := 25
FixtureSamples([92])
Check(fixtureCloseCalls = 1 && fixtureMessages.Length = 0, "disabled notifications do not disable protective closing")
FixtureReset()
config["Settings"]["MemWarnPct"] := 0
config["Settings"]["MemClosePct"] := 0
fixtureGtaGB := 60
FixtureSamples([99])
Check(fixtureCloseCalls = 0 && fixtureMessages.Length = 0 && gMemGuardWarning = "ok", "both disabled thresholds remain inert in tick")

FixtureReset()
FixtureSamples([80])
fixturePID := 0
FixtureSamples([80])
Check(gMemGuardPID = 0 && gMemGuardWarning = "ok" && gMemGuardLevel = "ok" && gMemGuardLastLog = 0 && fixtureMessages.Length = 1, "absent game clears alert and log state without notification")
fixturePID := 4242
FixtureSamples([80])
Check(fixtureMessages.Length = 2 && gMemGuardPID = 4242, "game returning after absence gets a fresh warning")
fixturePID := 4343
FixtureSamples([80])
Check(fixtureMessages.Length = 3 && gMemGuardPID = 4343, "new GTA PID rearms even without an observed absent interval")

FixtureReset()
FixtureSamples([80])
fixtureReadable := false
fixtureGtaGB := 60
FixtureSamples([99])
Check(fixtureMessages.Length = 1 && fixtureLogs.Length = 1 && fixtureCloseCalls = 0 && gMemGuardWarning = "warn", "failed commit read preserves the latch and never acts on failed data")
fixtureReadable := true
fixtureGtaGB := 17.5
FixtureSamples([80])
Check(fixtureMessages.Length = 1, "read recovery does not duplicate the warning")

FixtureReset()
FixtureSamples([79.49])
Check(fixtureMessages.Length = 0, "existing rounding keeps 79.49 percent below warning")
FixtureSamples([79.5])
Check(fixtureMessages.Length = 1 && InStr(fixtureMessages[1], "(80%)"), "existing rounding classifies 79.5 percent as 80")
FixtureReset()
FixtureSamples([80])
FixtureSamples([80])
Check(fixtureLogs.Length = 1 && fixtureMessages.Length = 1, "unchanged sample produces no extra periodic log or alert")
gMemGuardLastLog := A_TickCount - 600001
FixtureSamples([80])
Check(fixtureLogs.Length = 2 && fixtureMessages.Length = 1, "ten-minute diagnostic logging does not reissue user warning")
FileAppend("PASS MemGuard cases=" n, "*")
ExitApp(0)
CheckReaders() {
    Check(MemGuardSystemCommit(&usedGB, &limitGB) && limitGB > 2 && limitGB < 4096 && usedGB > 0 && usedGB < limitGB, "commit read")
    gb := MemGuardProcessGB(DllCall("GetCurrentProcessId"))
    Check(gb > 0 && gb < 1, "own private memory read " gb)
    Check(MemGuardProcessGB(0) = -1, "unopenable process reads -1")
    Check(MemGuardDisplayNote() ~= "^모니터 \d+", "display note")
}
Check(ok, name) {
    global n
    if (!ok)
        throw Error("FAIL " name)
    n += 1
}
"@
$path = Join-Path ([IO.Path]::GetTempPath()) ('gta-memguard-' + [Guid]::NewGuid().ToString('N') + '.ahk')
[IO.File]::WriteAllText($path, $driver, (New-Object Text.UTF8Encoding($true)))
try {
    $out = (& $AhkPath /ErrorStdOut $path 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $out -ne 'PASS MemGuard cases=54') { throw "MemGuard failed (exit=$LASTEXITCODE): $out" }
    Write-Output $out
} finally { [IO.File]::Delete($path) }
