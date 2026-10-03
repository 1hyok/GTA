#Requires -Version 5.1
<# Saved-pixel bunker screen regression. No desktop reads, windows or input. #>
[CmdletBinding()]
param(
    [string[]]$AdditionalResupplySamplePath = @(),
    [string[]]$AdditionalConfirmSamplePath = @()
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$evidence = Join-Path $root 'docs\evidence\2026-09-27-mct'
$assetDirectory = Join-Path $root 'Images\Earn\1920x1080'
$core = Get-Content -LiteralPath (Join-Path $root 'Features\Earn\EarnCore.ahk') -Raw
$cases = 0

# Reuse the existing ImageSearch-compatible per-channel/magenta matcher.
& (Join-Path $PSScriptRoot 'test-nightclub-templates.ps1') | Out-Null
$samples = @(
    @('mansion-bunker-result.png', 'bunker_page,bunker_resupply,bunker_buy'),
    @('mansion-bunker-code-fail.png', 'bunker_entry'),
    @('mansion-confirm2.png', 'bunker_confirm'),
    @('mansion-bunker-pending.png', 'bunker_pending'),
    @('mansion-dj-list.png', ''),
    @('mansion-dj-confirm.png', ''),
    @('mansion-mct-return2.png', ''),
    @('mct-final-restored.png', '')
)
foreach ($name in @('bunker_page', 'bunker_entry', 'bunker_resupply', 'bunker_buy', 'bunker_confirm', 'bunker_pending')) {
    $template = [Drawing.Bitmap]::FromFile((Join-Path $assetDirectory ($name + '.png')))
    try {
        $match = [regex]::Match($core, ('"' + $name + '",\s*\[([0-9.,]+)\]'))
        if (-not $match.Success) { throw "$name actual production search area was not found" }
        $ratios = @($match.Groups[1].Value.Split(',') | ForEach-Object {
            [double]::Parse($_, [Globalization.CultureInfo]::InvariantCulture)
        })
        $left = [int][Math]::Round(1920 * $ratios[0])
        $top = [int][Math]::Round(1080 * $ratios[1])
        $right = [int][Math]::Round(1920 * $ratios[2])
        $bottom = [int][Math]::Round(1080 * $ratios[3])
        $area = New-Object Drawing.Rectangle $left, $top, ($right - $left), ($bottom - $top)
        $pairs = @($samples | ForEach-Object { ,@((Join-Path $evidence $_[0]), ($_.Item(1).Split(',') -contains $name)) })
        foreach ($path in $AdditionalResupplySamplePath) {
            $pairs += ,@([IO.Path]::GetFullPath($path), ($name -in @('bunker_page', 'bunker_resupply', 'bunker_buy')))
        }
        foreach ($path in $AdditionalConfirmSamplePath) {
            $pairs += ,@([IO.Path]::GetFullPath($path), ($name -eq 'bunker_confirm'))
        }
        foreach ($pair in $pairs) {
            $source = [Drawing.Bitmap]::FromFile($pair[0])
            try {
                if ($source.Width -ne 1920 -or $source.Height -ne 1080) { throw 'Expected a 1920x1080 screenshot' }
                $x = 0; $y = 0
                $variation = [EarnNightclubTemplateTest]::MinimumVariation($source, $template, $area, [ref]$x, [ref]$y)
                if (($variation -le 40) -ne $pair[1]) {
                    throw "$name $([IO.Path]::GetFileName($pair[0])) expected=$($pair[1]) minVariation=$variation at $x,$y"
                }
                $cases++
                Write-Output "PASS $name $([IO.Path]::GetFileName($pair[0])) found=$($pair[1]) minVariation=$variation at $x,$y"
            }
            finally { $source.Dispose() }
        }
        # Raw $75,000 glyphs from 2026-10-03 bunker-fix-resupply-raw.png and
        # bunker-fix-confirm-raw.png, restored at the observed crop positions.
        # Store only these tiny crops, excluding player names and balances.
        foreach ($fixture in @(
            @('bunker-buy-75000.png', 'bunker_buy', 802, 769, 165, 29),
            @('bunker-confirm-75000.png', 'bunker_confirm', 700, 463, 519, 31)
        )) {
            $crop = [Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot ('mct-template-fixtures\' + $fixture[0])))
            $canvas = New-Object Drawing.Bitmap 1920, 1080
            $graphics = [Drawing.Graphics]::FromImage($canvas)
            try {
                if ($crop.Width -ne $fixture[4] -or $crop.Height -ne $fixture[5]) { throw "Invalid fixture dimensions: $($fixture[0])" }
                $graphics.Clear([Drawing.Color]::Black)
                $graphics.DrawImageUnscaled($crop, [int]$fixture[2], [int]$fixture[3])
                $graphics.Dispose(); $graphics = $null
                $x = 0; $y = 0
                $variation = [EarnNightclubTemplateTest]::MinimumVariation($canvas, $template, $area, [ref]$x, [ref]$y)
                $expected = $name -eq $fixture[1]
                if (($variation -le 40) -ne $expected -or ($expected -and ($x -ne $fixture[2] -or $y -ne $fixture[3]))) {
                    throw "$name $($fixture[0]) expected=$expected minVariation=$variation at $x,$y"
                }
                $cases++
                Write-Output "PASS $name $($fixture[0]) found=$expected minVariation=$variation at $x,$y"
            }
            finally {
                if ($null -ne $graphics) { $graphics.Dispose() }
                $canvas.Dispose(); $crop.Dispose()
            }
        }
        if ($name -in @('bunker_buy', 'bunker_confirm')) {
            $retained = 0
            for ($y = 0; $y -lt $template.Height; $y++) {
                for ($x = 0; $x -lt $template.Width; $x++) {
                    $pixel = $template.GetPixel($x, $y)
                    if ($pixel.R -eq 255 -and $pixel.G -eq 0 -and $pixel.B -eq 255) { continue }
                    if ($pixel.R -lt 200 -or $pixel.G -lt 200 -or $pixel.B -lt 200) { throw "$name retains unstable glyph edges" }
                    $retained++
                }
            }
            if ($retained -lt 500 -or $retained -ge $template.Width * $template.Height) { throw "$name invalid mask: $retained pixels" }
            $cases++
            Write-Output "PASS $name mask retained=$retained"
        }
    }
    finally { $template.Dispose() }
}

$generatedDirectory = Join-Path ([IO.Path]::GetTempPath()) ('gta-bunker-template-build-' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($generatedDirectory)
$names = @('bunker_buy', 'bunker_confirm')
try {
    & (Join-Path $PSScriptRoot 'build-mct-templates.ps1') -OutputDir $generatedDirectory -Name $names
    foreach ($name in $names) {
        $expected = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $assetDirectory ($name + '.png'))).Hash
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $generatedDirectory ($name + '.png'))).Hash
        if ($actual -ne $expected) { throw "Builder changes the checked-in mask: $name" }
        $cases++
        Write-Output "PASS builder reproduces $name $actual"
    }
}
finally {
    foreach ($name in $names) {
        $generated = Join-Path $generatedDirectory ($name + '.png')
        if ([IO.File]::Exists($generated)) { [IO.File]::Delete($generated) }
    }
    [IO.Directory]::Delete($generatedDirectory, $false)
}
Write-Output "PASS BunkerTemplates cases=$cases (saved pixels only)"
