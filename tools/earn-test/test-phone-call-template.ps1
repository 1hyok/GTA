#Requires -Version 5.1
<# Actual desktop and Steam-recording phone crops. No windows or game input. #>
[CmdletBinding()]
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
# Reuse the per-channel, magenta-transparent ImageSearch comparator.
& (Join-Path $PSScriptRoot 'test-nightclub-templates.ps1') | Out-Null
$template = [Drawing.Bitmap]::FromFile((Join-Path $root 'Images\Earn\1920x1080\phone_call_end.png'))
$scenarios = @()
try {
    foreach ($sample in @(@('live-call-end', $true), @('recorded-call-end', $true), @('no-phone', $false))) {
        $source = [Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot "phone-call-fixtures\$($sample[0]).png"))
        try {
            $x = 0; $y = 0
            $area = New-Object Drawing.Rectangle 0, 0, $source.Width, $source.Height
            $minimum = [EarnNightclubTemplateTest]::MinimumVariation($source, $template, $area, [ref]$x, [ref]$y)
            Write-Output "$($sample[0]): minimum=$minimum at $x,$y"
            $scenarios += '["' + $sample[0] + '",' + $minimum + ',' + ([int]$sample[1]) + ']'
        } finally { $source.Dispose() }
    }
} finally { $template.Dispose() }
$core = Get-Content -LiteralPath (Join-Path $root 'Features\Earn\EarnCore.ahk') -Raw -Encoding UTF8
$body = [regex]::Match($core, '(?ms)^EarnSeen\([^\r\n]*\) \{.*?^\}').Value
if (-not $body) { throw 'EarnSeen function not found' }
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global requiredVariation := 0
OnError((err,*) => (FileAppend("FAIL " err.Message "`n", "**"), ExitApp(1)))
for sample in FIXTURE_CASES {
    requiredVariation := sample[2]
    if (EarnSeen("phone_call_end", [0.9,0.92,0.99,0.98]) != sample[3])
        throw Error(sample[1] " call detection mismatch, required variation=" requiredVariation)
}
requiredVariation := 55
if (EarnSeen("afk_phone_frame", [0.83,0.58,0.98,0.72]))
    throw Error("Unrelated phone-frame tolerance must remain unchanged")
FileAppend("PASS phone-call fixtures and unrelated tolerance`n", "*")
ExitApp(0)
TemplateSeen(folder,name,area,&x,&y,variation) => requiredVariation <= variation
TemplateAt(*) => false
'@
$driver = $driver.Replace('FIXTURE_CASES', '[' + ($scenarios -join ',') + ']')
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
$process = [Diagnostics.Process]::Start($info)
try {
    $process.StandardInput.WriteLine($driver + "`n" + $body)
    $process.StandardInput.Close()
    if (-not $process.WaitForExit(10000)) { $process.Kill(); throw 'Phone template test timed out' }
    $stdout = $process.StandardOutput.ReadToEnd().Trim()
    $stderr = $process.StandardError.ReadToEnd().Trim()
    if ($process.ExitCode -ne 0 -or $stderr -or $stdout -ne 'PASS phone-call fixtures and unrelated tolerance') {
        throw "Phone template failed: exit=$($process.ExitCode) $stdout $stderr"
    }
    Write-Output $stdout
} finally { $process.Dispose(); [Console]::InputEncoding = $previousEncoding }
