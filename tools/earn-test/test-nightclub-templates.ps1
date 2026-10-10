#Requires -Version 5.1
<#
Compares PNG pixels without displaying windows or reading the live desktop.
The matcher follows ImageSearch *40 *Trans0xFF00FF: every nonmagenta template
pixel must be within 40 in each RGB channel. AdditionalSamplePath can contain
current nightclub captures whose Home and Resident DJ navigation labels show.
#>
[CmdletBinding()]
param([string[]]$AdditionalSamplePath = @())

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$evidence = Join-Path $root 'tools\earn-test\mct-capture-fixtures'
$core = Get-Content -LiteralPath (Join-Path $root 'Features\Earn\EarnCore.ahk') -Raw
$cases = 0
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @'
using System;
using System.Collections.Generic;
using System.Drawing;
public static class EarnNightclubTemplateTest {
    public static int MinimumVariation(Bitmap source, Bitmap template, Rectangle area,
                                       out int foundX, out int foundY) {
        var columns = new List<int>();
        var rows = new List<int>();
        var colors = new List<int>();
        for (int y = 0; y < template.Height; y++) {
            for (int x = 0; x < template.Width; x++) {
                int color = template.GetPixel(x, y).ToArgb() & 0xFFFFFF;
                if (color == 0xFF00FF) continue;
                columns.Add(x); rows.Add(y); colors.Add(color);
            }
        }
        if (colors.Count == 0) throw new InvalidOperationException("Empty template mask");
        int[] pixels = new int[area.Width * area.Height];
        for (int y = 0; y < area.Height; y++)
            for (int x = 0; x < area.Width; x++)
                pixels[y * area.Width + x] = source.GetPixel(area.X + x, area.Y + y).ToArgb();
        int best = 256;
        foundX = -1; foundY = -1;
        for (int y = 0; y + template.Height <= area.Height; y++) {
            for (int x = 0; x + template.Width <= area.Width; x++) {
                int worst = 0;
                for (int p = 0; p < colors.Count; p++) {
                    int actual = pixels[(y + rows[p]) * area.Width + x + columns[p]];
                    for (int c = 0; c < 3; c++) {
                        int shift = c * 8;
                        int difference = Math.Abs(((actual >> shift) & 255) - ((colors[p] >> shift) & 255));
                        worst = Math.Max(worst, difference);
                    }
                    if (worst >= best) break;
                }
                if (worst < best) {
                    best = worst; foundX = area.X + x; foundY = area.Y + y;
                    if (best == 0) return 0;
                }
            }
        }
        return best;
    }
}
'@

$samples = @(
    @('mansion-dj-list.png', $true),
    @('mansion-dj-after.png', $true),
    @('mansion-dj-right.png', $true),
    @('mansion-dj-right-after.png', $true),
    @('mansion-mct-return2.png', $false),
    @('mansion-bunker-result.png', $false),
    @('mansion-dj-confirm.png', $false),
    @('mansion-dj-confirm-tale.png', $false)
) | ForEach-Object { @((Join-Path $evidence $_[0]), $_[1]) }
# Preserve each pair instead of PowerShell's normal pipeline array unrolling.
$samplePairs = @()
for ($index = 0; $index -lt $samples.Count; $index += 2) {
    $samplePairs += ,@($samples[$index], $samples[$index + 1])
}
foreach ($path in $AdditionalSamplePath) {
    $samplePairs += ,@([IO.Path]::GetFullPath($path), $true)
}
foreach ($name in @('nc_dj_menu', 'nc_home')) {
    $template = [Drawing.Bitmap]::FromFile((Join-Path $root "Images\Earn\1920x1080\$name.png"))
    try {
        $retained = 0
        for ($y = 0; $y -lt $template.Height; $y++) {
            for ($x = 0; $x -lt $template.Width; $x++) {
                $pixel = $template.GetPixel($x, $y)
                if ($pixel.R -eq 255 -and $pixel.G -eq 0 -and $pixel.B -eq 255) { continue }
                if ($pixel.R -lt 200 -or $pixel.G -lt 200 -or $pixel.B -lt 200) {
                    throw "$name retains unstable antialias or background pixels at $x,$y"
                }
                $retained++
            }
        }
        if ($retained -lt 200 -or $retained -ge $template.Width * $template.Height) {
            throw "$name has an invalid white-text mask: $retained pixels"
        }
        $cases++
        $areaMatch = [regex]::Match($core, ('"' + $name + '",\s*\[([0-9.,]+)\]'))
        if (-not $areaMatch.Success) { throw "$name actual EarnCore search area was not found" }
        $ratios = @($areaMatch.Groups[1].Value.Split(',') | ForEach-Object {
            [double]::Parse($_, [Globalization.CultureInfo]::InvariantCulture)
        })
        $left = [int][Math]::Round(1920 * $ratios[0])
        $top = [int][Math]::Round(1080 * $ratios[1])
        $right = [int][Math]::Round(1920 * $ratios[2])
        $bottom = [int][Math]::Round(1080 * $ratios[3])
        $area = New-Object Drawing.Rectangle $left, $top, ($right - $left), ($bottom - $top)
        foreach ($sample in $samplePairs) {
            $source = [Drawing.Bitmap]::FromFile($sample[0])
            try {
                if ($source.Width -ne 1920 -or $source.Height -ne 1080) { throw 'Expected a 1920x1080 screenshot' }
                $x = 0; $y = 0
                $variation = [EarnNightclubTemplateTest]::MinimumVariation($source, $template, $area, [ref]$x, [ref]$y)
                $found = $variation -le 40
                if ($found -ne $sample[1]) {
                    throw "$name in $([IO.Path]::GetFileName($sample[0])) expected=$($sample[1]) minVariation=$variation at $x,$y"
                }
                $cases++
                Write-Output "PASS $name $([IO.Path]::GetFileName($sample[0])) found=$found minVariation=$variation at $x,$y"
            }
            finally { $source.Dispose() }
        }
    }
    finally { $template.Dispose() }
}
Write-Output "PASS NightclubTemplates cases=$cases (no game input or windows)"
