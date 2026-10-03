#Requires -Version 5.1
<#
Executes the actual EarnReadScreen body, preserving its command expression and
TSV parsing. Process/window APIs are replaced with deterministic test functions.
No child PowerShell, desktop capture, keyboard input or GTA window is used.
#>
[CmdletBinding()]
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnScreen.ahk') -Raw -Encoding UTF8
$functions = [regex]::Matches($source, '(?ms)^EarnReadScreen\([^\r\n]*\) \{.*?^\}')
if ($functions.Count -ne 1) { throw 'Expected one EarnReadScreen body.' }
$production = $functions[0].Value
$exitCall = 'DllCall("GetExitCodeProcess", "ptr", handle, "uint*", &code)'
if (-not $production.Contains($exitCall)) { throw 'Update the exit-code test adapter for the current native signature.' }
$production = $production.Replace($exitCall, 'OcrTestExitCode(&code)')
foreach ($adapter in @(@('DllCall(', 'OcrTestDllCall('), @('WinGetClientPos(', 'OcrTestClientPos('),
    @('Run(', 'OcrTestRun('), @('ProcessExist(', 'OcrTestProcessExist('), @('ProcessClose(', 'OcrTestProcessClose('),
    @('A_TickCount', 'OcrTestTick()'), @('Sleep(', 'OcrTestSleep('), @('FileRead(', 'OcrTestFileRead('))) {
    $production = $production.Replace($adapter[0], $adapter[1])
}
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global commandMode := "", capturedCommand := "", commandOutput := "", commandAborts := 0,
    commandTerminated := 0, commandClosed := 0, commandChecks := 0, commandTick := 1000,
    commandWaits := 0, commandSlept := 0
try {
    RunCommandTests()
    FileAppend("PASS EarnScreenCommand cases=" commandChecks " (no game input)`n", "*")
    ExitApp(0)
} catch as testFailure {
    FileAppend("FAIL EarnScreenCommand: " testFailure.Message "`n", "**")
    ExitApp(1)
}
RunCommandTests() {
    global capturedCommand, commandOutput, commandTerminated, commandClosed, commandSlept
    ResetCommand("success")
    result := EarnReadScreen([25,15,450,850])
    Check(result is Array && result.Length = 1 && result[1].text = "Nightclub"
        && result[1].x = 87 && result[1].y = 182, "actual wrapper converts negative-monitor absolute TSV to client coordinates")
    Check(InStr(capturedCommand, " -X -2535 -Y 115 -W 450 -H 850 -OutputPath ") > 0,
        "actual continued command expression contains computed rectangle")
    Check(InStr(capturedCommand, "Core\EarnOcr.ps1") > 0 && InStr(capturedCommand, "-NoProfile -ExecutionPolicy Bypass -File") > 0,
        "actual child command targets the shipped OCR helper")
    Check(!FileExist(commandOutput) && commandClosed = 1, "success cleans TSV and process handle")
    Check(!InStr(capturedCommand, "-WhiteText"), "normal OCR preserves black selected-row text")
    ResetCommand("success")
    result := EarnReadScreen([25,15,450,850], true)
    Check(InStr(capturedCommand, " -H 850 -WhiteText -OutputPath ") > 0,
        "white-text OCR is an explicit process switch without breaking command continuation")
    Check(result is Array && result.Length = 1 && result[1].x = 87 && result[1].y = 182,
        "white-text option preserves client-coordinate output contract")
    for failureMode in ["nonzero", "missing_output", "invalid_columns", "invalid_coordinate",
        "out_of_bounds", "invalid_size", "spawn_error", "window_error", "cancel", "open_error"] {
        ResetCommand(failureMode)
        result := EarnReadScreen([25,15,450,850])
        Check(!result, failureMode " returns false")
        Check(commandOutput = "" || !FileExist(commandOutput), failureMode " leaves no reusable output")
        if (failureMode = "cancel" || failureMode = "open_error")
            Check(commandTerminated = 1, failureMode " stops child exactly once")
    }
    ResetCommand("empty")
    result := EarnReadScreen([25,15,450,850])
    Check(result is Array && result.Length = 0 && !FileExist(commandOutput), "successful no-text OCR is distinct from failure")
    ResetCommand("success")
    result := EarnReadScreen([25,15,450,850], false, 1000)
    Check(!result && capturedCommand = "" && commandClosed = 0, "expired absolute deadline launches no OCR process")
    ResetCommand("window_deadline")
    result := EarnReadScreen([25,15,450,850], false, 1050)
    Check(!result && capturedCommand = "", "deadline reached during window checks is checked again before launch")
    ResetCommand("success")
    result := EarnReadScreen([25,15,450,850], true, 2000)
    Check(result is Array && result.Length = 1 && InStr(capturedCommand, "-WhiteText"), "future deadline accepts normal white-text OCR")
    ResetCommand("deadline_wait")
    result := EarnReadScreen([25,15,450,850], false, 1030)
    Check(!result && commandTerminated = 1 && commandClosed = 1 && !FileExist(commandOutput), "external deadline terminates and cleans pending OCR")
    Check(commandSlept = 30, "wait sleep is limited to the remaining external deadline")
    ResetCommand("late_complete")
    result := EarnReadScreen([25,15,450,850], false, 1050)
    Check(!result && commandTerminated = 0 && commandClosed = 1 && !FileExist(commandOutput), "process completed after deadline cannot publish a late result")
    ResetCommand("long_wait")
    result := EarnReadScreen([25,15,450,850], false, 60000)
    Check(!result && commandTerminated = 1 && commandClosed = 1, "per-call fifteen-second bound wins over a later external deadline")
    ResetCommand("long_wait")
    result := EarnReadScreen([25,15,450,850])
    Check(!result && commandTerminated = 1, "omitted deadline retains the per-call fifteen-second bound")
    ResetCommand("read_deadline")
    result := EarnReadScreen([25,15,450,850], false, 1050)
    Check(!result && commandClosed = 1 && !FileExist(commandOutput), "TSV parsing cannot publish after the caller deadline")
}
ResetCommand(mode) {
    global commandMode, capturedCommand, commandOutput, commandAborts, commandTerminated, commandClosed,
        commandTick, commandWaits, commandSlept
    commandMode := mode, capturedCommand := "", commandOutput := "", commandAborts := 0,
        commandTerminated := 0, commandClosed := 0, commandTick := 1000, commandWaits := 0, commandSlept := 0
}
EarnAborted() {
    global commandMode, commandAborts
    commandAborts++
    return commandMode = "cancel" && commandAborts >= 2
}
IsGTAActive() => 42
EarnFail(*) => false
OcrTestClientPos(&x, &y, &w, &h, *) {
    global commandMode, commandTick
    if (commandMode = "window_error")
        throw Error("test window disappeared")
    x := -2560, y := 100, w := 1920, h := 1080
    if (commandMode = "window_deadline")
        commandTick += 100
}
OcrTestRun(command, cwd := "", options := "", &pid := 0) {
    global commandMode, capturedCommand, commandOutput
    capturedCommand := command
    if (commandMode = "spawn_error")
        throw Error("test process start failed")
    if (options != "Hide" || !RegExMatch(command, '-OutputPath "([^"]+)"$', &pathMatch))
        throw Error("bad actual process command")
    commandOutput := pathMatch[1], pid := 99
    if (commandMode = "missing_output")
        return
    data := "x`ty`tw`th`ttext`n"
    if (commandMode = "invalid_columns")
        data .= "1`t2`tincomplete`n"
    else if (commandMode = "invalid_coordinate")
        data .= "word`t282`t92`t21`tNightclub`n"
    else if (commandMode = "out_of_bounds")
        data .= "-2000`t282`t92`t21`tNightclub`n"
    else if (commandMode = "invalid_size")
        data .= "-2473`t282`t0`t21`tNightclub`n"
    else if (commandMode != "empty")
        data .= "-2473`t282`t92`t21`tNightclub`n"
    FileAppend(data, commandOutput, "UTF-8")
}
OcrTestExitCode(&exitCode) {
    global commandMode
    exitCode := commandMode = "nonzero" ? 1 : 0
    return true
}
OcrTestDllCall(name, args*) {
    global commandMode, commandTerminated, commandClosed, commandTick, commandWaits
    if (name = "GetCurrentProcessId")
        return 54321
    if (name = "OpenProcess")
        return commandMode = "open_error" ? 0 : 11
    if (name = "WaitForSingleObject") {
        commandWaits++
        if (commandMode = "late_complete")
            commandTick += 100
        if (commandMode = "long_wait")
            commandTick += 16000
        if ((commandMode = "deadline_wait" || commandMode = "long_wait") && !commandTerminated)
            return 0x102
        return commandMode = "cancel" && !commandTerminated ? 0x102 : 0
    }
    if (name = "TerminateProcess")
        commandTerminated++
    if (name = "CloseHandle")
        commandClosed++
    return 1
}
OcrTestTick() {
    global commandTick
    return commandTick
}
OcrTestSleep(milliseconds) {
    global commandTick, commandSlept
    commandTick += milliseconds
    commandSlept += milliseconds
}
OcrTestFileRead(path, encoding) {
    global commandMode, commandTick
    data := FileRead(path, encoding)
    if (commandMode = "read_deadline")
        commandTick += 100
    return data
}
OcrTestProcessExist(*) => 99
OcrTestProcessClose(*) {
    global commandTerminated
    commandTerminated++
}
Check(condition, description) {
    global commandChecks
    if (!condition)
        throw Error(description)
    commandChecks++
}
'@
$testFile = Join-Path ([IO.Path]::GetTempPath()) ('gta-ocr-command-test-' + [Guid]::NewGuid().ToString('N') + '.ahk')
[IO.File]::WriteAllText($testFile, $driver + "`n" + $production, (New-Object Text.UTF8Encoding($true)))
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $AhkPath
$info.Arguments = '/ErrorStdOut /CP65001 "' + $testFile + '"'
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
$info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
$process = [Diagnostics.Process]::Start($info)
try {
    if (-not $process.WaitForExit(10000)) {
        $process.Kill()
        $process.WaitForExit()
        throw 'OCR command test timed out.'
    }
    $stdout = $process.StandardOutput.ReadToEnd().Trim()
    $stderr = $process.StandardError.ReadToEnd().Trim()
    if ($process.ExitCode -ne 0 -or $stderr -ne '' -or $stdout -ne 'PASS EarnScreenCommand cases=39 (no game input)') {
        throw "OCR command test failed (exit=$($process.ExitCode))`nstdout: $stdout`nstderr: $stderr"
    }
    Write-Output $stdout
}
finally {
    if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    $process.Dispose()
    if ([IO.File]::Exists($testFile)) { [IO.File]::Delete($testFile) }
}
