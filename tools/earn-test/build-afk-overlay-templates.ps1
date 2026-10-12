#Requires -Version 5.1
<# Rebuild the shared Vinewood title mask from its recorded fixture. No game input. #>
[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path $PSScriptRoot '..\..\Images\Earn\1920x1080'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$raw = [Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'afk-overlay-fixtures\afk_vinewood_title-raw.png'))
$mask = New-Object Drawing.Bitmap $raw.Width, $raw.Height
try {
    $background = New-Object 'System.Collections.Generic.List[object]'
    for ($y = 0; $y -lt $raw.Height; $y++) {
        for ($x = 0; $x -lt $raw.Width; $x++) {
            $pixel = $raw.GetPixel($x, $y)
            $white = [Math]::Min($pixel.R, [Math]::Min($pixel.G, $pixel.B)) -ge 200
            $mask.SetPixel($x, $y, $(if ($white) { $pixel } else { [Drawing.Color]::Magenta }))
            if ([Math]::Max($pixel.R, [Math]::Max($pixel.G, $pixel.B)) -gt 20) { continue }
            # Keep only flat dark pixels well away from antialiased glyph edges.
            $far = $true
            for ($dy = -2; $dy -le 2 -and $far; $dy++) {
                for ($dx = -2; $dx -le 2; $dx++) {
                    $xx = $x + $dx; $yy = $y + $dy
                    if ($xx -lt 0 -or $yy -lt 0 -or $xx -ge $raw.Width -or $yy -ge $raw.Height) { continue }
                    $near = $raw.GetPixel($xx, $yy)
                    if ([Math]::Max($near.R, [Math]::Max($near.G, $near.B)) -gt 20) { $far = $false; break }
                }
            }
            if ($far) { $background.Add(@($x, $y)) }
        }
    }
    if ($background.Count -lt 16) { throw 'Not enough stable title background pixels.' }
    for ($i = 0; $i -lt 16; $i++) {
        $point = $background[[int][Math]::Floor($i * $background.Count / 16)]
        $mask.SetPixel($point[0], $point[1], $raw.GetPixel($point[0], $point[1]))
    }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($OutputDirectory))
    $output = Join-Path $OutputDirectory 'afk_vinewood_title.png'
    $mask.Save($output, [Drawing.Imaging.ImageFormat]::Png)
    Write-Output "Vinewood title mask: existing white glyphs + 16 dark background anchors -> $output"
} finally { $mask.Dispose(); $raw.Dispose() }
