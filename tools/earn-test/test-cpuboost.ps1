#Requires -Version 5.1
<#
Runs the production CpuBoostWanted decision. No Main.ahk, powercfg or game input.
#>
[CmdletBinding()]
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$src = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Features\CpuBoost.ahk') -Raw -Encoding UTF8
$m = [regex]::Matches($src, '(?m)^CpuBoostWanted\([^\r\n]*')
if ($m.Count -ne 1) { throw 'Expected exactly one CpuBoostWanted' }
$driver = @"
#Requires AutoHotkey v2.0
#NoTrayIcon
#Warn All, StdOut
n := 0
Check(CpuBoostWanted(false, 999999, 300), "earner off keeps boost")
Check(CpuBoostWanted(true, 299999, 300), "recent input keeps boost")
Check(!CpuBoostWanted(true, 300000, 300), "idle earner turns boost off")
Check(CpuBoostWanted(true, 999999, 0), "zero disables the feature")
FileAppend("PASS CpuBoost cases=" n, "*")
ExitApp(0)
Check(ok, name) {
    global n
    if (!ok)
        throw Error("FAIL " name)
    n += 1
}
$($m[0].Value)
"@
$path = Join-Path ([IO.Path]::GetTempPath()) ('gta-cpuboost-' + [Guid]::NewGuid().ToString('N') + '.ahk')
[IO.File]::WriteAllText($path, $driver, (New-Object Text.UTF8Encoding($true)))
try {
    $out = (& $AhkPath /ErrorStdOut $path 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $out -ne 'PASS CpuBoost cases=4') { throw "CpuBoost failed (exit=$LASTEXITCODE): $out" }
    Write-Output $out
} finally { [IO.File]::Delete($path) }
