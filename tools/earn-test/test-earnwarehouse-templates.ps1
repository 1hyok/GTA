#Requires -Version 5.1
<#
Read saved pixels only. The fixtures are the 876x264 goods grid cropped at
(728,548), so account names, staff portraits and desktop notifications are absent.
Normal samples select Cargo, Sporting, Printing and Cash. Full Organic 80/80
uses the observed gray person with an exclamation mark, while the unselected
South American 10/10 tile contains only an exclamation circle. The immediate
and delayed full samples were pixel-identical, so only one fixture is retained.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'compare-png-pixels.ps1')
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$assets = Join-Path $root 'Images\Earn\1920x1080'
$fixtures = Join-Path $PSScriptRoot 'test-earnwarehouse-template-fixtures'
$production = Get-Content (Join-Path $root 'Features\Earn\EarnWarehouse.ahk') -Raw -Encoding UTF8
$cases = 0
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @'
using System;
using System.Drawing;
public static class EarnWarehouseTemplatePixels {
    // ImageSearch RGB channel comparison, including Trans0xFF00FF.
    public static int MinimumVariation(Bitmap source, Bitmap template, Rectangle area) {
        int best = 256;
        for (int y=area.Top; y+template.Height<=area.Bottom; y++) {
            for (int x=area.Left; x+template.Width<=area.Right; x++) {
                int worst = 0;
                for (int ty=0; ty<template.Height && worst<best; ty++) {
                    for (int tx=0; tx<template.Width; tx++) {
                        Color expected=template.GetPixel(tx,ty);
                        if (expected.R==255 && expected.G==0 && expected.B==255) continue;
                        Color actual=source.GetPixel(x+tx,y+ty);
                        worst=Math.Max(worst,Math.Max(Math.Abs(actual.R-expected.R),
                            Math.Max(Math.Abs(actual.G-expected.G),Math.Abs(actual.B-expected.B))));
                        if (worst>=best) break;
                    }
                }
                best=Math.Min(best,worst);
            }
        }
        return best;
    }
}
'@
$tiles = [regex]::Matches($production, '"(?<id>[a-z_]+)", \[(?<x>\d+),(?<y>\d+),282,78,')
if ($tiles.Count -ne 7) { throw 'Expected the seven production tile origins.' }
$samples = @(
    @('normal-cargo','cargo','normal'), @('normal-sporting','sporting','normal'),
    @('normal-printing','printing','normal'), @('normal-cash','cash','normal'),
    @('full-organic','organic','full'), @('sell-goods','','none')
)
foreach ($variant in @('normal','full')) {
    $name = if ($variant -eq 'normal') { 'warehouse_person_foot' } else { 'warehouse_person_full_foot' }
    $template = [Drawing.Bitmap]::FromFile((Join-Path $assets ($name + '.png')))
    try {
        if ($template.Width -ne 15 -or $template.Height -ne 17) { throw "Unexpected $name dimensions" }
        foreach ($sample in $samples) {
            $source = [Drawing.Bitmap]::FromFile((Join-Path $fixtures ($sample[0] + '.png')))
            try {
                if ($source.Width -ne 876 -or $source.Height -ne 264) { throw 'Unexpected fixture crop.' }
                foreach ($tile in $tiles) {
                    $id = $tile.Groups['id'].Value
                    $x = [int]$tile.Groups['x'].Value - 728 + 230
                    $y = [int]$tile.Groups['y'].Value - 548 + 43
                    $area = New-Object Drawing.Rectangle $x, $y, 40, 27
                    $delta = [EarnWarehouseTemplatePixels]::MinimumVariation($source,$template,$area)
                    $expected = $sample[1] -eq $id -and $sample[2] -eq $variant
                    if (($delta -le 45) -ne $expected) {
                        throw "$name $($sample[0])/$id expected=$expected minVariation=$delta"
                    }
                    $cases++
                }
            } finally { $source.Dispose() }
        }
    } finally { $template.Dispose() }
}
# Reproduction is checked independently of matching, so editing the image asset
# without its observed source cannot silently change what the regression proves.
$generatedDirectory = Join-Path ([IO.Path]::GetTempPath()) ('gta-warehouse-template-' + [Guid]::NewGuid().ToString('N'))
$generated = Join-Path $generatedDirectory 'warehouse_person_full_foot.png'
try {
    & (Join-Path $PSScriptRoot 'build-warehouse-templates.ps1') -OutputDir $generatedDirectory | Out-Null
    $diff = Compare-PngPixels (Join-Path $assets 'warehouse_person_full_foot.png') $generated
    if ($diff) { throw "Builder does not reproduce the checked-in full-stock asset ($diff)." }
    $cases++
} finally {
    if ([IO.File]::Exists($generated)) { [IO.File]::Delete($generated) }
    if ([IO.Directory]::Exists($generatedDirectory)) { [IO.Directory]::Delete($generatedDirectory, $false) }
}
# The 2026-10-15 native GDI crop differs from the Steam recording: the selected
# Cash foot needs variation 64 with the production 1.55 gain, or 72 unmodified.
# Check the widened normal-foot match against every historical grid as well.
$nativeWork = Join-Path ([IO.Path]::GetTempPath()) ('gta-warehouse-native-' + [Guid]::NewGuid().ToString('N'))
$nativeSource = Join-Path $nativeWork 'source'
$nativeGain = Join-Path $nativeWork 'gain'
$normalSetting = [regex]::Match($production, 'normal := EarnSeen\("warehouse_person_foot", area, , , (?<variation>\d+)\)')
if (-not $normalSetting.Success) { throw 'Expected the production normal-foot tolerance.' }
$normalTolerance = [int]$normalSetting.Groups['variation'].Value
$null = New-Item -ItemType Directory -Path $nativeSource
Copy-Item -LiteralPath (Join-Path $assets 'warehouse_person_foot.png') -Destination $nativeSource
try {
    & (Join-Path $root 'Core\TemplateGain.ps1') -Source $nativeSource -Destination $nativeGain -Gain 1.55 | Out-Null
    $normal = [Drawing.Bitmap]::FromFile((Join-Path $assets 'warehouse_person_foot.png'))
    $gain = [Drawing.Bitmap]::FromFile((Join-Path $nativeGain 'warehouse_person_foot.png'))
    try {
        foreach ($sample in ($samples + ,@('native-cash','cash','normal'))) {
            $source = [Drawing.Bitmap]::FromFile((Join-Path $fixtures ($sample[0] + '.png')))
            try {
                foreach ($tile in $tiles) {
                    $id = $tile.Groups['id'].Value
                    $x = [int]$tile.Groups['x'].Value - 728 + 230
                    $y = [int]$tile.Groups['y'].Value - 548 + 43
                    $area = New-Object Drawing.Rectangle $x, $y, 40, 27
                    $originalDelta = [EarnWarehouseTemplatePixels]::MinimumVariation($source,$normal,$area)
                    $gainDelta = [EarnWarehouseTemplatePixels]::MinimumVariation($source,$gain,$area)
                    $expected = $sample[1] -eq $id -and $sample[2] -eq 'normal'
                    if (([Math]::Min($originalDelta,$gainDelta) -le $normalTolerance) -ne $expected) {
                        throw "Normal foot $($sample[0])/$id expected=$expected original=$originalDelta gain=$gainDelta"
                    }
                    if ($sample[0] -eq 'native-cash' -and $id -eq 'cash' -and
                        ($originalDelta -le 65 -or $gainDelta -le 45)) {
                        throw 'Native fixture no longer reproduces the original 45 failure and gain-only 65 recovery.'
                    }
                    $cases++
                }
            } finally { $source.Dispose() }
        }
        # Same failure capture: only the 40x27 icon search regions are retained.
        foreach ($tile in $tiles) {
            $id = $tile.Groups['id'].Value
            $source = [Drawing.Bitmap]::FromFile((Join-Path $fixtures ("native-1634-$id.png")))
            try {
                if ($source.Width -ne 40 -or $source.Height -ne 27) { throw 'Unexpected native icon crop.' }
                $area = New-Object Drawing.Rectangle 0, 0, 40, 27
                $originalDelta = [EarnWarehouseTemplatePixels]::MinimumVariation($source,$normal,$area)
                $gainDelta = [EarnWarehouseTemplatePixels]::MinimumVariation($source,$gain,$area)
                if (([Math]::Min($originalDelta,$gainDelta) -le $normalTolerance) -ne ($id -eq 'sporting')) {
                    throw "Native 1634/$id original=$originalDelta gain=$gainDelta tolerance=$normalTolerance"
                }
                if ($id -eq 'sporting' -and ($originalDelta -ne 72 -or $gainDelta -ne 66)) {
                    throw 'Native failure must retain the measured 72/66 boundary.'
                }
                $cases++
            } finally { $source.Dispose() }
        }
    } finally { $normal.Dispose(); $gain.Dispose() }
} finally {
    $resolvedWork = [IO.Path]::GetFullPath($nativeWork)
    $expectedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($resolvedWork) -ne $expectedParent) { throw 'Unexpected native fixture work directory.' }
    Remove-Item -LiteralPath $resolvedWork -Recurse -Force
}
Write-Output "PASS EarnWarehouseTemplates cases=$cases (saved pixels; no game input or windows)"
