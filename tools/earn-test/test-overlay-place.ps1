#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe",
    [string]$BaselineRevision = ''
)
$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '..\..'
if ($BaselineRevision) {
    $source = (& git -C $root show ($BaselineRevision + ':Features/Overlay.ahk')) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read requested baseline' }
} else {
    $source = Get-Content (Join-Path $root 'Features\Overlay.ahk') -Raw -Encoding UTF8
}
$production = ''
foreach ($name in @('OverlayPlace', 'OverlayHitsDetection', 'OverlayDetectionZones')) {
    $function = [regex]::Match($source, ('(?ms)^' + $name + '\([^\r\n]*\) \{.*?^\}')).Value
    if (-not $function -and $name -ne 'OverlayDetectionZones') { throw "Missing production function: $name" }
    $production += $function + "`n"
}
if ($production -match 'DllCall\(|WinGet|ShowWindow|WinActivate|\bRun\(|\bSend\(|\bGui\(') {
    throw 'Native side effect remains in geometry fixture'
}
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global config := Map("Settings", Map("OverlayXPct", 100, "OverlayYPct", 88.5)), n := 0
@PRODUCTION@
try {
    Check(OverlayPlace(0, 0, 1920, 1080, 262, 59, &x, &y), "short overlay fits")
    Check(x = 1658 && y = 956, "existing short bottom-right position stays")
    Check(OverlayPlace(0, 0, 1920, 1080, 262, 76, &x, &y), "two-line overlay fits")
    Check(x = 1658 && y = 939, "growing status shifts up only 17 pixels, not to y194")
    CheckSafe(x, y, 262, 76, 1920, 1080, "two-line safety")
    Check(OverlayPlace(0, 0, 1920, 1080, 262, 220, &x, &y), "long notices fit")
    Check(x = 1658 && y = 795, "long notices remain right and adjacent to protected bottom area")
    CheckSafe(x, y, 262, 220, 1920, 1080, "long notice safety")
    Check(OverlayPlace(0, 0, 1920, 1080, 262, 500, &x, &y), "very tall notice fits")
    Check(x = 1658 && y = 515, "tall notice keeps right edge while avoiding protected bottom area")
    CheckSafe(x, y, 262, 500, 1920, 1080, "very tall notice safety")
    Check(OverlayPlace(0, 0, 1920, 1080, 262, 1040, &x, &y), "almost full-height notice fits")
    Check(x = 1447 && y = 40, "leftward alternative found when no vertical space remains on right edge")
    CheckSafe(x, y, 262, 1040, 1920, 1080, "almost full-height notice safety")
    Check(OverlayPlace(-2560, 120, 1920, 1080, 262, 76, &x, &y), "negative monitor origin fits")
    Check(x = -902 && y = 1059, "client origin is added once")
    Check(config["Settings"]["OverlayXPct"] = 100 && config["Settings"]["OverlayYPct"] = 88.5, "placement never rewrites preference")

    config["Settings"]["OverlayXPct"] := 98, config["Settings"]["OverlayYPct"] := 18
    Check(OverlayPlace(0, 0, 1920, 1080, 262, 76, &x, &y) && x = 1620 && y = 194, "safe default stays unchanged")
    config["Settings"]["OverlayXPct"] := 50, config["Settings"]["OverlayYPct"] := 80
    Check(OverlayPlace(0, 0, 1920, 1080, 262, 76, &x, &y) && x = 698 && y = 864, "other safe preference stays unchanged")
    config["Settings"]["OverlayXPct"] := 5, config["Settings"]["OverlayYPct"] := 0
    Check(OverlayPlace(0, 0, 1920, 1080, 262, 76, &x, &y) && x = 0 && y = 250, "top-left collision moves to closest safe boundary")
    config["Settings"]["OverlayXPct"] := 50, config["Settings"]["OverlayYPct"] := 50
    Check(OverlayPlace(0, 0, 1920, 1080, 262, 76, &x, &y) && x = 698 && y = 821, "center collision resolves without obscuring center")
    Check(!OverlayPlace(0, 0, 320, 200, 262, 76, &x, &y), "fully protected client hides overlay")
    Check(!OverlayPlace(0, 0, 1920, 1080, 1921, 76, &x, &y), "too wide hides rather than overflowing")
    Check(!OverlayPlace(0, 0, 1920, 1080, 262, 1081, &x, &y), "too tall hides rather than overflowing")
    Check(!OverlayPlace(0, 0, 0, 1080, 262, 76, &x, &y), "zero client width rejected")
    Check(!OverlayPlace(0, 0, 1920, 1080, 0, 76, &x, &y), "zero overlay width rejected")

    ; The exact existing detection rectangles and edge-contact semantics remain protected.
    Check(!OverlayHitsDetection(1658, 939, 262, 76, 1920, 1080), "touching bottom guard is safe")
    Check(OverlayHitsDetection(1658, 940, 262, 76, 1920, 1080), "one pixel into bottom guard rejected")
    Check(OverlayHitsDetection(0, 249, 20, 20, 1920, 1080), "top-left guard protected")
    Check(OverlayHitsDetection(480, 151, 20, 20, 1920, 1080), "center guard protected")
    Check(!OverlayHitsDetection(1440, 251, 20, 20, 1920, 1080), "right of center boundary is safe")
    for screen in [[1920, 1080], [1280, 720], [2560, 1600]] {
        for xp in [-10, 5, 50, 98, 100, 110] {
            for yp in [-10, 0, 18, 50, 88.5, 100, 110] {
                for height in [59, 76, 220] {
                    config["Settings"]["OverlayXPct"] := xp, config["Settings"]["OverlayYPct"] := yp
                    fits := OverlayPlace(0, 0, screen[1], screen[2], 262, height, &x, &y)
                    Check(fits, "grid case has a valid placement")
                    CheckSafe(x, y, 262, height, screen[1], screen[2], "grid placement safety")
                    Check(config["Settings"]["OverlayXPct"] = xp && config["Settings"]["OverlayYPct"] = yp, "grid preference preserved")
                }
            }
        }
    }
    FileAppend("PASS OverlayPlace: " n " cases; no window or game input`n", "*")
    ExitApp(0)
} catch as e {
    FileAppend("FAIL " e.Message "`n", "**")
    ExitApp(1)
}
Check(ok, message) {
    global n
    n += 1
    if (!ok)
        throw Error(message)
}
CheckSafe(x, y, w, h, cw, ch, message) {
    Check(x >= 0 && y >= 0 && x + w <= cw && y + h <= ch, message " within screen")
    Check(!OverlayHitsDetection(x, y, w, h, cw, ch), message " leaves every detection zone clear")
}
'@
$driver = $driver.Replace('@PRODUCTION@', $production)
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $AhkPath
$info.Arguments = '/ErrorStdOut /CP65001 *'
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardInput = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$previous = [Console]::InputEncoding
[Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
try {
    $process = [Diagnostics.Process]::Start($info)
    try {
        $process.StandardInput.WriteLine($driver)
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(10000)) { $process.Kill(); throw 'Geometry fixture timed out' }
        $stdout = $process.StandardOutput.ReadToEnd().Trim()
        $stderr = $process.StandardError.ReadToEnd().Trim()
        if ($process.ExitCode -ne 0 -or $stderr -or $stdout -notmatch '^PASS OverlayPlace: \d+ cases; no window or game input$') {
            throw "Geometry fixture exit=$($process.ExitCode) stdout=$stdout stderr=$stderr"
        }
        $stdout
    } finally { $process.Dispose() }
} finally { [Console]::InputEncoding = $previous }
