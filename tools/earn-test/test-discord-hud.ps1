#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe",
    [string]$BaselineRevision = ''
)
$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '..\..'
if ($BaselineRevision) {
    $source = (& git -C $root show ($BaselineRevision + ':Features/DiscordHUD.ahk')) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read requested baseline' }
    $production = [regex]::Match($source, '(?ms)^StartDiscordHUD\(\) \{.*?^\}').Value
    if (-not $production -or $source.Contains('DiscordHUDVisibilitySync')) { throw 'Expected pre-fix startup-only source' }
    $production = $production.Replace('FileExist(', 'FakeFileExist(').Replace('ProcessExist(', 'FakeProcessExist(')
    $driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
global config := Map("Settings", Map("DiscordHUDPath", "existing.exe")), GTA_WIN := "fake"
global hudVisible := true
if (StartDiscordHUD() || !hudVisible)
    ExitApp(1)
FileAppend("EXPECTED_REPRO: running HUD remains visible before automation`n", "*")
ExitApp(0)
FakeFileExist(*) => true
FakeProcessExist(*) => 101
DiscordHUDKeepGTAFront(*) => false
MacroLog(*) => false
'@
    $expected = '^EXPECTED_REPRO: running HUD remains visible before automation$'
} else {
    $source = Get-Content (Join-Path $root 'Features\DiscordHUD.ahk') -Raw -Encoding UTF8
    $production = $source.Substring($source.IndexOf('global gDiscordHUDLeases'))
    foreach ($name in @('DiscordHUDWindowList','DiscordHUDWindowRead','DiscordHUDWindowVisible')) {
        $production = [regex]::Replace($production, ('(?ms)^' + $name + '\([^\r\n]*\) \{.*?^\}\s*'), '')
    }
    if ($production -match 'DllCall\(|WinGet|ShowWindow|WinActivate|\bRun\(') { throw 'Native side effect remains in HUD fixture' }
    if (-not $source.Contains('title != "DiscordChatHUD C#" || WinGetProcessName("ahk_id " hwnd) != "DiscordChatHUD.exe"') -or
        -not $source.Contains('GetProcessTimes') -or -not $source.Contains('visible ? 8 : 0')) {
        throw 'Exact HUD identity and non-activating visibility boundary must be retained'
    }
    $driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global n := 0, windows := Map(), writes := [], logs := [], failWrite := false, failRead := false
global timers := [], exits := [], gEarnOn := true, config := Map("Settings", Map("AwayMode", 1))
@PRODUCTION@
try {
    windows[1] := Window(1)
    windows[2] := Window(2, false)
    windows[3] := Window(3, true, "DiscordChatHUD Config · C# Preview 337")
    windows[4] := Window(4, true, "계정 연결")
    windows[5] := Window(5)
    windows[5].minimized := true
    DiscordHUDVisibilityInit()
    Check(timers.Length = 1 && exits.Length = 1, "timer and normal exit hook installed")
    Check(timers[1].period = 1000 && timers[1].priority = -10, "visibility polling cannot preempt held game input")
    Check(!windows[1].visible && gDiscordHUDOwned.Count = 1, "away plus earning hides only actual visible HUD")
    Check(!windows[2].visible && windows[3].visible && windows[4].visible && windows[5].visible, "hidden, config, login and minimized windows unchanged")
    DiscordHUDVisibilityTick()
    Check(writes.Length = 1, "stable hide is idempotent")
    windows[1].visible := true
    DiscordHUDVisibilityTick()
    Check(!windows[1].visible && writes.Length = 2, "HUD self-show is re-hidden")
    DiscordHUDVisibilityAcquire()
    config["Settings"]["AwayMode"] := 0
    gEarnOn := false
    DiscordHUDVisibilityTick()
    Check(!windows[1].visible && gDiscordHUDLeases = 1, "return home and F9 off cannot expose active cleanup")
    DiscordHUDVisibilityAcquire()
    DiscordHUDVisibilityRelease()
    Check(!windows[1].visible && gDiscordHUDLeases = 1, "nested scope cannot restore early")
    DiscordHUDVisibilityRelease()
    Check(windows[1].visible && gDiscordHUDOwned.Count = 0, "last cleanup scope restores original HUD")
    Check(!windows[2].visible, "original hidden state survives full roundtrip")
    DiscordHUDVisibilityAcquire()
    Check(!windows[1].visible, "normal-mode screen work also synchronously hides before OCR")
    try {
        throw Error("task failure")
    } catch {
    } finally {
        DiscordHUDVisibilityRelease()
    }
    Check(windows[1].visible && gDiscordHUDLeases = 0, "exception finally restores")
    config["Settings"]["AwayMode"] := 1
    gEarnOn := true
    DiscordHUDVisibilityAcquire()
    DiscordHUDVisibilityRelease()
    Check(!windows[1].visible, "away session remains hidden between jobs")
    gEarnOn := false
    DiscordHUDVisibilityTick()
    Check(windows[1].visible, "stopped away session restores")
    DiscordHUDVisibilityAcquire()
    windows[1] := Window(1, false)
    windows[1].pid := 999
    DiscordHUDVisibilityRelease()
    Check(!windows[1].visible && gDiscordHUDOwned.Count = 0, "recycled HWND different PID never restored")
    windows[1] := Window(1)
    DiscordHUDVisibilityAcquire()
    windows[1].created += 1
    DiscordHUDVisibilityRelease()
    Check(!windows[1].visible, "reused PID different creation time never restored")
    windows[1] := Window(1)
    DiscordHUDVisibilityAcquire()
    windows[1].title := "계정 연결"
    DiscordHUDVisibilityRelease()
    Check(!windows[1].visible, "changed role is not restored")
    windows[1] := Window(1)
    failWrite := true
    rejected := false
    try DiscordHUDVisibilityAcquire()
    catch {
        rejected := true
    }
    Check(rejected && windows[1].visible && gDiscordHUDLeases = 0, "hide failure rejects OCR and unwinds lease")
    failWrite := false
    DiscordHUDVisibilityAcquire()
    failWrite := true
    DiscordHUDVisibilityRelease()
    Check(!windows[1].visible && gDiscordHUDOwned.Has(1) && gDiscordHUDError != "", "failed restore retains ownership for retry")
    failWrite := false
    DiscordHUDVisibilityTick()
    Check(windows[1].visible && !gDiscordHUDOwned.Has(1), "retry restores without losing original visibility")
    failRead := true
    rejected := false
    try DiscordHUDVisibilityAcquire()
    catch {
        rejected := true
    }
    Check(rejected && gDiscordHUDLeases = 0, "identity read failure prevents acquisition")
    failRead := false
    DiscordHUDVisibilityAcquire()
    windows.Delete(1)
    DiscordHUDVisibilityRelease()
    Check(gDiscordHUDOwned.Count = 0, "destroyed HUD ownership discarded")
    windows[1] := Window(1)
    gEarnOn := true
    DiscordHUDVisibilityTick()
    Check(!windows[1].visible, "new visible HUD during away session is protected")
    DiscordHUDVisibilityExit()
    Check(windows[1].visible && !windows[2].visible, "normal process exit restores only owned windows")
    FileAppend("PASS DiscordHUD: " n " cases; no window or game input`n", "*")
    ExitApp(0)
} catch as fixtureFailure {
    FileAppend("FAIL DiscordHUD: " fixtureFailure.Message " line=" fixtureFailure.Line "`n", "**")
    ExitApp(1)
}
Check(ok, message) {
    global n
    n += 1
    if (!ok)
        throw Error(message)
}
Window(id, visible := true, title := "DiscordChatHUD C#") => {hwnd: id, pid: 100 + id, created: 12345, title: title, visible: visible, minimized: false}
DiscordHUDWindowList() => [1, 2, 3, 4, 5]
DiscordHUDWindowRead(hwnd) {
    if (failRead)
        throw Error("identity unavailable")
    if (!windows.Has(hwnd) || windows[hwnd].title != "DiscordChatHUD C#")
        return false
    return windows[hwnd].Clone()
}
DiscordHUDWindowVisible(hwnd, visible) {
    if (failWrite)
        return false
    windows[hwnd].visible := visible
    writes.Push({hwnd: hwnd, visible: visible})
    return true
}
MacroLog(kind, message) => logs.Push(message)
SetTimer(fn, period, priority) => timers.Push({fn: fn, period: period, priority: priority})
OnExit(fn) => exits.Push(fn)
'@
    $driver = $driver.Replace('@PRODUCTION@', $production)
    $production = ''
    $expected = '^PASS DiscordHUD: 24 cases; no window or game input$'
}
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $AhkPath
$info.Arguments = '/ErrorStdOut /CP65001 *'
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardInput = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$previous = [Console]::InputEncoding
[Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
try {
    $process = [Diagnostics.Process]::Start($info)
    try {
        $process.StandardInput.WriteLine($driver + "`n" + $production)
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(10000)) { $process.Kill(); throw 'HUD fixture timed out' }
        $stdout = $process.StandardOutput.ReadToEnd().Trim()
        $stderr = $process.StandardError.ReadToEnd().Trim()
        if ($process.ExitCode -ne 0 -or $stderr -or $stdout -notmatch $expected) {
            throw "HUD fixture exit=$($process.ExitCode) stdout=$stdout stderr=$stderr"
        }
        $stdout
    } finally { $process.Dispose() }
} finally { [Console]::InputEncoding = $previous }
