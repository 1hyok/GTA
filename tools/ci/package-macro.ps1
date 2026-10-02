#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CheckResults,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $PSScriptRoot 'common.ps1')
$verification = Get-Content -LiteralPath $CheckResults -Raw -Encoding UTF8 | ConvertFrom-Json
$revision = (& git -C $repositoryRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Could not read the Git revision.' }
if (-not $verification.passed -or $verification.repositoryRoot -ne $repositoryRoot -or $verification.revision -ne $revision) {
    throw 'Run run-checks.ps1 successfully on this checkout and revision before packaging.'
}
$hashes = Get-MacroHashes $repositoryRoot
if (($hashes | ConvertTo-Json -Compress) -cne ($verification.sources | ConvertTo-Json -Compress)) {
    throw 'Macro source files changed since verification. Run run-checks.ps1 again.'
}
$outputPath = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $outputPath) {
    if (@(Get-ChildItem -LiteralPath $outputPath -Force).Count) { throw 'Choose a new or empty package directory.' }
} else {
    $null = New-Item -ItemType Directory -Path $outputPath
}
$stage = Join-Path $outputPath ('stage-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $stage
$zipPath = Join-Path $outputPath ('gta-macro-' + $revision.Substring(0, 12) + '.zip')
try {
    foreach ($item in (Get-MacroInputs $repositoryRoot)) {
        $target = Join-Path $stage $item.path
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
        Copy-Item -LiteralPath $item.source -Destination $target
    }
    # Check staged content too, so edits during copying cannot produce an unverified ZIP.
    foreach ($item in $hashes) {
        if ((Get-FileHash -LiteralPath (Join-Path $stage $item.path) -Algorithm SHA256).Hash -cne $item.sha256) {
            throw "Package source changed while copying: $($item.path)"
        }
    }
    [ordered]@{
        revision = $revision
        verifiedUtc = $verification.finishedUtc
        autoHotkeyVersion = $verification.autoHotkeyVersion
        files = $hashes
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stage 'manifest.json') -Encoding UTF8
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPath)
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $expected = @($hashes.path) + 'manifest.json'
        $actual = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        if (@(Compare-Object $expected $actual).Count) { throw 'ZIP content differs from the allowlist.' }
        if ('Config.ini' -in $actual) { throw 'ZIP must never contain the live Config.ini.' }
    } finally { $zip.Dispose() }
    $zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    ($zipHash + '  ' + [IO.Path]::GetFileName($zipPath)) | Set-Content -LiteralPath ($zipPath + '.sha256') -Encoding ASCII
    Write-Output $zipPath
    Write-Output ("SHA256 $zipHash; files=$($hashes.Count + 1)")
} finally {
    # Only remove this invocation's resolved staging directory under its output directory.
    $resolvedStage = [IO.Path]::GetFullPath($stage)
    $resolvedOutput = $outputPath.TrimEnd('\') + '\'
    if (-not $resolvedStage.StartsWith($resolvedOutput, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing to remove staging directory outside the package output directory.'
    }
    Remove-Item -LiteralPath $resolvedStage -Recurse -Force
}
