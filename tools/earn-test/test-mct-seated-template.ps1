#Requires -Version 5.1
<#
Static regression for the mansion MCT prompt and the template builder.
The saved fixtures contain only MCT prompt/title crops. No account name,
desktop notification or game balance is included. No windows or input.
#>
[CmdletBinding()]
param([string]$AdditionalSeatedSamplePath = '')
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$assetDirectory = Join-Path $root 'Images\Earn\1920x1080'
$evidence = Join-Path $root 'docs\evidence\2026-09-27-mct'
$cases = 0
. (Join-Path $PSScriptRoot 'compare-png-pixels.ps1')

$core = [IO.File]::ReadAllText((Join-Path $root 'Features\Earn\EarnCore.ahk'))
if ($core -notmatch 'TemplateSeen\("Earn",\s*"mct_sit_hdr_alt"[^\r\n]*TemplateAt\("Earn",\s*"mct_sit_hdr_alt_bg"') {
    throw 'Production mct_sit detection does not consume the alternate HDR text/background pair'
}
$cases++
Write-Output 'PASS production mct_sit detection consumes alternate HDR text/background pair'

# Also runs the existing nightclub positive/negative regression. Its public
# pixel matcher implements the same per-channel ImageSearch comparison.
& (Join-Path $PSScriptRoot 'test-nightclub-templates.ps1')
$screen = [IO.File]::ReadAllText((Join-Path $root 'Core\Screen.ahk'))
$atBody = [regex]::Match($screen, '(?s)TemplateAt\(folder,.*?\n\}').Value
if ($atBody -notmatch 'Min\(x \+ cw - 1, cx \+ cw - 1\)') {
    throw 'TemplateAt search width clips the 536px MCT HDR title background to 401px'
}
if ($atBody -notmatch 'return fx = x && fy = y') { throw 'TemplateAt must reject matches shifted from the supplied origin' }
$cases++
Write-Output 'PASS production TemplateAt admits wide backgrounds and keeps exact-origin guard'
$hdrSitBound = 40
if ($core -match 'mct_sit_hdr_alt"[^\r\n]*Max\(variation,\s*(\d+)\)') { $hdrSitBound = [int]$Matches[1] }
$hdrPhoneBound = 40
if ($core -match 'name = "ph_joblist_sel" \? Max\(variation,\s*(\d+)\)') { $hdrPhoneBound = [int]$Matches[1] }
foreach ($spec in @(
    @('mct-sit-hdr-bright-20261008.png','mct_sit_hdr_bright',240,48,40,0,0),
    @('phone-joblist-hdr-bright-20261008.png','ph_joblist_sel_live',288,77,$hdrPhoneBound,96,18)
)) {
    $bright = [Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot ('mct-template-fixtures\'+$spec[0])))
    $mask = [Drawing.Bitmap]::FromFile((Join-Path $assetDirectory ($spec[1]+'.png')))
    try {
        $x=0; $y=0
        $difference = [EarnNightclubTemplateTest]::MinimumVariation($bright,$mask,(New-Object Drawing.Rectangle 0,0,$spec[2],$spec[3]),[ref]$x,[ref]$y)
        if ($difference -gt $spec[4] -or $x -ne $spec[5] -or $y -ne $spec[6]) { throw "Bright HDR $($spec[1]) miss variation=$difference bound=$($spec[4]) at $x,$y" }
        $cases++
        Write-Output "PASS bright HDR $($spec[1]) variation=$difference bound=$($spec[4]) at $x,$y"
        $blank = New-Object Drawing.Bitmap $spec[2],$spec[3]
        $g = [Drawing.Graphics]::FromImage($blank)
        try {
            $g.Clear([Drawing.Color]::White)
            $negative = [EarnNightclubTemplateTest]::MinimumVariation($blank,$mask,(New-Object Drawing.Rectangle 0,0,$spec[2],$spec[3]),[ref]$x,[ref]$y)
            if ($negative -le $spec[4]) { throw "Bright blank screen matched $($spec[1]) variation=$negative" }
            $cases++
            Write-Output "PASS bright blank rejects $($spec[1]) variation=$negative"
        } finally { $g.Dispose(); $blank.Dispose() }
        if ($spec[1] -eq 'mct_sit_hdr_bright') {
            if ($core -notmatch 'TemplateSeen\("Earn",\s*"mct_sit_hdr_bright"[^\r\n]*TemplateAt\("Earn",\s*"mct_sit_hdr_bright_bg"') { throw 'Bright HDR masks are not consumed together by production' }
            $bg = [Drawing.Bitmap]::FromFile((Join-Path $assetDirectory 'mct_sit_hdr_bright_bg.png'))
            try {
                $difference = [EarnNightclubTemplateTest]::MinimumVariation($bright,$bg,(New-Object Drawing.Rectangle 0,0,240,48),[ref]$x,[ref]$y)
                if ($difference -gt 90 -or $x -ne 0 -or $y -ne 0) { throw "Bright HDR background miss variation=$difference at $x,$y" }
                $cases++
                Write-Output "PASS bright HDR dark-background guard variation=$difference"
                $retained=0
                for ($by=0; $by -lt $bg.Height; $by++) {
                    for ($bx=0; $bx -lt $bg.Width; $bx++) {
                        if ($bg.GetPixel($bx,$by).ToArgb() -ne [Drawing.Color]::Magenta.ToArgb()) { $retained++ }
                    }
                }
                if ($retained -lt 200) { throw "Insufficient bright HDR dark-background pixels: $retained" }
                foreach ($negativeName in @('mct-final-restored.png','mansion-dj-after.png','mansion-bunker-result.png')) {
                    $other = [Drawing.Bitmap]::FromFile((Join-Path $evidence $negativeName))
                    try {
                        $negative = [EarnNightclubTemplateTest]::MinimumVariation($other,$mask,(New-Object Drawing.Rectangle 0,0,576,108),[ref]$x,[ref]$y)
                        if ($negative -le 40) { throw "Bright HDR sit prompt matched unrelated screen $negativeName" }
                        $cases++
                        Write-Output "PASS bright HDR sit rejects $negativeName variation=$negative"
                    } finally { $other.Dispose() }
                }
            } finally { $bg.Dispose() }
        }
    } finally { $bright.Dispose(); $mask.Dispose() }
}
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
    $sitTemplate = [Drawing.Bitmap]::FromFile((Join-Path $assetDirectory 'mct_sit_hdr.png'))
    $sitFixture = [Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'mct-template-fixtures\mct-sit-hdr-live.png'))
    try {
        if ($sitTemplate.Width -ne 240 -or $sitTemplate.Height -ne 48) { throw 'Unexpected HDR stand-at-MCT prompt dimensions' }
        $x=0; $y=0
        $positiveVariation = [EarnNightclubTemplateTest]::MinimumVariation($sitFixture,$sitTemplate,(New-Object Drawing.Rectangle 0,0,240,48),[ref]$x,[ref]$y)
        if ($positiveVariation -gt 40 -or $x -ne 0 -or $y -ne 0) { throw "Live HDR sit prompt did not match at expected offset: $positiveVariation at $x,$y" }
        $cases++
        Write-Output "PASS live HDR stand-at-MCT prompt variation=$positiveVariation at $x,$y"
        $sitBackground = [Drawing.Bitmap]::FromFile((Join-Path $assetDirectory 'mct_sit_hdr_bg.png'))
        try {
            $x=0; $y=0
            $backgroundVariation = [EarnNightclubTemplateTest]::MinimumVariation($sitFixture,$sitBackground,(New-Object Drawing.Rectangle 0,0,240,48),[ref]$x,[ref]$y)
            if ($backgroundVariation -gt 40 -or $x -ne 0 -or $y -ne 0) { throw "HDR MCT prompt background did not match at expected offset: $backgroundVariation at $x,$y" }
            $cases++
            Write-Output "PASS HDR MCT prompt background positive variation=$backgroundVariation at $x,$y"
            $glyphs = 0; $backgroundPixels = 0
            for ($y=0; $y -lt 48; $y++) {
                for ($x=0; $x -lt 240; $x++) {
                    $p = $sitTemplate.GetPixel($x,$y)
                    if ($p.R -ne 255 -or $p.G -ne 0 -or $p.B -ne 255) {
                        $observed = $sitFixture.GetPixel($x,$y)
                        $redDiff = [Math]::Abs([int]$p.R - [int]$observed.R)
                        $greenDiff = [Math]::Abs([int]$p.G - [int]$observed.G)
                        $blueDiff = [Math]::Abs([int]$p.B - [int]$observed.B)
                        if ($redDiff -gt 1 -or $greenDiff -gt 1 -or $blueDiff -gt 1) { throw 'HDR prompt mask differs from observed glyph pixels' }
                        $glyphs++
                    }
                    $b = $sitBackground.GetPixel($x,$y)
                    if ($b.R -ne 255 -or $b.G -ne 0 -or $b.B -ne 255) { $backgroundPixels++ }
                }
            }
            if ($glyphs -lt 200 -or $backgroundPixels -lt 200) { throw "Insufficient HDR prompt evidence glyphs=$glyphs background=$backgroundPixels" }
            $cases++
            Write-Output "PASS HDR stand-at-MCT prompt masks glyphs=$glyphs background=$backgroundPixels"
        } finally { $sitBackground.Dispose() }
        foreach ($name in @('mct-final-restored.png','mansion-dj-after.png','mansion-bunker-result.png')) {
            $source = [Drawing.Bitmap]::FromFile((Join-Path $evidence $name))
            try {
                $x=0; $y=0
                $variation = [EarnNightclubTemplateTest]::MinimumVariation($source,$sitTemplate,(New-Object Drawing.Rectangle 0,0,576,108),[ref]$x,[ref]$y)
                if ($variation -le 40) { throw "HDR sit prompt matched unrelated MCT screen $name at $x,$y" }
                $cases++
                Write-Output "PASS HDR sit prompt rejects $name variation=$variation"
            } finally { $source.Dispose() }
        }
    } finally { $sitTemplate.Dispose(); $sitFixture.Dispose() }
    $sitAltTemplate = [Drawing.Bitmap]::FromFile((Join-Path $assetDirectory 'mct_sit_hdr_alt.png'))
    $sitAltFixture = [Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'mct-template-fixtures\mct-sit-hdr-live-20261008.png'))
    try {
        if ($sitAltTemplate.Width -ne 240 -or $sitAltTemplate.Height -ne 48) { throw 'Unexpected alternate HDR stand-at-MCT prompt dimensions' }
        $x=0; $y=0
        $variation = [EarnNightclubTemplateTest]::MinimumVariation($sitAltFixture,$sitAltTemplate,(New-Object Drawing.Rectangle 0,0,240,48),[ref]$x,[ref]$y)
        if ($variation -gt 40 -or $x -ne 0 -or $y -ne 0) { throw "Alternate HDR sit prompt missed current live sample: $variation at $x,$y" }
        $cases++
        Write-Output "PASS alternate live HDR stand-at-MCT prompt variation=$variation at $x,$y"
        $legacyTemplate = [Drawing.Bitmap]::FromFile((Join-Path $assetDirectory 'mct_sit_hdr.png'))
        try {
            $legacyVariation = [EarnNightclubTemplateTest]::MinimumVariation($sitAltFixture,$legacyTemplate,(New-Object Drawing.Rectangle 0,0,240,48),[ref]$x,[ref]$y)
            if ($legacyVariation -le 40) { throw "Current live sample no longer reproduces legacy HDR template miss: $legacyVariation" }
            $cases++
            Write-Output "PASS current live sample reproduces legacy HDR template miss variation=$legacyVariation"
        } finally { $legacyTemplate.Dispose() }
        $sitAltBackground = [Drawing.Bitmap]::FromFile((Join-Path $assetDirectory 'mct_sit_hdr_alt_bg.png'))
        try {
            $x=0; $y=0
            $variation = [EarnNightclubTemplateTest]::MinimumVariation($sitAltFixture,$sitAltBackground,(New-Object Drawing.Rectangle 0,0,240,48),[ref]$x,[ref]$y)
            if ($variation -gt 40 -or $x -ne 0 -or $y -ne 0) { throw "Alternate HDR sit background missed current live sample: $variation at $x,$y" }
            $cases++
            Write-Output "PASS alternate HDR MCT prompt background variation=$variation at $x,$y"
        } finally { $sitAltBackground.Dispose() }
        foreach ($name in @('mct-final-restored.png','mansion-dj-after.png','mansion-bunker-result.png')) {
            $source = [Drawing.Bitmap]::FromFile((Join-Path $evidence $name))
            try {
                $x=0; $y=0
                $variation = [EarnNightclubTemplateTest]::MinimumVariation($source,$sitAltTemplate,(New-Object Drawing.Rectangle 0,0,576,108),[ref]$x,[ref]$y)
                if ($variation -le $hdrSitBound) { throw "Alternate HDR sit prompt matched unrelated MCT screen $name at $x,$y" }
                $cases++
                Write-Output "PASS alternate HDR sit prompt rejects $name variation=$variation"
            } finally { $source.Dispose() }
        }
    } finally { $sitAltTemplate.Dispose(); $sitAltFixture.Dispose() }
    $seatedHdr = [Drawing.Bitmap]::FromFile((Join-Path $assetDirectory 'mct_seated_hdr.png'))
    $seatedHdrBg = [Drawing.Bitmap]::FromFile((Join-Path $assetDirectory 'mct_seated_hdr_bg.png'))
    $seatedFixture = [Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'mct-template-fixtures\mct-seated-hdr-current.png'))
    try {
        if ($seatedHdr.Width -ne 240 -or $seatedHdr.Height -ne 24) { throw 'Unexpected HDR seated MCT prompt dimensions' }
        foreach ($pair in @(@($seatedHdr,'text'),@($seatedHdrBg,'background'))) {
            $x=0; $y=0
            $variation = [EarnNightclubTemplateTest]::MinimumVariation($seatedFixture,$pair[0],(New-Object Drawing.Rectangle 0,0,240,24),[ref]$x,[ref]$y)
            if ($variation -gt 40 -or $x -ne 0 -or $y -ne 0) { throw "HDR seated MCT $($pair[1]) missed observed prompt: $variation at $x,$y" }
            $cases++
            Write-Output "PASS HDR seated MCT $($pair[1]) variation=$variation"
        }
        foreach ($name in @('mct-final-restored.png','mansion-dj-after.png','mansion-bunker-result.png')) {
            $source = [Drawing.Bitmap]::FromFile((Join-Path $evidence $name))
            try {
                $x=0; $y=0
                $variation = [EarnNightclubTemplateTest]::MinimumVariation($source,$seatedHdr,(New-Object Drawing.Rectangle 0,0,576,108),[ref]$x,[ref]$y)
                if ($variation -le 40) { throw "HDR seated MCT matched unrelated screen $name at $x,$y" }
                $cases++
                Write-Output "PASS HDR seated MCT rejects $name variation=$variation"
            } finally { $source.Dispose() }
        }
    } finally { $seatedHdr.Dispose(); $seatedHdrBg.Dispose(); $seatedFixture.Dispose() }
    $titleHdr = [Drawing.Bitmap]::FromFile((Join-Path $assetDirectory 'mct_title_hdr.png'))
    $titleHdrBg = [Drawing.Bitmap]::FromFile((Join-Path $assetDirectory 'mct_title_hdr_bg.png'))
    $titleFixture = [Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'mct-template-fixtures\mct-title-hdr-current.png'))
    try {
        if ($titleHdr.Width -ne 536 -or $titleHdr.Height -ne 39) { throw 'Unexpected HDR MCT title dimensions' }
        foreach ($pair in @(@($titleHdr,'text'),@($titleHdrBg,'background'))) {
            $x=0; $y=0
            $variation = [EarnNightclubTemplateTest]::MinimumVariation($titleFixture,$pair[0],(New-Object Drawing.Rectangle 0,0,536,39),[ref]$x,[ref]$y)
            if ($variation -gt 40 -or $x -ne 0 -or $y -ne 0) { throw "HDR MCT title $($pair[1]) missed observed screen: $variation at $x,$y" }
            $cases++
            Write-Output "PASS HDR MCT title $($pair[1]) variation=$variation"
        }
        foreach ($name in @('mct-final-restored.png','mansion-dj-after.png','mansion-bunker-result.png')) {
            $source = [Drawing.Bitmap]::FromFile((Join-Path $evidence $name))
            try {
                $x=0; $y=0
                $variation = [EarnNightclubTemplateTest]::MinimumVariation($source,$titleHdr,(New-Object Drawing.Rectangle 576,0,768,108),[ref]$x,[ref]$y)
                if ($variation -le 40) { throw "HDR MCT title matched unrelated screen $name at $x,$y" }
                $cases++
                Write-Output "PASS HDR MCT title rejects $name variation=$variation"
            } finally { $source.Dispose() }
        }
    } finally { $titleHdr.Dispose(); $titleHdrBg.Dispose(); $titleFixture.Dispose() }
    if ($AdditionalSeatedSamplePath) {
        $source = [Drawing.Bitmap]::FromFile([IO.Path]::GetFullPath($AdditionalSeatedSamplePath))
        try { Assert-SeatedMatch $source $true ([IO.Path]::GetFileName($AdditionalSeatedSamplePath)) }
        finally { $source.Dispose() }
    }
}
finally { $template.Dispose() }

$generatedDirectory = Join-Path ([IO.Path]::GetTempPath()) ('gta-mct-template-build-' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($generatedDirectory)
$names = @('nc_dj_menu', 'nc_home', 'mct_seated_mansion', 'mct_sit_hdr', 'mct_sit_hdr_alt', 'mct_sit_hdr_bright', 'mct_seated_hdr', 'mct_title_hdr')
try {
    & (Join-Path $PSScriptRoot 'build-mct-templates.ps1') -OutputDir $generatedDirectory -Name $names
    foreach ($name in $names) {
        $outputs = if ($name -in @('mct_sit_hdr','mct_sit_hdr_alt','mct_sit_hdr_bright','mct_seated_hdr','mct_title_hdr')) { @($name,($name+'_bg')) } else { @($name) }
        foreach ($outputName in $outputs) {
            $diff = Compare-PngPixels (Join-Path $assetDirectory ($outputName + '.png')) (Join-Path $generatedDirectory ($outputName + '.png'))
            if ($diff) { throw "Builder changes the checked-in stable mask: $outputName ($diff)" }
            $cases++
            Write-Output "PASS builder reproduces $outputName"
        }
    }
}
finally {
    foreach ($name in $names) {
        $outputs = if ($name -in @('mct_sit_hdr','mct_sit_hdr_alt','mct_sit_hdr_bright','mct_seated_hdr','mct_title_hdr')) { @($name,($name+'_bg')) } else { @($name) }
        foreach ($outputName in $outputs) {
            $generated = Join-Path $generatedDirectory ($outputName + '.png')
            if ([IO.File]::Exists($generated)) { [IO.File]::Delete($generated) }
        }
    }
    [IO.Directory]::Delete($generatedDirectory, $false)
}
Write-Output "PASS MCTSeatedTemplate cases=$cases (no game input or windows)"
