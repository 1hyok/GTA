#Requires -Version 5.1
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$fixture = Join-Path $env:TEMP ('gta capture & path ' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path (Join-Path $fixture 'Features\Earn'), (Join-Path $fixture 'Core'), (Join-Path $fixture 'tools\earn-test') -Force
$utf8 = New-Object System.Text.UTF8Encoding($false)
$resultFile = Join-Path $fixture 'arguments.json'
$previousResult = $env:GTA_CAPTURE_TEST_RESULT
$env:GTA_CAPTURE_TEST_RESULT = $resultFile

function Assert-Arguments($name, $x, $y, $w, $h, $scale) {
    if (!(Test-Path -LiteralPath $resultFile)) { throw 'Capture command did not reach the fixture script' }
    $actual = Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json
    if ($actual.Name -cne $name -or $actual.X -ne $x -or $actual.Y -ne $y -or $actual.W -ne $w -or $actual.H -ne $h -or $actual.Scale -ne $scale) {
        throw ('Unexpected capture arguments: ' + ($actual | ConvertTo-Json -Compress))
    }
    Remove-Item -LiteralPath $resultFile
}

try {
    $captureSource = Join-Path $repo 'Core\ScreenCapture.ps1'
    $tokens = $null; $parseErrors = $null
    $captureAst = [Management.Automation.Language.Parser]::ParseFile($captureSource, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
    # Use the production parameters but replace screen capture with an argument recorder.
    $spy = $captureAst.ParamBlock.Extent.Text + @'

@{ Name=$Name; X=$X; Y=$Y; W=$W; H=$H; Scale=$Scale } | ConvertTo-Json | Set-Content -LiteralPath $env:GTA_CAPTURE_TEST_RESULT -Encoding UTF8
'@
    [IO.File]::WriteAllText((Join-Path $fixture 'Core\ScreenCapture.ps1'), $spy, $utf8)
    Copy-Item -LiteralPath (Join-Path $repo 'tools\earn-test\capscreen.ps1') -Destination (Join-Path $fixture 'tools\earn-test\capscreen.ps1')
    & (Join-Path $fixture 'tools\earn-test\capscreen.ps1') -Name 'manual capture & test' -X -40 -Y -25 -W 120 -H 80 -Scale 0.25
    Assert-Arguments 'manual capture & test' -40 -25 120 80 0.25
    & (Join-Path $fixture 'tools\earn-test\capscreen.ps1')
    Assert-Arguments 'cap' 1920 0 2560 1600 0.5
    'PASS manual wrapper forwards explicit arguments and production defaults'

    $source = Get-Content -LiteralPath (Join-Path $repo 'Features\Earn\EarnCore.ahk') -Raw -Encoding UTF8
    $match = [regex]::Match($source, '(?ms)^EarnSnapMinimap\(tag\) \{.*?^\}')
    if (!$match.Success) { throw 'Production EarnSnapMinimap function missing' }
    # Only window discovery is replaced. RunWait and A_LineFile path resolution execute unchanged.
    $function = $match.Value.Replace('IsGTAActive()', 'CaptureTestActive()').Replace('WinGetClientPos(', 'CaptureTestClientPos(')
    [IO.File]::WriteAllText((Join-Path $fixture 'Features\Earn\EarnCore.ahk'), $function, $utf8)
    $harness = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#Include __INCLUDE__
global EARN_MINIMAP := [40, 50, 140, 150]
CaptureTestActive() => 1
CaptureTestClientPos(&x, &y, &w, &h, *) {
    x := -2560, y := -80, w := 1920, h := 1080
}
EarnSnapMinimap("probe name & literal")
ExitApp()
'@
    foreach ($entry in @('Main.ahk', 'tools\earn-test\earntest.ahk')) {
        $include = if ($entry -eq 'Main.ahk') { '%A_ScriptDir%\Features\Earn\EarnCore.ahk' } else { '%A_ScriptDir%\..\..\Features\Earn\EarnCore.ahk' }
        $entryPath = Join-Path $fixture $entry
        [IO.File]::WriteAllText($entryPath, $harness.Replace('__INCLUDE__', $include), $utf8)
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $AhkPath
        $startInfo.Arguments = '/ErrorStdOut "' + $entryPath + '"'
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        $null = $process.Start()
        if (!$process.WaitForExit(15000)) { $process.Kill(); throw "Capture path check timed out: $entry" }
        $processOutput = $process.StandardOutput.ReadToEnd()
        $processError = $process.StandardError.ReadToEnd()
        if ($process.ExitCode -ne 0) { throw "AHK fixture failed ($($process.ExitCode)): $processOutput $processError" }
        $process.Dispose()
        Assert-Arguments 'gta-earn-probe name & literal' -2520 -30 100 100 1
        "PASS runtime capture path from $entry with spaces and ampersand in the checkout path"
    }

    # Execute only directory setup from the real script, before its first capture-related command.
    $setup = @($captureAst.EndBlock.Statements | Select-Object -First 2)
    if ($setup.Count -ne 2 -or $setup[0].Extent.Text -notmatch '^\$outputDirectory\s*=' -or $setup[1].Extent.Text -notmatch '^\$null\s*=\s*New-Item ') {
        throw 'Capture output setup changed; update the no-capture setup check'
    }
    $previousTemp = $env:TEMP
    try {
        $env:TEMP = Join-Path $fixture 'fresh temp'
        $null = New-Item -ItemType Directory -Path $env:TEMP
        foreach ($statement in $setup) { Invoke-Expression $statement.Extent.Text }
        if (!(Test-Path -LiteralPath (Join-Path $env:TEMP 'claude') -PathType Container)) { throw 'Missing capture output directory' }
    } finally { $env:TEMP = $previousTemp }
    'PASS capture output directory is created on a fresh machine without taking a screenshot'
} finally {
    $env:GTA_CAPTURE_TEST_RESULT = $previousResult
    # Keep failure evidence in TEMP; CI also records this test output.
    "Capture path fixtures: $fixture"
}
