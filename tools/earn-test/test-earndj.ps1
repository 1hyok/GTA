#Requires -Version 5.1
<#
Runs the production EarnDJNextSec decision. No Main.ahk, game input or state file.
#>
[CmdletBinding()]
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$src = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnTasks.ahk') -Raw -Encoding UTF8
$m = [regex]::Matches($src, '(?ms)^EarnDJNextSec\(.*?^\}')
if ($m.Count -ne 1) { throw 'Expected exactly one EarnDJNextSec' }
$driver = @"
#Requires AutoHotkey v2.0
#NoTrayIcon
#Warn All, StdOut
n := 0, D := 2880, b := 0
Check(EarnDJNextSec(-1, 0, 0, 100, 1000, &b) = 0 && b = 0, "unknown start uses default interval")
Check(EarnDJNextSec(100, 10000, 0, 95, 10300, &b) = 10000 + D + 180 - 10300 && b = 10000, "drop after a short gap sets the boundary")
Check(EarnDJNextSec(95, 10000 + 180, 10000, 91, 10000 + D + 180, &b) = D && b = 10000 + D, "predicted drop advances one day")
Check(EarnDJNextSec(100, 10000 + D + 180, 10000 + D, 95, 10000 + 2*D + 180, &b) = D && b = 10000 + 2*D, "drop after rebook advances one day")
Check(EarnDJNextSec(95, 10000 + 180, 10000, 95, 10000 + D + 180, &b) = 120 && b = 10000, "late drop polls every two minutes")
Check(EarnDJNextSec(95, 10000 + D + 180, 10000, 91, 10000 + D + 300, &b) = D + 180 - 120 && b = 10000 + D + 180, "poll narrows the boundary")
Check(EarnDJNextSec(95, 10000 + D + 1000, 10000, 95, 10000 + D + 1200, &b) = 0 && b = 0, "stale prediction falls back")
Check(EarnDJNextSec(91, 10000 + 180, 10000, 100, 10000 + 400, &b) = D - 220 && b = 10000, "rise keeps the boundary")
Check(EarnDJNextSec(95, 10000 + D + 100, 10000, 91, 10000 + D + 1500, &b) = 0 && b = 0, "drop outside the predicted window drops the boundary")
FileAppend("PASS EarnDJ cases=" n, "*")
ExitApp(0)
Check(ok, name) {
    global n
    if (!ok)
        throw Error("FAIL " name)
    n += 1
}
$($m[0].Value)
"@
$path = Join-Path ([IO.Path]::GetTempPath()) ('gta-earndj-' + [Guid]::NewGuid().ToString('N') + '.ahk')
[IO.File]::WriteAllText($path, $driver, (New-Object Text.UTF8Encoding($true)))
try {
    $out = (& $AhkPath /ErrorStdOut $path 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $out -ne 'PASS EarnDJ cases=9') { throw "EarnDJ failed (exit=$LASTEXITCODE): $out" }
    Write-Output $out
} finally { [IO.File]::Delete($path) }
