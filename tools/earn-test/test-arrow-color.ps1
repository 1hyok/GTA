#Requires -Version 5.1
<#
Runs the production EarnArrowColorOf on saved minimap arrow crops (29x31 at 150,990).
CEO crops come from the 2026-10-04 11:16 recording while registered (yellow organization arrow);
plain crops are the same spot before registration and after retire (white arrow under the white MCT laptop icon).
No Main.ahk, game input, screen capture or window activation.
#>
[CmdletBinding()]
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$core = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnCore.ahk') -Raw -Encoding UTF8
$match = [regex]::Matches($core, '(?ms)^EarnArrowColorOf\([^\r\n]*\) \{.*?^\}')
if ($match.Count -ne 1) { throw 'Expected exactly one EarnArrowColorOf' }
if (-not (Test-Path -LiteralPath $AhkPath -PathType Leaf)) { throw "AutoHotkey executable not found: $AhkPath" }
$work = Join-Path ([IO.Path]::GetTempPath()) ('gta-arrow-' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($work)
try {
    $cases = @(
        @('arrow-plain-before', 0), @('arrow-ceo-1', 1), @('arrow-ceo-2', 1), @('arrow-ceo-3', 1),
        @('arrow-plain-after-1', 0), @('arrow-plain-after-2', 0)
    )
    $lines = @()
    foreach ($case in $cases) {
        $bitmap = [Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot ('mct-template-fixtures\' + $case[0] + '.png')))
        try {
            if ($bitmap.Width -ne 29 -or $bitmap.Height -ne 31) { throw "Invalid fixture size: $($case[0])" }
            $bytes = New-Object byte[] (29 * 31 * 4)
            for ($y = 0; $y -lt 31; $y++) {
                for ($x = 0; $x -lt 29; $x++) {
                    $p = $bitmap.GetPixel($x, $y); $o = ($y * 29 + $x) * 4
                    $bytes[$o] = $p.B; $bytes[$o + 1] = $p.G; $bytes[$o + 2] = $p.R; $bytes[$o + 3] = 255
                }
            }
        } finally { $bitmap.Dispose() }
        $bin = Join-Path $work ($case[0] + '.bin')
        [IO.File]::WriteAllBytes($bin, $bytes)
        $lines += '["' + $bin + '", ' + $case[1] + ']'
    }
    # 미니맵이 안 보이는(검은) 화면은 어느 쪽으로도 판정하지 않는다.
    $black = Join-Path $work 'black.bin'
    [IO.File]::WriteAllBytes($black, (New-Object byte[] (29 * 31 * 4)))
    $lines += '["' + $black + '", -1]'
    $driver = @"
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
n := 0
for c in [$($lines -join ', ')] {
    got := EarnArrowColorOf(FileRead(c[1], "RAW"), 29, 31)
    if (got != c[2]) {
        FileAppend("FAIL arrow " c[1] " expected=" c[2] " got=" got "``n", "*")
        ExitApp(1)
    }
    n += 1
}
FileAppend("PASS ArrowColor cases=" n "``n", "*")
ExitApp(0)
"@ + "`n" + $match[0].Value
    $script = Join-Path $work 'driver.ahk'
    [IO.File]::WriteAllText($script, $driver, (New-Object Text.UTF8Encoding $true))
    $out = & $AhkPath /ErrorStdOut $script 2>&1 | Out-String
    Write-Output $out.Trim()
    if ($LASTEXITCODE -ne 0 -or $out -notmatch 'PASS ArrowColor cases=7') { throw "ArrowColor failed (exit=$LASTEXITCODE)`n$out" }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
