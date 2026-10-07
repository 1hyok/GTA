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
$workingTreeProperty = $verification.PSObject.Properties['workingTree']
if ($null -eq $workingTreeProperty -or $workingTreeProperty.Value -isnot [Array]) {
    throw 'Verification results do not record the working-tree state. Run run-checks.ps1 again.'
}
$workingTreeDirty = $workingTreeProperty.Value.Count -gt 0
$verificationHash = (Get-FileHash -LiteralPath $CheckResults -Algorithm SHA256).Hash
$revision = (& git -C $repositoryRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Could not read the Git revision.' }
if ($verification.verificationScope -ne 'full' -or -not $verification.passed -or $verification.repositoryRoot -ne $repositoryRoot -or $verification.revision -ne $revision) {
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
$suffix = if ($workingTreeDirty) { '-dirty' } else { '' }
$zipPath = Join-Path $outputPath ('gta-macro-' + $revision.Substring(0, 12) + $suffix + '.zip')
$pendingZip = Join-Path $outputPath ((Split-Path -Leaf $stage) + '.zip.partial')
$checksumPath = $zipPath + '.sha256'
$pendingChecksum = Join-Path $outputPath ((Split-Path -Leaf $stage) + '.sha256.partial')
$publishedZip = $false
$publishedChecksum = $false
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
    $manifestJson = [ordered]@{
        revision = $revision
        workingTreeDirty = $workingTreeDirty
        verificationSha256 = $verificationHash
        verifiedUtc = $verification.finishedUtc
        autoHotkeyVersion = $verification.autoHotkeyVersion
        files = $hashes
    } | ConvertTo-Json -Depth 5
    $manifestBytes = [Text.Encoding]::UTF8.GetBytes($manifestJson)
    [IO.File]::WriteAllBytes((Join-Path $stage 'manifest.json'), $manifestBytes)
    $expectedHashes = @{}
    foreach ($item in $hashes) { $expectedHashes[$item.path] = $item.sha256 }
    $manifestStream = [IO.MemoryStream]::new($manifestBytes, $false)
    try {
        $expectedHashes['manifest.json'] = (Get-FileHash -InputStream $manifestStream -Algorithm SHA256).Hash
    } finally { $manifestStream.Dispose() }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($stage, $pendingZip)
    $zip = [IO.Compression.ZipFile]::OpenRead($pendingZip)
    try {
        $expected = @($hashes.path) + 'manifest.json'
        $actual = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        if (@(Compare-Object $expected $actual).Count) { throw 'ZIP content differs from the allowlist.' }
        if ('Config.ini' -in $actual) { throw 'ZIP must never contain the live Config.ini.' }
        foreach ($entry in $zip.Entries) {
            $entryName = $entry.FullName.Replace('\', '/')
            $stream = $entry.Open()
            try { $entryHash = (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash }
            finally { $stream.Dispose() }
            if ($entryHash -cne $expectedHashes[$entryName]) {
                throw "ZIP content hash differs from verification: $entryName"
            }
        }
    } finally { $zip.Dispose() }
    $zipHash = (Get-FileHash -LiteralPath $pendingZip -Algorithm SHA256).Hash
    ($zipHash + '  ' + [IO.Path]::GetFileName($zipPath)) | Set-Content -LiteralPath $pendingChecksum -Encoding ASCII
    # Only validated artifacts receive the final names. Do not overwrite another invocation's files.
    [IO.File]::Move($pendingZip, $zipPath)
    $publishedZip = $true
    [IO.File]::Move($pendingChecksum, $checksumPath)
    $publishedChecksum = $true
    Write-Output $zipPath
    Write-Output ("SHA256 $zipHash; files=$($hashes.Count + 1)")
} catch {
    # Roll back a partially published pair if the second rename fails.
    if ($publishedChecksum) { Remove-Item -LiteralPath $checksumPath -Force }
    if ($publishedZip) { Remove-Item -LiteralPath $zipPath -Force }
    throw
} finally {
    foreach ($temporaryFile in @($pendingZip, $pendingChecksum)) {
        if (Test-Path -LiteralPath $temporaryFile -PathType Leaf) { Remove-Item -LiteralPath $temporaryFile -Force }
    }
    # Only remove this invocation's resolved staging directory under its output directory.
    $resolvedStage = [IO.Path]::GetFullPath($stage)
    $resolvedOutput = $outputPath.TrimEnd('\') + '\'
    if (-not $resolvedStage.StartsWith($resolvedOutput, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing to remove staging directory outside the package output directory.'
    }
    Remove-Item -LiteralPath $resolvedStage -Recurse -Force
}
