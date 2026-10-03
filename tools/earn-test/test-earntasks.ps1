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
$script:earnCaseTotal = 0
if (-not (Test-Path -LiteralPath $AhkPath -PathType Leaf)) {
    throw "AutoHotkey executable not found: $AhkPath"
}

function Get-EarnFunctionBody {
    param([string]$Text, [string]$FunctionName)
    $pattern = '(?ms)^' + [regex]::Escape($FunctionName) + '\([^\r\n]*\) \{.*?^\}'
    $functionMatches = [regex]::Matches($Text, $pattern)
    if ($functionMatches.Count -ne 1) {
        throw "Expected one source function: $FunctionName ($($functionMatches.Count))"
    }
    return $functionMatches[0].Value
}

function Invoke-EarnOfflineCheck {
    param(
        [string]$Name,
        [string]$FunctionName,
        [string]$Driver,
        [int]$CaseCount
    )

    $functionBody = Get-EarnFunctionBody $sourceText $FunctionName
    $prefix = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
OnError(EarnOfflineFailure)
EarnOfflineFailure(failure, *) {
    FileAppend("FAIL offline runtime: " failure.Message "`n", "**")
    ExitApp(1)
}

'@
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
        $testProcess.StandardInput.WriteLine($prefix + $Driver + "`n" + $functionBody)
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
        $script:earnCaseTotal += $CaseCount
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
global EARN_PROMPT_AREA := [], mode := "", presses := 0, walks := 0, opened := false
cases := [["MissingOpen", false, 0, 0], ["FaceFail", false, 1, 0], ["ClosedEmpty", true, 1, 0], ["OpenEmpty", true, 0, 0], ["OpenMoney", true, 0, 1]]
for c in cases {
    mode := c[1], presses := 0, walks := 0, opened := InStr(mode, "Open") = 1
    result := EarnSafeCollect()
    if (result != c[2] || presses != c[3] || walks != c[4]) {
        FileAppend("FAIL " mode ": result=" result " presses=" presses " walks=" walks Chr(10), "*", "UTF-8")
        ExitApp(1)
    }
}
FileAppend("PASS SafeCollect cases=5" Chr(10), "*", "UTF-8")
ExitApp(0)
EarnSeen(name, area := "") {
    global mode, opened, walks
    if (name = "safe_prompt")
        return !opened && mode != "MissingOpen"
    if (name = "hud_safe_zero")
        return mode != "FaceFail" && (mode != "OpenMoney" || walks > 0)
    return name = "safe_close_prompt" && opened
}
EarnPress(*) {
    global presses, opened
    presses += 1
    opened := !opened
    return true
}
EarnWalk(*) {
    global walks
    walks += 1
    return true
}
EarnFace(*) => mode != "FaceFail"
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
global config := Map("Settings", Map("EarnWalkRetry", 3)), atMCT := false, inArcade := false, walkFirst := true, walkCalls := 0, order := "", laptopSeated := false, standOk := true, reloadOk := true
; Existing MCT, inside success/failure, outside success/failure, session entry failure.
cases := [[true,false,true,true,"",true], [false,true,true,true,"IW",true], [false,true,false,true,"IW",false],
    [false,false,true,true,"IRW",true], [false,false,false,true,"IRW",false], [false,false,true,false,"IR",false]]
for c in cases {
    atMCT := c[1], inArcade := c[2], walkFirst := c[3], reloadOk := c[4], walkCalls := 0, order := ""
    result := EarnGoHome()
    if (result != c[6] || order != c[5] || walkCalls > 1) {
        FileAppend("FAIL Home order=" order Chr(10), "*", "UTF-8")
        ExitApp(1)
    }
}
laptopSeated := true, standOk := true, atMCT := false, inArcade := true, walkFirst := true, order := ""
if (!EarnGoHome() || order != "DUVIW")
    throw Error("Laptop recovery must stand and verify before walking: " order)
standOk := false, order := ""
if (EarnGoHome() || order != "DUV")
    throw Error("Failed laptop exit must not navigate: " order)
FileAppend("PASS GoHome cases=8" Chr(10), "*", "UTF-8")
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
    return walkFirst
}
EarnGoTo(*) {
    FileAppend("FAIL GoHome must not use repeated destination search`n", "*")
    ExitApp(1)
}
EarnReloadInto(place, direction) {
    global order
    if (place != "Arcade" || direction != "Right")
        throw Error("Unexpected session destination")
    order .= "R"
    return reloadOk
}
EarnAborted() => false
EarnFail(*) => false
EarnLog(*) => true
EarnRejoin(*) {
    FileAppend("FAIL GoHome must not rejoin after navigation failure`n", "*")
    ExitApp(1)
}
EarnSeen(name,*) => name = "arcade_laptop_seated" && laptopSeated
Click(key) {
    global order
    order .= key = "Right Down" ? "D" : "U"
}
Sleep(*) => true
EarnSleep(*) => true
EarnWaitGone(*) {
    global order
    order .= "V"
    return standOk
}
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
    Invoke-EarnOfflineCheck 'SafeCollect' 'EarnSafeCollect' $collectDriver 5
    Invoke-EarnOfflineCheck 'InPlace' 'EarnInPlace' $placeDriver 4
    Invoke-EarnOfflineCheck 'GoHome' 'EarnGoHome' $homeDriver 8
    Invoke-EarnOfflineCheck 'SafeTask' 'EarnSafeTask' $safeDriver 3
    $atMCTDriver = @'
global EARN_PROMPT_AREA := [], visible := ""
for c in [["mct_sit",false],["arcade_laptop_seated",false],["mct_seated",true],["mct_title",true]] {
    visible := c[1]
    if (EarnAtMCT() != c[2])
        throw Error("MCT identity mismatch: " visible)
}
FileAppend("PASS AtMCT cases=4`n", "*")
ExitApp(0)
EarnSeen(name,*) => name = visible
'@
    Invoke-EarnOfflineCheck 'AtMCT' 'EarnAtMCT' $atMCTDriver 4
    $seatDriver = @'
global EARN_PROMPT_AREA := [], prompt := true, mctSeated := true, presses := 0
for c in [[true,true,true,1],[true,false,false,1],[false,false,false,0]] {
    prompt := c[1], mctSeated := c[2], presses := 0
    if (EarnConfirmMCTSeat() != c[3] || presses != c[4])
        throw Error("Generic sit prompt cannot confirm MCT arrival")
}
FileAppend("PASS MCTSeat cases=3`n", "*")
ExitApp(0)
EarnSeen(*) => prompt
EarnPress(key) {
    global presses
    if (key != "e")
        throw Error("Unexpected input")
    presses++
    return true
}
EarnWaitSeen(name,*) => name = "mct_seated" && mctSeated
EarnFail(*) => false
'@
    Invoke-EarnOfflineCheck 'MCTSeat' 'EarnConfirmMCTSeat' $seatDriver 3
    $basementDriver = @'
global mode := "", order := ""
for c in [["spawn",false,"S"],["walk",false,"SW"],["sleep",false,"SWL"],
    ["blip",false,"SWLB"],["edge",false,"SWLB"],["plan",false,"SWLBP"],
    ["goal",false,"SWLBP"],["nav",false,"SWLBPN"],["seat",false,"SWLBPNC"],["ok",true,"SWLBPNC"]] {
    mode := c[1], order := ""
    if (EarnArcadeBasementToMCT() != c[2] || order != c[3]) {
        FileAppend("FAIL Basement route " mode " order=" order "`n", "*")
        ExitApp(1)
    }
}
FileAppend("PASS BasementRoute cases=10`n", "*")
ExitApp(0)
EarnSeen(name,*) {
    global order
    order .= "S"
    return name = "arcade_basement_spawn" && mode != "spawn"
}
EarnWalk(path) {
    global order
    order .= "W"
    if (!RegExMatch(path, "^w:\d+$"))
        throw Error("Basement traversal must use the guarded forward segment")
    return mode != "walk"
}
EarnSleep(*) {
    global order
    order .= "L"
    return mode != "sleep"
}
EarnBlip(name, &a, &d) {
    global order
    order .= "B", a := 0, d := mode = "edge" ? 999 : 62
    return name = "mct" && mode != "blip"
}
EarnNavPlan(name, &t, &s, &g) {
    global order
    order .= "P", t := 0, s := 10, g := mode = "goal" ? 15 : 14
    return name = "mct" && mode != "plan"
}
EarnNavTo(name, prompt) {
    global order
    order .= "N"
    return name = "mct" && prompt = "mct_sit" && mode != "nav"
}
EarnConfirmMCTSeat() {
    global order
    order .= "C"
    return mode != "seat"
}
EarnFail(*) => false
EarnLog(*) => true
'@
    Invoke-EarnOfflineCheck 'BasementRoute' 'EarnArcadeBasementToMCT' $basementDriver 10
    $djDriver = @'
cases := [[-1,95,false],[0,95,true],[80,95,true],[86,95,true],[90,95,true],[90.1,95,true],[94,95,true],[95,95,false],[100,95,false],[80,80,false]]
for c in cases {
    if (EarnDJNeedsRebook(c[1],c[2]) != c[3])
        throw Error("DJ boundary " c[1])
}
FileAppend("PASS DJRebook cases=10`n", "*")
ExitApp(0)
'@
    Invoke-EarnOfflineCheck 'DJRebook' 'EarnDJNeedsRebook' $djDriver 10
    $mctDriver = @'
global config := Map("Settings", Map("EarnMCTOnly",1)), scene := "", failAt := "", order := ""
for c in [["list","",true,"C+OR"],["stand","",true,"+OR"],["chair","",true,"C+OR"],
    ["away","",false,""],["chair","C",false,"C"],["stand","+",false,"+E"],
    ["stand","O",false,"+OE"],["stand","R",false,"+ORE"]] {
    scene := c[1], failAt := c[2], order := ""
    if (EarnTaskMCTBegin() != c[3] || order != c[4])
        throw Error("MCT begin guard: " c[1] "/" c[2] " order=" order)
}
FileAppend("PASS MCTBegin cases=8`n", "*")
ExitApp(0)
EarnUIReady(name,*) => name = "mct_title" && scene = "list"
EarnAtMCT() => scene = "list" || scene = "chair"
EarnSeen(name,*) => name = "mct_sit" && scene = "stand"
EarnMCTClose() {
    global scene, order, failAt
    order .= "C"
    if (failAt = "C")
        return false
    scene := "stand"
    return true
}
EarnCEO(on) {
    global order, failAt
    if (!on)
        throw Error("Unexpected CEO cleanup")
    order .= "+"
    return failAt != "+"
}
EarnMCTOpen() {
    global order, failAt
    order .= "O"
    return failAt != "O"
}
EarnMCTRefresh() {
    global order, failAt
    order .= "R"
    return failAt != "R"
}
EarnTaskMCTEnd() {
    global order
    order .= "E"
    return true
}
EarnGoHome(*) {
    throw Error("MCT tasks must not travel")
}
EarnFail(*) => false
'@
    Invoke-EarnOfflineCheck 'MCTBegin' 'EarnTaskMCTBegin' $mctDriver 8
    $mctCleanupSupport = @'
EarnAborted() => endAbort
EarnUIReady(name,*) {
    global endScene
    if (name = endScene)
        return true
    ; Parent page remains visible behind known confirmation dialogs.
    return name = "bunker_page" && (endScene = "bunker_confirm" || endScene = "bunker_pending")
        || name = "nc_dj_menu" && InStr(endScene,"dj_confirm_") = 1
}
EarnUIClick(name,x,y,*) {
    global endScene, endFailure, endOrder
    if (!EarnUIReady(name))
        throw Error("Cleanup clicked an unconfirmed screen")
    if (name = "bunker_confirm") {
        if (x != 850 || y != 619)
            throw Error("Cleanup must never confirm a bunker purchase")
        endOrder .= "x", nextScene := "bunker_page"
    } else if (name = "bunker_pending") {
        if (x != 960 || y != 619)
            throw Error("Unexpected bunker acknowledgement coordinate")
        endOrder .= "p", nextScene := "bunker_page"
    } else if (name = "dj_confirm_solomun" || name = "dj_confirm_tale") {
        if (x != 750 || y != 628)
            throw Error("Cleanup must only click the observed left DJ Cancel")
        endOrder .= "d", nextScene := "nc_dj_menu"
    } else if (name = "nc_dj_menu") {
        if (x != 495 || y != 596)
            throw Error("Nightclub cleanup must first choose Home")
        endOrder .= "H", nextScene := "nc_dj_menu"
    } else {
        throw Error("Unexpected cleanup click " name)
    }
    if (endFailure = "click")
        return EarnFail("cleanup click rejected")
    endScene := endFailure = "unknown_after_click" ? "unknown" : nextScene
    return true
}
EarnWaitGone(*) => endFailure != "gone"
EarnSleep(*) => endFailure != "sleep"
EarnUIBackToMCT(guard,presses) {
    global endScene, endFailure, endOrder
    if (!EarnUIReady(guard))
        throw Error("Cleanup back from unknown screen")
    if (guard = "bunker_page" && presses = 2)
        endOrder .= "B2"
    else if (guard = "bunker_entry" && presses = 1)
        endOrder .= "E1"
    else if (guard = "nc_dj_menu" && presses = 1)
        endOrder .= "N1"
    else
        throw Error("Cleanup exceeded a confirmed back route")
    if (endFailure = "back")
        return EarnFail("cleanup back failed")
    if (endFailure != "back_unchanged")
        endScene := "mct_title"
    return true
}
EarnMCTClose() {
    global endScene, endFailure, endOrder
    if (endScene != "mct_title" && endScene != "mct_seated" && endScene != "mct_need_ceo")
        throw Error("Close without confirmed MCT state")
    endOrder .= "C"
    if (endFailure = "close_error")
        throw Error("cleanup close exception")
    if (endFailure = "close")
        return EarnFail("cleanup close failed")
    endScene := "mct_sit"
    return true
}
EarnCEO(on) {
    global endScene, endFailure, endOrder, endBoss
    if (on) {
        endOrder .= "+"
        if (endFailure = "register")
            return EarnFail("registration failed")
        endBoss := true
        if (endFailure = "register_error")
            throw Error("registration exception")
        return true
    }
    if (endScene != "mct_sit")
        throw Error("Retire attempted before returning to confirmed standing state")
    endOrder .= "-"
    if (endFailure = "retire")
        return EarnFail("cleanup retire failed")
    endBoss := false
    return true
}
EarnFail(reason) {
    global gEarnFail, endLogs
    gEarnFail := reason
    endLogs.Push(reason)
    return false
}
'@
    $mctEndDriver = @'
global endScene := "", endFailure := "", endOrder := "", endAbort := false, endBoss := true, gEarnFail := "", endLogs := []
cases := [
 ["mct_title","",false,"original",true,"C-"],
 ["mct_seated","",false,"original",true,"C-"],
 ["mct_need_ceo","",false,"original",true,"C-"],
 ["mct_sit","",false,"original",true,"-"],
 ["unknown","",false,"original",false,""],
 ["mct_title","",true,"original",false,""],
 ["bunker_confirm","",false,"original",true,"xB2C-"],
 ["bunker_pending","",false,"original",true,"pB2C-"],
 ["bunker_page","",false,"original",true,"B2C-"],
 ["bunker_entry","",false,"original",true,"E1C-"],
 ["nc_dj_menu","",false,"original",true,"HN1C-"],
 ["dj_confirm_solomun","",false,"original",true,"dHN1C-"],
 ["dj_confirm_tale","",false,"original",true,"dHN1C-"],
 ["mct_title","close",false,"original",false,"C"],
 ["mct_title","retire",false,"original",false,"C-"],
 ["bunker_confirm","click",false,"original",false,"x"],
 ["bunker_confirm","gone",false,"original",false,"x"],
 ["bunker_pending","click",false,"original",false,"p"],
 ["bunker_pending","gone",false,"original",false,"p"],
 ["dj_confirm_solomun","click",false,"original",false,"d"],
 ["dj_confirm_tale","gone",false,"original",false,"d"],
 ["bunker_page","back",false,"original",false,"B2"],
 ["nc_dj_menu","click",false,"original",false,"H"],
 ["nc_dj_menu","sleep",false,"original",false,"H"],
 ["nc_dj_menu","back",false,"original",false,"HN1"],
 ["bunker_confirm","unknown_after_click",false,"original",false,"x"],
 ["bunker_page","back_unchanged",false,"original",false,"B2"],
 ["unknown","",false,"",false,""],
 ["mct_title","close",false,"",false,"C"],
 ["mct_title","",false,"",true,"C-"],
 ["mct_sit","retire",false,"original",false,"-"],
 ["mct_title","close_error",false,"original",false,"C"]
]
for c in cases {
    endScene := c[1], endFailure := c[2], endAbort := c[3], gEarnFail := c[4], endOrder := "", endLogs := [], endBoss := true
    result := EarnTaskMCTEnd()
    if (result != c[5] || endOrder != c[6] || (result && endBoss))
        throw Error("MCT cleanup: " c[1] "/" c[2] " order=" endOrder " result=" result)
    if (c[4] != "" && gEarnFail != c[4])
        throw Error("Cleanup replaced the original task failure")
    if (c[4] = "" && ((!result && gEarnFail = "") || (result && gEarnFail != "")))
        throw Error("Cleanup must retain its own failure only when no prior failure exists")
}
FileAppend("PASS MCTEnd cases=32`n", "*")
ExitApp(0)
'@
    $mctEndDriver += "`n" + $mctCleanupSupport
    Invoke-EarnOfflineCheck 'MCTEnd' 'EarnTaskMCTEnd' $mctEndDriver 32
    $mctBeginCleanupDriver = @'
global config := Map(), endScene := "mct_sit", endFailure := "", endOrder := "", endAbort := false, endBoss := false, gEarnFail := "", endLogs := []
global beginFailure := "", beginFailedScene := ""
cases := [
 ["open","mct_sit",false,"+O-",false],
 ["open","mct_seated",false,"+OC-",false],
 ["open","unknown",false,"+O",true],
 ["refresh","bunker_entry",false,"+ORE1C-",false],
 ["refresh","bunker_page",false,"+ORB2C-",false],
 ["refresh","bunker_confirm",false,"+ORxB2C-",false],
 ["refresh","unknown",false,"+OR",true],
 ["register","mct_sit",false,"+-",false],
 ["","mct_title",true,"+OR",true]
]
for c in cases {
    beginFailure := c[1], beginFailedScene := c[2], endScene := "mct_sit", endFailure := c[1] = "register" ? "register" : "",
        endOrder := "", endBoss := false, gEarnFail := "", endLogs := []
    result := EarnTaskMCTBegin()
    if (result != c[3] || endOrder != c[4] || endBoss != c[5])
        throw Error("Begin cleanup: " c[1] "/" c[2] " order=" endOrder)
    if ((c[1] = "open" && gEarnFail != "opening failed") || (c[1] = "refresh" && gEarnFail != "refresh failed"))
        throw Error("Begin cleanup erased its original failure")
}
; A successful registration can be followed by a native screen-reading error.
; Cleanup errors are caught by the real End function and must not replace it.
for c in [["open_error","mct_seated","",false,"+OC-",false,"opening exception"],
    ["refresh_error","bunker_page","",false,"+ORB2C-",false,"refresh exception"],
    ["register_error","mct_sit","register_error",false,"+-",false,"registration exception"],
    ["open_error","mct_seated","close_error",false,"+OC",true,"opening exception"],
    ["refresh_error","bunker_page","",true,"+OR",true,"refresh exception"]] {
    beginFailure := c[1], beginFailedScene := c[2], endFailure := c[3], endAbort := c[4],
        endScene := "mct_sit", endOrder := "", endBoss := false, gEarnFail := "", endLogs := []
    caught := ""
    try EarnTaskMCTBegin()
    catch as beginException
        caught := beginException.Message
    if (caught != c[7] || endOrder != c[5] || endBoss != c[6])
        throw Error("Begin exception cleanup: " c[1] " order=" endOrder " exception=" caught)
}
FileAppend("PASS MCTBeginCleanup cases=14`n", "*")
ExitApp(0)
EarnAtMCT() => endScene = "mct_title" || endScene = "mct_seated"
EarnSeen(name,*) => EarnUIReady(name)
EarnMCTOpen() {
    global endScene, endOrder, beginFailure, beginFailedScene
    endOrder .= "O"
    if (beginFailure = "open" || beginFailure = "open_error") {
        endScene := beginFailedScene
        if (beginFailure = "open_error")
            throw Error("opening exception")
        return EarnFail("opening failed")
    }
    endScene := "mct_title"
    return true
}
EarnMCTRefresh() {
    global endScene, endOrder, beginFailure, beginFailedScene
    endOrder .= "R"
    if (beginFailure = "refresh" || beginFailure = "refresh_error") {
        endScene := beginFailedScene
        if (beginFailure = "refresh_error")
            throw Error("refresh exception")
        return EarnFail("refresh failed")
    }
    return true
}
'@
    $mctBeginCleanupDriver += "`n" + $mctCleanupSupport + "`n" + (Get-EarnFunctionBody $sourceText 'EarnTaskMCTEnd')
    Invoke-EarnOfflineCheck 'MCTBeginCleanup' 'EarnTaskMCTBegin' $mctBeginCleanupDriver 14
    $djFlowDriver = @'
global config := Map("Settings",Map("EarnDJPopularityPct",95)), popularity := 90, allowRebook := true,
    gain := 10, confirmations := 0, djScene := "mct", djMode := "", homeReads := 0, backs := 0,
    djClock := 0, lastPaymentAt := 0, pendingPopularity := 0, postRefreshes := 0
; Real Home reader/opening and DJ loop. A stale MCT value (92) is never authoritative.
cases := [[97,true,10,true,0,"mct",""],[90,true,10,true,1,"mct",""],
    [90,false,10,false,0,"mct",""],[90,true,0,false,1,"mct",""],
    [95,true,10,true,0,"mct",""],[94,true,10,true,1,"mct",""],
    [0,true,10,true,10,"mct",""],[0,true,5,false,10,"mct",""],
    [-1,true,10,false,0,"mct",""],[95,true,10,true,0,"home",""],
    [90,true,10,false,0,"unknown",""],[90,true,10,false,0,"mct","missing_label"],
    [90,true,10,false,0,"mct","open_failed"],[90,true,10,false,0,"mct","home_failed"],
    [90,true,10,false,1,"mct","post_label_missing"],
    [90,true,10,false,1,"mct","post_unreadable"],
    [95,true,10,false,0,"mct","back_failed"],[90,true,10,false,0,"mct","abort"],
    [91,true,10,true,1,"mct","post_cached"],
    [91,true,10,true,1,"mct","post_delayed"],
    [91,true,10,true,1,"mct","post_unreadable_delayed"],
    [91,true,10,false,1,"mct","post_refresh_failed"],
    [91,true,0,false,1,"mct","post_abort_wait"],
    [91,true,0,false,1,"mct","post_unknown_wait"],
    [91,true,10,true,1,"mct","post_at_deadline"],
    [91,true,10,false,1,"mct","post_after_deadline"]]
for c in cases {
    popularity := c[1], allowRebook := c[2], gain := c[3], confirmations := 0,
        djScene := c[6], djMode := c[7], homeReads := 0, backs := 0,
        djClock := 0, lastPaymentAt := 0, pendingPopularity := 0, postRefreshes := 0
    result := EarnDJSwapLoop(92)
    if (result != c[4] || confirmations != c[5] || (result && (djScene != "mct" || backs != confirmations + 1)))
        throw Error("DJ Home flow " A_Index ": result=" result " payments=" confirmations " scene=" djScene)
    if (c[1] >= 95 && confirmations)
        throw Error("Stale MCT reading spent money while Home already reached target")
    if (backs > confirmations + 1 || postRefreshes > confirmations)
        throw Error("DJ retried Home refresh more than once per payment")
    if ((djMode = "post_delayed" || djMode = "post_unreadable_delayed") && homeReads < 4)
        throw Error("DJ did not poll its delayed result")
    if ((djMode = "post_after_deadline" || (gain = 0 && djMode = "")) && djClock - lastPaymentAt != 16000)
        throw Error("DJ missing update did not stop at its 15-second read deadline")
    if (djMode = "post_abort_wait" && djClock - lastPaymentAt != 1500)
        throw Error("DJ kept reading after physical-input abort")
    if (djMode = "post_unknown_wait" && djClock - lastPaymentAt != 2000)
        throw Error("DJ kept reading after Home context disappeared")
}
FileAppend("PASS DJFlow cases=26`n", "*")
ExitApp(0)
EarnPopularityMCTPct() {
    throw Error("MCT popularity is diagnostic only and must not be read for DJ spending")
}
EarnBarFill(x1,x2,y,kind) {
    global popularity, homeReads, djScene, djMode, confirmations, djClock, lastPaymentAt, pendingPopularity
    if (x1 != 1069 || x2 != 1584 || y != 173 || kind != "pop" || djScene != "home")
        throw Error("DJ read pixels outside the confirmed Home popularity bar")
    homeReads++
    elapsed := djClock - lastPaymentAt
    if (confirmations && ((djMode = "post_delayed" && elapsed >= 6500)
        || (djMode = "post_unreadable_delayed" && elapsed >= 4500)
        || (djMode = "post_at_deadline" && elapsed >= 16000)
        || (djMode = "post_after_deadline" && elapsed >= 16500)))
        popularity := pendingPopularity
    if (djMode = "post_unreadable_delayed" && confirmations && elapsed < 4500)
        return -1
    return djMode = "post_unreadable" && confirmations ? -1 : popularity / 100
}
DJClockRead() => djClock
EarnAborted() => djMode = "abort" || (djMode = "post_abort_wait" && confirmations && djClock - lastPaymentAt >= 1500)
EarnUIReady(name,*) => !EarnAborted() && EarnSeen(name)
EarnSeen(name,*) {
    global allowRebook, djScene, djMode, confirmations, djClock, lastPaymentAt
    if (name = "mct_title")
        return djScene = "mct"
    if (name = "nc_popularity_home")
        return djScene = "home" && djMode != "missing_label" && !(djMode = "post_label_missing" && confirmations)
            && !(djMode = "post_unknown_wait" && confirmations && djClock - lastPaymentAt >= 2000)
    if (name = "nc_home")
        return djScene = "club" || djScene = "home" || djScene = "dj"
    if (name = "nc_dj_menu")
        return djScene = "home" || djScene = "dj"
    if (name = "mct_nightclub_card")
        return djScene = "mct"
    if (name = "dj_rebook_10k" || name = "dj_rebook_10k_right")
        return djScene = "dj" && allowRebook
    if (name = "dj_solomun" || name = "dj_resident" || name = "dj_resident_right")
        return djScene = "dj"
    return djScene = name
}
EarnUIClick(name,x,y,*) {
    global popularity, gain, confirmations, djScene, djMode, djClock, lastPaymentAt, pendingPopularity, postRefreshes
    if (!EarnUIReady(name))
        throw Error("DJ clicked an unconfirmed screen: " name " from " djScene)
    if (name = "mct_nightclub_card") {
        if (confirmations) {
            postRefreshes++
            if (djMode = "post_refresh_failed")
                return false
            if (djMode = "post_cached")
                popularity := pendingPopularity
        }
        if (djMode = "open_failed")
            return false
        djScene := "club"
    } else if (name = "nc_home") {
        if (djMode = "home_failed")
            return false
        djScene := "home"
    } else if (name = "nc_dj_menu") {
        djScene := "dj"
    } else if (name = "dj_rebook_10k" || name = "dj_rebook_10k_right") {
        djScene := name = "dj_rebook_10k" ? "dj_confirm_solomun" : "dj_confirm_tale"
    } else if (name = "dj_confirm_solomun" || name = "dj_confirm_tale") {
        confirmations += 1
        pendingPopularity := Min(100,popularity+gain), lastPaymentAt := djClock
        if (djMode != "post_cached" && djMode != "post_delayed" && djMode != "post_unreadable_delayed"
            && djMode != "post_at_deadline" && djMode != "post_after_deadline")
            popularity := pendingPopularity
        djScene := "dj"
    } else {
        throw Error("Unexpected DJ click " name)
    }
    return true
}
EarnWaitSeen(name,*) => EarnSeen(name)
EarnWaitGone(name,*) => !EarnSeen(name)
EarnSleep(ms) {
    global djClock
    djClock += ms
    return !EarnAborted()
}
EarnUIBackToMCT(guard,presses) {
    global djScene, backs, djMode
    if (guard != "nc_dj_menu" || presses != 1 || djScene != "home")
        throw Error("DJ return must start on Home")
    if (djMode = "back_failed")
        return false
    djScene := "mct", backs++
    return true
}
EarnFail(*) => false
EarnLog(*) => true
'@
    foreach ($fn in @('EarnDJNeedsRebook','EarnDJHomeOpen','EarnPopularityHomePct')) {
        $djFlowDriver += "`n" + (Get-EarnFunctionBody $sourceText $fn)
    }
    # Preserve the actual wait body; only replace its monotonic clock to avoid real sleeps.
    $djFlowDriver += "`n" + (Get-EarnFunctionBody $sourceText 'EarnDJWaitForIncrease').Replace('A_TickCount', 'DJClockRead()')
    Invoke-EarnOfflineCheck 'DJFlow' 'EarnDJSwapLoop' $djFlowDriver 26
    # Real saved pixels, real bar sampler and real Home reader. No desktop APIs.
    Add-Type -AssemblyName System.Drawing
    Add-Type -ReferencedAssemblies System.Drawing @'
using System;
using System.Collections.Generic;
using System.Drawing;
public static class EarnHomeTextFixture {
    public static bool Contains(Bitmap source, Bitmap mask) {
        var points = new List<Point>();
        var colors = new List<Color>();
        for (int y = 0; y < mask.Height; y++) for (int x = 0; x < mask.Width; x++) {
            Color c = mask.GetPixel(x, y);
            if (c.R == 255 && c.G == 0 && c.B == 255) continue;
            if (Math.Min(c.R, Math.Min(c.G, c.B)) < 220)
                throw new Exception("Home context template retained unstable background pixels");
            points.Add(new Point(x,y)); colors.Add(c);
        }
        if (points.Count < 1000) throw new Exception("Home context mask is incomplete");
        for (int y = 0; y + mask.Height <= source.Height; y++) {
            for (int x = 0; x + mask.Width <= source.Width; x++) {
                bool found = true;
                for (int p = 0; p < points.Count; p++) {
                    Color a = source.GetPixel(x + points[p].X, y + points[p].Y), b = colors[p];
                    if (Math.Abs(a.R-b.R)>40 || Math.Abs(a.G-b.G)>40 || Math.Abs(a.B-b.B)>40) {
                        found = false; break;
                    }
                }
                if (found) return true;
            }
        }
        return false;
    }
}
'@
    $fixtureRoot = Join-Path $PSScriptRoot 'test-earntasks-fixtures'
    $homeFixture = [Drawing.Bitmap]::FromFile((Join-Path $fixtureRoot 'nightclub-home-95.png'))
    $mctFixture = [Drawing.Bitmap]::FromFile((Join-Path $fixtureRoot 'mct-popularity-92.png'))
    $homeTemplate = [Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot '..\..\Images\Earn\1920x1080\nc_popularity_home.png'))
    try {
        if (-not [EarnHomeTextFixture]::Contains($homeFixture,$homeTemplate)) { throw 'Home text template does not match the observed Home screen' }
        if ([EarnHomeTextFixture]::Contains($mctFixture,$homeTemplate)) { throw 'Home text template accepted the MCT popularity card' }
        $pixelEntries = @()
        for ($x=1069; $x -le 1584; $x+=3) {
            $color = $homeFixture.GetPixel($x-728,173-135).ToArgb() -band 0xFFFFFF
            $pixelEntries += ('"{0},173",{1}' -f $x,$color)
        }
        for ($x=340; $x -le 708; $x+=3) {
            $color = $mctFixture.GetPixel($x-325,471-435).ToArgb() -band 0xFFFFFF
            $pixelEntries += ('"{0},471",{1}' -f $x,$color)
        }
    } finally {
        $homeFixture.Dispose(); $mctFixture.Dispose(); $homeTemplate.Dispose()
    }
    Write-Output 'PASS DJHomeTemplate cases=2 (saved pixels only)'
    $script:earnCaseTotal += 2
    $homePixelDriver = @'
global fixturePixels := Map(__PIXELS__), fixtureContext := "home", fixtureActive := true, fixtureAbort := false, pixelReads := 0
if (EarnPopularityHomePct() != 95 || pixelReads != 172 || EarnDJNeedsRebook(EarnPopularityHomePct()))
    throw Error("Observed Home 95% must not cause a DJ purchase")
fixtureContext := "mct", pixelReads := 0
if (EarnPopularityMCTPct() != 92 || pixelReads != 123)
    throw Error("MCT comparison fixture no longer represents the old 92% diagnostic")
pixelReads := 0
if (EarnPopularityHomePct() != -1 || pixelReads)
    throw Error("MCT pixels were accepted without Nightclub Home context")
fixtureContext := "unknown", pixelReads := 0
if (EarnPopularityHomePct() != -1 || pixelReads)
    throw Error("Unconfirmed Home text must block pixel reads")
fixtureContext := "home", fixtureActive := false, pixelReads := 0
if (EarnPopularityHomePct() != -1 || pixelReads)
    throw Error("Missing game focus must block Home reads")
fixtureActive := true, fixtureAbort := true, pixelReads := 0
if (EarnPopularityHomePct() != -1 || pixelReads)
    throw Error("Input cancellation must block Home reads")
FileAppend("PASS DJHomePixels cases=6`n", "*")
ExitApp(0)
EarnUIReady(name,area) {
    if (name != "nc_popularity_home" || area[1] != 0.38 || area[2] != 0.14 || area[3] != 0.54 || area[4] != 0.19)
        throw Error("Unexpected popularity context")
    return fixtureContext = "home" && !fixtureAbort
}
EarnSeen(name,*) => name = "mct_title" && fixtureContext = "mct"
IsGTAActive() => fixtureActive ? 1 : 0
WinGetClientPos(&cx,&cy,&cw,&ch,*) {
    cx := 0, cy := 0, cw := 1920, ch := 1080
}
CoordMode(*) => true
PixelGetColor(x,y) {
    global pixelReads
    pixelReads++
    return fixturePixels[x "," y]
}
'@
    $homePixelDriver = $homePixelDriver.Replace('__PIXELS__',($pixelEntries -join ','))
    $barReaderSource = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnCore.ahk') -Raw -Encoding UTF8
    foreach ($fn in @('EarnBarFill','EarnPopularityMCTPct')) {
        $homePixelDriver += "`n" + (Get-EarnFunctionBody $barReaderSource $fn)
    }
    $homePixelDriver += "`n" + (Get-EarnFunctionBody $sourceText 'EarnDJNeedsRebook')
    Invoke-EarnOfflineCheck 'DJHomePixels' 'EarnPopularityHomePct' $homePixelDriver 6
    $policyText = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnPolicy.ahk') -Raw -Encoding UTF8
    $screenText = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnScreen.ahk') -Raw -Encoding UTF8
    $bunkerPolicy = "`n" + (Get-EarnFunctionBody $policyText 'EarnBunkerOrderPlan')
    $bunkerTaskDriver = @'
global config := Map("Settings",Map("EarnBunkerIntervalSec",8400)), gEarnNextDue := Map(), gEarnBunkerOrdered := false
global c := [], buyCalls := 0, endCalls := 0
; stock, supply, interval, begin OK, buy OK, end OK, result, buys, ends, due milliseconds.
cases := [[0.4,1,8400,true,true,true,true,0,1,300000],
    [1,0,8400,true,true,true,true,0,1,300000],
    [0.4,0.75,1680,true,true,true,true,0,1,300000],
    [0.4,0,8400,true,true,true,true,1,1,600000],
    [0.4,0.8,1680,true,true,true,true,1,1,600000],
    [0.4,0.6,3360,true,true,true,true,1,1,600000],
    [0.4,0,1645,true,true,true,false,0,1,0],
    [-1,0,8400,true,true,true,false,0,1,0],
    [0.4,1.1,8400,true,true,true,false,0,1,0],
    [0.4,0,8400,false,true,true,false,0,0,0],
    [0.4,0,8400,true,false,true,false,1,1,600000],
    [0.4,0,8400,true,true,false,false,1,1,600000]]
for row in cases {
    c := row, config["Settings"]["EarnBunkerIntervalSec"] := c[3]
    gEarnNextDue := Map("bunker",0), buyCalls := 0, endCalls := 0, gEarnBunkerOrdered := true
    before := A_TickCount
    result := EarnBunkerTask()
    after := A_TickCount
    due := gEarnNextDue["bunker"]
    if (result != c[7] || buyCalls != c[8] || endCalls != c[9])
        throw Error("Bunker task result/cleanup " A_Index)
    if (c[10] = 0 ? due != 0 : due < before+c[10] || due > after+c[10])
        throw Error("Bunker task scheduling " A_Index " due=" due)
}
FileAppend("PASS BunkerTask cases=12`n", "*")
ExitApp(0)
EarnTaskMCTBegin() => c[4]
EarnTaskMCTEnd() {
    global endCalls, c
    endCalls++
    return c[6]
}
EarnBunkerBuy() {
    global buyCalls, c, gEarnBunkerOrdered
    if (gEarnBunkerOrdered)
        throw Error("Previous order state must reset")
    buyCalls++
    return c[5]
}
EarnBarFill(x1,x2,y,*) => y = 555 ? c[1] : c[2]
EarnLog(*) => true
EarnFail(*) => false
'@
    Invoke-EarnOfflineCheck 'BunkerTask' 'EarnBunkerTask' ($bunkerTaskDriver + $bunkerPolicy) 12
    $taskFinallyDriver = @'
global config := Map("Settings",Map("EarnBunkerIntervalSec",8400,"EarnDJPopularityPct",95)),
    gEarnNextDue := Map(), gEarnBunkerOrdered := false, gEarnFail := "",
    endScene := "mct_title", endFailure := "", endOrder := "", endAbort := false,
    endBoss := true, endLogs := [], taskMode := "", originalException := 0
cases := [
    ["read_throw","",false,"C-",false,true],
    ["write_throw","",false,"C-",false,true],
    ["write_throw","close_error",false,"C",true,true],
    ["write_throw","retire",false,"C-",true,true],
    ["abort_throw","",false,"",true,true],
    ["return_false","close_error",false,"C",true,false],
    ["ok","close_error",false,"C",true,false],
    ["ok","",true,"C-",false,false]
]
for task in [EarnBunkerTask, EarnDJTask, EarnWarehouseTask] {
    for c in cases {
        taskMode := c[1], endFailure := c[2], endScene := "mct_title", endOrder := "",
            endBoss := true, endAbort := false, gEarnFail := "", endLogs := [], gEarnNextDue := Map(),
            originalException := Error("original task exception"), caught := 0, result := false
        try result := task.Call()
        catch as taskException
            caught := taskException
        if (result != c[3] || endOrder != c[4] || endBoss != c[5])
            throw Error(task.Name " cleanup " c[1] " order=" endOrder " result=" result)
        if (c[6] ? !caught || ObjPtr(caught) != ObjPtr(originalException) : IsObject(caught))
            throw Error(task.Name " original exception was replaced or swallowed")
        if (taskMode = "return_false" && gEarnFail != "original task failure")
            throw Error(task.Name " cleanup replaced the original failure reason")
        if (taskMode = "ok" && endFailure = "close_error" && !InStr(gEarnFail,"cleanup close exception"))
            throw Error(task.Name " cleanup-only error was not reported")
    }
}
FileAppend("PASS MCTTaskFinally cases=24`n", "*")
ExitApp(0)
EarnTaskMCTBegin() => true
TaskReadGuard() {
    global taskMode, originalException
    if (taskMode = "read_throw")
        throw originalException
}
TaskWriteResult() {
    global taskMode, originalException, endAbort
    if (taskMode = "abort_throw")
        endAbort := true
    if (taskMode = "write_throw" || taskMode = "abort_throw")
        throw originalException
    return taskMode = "return_false" ? EarnFail("original task failure") : true
}
EarnBarFill(x1,x2,y,*) {
    TaskReadGuard()
    return y = 555 ? 0.4 : 0
}
EarnBunkerBuy() => TaskWriteResult()
EarnDJSwapLoop(*) {
    TaskReadGuard()
    return TaskWriteResult()
}
EarnWarehouseManage() {
    TaskReadGuard()
    return TaskWriteResult()
}
EarnLog(*) => true
'@
    $warehouseText = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnWarehouse.ahk') -Raw -Encoding UTF8
    $taskFinallyDriver += "`n" + $mctCleanupSupport + $bunkerPolicy
    foreach ($fn in @('EarnTaskMCTEnd','EarnDJTask','EarnDJNeedsRebook')) {
        $taskFinallyDriver += "`n" + (Get-EarnFunctionBody $sourceText $fn)
    }
    $taskFinallyDriver += "`n" + (Get-EarnFunctionBody $warehouseText 'EarnWarehouseTask')
    Invoke-EarnOfflineCheck 'MCTTaskFinally' 'EarnBunkerTask' $taskFinallyDriver 24
    $bunkerBuyDriver = @'
global config := Map("Settings",Map("EarnBunkerIntervalSec",8400)), gEarnBunkerOrdered := false
global c := Map(), stage := "mct", pays := 0, cancels := 0, reads := 0, buyClicks := 0
; Options, result, payments, cancellations, delivery confirmed, OCR reads.
cases := [
    ["empty",Map(),true,1,0,true,2],
    ["one-bar",Map("supply",0.8,"interval",1680,"quote","$15,000"),true,1,0,true,2],
    ["two-bars",Map("supply",0.6,"interval",3360,"quote","$30,000"),true,1,0,true,2],
    ["pending",Map("pending",true),true,0,0,false,0],
    ["price-too-high",Map("supply",0.8,"interval",1680,"quote","$30,000"),true,0,1,false,1],
    ["discount-unknown",Map("quote","$74,000"),true,0,1,false,1],
    ["OCR-letters",Map("quote","$75,OOO"),false,0,1,false,1],
    ["OCR-failed",Map("quote",false),false,0,1,false,1],
    ["second-price-changed",Map("quote2","$90,000"),true,0,1,false,2],
    ["second-OCR-failed",Map("quote2",false),false,0,1,false,2],
    ["full-stock",Map("stock",1),true,0,0,false,0],
    ["full-supply",Map("supply",1),true,0,0,false,0],
    ["past-boundary",Map("supply",0.75,"interval",1680),true,0,0,false,0],
    ["invalid-interval",Map("interval",1645),false,0,0,false,0],
    ["read-negative",Map("stock",-1),false,0,0,false,0],
    ["read-range",Map("supply",1.1),false,0,0,false,0],
    ["missing-card",Map("ready",false),false,0,0,false,0],
    ["card-click-failed",Map("fail","mct_bunker_card"),false,0,0,false,0],
    ["resupply-failed",Map("fail","bunker_resupply"),false,0,0,false,0],
    ["payment-send-failed",Map("fail","pay"),false,0,0,false,2],
    ["payment-outcome-unknown",Map("confirmGone",false),false,1,0,false,2],
    ["delivery-not-confirmed",Map("postPending",false),false,1,0,false,2],
    ["pending-dismiss-failed",Map("fail","bunker_pending"),false,1,0,true,2],
    ["return-failed",Map("back",false),false,1,0,true,2],
    ["entry-screen",Map("entry",true),true,1,0,true,2],
    ["missing-dialog",Map("dialog",false),false,0,0,false,0],
    ["cancel-failed",Map("quote","$90,000","fail","cancel"),false,0,0,false,1],
    ["pending-dismiss-unknown",Map("pendingGone",false),false,1,0,true,2]]
for scenario in cases {
    c := scenario[2], config["Settings"]["EarnBunkerIntervalSec"] := c.Get("interval",8400)
    stage := "mct", pays := 0, cancels := 0, reads := 0, buyClicks := 0, gEarnBunkerOrdered := false
    result := EarnBunkerBuy()
    if (result != scenario[3] || pays != scenario[4] || cancels != scenario[5]
        || gEarnBunkerOrdered != scenario[6] || reads != scenario[7])
        throw Error("Bunker buy " scenario[1] ": result=" result " pays=" pays " cancels=" cancels " reads=" reads)
    if (pays > 1)
        throw Error("No repeated payment permitted")
}
FileAppend("PASS BunkerBuy cases=28`n", "*")
ExitApp(0)
EarnUIReady(name,*) => name = "mct_bunker_card" && stage = "mct" && c.Get("ready",true)
EarnBarFill(x1,x2,y,*) => y = 555 ? c.Get("stock",0.4) : c.Get("supply",0)
EarnSeen(name,*) => stage = name
EarnWaitSeen(name,*) => EarnSeen(name)
EarnWaitGone(name,*) {
    global c, stage
    return stage != name && (name != "bunker_confirm" || c.Get("confirmGone",true))
        && (name != "bunker_pending" || c.Get("pendingGone",true))
}
EarnUIClick(name,x,y,*) {
    global c, stage, pays, cancels, buyClicks
    action := name = "bunker_confirm" ? (x = 1065 ? "pay" : "cancel") : name
    if (c.Get("fail","") = action)
        return false
    switch name {
        case "mct_bunker_card":
            if (stage != "mct")
                throw Error("Card requires MCT")
            stage := c.Get("entry",false) ? "bunker_entry" : "bunker_page"
        case "bunker_entry":
            if (stage != name)
                throw Error("Entry requires visible entry")
            stage := "bunker_page"
        case "bunker_resupply":
            if (stage != "bunker_page")
                throw Error("Resupply requires bunker page")
            stage := "bunker_buy"
        case "bunker_buy":
            if (stage != name)
                throw Error("Buy requires purchase page")
            buyClicks++
            stage := buyClicks = 1 ? (c.Get("dialog",true) ? (c.Get("pending",false) ? "bunker_pending" : "bunker_confirm") : "unknown")
                : (c.Get("postPending",true) ? "bunker_pending" : "bunker_confirm")
        case "bunker_confirm":
            if (stage != name || (x != 1065 && x != 850))
                throw Error("Confirmation requires visible dialog and known button")
            if (x = 1065)
                pays++
            else
                cancels++
            stage := "bunker_buy"
        case "bunker_pending":
            if (stage != name)
                throw Error("Delivery dismissal requires confirmed delivery")
            stage := "bunker_buy"
        default:
            throw Error("Unexpected game action " name)
    }
    return true
}
EarnReadScreen(*) {
    global c, reads
    reads++
    value := reads = 1 ? c.Get("quote","$75,000") : c.Get("quote2",c.Get("quote","$75,000"))
    return Type(value) = "String" ? [{text:value}] : false
}
EarnUIBackToMCT(*) {
    global c, stage
    if (!c.Get("back",true))
        return false
    stage := "mct"
    return true
}
EarnSleep(*) => false
EarnLog(*) => true
EarnFail(*) => false
'@
    $bunkerBuyDriver += $bunkerPolicy + "`n" + (Get-EarnFunctionBody $policyText 'EarnBunkerPriceAllowed')
    $bunkerBuyDriver += "`n" + (Get-EarnFunctionBody $screenText 'EarnScreenText')
    $bunkerBuyDriver += "`n" + (Get-EarnFunctionBody $screenText 'EarnReadDollars')
    Invoke-EarnOfflineCheck 'BunkerBuy' 'EarnBunkerBuy' $bunkerBuyDriver 28
    $uiClickDriver = @'
global clickMode := "", clickAbort := false, cursorMoves := 0, mouseEvents := [], dpiCalls := 0
for c in [["normal",true,2,2,2,""],["abort-held",false,1,2,2,""],
    ["abort-before",false,0,0,0,""],["bad-size",false,0,0,2,""],
    ["abort-move",false,1,0,2,""],["lost-context",false,1,0,2,""],
    ["throw-held",false,1,2,2,"held failure"]] {
    clickMode := c[1], clickAbort := clickMode = "abort-before", cursorMoves := 0, mouseEvents := [], dpiCalls := 0
    result := false, caught := ""
    try result := EarnUIClick("known",100,200)
    catch as e
        caught := e.Message
    if (result != c[2] || cursorMoves != c[3] || mouseEvents.Length != c[4] || dpiCalls != c[5] || caught != c[6])
        throw Error("UI click " clickMode ": result=" result " cursor=" cursorMoves " events=" mouseEvents.Length " error=" caught)
    if (mouseEvents.Length && (mouseEvents[1] != "{Blind}{LButton down}" || mouseEvents[2] != "{Blind}{LButton up}"))
        throw Error("Mouse button was not released after an interrupted click")
}
FileAppend("PASS UIClickBoundary cases=7`n", "*")
ExitApp(0)
EarnAborted() => clickAbort
EarnUIReady(*) => !clickAbort && !(clickMode = "lost-context" && cursorMoves)
IsGTAActive() => 42
WinGetClientPos(&x,&y,&w,&h,window) {
    x := 10, y := 20, w := clickMode = "bad-size" ? 1280 : 1920, h := 1080
}
DllCall(name,args*) {
    global cursorMoves, dpiCalls
    if (name = "SetThreadDpiAwarenessContext") {
        dpiCalls++
        if ((dpiCalls = 1 && args[2] != -4) || (dpiCalls = 2 && args[2] != 77))
            throw Error("DPI context was not restored")
        return 77
    }
    if (name != "SetCursorPos")
        throw Error("Unexpected native call " name)
    if (clickAbort)
        throw Error("Cursor moved after physical-input abort")
    cursorMoves++
    return true
}
SendEvent(event) {
    global mouseEvents
    mouseEvents.Push(event)
}
Sleep(ms) {
    global clickAbort
    if (ms != 100)
        throw Error("Unexpected held-button delay")
    if (clickMode = "abort-held")
        clickAbort := true
    if (clickMode = "throw-held")
        throw Error("held failure")
}
EarnSleep(ms) {
    global clickAbort
    if (clickMode = "abort-move" && ms = 80)
        clickAbort := true
    return !clickAbort
}
EarnFail(*) => false
'@
    Invoke-EarnOfflineCheck 'UIClickBoundary' 'EarnUIClick' $uiClickDriver 7
    $sourceText = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\Earner.ahk') -Raw -Encoding UTF8
    $listDriver = @'
global config := Map("Settings", Map("EarnMCTOnly",1,"EarnBunker",1,"EarnBunkerIntervalSec",300,"EarnDJ",1,"EarnDJIntervalMin",5,"EarnSafe",1,"EarnSafeIntervalMin",210,"EarnDispatch",1,"EarnDispatchIntervalMin",48))
for mode in [1,0] {
    config["Settings"]["EarnMCTOnly"] := mode
    list := EarnTaskList()
    if (list.Length != 6 || list[1].id != "safe" || list[2].id != "bunker"
        || list[3].id != "dj" || list[4].id != "warehouse" || list[5].id != "staff" || list[6].id != "dispatch"
        || !list[1].on || !list[2].on || !list[3].on || !list[4].on || !list[5].on || list[6].on != !mode
        || list[1].fn != EarnVinewoodSafeTask || list[4].fn != EarnWarehouseTask || list[5].fn != EarnVinewoodStaffTask)
        throw Error("MCT task priority, phone safe, or warehouse routing")
}
FileAppend("PASS MCTTaskList cases=2`n", "*")
ExitApp(0)
EarnBunkerTask() => true
EarnDJTask() => true
EarnVinewoodSafeTask() => true
EarnWarehouseTask() => true
EarnVinewoodStaffTask() => true
EarnDispatchTask() => true
'@
    Invoke-EarnOfflineCheck 'MCTTaskList' 'EarnTaskList' $listDriver 2
    $sourceText = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnCore.ahk') -Raw -Encoding UTF8
    $ceoMenuDriver = @'
global EARN_MENU_AREA := [0,0,0.3,0.5], menuScene := "closed", menuBoss := true,
    menuCursor := 2, menuMode := "", menuOrder := "", menuAbort := false,
    retireRequests := 0, submenuUps := 0, menuTests := 0, menuFailure := ""
for c in [["main",true],["preferences",true],["boss",true],["securo",true],["unknown",false],["closed",false]] {
    menuScene := c[1]
    MenuCheck(EarnMenuIsOpen() = c[2], "known title " c[1])
}
MenuCheck(!EarnSeen("mct_need_ceo"), "CEO warning uses its bounded prompt area")
menuScene := "boss", menuCursor := 0, menuOrder := ""
MenuCheck(EarnSelectRow("m_ceo_sel",EARN_MENU_AREA,"Down",3) && menuOrder = "DD",
    "boss submenu can select a row that is not initially highlighted")
; Start registered, with SecuroServ and Retire both initially unselected.
for c in [["normal","closed",true,false,true,"MUUEUUUEMM",false,1,3],
    ["normal","closed",false,false,true,"MM",false,0,0],
    ["normal","closed",true,true,true,"MM",true,0,0],
    ["normal","securo",true,false,false,"M",true,0,0],
    ["normal","unknown",true,false,false,"",true,0,0],
    ["unknown_submenu","closed",true,false,false,"MUUE",true,0,0],
    ["abort_submenu","closed",true,false,false,"MUUE",true,0,0],
    ["missing_retire","closed",true,false,false,"MUUEUUUUUUUUUUUUM",true,0,12],
    ["reject_retire","closed",true,false,false,"MUUEUUUEM",true,1,3],
    ["verify_missing","closed",true,false,false,"MUUEUUUEMM",false,1,3]] {
    menuMode := c[1], menuScene := c[2], menuBoss := c[3], menuCursor := 2,
        menuOrder := "", menuAbort := false, retireRequests := 0, submenuUps := 0, menuFailure := ""
    result := EarnCEO(c[4])
    MenuCheck(result = c[5] && menuOrder = c[6] && menuBoss = c[7]
        && retireRequests = c[8] && submenuUps = c[9],
        "CEO flow " c[1] "/" c[2] " order=" menuOrder " result=" result)
    if (!result && menuFailure = "" && menuMode != "abort_submenu" && menuMode != "reject_retire")
        throw Error("CEO failure must have a reason")
}
FileAppend("PASS CEOSubmenu cases=" menuTests "`n", "*")
ExitApp(0)
MenuCheck(condition,label) {
    global menuTests
    if (!condition)
        throw Error(label)
    menuTests++
}
TemplateSeen(folder,name,area := "",&fx := 0,&fy := 0,variation := 40) {
    global menuScene, menuBoss, menuCursor, menuMode
    if (name = "mct_need_ceo" && (!(area is Array) || area.Length != 4
        || area[1] != 0 || area[2] != 0 || area[3] != 0.3 || area[4] != 0.1))
        throw Error("CEO warning lookup must not scan the whole transition screen")
    if (name = "m_sub_boss" || name = "m_sub_securo" || name = "m_securo"
        || name = "m_securo_sel" || name = "m_boss" || name = "m_boss_sel"
        || name = "m_retire_sel" || name = "m_ceo_sel" || name = "m_start_org_sel") {
        if (folder != "JobWarp")
            throw Error("Boss menu must use the shared JobWarp template: " name)
    } else if (folder != "Earn") {
        throw Error("Ordinary menu title must retain its Earn template: " name)
    }
    switch name {
        case "m_title": return menuScene = "main"
        case "m_pref_title": return menuScene = "preferences"
        case "m_sub_boss": return menuScene = "boss"
        case "m_sub_securo": return menuScene = "securo"
        case "m_securo": return menuScene = "main" && menuBoss
        case "m_securo_sel": return menuScene = "main" && menuBoss && menuCursor = 0
        case "m_boss": return menuScene = "main" && !menuBoss && menuMode != "verify_missing"
        case "m_boss_sel": return menuScene = "main" && !menuBoss && menuCursor = 0 && menuMode != "verify_missing"
        case "m_retire_sel": return menuScene = "securo" && menuCursor = 7 && menuMode != "missing_retire"
        case "m_ceo_sel": return menuScene = "boss" && menuCursor = 2
        default: return false
    }
}
EarnPress(key) {
    global menuScene, menuBoss, menuCursor, menuMode, menuOrder, menuAbort, retireRequests, submenuUps
    if (menuAbort)
        return false
    menuOrder .= key = "m" ? "M" : key = "Enter" ? "E" : key = "Up" ? "U" : key = "Down" ? "D" : "?"
    if (key = "m") {
        if (menuScene = "unknown")
            throw Error("No input is allowed on an unknown menu")
        menuScene := menuScene = "closed" ? "main" : "closed", menuCursor := 2
    } else if (key = "Up" && menuScene = "main") {
        menuCursor := Max(0,menuCursor-1)
    } else if (key = "Up" && menuScene = "securo") {
        menuCursor := Mod(menuCursor+7,8), submenuUps++
    } else if (key = "Down" && menuScene = "boss") {
        menuCursor++
    } else if (key = "Enter" && menuScene = "main" && menuBoss && menuCursor = 0) {
        menuScene := menuMode = "unknown_submenu" ? "unknown" : "securo", menuCursor := 2
        menuAbort := menuMode = "abort_submenu"
    } else if (key = "Enter" && menuScene = "securo" && menuCursor = 7) {
        retireRequests++
        if (menuMode = "reject_retire")
            return false
        menuBoss := false, menuScene := "closed"
    } else {
        throw Error("Unexpected CEO menu input " key " in " menuScene)
    }
    return true
}
EarnHudVisible() => menuScene = "closed"
EarnWaitSeen(name,*) => EarnSeen(name)
EarnSleep(*) => !menuAbort
Sleep(*) => true
EarnLog(*) => true
EarnFail(reason) {
    global menuFailure
    menuFailure := reason
    return false
}
'@
    foreach ($fn in @('EarnSeen','EarnMenuIsOpen','EarnSelectRow','EarnMenuOpen','EarnMenuClose','EarnCEOIs')) {
        $ceoMenuDriver += "`n" + (Get-EarnFunctionBody $sourceText $fn)
    }
    Invoke-EarnOfflineCheck 'CEOSubmenu' 'EarnCEO' $ceoMenuDriver 18
    $mctCloseDriver = @'
global EARN_PROMPT_AREA := [], config := Map("Settings",Map("EarnTurnUnitsPerDeg",29))
global closeCase := Map(), scene := "", aborted := false, backspaces := 0, clicks := [], promptReads := 0, turns := 0, turnUnits := 0,
    closeClockMs := 0, seatedWaits := 0, seatedReads := 0, seatedAt := -1, stoodAt := -1, abortInputs := -1
; Options, result, Backspace presses, right-button events, camera turns, prompt waits.
cases := [
    ["list",Map("scene","mct_title"),true,1,2,0,1],
    ["CEO-message",Map("scene","mct_need_ceo"),true,1,2,0,1],
    ["seated",Map(),true,0,2,0,1],
    ["unknown",Map("scene","unknown"),false,0,0,0,0],
    ["close-timeout",Map("scene","mct_title","seatedAfter",9000),false,1,0,0,0],
    ["press-failed",Map("scene","mct_title","press",false),false,0,0,0,0],
    ["abort-before-click",Map("abortAt","start"),false,0,0,0,0],
    ["still-seated",Map("gone",false),false,0,2,0,0],
    ["reverse-wall",Map("prompt",false),true,0,2,1,2],
    ["prompt-still-missing",Map("prompt",false,"afterTurn",false),false,0,2,1,2],
    ["turn-failed",Map("prompt",false,"turn",false),false,0,2,0,1],
    ["abort-during-prompt",Map("abortAt","prompt"),false,0,2,0,1],
    ["abort-button-held",Map("abortAt","held"),false,0,2,0,0],
    ["abort-after-back",Map("scene","mct_title","abortAt","back"),false,1,0,0,0],
    ["calibrated-turn",Map("prompt",false,"sensitivity",15),true,0,2,1,2],
    ["delayed-seated",Map("scene","mct_title","seatedAfter",1200),true,1,2,0,1],
    ["abort-transition",Map("scene","mct_title","seatedAfter",1200,"abortAt","transition"),false,1,0,0,0],
    ["transient-stand-prompt",Map(),true,0,2,0,1],
    ["abort-standing",Map("abortAt","standing"),false,0,2,0,0]]
for scenario in cases {
    closeCase := scenario[2], scene := closeCase.Get("scene","mct_seated")
    aborted := closeCase.Get("abortAt","") = "start", backspaces := 0, clicks := [], promptReads := 0, turns := 0, turnUnits := 0,
        closeClockMs := 0, seatedWaits := 0, seatedReads := 0, seatedAt := -1, stoodAt := -1, abortInputs := -1
    config["Settings"]["EarnTurnUnitsPerDeg"] := closeCase.Get("sensitivity",29)
    result := EarnMCTClose()
    if (result != scenario[3] || backspaces != scenario[4] || clicks.Length != scenario[5]
        || turns != scenario[6] || promptReads != scenario[7])
        throw Error("MCT close " scenario[1] " result=" result " keys=" backspaces " clicks=" clicks.Length " turns=" turns " waits=" promptReads)
    if (clicks.Length && (clicks[1] != "Right Down" || clicks[2] != "Right Up"))
        throw Error("Right button must be released even after interruption")
    if (turns && turnUnits != Round(180*config["Settings"]["EarnTurnUnitsPerDeg"]))
        throw Error("Recovery must use one calibrated half-turn")
    if (backspaces > 1 || (scenario[1] = "seated" && seatedWaits))
        throw Error("A known seated state needs no close key; a transition must never resend it")
    if (scenario[1] = "delayed-seated" && (seatedWaits != 1 || seatedReads < 7 || seatedAt != 1200))
        throw Error("A prompt absent at 900ms must be allowed to arrive later without resending Backspace")
    if (scenario[1] = "close-timeout" && (seatedWaits != 1 || closeClockMs != 8000))
        throw Error("Close transition must stop at its single 8-second deadline")
    if (scenario[1] = "abort-transition" && (seatedWaits != 1 || closeClockMs != 400))
        throw Error("User input during the transition must stop before any stand/camera input")
    if (result && !FixtureCEOEntryReady())
        throw Error("Close allowed CEO menu entry before the stand animation finished")
    if (scenario[1] = "transient-stand-prompt" && closeClockMs - stoodAt != 3500)
        throw Error("A transient approach prompt must not bypass the stand animation wait")
    if (scenario[1] = "abort-standing" && (closeClockMs - stoodAt != 700
        || abortInputs != backspaces + clicks.Length + turns))
        throw Error("Stand wait did not stop promptly without further input")
}
FileAppend("PASS MCTClose cases=19`n", "*")
ExitApp(0)
EarnSeen(name,*) {
    global scene, closeCase, seatedReads, seatedAt
    if (scene = "transition" && name = "mct_seated") {
        seatedReads++
        if (closeClockMs >= closeCase.Get("seatedAfter",0))
            scene := "mct_seated", seatedAt := closeClockMs
    }
    return scene = name
}
EarnAborted() => aborted
EarnPress(key) {
    global closeCase, aborted, backspaces, scene
    if (key != "Backspace")
        throw Error("Unexpected close key " key)
    if (aborted || !closeCase.Get("press",true))
        return false
    backspaces++
    scene := "transition"
    if (closeCase.Get("abortAt","") = "back")
        aborted := true
    return true
}
Click(event) {
    global clicks, aborted
    if (event != "Right Down" && event != "Right Up")
        throw Error("Unexpected click " event)
    if (event = "Right Down" && aborted)
        throw Error("Right button pressed after abort")
    clicks.Push(event)
}
Sleep(ms) {
    global closeCase, aborted, closeClockMs, scene, stoodAt, abortInputs, backspaces, clicks, turns
    closeClockMs += ms
    if (closeCase.Get("abortAt","") = "held")
        aborted := true
    if (scene = "transition" && closeCase.Get("abortAt","") = "transition" && closeClockMs >= 400)
        aborted := true
    if (stoodAt >= 0 && closeCase.Get("abortAt","") = "standing" && closeClockMs - stoodAt >= 700) {
        aborted := true
        if (abortInputs < 0)
            abortInputs := backspaces + clicks.Length + turns
    }
}
CloseClock() => closeClockMs
FixtureCEOEntryReady() => !aborted && stoodAt >= 0 && closeClockMs - stoodAt >= 3500
EarnWaitGone(name,area,timeoutMs) {
    global closeCase, aborted, stoodAt, scene
    if (name != "mct_seated" || timeoutMs != 8000)
        throw Error("Must confirm standing before camera recovery")
    if (aborted || !closeCase.Get("gone",true))
        return false
    stoodAt := closeClockMs, scene := "standing"
    return true
}
EarnWaitSeen(name,area,timeoutMs) {
    global closeCase, promptReads, aborted, seatedWaits
    if (timeoutMs != 8000)
        throw Error("Recovery must wait for the seated-entry prompt")
    if (name = "mct_seated") {
        seatedWaits++
        return FixtureWaitSeen(name,area,timeoutMs)
    }
    if (name != "mct_sit")
        throw Error("Unexpected close wait target " name)
    if (!FixtureCEOEntryReady())
        throw Error("Approach prompt checked while standing animation was still active")
    promptReads++
    if (closeCase.Get("abortAt","") = "prompt")
        aborted := true
    return !aborted && (promptReads = 1 ? closeCase.Get("prompt",true) : closeCase.Get("afterTurn",true))
}
EarnTurn(units) {
    global closeCase, aborted, turns, turnUnits
    if (aborted || !closeCase.Get("turn",true))
        return false
    turns++, turnUnits := units
    return true
}
EarnFail(*) => false
'@
    # Keep the production polling loop; replace only its clock and input-free dependencies.
    $closeWaitBody = (Get-EarnFunctionBody $sourceText 'EarnWaitSeen').Replace('EarnWaitSeen(', 'FixtureWaitSeen(').Replace('A_TickCount', 'CloseClock()')
    $mctCloseDriver += "`n" + $closeWaitBody + "`n" + (Get-EarnFunctionBody $sourceText 'EarnSleep').Replace('A_TickCount', 'CloseClock()')
    Invoke-EarnOfflineCheck 'MCTClose' 'EarnMCTClose' $mctCloseDriver 19
    $turnGuardDriver = @'
global turnCase := [], moves := 0, movedX := 0, movedY := 0
; Relative mouse calls are intercepted. Run the actual turn loop and input guards.
for scenario in [[5220,0,-1,-1,true,261,5220,0],
    [5220,0,0,-1,false,0,0,0],[5220,0,1,-1,false,1,20,0],
    [5220,0,-1,0,false,0,0,0],[5220,0,-1,1,false,1,20,0]] {
    turnCase := scenario, moves := 0, movedX := 0, movedY := 0
    if (EarnTurn(scenario[1]) != scenario[5] || moves != scenario[6]
        || movedX != scenario[7] || movedY != scenario[8])
        throw Error("Camera recovery must preserve abort/HUD guards and bounded movement")
}
FileAppend("PASS TurnGuard cases=5`n", "*")
ExitApp(0)
EarnAborted() => turnCase[3] >= 0 && moves >= turnCase[3]
EarnHudVisible() => turnCase[4] < 0 || moves < turnCase[4]
DllCall(name,args*) {
    global moves, movedX, movedY
    if (name != "mouse_event" || args[2] != 1 || Abs(args[4]) > 20 || Abs(args[6]) > 20)
        throw Error("Unexpected native input call")
    moves++, movedX += args[4], movedY += args[6]
    return 0
}
Sleep(*) => true
EarnFail(*) => false
'@
    Invoke-EarnOfflineCheck 'TurnGuard' 'EarnTurn' $turnGuardDriver 5
    $safeNavDriver = @'
global EARN_PROMPT_AREA := [], config := Map("Settings", Map("EarnTurnUnitsPerDeg",29))
; Open-safe prompt succeeds before navigation and at the final arrival check.
if (!EarnNavTo("safe", "safe_prompt", 12, 1) || !EarnNavTo("safe", "safe_prompt", 12, 0)
    || EarnNavTo("laptop", "laptop_prompt", 12, 0))
    throw Error("Open safe arrival must not start navigation or satisfy other prompts")
FileAppend("PASS OpenSafeNav cases=3`n", "*")
ExitApp(0)
EarnSeen(name,*) => name = "safe_close_prompt"
EarnAborted() => false
EarnFail(*) => false
EarnNavPlan(*) {
    throw Error("Already at open safe: navigation forbidden")
}
EarnBlip(*) => false
EarnWalk(*) => false
EarnTurn(*) => false
EarnFace(*) => false
EarnLog(*) => true
'@
    Invoke-EarnOfflineCheck 'OpenSafeNav' 'EarnNavTo' $safeNavDriver 3
    $mctNavDriver = @'
global EARN_PROMPT_AREA := [], config := Map("Settings", Map("EarnTurnUnitsPerDeg",29)), distance := 20, planCalls := 0
; Edge distance 999 with gp=0 must not become nearby after walking, in either final or next-loop check.
for c in [[20,1,true,0],[20,0,true,0],[100,1,false,1],[100,0,false,0],[999,1,false,1],[999,2,false,2]] {
    distance := c[1], planCalls := 0
    if (EarnNavTo("mct", "mct_sit", 12, c[2]) != c[3] || planCalls != c[4]) {
        FileAppend("FAIL Generic sit prompt must require nearby MCT; distance=" distance " steps=" c[2] "`n", "*")
        ExitApp(1)
    }
}
FileAppend("PASS MCTNav cases=6`n", "*")
ExitApp(0)
EarnSeen(name,*) => name = "mct_sit"
EarnAborted() => false
EarnFail(*) => false
EarnNavPlan(name, &a, &s, &g) {
    global planCalls
    planCalls++
    a := 0, s := 10, g := 0
    return true
}
EarnBlip(name, &a, &d) {
    a := 0, d := distance
    return true
}
EarnWalk(*) => distance = 999
EarnTurn(*) => false
EarnFace(*) => false
EarnLog(*) => true
Sleep(*) => true
'@
    Invoke-EarnOfflineCheck 'MCTNav' 'EarnNavTo' $mctNavDriver 6
    $faceDriver = @'
global config := Map("Settings", Map("EarnTurnUnitsPerDeg",29)), EARN_PROMPT_AREA := []
global sensitivity := 29, angle := 0, mode := "ok", turns := 0, walks := 0
for value in [14.5,29,40] {
    sensitivity := value, angle := 110, mode := "ok", turns := 0, walks := 0
    Check(EarnFace("mct") && Abs(angle) <= 5 && turns > 0 && turns < 8 && walks = 0, "sensitivity " value)
}
for c in [[179,-179],[-179,179]] {
    sensitivity := 29, angle := c[1], turns := 0
    Check(EarnFace("mct", c[2], 0.5) && Abs(Wrap(angle-c[2])) <= 0.5 && turns = 1, "angle boundary")
}
for testMode in ["blip-initial","blip-after","abort-initial","abort-after"] {
    sensitivity := 29, angle := 110, mode := testMode, turns := 0, walks := 0
    expectedTurns := InStr(mode,"initial") ? 0 : 1
    Check(!EarnFace("mct") && turns = expectedTurns && walks = 0, mode)
}
; Run the real navigation function with the real facing function. A lost sensor or
; cancellation during facing must stop before the first walking command.
for testMode in ["blip-after","abort-after"] {
    sensitivity := 29, angle := 30, mode := testMode, turns := 0, walks := 0
    Check(!EarnNavTo("mct", "", 12, 1) && turns = 1 && walks = 0, "navigation " mode)
}
FileAppend("PASS FaceControl cases=11`n", "*")
ExitApp(0)
Check(ok, label) {
    if (!ok) {
        FileAppend("FAIL FaceControl " label " angle=" angle " turns=" turns " walks=" walks "`n", "*")
        ExitApp(1)
    }
}
Wrap(value) => Mod(Mod(value + 180, 360) + 360, 360) - 180
EarnAborted() => mode = "abort-initial" || (mode = "abort-after" && turns > 0)
EarnBlip(name, &a, &d) {
    a := angle, d := 80
    return mode != "blip-initial" && !(mode = "blip-after" && turns > 0)
}
EarnTurn(units) {
    global angle, turns
    angle := Wrap(angle - units / sensitivity)
    turns++
    return true
}
EarnSleep(*) => true
EarnSeen(*) => false
EarnNavPlan(name, &a, &s, &g) {
    a := 20, s := 10, g := 5
    return true
}
EarnWalk(*) {
    global walks
    walks++
    return true
}
EarnFail(*) => false
EarnLog(*) => true
Sleep(*) => true
'@
    $faceDriver += "`n" + [regex]::Match($sourceText, '(?ms)^EarnNavTo\([^\r\n]*\) \{.*?^\}').Value
    Invoke-EarnOfflineCheck 'FaceControl' 'EarnFace' $faceDriver 11
    Write-Output "PASS EarnTasks: $script:earnCaseTotal cases; no game input"
} finally {
    [Console]::InputEncoding = $previousInputEncoding
}
