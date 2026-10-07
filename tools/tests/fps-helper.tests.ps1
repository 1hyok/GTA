#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$helperPath = Join-Path $repositoryRoot 'tools\fps-helper\gta-fps-helper.ps1'
$source = [IO.File]::ReadAllText($helperPath)

$tokens = $null
$parseErrors = $null
$null = [Management.Automation.Language.Parser]::ParseFile($helperPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) {
    throw ('fps helper parse errors: ' + (($parseErrors | ForEach-Object Message) -join '; '))
}

$rtssMissing = $source.IndexOf("if (-not (Get-Process RTSS -ErrorAction SilentlyContinue))", [StringComparison]::Ordinal)
$gtaRunning = $source.IndexOf("if (Get-Process GTA5_Enhanced -ErrorAction SilentlyContinue)", [StringComparison]::Ordinal)
$deferLog = $source.IndexOf('RTSS start deferred until GTA exits', [StringComparison]::Ordinal)
$continue = $source.IndexOf('continue', $gtaRunning, [StringComparison]::Ordinal)
$startRtss = $source.IndexOf('Start-Process "$rtssDir\RTSS.exe"', [StringComparison]::Ordinal)

if ($rtssMissing -lt 0) { throw 'RTSS absence guard is missing.' }
if ($gtaRunning -le $rtssMissing) { throw 'GTA running guard must be inside the RTSS absence path.' }
if ($deferLog -le $gtaRunning) { throw 'Deferred RTSS start must leave an operator-visible log.' }
if ($continue -le $gtaRunning -or $continue -ge $startRtss) {
    throw 'The GTA running path must skip RTSS startup.'
}
if ($startRtss -le $gtaRunning) { throw 'RTSS may only start after the GTA running guard.' }

Write-Output 'PASS fps helper defers RTSS startup while GTA is running (source-only; no process changes)'
