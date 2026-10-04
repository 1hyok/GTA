#Requires -Version 5.1
<#
Static regression for the mansion MCT prompt and the template builder.
The saved fixture contains only the observed 240x24 "Master Control Terminal"
label at 72,28, cropped from earn-warehouse-done.png on 2026-10-03. No account
name, desktop notification or game balance is included. No windows or input.
#>
[CmdletBinding()]
param([string]$AdditionalSeatedSamplePath = '')
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$assetDirectory = Join-Path $root 'Images\Earn\1920x1080'
$evidence = Join-Path $root 'docs\evidence\2026-09-27-mct'
$cases = 0
. (Join-Path $PSScriptRoot 'compare-png-pixels.ps1')

# Also runs the existing nightclub positive/negative regression. Its public
# pixel matcher implements the same per-channel ImageSearch comparison.
& (Join-Path $PSScriptRoot 'test-nightclub-templates.ps1')
$template = [Drawing.Bitmap]::FromFile((Join-Path $assetDirectory 'mct_seated_mansion.png'))
$area = New-Object Drawing.Rectangle 0, 0, 576, 108
function Assert-SeatedMatch([Drawing.Bitmap]$Source, [bool]$Expected, [string]$Label) {
    if ($Source.Width -ne 1920 -or $Source.Height -ne 1080) { throw "$Label is not a 1920x1080 screenshot" }
    $x = 0; $y = 0
    $variation = [EarnNightclubTemplateTest]::MinimumVariation($Source, $template, $area, [ref]$x, [ref]$y)
    if (($variation -le 40) -ne $Expected -or ($Expected -and ($x -ne 72 -or $y -ne 28))) {
        throw "$Label expected=$Expected minVariation=$variation at $x,$y"
    }
    $script:cases++
    Write-Output "PASS seated $Label found=$Expected minVariation=$variation at $x,$y"
}
try {
    if ($template.Width -ne 240 -or $template.Height -ne 24) { throw 'Unexpected mansion prompt dimensions' }
    $retained = 0
    for ($y = 0; $y -lt $template.Height; $y++) {
        for ($x = 0; $x -lt $template.Width; $x++) {
            $pixel = $template.GetPixel($x, $y)
            if ($pixel.R -eq 255 -and $pixel.G -eq 0 -and $pixel.B -eq 255) { continue }
            if ($pixel.R -lt 200 -or $pixel.G -lt 200 -or $pixel.B -lt 200) { throw 'Prompt retains unstable glyph fringe' }
            $retained++
        }
    }
    if ($retained -lt 500 -or $retained -ge 240 * 24) { throw "Insufficient distinct prompt pixels: $retained" }
    $cases++
    Write-Output "PASS seated mask dimensions=240x24 retained=$retained"
    $fixture = [Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'mct-template-fixtures\mct-seated-current.png'))
    try {
        foreach ($scale in @(1.0, 0.5)) {
            $canvas = New-Object Drawing.Bitmap 1920, 1080
            $graphics = [Drawing.Graphics]::FromImage($canvas)
            try {
                $graphics.Clear([Drawing.Color]::Black)
                $graphics.DrawImage($fixture, [int](72 * $scale), [int](28 * $scale), [int](240 * $scale), [int](24 * $scale))
                $graphics.Dispose(); $graphics = $null
                Assert-SeatedMatch $canvas ($scale -eq 1.0) "actual-label-scale-$scale"
            }
            finally { if ($null -ne $graphics) { $graphics.Dispose() }; $canvas.Dispose() }
        }
    }
    finally { $fixture.Dispose() }
    foreach ($name in @('mct-final-restored.png', 'mansion-dj-after.png', 'mansion-bunker-result.png')) {
        $source = [Drawing.Bitmap]::FromFile((Join-Path $evidence $name))
        try { Assert-SeatedMatch $source $false $name }
        finally { $source.Dispose() }
    }
    if ($AdditionalSeatedSamplePath) {
        $source = [Drawing.Bitmap]::FromFile([IO.Path]::GetFullPath($AdditionalSeatedSamplePath))
        try { Assert-SeatedMatch $source $true ([IO.Path]::GetFileName($AdditionalSeatedSamplePath)) }
        finally { $source.Dispose() }
    }
}
finally { $template.Dispose() }

$generatedDirectory = Join-Path ([IO.Path]::GetTempPath()) ('gta-mct-template-build-' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($generatedDirectory)
$names = @('nc_dj_menu', 'nc_home', 'mct_seated_mansion')
try {
    & (Join-Path $PSScriptRoot 'build-mct-templates.ps1') -OutputDir $generatedDirectory -Name $names
    foreach ($name in $names) {
        $diff = Compare-PngPixels (Join-Path $assetDirectory ($name + '.png')) (Join-Path $generatedDirectory ($name + '.png'))
        if ($diff) { throw "Builder changes the checked-in stable mask: $name ($diff)" }
        $cases++
        Write-Output "PASS builder reproduces $name"
    }
}
finally {
    foreach ($name in $names) {
        $generated = Join-Path $generatedDirectory ($name + '.png')
        if ([IO.File]::Exists($generated)) { [IO.File]::Delete($generated) }
    }
    [IO.Directory]::Delete($generatedDirectory, $false)
}
Write-Output "PASS MCTSeatedTemplate cases=$cases (no game input or windows)"
