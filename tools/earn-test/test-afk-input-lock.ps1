#Requires -Version 5.1
[CmdletBinding()]
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $PSScriptRoot '..\..\Features\AntiAFK.ahk'
$source = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8
$mutexPrefix = 'Local\GtaAfkOffline-' + [Guid]::NewGuid().ToString('N')
$macroName = $mutexPrefix + '-macro'
$guiName = $mutexPrefix + '-gui'
$lockFunctions = @('AFKInputLockAcquire', 'AFKInputLockRelease') | ForEach-Object {
    $matches = [regex]::Matches($source, ('(?ms)^' + $_ + '\([^\r\n]*\) \{.*?^\}'))
    if ($matches.Count -ne 1) { throw "Expected one production function: $_" }
    $matches[0].Value
}
$production = ($lockFunctions -join "`n").Replace('"Local\GtaMacroInput"', ('"' + $macroName + '"')).Replace('"Local\GtaGuiInput"', ('"' + $guiName + '"'))
if ($production.Contains('Local\GtaMacroInput') -or $production.Contains('Local\GtaGuiInput')) {
    throw 'Live input mutex name remained in isolated fixture.'
}
$script:mutexChecks = 0
$preamble = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global mutexChecks := 0, macroName := "@MACRO@", guiName := "@GUI@"
try {
    RunMutexFixture()
    FileAppend("PASS AFKMutex cases=" mutexChecks "`n", "*")
    ExitApp(0)
} catch as failure {
    FileAppend("FAIL AFKMutex: " failure.Message "`n", "**")
    ExitApp(1)
}
Check(condition, description) {
    global mutexChecks
    if (!condition)
        throw Error(description)
    mutexChecks++
}
NameExists(name) {
    if (!RegExMatch(name, "^Local\\GtaAfkOffline-[a-f0-9]{32}-(macro|gui)$"))
        throw Error("refusing non-fixture mutex name")
    handle := DllCall("OpenMutexW", "uint", 0x100000, "int", 0, "str", name, "ptr")
    if (handle)
        DllCall("CloseHandle", "ptr", handle)
    return !!handle
}
'@
$preamble = $preamble.Replace('@MACRO@', $macroName).Replace('@GUI@', $guiName)

function Invoke-AFKMutexCheck {
    param([string]$Driver, [int]$ExpectedCount, [string]$Name)
    $previousEncoding = [Console]::InputEncoding
    [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
    $process = $null
    try {
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
        $process = [Diagnostics.Process]::Start($info)
        $process.StandardInput.WriteLine($preamble + "`n" + $Driver + "`n" + $production)
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(10000)) {
            $process.Kill()
            $process.WaitForExit()
            throw "AFK input mutex fixture timed out: $Name"
        }
        $stdout = $process.StandardOutput.ReadToEnd().Trim()
        $stderr = $process.StandardError.ReadToEnd().Trim()
        if ($process.ExitCode -ne 0 -or $stderr -or $stdout -cne "PASS AFKMutex cases=$ExpectedCount") {
            throw "AFK input mutex fixture failed: $Name; exit=$($process.ExitCode); stdout=$stdout; stderr=$stderr"
        }
        $script:mutexChecks += $ExpectedCount
    } finally {
        if ($process) {
            if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
            $process.Dispose()
        }
        [Console]::InputEncoding = $previousEncoding
    }
}

$freeDriver = @'
RunMutexFixture() {
    global macroName, guiName
    held := AFKInputLockAcquire(macroName, guiName)
    Check(IsObject(held), "free macro and GUI locks acquired")
    try {
        Check(AFKInputLockAcquire(macroName, guiName) = 0, "GUI name reservation prevents nested task entry")
        for name in [macroName, guiName]
            Check(NameExists(name), "both objects exist while held")
    } finally {
        AFKInputLockRelease(held)
    }
    for name in [macroName, guiName]
        Check(!NameExists(name), "no named object leaks after release")
    held := AFKInputLockAcquire(macroName, guiName)
    Check(IsObject(held), "next task reacquires released pair")
    AFKInputLockRelease(held)
    for name in [macroName, guiName]
        Check(!NameExists(name), "reacquired pair also fully released")
}
'@
Invoke-AFKMutexCheck $freeDriver 9 'free/release/reacquire'

$goneDriver = @'
RunMutexFixture() {
    global macroName, guiName
    for name in [macroName, guiName]
        Check(!NameExists(name), "cross-process fixture left no named object")
}
'@

# The PowerShell thread owns the macro mutex while a separate AHK process tries it.
$ownedMutex = New-Object Threading.Mutex($false, $macroName)
$owned = $false
try {
    $owned = $ownedMutex.WaitOne(0)
    if (-not $owned) { throw 'Unique test mutex was unexpectedly occupied.' }
    $busyDriver = @'
RunMutexFixture() {
    global macroName, guiName
    Check(AFKInputLockAcquire(macroName, guiName) = 0, "other process owns macro mutex")
    Check(!NameExists(guiName), "failed contender releases GUI reservation")
    Check(NameExists(macroName), "failed contender preserves owner's object")
}
'@
    Invoke-AFKMutexCheck $busyDriver 3 'independent-process contention'
} finally {
    if ($owned) { $ownedMutex.ReleaseMutex() }
    $ownedMutex.Dispose()
}
Invoke-AFKMutexCheck $goneDriver 2 'contention cleanup'

# GUI receivers reserve the name without owning the mutex; existence alone blocks.
$existingGui = New-Object Threading.Mutex($false, $guiName)
try {
    $guiDriver = @'
RunMutexFixture() {
    global macroName, guiName
    Check(AFKInputLockAcquire(macroName, guiName) = 0, "existing unowned GUI object blocks task")
    Check(!NameExists(macroName), "GUI conflict never creates a macro object")
    Check(NameExists(guiName), "GUI conflict preserves receiver's reservation")
}
'@
    Invoke-AFKMutexCheck $guiDriver 3 'GUI reservation'
} finally { $existingGui.Dispose() }
Invoke-AFKMutexCheck $goneDriver 2 'GUI cleanup'

$recursiveDriver = @'
RunMutexFixture() {
    global macroName, guiName
    outer := DllCall("CreateMutexW", "ptr", 0, "int", 0, "str", macroName, "ptr")
    Check(!!outer, "outer guard creates fixture macro mutex")
    try {
        Check(DllCall("WaitForSingleObject", "ptr", outer, "uint", 0, "uint") = 0, "outer guard acquires on current thread")
        held := AFKInputLockAcquire(macroName, guiName)
        Check(IsObject(held), "AFK recursively acquires same-thread macro mutex")
        AFKInputLockRelease(held)
        Check(!NameExists(guiName), "inner release removes GUI reservation")
        Check(NameExists(macroName), "inner release retains outer guard's handle")
        Check(!!DllCall("ReleaseMutex", "ptr", outer), "inner release leaves outer ownership intact")
        Check(!DllCall("ReleaseMutex", "ptr", outer), "inner acquire/release changes recursion count exactly once")
    } finally {
        DllCall("CloseHandle", "ptr", outer)
    }
    for name in [macroName, guiName]
        Check(!NameExists(name), "recursive fixture leaves no handle leak")
}
'@
Invoke-AFKMutexCheck $recursiveDriver 9 'same-thread guard compatibility'

# Keep the object alive while one AHK owner exits without releasing it, then let
# another AHK process exercise the production WAIT_ABANDONED acceptance branch.
$abandonedKeeper = New-Object Threading.Mutex($false, $macroName)
try {
    $abandonDriver = @'
RunMutexFixture() {
    global macroName
    owner := DllCall("CreateMutexW", "ptr", 0, "int", 0, "str", macroName, "ptr")
    Check(!!owner, "abandoning child opens fixture object")
    Check(DllCall("WaitForSingleObject", "ptr", owner, "uint", 0, "uint") = 0, "abandoning child owns mutex")
    ; The test process exits with ownership. Windows closes its handle and marks
    ; the object abandoned while the PowerShell keeper retains the unique name.
}
'@
    Invoke-AFKMutexCheck $abandonDriver 2 'prepare abandoned ownership'
    $recoverDriver = @'
RunMutexFixture() {
    global macroName, guiName
    held := AFKInputLockAcquire(macroName, guiName)
    Check(IsObject(held), "production accepts ownership abandoned by another process")
    AFKInputLockRelease(held)
    Check(!NameExists(guiName), "abandoned recovery releases GUI reservation")
    Check(NameExists(macroName), "abandoned recovery preserves keeper's handle")
}
'@
    Invoke-AFKMutexCheck $recoverDriver 3 'abandoned ownership recovery'
} finally { $abandonedKeeper.Dispose() }
Invoke-AFKMutexCheck $goneDriver 2 'abandoned cleanup'

Write-Output "PASS AFKInputLock cases=$script:mutexChecks (unique OS mutexes; no game input)"
