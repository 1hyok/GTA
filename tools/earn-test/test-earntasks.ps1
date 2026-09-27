#Requires -Version 5.1
<#
Runs the actual EarnTasks.ahk functions with all game dependencies replaced.
No game input, screen reads, window activation, or Main.ahk execution.
Run: powershell -NoProfile -ExecutionPolicy Bypass -File tools/earn-test/test-earntasks.ps1
#>
[CmdletBinding()]
param(
    [string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
)

$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $PSScriptRoot '..\..\Features\Earn\EarnTasks.ahk'
$sourceText = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8
if (-not (Test-Path -LiteralPath $AhkPath -PathType Leaf)) {
    throw "AutoHotkey executable not found: $AhkPath"
}

function Invoke-EarnOfflineCheck {
    param(
        [string]$Name,
        [string]$FunctionName,
        [string]$Driver,
        [int]$CaseCount
    )

    $pattern = '(?ms)^' + [regex]::Escape($FunctionName) + '\([^\r\n]*\) \{.*?^\}'
    $functionMatches = [regex]::Matches($sourceText, $pattern)
    if ($functionMatches.Count -ne 1) {
        throw "Expected one source function: $FunctionName ($($functionMatches.Count))"
    }
    $prefix = "#Requires AutoHotkey v2.0`n#SingleInstance Off`n#NoTrayIcon`n#Warn All, StdOut`n"
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $AhkPath
    $info.Arguments = '/ErrorStdOut /CP65001 *'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $testProcess = [Diagnostics.Process]::Start($info)
    try {
        $testProcess.StandardInput.WriteLine($prefix + $Driver + "`n" + $functionMatches[0].Value)
        $testProcess.StandardInput.Close()
        if (-not $testProcess.WaitForExit(10000)) {
            $testProcess.Kill()
            $testProcess.WaitForExit()
            throw "$Name : AHK check timed out after 10 seconds"
        }
        $stdout = $testProcess.StandardOutput.ReadToEnd().Trim()
        $stderr = $testProcess.StandardError.ReadToEnd().Trim()
        $expected = "PASS $Name cases=$CaseCount"
        if ($testProcess.ExitCode -ne 0 -or $stderr -ne '' -or $stdout -ne $expected) {
            throw "$Name failed (exit=$($testProcess.ExitCode))`nstdout: $stdout`nstderr: $stderr"
        }
        Write-Output $stdout
    } finally {
        if (-not $testProcess.HasExited) {
            $testProcess.Kill()
            $testProcess.WaitForExit()
        }
        $testProcess.Dispose()
    }
}

$spawnDriver = @'
global config := Map("Settings", Map("EarnReachPx", 14))
global routeCase := []
; Name, safe seen/distance/plan/goal, laptop seen/distance/plan/goal, expected route.
cases := [
    ["edge path", false, 0, false, 0, true, 999, true, 80, "laptop"],
    ["edge no path", false, 0, false, 0, true, 999, false, 0, ""],
    ["office reachable", false, 0, false, 0, true, 80, true, 30, "laptop"],
    ["office blocked", false, 0, false, 0, true, 80, true, 31, ""],
    ["safe preferred", true, 60, true, 14, true, 999, true, 80, "safe"],
    ["safe blocked fallback", true, 60, true, 15, true, 999, true, 80, "laptop"],
    ["edge safe ignored", true, 999, true, 10, false, 0, false, 0, ""],
    ["no blips", false, 0, false, 0, false, 0, false, 0, ""]
]
for testCase in cases {
    routeCase := testCase
    actual := EarnSpawnRoute()
    if (actual != testCase[10]) {
        FileAppend("FAIL " testCase[1] ": expected=" testCase[10] " actual=" actual Chr(10), "*", "UTF-8")
        ExitApp(1)
    }
}
FileAppend("PASS SpawnRoute cases=8" Chr(10), "*", "UTF-8")
ExitApp(0)
EarnBlip(name, &angle, &distance) {
    global routeCase
    base := name = "safe" ? 2 : 6
    angle := 0
    distance := routeCase[base + 1]
    return routeCase[base]
}
EarnNavPlan(name, &angle, &step, &goal) {
    global routeCase
    base := name = "safe" ? 2 : 6
    angle := 0, step := 10, goal := routeCase[base + 3]
    return routeCase[base + 2]
}
'@

$collectDriver = @'
global EARN_PROMPT_AREA := [], mode := "", presses := 0, walks := 0, closeReads := 0
cases := [["MissingOpen", false, 0], ["FaceFail", false, 1], ["CloseStale", false, 1], ["Ready", true, 2]]
for c in cases {
    mode := c[1], presses := 0, walks := 0, closeReads := 0
    result := EarnSafeCollect()
    if (result != c[2] || presses != c[3] || walks != 0) {
        FileAppend("FAIL " mode ": result=" result " presses=" presses " walks=" walks Chr(10), "*", "UTF-8")
        ExitApp(1)
    }
}
FileAppend("PASS SafeCollect cases=4" Chr(10), "*", "UTF-8")
ExitApp(0)
EarnSeen(name, area := "") {
    global mode, closeReads
    if (name = "safe_prompt")
        return mode != "MissingOpen"
    if (name = "hud_safe_zero")
        return mode != "FaceFail"
    closeReads += 1
    return mode != "CloseStale" || closeReads = 1
}
EarnPress(*) {
    global presses
    presses += 1
    return true
}
EarnWalk(*) {
    global walks
    walks += 1
    return true
}
EarnFace(*) => false
EarnFail(*) => false
EarnSleep(*) => true
EarnLog(*) => true
EarnWaitGone(*) => true
'@

$placeDriver = @'
global EARN_MENU_AREA := [], openOk := true, seenOk := true, closeOk := true, closeCalls := 0
cases := [[true, true, true, true, 1], [true, true, false, false, 1], [true, false, true, false, 1], [false, true, true, false, 0]]
for c in cases {
    openOk := c[1], seenOk := c[2], closeOk := c[3], closeCalls := 0
    result := EarnInPlace("Arcade")
    if (result != c[4] || closeCalls != c[5]) {
        FileAppend("FAIL EarnInPlace" Chr(10), "*", "UTF-8")
        ExitApp(1)
    }
}
FileAppend("PASS InPlace cases=4" Chr(10), "*", "UTF-8")
ExitApp(0)
EarnMenuOpen() {
    global openOk
    return openOk
}
EarnSeen(*) {
    global seenOk
    return seenOk
}
EarnMenuClose() {
    global closeOk, closeCalls
    closeCalls += 1
    return closeOk
}
'@

$homeDriver = @'
global config := Map("Settings", Map("EarnWalkRetry", 3)), atMCT := false, inArcade := false, walkFirst := true, walkCalls := 0, order := ""
cases := [[true, false, true, ""], [false, true, true, "IW"], [false, false, true, "IGW"], [false, true, false, "IWGW"]]
for c in cases {
    atMCT := c[1], inArcade := c[2], walkFirst := c[3], walkCalls := 0, order := ""
    result := EarnGoHome()
    if (!result || order != c[4]) {
        FileAppend("FAIL Home order=" order Chr(10), "*", "UTF-8")
        ExitApp(1)
    }
}
FileAppend("PASS GoHome cases=4" Chr(10), "*", "UTF-8")
ExitApp(0)
EarnAtMCT() {
    global atMCT
    return atMCT
}
EarnInPlace(*) {
    global inArcade, order
    order .= "I"
    return inArcade
}
EarnWalkToMCT() {
    global walkFirst, walkCalls, order
    order .= "W", walkCalls += 1
    return walkFirst || walkCalls > 1
}
EarnGoTo(*) {
    global order
    order .= "G"
    return true
}
EarnAborted() => false
EarnFail(*) => false
EarnLog(*) => true
EarnRejoin(*) => false
'@

$safeDriver = @'
global config := Map("Settings", Map("EarnSafeRetryMin", 15, "EarnRerollMax", 12)), gEarnFail := "", gSafeCollectedTick := 0, homeOk := true, homeCalls := 0, softCalls := 0, inCalls := 0
for c in [[true, false], [false, false], [true, true]] {
    homeOk := c[1], gSafeCollectedTick := c[2] ? A_TickCount : 0, homeCalls := 0, softCalls := 0, inCalls := 0
    result := EarnSafeTask()
    if (result != homeOk || homeCalls != 1 || softCalls != (homeOk ? 0 : 1) || !gSafeCollectedTick || inCalls != (c[2] ? 0 : 1)) {
        FileAppend("FAIL SafeTask empty return" Chr(10), "*", "UTF-8")
        ExitApp(1)
    }
}
FileAppend("PASS SafeTask cases=3" Chr(10), "*", "UTF-8")
ExitApp(0)
EarnGoHome() {
    global homeOk, homeCalls
    homeCalls += 1
    return homeOk
}
EarnSoftFail(*) {
    global softCalls
    softCalls += 1
    return false
}
EarnInPlace(*) {
    global inCalls
    inCalls += 1
    return true
}
EarnSeen(*) => true
EarnLog(*) => true
EarnAborted() => false
EarnReloadInto(*) => false
EarnFail(*) => false
EarnSpawnRoute(*) => ""
EarnWalkToSafeVia(*) => false
EarnRejoin(*) => false
EarnSafeCollect(*) => false
'@

# Avoid a UTF-8 BOM in AHK stdin on Windows PowerShell 5.1; restore on exit.
$previousInputEncoding = [Console]::InputEncoding
try {
    [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
    Invoke-EarnOfflineCheck 'SpawnRoute' 'EarnSpawnRoute' $spawnDriver 8
    Invoke-EarnOfflineCheck 'SafeCollect' 'EarnSafeCollect' $collectDriver 4
    Invoke-EarnOfflineCheck 'InPlace' 'EarnInPlace' $placeDriver 4
    Invoke-EarnOfflineCheck 'GoHome' 'EarnGoHome' $homeDriver 4
    Invoke-EarnOfflineCheck 'SafeTask' 'EarnSafeTask' $safeDriver 3
    Write-Output 'PASS EarnTasks: 23 cases; no game input'
} finally {
    [Console]::InputEncoding = $previousInputEncoding
}
