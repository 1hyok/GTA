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
global config := Map("Settings", Map("EarnMCTOnly",1)), visible := true, order := ""
for c in [[1,true,true,"VR"],[1,false,false,"V"],[0,true,true,"HO"]] {
    config["Settings"]["EarnMCTOnly"] := c[1], visible := c[2], order := ""
    if (EarnTaskMCTBegin() != c[3] || order != c[4])
        throw Error("MCT begin must not travel: " order)
}
FileAppend("PASS MCTBegin cases=3`n", "*")
ExitApp(0)
EarnUIReady(*) {
    global visible, order
    order .= "V"
    return visible
}
EarnGoHome() {
    global order
    order .= "H"
    return true
}
EarnMCTOpen() {
    global order
    order .= "O"
    return true
}
EarnFail(*) => false
EarnMCTRefresh() {
    global order
    order .= "R"
    return true
}
'@
    Invoke-EarnOfflineCheck 'MCTBegin' 'EarnTaskMCTBegin' $mctDriver 3
    $mctEndDriver = $mctDriver.Replace('EarnTaskMCTBegin()', 'EarnTaskMCTEnd()').Replace('MCTBegin', 'MCTEnd').Replace('[0,true,true,"HO"]','[0,true,true,"O"]').Replace('[1,true,true,"VR"]','[1,true,true,"V"]').Replace('EarnMCTOpen()', 'EarnMCTClose()')
    Invoke-EarnOfflineCheck 'MCTEnd' 'EarnTaskMCTEnd' $mctEndDriver 3
    $djFlowDriver = @'
global config := Map("Settings",Map("EarnDJPopularityPct",95)), popularity := 90, allowRebook := true, gain := 10, confirmations := 0
for c in [[97,true,10,true,0],[90,true,10,true,1],[90,false,10,false,0],[90,true,0,false,1]] {
    popularity := c[1], allowRebook := c[2], gain := c[3], confirmations := 0
    if (EarnDJSwapLoop(popularity) != c[4] || confirmations != c[5])
        throw Error("DJ purchase guard failed")
}
FileAppend("PASS DJFlow cases=4`n", "*")
ExitApp(0)
EarnPopularityMCTPct() {
    global popularity
    return popularity
}
EarnDJNeedsRebook(p,t) => p >= 0 && p < t
EarnSeen(name,*) {
    global allowRebook
    return (name != "dj_rebook_10k" && name != "dj_rebook_10k_right") || allowRebook
}
EarnUIClick(name,x,y,*) {
    global popularity, gain, confirmations
    if (name = "dj_confirm_solomun" || name = "dj_confirm_tale") {
        confirmations += 1
        popularity := Min(100,popularity+gain)
    }
    return true
}
EarnWaitSeen(*) => true
EarnWaitGone(*) => true
EarnSleep(*) => true
EarnUIBackToMCT(*) => true
EarnFail(*) => false
EarnLog(*) => true
'@
    Invoke-EarnOfflineCheck 'DJFlow' 'EarnDJSwapLoop' $djFlowDriver 4
    $sourceText = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\Earner.ahk') -Raw -Encoding UTF8
    $listDriver = @'
global config := Map("Settings", Map("EarnMCTOnly",1,"EarnBunker",1,"EarnBunkerIntervalSec",300,"EarnDJ",1,"EarnDJIntervalMin",5,"EarnSafe",1,"EarnSafeIntervalMin",210,"EarnDispatch",1,"EarnDispatchIntervalMin",48))
for mode in [1,0] {
    config["Settings"]["EarnMCTOnly"] := mode
    list := EarnTaskList()
    if (!list[1].on || !list[2].on || list[3].on != !mode || list[4].on != !mode)
        throw Error("MCT mode scheduled travel task")
}
FileAppend("PASS MCTTaskList cases=2`n", "*")
ExitApp(0)
EarnBunkerTask() => true
EarnDJTask() => true
EarnSafeTask() => true
EarnDispatchTask() => true
'@
    Invoke-EarnOfflineCheck 'MCTTaskList' 'EarnTaskList' $listDriver 2
    $sourceText = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnCore.ahk') -Raw -Encoding UTF8
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
    Write-Output 'PASS EarnTasks: 87 cases; no game input'
} finally {
    [Console]::InputEncoding = $previousInputEncoding
}
