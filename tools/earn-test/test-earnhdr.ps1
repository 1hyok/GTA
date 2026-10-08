#Requires -Version 5.1
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
# Production lease/controller, fake display/clock/store only. Never calls a native display API.
$source = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnHdr.ahk') -Raw -Encoding UTF8
$production = ''
foreach ($name in @('EarnHdrBegin','EarnHdrWait','EarnHdrRestore','EarnHdrExit','EarnHdrPacket','EarnHdrInputAllowed')) {
    $body = [regex]::Match($source, ('(?ms)^' + $name + '\([^\r\n]*\) \{.*?^\}')).Value
    if (-not $body) { throw "Production HDR function missing: $name" }
    $production += "`n" + $body.Replace('A_TickCount','clockMs')
}
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global gEarnHdrLease := "", gEarnHdrRestoring := false, gEarnHdrPreparing := false, clockMs := 0, enabled := true
global writes := [], store := "", allow := true, writable := true, writeOK := true, readFails := false, ignoreWrite := false
global abortAt := -1, abortDuringWrite := false, checks := 0, logs := [], timers := []
global hdrLockHeld := false, otherOwner := false, journalReads := 0, activeMode := true, modeDelay := 0, modeReadyAt := -1
global restoreDuringRead := false, keyReleased := false, requireKeyRelease := false
global gEarnInputGuard := EarnInputAllowed
OnError((e,*) => (FileAppend("FAIL " e.Message "`n","**"),ExitApp(1)))
try {
    Check(EarnHdrBegin() && !enabled && writes.Length = 1 && writes[1] = false,"active work turns HDR OFF and verifies stable state")
    Check(store != "" && IsObject(gEarnHdrLease),"original ON durable before write")
    Check(EarnHdrRestore() && enabled && store = "" && !IsObject(gEarnHdrLease),"finally restores original ON")
    Reset(false)
    Check(EarnHdrBegin() && EarnHdrRestore() && !enabled && writes.Length = 0,"original OFF unchanged")
    Reset(true)
    allow := false
    Check(!EarnHdrBegin() && writes.Length = 0,"no active input owner means no HDR change")
    Reset(true)
    writable := false, threw := false
    try EarnHdrBegin()
    catch
        threw := true
    Check(threw && enabled && writes.Length = 0,"journal save failure forbids OFF")
    Reset(true)
    abortAt := 100
    Check(!EarnHdrBegin() && enabled && !IsObject(gEarnHdrLease),"physical user interruption restores during transition without task input")
    Reset(true)
    abortDuringWrite := true
    Check(!EarnHdrBegin() && enabled && writes.Length = 2 && !writes[1] && writes[2]
        && store = "", "input during synchronous OFF call restores on return without a late OFF")
    Reset(true)
    writeOK := false, threw := false
    try EarnHdrBegin()
    catch
        threw := true
    Check(threw && enabled && store != "","failed OFF request preserves restoration record")
    writeOK := true
    Check(EarnHdrRestore() && store = "","failed OFF finally resolves original state")
    Reset(true)
    ignoreWrite := true
    threw := false
    try EarnHdrBegin()
    catch
        threw := true
    Check(threw && clockMs = 5000,"OFF status mismatch times out before task input")
    ignoreWrite := false
    Check(EarnHdrRestore(),"failed transition restored")
    Reset(true)
    Check(EarnHdrBegin(),"setup restore failure")
    readFails := true
    Check(!EarnHdrRestore() && store != "" && IsObject(gEarnHdrLease),"restore failure retains exact target and durable record")
    readFails := false
    Check(EarnHdrRestore() && enabled,"retry consumes retained restoration")
    Reset(false)
    store := "42|7|16|monitor-A"
    Check(EarnHdrRestore("startup") && enabled && store = "","next startup restores journal after forced termination")
    Reset(false)
    store := "42|7|16|different-monitor"
    Check(!EarnHdrRestore() && writes.Length = 0 && store != "","changed display identity forbids restore to another monitor")
    Reset(true)
    Check(EarnHdrBegin() && EarnHdrExit() = 0 && enabled,"OnExit restores original HDR")
    Reset(true)
    Check(EarnHdrBegin(),"setup exit key ordering")
    requireKeyRelease := true
    gEarnHdrPreparing := true, gEarnHdrRestoring := true
    Check(EarnHdrExit() = 0 && enabled && keyReleased && !gEarnHdrPreparing && !gEarnHdrRestoring,"OnExit inherits interrupted preparation/restore and releases keys first")
    Reset(true)
    restoreDuringRead := true
    Check(EarnHdrBegin() && hdrLockHeld && store != "", "preparation retry cannot unlock owner before durable OFF")
    Check(EarnHdrRestore(),"preparation reentry lease restores normally")
    Reset(true)
    modeDelay := 300
    Check(EarnHdrBegin() && clockMs >= 800 && !activeMode,"OFF waits for actual SDR mode after user flag changes")
    Check(EarnHdrRestore() && activeMode,"ON waits for actual HDR mode")
    Reset(false)
    activeMode := true, modeReadyAt := 300
    Check(EarnHdrBegin() && clockMs >= 800 && writes.Length = 0,"original OFF with HDR mode still active waits without writing")
    Reset(false)
    store := "42|7|16|monitor-A", otherOwner := true
    Check(!EarnHdrRestore("other Main startup") && journalReads = 0 && writes.Length = 0 && store != "",
        "active other process blocks startup and retry before reading its journal")
    otherOwner := false
    Check(EarnHdrRestore() && enabled,"abandoned owner journal is recoverable")
    testPacket := EarnHdrPacket(16,24,{adapter:42,id:7})
    Check(testPacket.Size = 24 && NumGet(testPacket,0,"uint") = 16 && NumGet(testPacket,4,"uint") = 24
        && NumGet(testPacket,8,"int64") = 42 && NumGet(testPacket,16,"uint") = 7 && NumGet(testPacket,20,"uint") = 0,
        "official native header sizes and offsets")
    FileAppend("PASS EarnHDR cases=" checks " (no display changes or game input)`n","*")
    ExitApp(0)
} catch as testFailure {
    FileAppend("FAIL " testFailure.Message "`n" testFailure.Stack,"**")
    ExitApp(1)
}
Reset(initial) {
    global
    gEarnHdrLease := "", gEarnHdrRestoring := false, clockMs := 0, enabled := initial
    writes := [], store := "", allow := true, writable := true, writeOK := true, readFails := false
    ignoreWrite := false, abortAt := -1, abortDuringWrite := false
    hdrLockHeld := false, otherOwner := false, journalReads := 0, activeMode := initial, modeDelay := 0, modeReadyAt := -1
    restoreDuringRead := false, keyReleased := false, requireKeyRelease := false
}
Check(ok,message) {
    global checks
    checks++
    if (!ok)
        throw Error(message)
}
EarnHdrTarget() => {adapter:42,id:7,path:"monitor-A"}
EarnHdrRead(target) {
    global activeMode,modeReadyAt,restoreDuringRead
    if (restoreDuringRead) {
        restoreDuringRead := false
        Check(!EarnHdrRestore("preparation timer") && hdrLockHeld,"retry preserves preparing owner's mutex")
    }
    if (readFails || target.path != "monitor-A")
        throw Error("display identity or query failed")
    if (modeReadyAt >= 0 && clockMs >= modeReadyAt)
        activeMode := enabled, modeReadyAt := -1
    return {enabled:enabled,active:activeMode,api:16}
}
EarnHdrWrite(target,api,value) {
    global enabled,writes,clockMs,abortAt,activeMode,modeReadyAt
    if (store = "" || target.path != "monitor-A" || api != 16)
        throw Error("write before durable lease or to wrong target")
    writes.Push(value)
    if (value && requireKeyRelease && !keyReleased)
        throw Error("HDR restore preceded key release")
    if (!hdrLockHeld)
        throw Error("display write without HDR owner mutex")
    if (writeOK && !ignoreWrite) {
        enabled := value
        modeReadyAt := clockMs+modeDelay
    }
    if (!value && abortDuringWrite)
        clockMs += 100, abortAt := clockMs
    return writeOK
}
EarnStateGet(*) {
    global journalReads
    journalReads++
    return store
}
EarnHdrLock() {
    global hdrLockHeld
    if (otherOwner)
        return false
    hdrLockHeld := true
    return true
}
EarnHdrUnlock() {
    global hdrLockHeld
    hdrLockHeld := false
}
ReleaseHeldKeys(*) {
    global keyReleased
    keyReleased := true
}
EarnStateSet(key,value) {
    global store
    if (writable)
        store := value
}
EarnInputAllowed() {
    global allow
    if (abortAt >= 0 && clockMs >= abortAt) {
        allow := false
        EarnHdrRestore("user input")
    }
    return allow
}
Sleep(ms) {
    global clockMs
    clockMs += ms
}
EarnLog(message) => logs.Push(message)
EarnHdrRetryRestore() => EarnHdrRestore()
SetTimer(fn,period) => timers.Push(period)
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
$previousEncoding = [Console]::InputEncoding
[Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
$p = [Diagnostics.Process]::Start($info)
try {
    $p.StandardInput.WriteLine($driver + $production)
    $p.StandardInput.Close()
    if (-not $p.WaitForExit(10000)) { $p.Kill(); throw 'HDR offline test timed out' }
    $out = $p.StandardOutput.ReadToEnd().Trim()
    $err = $p.StandardError.ReadToEnd().Trim()
    if ($p.ExitCode -ne 0 -or $err -or $out -notmatch '^PASS EarnHDR cases=\d+ \(no display changes or game input\)$') {
        throw "HDR test failed exit=$($p.ExitCode) stdout=$out stderr=$err"
    }
    $out
} finally { $p.Dispose(); [Console]::InputEncoding = $previousEncoding }

$nativeProduction = ''
foreach ($name in @('EarnHdrTarget','EarnHdrRead','EarnHdrDevicePath','EarnHdrWrite','EarnHdrPacket','EarnHdrLock','EarnHdrUnlock')) {
    $nativeProduction += "`n" + [regex]::Match($source, ('(?ms)^' + $name + '\([^\r\n]*\) \{.*?^\}')).Value
}
$nativeDriver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global modern := true, cloned := false, queryRetry := true, queries := 0, legacyBits := 3, writes := []
global gEarnHdrMutex := 0, nativeOwnerBusy := false
try {
    testTarget := EarnHdrTarget()
    if (testTarget.adapter != 43 || testTarget.id != 9 || testTarget.path != "monitor-B" || queries != 2)
        throw Error("active target mapping/retry was wrong")
    nativeState := EarnHdrRead(testTarget)
    if (!nativeState.enabled || nativeState.api != 16)
        throw Error("modern HDR bit or structure was wrong")
    if (!EarnHdrWrite(testTarget,16,false) || writes.Length != 1 || writes[1] != 0)
        throw Error("native OFF packet was wrong")
    modern := false
    nativeState := EarnHdrRead(testTarget)
    if (!nativeState.enabled || nativeState.api != 10)
        throw Error("legacy HDR mapping was wrong")
    legacyBits := 7, rejected := false
    try EarnHdrRead(testTarget)
    catch
        rejected := true
    if (!rejected)
        throw Error("legacy enforced WCG must not be changed")
    cloned := true, rejected := false
    try EarnHdrTarget()
    catch
        rejected := true
    if (!rejected)
        throw Error("cloned targets must be rejected")
    if (!EarnHdrLock() || !gEarnHdrMutex)
        throw Error("native HDR owner lock not retained")
    EarnHdrUnlock(), nativeOwnerBusy := true
    if (EarnHdrLock() || gEarnHdrMutex)
        throw Error("native other-owner lock must be nonblocking")
    FileAppend("PASS EarnHDR native packets cases=8 (mock DisplayConfig only)`n","*")
    ExitApp(0)
} catch as nativeFailure {
    FileAppend("FAIL " nativeFailure.Message,"**")
    ExitApp(1)
}
IsGTAActive() => 100
DllCall(name,args*) {
    global queries
    if (name = "CreateMutexW")
        return 55
    if (name = "WaitForSingleObject")
        return nativeOwnerBusy ? 0x102 : 0
    if (name = "ReleaseMutex" || name = "CloseHandle")
        return 1
    if (name = "User32\MonitorFromWindow")
        return 5
    if (name = "User32\GetMonitorInfoW") {
        StrPut("\\.\DISPLAY2",args[4].Ptr+40,32,"UTF-16")
        return 1
    }
    if (name = "User32\GetDisplayConfigBufferSizes") {
        if (args[2] != 2)
            throw Error("query must only enumerate active paths")
        %args[4]% := 2, %args[6]% := 2
        return 0
    }
    if (name = "User32\QueryDisplayConfig") {
        queries++
        if (queryRetry && queries = 1)
            return 122
        paths := args[6]
        Loop 2 {
            pos := (A_Index-1)*72
            NumPut("int64",42+A_Index-1,"uint",A_Index = 1 ? 0 : 2,paths,pos)
            NumPut("int64",42+A_Index-1,"uint",A_Index = 1 ? 7 : 9,paths,pos+20)
        }
        return 0
    }
    if (name = "User32\DisplayConfigGetDeviceInfo" || name = "User32\DisplayConfigSetDeviceInfo") {
        packetData := args[2], kind := NumGet(packetData,0,"uint"), packetSize := NumGet(packetData,4,"uint")
        if (kind = 1) {
            if (packetSize != 84)
                throw Error("source packet size")
            StrPut(cloned || NumGet(packetData,16,"uint") = 2 ? "\\.\DISPLAY2" : "\\.\DISPLAY1",packetData.Ptr+20,32,"UTF-16")
            return 0
        }
        if (NumGet(packetData,8,"int64") != 43 || NumGet(packetData,16,"uint") != 9)
            throw Error("changed a non-game display")
        if (kind = 2) {
            if (packetSize != 420)
                throw Error("target identity packet size")
            StrPut("monitor-B",packetData.Ptr+164,128,"UTF-16")
            return 0
        }
        if (kind = 15) {
            if (packetSize != 36)
                throw Error("modern query packet size")
            NumPut("uint",48,packetData,20)
            NumPut("uint",2,packetData,32)
            return modern ? 0 : 87
        }
        if (kind = 9) {
            if (packetSize != 32)
                throw Error("legacy query packet size")
            NumPut("uint",legacyBits,packetData,20)
            return 0
        }
        if (kind = 16 && name = "User32\DisplayConfigSetDeviceInfo") {
            if (packetSize != 24)
                throw Error("set packet size")
            writes.Push(NumGet(packetData,20,"uint"))
            return 0
        }
    }
    throw Error("unmocked native call: " name)
}
'@
$previousEncoding = [Console]::InputEncoding
[Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
$p = [Diagnostics.Process]::Start($info)
try {
    $p.StandardInput.WriteLine($nativeDriver + $nativeProduction)
    $p.StandardInput.Close()
    if (-not $p.WaitForExit(10000)) { $p.Kill(); throw 'Native HDR mock timed out' }
    $out = $p.StandardOutput.ReadToEnd().Trim()
    $err = $p.StandardError.ReadToEnd().Trim()
    if ($p.ExitCode -ne 0 -or $err -or $out -ne 'PASS EarnHDR native packets cases=8 (mock DisplayConfig only)') {
        throw "Native HDR mock failed exit=$($p.ExitCode) stdout=$out stderr=$err"
    }
    $out
} finally { $p.Dispose(); [Console]::InputEncoding = $previousEncoding }

# The real one-shot input consumer uses the same lease, while readonly invocations never consume it.
$standaloneSource = Get-Content (Join-Path $PSScriptRoot 'earntest.ahk') -Raw -Encoding UTF8
$standaloneProduction = ''
$standaloneProduction += [regex]::Match($source, '(?ms)^EarnHdrExit\([^\r\n]*\) \{.*?^\}').Value
foreach ($name in @('EarnTestPrepare','EarnTestInputAllowed','EarnTestExit','StopAll')) {
    $body = [regex]::Match($standaloneSource, ('(?ms)^' + $name + '\([^\r\n]*\) \{.*?^\}')).Value
    if (-not $body) { throw "Standalone consumer missing: $name" }
    $standaloneProduction += "`n" + $body.Replace('A_TimeIdlePhysical','testIdle')
}
$standaloneDriver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global GTA_WIN := "fake GTA", gAbort := false, gTestArmed := false, gTestIdleMs := 8000, gTestInputMutex := 0
global testIdle := 60000, hdrStarts := 0, hdrRestores := 0, beginOK := true, checks := 0
global gEarnHdrPreparing := false, gEarnHdrRestoring := false
try {
    EarnTestExit()
    Check(hdrStarts = 0 && hdrRestores = 0,"readonly exit never consumes HDR journal")
    Check(EarnTestPrepare() && hdrStarts = 1 && gTestArmed,"one-shot prepare acquires HDR after input owner")
    testIdle := 0
    Check(!EarnTestInputAllowed() && gAbort && hdrRestores = 1,"one-shot physical input abort restores HDR")
    gEarnHdrPreparing := true, gEarnHdrRestoring := true
    EarnTestExit()
    Check(hdrRestores = 2 && !gEarnHdrPreparing && !gEarnHdrRestoring,"one-shot exit inherits interrupted preparation and restore")
    gAbort := false, testIdle := 60000, beginOK := false
    Check(!EarnTestPrepare(),"failed HDR preparation prevents one-shot task")
    StopAll()
    Check(gAbort && hdrRestores = 3,"one-shot End restores HDR")
    FileAppend("PASS EarnHDR standalone cases=6 (no display changes or game input)`n","*")
    ExitApp(0)
} catch as standaloneFailure {
    FileAppend("FAIL " standaloneFailure.Message,"**")
    ExitApp(1)
}
Check(ok,message) {
    global checks
    checks++
    if (!ok)
        throw Error(message)
}
Idle() => testIdle
WinExist(*) => 1
IsGTAActive() => 1
WinGetPID(*) => 101
WinActivate(*) => 0
WinWaitActive(*) => true
EarnTestTimeout(*) => 0
EarnTestWatch(*) => 0
SetTimer(*) => 0
ReleaseHeldKeys(*) => 0
EarnLog(*) => 0
EarnFail(*) => false
EarnHdrBegin() {
    global hdrStarts
    if (!gTestArmed || !gTestInputMutex)
        throw Error("one-shot HDR changed before acquiring input ownership")
    hdrStarts++
    return beginOK
}
EarnHdrRestore(*) {
    global hdrRestores
    if (gEarnHdrPreparing || gEarnHdrRestoring)
        return false
    hdrRestores++
    return true
}
DllCall(name,*) {
    if (name = "CreateMutexW")
        return 7
    if (name = "WaitForSingleObject" || name = "ReleaseMutex" || name = "CloseHandle")
        return 0
    throw Error("unexpected native call in standalone mock")
}
'@
$previousEncoding = [Console]::InputEncoding
[Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
$p = [Diagnostics.Process]::Start($info)
try {
    $p.StandardInput.WriteLine($standaloneDriver + $standaloneProduction)
    $p.StandardInput.Close()
    if (-not $p.WaitForExit(10000)) { $p.Kill(); throw 'Standalone HDR offline test timed out' }
    $out = $p.StandardOutput.ReadToEnd().Trim()
    $err = $p.StandardError.ReadToEnd().Trim()
    if ($p.ExitCode -ne 0 -or $err -or $out -ne 'PASS EarnHDR standalone cases=6 (no display changes or game input)') {
        throw "Standalone HDR failed exit=$($p.ExitCode) stdout=$out stderr=$err"
    }
    $out
} finally { $p.Dispose(); [Console]::InputEncoding = $previousEncoding }
