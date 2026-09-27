#Requires -Version 5.1
<#
Checks the actual EarnNavLine function against obstacle grids without game input,
screen reads, window activation, or Main.ahk execution.
#>
[CmdletBinding()]
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")

$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnCore.ahk') -Raw -Encoding UTF8
$functions = [regex]::Matches($source, '(?ms)^EarnNavLine\([^\r\n]*\) \{.*?^\}')
if ($functions.Count -ne 1) { throw 'Expected exactly one EarnNavLine function.' }
if (-not (Test-Path -LiteralPath $AhkPath -PathType Leaf)) { throw "AutoHotkey executable not found: $AhkPath" }

$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
; Name, grid width/height, start x/y, end x/y, blocked cells, expected clear.
cases := [
    ["open horizontal", 4, 3, 0, 1, 3, 1, [], true],
    ["open vertical", 3, 4, 1, 0, 1, 3, [], true],
    ["open diagonal", 3, 3, 0, 0, 2, 2, [], true],
    ["blocked destination", 3, 3, 0, 0, 2, 2, [[2, 2]], false],
    ["blocked horizontal", 4, 3, 0, 1, 3, 1, [[2, 1]], false],
    ["blocked vertical", 3, 4, 1, 0, 1, 3, [[1, 2]], false],
    ["corner east", 3, 3, 0, 0, 2, 2, [[1, 0]], false],
    ["corner south", 3, 3, 0, 0, 2, 2, [[0, 1]], false],
    ["corner reversed", 3, 3, 2, 2, 0, 0, [[1, 0]], false],
    ["corner mirrored", 3, 3, 2, 0, 0, 2, [[1, 0]], false],
    ["shallow corner", 4, 3, 0, 0, 3, 1, [[2, 0]], false],
    ["steep corner", 3, 4, 0, 0, 1, 3, [[0, 2]], false],
    ["obstacle outside route", 4, 3, 0, 0, 3, 0, [[1, 2]], true],
    ["same cell", 3, 3, 1, 1, 1, 1, [], true]
]
for c in cases {
    grid := Buffer(c[2] * c[3], 1)
    for point in c[8]
        NumPut("uchar", 0, grid, point[2] * c[2] + point[1])
    actual := EarnNavLine(grid, c[2], c[4], c[5], c[6], c[7])
    if (actual != c[9]) {
        FileAppend("FAIL " c[1] ": expected=" c[9] " actual=" actual "`n", "*", "UTF-8")
        ExitApp(1)
    }
}
FileAppend("PASS EarnNavLine cases=" cases.Length " (no game input)`n", "*", "UTF-8")
ExitApp(0)
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
$previousInputEncoding = [Console]::InputEncoding
[Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
$testProcess = [Diagnostics.Process]::Start($info)
try {
    $testProcess.StandardInput.WriteLine($driver + "`n" + $functions[0].Value)
    $testProcess.StandardInput.Close()
    if (-not $testProcess.WaitForExit(10000)) {
        $testProcess.Kill()
        $testProcess.WaitForExit()
        throw 'EarnNavLine check timed out after 10 seconds.'
    }
    $stdout = $testProcess.StandardOutput.ReadToEnd().Trim()
    $stderr = $testProcess.StandardError.ReadToEnd().Trim()
    if ($testProcess.ExitCode -ne 0 -or $stderr -ne '' -or $stdout -ne 'PASS EarnNavLine cases=14 (no game input)') {
        throw "EarnNavLine check failed (exit=$($testProcess.ExitCode))`nstdout: $stdout`nstderr: $stderr"
    }
    Write-Output $stdout
} finally {
    if (-not $testProcess.HasExited) {
        $testProcess.Kill()
        $testProcess.WaitForExit()
    }
    $testProcess.Dispose()
    [Console]::InputEncoding = $previousInputEncoding
}
