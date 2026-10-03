#Requires -Version 5.1
<#
Reproduce the observed full-stock selected-person feet. Input is the saved
876x264 goods grid at client (728,548), or an original 1920x1080 screenshot.
The crop is (1266,690,15,17) in the 2026-10-03 Organic Produce selection.
No screen capture, window activation or game input.
#>
[CmdletBinding()]
param(
    [string]$SourcePath = '',
    [string]$OutputDir = ''
)
$ErrorActionPreference = 'Stop'
if (-not $SourcePath) { $SourcePath = Join-Path $PSScriptRoot 'test-earnwarehouse-template-fixtures\full-organic.png' }
if (-not $OutputDir) { $OutputDir = Join-Path $PSScriptRoot '..\..\Images\Earn\1920x1080' }
Add-Type -AssemblyName System.Drawing
$source = [Drawing.Bitmap]::FromFile([IO.Path]::GetFullPath($SourcePath))
$crop = $null
try {
    if ($source.Width -eq 876 -and $source.Height -eq 264) {
        $x = 538; $y = 142
    } elseif ($source.Width -eq 1920 -and $source.Height -eq 1080) {
        $x = 1266; $y = 690
    } else {
        throw 'Expected the observed 876x264 goods grid or a 1920x1080 screenshot.'
    }
    $crop = $source.Clone((New-Object Drawing.Rectangle $x, $y, 15, 17), [Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $output = [IO.Path]::GetFullPath($OutputDir)
    $null = [IO.Directory]::CreateDirectory($output)
    $path = Join-Path $output 'warehouse_person_full_foot.png'
    $crop.Save($path, [Drawing.Imaging.ImageFormat]::Png)
    Write-Output "Generated $path"
} finally {
    if ($null -ne $crop) { $crop.Dispose() }
    $source.Dispose()
}
