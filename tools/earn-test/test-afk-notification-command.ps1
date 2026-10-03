#Requires -Version 5.1
[CmdletBinding()]
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $PSScriptRoot '..\..\Features\AntiAFK.ahk'
$source = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8
$functions = [regex]::Matches($source, '(?ms)^AFKDismissNotification\([^\r\n]*\) \{.*?^\}')
if ($functions.Count -ne 1) { throw 'Expected one AFKDismissNotification body.' }
$production = $functions[0].Value
$exitCall = 'DllCall("GetExitCodeProcess", "ptr", handle, "uint*", &code)'
if (-not $production.Contains($exitCall)) { throw 'Update the exit-code adapter for the current native signature.' }
$production = $production.Replace($exitCall, 'NotificationTestExitCode(handle, &code)')
foreach ($adapter in @(
    @('DllCall(', 'NotificationTestDllCall('), @('WinExist(', 'NotificationTestWinExist('),
    @('WinGetProcessName(', 'NotificationTestProcessName('), @('WinGetTitleSafe(', 'NotificationTestTitle('),
    @('WinGetPID(', 'NotificationTestPID('), @('AFKRefocusAllowed(', 'NotificationTestAllowed('),
    @('Run(', 'NotificationTestRun('), @('ProcessExist(', 'NotificationTestProcessExist('),
    @('ProcessClose(', 'NotificationTestProcessClose('), @('Sleep(', 'NotificationTestSleep('),
    @('SplitPath(', 'NotificationTestSplitPath('), @('A_TimeIdle', 'NotificationTestIdle()')
)) {
    $production = $production.Replace($adapter[0], $adapter[1])
}
if ($production -match '(?<![\w])(?:DllCall|Run|WinExist|WinGetProcessName|WinGetPID|WinGetTitleSafe|AFKRefocusAllowed|ProcessExist|ProcessClose|Sleep)\(') {
    throw 'An unmocked process, window, input or guard call remains.'
}
$deadline = 'deadline := A_TickCount + 8000'
if (-not $production.Contains($deadline)) { throw 'Update the bounded timeout fixture for the current deadline.' }
# Only the timeout variant changes the clock expression. Its decision and cleanup
# are otherwise the same production body; no real eight-second wait is needed.
$timeoutProduction = $production.Replace('AFKDismissNotification(hwnd)', 'NotificationTestTimeout(hwnd)').Replace($deadline, 'deadline := A_TickCount - 1')
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global notificationMode := "", capturedCommand := "", commandOutput := "", notificationChecks := 0,
    notificationStarts := 0, notificationTerminated := 0, notificationClosed := 0, notificationPidClosed := 0,
    notificationGuardChecks := 0, notificationInputReads := 0, notificationWaits := 0,
    afkSelfBefore := -1
try {
    RunNotificationCommandTests()
    FileAppend("PASS AFKNotificationCommand cases=" notificationChecks " (offline adapters only)`n", "*")
    ExitApp(0)
} catch as testFailure {
    if (commandOutput != "" && FileExist(commandOutput))
        FileDelete(commandOutput)
    FileAppend("FAIL AFKNotificationCommand: " testFailure.Message "`n", "**")
    ExitApp(1)
}

RunNotificationCommandTests() {
    global capturedCommand, commandOutput, notificationStarts, notificationTerminated, notificationClosed,
        notificationPidClosed, notificationInputReads, notificationGuardChecks, afkSelfBefore
    ResetNotificationCommand("success")
    result := AFKDismissNotification(12345)
    Check(result = "dismissed", "zero exit and matching final input tick succeed")
    Check(notificationInputReads = 2 && notificationGuardChecks = 2, "success checks final input and guard after process completion")
    Check(InStr(capturedCommand, ' -WindowHandle 12345 -ProcessId 4321 -LastInputTick 4294967294 -OutputPath "') > 0,
        "actual command preserves HWND, process ID and uint32 input tick")
    Check(InStr(capturedCommand, ' -NoProfile -ExecutionPolicy Bypass -File "C:\fixture repo\Features\..\Core\NotificationDismiss.ps1"') > 0,
        "actual command quotes the shipped helper path including spaces")
    Check(RegExMatch(capturedCommand, '^"[^"\r\n]+\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe" '),
        "actual command quotes Windows PowerShell executable")
    Check(notificationStarts = 1 && notificationClosed = 1 && notificationTerminated = 0 && notificationPidClosed = 0,
        "success starts one child and closes its handle without terminating it")
    Check(!FileExist(commandOutput), "success removes result file")

    for mode in ["wrong_hwnd", "wrong_process", "wrong_title", "initial_guard"] {
        ResetNotificationCommand(mode)
        result := AFKDismissNotification(12345)
        Check(result = "blocked:foreground-or-input", mode " fails before process creation")
        Check(notificationStarts = 0 && notificationInputReads = 0 && commandOutput = "", mode " has no native input read or child")
    }
    ResetNotificationCommand("initial_input_error")
    Check(AFKDismissNotification(12345) = "error:last-input" && notificationStarts = 0, "failed initial input snapshot prevents child")

    for mode in ["blocked_input", "helper_error", "missing_status", "invalid_status", "nonzero_dismissed",
        "exit_code_error", "spawn_error", "open_error", "final_tick_changed", "final_guard", "final_input_error"] {
        ResetNotificationCommand(mode)
        expected := Map("blocked_input", "blocked:input-changed", "helper_error", "error:runtime-exception",
            "missing_status", "error:missing-result", "invalid_status", "error:invalid-result",
            "nonzero_dismissed", "error:invalid-result", "exit_code_error", "error:missing-result",
            "spawn_error", "error:helper", "open_error", "error:process-handle",
            "final_tick_changed", "blocked:recent-input", "final_guard", "blocked:recent-input",
            "final_input_error", "error:last-input")[mode]
        result := AFKDismissNotification(12345)
        Check(result = expected, mode " result=" result)
        Check(commandOutput = "" || !FileExist(commandOutput), mode " removes result file")
        if (mode = "open_error") {
            Check(notificationPidClosed = 1 && notificationTerminated = 0 && notificationClosed = 0,
                "no handle closes only the child PID returned by Run")
        } else if (mode = "spawn_error") {
            Check(notificationPidClosed = 0 && notificationTerminated = 0 && notificationClosed = 0,
                "failed spawn has no owned process or handle to close")
        } else {
            Check(notificationClosed = 1 && notificationTerminated = 0 && notificationPidClosed = 0,
                mode " closes exactly the completed owned handle")
        }
        if (mode = "blocked_input" || mode = "final_tick_changed")
            Check(afkSelfBefore >= 0, mode " records external input even during a self-input window")
    }
    for mode in ["cancel", "timeout", "guard_exception"] {
        ResetNotificationCommand(mode)
        result := mode = "timeout" ? NotificationTestTimeout(12345) : AFKDismissNotification(12345)
        expected := mode = "cancel" ? "blocked:recent-input" : (mode = "timeout" ? "error:timeout" : "error:helper")
        Check(result = expected, mode " bounded exit")
        Check(notificationTerminated = 1 && notificationClosed = 1 && notificationPidClosed = 0,
            mode " terminates exactly the owner handle once and closes it once")
        Check(!FileExist(commandOutput), mode " deletes child result")
    }
}

ResetNotificationCommand(mode) {
    global notificationMode, capturedCommand, commandOutput, notificationStarts, notificationTerminated,
        notificationClosed, notificationPidClosed, notificationGuardChecks, notificationInputReads, notificationWaits, afkSelfBefore
    notificationMode := mode, capturedCommand := "", commandOutput := "", notificationStarts := 0,
        notificationTerminated := 0, notificationClosed := 0, notificationPidClosed := 0,
        notificationGuardChecks := 0, notificationInputReads := 0, notificationWaits := 0, afkSelfBefore := -1
}
NotificationTestAllowed() {
    global notificationMode, notificationGuardChecks
    notificationGuardChecks++
    if (notificationMode = "guard_exception" && notificationGuardChecks > 1)
        throw Error("fixture guard exception")
    return notificationMode != "initial_guard"
        && !((notificationMode = "cancel" || notificationMode = "final_guard") && notificationGuardChecks > 1)
}
NotificationTestWinExist(query) {
    global notificationMode
    if (query != "A")
        throw Error("unexpected foreground query")
    return notificationMode = "wrong_hwnd" ? 12346 : 12345
}
NotificationTestProcessName(query) {
    global notificationMode
    if (query != "ahk_id 12345")
        throw Error("unexpected process query")
    return notificationMode = "wrong_process" ? "Other.exe" : "ShellExperienceHost.exe"
}
NotificationTestTitle(hwnd) {
    global notificationMode
    if (hwnd != 12345)
        throw Error("unexpected title query")
    return notificationMode = "wrong_title" ? "New notification - Approve" : "New notification"
}
NotificationTestPID(query) {
    if (query != "ahk_id 12345")
        throw Error("unexpected process-ID query")
    return 4321
}
NotificationTestSplitPath(path, &file := "", &directory := "", *) {
    directory := "C:\fixture repo\Features"
}
NotificationTestRun(command, cwd := "", options := "", &pid := 0) {
    global notificationMode, capturedCommand, commandOutput, notificationStarts
    notificationStarts++
    capturedCommand := command
    if (notificationMode = "spawn_error")
        throw Error("fixture spawn failure")
    if (cwd != "" || options != "Hide" || !RegExMatch(command, '-OutputPath "([^"\r\n]+)"$', &pathMatch))
        throw Error("unexpected actual process command")
    commandOutput := pathMatch[1]
    if (SubStr(commandOutput, 1, StrLen(A_Temp) + 1) != A_Temp "\"
        || !RegExMatch(SubStr(commandOutput, StrLen(A_Temp) + 2), "^gta-afk-notification-654321-[0-9]+\.txt$"))
        throw Error("result path escaped the dedicated temporary output")
    pid := 9876
    if (notificationMode = "missing_status")
        return
    status := notificationMode = "blocked_input" ? "blocked:input-changed"
        : notificationMode = "helper_error" ? "error:runtime-exception"
        : notificationMode = "invalid_status" ? "dismissed`nApprove" : "dismissed"
    FileAppend(status, commandOutput, "UTF-8")
}
NotificationTestExitCode(handle, &code) {
    global notificationMode
    if (handle != 9001)
        throw Error("exit code read from non-owned handle")
    code := notificationMode = "nonzero_dismissed" || notificationMode = "blocked_input" ? 2
        : notificationMode = "helper_error" ? 1 : 0
    return notificationMode != "exit_code_error"
}
NotificationTestDllCall(name, args*) {
    global notificationMode, notificationInputReads, notificationTerminated, notificationClosed, notificationWaits
    switch name {
        case "GetLastInputInfo":
            notificationInputReads++
            if (notificationMode = "initial_input_error" || (notificationMode = "final_input_error" && notificationInputReads > 1))
                return false
            if (args.Length != 2 || args[1] != "ptr" || !(args[2] is Buffer) || NumGet(args[2], 0, "uint") != 8)
                throw Error("unexpected LASTINPUTINFO buffer")
            tick := notificationMode = "final_tick_changed" && notificationInputReads > 1 ? 0 : 4294967294
            NumPut("uint", tick, args[2], 4)
            return true
        case "GetCurrentProcessId":
            return 654321
        case "OpenProcess":
            if (args[2] != 0x101001 || args[4] != false || args[6] != 9876)
                throw Error("unexpected process access or non-owned child PID")
            return notificationMode = "open_error" ? 0 : 9001
        case "WaitForSingleObject":
            if (args[2] != 9001)
                throw Error("wait used non-owned handle")
            notificationWaits++
            if (args[4] = 2000) {
                if (notificationTerminated != 1)
                    throw Error("termination wait did not follow one owned termination")
                return 0
            }
            if (args[4] != 0)
                throw Error("unexpected process polling interval")
            return (notificationMode = "cancel" || notificationMode = "timeout" || notificationMode = "guard_exception") && !notificationTerminated ? 0x102 : 0
        case "TerminateProcess":
            if (args[2] != 9001 || args[4] != 1)
                throw Error("termination used non-owned handle")
            notificationTerminated++
            return true
        case "CloseHandle":
            if (args[2] != 9001)
                throw Error("close used non-owned handle")
            notificationClosed++
            return true
        default:
            throw Error("unexpected native API: " name)
    }
}
NotificationTestProcessExist(pid) {
    if (pid != 9876)
        throw Error("PID existence query is not for owned child")
    return pid
}
NotificationTestProcessClose(pid) {
    global notificationPidClosed
    if (pid != 9876)
        throw Error("PID close is not for owned child")
    notificationPidClosed++
}
NotificationTestSleep(ms) {
    throw Error("fixture unexpectedly reached a live polling sleep: " ms)
}
NotificationTestIdle() => 0
Check(condition, description) {
    global notificationChecks
    if (!condition)
        throw Error(description)
    notificationChecks++
}
'@
$testFile = Join-Path ([IO.Path]::GetTempPath()) ('gta-afk-notification-command-' + [Guid]::NewGuid().ToString('N') + '.ahk')
[IO.File]::WriteAllText($testFile, $driver + "`n" + $production + "`n" + $timeoutProduction, (New-Object Text.UTF8Encoding($true)))
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
        throw 'AFK notification command test timed out.'
    }
    $stdout = $process.StandardOutput.ReadToEnd().Trim()
    $stderr = $process.StandardError.ReadToEnd().Trim()
    if ($process.ExitCode -ne 0 -or $stderr -ne '' -or $stdout -notmatch '^PASS AFKNotificationCommand cases=[0-9]+ \(offline adapters only\)$') {
        throw "AFK notification command test failed (exit=$($process.ExitCode))`nstdout: $stdout`nstderr: $stderr"
    }
    Write-Output $stdout
} finally {
    if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    $process.Dispose()
    if ([IO.File]::Exists($testFile)) { [IO.File]::Delete($testFile) }
}
