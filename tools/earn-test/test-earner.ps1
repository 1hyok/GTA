#Requires -Version 5.1
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
# Exercise the production scheduler with all window/input/timer dependencies replaced.
$source = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\Earner.ahk') -Raw -Encoding UTF8
$tick = [regex]::Match($source, '(?ms)^EarnTick\(\) \{.*?^\}').Value
if (-not $tick) { throw 'EarnTick missing' }
$guards = @('EarnInputGuardStart', 'EarnInputGuardStop', 'EarnInputWatch', 'EarnInputAllowed', 'EarnGamePID', 'EarnTaskList', 'EarnEnabledText', 'SetEarner', 'EarnStatusText', 'EarnIsMCTTask', 'EarnRunScheduledTask', 'EarnRunMCTBatch', 'EarnFinishScheduledTask', 'EarnStopAfterFailure') | ForEach-Object {
    $body = [regex]::Match($source, ('(?ms)^' + $_ + '\([^\r\n]*\) \{.*?^\}')).Value
    if (-not $body) { throw "Production function missing: $_" }
    $body
}
$production = ($tick + "`n" + ($guards -join "`n")).Replace('A_TimeIdlePhysical', 'idleMs').Replace('A_TickCount', 'fakeTick')
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
OnError(EarnerOfflineFailure)
EarnerOfflineFailure(failure, *) {
    FileAppend("FAIL scheduler runtime: " failure.Message "`n", "**")
    ExitApp(1)
}
global gEarnOn, gEarnBusy, gEarnDue, gEarnDone, gEarnTasks, gEarnCurrent, gEarnFail, gEarnNextDue, gEarnSoftFails, gEarnRetryIn, gAbort, config, GTA_WIN, afkOn
global calls, releaseCount, stopped, mode, windowExists, focused, otherBusy, activationCount, idleMs, gEarnGuardArmed, timers
global feedTimer := 0
global gEarnGamePID, fakePID, fakeTick, gEarnGuardStartedTick, gEarnUserAbort, lockAvailable, lockCalls, lockReleases, lockHeld, hooks, checkCount := 0
global beginCount, endCount, beginCleanupCount, beginOK, endOK, beginThrows, endThrows, mctOpen, events, logs, taskModes, taskDurations, beginDelay, endDelay, endInput
Reset()
gEarnOn := false
EarnTick()
Check(calls.Length = 0, "disabled")
Reset()
gEarnBusy := true
EarnTick()
Check(calls.Length = 0, "busy")
Reset()
windowExists := false
EarnTick()
Check(calls.Length = 0 && !gEarnOn && stopped = 1 && releaseCount = 0, "no game stops without cleanup input")
Reset()
fakePID := 102
EarnTick()
Check(calls.Length = 0 && !gEarnOn && stopped = 1 && lockCalls = 0, "game restart requires manual enable")
Reset()
config["Settings"]["EarnUserIdleSec"] := 1000000000
EarnTick()
Check(calls.Length = 0, "user active")
Reset()
idleMs := 1999
EarnTick()
Check(calls.Length = 0 && lockCalls = 0 && !gEarnGuardArmed, "two-second start gate waits at 1999ms")
fakeTick++, idleMs++
EarnTick()
Check(calls.Length = 2 && gEarnDone["bunker"] = 1 && lockReleases = 1, "two-second start gate executes at 2000ms")
Reset()
idleMs := 2000
mode := "long-readonly"
EarnTick()
Check(gEarnOn && !gAbort && gEarnDone["bunker"] = 1 && lockReleases = 1, "pre-start input never aborts long readonly work")
Reset()
idleMs := 2000
mode := "long-physical"
EarnTick()
Check(gEarnOn && !gAbort && idleMs > 2000 && gEarnDone["bunker"] = 0 && lockReleases = 1 && gEarnDue["bunker"] >= A_TickCount + 170000,
    "input during blocked work aborts even when newer idle exceeds start wait")
Reset()
idleMs := 0
Check(EarnStatusText() = "수익: 입력 안정 대기 2초", "overlay shows two-second input countdown")
idleMs := 1999
Check(EarnStatusText() = "수익: 입력 안정 대기 1초", "overlay keeps countdown before boundary")
idleMs := 2000
Check(EarnStatusText() = "수익: bunker 시작 대기", "overlay clears input countdown at boundary")
focused := false
Check(EarnStatusText() = "수익: GTA 포커스 대기", "overlay explains focus wait")
focused := true, otherBusy := true
Check(EarnStatusText() = "수익: 다른 매크로 종료 대기", "overlay explains busy macro wait")
otherBusy := false
for id in ["bunker", "dj"]
    gEarnDue[id] := A_TickCount + 5000
Check(EarnStatusText() = "수익: 다음 bunker 0:05 뒤", "overlay preserves future due countdown")
gEarnCurrent := "bunker", idleMs := 0, focused := false
Check(EarnStatusText() = "수익: bunker 진행 중", "running task status precedes startup wait")
Reset()
otherBusy := true
EarnTick()
Check(calls.Length = 0, "other macro")
Reset()
gEarnDue["bunker"] := A_TickCount + 300000
gEarnDue["dj"] := A_TickCount + 300000
EarnTick()
Check(calls.Length = 0, "not due")
Reset()
EarnTick()
EarnTick()
EarnTick()
Check(calls.Length = 2 && calls[1] = "bunker" && calls[2] = "dj", "serial and no immediate repeat")
Check(gEarnDone["bunker"] = 1 && gEarnDone["dj"] = 1 && releaseCount = 1, "counts and one grouped release")
gEarnDue["bunker"] := A_TickCount - 1
EarnTick()
Check(calls.Length = 3 && gEarnDone["bunker"] = 2, "next cycle")
Reset()
mode := "override"
EarnTick()
Check(gEarnDue["bunker"] > A_TickCount + 299000 && !gEarnNextDue.Has("bunker"), "task override consumed")
Reset()
mode := "retry"
EarnTick()
Check(gEarnOn && gEarnSoftFails["bunker"] = 1 && gEarnDue["bunker"] > A_TickCount + 59000, "soft retry")
gEarnDue["bunker"] := A_TickCount - 1
EarnTick()
Check(!gEarnOn && stopped = 1, "retry exhausted")
Reset()
mode := "fail"
EarnTick()
Check(!gEarnOn && stopped = 1 && releaseCount = 1 && !gEarnBusy, "hard failure")
Reset()
mode := "throw"
EarnTick()
Check(!gEarnOn && releaseCount = 1 && !gEarnBusy && InStr(gEarnFail, "test exception"), "exception releases")
Check(lockReleases = 1 && !lockHeld, "exception releases input lock")
Reset()
mode := "reenter"
EarnTick()
Check(calls.Length = 2 && releaseCount = 1, "reentry blocked while outer group continues")
Reset()
focused := false
EarnTick()
Check(calls.Length = 0 && activationCount = 0 && gEarnDue["bunker"] > A_TickCount + 29000, "focus loss postpones without activation")
Reset()
mode := "physical"
EarnTick()
Check(gEarnOn && !gAbort && stopped = 0 && !gEarnGuardArmed && gEarnDone["bunker"] = 0 && gEarnRetryIn = 0
    && gEarnDue["bunker"] >= A_TickCount + 170000 && gEarnSoftFails.Get("bunker", 0) = 0, "physical input retries in 3 minutes instead of stopping")
Reset()
mode := "focus"
EarnTick()
Check(gEarnOn && !gAbort && !gEarnGuardArmed && gEarnDone["bunker"] = 0 && gEarnDue["bunker"] >= A_TickCount + 170000,
    "focus loss retries in 3 minutes instead of stopping")
Reset()
config["Settings"]["EarnUserIdleSec"] := 0
mode := "idle-zero"
EarnTick()
Check(gEarnOn && gEarnDone["bunker"] = 0 && gEarnDue["bunker"] >= A_TickCount + 170000, "physical guard still enabled with zero start wait")
Reset()
mode := "pid"
EarnTick()
Check(!gEarnOn && gAbort && stopped = 1 && lockReleases = 1 && !lockHeld, "game restart during task aborts and unlocks")
Reset()
lockAvailable := false
EarnTick()
Check(gEarnOn && calls.Length = 0 && lockCalls = 1 && lockReleases = 0 && releaseCount = 0, "occupied input lock waits without input")
lockAvailable := true
EarnTick()
Check(calls.Length = 2 && lockReleases = 1 && !lockHeld, "available lock resumes due group")
Reset()
mode := "lock-error"
EarnTick()
Check(!gEarnOn && stopped = 1 && calls.Length = 0 && releaseCount = 0, "lock creation failure stops without game input")
Reset()
EarnInputGuardStart()
gAbort := true
Check(!EarnInputAllowed(), "abort stays latched")
EarnInputGuardStop()
Check(!gEarnGuardArmed && timers[timers.Length] = 0, "watch removed")
Reset()
for mctMode in [0,1] {
    config["Settings"]["EarnMCTOnly"] := mctMode
    tasks := EarnTaskList()
    Check(tasks.Length = 6 && tasks[1].id = "bunker" && tasks[2].id = "dj" && tasks[3].id = "warehouse"
        && tasks[4].id = "safe" && tasks[5].id = "staff" && tasks[6].id = "dispatch", "task order " mctMode)
    Check(tasks[4].on && tasks[4].fn.Name = "EarnVinewoodSafeTask" && tasks[3].on
        && tasks[3].fn.Name = "EarnWarehouseTask" && tasks[5].on
        && tasks[5].fn.Name = "EarnVinewoodStaffTask" && !tasks[6].on, "production tasks and MCT safe " mctMode)
}
Check(tasks[3].every = 600000 && tasks[4].every = 300000, "warehouse default and safe screen check interval")
config["Settings"]["EarnWarehouse"] := 0
config["Settings"]["EarnWarehouseIntervalMin"] := 12
tasks := EarnTaskList()
Check(!tasks[3].on && tasks[3].every = 720000, "warehouse explicit setting")
config["Settings"]["EarnBailAgents"] := 0
config["Settings"]["EarnCargoStaff"] := 0
config["Settings"]["EarnStaffIntervalMin"] := 7
tasks := EarnTaskList()
Check(tasks[5].on && tasks[5].every = 420000, "hangar staff alone keeps staff task on")
config["Settings"]["EarnHangarStaff"] := 0
tasks := EarnTaskList()
Check(!tasks[5].on && tasks[5].every = 420000, "staff disabled and interval")
config["Settings"]["EarnCargoStaff"] := 1
Check(EarnTaskList()[5].on, "cargo alone enables staff")
Reset()
start := A_TickCount
SetEarner(true)
Check(gEarnOn && gEarnGamePID = fakePID && hooks = 2 && timers[timers.Length] = 1000, "enable binds current game and one-second timer")
Check(feedTimer = 4000, "enable starts the safe deposit feed watch")
Check(gEarnDue["safe"] >= start && gEarnDue["safe"] <= A_TickCount
    && gEarnDue["warehouse"] >= start && gEarnDue["warehouse"] <= A_TickCount, "safe and warehouse first check immediately")
Check(gEarnDue["bunker"] <= A_TickCount && gEarnDue["dj"] <= A_TickCount, "bunker and DJ fresh read immediately")
gEarnNextDue["bunker"] := A_TickCount + 900000
gEarnDone["safe"] := 8
config["Settings"]["EarnSafeFirstMin"] := 3
fakePID := 202
start := A_TickCount
SetEarner(true)
Check(gEarnGamePID = 202 && gEarnNextDue.Count = 0 && gEarnDone["safe"] = 0
    && gEarnDue["safe"] >= start + 180000, "manual restart resets old reservations and respects first wait")
Reset()
windowExists := false
SetEarner(true)
Check(!gEarnOn && hooks = 0 && stopped = 1 && releaseCount = 0, "enable without game stays off")
Reset()
SetEarner(true)
EarnTick()
EarnTick()
EarnTick()
EarnTick()
EarnTick()
Check(calls.Length = 5 && calls[1] = "bunker" && calls[2] = "dj" && calls[3] = "warehouse"
    && calls[4] = "safe" && calls[5] = "staff" && lockReleases = 3, "real task list consumes MCT group then two app tasks")
FileAppend("PASS Earner: " checkCount " cases; no game input`n", "*")
ExitApp(0)

Reset() {
    global
    fakeTick := 100000, idleMs := 60000, gEarnGuardArmed := false, gEarnGuardStartedTick := 0, gEarnUserAbort := false
    timers := [], fakePID := 101, gEarnGamePID := 101
    beginCount := 0, endCount := 0, beginCleanupCount := 0, beginOK := true, endOK := true,
        beginThrows := false, endThrows := false, mctOpen := false, events := [], logs := [],
        taskModes := Map(), taskDurations := Map(), beginDelay := 0, endDelay := 0, endInput := false
    lockAvailable := true, lockCalls := 0, lockReleases := 0, lockHeld := false, hooks := 0
    gEarnOn := true, gEarnBusy := false, gEarnCurrent := "", gEarnFail := "", gEarnRetryIn := 0, gAbort := false, afkOn := false
    gEarnDue := Map("bunker", A_TickCount - 1, "dj", A_TickCount - 1)
    gEarnDone := Map("bunker", 0, "dj", 0), gEarnNextDue := Map(), gEarnSoftFails := Map()
    gEarnTasks := [{id:"bunker", label:"bunker", on:true, every:300000, fn:RunTask.Bind("bunker")}, {id:"dj", label:"dj", on:true, every:300000, fn:RunTask.Bind("dj")}]
    config := Map("Settings", Map("EarnUserIdleSec", 2, "EarnSoftFailMax", 1, "EarnMCTOnly",1,
        "EarnSafe",1,"EarnSafeIntervalMin",5,"EarnSafeFirstMin",0,"EarnBunker",1,"EarnBunkerIntervalSec",6720,
        "EarnDJ",1,"EarnDJIntervalMin",5,"EarnDispatch",0,"EarnDispatchIntervalMin",48,"EarnDispatchFirstMin",0),
        "Features", Map("AntiAFK", 0))
    GTA_WIN := "fake", calls := [], releaseCount := 0, stopped := 0, mode := "ok", windowExists := true, focused := true, otherBusy := false, activationCount := 0
}
RunTask(id, manageSession := true) {
    global calls, mode, gEarnNextDue, gEarnRetryIn, idleMs, focused, fakePID, fakeTick
    if (!lockHeld || !gEarnBusy || !gEarnGuardArmed)
        throw Error("Every body must share the live input lock and guard")
    if (EarnIsMCTTask(id) ? manageSession || !mctOpen : mctOpen)
        throw Error("MCT bodies require the shared session; apps require it closed")
    calls.Push(id)
    events.Push(id)
    taskMode := taskModes.Get(id,mode)
    duration := taskDurations.Get(id,0)
    fakeTick += duration, idleMs += duration
    if (taskMode = "long-readonly") {
        fakeTick += 30000
        idleMs += 30000
        EarnInputWatch()
        return true
    }
    if (taskMode = "long-physical") {
        fakeTick += 10000
        idleMs := 5000
        EarnInputWatch()
        return true
    }
    if (taskMode = "pid") {
        fakePID++
        EarnInputWatch()
        return true
    }
    if (taskMode = "physical" || taskMode = "idle-zero") {
        idleMs := 0
        EarnInputWatch()
        gEarnRetryIn := 60000
        return true
    }
    if (taskMode = "focus") {
        focused := false
        EarnInputWatch()
        return true
    }
    if (taskMode = "override")
        gEarnNextDue[id] := A_TickCount + 300000
    if (taskMode = "retry") {
        gEarnRetryIn := 60000
        return false
    }
    if (taskMode = "fail")
        return EarnFail("expected failure")
    if (taskMode = "throw")
        throw Error("test exception")
    if (taskMode = "reenter")
        EarnTick()
    return true
}
Check(ok, name) {
    global checkCount
    checkCount++
    if (!ok) {
        FileAppend("FAIL " name "`n", "*")
        ExitApp(1)
    }
}
WinExist(*) => windowExists
WinGetPID(*) => fakePID
IsGTAActive() => focused
EarnOtherMacroBusy() => otherBusy
BringGTAToFront() {
    global activationCount
    activationCount++
    return false
}
ReleaseHeldKeys() {
    global releaseCount
    releaseCount++
}
EarnFail(reason) {
    global gEarnFail
    gEarnFail := reason
    return false
}
SetAntiAFK(*) {
    throw Error("unexpected AFK call")
}
SetTimer(fn, period) {
    global timers, stopped, feedTimer
    if (fn.Name = "EarnSafeFeedWatch") {
        feedTimer := period
        return
    }
    timers.Push(period)
    if (fn.Name = "EarnTick" && period = 0)
        stopped++
}
EarnInputLockAcquire(*) {
    global lockCalls, lockHeld
    lockCalls++
    if (mode = "lock-error")
        throw Error("test lock failure")
    if (!lockAvailable)
        return 0
    if (lockHeld)
        throw Error("input lock was not released")
    lockHeld := true
    return {macro:1,gui:2}
}
EarnInputLockRelease(*) {
    global lockHeld, lockReleases
    if (!lockHeld)
        throw Error("released input lock without ownership")
    lockHeld := false
    lockReleases++
}
InstallKeybdHook(*) {
    global hooks
    hooks++
}
InstallMouseHook(*) {
    global hooks
    hooks++
}
KeyLabelFor(*) => "F9"
EarnVinewoodSafeTask() => RunTask("safe")
; 입금 알림 감시는 화면을 읽으므로 스케줄러 시험에서는 타이머 대상 이름만 있으면 된다.
EarnSafeFeedWatch() => 0
EarnBunkerTask(manageSession := true) => RunTask("bunker",manageSession)
EarnDJTask(manageSession := true) => RunTask("dj",manageSession)
EarnWarehouseTask(manageSession := true) => RunTask("warehouse",manageSession)
EarnVinewoodStaffTask() => RunTask("staff")
EarnDispatchTask() => RunTask("dispatch")
EarnTaskMCTBegin() {
    global beginCount, beginCleanupCount, mctOpen, fakeTick, idleMs
    if (!lockHeld || !gEarnGuardArmed || mctOpen)
        throw Error("Group begin requires one guarded lock and no open session")
    beginCount++, events.Push("begin")
    fakeTick += beginDelay, idleMs += beginDelay
    if (!beginOK || beginThrows) {
        beginCleanupCount++
        if (beginThrows)
            throw Error("begin exception")
        return EarnFail("begin failed")
    }
    mctOpen := true
    return true
}
EarnTaskMCTEnd() {
    global endCount, mctOpen, fakeTick, idleMs
    if (!lockHeld || !gEarnGuardArmed || !mctOpen)
        throw Error("Group end must retain its single input lock and guard")
    endCount++, events.Push("end")
    fakeTick += endDelay, idleMs += endDelay
    if (endInput) {
        idleMs := 0
        EarnInputWatch()
    }
    if (endThrows)
        throw Error("end exception")
    if (!endOK || gAbort)
        return EarnFail("end failed")
    mctOpen := false
    return true
}
EarnLog(message) {
    logs.Push(message)
    if (SubStr(message,1,3) = "끝: " && mctOpen)
        throw Error("Completion log cannot precede MCT cleanup")
}
ShowTooltip(*) {
}
'@
$driver = $driver.Replace('A_TickCount', 'fakeTick')
$previous = [Console]::InputEncoding
[Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
try {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $AhkPath
    $info.Arguments = '/ErrorStdOut /CP65001 *'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($info)
    try {
        $p.StandardInput.WriteLine($driver + "`n" + $production)
        $p.StandardInput.Close()
        if (-not $p.WaitForExit(10000)) { $p.Kill(); throw 'Scheduler test timed out' }
        $stdout = $p.StandardOutput.ReadToEnd().Trim()
        $stderr = $p.StandardError.ReadToEnd().Trim()
        if ($p.ExitCode -ne 0 -or $stderr -or $stdout -ne 'PASS Earner: 54 cases; no game input') {
            throw "exit=$($p.ExitCode) stdout=$stdout stderr=$stderr"
        }
        $stdout
    } finally { $p.Dispose() }
} finally { [Console]::InputEncoding = $previous }

# Use unique Windows object names. These checks never open the live GTA input locks.
$lockFunctions = @('EarnInputLockAcquire', 'EarnInputLockRelease') | ForEach-Object {
    $body = [regex]::Match($source, ('(?ms)^' + $_ + '\([^\r\n]*\) \{.*?^\}')).Value
    if (-not $body) { throw "Production lock function missing: $_" }
    $body
}
function Invoke-EarnerMutexCheck {
    param([string]$Driver, [string]$Expected)
    $previousMutexEncoding = [Console]::InputEncoding
    [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $AhkPath
    $info.Arguments = '/ErrorStdOut /CP65001 *'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($info)
    try {
        $p.StandardInput.WriteLine("#Requires AutoHotkey v2.0`n#SingleInstance Off`n#NoTrayIcon`n#Warn All, StdOut`n" +
            $Driver + "`n" + ($lockFunctions -join "`n"))
        $p.StandardInput.Close()
        if (-not $p.WaitForExit(10000)) {
            $p.Kill()
            $p.WaitForExit()
            throw 'Input mutex check timed out'
        }
        $stdout = $p.StandardOutput.ReadToEnd().Trim()
        $stderr = $p.StandardError.ReadToEnd().Trim()
        if ($p.ExitCode -ne 0 -or $stderr -or $stdout -cne $Expected) {
            throw "Input mutex check failed: exit=$($p.ExitCode) stdout=$stdout stderr=$stderr"
        }
        $stdout
    } finally {
        if (-not $p.HasExited) { $p.Kill(); $p.WaitForExit() }
        $p.Dispose()
        [Console]::InputEncoding = $previousMutexEncoding
    }
}
$mutexPrefix = 'Local\GtaEarnerOffline-' + [guid]::NewGuid().ToString('N')
$macroName = $mutexPrefix + '-macro'
$guiName = $mutexPrefix + '-gui'
$mutexDriver = @'
macroName := "@MACRO@", guiName := "@GUI@"
held := EarnInputLockAcquire(macroName, guiName)
if (!IsObject(held))
    throw Error("free input locks must be acquired")
if (EarnInputLockAcquire(macroName, guiName) != 0)
    throw Error("GUI name reservation must prevent another task")
for name in [macroName,guiName] {
    probe := DllCall("OpenMutexW", "uint", 0x100000, "int", 0, "str", name, "ptr")
    if (!probe)
        throw Error("both names must exist while task holds locks")
    DllCall("CloseHandle", "ptr", probe)
}
EarnInputLockRelease(held)
for name in [macroName,guiName] {
    probe := DllCall("OpenMutexW", "uint", 0x100000, "int", 0, "str", name, "ptr")
    if (probe)
        throw Error("released input lock handle leaked")
}
held := EarnInputLockAcquire(macroName, guiName)
if (!IsObject(held))
    throw Error("next task must reacquire released locks")
EarnInputLockRelease(held)
FileAppend("PASS EarnerMutex free: 5 cases; no game input`n", "*")
ExitApp(0)
'@
Invoke-EarnerMutexCheck ($mutexDriver.Replace('@MACRO@', $macroName).Replace('@GUI@', $guiName)) 'PASS EarnerMutex free: 5 cases; no game input'

# The PowerShell host owns this mutex; AHK is another process and cannot recursively acquire it.
$ownedMutex = New-Object Threading.Mutex($false, $macroName)
$owned = $ownedMutex.WaitOne(0)
if (-not $owned) { $ownedMutex.Dispose(); throw 'Unique test mutex was unexpectedly occupied' }
try {
    $blockedDriver = @'
if (EarnInputLockAcquire("@MACRO@", "@GUI@") != 0)
    throw Error("another process owns the macro mutex")
probe := DllCall("OpenMutexW", "uint", 0x100000, "int", 0, "str", "@GUI@", "ptr")
if (probe)
    throw Error("waiting task must close its temporary GUI reservation")
FileAppend("PASS EarnerMutex busy: 2 cases; no game input`n", "*")
ExitApp(0)
'@
    Invoke-EarnerMutexCheck ($blockedDriver.Replace('@MACRO@', $macroName).Replace('@GUI@', $guiName)) 'PASS EarnerMutex busy: 2 cases; no game input'
} finally {
    $ownedMutex.ReleaseMutex()
    $ownedMutex.Dispose()
}
$existingGui = New-Object Threading.Mutex($false, $guiName)
try {
    $guiDriver = @'
if (EarnInputLockAcquire("@MACRO@", "@GUI@") != 0)
    throw Error("existing GUI receiver must block task entry")
probe := DllCall("OpenMutexW", "uint", 0x100000, "int", 0, "str", "@MACRO@", "ptr")
if (probe)
    throw Error("waiting for GUI must not create or retain a macro mutex")
FileAppend("PASS EarnerMutex GUI: 2 cases; no game input`n", "*")
ExitApp(0)
'@
    Invoke-EarnerMutexCheck ($guiDriver.Replace('@MACRO@', $macroName).Replace('@GUI@', $guiName)) 'PASS EarnerMutex GUI: 2 cases; no game input'
} finally { $existingGui.Dispose() }
