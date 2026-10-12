#Requires -Version 5.1
<# Static ImageSearch-compatible phone/app guard checks. No desktop reads or input. #>
[CmdletBinding()]
param([string]$SampleDirectory = '', [string[]]$NegativeImages = @())
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @'
using System;
using System.Drawing;
using System.Collections.Generic;
public static class AFKOverlayTest {
    public static string FirstPixelDifference(Bitmap expected, Bitmap actual) {
        if (expected.Width != actual.Width || expected.Height != actual.Height)
            return String.Format("dimensions expected={0}x{1} actual={2}x{3}",
                expected.Width, expected.Height, actual.Width, actual.Height);
        for (int y = 0; y < expected.Height; y++) for (int x = 0; x < expected.Width; x++) {
            int expectedArgb = expected.GetPixel(x, y).ToArgb();
            int actualArgb = actual.GetPixel(x, y).ToArgb();
            if (expectedArgb != actualArgb)
                return String.Format("pixel ({0},{1}) expected=0x{2:X8} actual=0x{3:X8}",
                    x, y, expectedArgb, actualArgb);
        }
        return "";
    }
    public static Bitmap Brighten(Bitmap source, double gain) {
        var result = new Bitmap(source.Width, source.Height);
        for (int y = 0; y < source.Height; y++) for (int x = 0; x < source.Width; x++) {
            Color c = source.GetPixel(x, y);
            result.SetPixel(x, y, Color.FromArgb(
                Math.Min(255, (int)Math.Round(c.R * gain)),
                Math.Min(255, (int)Math.Round(c.G * gain)),
                Math.Min(255, (int)Math.Round(c.B * gain))));
        }
        return result;
    }
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

function Assert-AppTitle([Drawing.Bitmap]$Image, [string]$Label, [string]$TemplatePath, [bool]$Expected) {
    if ($Image.Width -ne 1920 -or $Image.Height -ne 1080) { throw 'Expected 1920x1080 capture' }
    $template = [Drawing.Bitmap]::FromFile($TemplatePath)
    try {
        # AFK searches the top 20%; Vinewood entry searches the top 55%.
        # The MCT recovery HUD also consumes this mask with variation 15.
        foreach ($height in @(216, 594)) {
            $variation = [AFKOverlayTest]::MinimumVariation($Image, $template, (New-Object Drawing.Rectangle 0, 0, 518, $height))
            foreach ($limit in @(15, 40)) {
                if (($variation -le $limit) -ne $Expected) {
                    throw "$Label app title expected=$Expected height=$height limit=$limit minVariation=$variation"
                }
                $script:cases++
                Write-Output "PASS $Label app title found=$Expected height=$height limit=$limit minVariation=$variation"
            }
        }
    }
    finally { $template.Dispose() }
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

# Exercise the production brightness-copy generator as well as the original
# shared asset. The old glyph-only mask falsely matched uniform RGB 220 at
# variation 20; its 1.55 gain copy falsely matched uniform white at variation 0.
$temporary = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('gta-afk-overlay-' + [Guid]::NewGuid().ToString('N'))))
$originalDirectory = Join-Path $temporary 'original'
$gainDirectory = Join-Path $temporary 'gain'
$rebuiltDirectory = Join-Path $temporary 'rebuilt'
$titleName = 'afk_vinewood_title.png'
$committedTitle = Join-Path $root ('Images\Earn\1920x1080\' + $titleName)
[void][IO.Directory]::CreateDirectory($originalDirectory)
try {
    Copy-Item -LiteralPath $committedTitle -Destination (Join-Path $originalDirectory $titleName)
    & (Join-Path $root 'Core\TemplateGain.ps1') -Source $originalDirectory -Destination $gainDirectory -Gain 1.55
    & (Join-Path $PSScriptRoot 'build-afk-overlay-templates.ps1') -OutputDirectory $rebuiltDirectory
    $rebuiltTitle = Join-Path $rebuiltDirectory $titleName
    # GDI+ may encode identical pixels into different PNG bytes across Windows
    # versions. Compare every decoded ARGB pixel, including transparent colors.
    $committedBitmap = [Drawing.Bitmap]::FromFile($committedTitle)
    $rebuiltBitmap = [Drawing.Bitmap]::FromFile($rebuiltTitle)
    $mutatedBitmap = $null
    try {
        $difference = [AFKOverlayTest]::FirstPixelDifference($committedBitmap, $rebuiltBitmap)
        if ($difference) { throw "The app-title mask is not reproducible: $difference" }
        $script:cases++
        Write-Output 'PASS app-title mask exactly reproduces its decoded dimensions and ARGB pixels'

        # Change only the alpha channel of the final pixel. This proves the
        # comparator reaches the end of the image and checks ARGB, not just RGB.
        $mutatedBitmap = [Drawing.Bitmap]$rebuiltBitmap.Clone()
        $lastX = $mutatedBitmap.Width - 1; $lastY = $mutatedBitmap.Height - 1
        $before = $mutatedBitmap.GetPixel($lastX, $lastY)
        $after = [Drawing.Color]::FromArgb(($before.A -bxor 1), $before.R, $before.G, $before.B)
        $mutatedBitmap.SetPixel($lastX, $lastY, $after)
        $difference = [AFKOverlayTest]::FirstPixelDifference($committedBitmap, $mutatedBitmap)
        $expectedDifference = 'pixel ({0},{1}) expected=0x{2:X8} actual=0x{3:X8}' -f $lastX, $lastY, $before.ToArgb(), $after.ToArgb()
        if ($difference -ne $expectedDifference) { throw "Pixel-comparison mutation check failed: $difference" }
        $script:cases++
        Write-Output "PASS app-title pixel comparison rejects one alpha mutation: $difference"
    }
    finally {
        if ($null -ne $mutatedBitmap) { $mutatedBitmap.Dispose() }
        $rebuiltBitmap.Dispose(); $committedBitmap.Dispose()
    }

    foreach ($spec in @(@('original', $originalDirectory, 1.0), @('gain-1.55', $gainDirectory, 1.55))) {
        $templatePath = Join-Path $spec[1] $titleName
        foreach ($brightness in @(0, 180, 200, 220, 240, 255)) {
            $canvas = New-Object Drawing.Bitmap 1920, 1080
            $graphics = [Drawing.Graphics]::FromImage($canvas)
            try {
                $graphics.Clear([Drawing.Color]::FromArgb($brightness, $brightness, $brightness))
                $graphics.Dispose(); $graphics = $null
                Assert-AppTitle $canvas ($spec[0] + '-uniform-' + $brightness) $templatePath $false
            }
            finally { if ($null -ne $graphics) { $graphics.Dispose() }; $canvas.Dispose() }
        }

        $raw = [Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'afk-overlay-fixtures\afk_vinewood_title-raw.png'))
        $source = [AFKOverlayTest]::Brighten($raw, $spec[2])
        $canvas = New-Object Drawing.Bitmap 1920, 1080
        $graphics = [Drawing.Graphics]::FromImage($canvas)
        try {
            # A bright world around the real dark title must not hide the app.
            $graphics.Clear([Drawing.Color]::White)
            $graphics.DrawImageUnscaled($source, 38, 132)
            $graphics.Dispose(); $graphics = $null
            Assert-AppTitle $canvas ($spec[0] + '-recorded-title-on-bright-world') $templatePath $true
        }
        finally {
            if ($null -ne $graphics) { $graphics.Dispose() }
            $canvas.Dispose(); $source.Dispose(); $raw.Dispose()
        }

        foreach ($path in $NegativeImages) {
            $source = [Drawing.Bitmap]::FromFile([IO.Path]::GetFullPath($path))
            try { Assert-AppTitle $source ($spec[0] + '-' + [IO.Path]::GetFileName($path)) $templatePath $false }
            finally { $source.Dispose() }
        }
    }
}
finally {
    # This is only the GUID-named directory created by this invocation.
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $temporary.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($temporary) -notmatch '^gta-afk-overlay-[0-9a-f]{32}$') {
        throw 'Refusing to remove an unexpected overlay-test directory'
    }
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
Write-Output "PASS AFKOverlays: $cases cases; no game input"
