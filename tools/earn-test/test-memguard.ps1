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
$stateHelpers = foreach ($name in @('MemGuardLoadState', 'MemGuardSaveState', 'MemGuardForgetState')) {
    $source = [regex]::Match($guardSource, ('(?ms)^' + $name + '\([^\r\n]*\) \{.*?^\}')).Value
    if (-not $source) { throw "$name missing" }
    $source.Replace($name + '(', 'Fixture' + $name + '(').Replace('MemGuardLog(', 'FixtureMemGuardLog(')
}
$stateHelpers = $stateHelpers -join "`n"
$tickGuard = [regex]::Match($guardSource, '(?ms)^MemGuardTick\([^\r\n]*\) \{.*?^\}').Value
if (-not $tickGuard) { throw 'MemGuardTick missing' }
$tickGuard = $tickGuard.Replace('MemGuardTick(', 'FixtureMemGuardTick(').
    Replace('ProcessExist(', 'FixtureProcessExist(').
    Replace('MemGuardProcessCreated(', 'FixtureProcessCreated(').
    Replace('MemGuardUtcNow(', 'FixtureUtcNow(').
    Replace('MemGuardLoadState(', 'FixtureMemGuardLoadState(').
    Replace('MemGuardSaveState(', 'FixtureMemGuardSaveState(').
    Replace('MemGuardForgetState(', 'FixtureMemGuardForgetState(').
    Replace('MemGuardSystemCommit(', 'FixtureSystemCommit(').
    Replace('MemGuardProcessGB(', 'FixtureProcessGB(').
    Replace('MemGuardDisplayNote(', 'FixtureDisplayNote(').
    Replace('MemGuardLog(', 'FixtureMemGuardLog(').
    Replace('MemGuardCloseGame(', 'FixtureTickClose(')
if ($tickGuard -match '\b(?:ProcessExist|MemGuardProcessCreated|MemGuardUtcNow|MemGuardLoadState|MemGuardSaveState|MemGuardForgetState|MemGuardSystemCommit|MemGuardProcessGB|MemGuardDisplayNote|MemGuardLog|MemGuardCloseGame)\(' -or
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
global fixtureCreated := 134000000000000000, fixtureNow := 134000000600000000
global gMemGuardStatePath := A_Args[1]
global n := 0
if (A_Args.Length > 1) {
    FixtureRestartPhase(A_Args[2])
    ExitApp(0)
}
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
FixtureProcessCreated(*) {
    global fixtureCreated
    return fixtureCreated
}
FixtureUtcNow() {
    global fixtureNow
    return fixtureNow
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
    global gMemGuardCreated, gMemGuardPolicy, gMemGuardStatePath, fixtureCreated, fixtureNow
    global fixtureMessages, fixtureLogs, fixturePID, fixturePct, fixtureGtaGB, fixtureReadable, fixtureCloseCalls, fixtureClosePID
    config := Map("Settings", Map())
    gMemGuardLevel := "ok", gMemGuardLastLog := 0, gMemGuardPID := 0, gMemGuardWarning := "ok"
    gMemGuardCreated := 0, gMemGuardPolicy := ""
    fixtureCreated := 134000000000000000, fixtureNow := 134000000600000000
    try FileDelete(gMemGuardStatePath)
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
$stateHelpers
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
Check(InStr(fixtureLogs[1], "수익 꺼짐") && !InStr(fixtureLogs[1], "증가 "), "first log carries earner state and no rate before a previous sample")
gMemGuardLastLog := A_TickCount - 600001
gMemGuardPrevTick := A_TickCount - 600000, gMemGuardPrevGB := 16.5
FixtureSamples([80])
Check(fixtureLogs.Length = 2 && fixtureMessages.Length = 1, "ten-minute diagnostic logging does not reissue user warning")
Check(InStr(fixtureLogs[2], "증가 102MB/분"), "periodic log carries growth rate since the previous log")
CheckPersistence()
FileAppend("PASS MemGuard cases=" n, "*")
ExitApp(0)
CheckReaders() {
    Check(MemGuardSystemCommit(&usedGB, &limitGB) && limitGB > 2 && limitGB < 4096 && usedGB > 0 && usedGB < limitGB, "commit read")
    gb := MemGuardProcessGB(DllCall("GetCurrentProcessId"))
    Check(gb > 0 && gb < 1, "own private memory read " gb)
    Check(MemGuardProcessGB(0) = -1, "unopenable process reads -1")
    created := MemGuardProcessCreated(DllCall("GetCurrentProcessId"))
    Check(created > 0 && created <= MemGuardUtcNow(), "own process creation uses read-only OS metadata")
    Check(MemGuardProcessCreated(0) = 0, "unopenable creation time is unknown")
    Check(MemGuardDisplayNote() ~= "^모니터 \d+", "display note")
}
CheckPersistence() {
    global fixtureCreated, fixtureNow, fixturePID, fixtureMessages, fixtureLogs, fixtureGtaGB
    global fixtureCloseCalls, gMemGuardWarning, gMemGuardPID, gMemGuardCreated, gMemGuardPolicy, gMemGuardStatePath, config
    FixtureReset()
    valid := "v1|4242|" fixtureCreated "|" fixtureNow "|80|92|25|warn"
    Check(MemGuardParseState(valid, 4242, fixtureCreated, "80|92|25", fixtureNow) = "warn", "valid same-process state restores warning")
    Check(MemGuardParseState(valid, 4242, fixtureCreated, "80|92|25", fixtureNow + 9000000000) = "warn", "15-minute freshness boundary remains valid")
    Check(MemGuardParseState(valid, 4242, fixtureCreated, "80|92|25", fixtureNow + 9000000001) = "", "state older than 15 minutes is rejected")
    Check(MemGuardParseState(valid, 4242, fixtureCreated, "80|92|25", fixtureNow - 1) = "", "future observation is rejected")
    Check(MemGuardParseState(valid, 4343, fixtureCreated, "80|92|25", fixtureNow) = "", "different PID cannot restore")
    Check(MemGuardParseState(valid, 4242, fixtureCreated + 1, "80|92|25", fixtureNow) = "", "reused PID with different creation cannot restore")
    for bad in ["", "v2|4242|1|2|80|92|25|warn", valid "|extra", StrReplace(valid, "warn", "close"),
        StrReplace(valid, "4242", "-1"), StrReplace(valid, "4242", "4294967296"),
        StrReplace(valid, "4242", "4242``n"), StrReplace(valid, fixtureCreated, "0"),
        StrReplace(valid, "4242", "4.242e3"), StrReplace(valid, fixtureCreated, "9999999999999999999"),
        StrReplace(valid, fixtureCreated, fixtureNow + 1), StrReplace(valid, "80|92|25", "NaN|92|25"),
        StrReplace(valid, "80|92|25", "101|92|25"), StrReplace(valid, "80|92|25", "80|92|-1"),
        StrReplace(valid, "80|92|25", "0|92|25"), StrReplace(valid, "80|92|25|warn", "80|0|25|high")]
        Check(MemGuardParseState(bad, 4242, fixtureCreated, "80|92|25", fixtureNow) = "", "malformed persisted state cannot suppress alerts")
    for policy in ["81|92|25", "80|93|25", "80|92|26"]
        Check(MemGuardParseState(valid, 4242, fixtureCreated, policy, fixtureNow) = "", "changed policy does not inherit old suppression")
    Check(FixtureMemGuardLoadState(gMemGuardStatePath, 4242, fixtureCreated, "80|92|25", fixtureNow) = "ok", "missing file starts armed")
    Check(FixtureMemGuardSaveState(gMemGuardStatePath, 4242, fixtureCreated, "80|92|25", "warn", fixtureNow), "atomic state write succeeds")
    Check(FileRead(gMemGuardStatePath, "UTF-8") = valid, "state file contains exact process identity and policy")
    Check(FixtureMemGuardLoadState(gMemGuardStatePath, 4242, fixtureCreated, "80|92|25", fixtureNow) = "warn", "saved state reloads")
    FileSetAttrib("+R", gMemGuardStatePath)
    try Check(FixtureMemGuardLoadState(gMemGuardStatePath, 4242, fixtureCreated, "80|92|25", fixtureNow) = "ok", "read-only stale suppression is not trusted")
    finally FileSetAttrib("-R", gMemGuardStatePath)
    FileDelete(gMemGuardStatePath)
    FileAppend("broken", gMemGuardStatePath, "UTF-8-RAW")
    Check(FixtureMemGuardLoadState(gMemGuardStatePath, 4242, fixtureCreated, "80|92|25", fixtureNow) = "ok", "corrupt file rearms instead of suppressing")
    Check(InStr(fixtureLogs[-1], "경고 이력 무시:") = 1, "corrupt state diagnosis is logged")
    FileDelete(gMemGuardStatePath)
    FileAppend(Format("{:0600}", 1), gMemGuardStatePath, "UTF-8-RAW")
    Check(FixtureMemGuardLoadState(gMemGuardStatePath, 4242, fixtureCreated, "80|92|25", fixtureNow) = "ok", "oversized file is rejected")
    FixtureReset()
    FixtureSamples([80])
    fixtureCreated += 1
    FixtureSamples([80])
    Check(fixtureMessages.Length = 2, "same PID with a new creation time rearms production tick")
    config["Settings"]["MemWarnPct"] := 81
    FixtureSamples([83])
    Check(fixtureMessages.Length = 3, "live policy changes rearm production tick")
    FixtureReset()
    fixtureCreated := 0
    FixtureSamples([80, 80])
    Check(fixtureMessages.Length = 1 && !FileExist(gMemGuardStatePath), "unknown creation preserves in-process dedupe but cannot persist it")
    FixtureReset()
    statePath := gMemGuardStatePath
    gMemGuardStatePath := statePath "\missing-parent\state.txt"
    FixtureSamples([80, 80, 92])
    Check(fixtureMessages.Length = 2 && gMemGuardWarning = "high", "write failure cannot hide warning or escalation")
    Check(InStr(fixtureLogs[-1], "경고 이력 저장 실패") = 1, "failed write is logged and retried")
    gMemGuardStatePath := statePath
    FixtureSamples([92])
    Check(FileExist(statePath) && fixtureMessages.Length = 2, "subsequent successful persistence does not duplicate alert")
}
FixtureRestartPhase(phase) {
    global fixtureMessages, fixtureLogs, fixtureCreated, fixtureNow, fixtureGtaGB, fixtureCloseCalls, gMemGuardWarning, gMemGuardStatePath, config
    switch phase {
        case "warn":
            FixtureSamples([83])
            Check(fixtureMessages.Length = 1 && gMemGuardWarning = "warn", "first process warns")
        case "reload":
            FixtureSamples([83])
            Check(fixtureMessages.Length = 0 && gMemGuardWarning = "warn", "second process restores warning without alert")
            Check(fixtureLogs.Length = 1 && InStr(fixtureLogs[1], "warn alert=warn"), "reload still logs first raw measurement")
        case "escalate":
            FixtureSamples([92])
            Check(fixtureMessages.Length = 1 && gMemGuardWarning = "high", "reloaded warning still escalates")
        case "high":
            FixtureSamples([92])
            Check(fixtureMessages.Length = 0 && gMemGuardWarning = "high", "critical warning survives reload")
            fixtureGtaGB := 25
            FixtureSamples([92])
            Check(fixtureCloseCalls = 1, "restored critical latch never suppresses protective close")
        case "recover":
            FixtureSamples([75])
            Check(fixtureMessages.Length = 0 && gMemGuardWarning = "ok", "recovery clears persisted warning")
        case "policy":
            config["Settings"]["MemClosePct"] := 91
            FixtureSamples([83])
            Check(fixtureMessages.Length = 1 && gMemGuardWarning = "warn", "new process with changed policy warns")
        case "new-game":
            fixtureCreated += 1
            FixtureSamples([83])
            Check(fixtureMessages.Length = 1 && gMemGuardWarning = "warn", "PID reused by new game warns after reload")
        case "stale":
            fixtureNow += 9000000001
            FixtureSamples([83])
            Check(fixtureMessages.Length = 1 && gMemGuardWarning = "warn", "stale prior process record cannot suppress warning")
        default:
            throw Error("Unknown restart phase")
    }
    FileAppend("PASS restart " phase, "*")
}
Check(ok, name) {
    global n
    if (!ok)
        throw Error("FAIL " name)
    n += 1
}
"@
$path = Join-Path ([IO.Path]::GetTempPath()) ('gta-memguard-' + [Guid]::NewGuid().ToString('N') + '.ahk')
$statePath = $path + '.state'
[IO.File]::WriteAllText($path, $driver, (New-Object Text.UTF8Encoding($true)))
try {
    $out = (& $AhkPath /ErrorStdOut $path $statePath 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $out -ne 'PASS MemGuard cases=97') { throw "MemGuard failed (exit=$LASTEXITCODE): $out" }
    Write-Output $out
    [IO.File]::Delete($statePath)
    foreach ($phase in @('warn', 'reload', 'escalate', 'high', 'recover', 'warn')) {
        $out = (& $AhkPath /ErrorStdOut $path $statePath $phase 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $out -ne "PASS restart $phase") { throw "MemGuard restart failed (exit=$LASTEXITCODE): $out" }
        Write-Output $out
    }
    foreach ($changed in @('policy', 'new-game', 'stale')) {
        [IO.File]::Delete($statePath)
        foreach ($phase in @('warn', $changed)) {
            $out = (& $AhkPath /ErrorStdOut $path $statePath $phase 2>&1 | Out-String).Trim()
            if ($LASTEXITCODE -ne 0 -or $out -ne "PASS restart $phase") { throw "MemGuard restart failed (exit=$LASTEXITCODE): $out" }
            Write-Output $out
        }
    }
} finally {
    [IO.File]::Delete($path)
    [IO.File]::Delete($statePath)
}
