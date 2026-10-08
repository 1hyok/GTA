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
. (Join-Path $PSScriptRoot 'compare-png-pixels.ps1')

# Reuse the existing ImageSearch-compatible per-channel/magenta matcher.
& (Join-Path $PSScriptRoot 'test-nightclub-templates.ps1') | Out-Null
# HDR dashboard card titles retain only bright glyph interiors and require
# the corresponding background at the same origin. Samples exclude overlays.
if ($core -notmatch 'name = "mct_bunker_card" \|\| name = "mct_nightclub_card"' -or $core -notmatch 'TemplateAt\("Earn", name "_hdr_bg", fx, fy, 40\)') { throw 'HDR card pair is not consumed by production at the original tolerance' }
foreach ($card in @(@('bunker',830,227,260,26),@('nightclub',470,227,106,25))) {
    $name='mct_'+$card[0]+'_card'
    $fixture=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot ('mct-template-fixtures\mct-'+$card[0]+'-card-hdr-20261008.png')))
    $legacy=[Drawing.Bitmap]::FromFile((Join-Path $assetDirectory ($name+'.png')))
    $text=[Drawing.Bitmap]::FromFile((Join-Path $assetDirectory ($name+'_hdr.png')))
    $background=[Drawing.Bitmap]::FromFile((Join-Path $assetDirectory ($name+'_hdr_bg.png')))
    $area=New-Object Drawing.Rectangle 0,0,$card[3],$card[4]
    try {
        $x=0;$y=0
        $old=[EarnNightclubTemplateTest]::MinimumVariation($fixture,$legacy,$area,[ref]$x,[ref]$y)
        if ($old -le 40) { throw "$name fixture no longer reproduces the legacy miss" }
        $cases++
        foreach ($mask in @($text,$background)) {
            $difference=[EarnNightclubTemplateTest]::MinimumVariation($fixture,$mask,$area,[ref]$x,[ref]$y)
            if ($difference -gt 40 -or $x -ne 0 -or $y -ne 0) { throw "$name HDR pair miss $difference at $x,$y" }
            $cases++
        }
        foreach ($color in @([Drawing.Color]::White,[Drawing.Color]::Black,[Drawing.Color]::FromArgb(90,100,110))) {
            $blank=New-Object Drawing.Bitmap $card[3],$card[4]
            $g=[Drawing.Graphics]::FromImage($blank)
            try {
                $g.Clear($color)
                $a=[EarnNightclubTemplateTest]::MinimumVariation($blank,$text,$area,[ref]$x,[ref]$y)
                $b=[EarnNightclubTemplateTest]::MinimumVariation($blank,$background,$area,[ref]$x,[ref]$y)
                if ($a -le 40 -and $b -le 40) { throw "$name matched blank $color" }
                $cases++
            } finally { $g.Dispose();$blank.Dispose() }
        }
        foreach ($negative in @('mansion-dj-list.png','mansion-bunker-result.png','mct-final-restored.png')) {
            $image=[Drawing.Bitmap]::FromFile((Join-Path $evidence $negative))
            try {
                $ratios=if($card[0] -eq 'bunker'){@(0.42,0.20,0.58,0.25)}else{@(0.23,0.20,0.32,0.25)}
                $search=New-Object Drawing.Rectangle ([int][Math]::Round(1920*$ratios[0])),216,([int][Math]::Round(1920*$ratios[2])-[int][Math]::Round(1920*$ratios[0])),54
                $a=[EarnNightclubTemplateTest]::MinimumVariation($image,$text,$search,[ref]$x,[ref]$y)
                $bx=0;$by=0
                $b=[EarnNightclubTemplateTest]::MinimumVariation($image,$background,(New-Object Drawing.Rectangle $x,$y,$card[3],$card[4]),[ref]$bx,[ref]$by)
                if($a -le 40 -and $b -le 40){throw "$name matched unrelated $negative"}
                $cases++
            } finally { $image.Dispose() }
        }
        Write-Output "PASS HDR card $name legacy=$old, paired match and blank/unrelated rejection"
    } finally {$fixture.Dispose();$legacy.Dispose();$text.Dispose();$background.Dispose()}
}
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
        # EarnSeen 이 구매 버튼만 오차 100까지 본다(가격에 따라 글자 위치가 1~2px 밀림).
        $limit = if ($name -eq 'bunker_buy') { 100 } else { 40 }
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
                if (($variation -le $limit) -ne $pair[1]) {
                    throw "$name $([IO.Path]::GetFileName($pair[0])) expected=$($pair[1]) minVariation=$variation at $x,$y"
                }
                $cases++
                Write-Output "PASS $name $([IO.Path]::GetFileName($pair[0])) found=$($pair[1]) minVariation=$variation at $x,$y"
            }
            finally { $source.Dispose() }
        }
        # Raw $75,000 glyphs from 2026-10-03 bunker-fix-resupply-raw.png and
        # bunker-fix-confirm-raw.png, restored at the observed crop positions.
        # $60,000 is a 2026-10-04 03:20 recording frame (lossy; the button text sits 2px left).
        # Store only these tiny crops, excluding player names and balances.
        foreach ($fixture in @(
            @('bunker-buy-75000.png', 'bunker_buy', 802, 769, 165, 29),
            @('bunker-buy-60000.png', 'bunker_buy', 800, 769, 165, 29),
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
                if (($variation -le $limit) -ne $expected -or ($expected -and ($x -ne $fixture[2] -or $y -ne $fixture[3]))) {
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
$names = @('bunker_buy', 'bunker_confirm', 'mct_bunker_card_hdr', 'mct_nightclub_card_hdr')
try {
    & (Join-Path $PSScriptRoot 'build-mct-templates.ps1') -OutputDir $generatedDirectory -Name $names
    foreach ($name in $names) {
        foreach ($name in $(if ($name.EndsWith('_hdr')) { @($name,($name+'_bg')) } else { @($name) })) {
        $diff = Compare-PngPixels (Join-Path $assetDirectory ($name + '.png')) (Join-Path $generatedDirectory ($name + '.png'))
        if ($diff) { throw "Builder changes the checked-in mask: $name ($diff)" }
        $cases++
        Write-Output "PASS builder reproduces $name"
        }
    }
}
finally {
    foreach ($name in $names) {
        foreach ($name in $(if ($name.EndsWith('_hdr')) { @($name,($name+'_bg')) } else { @($name) })) {
        $generated = Join-Path $generatedDirectory ($name + '.png')
        if ([IO.File]::Exists($generated)) { [IO.File]::Delete($generated) }
        }
    }
    [IO.Directory]::Delete($generatedDirectory, $false)
}
Write-Output "PASS BunkerTemplates cases=$cases (saved pixels only)"
