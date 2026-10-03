#Requires -Version 5.1
<#
Runs EarnScreen's actual money/text/selection functions with screen and key APIs
stubbed. No desktop capture, keyboard input, foreground changes or game process.
#>
[CmdletBinding()]
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")

$ErrorActionPreference = 'Stop'
$sourceFile = Join-Path $PSScriptRoot '..\..\Features\Earn\EarnScreen.ahk'
$source = Get-Content -LiteralPath $sourceFile -Raw -Encoding UTF8
$definitions = ''
foreach ($functionName in @('EarnReadDollars', 'EarnFindText', 'EarnScreenText', 'EarnSelectText', 'EarnMenuStepKey')) {
    $pattern = '(?ms)^' + [regex]::Escape($functionName) + '\([^\r\n]*\) \{.*?^\}'
    $matches = [regex]::Matches($source, $pattern)
    if ($matches.Count -ne 1) { throw "Expected exactly one $functionName definition." }
    $definitions += $matches[0].Value + "`n"
}
foreach ($functionName in @('EarnReadScreen', 'EarnMenuRowSelected')) {
    $pattern = '(?ms)^' + [regex]::Escape($functionName) + '\([^\r\n]*\) \{.*?^\}'
    $matches = [regex]::Matches($source, $pattern)
    if ($matches.Count -ne 1) { throw "Expected exactly one $functionName definition." }
    # Preserve the real function body, and distinguish it from selection mocks.
    $definitions += [regex]::Replace($matches[0].Value, '^' + $functionName + '\(', $functionName + 'NativeForTest(') + "`n"
}

$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global checks := 0, frames := [], reads := 0, presses := 0, allowPress := true
try {
    cases := [
        ["$0", 0], ["$15,000", 15000], ["Nightclub $250,000", 250000],
        ["Are you sure for $ 75000?", 75000], ["$1,234,567", 1234567],
        ["$75000`tto buy", 75000], ["No earnings to claim.", -1],
        ["$75,OOO", -1], ["$75,000,0000", -1], ["$75 000", -1],
        ["$75,000.00", -1], ["$75000O", -1], ["$75,000 $15,000", -1],
        ["$250,000 or $250,000", -1], ["$75,000`n$15,000", -1],
        ["$7.5e4", -1], ["$1,000,00", -1], ["$7,5000", -1],
        ["$1000000000000000000000", -1], ["$-75000", -1],
        ["$+75000", -1], ["$75`n000", -1], ["$000,075", -1],
        ["$75000+15000", -1], ["$75000-15000", -1]
    ]
    for item in cases
        Check(EarnReadDollars(item[1]) = item[2], "money: " item[1])

    Check(!EarnReadScreenNativeForTest([25,15,450,850]), "lost GTA handle refuses capture")
    Check(!EarnReadScreenNativeForTest([25,15,0,850]), "zero width refuses capture")
    Check(!EarnReadScreenNativeForTest([-1,15,450,850]), "negative crop refuses capture")
    Check(!EarnReadScreenNativeForTest([25,15,1920,850]), "outside crop refuses capture")
    Check(!EarnMenuRowSelectedNativeForTest(false), "invalid row refuses selection read")
    Check(!EarnMenuRowSelectedNativeForTest(MakeRow("Nightclub", true)), "lost GTA handle refuses selection read")

    nightclubTestRow := MakeRow("Nightclub $250,000", true)
    other := MakeRow("Arcade $100,000", false)
    Check(!EarnFindText(false, "Nightclub"), "false OCR has no match")
    Check(!EarnFindText([], "Nightclub"), "empty OCR has no match")
    Check(EarnFindText([other, nightclubTestRow], "i)^nightclub") = nightclubTestRow, "find returns matching row")
    Check(!EarnFindText([other], "^Nightclub"), "other business is not nightclub")
    Check(EarnScreenText(false) = "", "false OCR has no text")
    Check(EarnScreenText([other, nightclubTestRow]) = "Arcade $100,000`nNightclub $250,000`n", "screen text retains line boundaries")

    heading := MakeRow("THE VINEWOOD CLUB APP", false)
    target := MakeRow("Claim Business Earnings", false)
    selected := MakeRow("Claim Business Earnings", true)
    Setup([false])
    Check(!SelectClaim() && presses = 0 && reads = 1, "failed OCR sends no key")
    Setup([[]])
    Check(!SelectClaim() && presses = 0, "empty OCR sends no key")
    Setup([[MakeRow("Wrong menu", false), selected]])
    Check(!SelectClaim() && presses = 0, "target without expected heading sends no key")
    Setup([[heading, selected]])
    Check(SelectClaim() = selected && presses = 0 && reads = 1, "already selected does not move")
    Setup([[heading, target], [heading, selected]])
    Check(SelectClaim() = selected && presses = 1 && reads = 2, "one Down requires new selected screen")
    Setup([[heading, target], false])
    Check(!SelectClaim() && presses = 1 && reads = 2, "OCR loss stops after first movement")
    Setup([[heading, target], [MakeRow("Wrong menu", false), selected]])
    Check(!SelectClaim() && presses = 1, "heading loss stops selection")
    Setup([[heading, target]])
    allowPress := false
    Check(!SelectClaim() && presses = 1 && reads = 1, "key rejection stops selection")
    Setup([[heading, target], [heading, target], [heading, target]])
    Check(!SelectClaim(2) && presses = 2 && reads = 3, "maxPress bounds navigation")
    Setup([[heading, target]])
    Check(!SelectClaim(0) && presses = 0 && reads = 1, "zero movement budget is read-only")
    Setup([[heading, selected]])
    Check(SelectClaim(0) = selected && presses = 0, "zero budget still recognizes selection")
    FileAppend("PASS EarnScreen cases=" checks " (no game input)`n", "*")
    ExitApp(0)
} catch as testFailure {
    FileAppend("FAIL EarnScreen: " testFailure.Message "`n", "**")
    ExitApp(1)
}

Check(condition, description) {
    global checks
    if (!condition)
        throw Error(description)
    checks++
}
MakeRow(text, selected) {
    return {x: 150, y: 180, w: 200, h: 20, text: text, selected: selected}
}
Setup(nextFrames) {
    global frames, reads, presses, allowPress
    frames := nextFrames, reads := 0, presses := 0, allowPress := true
}
SelectClaim(maxPress := 12) {
    return EarnSelectText("^Claim Business Earnings$", "^THE VINEWOOD CLUB APP$", maxPress)
}
EarnReadScreen(area) {
    global frames, reads
    reads++
    if (area[1] != 25 || area[2] != 15 || area[3] != 450 || area[4] != 800)
        throw Error("Unexpected selection OCR area")
    return reads <= frames.Length ? frames[reads] : false
}
EarnMenuRowSelected(row) {
    return row.selected
}
EarnPress(key) {
    global presses, allowPress
    if (key != "Down" && key != "Up")
        throw Error("Selection attempted an unsafe key: " key)
    presses++
    return allowPress
}
EarnLog(*) => true
EarnAborted() {
    return false
}
IsGTAActive() {
    return 0
}
EarnFail(reason) {
    return false
}
'@

$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $AhkPath
$testFile = Join-Path ([IO.Path]::GetTempPath()) ('gta-earnscreen-test-' + [Guid]::NewGuid().ToString('N') + '.ahk')
[IO.File]::WriteAllText($testFile, $driver + "`n" + $definitions, (New-Object Text.UTF8Encoding($true)))
$info.Arguments = '/ErrorStdOut /CP65001 "' + $testFile + '"'
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
$info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
$testProcess = [Diagnostics.Process]::Start($info)
try {
    if (-not $testProcess.WaitForExit(10000)) {
        $testProcess.Kill()
        $testProcess.WaitForExit()
        throw 'EarnScreen test timed out.'
    }
    $stdout = $testProcess.StandardOutput.ReadToEnd().Trim()
    $stderr = $testProcess.StandardError.ReadToEnd().Trim()
    if ($testProcess.ExitCode -ne 0 -or $stderr -ne '' -or $stdout -ne 'PASS EarnScreen cases=48 (no game input)') {
        throw "EarnScreen test failed (exit=$($testProcess.ExitCode))`nstdout: $stdout`nstderr: $stderr"
    }
    Write-Output $stdout
}
finally {
    if (-not $testProcess.HasExited) { $testProcess.Kill(); $testProcess.WaitForExit() }
    $testProcess.Dispose()
    if ([IO.File]::Exists($testFile)) { [IO.File]::Delete($testFile) }
}
