#Requires -Version 5.1
<# Static ImageSearch-compatible phone/app guard checks. No desktop reads or input. #>
[CmdletBinding()]
param([string]$SampleDirectory = '')
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @'
using System;
using System.Drawing;
using System.Collections.Generic;
public static class AFKOverlayTest {
    public static int MinimumVariation(Bitmap image, Bitmap template, Rectangle area) {
        var offsets = new List<int>(); var colors = new List<int>();
        for (int y = 0; y < template.Height; y++) for (int x = 0; x < template.Width; x++) {
            int color = template.GetPixel(x, y).ToArgb() & 0xFFFFFF;
            if (color != 0xFF00FF) { offsets.Add(y * area.Width + x); colors.Add(color); }
        }
        if (colors.Count < 100) throw new InvalidOperationException("Insufficient template pixels");
        int[] pixels = new int[area.Width * area.Height];
        for (int y = 0; y < area.Height; y++) for (int x = 0; x < area.Width; x++)
            pixels[y * area.Width + x] = image.GetPixel(area.X + x, area.Y + y).ToArgb();
        int best = 256;
        for (int y = 0; y + template.Height <= area.Height; y++) for (int x = 0; x + template.Width <= area.Width; x++) {
            int worst = 0;
            for (int p = 0; p < offsets.Count; p++) {
                int actual = pixels[y * area.Width + x + offsets[p]];
                for (int c = 0; c < 3; c++) {
                    int shift = c * 8;
                    worst = Math.Max(worst, Math.Abs(((actual >> shift) & 255) - ((colors[p] >> shift) & 255)));
                }
                if (worst >= best) break;
            }
            if (worst < best) { best = worst; if (best == 0) return 0; }
        }
        return best;
    }
}
'@
$cases = 0
$names = @('afk_phone_frame', 'afk_vinewood_title')
function Assert-Overlay([Drawing.Bitmap]$Image, [string]$Label, [bool]$Phone, [bool]$App) {
    if ($Image.Width -ne 1920 -or $Image.Height -ne 1080) { throw 'Expected 1920x1080 capture' }
    foreach ($name in $names) {
        $template = [Drawing.Bitmap]::FromFile((Join-Path $root "Images\Earn\1920x1080\$name.png"))
        try {
            $phoneTemplate = $name -eq 'afk_phone_frame'
            $area = if ($phoneTemplate) { New-Object Drawing.Rectangle 1594, 626, 288, 152 }
                else { New-Object Drawing.Rectangle 0, 0, 518, 216 }
            $variation = [AFKOverlayTest]::MinimumVariation($Image, $template, $area)
            $expected = if ($phoneTemplate) { $Phone } else { $App }
            if (($variation -le 40) -ne $expected) { throw "$Label $name expected=$expected minVariation=$variation" }
            $script:cases++
            Write-Output "PASS $Label $name found=$expected minVariation=$variation"
        }
        finally { $template.Dispose() }
    }
}
# These two tiny fixtures contain only iFruit and THE VINEWOOD CLUB APP labels.
foreach ($name in $names) {
    $source = [Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot "afk-overlay-fixtures\$name-raw.png"))
    $canvas = New-Object Drawing.Bitmap 1920, 1080
    $graphics = [Drawing.Graphics]::FromImage($canvas)
    try {
        $graphics.Clear([Drawing.Color]::Black)
        if ($name -eq 'afk_phone_frame') { $graphics.DrawImageUnscaled($source, 1710, 666) }
        else { $graphics.DrawImageUnscaled($source, 38, 132) }
        $graphics.Dispose(); $graphics = $null
        Assert-Overlay $canvas $name ($name -eq 'afk_phone_frame') ($name -eq 'afk_vinewood_title')
    }
    finally { if ($null -ne $graphics) { $graphics.Dispose() }; $canvas.Dispose(); $source.Dispose() }
}
if ($SampleDirectory) {
    foreach ($sample in @(
        @('earn-vinewood-selected', $true, $false),
        @('earn-vinewood-main', $false, $true),
        @('earn-bail-agents', $false, $true),
        @('earn-cargo-disabled', $false, $true),
        @('earn-safe-final', $false, $false),
        @('earn-final-boss-status', $false, $false)
    )) {
        $source = [Drawing.Bitmap]::FromFile((Join-Path $SampleDirectory ($sample[0] + '.png')))
        try { Assert-Overlay $source $sample[0] $sample[1] $sample[2] }
        finally { $source.Dispose() }
    }
}
Write-Output "PASS AFKOverlays: $cases cases; no game input"
