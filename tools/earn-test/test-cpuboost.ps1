#Requires -Version 5.1
<#
Runs production CpuBoostTick, tray callbacks, and config persistence with isolated I/O.
No Main.ahk, live timer, powercfg, RTSS profile, input, or foreground changes.
#>
[CmdletBinding()]
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '..\..'
$src = Get-Content -LiteralPath (Join-Path $root 'Features\CpuBoost.ahk') -Raw -Encoding UTF8
$configSource = Get-Content -LiteralPath (Join-Path $root 'Core\ConfigLoader.ahk') -Raw -Encoding UTF8
$hotkeySource = Get-Content -LiteralPath (Join-Path $root 'Core\HotkeyManager.ahk') -Raw -Encoding UTF8
$tray = [regex]::Matches($hotkeySource, '(?ms)^SetupTrayMenu\([^\r\n]*\) \{.*?^\}')
if ($tray.Count -ne 1) { throw 'Expected exactly one production SetupTrayMenu' }
$timer = [regex]::Matches($src, '(?m)^SetTimer\(CpuBoostTick, 2000, (-?\d+)\)\s*$')
if ($timer.Count -ne 1) { throw 'Expected exactly one production CpuBoostTick timer' }
$src = $src.Remove($timer[0].Index, $timer[0].Length)
$publisher = [regex]::Matches($src, '(?m)^SetTimer\(CpuBoostPublishTick, 2000\)\s*$')
if ($publisher.Count -ne 1) { throw 'Expected one normal-priority lightweight publisher timer' }
$src = $src.Remove($publisher[0].Index, $publisher[0].Length)
$src = $src.Replace('RunWait(', 'TestRunWait(').Replace('FileOpen(', 'TestFpsFileOpen(').
    Replace('FileRead(', 'TestFpsFileRead(').Replace('EnvGet(', 'TestEnvGet(').
    Replace('A_TrayMenu', 'gTestTray').Replace('A_IconTip', 'gTestIconTip').Replace('A_TickCount', 'TestNow()').
    Replace('DllCall("GetTickCount64", "UInt64")', 'TestNow()')
$configSource = $configSource.Replace('A_ScriptDir', 'gFixtureRoot')
$traySource = $tray[0].Value.Replace('A_TrayMenu', 'gTestTray').Replace('A_IconTip', 'gTestIconTip')
if ($src -match '(?m)^SetTimer\(' -or $src -match '(?<!Test)Run(?:Wait)?\(') {
    throw 'Live side effect remained in CPU fixture.'
}
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('gta-cpuboost-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
#Warn LocalSameAsGlobal, Off
global n := 0, gFixtureRoot := "@FIXTURE@", gTestTray := FakeTray(), gTestIconTip := ""
global gEarnOn := false, testPhys := 0, testOthers := 0, testPowerExit := 0, testPowerCalls := []
global testFpsFail := "", testFpsOpens := 0, testFpsReads := 0, testLogs := [], testTips := []
global testPowerDelay := 0, testHeld := false, testPowerDuringHold := false, testHoldMs := 0
global testNowMs := 1000000
global testPhysicalHeld := false, testAwayFail := false
@CONFIG@
@CPU@
try {
    RunCases()
    FileAppend("PASS CpuBoost cases=" n "`n", "*")
    ExitApp(0)
} catch as failure {
    FileAppend("FAIL CpuBoost: " failure.Message " (line " failure.Line ")`n", "**")
    ExitApp(1)
}

RunCases() {
    global
    ResetState(1, 0, 0, false, 0, 0)
    Check(CpuBoostTick() && gCpuBoostState = "off" && ReadFps() = "30", "manual away overrides disabled idle policy and earn off")
    Check(testPowerCalls.Length = 1 && InStr(testPowerCalls[1], "PROCTHROTTLEMAX 99"), "manual mode calls boost-off command")
    Check(InStr(testPowerCalls[1], " && ") && !InStr(testPowerCalls[1], " & "), "power command stops on failed subcommand")
    Check(CpuBoostWanted(false, 999999, 300), "earner off keeps normal boost")
    Check(CpuBoostWanted(true, 299999, 300), "recent input keeps normal boost")
    Check(!CpuBoostWanted(true, 300000, 300), "idle earner turns normal boost off")
    Check(CpuBoostWanted(true, 999999, 0), "zero disables normal idle policy")
    Check(!CpuBoostWanted(false, 0, 0, true), "manual policy wins over no idle and disabled auto")
    Check(CpuBoostLastActive(0, 100000, 5000) = 95000, "first input sets last activity")
    Check(CpuBoostLastActive(95000, 130000, 900000) = 95000, "masked idle never moves activity back")
    Check(CpuBoostLastActive(95000, 130000, 1000) = 129000, "new input moves activity forward")

    ResetState(0, 0, 30, false, 0, 0)
    Check(CpuBoostTick(), "disabled untouched normal policy returns success")
    Check(testPowerCalls.Length = 0 && testFpsOpens = 0, "disabled untouched normal policy has no side effects")
    ResetState(0, 300, 24, true, 600000, 600000)
    testNowMs := 120000
    Check(CpuBoostTick() && gCpuBoostState = "on", "idle cannot exceed a fresh machine uptime")
    ResetState(0, 300, 24, true, 600000, 600000)
    Check(CpuBoostTick() && gCpuBoostState = "off" && ReadFps() = "24", "normal idle policy uses configured FPS")
    config["Settings"]["IdleFpsLimit"] := 20
    Check(CpuBoostTick() && ReadFps() = "20", "FPS setting changes while boost stays off")
    Check(testPowerCalls.Length = 1 && testFpsOpens = 2, "FPS-only change does not repeat power command")
    config["Settings"]["AwayMode"] := 1
    Check(CpuBoostTick() && ReadFps() = "30", "entering away replaces idle FPS while boost remains off")
    Check(testPowerCalls.Length = 1, "entering away does not repeat unchanged power state")
    config["Settings"]["IdleFpsLimit"] := 0
    testPhys := 0, testOthers := 0, gEarnOn := false
    Check(CpuBoostTick() && ReadFps() = "30", "input and earn stop cannot lift manual cap")
    Check(testPowerCalls.Length = 1 && testFpsOpens = 3, "unchanged manual request is not rewritten")
    config["Settings"]["AwayMode"] := 0
    Check(CpuBoostTick() && gCpuBoostState = "on" && ReadFps() = "0", "return to normal lifts cap for active user")
    Check(InStr(testPowerCalls[2], "PROCTHROTTLEMAX 100"), "return path calls normal boost command")

    ResetState(1, 300, 0, true, 600000, 600000)
    Check(CpuBoostTick() && ReadFps() = "30", "away ignores zero idle FPS")
    testPhys := 0
    Check(CpuBoostTick() && gCpuBoostState = "off", "physical input does not lift manual mode")
    testPhys := 600000, testOthers := 0
    Check(CpuBoostTick() && gCpuBoostState = "off", "injected input does not lift manual mode")
    config["Settings"]["AwayMode"] := 0
    Check(CpuBoostTick() && gCpuBoostState = "on", "normal policy again follows injected input")

    ResetState(1, 300, 60, true, 0, 0)
    testPowerExit := 5
    Check(!CpuBoostTick(), "powercfg nonzero is not success")
    Check(gCpuBoostState = "" && gCpuBoostFps = 30 && ReadFps() = "30", "failed CPU is uncached while independent FPS request succeeds")
    Check(InStr(gCpuBoostError, "powercfg exit=5"), "power exit is observable")
    logCount := testLogs.Length
    Check(!CpuBoostTick() && testLogs.Length = logCount, "identical failure is retried without log spam")
    Check(testPowerCalls.Length = 2 && testFpsOpens = 1, "failure retries only unapplied CPU state")
    testPowerExit := 0
    Check(CpuBoostTick() && gCpuBoostState = "off" && gCpuBoostError = "", "CPU recovers on next tick")

    ResetState(1, 0, 0, false, 0, 0)
    testFpsFail := "open"
    Check(!CpuBoostTick() && gCpuBoostState = "off" && gCpuBoostFps = "", "FPS open failure never caches success")
    Check(InStr(gCpuBoostError, "FPS"), "FPS failure is observable")
    testFpsFail := "read"
    Check(!CpuBoostTick() && gCpuBoostFps = "", "FPS read failure never caches success")
    testFpsFail := "mismatch"
    Check(!CpuBoostTick() && gCpuBoostFps = "", "FPS readback mismatch never caches success")
    testFpsFail := ""
    Check(CpuBoostTick() && gCpuBoostFps = 30 && gCpuBoostError = "", "FPS recovers on next tick")
    Check(testPowerCalls.Length = 1, "FPS retry does not repeat successful power command")

    ResetState(0, 300, 30, false, 0, 0)
    Check(CpuBoostTick() && gCpuBoostState = "on", "normal state exists before partial failure")
    config["Settings"]["AwayMode"] := 1
    testPowerExit := 5
    Check(!CpuBoostTick() && gCpuBoostState = "", "partial CPU failure invalidates previous on cache")
    config["Settings"]["AwayMode"] := 0
    testPowerExit := 0
    Check(CpuBoostTick() && testPowerCalls.Length = 3 && gCpuBoostState = "on", "reverse toggle reapplies normal power after partial failure")
    config["Settings"]["AwayMode"] := 1
    testFpsFail := "read"
    Check(!CpuBoostTick() && gCpuBoostFps = "" && ReadFps() = "30", "failed FPS readback invalidates previous zero cache")
    config["Settings"]["AwayMode"] := 0
    testFpsFail := ""
    Check(CpuBoostTick() && gCpuBoostFps = 0 && ReadFps() = "0", "reverse toggle restores FPS after failed write verification")
    ResetState(1, 0, 0, false, 0, 0)
    testPowerExit := 5, testFpsFail := "open"
    Check(!CpuBoostTick() && gCpuBoostState = "" && gCpuBoostFps = "" && gCpuBoostError != "", "both failed outputs retain unknown state")
    config["Settings"]["AwayMode"] := 0
    testPowerExit := 0, testFpsFail := ""
    Check(CpuBoostTick() && gCpuBoostState = "on" && ReadFps() = "0", "disabled auto still restores after both manual outputs failed")
    Check(testPowerCalls.Length = 2 && testFpsOpens = 2, "failed unknown state is not mistaken for untouched startup")

    ; Real ConfigLoader persistence and real tray callback wiring, all files under fixture.
    ResetState(0, 0, 0, false, 0, 0)
    WriteConfig("[Settings]`nCpuBoostIdleSec=0`nIdleFpsLimit=0`n")
    LoadConfig()
    Check(config["Settings"]["AwayMode"] = 0, "missing mode defaults off")
    SetupTrayMenu()
    Check(gTestTray.actions.Has("외출 저부하 켜기 (30 FPS)") && gTestTray.actions.Has("외출 저부하 끄기 (일반 복귀)"), "both real tray entries exist")
    Check(gTestTray.checked["외출 저부하 끄기 (일반 복귀)"], "tray initially reflects normal mode")
    gTestTray.actions["외출 저부하 켜기 (30 FPS)"].Call()
    Check(config["Settings"]["AwayMode"] = 1 && IniRead(gFixtureRoot "\Config.ini", "Settings", "AwayMode") = "1", "tray enable persists mode")
    Check(testPowerCalls.Length = 0 && testFpsOpens = 0 && InStr(testTips[testTips.Length], "적용 대기"), "tray never blocks game input on power command")
    Check(CpuBoostTick() && gCpuBoostState = "off" && ReadFps() = "30", "timer applies saved tray request")
    Check(gTestTray.checked["외출 저부하 켜기 (30 FPS)"] && !gTestTray.checked["외출 저부하 끄기 (일반 복귀)"], "tray checkmark moves to away")
    config["Settings"]["AwayMode"] := 0
    LoadConfig()
    Check(config["Settings"]["AwayMode"] = 1, "restart reload preserves away")
    gTestTray.actions["외출 저부하 끄기 (일반 복귀)"].Call()
    Check(config["Settings"]["AwayMode"] = 0 && CpuBoostTick() && gCpuBoostState = "on" && ReadFps() = "0", "saved tray disable restores normal policy on tick")
    LoadConfig()
    Check(config["Settings"]["AwayMode"] = 0, "restart reload preserves normal mode")

    FileMove(gFixtureRoot "\Config.ini", gFixtureRoot "\Config.saved")
    calls := testPowerCalls.Length, opens := testFpsOpens
    Check(!SetAwayMode(true), "config read failure does not claim success")
    Check(config["Settings"]["AwayMode"] = 0 && testPowerCalls.Length = calls && testFpsOpens = opens, "config read failure preserves running mode")
    Check(InStr(testTips[testTips.Length], "변경 실패"), "config read failure shows failure")
    FileMove(gFixtureRoot "\Config.saved", gFixtureRoot "\Config.ini")
    FileSetAttrib("+R", gFixtureRoot "\Config.ini")
    try {
        Check(!SetAwayMode(true), "config save failure does not claim success")
        Check(config["Settings"]["AwayMode"] = 0 && testPowerCalls.Length = calls, "config save failure preserves running mode")
        Check(IniRead(gFixtureRoot "\Config.ini", "Settings", "AwayMode") = "0", "config save failure preserves persisted mode")
    } finally {
        FileSetAttrib("-R", gFixtureRoot "\Config.ini")
    }
    testFpsFail := "open"
    Check(SetAwayMode(true) && !CpuBoostTick(), "saved mode is separate from application failure")
    Check(config["Settings"]["AwayMode"] = 1 && InStr(testTips[testTips.Length], "적용 대기"), "saved but unapplied mode is explicit")
    testFpsFail := ""
    Check(CpuBoostTick(), "saved mode retries after application failure")
    LoadConfig()
    Check(config["Settings"]["AwayMode"] = 1, "application failure does not discard requested manual mode")

    ResetState(0, 300, 24, false, 60000, 60000)
    config["Settings"]["AutoAwayIdleSec"] := 60
    Check(CpuBoostTick() && gCpuBoostAutoAway && gCpuBoostState = "off" && ReadFps() = "30", "automatic away works independently of earning")
    firstSignal := FileRead(gFixtureRoot "\.gta-away-want", "UTF-8")
    Check(RegExMatch(firstSignal, "^v1\|\d+\|1000000\|1\|0$"), "atomic signal contains producer identity clock and desired states")
    Check(!FileExist(gFixtureRoot "\.gta-away-want.tmp"), "published signal has no partial temporary file")
    testNowMs += 2000, testPhys += 2000, testOthers += 2000
    Check(CpuBoostTick() && FileRead(gFixtureRoot "\.gta-away-want", "UTF-8") != firstSignal, "unchanged state still refreshes heartbeat")
    Check(testPowerCalls.Length = 1 && testFpsOpens = 1, "heartbeat does not repeat power and FPS writes")
    testPhys := 0
    Check(CpuBoostTick() && !gCpuBoostAutoAway && gCpuBoostState = "on" && ReadFps() = "0", "physical input promptly restores normal policy")
    Check(InStr(FileRead(gFixtureRoot "\.gta-away-want", "UTF-8"), "|0|1"), "normal restoration is published to watcher")
    testNowMs += 60000, testPhys := 60000, testOthers := 60000
    Check(CpuBoostTick() && gCpuBoostAutoAway, "automatic away can repeat after renewed idle")
    testOthers := 0
    Check(CpuBoostTick() && !gCpuBoostAutoAway, "external injected input also restores normal policy")
    testNowMs += 60000, testPhys := 60000, testOthers := 60000, testPhysicalHeld := true
    Check(CpuBoostTick() && !gCpuBoostAutoAway && gCpuBoostState = "on", "held driving key prevents idle transition")
    testPhysicalHeld := false
    Check(CpuBoostTick() && !gCpuBoostAutoAway, "release starts a fresh idle period")
    testNowMs += 60000, testPhys := 60000, testOthers := 60000
    Check(CpuBoostTick() && gCpuBoostAutoAway, "auto policy resumes after released-key idle period")
    config["Settings"]["AwayMode"] := 1, testPhys := 0
    Check(CpuBoostTick() && gCpuBoostState = "off" && ReadFps() = "30", "manual away still overrides user activity with auto enabled")
    config["Settings"]["AwayMode"] := 0, testAwayFail := true
    Check(!CpuBoostTick() && gCpuBoostState = "on" && ReadFps() = "0", "IPC failure does not block restoring CPU and FPS")
    Check(InStr(gCpuBoostError, "자동 외출"), "IPC failure is visible and not cached as success")
    testAwayFail := false
    Check(CpuBoostTick() && gCpuBoostError = "", "IPC failure retries next tick")
    Check(!CpuBoostAutoAway(999999, 0) && !CpuBoostAutoAway(59999, 60) && CpuBoostAutoAway(60000, 60), "auto threshold is inclusive and zero disables")
    Check(!CpuBoostAutoAway(999999, 60, true), "held-key guard wins over idle duration")
    Check(CpuBoostLastActive(4294967000, 4295027000, 1) = 4295026999, "activity clock remains monotonic beyond 32 bit uptime")
    ResetState(0, 300, 30, false, 60000, 60000)
    config["Settings"]["AutoAwayIdleSec"] := 60
    Check(CpuBoostTick() && ReadFps() = "30", "automatic FPS cache initialized before stale-writer race")
    f := FileOpen(gFixtureRoot "\.gta-fps-want", "w", "UTF-8-RAW"), f.Write("0"), f.Close()
    Check(CpuBoostTick() && ReadFps() = "30" && testPowerCalls.Length = 1, "fresh Main repairs competing stale release despite matching FPS cache")
}

ResetState(away, sec, fps, earn, phys, others) {
    global
    config["Settings"] := Map("AwayMode", away, "CpuBoostIdleSec", sec, "IdleFpsLimit", fps)
    gCpuBoostState := "", gCpuBoostFps := "", gCpuBoostLastActive := 0
    gCpuBoostWorking := false, gCpuBoostError := "", gEarnOn := earn
    gCpuBoostAutoAway := false, testPhysicalHeld := false, testAwayFail := false
    gCpuBoostPublishError := ""
    ; Synthetic idle values must share a deterministic clock, not the CI VM uptime.
    testNowMs := 1000000
    testPhys := phys, testOthers := others, testPowerExit := 0, testPowerCalls := []
    testFpsFail := "", testFpsOpens := 0, testFpsReads := 0, testLogs := [], testTips := []
    try FileDelete(gFixtureRoot "\.gta-fps-want")
    try FileDelete(gFixtureRoot "\.gta-away-want")
    try FileDelete(gFixtureRoot "\.gta-away-want.tmp")
}
ReadFps() {
    global gFixtureRoot
    try return FileRead(gFixtureRoot "\.gta-fps-want", "UTF-8")
    catch
        return "missing"
}
WriteConfig(text) {
    global gFixtureRoot
    file := FileOpen(gFixtureRoot "\Config.ini", "w", "UTF-8-RAW")
    file.Write(text), file.Close()
}
Check(ok, name) {
    global n
    if (!ok)
        throw Error(name)
    n += 1
}
AFKPhysicalIdleMs() {
    global testPhys
    return testPhys
}
AFKOthersIdleMs() {
    global testOthers
    return testOthers
}
AFKKeysHeld() {
    global testPhysicalHeld
    return testPhysicalHeld
}
TestNow() {
    global testNowMs
    return testNowMs
}
TestTick() {
    CpuBoostPublishTick()
    return CpuBoostTick()
}
TestRunWait(command, workingDir := "", options := "") {
    global testPowerCalls, testPowerExit, testPowerDelay, testHeld, testPowerDuringHold
    if (!InStr(command, "powercfg ") || options != "Hide")
        throw Error("unexpected OS command in fixture")
    testPowerCalls.Push(command)
    if (testHeld)
        testPowerDuringHold := true
    if (testPowerDelay)
        Sleep(testPowerDelay)
    return testPowerExit
}
TestEnvGet(name) {
    global gFixtureRoot
    if (name != "USERPROFILE")
        throw Error("unexpected environment lookup")
    return gFixtureRoot
}
TestFpsFileOpen(path, mode, encoding) {
    global gFixtureRoot, testFpsFail, testFpsOpens, testAwayFail
    if (path = gFixtureRoot "\.gta-away-want.tmp") {
        if (testAwayFail)
            throw Error("fixture signal failure")
        return FileOpen(path, mode, encoding)
    }
    if (path != gFixtureRoot "\.gta-fps-want")
        throw Error("refusing non-fixture path")
    testFpsOpens++
    if (testFpsFail = "open")
        throw Error("fixture open failure")
    return FileOpen(path, mode, encoding)
}
TestFpsFileRead(path, encoding) {
    global gFixtureRoot, testFpsFail, testFpsReads
    if (path != gFixtureRoot "\.gta-fps-want")
        throw Error("refusing non-fixture path")
    testFpsReads++
    if (testFpsFail = "read")
        throw Error("fixture read failure")
    return testFpsFail = "mismatch" ? "wrong" : FileRead(path, encoding)
}
EarnLog(text) {
    global testLogs
    testLogs.Push(text)
}
MacroLog(tag, text) => EarnLog(tag ": " text)
ShowTooltip(text, ms := 0) {
    global testTips
    testTips.Push(text)
}
ExitAll() => 0
StopAll(reason) => 0
ToggleAntiAFK() => 0
ShowHelp() => 0
OpenPanel() => 0
class FakeTray {
    actions := Map()
    checked := Map()
    Insert(args*) {
        if (args.Length >= 3)
            this.actions[args[2]] := args[3]
    }
    Check(name) => this.checked[name] := true
    Uncheck(name) => this.checked[name] := false
}
@TRAY@
'@
$driver = $driver.Replace('Check(CpuBoostTick()', 'Check(TestTick()').Replace('!CpuBoostTick()', '!TestTick()').
    Replace('&& CpuBoostTick()', '&& TestTick()')
$driver = $driver.Replace('@FIXTURE@', $fixture).Replace('@CONFIG@', $configSource).
    Replace('@CPU@', $src).Replace('@TRAY@', $traySource)
$path = Join-Path $fixture 'driver.ahk'
function Invoke-CpuFixture {
    param([string]$Code, [string]$ExpectedPattern, [int]$ExpectedExit = 0)
    [IO.File]::WriteAllText($path, $Code, (New-Object Text.UTF8Encoding($true)))
    $process = $null
    try {
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = $AhkPath
        $info.Arguments = '/ErrorStdOut "' + $path + '"'
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
        $info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
        $process = [Diagnostics.Process]::Start($info)
        if (-not $process.WaitForExit(15000)) {
            $process.Kill()
            $process.WaitForExit()
            throw 'CpuBoost fixture timed out'
        }
        $stdout = $process.StandardOutput.ReadToEnd().Trim()
        $stderr = $process.StandardError.ReadToEnd().Trim()
        if ($process.ExitCode -ne $ExpectedExit -or $stderr -or $stdout -cnotmatch $ExpectedPattern) {
            throw "CpuBoost failed (exit=$($process.ExitCode)): stdout=$stdout; stderr=$stderr"
        }
        Write-Output $stdout
    } finally {
        if ($process) {
            if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
            $process.Dispose()
        }
    }
}
$timingFunctions = @'
BeginTiming() {
    global testPowerDelay, testHeld, testHoldMs
    ResetState(1, 0, 0, false, 0, 0)
    testPowerDelay := 250
    ; This is only a logical held-key marker. No input API is used.
    testHeld := true
    started := A_TickCount
    SetTimer(CpuBoostTick, -20, @PRIORITY@)
    Sleep(120)
    testHeld := false
    testHoldMs := A_TickCount - started
    SetTimer(FinishTiming, -600)
}
FinishTiming() {
    global testPowerDuringHold, testPowerCalls, testHoldMs
    ok := !testPowerDuringHold && testPowerCalls.Length = 1
    FileAppend((ok ? "PASS" : "EXPECTED_REPRO") " CpuBoost timing priority=@PRIORITY@ power_during_hold="
        (testPowerDuringHold ? 1 : 0) " hold_ms=" testHoldMs "`n", "*")
    ExitApp(ok ? 0 : 1)
}
'@
$heartbeatFunctions = @'
BeginHeartbeat() {
    global testHeld, testNowMs
    ResetState(0, 300, 30, false, 60000, 60000)
    config["Settings"]["AutoAwayIdleSec"] := 60
    testHeld := true
    SetTimer(CpuBoostPublishTick, 20)
    SetTimer(CpuBoostTick, -20, -10)
    Sleep(70)
    first := FileRead(gFixtureRoot "\.gta-away-want", "UTF-8")
    testNowMs += 2000
    Sleep(70)
    next := FileRead(gFixtureRoot "\.gta-away-want", "UTF-8")
    SetTimer(CpuBoostPublishTick, 0)
    Check(first != next && InStr(next, "|1|0"), "heartbeat continues while normal-priority macro thread sleeps")
    Check(testPowerCalls.Length = 0 && testFpsOpens = 0, "heartbeat performs no power or FPS side effects during macro input")
    testHeld := false
    SetTimer(FinishHeartbeat, -100)
}
FinishHeartbeat() {
    global testPowerDuringHold, testPowerCalls
    Check(!testPowerDuringHold && testPowerCalls.Length = 1, "power waits until normal macro thread yields")
    FileAppend("PASS CpuBoost heartbeat_during_macro=1 power_during_hold=0`n", "*")
    ExitApp(0)
}
'@
try {
    Invoke-CpuFixture $driver '^PASS CpuBoost cases=88$'
    $timingDriver = [regex]::Replace($driver, '(?m)^    RunCases\(\)\r?\n    FileAppend[^\r\n]*\r?\n    ExitApp\(0\)',
        "    SetTimer(BeginTiming, -1)`n    return")
    # Control reproduces the RunWait interruption before the timer-priority fix.
    Invoke-CpuFixture ($timingDriver + "`n" + $timingFunctions.Replace('@PRIORITY@', '0')) `
        '^EXPECTED_REPRO CpuBoost timing priority=0 power_during_hold=1 hold_ms=\d+$' 1
    $priority = $timer[0].Groups[1].Value
    if ([int]$priority -ge 0) { throw 'Production CPU timer must not preempt normal input threads.' }
    Invoke-CpuFixture ($timingDriver + "`n" + $timingFunctions.Replace('@PRIORITY@', $priority)) `
        ('^PASS CpuBoost timing priority=' + $priority + ' power_during_hold=0 hold_ms=\d+$')
    $heartbeatDriver = $timingDriver.Replace('SetTimer(BeginTiming, -1)', 'SetTimer(BeginHeartbeat, -1)')
    Invoke-CpuFixture ($heartbeatDriver + "`n" + $heartbeatFunctions) '^PASS CpuBoost heartbeat_during_macro=1 power_during_hold=0$'
} finally {
    # Only delete known generated files in this newly created fixture directory.
    foreach ($name in @('driver.ahk', 'Config.ini', 'Config.ini.tmp', 'Config.saved', '.gta-fps-want', '.gta-away-want', '.gta-away-want.tmp')) {
        $file = Join-Path $fixture $name
        if ([IO.File]::Exists($file)) { [IO.File]::SetAttributes($file, 'Normal'); [IO.File]::Delete($file) }
    }
    [IO.Directory]::Delete($fixture)
}
