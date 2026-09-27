#Requires -Version 5.1
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$source = Get-Content (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnCore.ahk') -Raw -Encoding UTF8
$functions = @('EarnBlipFromPixels','EarnComputerBlipKind','EarnBlipPixelLevel','ATan2Deg') | ForEach-Object {
    $match = [regex]::Match($source, ('(?ms)^' + $_ + '\([^\r\n]*\) \{.*?^\}'))
    if (!$match.Success) { throw "Production function missing: $_" }
    $match.Value
}
$fixtureDir = Join-Path $PSScriptRoot 'test-earnblip-fixtures'
$scratch = Join-Path $env:TEMP ('earnblip-offline-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
# Source screenshot coordinates. False cases ensure one computer type cannot substitute for another.
$cases = @(
    @('arcade-stair-stop1','mct',1,221.5,980.5), @('arcade-stair-stop1','laptop',0,0,0),
    @('arcade-stair-mct-current','mct',1,112.5,983), @('arcade-stair-mct-current','laptop',1,210,901),
    @('arcade-mct-feedback-state','mct',0,0,0), @('arcade-mct-feedback-state','laptop',1,147,1001),
    @('arcade-route-spawn','mct',0,0,0), @('arcade-route-spawn','laptop',1,237,947),
    @('clipped-mct','mct',0,0,0), @('clipped-mct','laptop',0,0,0),
    @('screen-only','mct',0,0,0), @('screen-only','laptop',0,0,0),
    @('whole-edge-mct','mct',1,32.5,924.5,1), @('whole-edge-mct','laptop',0,0,0),
    @('whole-edge-laptop','laptop',1,33,935,1), @('whole-edge-laptop','mct',0,0,0)
)
$previousEncoding = [Console]::InputEncoding
try {
    foreach ($name in ($cases | ForEach-Object { $_[0] } | Select-Object -Unique)) {
        if ($name -like 'whole-edge-*') {
            # Translate a complete real icon to the minimap edge; no game input or invented sprite.
            $isMct = $name -eq 'whole-edge-mct'
            $original = if ($isMct) { 'arcade-stair-stop1' } else { 'arcade-route-spawn' }
            $sourceRect = if ($isMct) { New-Object Drawing.Rectangle 190,116,26,29 } else { New-Object Drawing.Rectangle 205,82,26,29 }
            $targetRect = New-Object Drawing.Rectangle 1,($(if ($isMct) { 60 } else { 70 })),26,29
            $originalBmp = New-Object Drawing.Bitmap (Join-Path $fixtureDir "$original.png")
            $bmp = New-Object Drawing.Bitmap 290,190
            $graphics = [Drawing.Graphics]::FromImage($bmp)
            try {
                $graphics.Clear([Drawing.Color]::FromArgb(120,120,120))
                $graphics.DrawImage($originalBmp, $targetRect, $sourceRect, [Drawing.GraphicsUnit]::Pixel)
            } finally { $graphics.Dispose(); $originalBmp.Dispose() }
        } else {
            $bmp = New-Object Drawing.Bitmap (Join-Path $fixtureDir "$name.png")
        }
        try {
            $rect = New-Object Drawing.Rectangle 0,0,$bmp.Width,$bmp.Height
            $locked = $bmp.LockBits($rect, [Drawing.Imaging.ImageLockMode]::ReadOnly, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
            try {
                if ($bmp.Width -ne 290 -or $bmp.Height -ne 190 -or $locked.Stride -ne 1160) { throw 'Unexpected fixture dimensions' }
                $bytes = New-Object byte[] (290*190*4)
                [Runtime.InteropServices.Marshal]::Copy($locked.Scan0,$bytes,0,$bytes.Length)
                [IO.File]::WriteAllBytes((Join-Path $scratch "$name.bgra"),$bytes)
            } finally { $bmp.UnlockBits($locked) }
        } finally { $bmp.Dispose() }
    }
    $caseLines = $cases | ForEach-Object { '["' + $_[0] + '","' + $_[1] + '",' + ($_[2..4] -join ',') + ',' + ($(if ($_.Length -gt 5) { $_[5] } else { 0 })) + ']' }
    $driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global EARN_MINIMAP := [20,860,310,1050], EARN_ARROW := [164,1005]
'@
    $driver += "`nscratch := `"$scratch`"`ncases := [" + ($caseLines -join ',') + "]`n"
    $driver += @'
for c in cases {
    pixels := FileRead(scratch "\" c[1] ".bgra", "RAW")
    found := EarnBlipFromPixels(c[2], pixels, 290, 190, 1, 1, &angle, &distance)
    actualX := 164 + Sin(angle * 3.14159265 / 180) * distance
    actualY := 1005 - Cos(angle * 3.14159265 / 180) * distance
    edgeWrong := c[6] && (distance != 999 || Abs(angle - ATan2Deg(c[4]-164,1005-c[5])) > 1)
    locationWrong := !c[6] && (Abs(actualX-c[4]) > 1 || Abs(actualY-c[5]) > 1)
    if (found != c[3] || (found && (edgeWrong || locationWrong))) {
        FileAppend("FAIL " c[1] " " c[2] " found=" found " x=" actualX " y=" actualY "`n", "*")
        ExitApp(1)
    }
}
FileAppend("PASS EarnBlip: 16 screenshot cases; no game input`n", "*")
ExitApp(0)
'@
    [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $AhkPath
    $info.Arguments = '/ErrorStdOut /CP65001 *'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($info)
    try {
        $p.StandardInput.WriteLine($driver + "`n" + ($functions -join "`n"))
        $p.StandardInput.Close()
        if (!$p.WaitForExit(10000)) { $p.Kill(); throw 'Offline blip test timed out' }
        $stdout = $p.StandardOutput.ReadToEnd().Trim()
        $stderr = $p.StandardError.ReadToEnd().Trim()
        if ($p.ExitCode -ne 0 -or $stderr -or $stdout -ne 'PASS EarnBlip: 16 screenshot cases; no game input') {
            throw "exit=$($p.ExitCode) stdout=$stdout stderr=$stderr"
        }
        $stdout
    } finally { $p.Dispose() }
} finally {
    [Console]::InputEncoding = $previousEncoding
    # Delete only this invocation's known temporary files and empty directory.
    Get-ChildItem -LiteralPath $scratch -File | Remove-Item
    Remove-Item -LiteralPath $scratch
}
