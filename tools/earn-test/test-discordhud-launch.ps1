#Requires -Version 5.1
[CmdletBinding()]
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '..\..'
$source = Get-Content (Join-Path $root 'Features\DiscordHUD.ahk') -Raw -Encoding UTF8
$loader = Get-Content (Join-Path $root 'Core\ConfigLoader.ahk') -Raw -Encoding UTF8
$config = Get-Content (Join-Path $root 'Config.ini') -Raw -Encoding UTF8
$expectedAppId = 'alex6483.DiscordChatHUD_dc909tavazxht!DiscordChatHUD'
if ($loader -notmatch '(?s)"DiscordHUDAppID",\s*""' -or
    $config -notmatch ('(?m)^DiscordHUDAppID=' + [regex]::Escape($expectedAppId) + '$')) {
    throw 'The app ID default must remain empty and tracked Config.ini must select the installed package.'
}

$start = [regex]::Match($source, '(?ms)^StartDiscordHUD\(\) \{.*?^\}').Value
$targetCheck = [regex]::Match($source, '(?ms)^DiscordHUDTargetAppRunning\(appId\) \{.*?^\}').Value
if (-not $start -or -not $targetCheck) { throw 'Store app launcher functions were not found.' }
if (-not $start.Contains('Run(target, dir)')) { throw 'Launcher must call Run with a replaceable, test-stubbed target.' }
$production = ($start + "`n" + $targetCheck).Replace('Run(target, dir)', 'DiscordHUDLaunchRecord(target, dir)')

$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global fixtureAppId := "alex6483.DiscordChatHUD_dc909tavazxht!DiscordChatHUD"
global config := Map("Settings", Map("DiscordHUDAppID", fixtureAppId, "DiscordHUDPath", "%LOCALAPPDATA%\Programs\DiscordChatHUD\DiscordChatHUD.exe"))
global running := Map(), packageIds := Map(), windows := [], launches := [], logs := [], keepCalls := []
global GTA_WIN := "gta", gameExists := true, gameActive := true
@PRODUCTION@
try {
    running["DiscordChatHUD.exe"] := 18808
    packageIds[18808] := ""
    windows := [18808]
    Check(StartDiscordHUD(), "Store AppID launches even while the legacy desktop process is running")
    Check(launches.Length = 1 && launches[1].target = "explorer.exe shell:AppsFolder\" fixtureAppId && launches[1].dir = "",
        "Store activation uses the installed AppUserModelID")
    Check(packageIds.Has(18808) && packageIds[18808] = "", "legacy process was left running")
    Check(keepCalls.Length = 1, "existing focus guard is scheduled when GTA was active")

    Reset()
    running["DiscordChatHUD.exe"] := 19001
    packageIds[19001] := fixtureAppId
    windows := [19001]
    Check(!StartDiscordHUD() && launches.Length = 0, "already-running target package is not activated twice")

    Reset()
    config["Settings"]["DiscordHUDAppID"] := "bad-aumid"
    Check(!StartDiscordHUD() && launches.Length = 0 && logs.Length = 1, "invalid AUMID fails without launching")

    Reset()
    config["Settings"]["DiscordHUDAppID"] := ""
    config["Settings"]["DiscordHUDPath"] := "C:\Windows\System32\notepad.exe"
    Check(StartDiscordHUD() && launches.Length = 1, "legacy path mode remains available")
    Check(launches[1].target = '"C:\Windows\System32\notepad.exe"' && launches[1].dir = "C:\Windows\System32",
        "legacy path target and working directory are preserved")

    Reset()
    config["Settings"]["DiscordHUDAppID"] := ""
    config["Settings"]["DiscordHUDPath"] := "C:\missing\DiscordChatHUD.exe"
    Check(!StartDiscordHUD() && launches.Length = 0, "missing legacy path remains a no-op")

    Reset()
    config["Settings"]["DiscordHUDAppID"] := fixtureAppId
    gameActive := false
    Check(StartDiscordHUD() && keepCalls.Length = 0, "Store activation does not schedule focus recovery when GTA was not active")
    FileAppend("PASS DiscordHUD launch: 6 cases; Run stubbed; no app or game input`n", "*")
    ExitApp(0)
} catch as fixtureError {
    FileAppend("FAIL DiscordHUD launch: " fixtureError.Message "`n", "*")
    ExitApp(1)
}
Check(value, message) {
    if (!value)
        throw Error(message)
}
Reset() {
    global config, fixtureAppId, running, packageIds, windows, launches, logs, keepCalls, gameActive
    config["Settings"]["DiscordHUDAppID"] := fixtureAppId
    config["Settings"]["DiscordHUDPath"] := "%LOCALAPPDATA%\Programs\DiscordChatHUD\DiscordChatHUD.exe"
    running := Map(), packageIds := Map(), windows := [], launches := [], logs := [], keepCalls := []
    gameActive := true
}
ProcessExist(name) => running.Get(name, 0)
DiscordHUDProcessAppId(pid) => packageIds.Get(pid, "")
WinGetList(*) => windows.Clone()
WinGetPID(spec) => Integer(SubStr(spec, 8))
WinExist(*) => gameExists
WinActive(*) => gameActive
DiscordHUDKeepGTAFront(deadline) => keepCalls.Push(deadline)
DiscordHUDLaunchRecord(target, dir) => launches.Push({target: target, dir: dir})
MacroLog(*) => logs.Push(1)
'@
$driver = $driver.Replace('@PRODUCTION@', $production)
$driverPath = Join-Path $env:TEMP ('gta-discordhud-launch-' + [guid]::NewGuid().ToString('N') + '.ahk')
[IO.File]::WriteAllText($driverPath, $driver, (New-Object Text.UTF8Encoding($false)))
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $AhkPath
$info.Arguments = '/ErrorStdOut "' + $driverPath + '"'
$info.WorkingDirectory = $root
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
$info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
$process = [Diagnostics.Process]::Start($info)
try {
    if (-not $process.WaitForExit(10000)) { $process.Kill(); throw 'HUD launch fixture timed out.' }
    $stdout = $process.StandardOutput.ReadToEnd().Trim()
    $stderr = $process.StandardError.ReadToEnd().Trim()
    if ($process.ExitCode -ne 0 -or $stderr -or $stdout -ne 'PASS DiscordHUD launch: 6 cases; Run stubbed; no app or game input') {
        throw "HUD launch fixture exit=$($process.ExitCode) stdout=$stdout stderr=$stderr"
    }
    $stdout
} finally {
    $process.Dispose()
    [IO.File]::Delete($driverPath)
}
