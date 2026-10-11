#Requires -Version 5.1
<#
Runs the production MemGuardLevel decision and the real commit/process memory readers. No Main.ahk, no game input, nothing is closed.
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
$driver = @"
#Requires AutoHotkey v2.0
#NoTrayIcon
#Warn All, StdOut
#Include $guard
SetTimer(MemGuardTick, 0)
global config := Map("Settings", Map()), gEarnOn := false, gEarnBusy := false, GTA_WIN := "ahk_exe none.exe"
global setCalls := 0, setOn := true, setReason := "", releaseCalls := 0, closePID := 0, waitPID := 0
EarnLog(*) => true
SetEarner(on, reason := "", *) {
    global setCalls, setOn, setReason
    setCalls++, setOn := on, setReason := reason
}
ReleaseHeldKeys() {
    global releaseCalls
    releaseCalls++
}
FixtureMemGuardLog(*) => true
FixtureProcessClose(pid) {
    global closePID := pid
}
FixtureProcessWaitClose(pid, *) {
    global waitPID := pid
    return false
}
$closeGuard
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
    if ($LASTEXITCODE -ne 0 -or $out -ne 'PASS MemGuard cases=12') { throw "MemGuard failed (exit=$LASTEXITCODE): $out" }
    Write-Output $out
} finally { [IO.File]::Delete($path) }
