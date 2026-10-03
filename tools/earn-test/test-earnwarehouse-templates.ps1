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
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $generated).Hash
    $expected = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $assets 'warehouse_person_full_foot.png')).Hash
    if ($actual -ne $expected) { throw 'Builder does not reproduce the checked-in full-stock asset.' }
    $cases++
} finally {
    if ([IO.File]::Exists($generated)) { [IO.File]::Delete($generated) }
    if ([IO.Directory]::Exists($generatedDirectory)) { [IO.Directory]::Delete($generatedDirectory, $false) }
}
Write-Output "PASS EarnWarehouseTemplates cases=$cases (saved pixels; no game input or windows)"
