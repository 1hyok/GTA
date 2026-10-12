#Requires -Version 5.1
<#
Checks saved pixels only. No window, live capture, OCR, or game input.
The legacy mask is reconstructed from the same committed capture and its old
rectangle, so a synthetic right-side overlay reproduces the original failure
without publishing chat content. Optional current samples remain local.
#>
[CmdletBinding()]
param([string[]]$AdditionalTaleSamplePath = @())

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$fixtures = Join-Path $PSScriptRoot 'mct-capture-fixtures'
$core = Get-Content -LiteralPath (Join-Path $root 'Features\Earn\EarnCore.ahk') -Raw
$cases = 0
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @'
using System;
using System.Collections.Generic;
using System.Drawing;
public static class EarnDJTemplateTest {
    // EarnSeen MCT branches use ImageSearch *60 *Trans0xFF00FF.
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
    public static Bitmap LegacyMask(Bitmap source, int left, int width) {
        Bitmap mask = source.Clone(new Rectangle(left, 505, width, 56), source.PixelFormat);
        for (int y = 0; y < mask.Height; y++) {
            for (int x = 0; x < mask.Width; x++) {
                Color color = mask.GetPixel(x, y);
                int low = Math.Min(color.R, Math.Min(color.G, color.B));
                int high = Math.Max(color.R, Math.Max(color.G, color.B));
                if (low < 170 || high - low > 35) mask.SetPixel(x, y, Color.Magenta);
            }
        }
        return mask;
    }
    public static void Cover(Bitmap source, Rectangle area) {
        using (Graphics graphics = Graphics.FromImage(source)) graphics.FillRectangle(Brushes.Black, area);
    }
    public static void WrongPrice(Bitmap source, int firstOne, int finalZero) {
        // Replace the last zero with the same captured '1', producing $10001.
        // All unmodified text and original font pixels remain untouched.
        using (Bitmap one = source.Clone(new Rectangle(firstOne, 509, 4, 20), source.PixelFormat)) {
            Cover(source, new Rectangle(finalZero, 509, 13, 20));
            for (int y = 0; y < one.Height; y++)
                for (int x = 0; x < one.Width; x++)
                    source.SetPixel(finalZero + 4 + x, 509 + y, one.GetPixel(x, y));
        }
    }
}
'@

function Check-Match([Drawing.Bitmap]$Source, [Drawing.Bitmap]$Template, [Drawing.Rectangle]$Area,
                     [bool]$Expected, [string]$Label) {
    if ($Source.Width -ne 1920 -or $Source.Height -ne 1080) { throw 'Expected 1920x1080 source pixels' }
    $x = 0; $y = 0
    $variation = [EarnDJTemplateTest]::MinimumVariation($Source, $Template, $Area, [ref]$x, [ref]$y)
    if (($variation -le 60) -ne $Expected) { throw "$Label expected=$Expected minVariation=$variation at $x,$y" }
    $script:cases++
    Write-Output "PASS $Label found=$Expected minVariation=$variation at $x,$y"
}

$samples = @('mansion-dj-confirm.png', 'mansion-dj-confirm-tale.png', 'mansion-dj-list.png',
    'mansion-dj-after.png', 'mansion-dj-right.png', 'mansion-dj-right-after.png',
    'mansion-bunker-result.png', 'mansion-confirm2.png')
$definitions = @(
    @{ Name = 'dj_confirm_solomun'; Source = 'mansion-dj-confirm.png'; Left = 605; OldWidth = 710; PriceX = 1118; OneX = 1131; ZeroX = 1182 },
    @{ Name = 'dj_confirm_tale'; Source = 'mansion-dj-confirm-tale.png'; Left = 595; OldWidth = 730; PriceX = 1127; OneX = 1140; ZeroX = 1191 }
)
foreach ($definition in $definitions) {
    $name = $definition.Name
    $template = [Drawing.Bitmap]::FromFile((Join-Path $root "Images\Earn\1920x1080\$name.png"))
    $observed = [Drawing.Bitmap]::FromFile((Join-Path $fixtures $definition.Source))
    $legacy = $null
    try {
        $legacy = [EarnDJTemplateTest]::LegacyMask($observed, $definition.Left, $definition.OldWidth)
        if ($template.Width -ne 630 -or $template.Height -ne 56) { throw "$name must preserve its complete 630x56 identity crop" }
        for ($y = 0; $y -lt $template.Height; $y++) {
            for ($x = 0; $x -lt $template.Width; $x++) {
                if ($template.GetPixel($x, $y).ToArgb() -ne $legacy.GetPixel($x, $y).ToArgb()) {
                    throw "$name changed retained identity pixels at $x,$y instead of removing only the right suffix"
                }
            }
        }
        $cases++
        $areaMatch = [regex]::Match($core, ('"' + $name + '",\s*\[([0-9.,]+)\]'))
        if (-not $areaMatch.Success) { throw "$name actual EarnSeen search area is missing" }
        $ratios = @($areaMatch.Groups[1].Value.Split(',') | ForEach-Object { [double]::Parse($_, [Globalization.CultureInfo]::InvariantCulture) })
        $left = [int][Math]::Round(1920 * $ratios[0]); $top = [int][Math]::Round(1080 * $ratios[1])
        $right = [int][Math]::Round(1920 * $ratios[2]); $bottom = [int][Math]::Round(1080 * $ratios[3])
        $area = New-Object Drawing.Rectangle $left, $top, ($right - $left), ($bottom - $top)
        Check-Match $observed $legacy $area $true "$name legacy-unobstructed-control"
        foreach ($sample in $samples) {
            $source = [Drawing.Bitmap]::FromFile((Join-Path $fixtures $sample))
            try { Check-Match $source $template $area ($sample -eq $definition.Source) "$name $sample" }
            finally { $source.Dispose() }
        }
        $covered = [Drawing.Bitmap]$observed.Clone()
        try {
            [EarnDJTemplateTest]::Cover($covered, (New-Object Drawing.Rectangle 1288, 480, 250, 190))
            Check-Match $covered $legacy $area $false "$name right-overlay legacy-reproduction"
            Check-Match $covered $template $area $true "$name right-overlay repaired"
        } finally { $covered.Dispose() }
        foreach ($mutation in @('wrong-price', 'hidden-price', 'hidden-DJ-name', 'hidden-resident-sentence')) {
            $changed = [Drawing.Bitmap]$observed.Clone()
            try {
                switch ($mutation) {
                    'wrong-price' { [EarnDJTemplateTest]::WrongPrice($changed, $definition.OneX, $definition.ZeroX) }
                    'hidden-price' { [EarnDJTemplateTest]::Cover($changed, (New-Object Drawing.Rectangle $definition.PriceX, 505, 80, 26)) }
                    'hidden-DJ-name' { [EarnDJTemplateTest]::Cover($changed, (New-Object Drawing.Rectangle 970, 505, 112, 26)) }
                    'hidden-resident-sentence' { [EarnDJTemplateTest]::Cover($changed, (New-Object Drawing.Rectangle 829, 536, 260, 26)) }
                }
                Check-Match $changed $template $area $false "$name $mutation"
            } finally { $changed.Dispose() }
        }
        if ($name -eq 'dj_confirm_tale') {
            foreach ($path in $AdditionalTaleSamplePath) {
                $source = [Drawing.Bitmap]::FromFile([IO.Path]::GetFullPath($path))
                try { Check-Match $source $template $area $true "$name additional-local-sample" }
                finally { $source.Dispose() }
            }
        }
    } finally {
        if ($null -ne $legacy) { $legacy.Dispose() }
        $observed.Dispose(); $template.Dispose()
    }
}
Write-Output "PASS DJTemplates cases=$cases (no game input or windows)"
