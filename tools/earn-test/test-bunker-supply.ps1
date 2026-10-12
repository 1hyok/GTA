#Requires -Version 5.1
<#
Runs the production bunker page reader and bar sampler against saved pixels.
No desktop reads, windows, input, Main.ahk execution, or game processes.
The full fixture is the (653,367,940,33) Supplies Level region from the
2026-10-12 23:57:44 KST Steam recording (timed-21.png). It contains no account UI.
The label is its (11,1,192,30) text crop, retaining only min(R,G,B) >= 200 pixels.
#>
[CmdletBinding()]
param(
    [string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$tasks = Get-Content -LiteralPath (Join-Path $root 'Features\Earn\EarnTasks.ahk') -Raw -Encoding UTF8
$core = Get-Content -LiteralPath (Join-Path $root 'Features\Earn\EarnCore.ahk') -Raw -Encoding UTF8
$fixtureDirectory = Join-Path $PSScriptRoot 'test-earntasks-fixtures'
$captureDirectory = Join-Path $PSScriptRoot 'mct-capture-fixtures'
if (-not (Test-Path -LiteralPath $AhkPath -PathType Leaf)) { throw "AutoHotkey executable not found: $AhkPath" }

function Get-BunkerSourceFunction([string]$Source, [string]$Name) {
    $matches = [regex]::Matches($Source, ('(?ms)^' + [regex]::Escape($Name) + '\([^\r\n]*\) \{.*?^\}'))
    if ($matches.Count -ne 1) { throw "Expected one production function $Name, found $($matches.Count)" }
    return $matches[0].Value
}

Add-Type -AssemblyName System.Drawing
# Reuse the existing ImageSearch-compatible matcher without running its test suite.
if (-not ('EarnNightclubTemplateTest' -as [type])) {
    $matcherSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-nightclub-templates.ps1') -Raw
    $matcher = [regex]::Match($matcherSource, "(?s)Add-Type -ReferencedAssemblies System.Drawing @'\r?\n(.*?)\r?\n'@")
    if (-not $matcher.Success) { throw 'Existing saved-pixel matcher was not found' }
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition $matcher.Groups[1].Value
}

$full = [Drawing.Bitmap]::FromFile((Join-Path $fixtureDirectory 'bunker-supply-full.png'))
$partial = [Drawing.Bitmap]::FromFile((Join-Path $captureDirectory 'mansion-bunker-result.png'))
$label = [Drawing.Bitmap]::FromFile((Join-Path $root 'Images\Earn\1920x1080\bunker_supplies_label.png'))
$templateCases = 0
try {
    if ($full.Width -ne 940 -or $full.Height -ne 33 -or $label.Width -ne 192 -or $label.Height -ne 30) {
        throw 'The supplied regions changed their observed geometry'
    }
    $retained = 0
    for ($y = 0; $y -lt $label.Height; $y++) {
        for ($x = 0; $x -lt $label.Width; $x++) {
            $pixel = $label.GetPixel($x, $y)
            $observed = $full.GetPixel($x + 11, $y + 1)
            $bright = [Math]::Min($observed.R, [Math]::Min($observed.G, $observed.B)) -ge 200
            $expected = if ($bright) { $observed.ToArgb() } else { [Drawing.Color]::Magenta.ToArgb() }
            if ($pixel.ToArgb() -ne $expected) { throw "Label differs from saved white-text crop at $x,$y" }
            if ($bright) { $retained++ }
        }
    }
    if ($retained -lt 200 -or $retained -ge $label.Width * $label.Height) { throw "Invalid text mask: $retained pixels" }
    $templateCases++

    $reader = Get-BunkerSourceFunction $tasks 'EarnBunkerPageSupply'
    $areaMatch = [regex]::Match($reader, 'EarnUIReady\("bunker_supplies_label",\s*\[([0-9.,]+)\]')
    if (-not $areaMatch.Success) { throw 'Production Supplies Level search area missing' }
    $ratios = $areaMatch.Groups[1].Value.Split(',') | ForEach-Object { [double]::Parse($_, [Globalization.CultureInfo]::InvariantCulture) }
    $area = [Drawing.Rectangle]::FromLTRB([int][Math]::Round(1920*$ratios[0]), [int][Math]::Round(1080*$ratios[1]),
        [int][Math]::Round(1920*$ratios[2]), [int][Math]::Round(1080*$ratios[3]))
    $cropArea = [Drawing.Rectangle]::new($area.X-653, $area.Y-367, $area.Width, $area.Height)
    $foundX = 0; $foundY = 0
    $variation = [EarnNightclubTemplateTest]::MinimumVariation($full, $label, $cropArea, [ref]$foundX, [ref]$foundY)
    if ($variation -gt 40 -or $foundX -ne 11 -or $foundY -ne 1) { throw "Full supply label mismatch: $variation at $foundX,$foundY" }
    $templateCases++
    $variation = [EarnNightclubTemplateTest]::MinimumVariation($partial, $label, $area, [ref]$foundX, [ref]$foundY)
    if ($variation -gt 40 -or $foundX -ne 664 -or $foundY -ne 368) { throw "Partial supply label mismatch: $variation at $foundX,$foundY" }
    $templateCases++
    foreach ($name in @('mansion-bunker-pending.png', 'mansion-confirm2.png', 'mansion-bunker-code-fail.png', 'mansion-dj-list.png', 'mct-final-restored.png')) {
        $negative = [Drawing.Bitmap]::FromFile((Join-Path $captureDirectory $name))
        try {
            $variation = [EarnNightclubTemplateTest]::MinimumVariation($negative, $label, $area, [ref]$foundX, [ref]$foundY)
            if ($variation -le 60) { throw "Supplies label matched unrelated $name at tolerance $variation" }
            $templateCases++
        } finally { $negative.Dispose() }
    }

    $fullPixels = @(); $partialPixels = @()
    for ($x = 994; $x -le 1592; $x += 3) {
        $fullPixels += ('0x{0:X6}' -f ($full.GetPixel($x-653, 379-367).ToArgb() -band 0xFFFFFF))
        $partialPixels += ('0x{0:X6}' -f ($partial.GetPixel($x, 379).ToArgb() -band 0xFFFFFF))
    }
} finally { $full.Dispose(); $partial.Dispose(); $label.Dispose() }

$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global fullPixels := [__FULL_PIXELS__], partialPixels := [__PARTIAL_PIXELS__]
global supplyCase := [], pixelReads := 0, fixtureAborted := false, fixtureFocused := true, contextReads := 0
OnError(FixtureFailure)
; Name, pixel source, page context, label context, expected value, pixel count.
cases := [
    ["saved-full",fullPixels,true,true,1,200],
    ["saved-partial",partialPixels,true,true,0.43,200],
    ["empty",0x000000,true,true,0,200],
    ["white",0xFFFFFF,true,true,0,200],
    ["blue",0x395E91,true,true,0,200],
    ["green",0x399167,true,true,0,200],
    ["red",0xAA0000,true,true,0,200],
    ["missing-page",fullPixels,false,true,-1,0],
    ["missing-label",fullPixels,true,false,-1,0],
    ["pending",fullPixels,true,false,-1,0],
    ["abort-before",fullPixels,true,true,-1,0],
    ["focus-before",fullPixels,true,true,-1,0],
    ["abort-during-pixels",fullPixels,true,true,-1,200],
    ["focus-during-pixels",fullPixels,true,true,-1,200],
    ["focus-after-context",fullPixels,true,true,-1,0]]
for scenario in cases {
    supplyCase := scenario, pixelReads := 0, contextReads := 0
    fixtureAborted := supplyCase[1] = "abort-before", fixtureFocused := supplyCase[1] != "focus-before"
    result := EarnBunkerPageSupply()
    if (Abs(result - supplyCase[5]) > 0.000001 || pixelReads != supplyCase[6])
        throw Error("Bunker supply " supplyCase[1] ": result=" result ", pixels=" pixelReads)
}
FileAppend("PASS BunkerSupplyReader cases=" cases.Length "`n", "*")
ExitApp(0)
EarnUIReady(name, area := "") {
    global contextReads, fixtureFocused
    if (EarnAborted())
        return false
    if (name != "bunker_page" && name != "bunker_supplies_label")
        throw Error("Unexpected context " name)
    expected := name = "bunker_page" ? [0.15,0,0.35,0.12] : [0.34,0.34,0.46,0.37]
    if (!IsObject(area) || area.Length != 4)
        throw Error("Missing bounded context area")
    for index, value in expected
        if (area[index] != value)
            throw Error("Unexpected context area for " name)
    contextReads++
    if (supplyCase[1] = "focus-after-context" && contextReads = 2)
        fixtureFocused := false
    return name = "bunker_page" ? supplyCase[3] : supplyCase[4]
}
IsGTAActive() => fixtureFocused ? 1 : 0
WinGetClientPos(&x, &y, &w, &h, title) {
    if (title != "ahk_id 1")
        throw Error("Unexpected window query")
    x := 0, y := 0, w := 1920, h := 1080
}
CoordMode(target, relative) {
    if (target != "Pixel" || relative != "Screen")
        throw Error("Unexpected coordinate mode")
}
PixelGetColor(x, y) {
    global pixelReads, fixtureAborted, fixtureFocused
    if (y != 379 || x != 994 + pixelReads * 3 || pixelReads >= 200)
        throw Error("Pixel request outside observed supply bar: " x "," y)
    pixelReads++
    if (pixelReads = 100) {
        if (supplyCase[1] = "abort-during-pixels")
            fixtureAborted := true
        if (supplyCase[1] = "focus-during-pixels")
            fixtureFocused := false
    }
    return IsObject(supplyCase[2]) ? supplyCase[2][pixelReads] : supplyCase[2]
}
EarnAborted() => fixtureAborted || !fixtureFocused
FixtureFailure(failure, *) {
    FileAppend("FAIL BunkerSupplyReader: " failure.Message "`n", "**")
    ExitApp(1)
}
'@
$driver = $driver.Replace('__FULL_PIXELS__', ($fullPixels -join ',')).Replace('__PARTIAL_PIXELS__', ($partialPixels -join ','))
$driver += "`n" + (Get-BunkerSourceFunction $tasks 'EarnBunkerPageSupply')
$driver += "`n" + (Get-BunkerSourceFunction $core 'EarnBarFill')
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $AhkPath
$info.Arguments = '/ErrorStdOut /CP65001 *'
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardInput = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
$info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
$previousEncoding = [Console]::InputEncoding
$testProcess = $null
try {
    [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
    $testProcess = [Diagnostics.Process]::Start($info)
    $testProcess.StandardInput.WriteLine($driver)
    $testProcess.StandardInput.Close()
    if (-not $testProcess.WaitForExit(10000)) {
        $testProcess.Kill()
        $testProcess.WaitForExit()
        throw 'Bunker supply reader timed out after 10 seconds'
    }
    $stdout = $testProcess.StandardOutput.ReadToEnd().Trim()
    $stderr = $testProcess.StandardError.ReadToEnd().Trim()
    if ($testProcess.ExitCode -ne 0 -or $stderr -ne '' -or $stdout -ne 'PASS BunkerSupplyReader cases=15') {
        throw "Bunker supply reader failed (exit=$($testProcess.ExitCode))`nstdout: $stdout`nstderr: $stderr"
    }
    Write-Output "PASS BunkerSupplyTemplate cases=$templateCases"
    Write-Output $stdout
    Write-Output "PASS BunkerSupply cases=$($templateCases+15)"
} finally {
    if ($null -ne $testProcess) {
        if (-not $testProcess.HasExited) { $testProcess.Kill(); $testProcess.WaitForExit() }
        $testProcess.Dispose()
    }
    [Console]::InputEncoding = $previousEncoding
}
