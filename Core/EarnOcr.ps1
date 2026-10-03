# Windows PowerShell 5.1; Windows.Media.Ocr only, no game input or downloads.
# TSV: x<TAB>y<TAB>w<TAB>h<TAB>text. Coordinates are physical screen pixels
# for capture, or original-image pixels for -ImagePath (including a crop offset).
# Callers must require exit code 0 AND a newly written output before consuming it.
[CmdletBinding()]
param(
    [string]$ImagePath = '',
    [int]$X = 0,
    [int]$Y = 0,
    [int]$W = 0,
    [int]$H = 0,
    [double]$Scale = 2,
    [switch]$WhiteText,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$outputFile = $null
$stagingFile = $null
$bitmapFile = $null
$source = $null
$region = $null
$scaled = $null
$graphics = $null
$stream = $null
$softwareBitmap = $null
$exitCode = 1

try {
    $outputFile = [IO.Path]::GetFullPath($OutputPath)
    if ($ImagePath) {
        $ImagePath = [IO.Path]::GetFullPath($ImagePath)
        if ([string]::Equals($ImagePath, $outputFile, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'ImagePath and OutputPath must be different files.'
        }
    }
    # Invalidate an older successful result before validation or recognition.
    if ([IO.File]::Exists($outputFile)) { [IO.File]::Delete($outputFile) }
    if (-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($outputFile))) {
        throw 'OutputPath parent directory does not exist.'
    }
    if ([double]::IsNaN($Scale) -or [double]::IsInfinity($Scale) -or $Scale -lt 1 -or $Scale -gt 4) {
        throw 'Scale must be between 1 and 4.'
    }
    if ($PSVersionTable.PSEdition -eq 'Core') {
        throw 'Run EarnOcr.ps1 with Windows powershell.exe 5.1; WinRT projection is required.'
    }

    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    Add-Type -AssemblyName System.Drawing
    $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
    $null = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
    $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]
    $language = New-Object Windows.Globalization.Language 'en-US'
    if (-not [Windows.Media.Ocr.OcrEngine]::IsLanguageSupported($language)) {
        $available = @([Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages | ForEach-Object { $_.LanguageTag }) -join ', '
        throw "Windows OCR en-US is unavailable. Installed OCR languages: $available"
    }
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($language)
    if ($null -eq $engine) { throw 'Windows OCR failed to create the en-US recognizer.' }
    $asyncAdapter = @([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and
        $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    })[0]
    if ($null -eq $asyncAdapter) { throw 'Windows Runtime task adapter was not found.' }
    function Wait-OcrOperation($Operation, [Type]$ResultType) {
        $task = $asyncAdapter.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
        if (-not $task.Wait(20000)) { throw 'Windows OCR operation timed out after 20 seconds.' }
        return $task.GetAwaiter().GetResult()
    }

    if ($ImagePath) {
        if (-not [IO.File]::Exists($ImagePath)) { throw "ImagePath does not exist: $ImagePath" }
        $source = [Drawing.Bitmap]::FromFile($ImagePath)
        if ($W -eq 0 -and $H -eq 0 -and $X -eq 0 -and $Y -eq 0) {
            $W = $source.Width
            $H = $source.Height
        }
        if ($W -le 0 -or $H -le 0 -or $X -lt 0 -or $Y -lt 0 -or
            ([long]$X + $W) -gt $source.Width -or ([long]$Y + $H) -gt $source.Height) {
            throw 'Image crop must have positive dimensions and fit inside ImagePath.'
        }
        $rect = New-Object Drawing.Rectangle $X, $Y, $W, $H
        $region = $source.Clone($rect, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    }
    else {
        if ($W -le 0 -or $H -le 0) { throw 'Screen capture requires positive W and H.' }
        if (-not ('EarnOcrDisplayNative' -as [Type])) {
            Add-Type @'
using System.Runtime.InteropServices;
public static class EarnOcrDisplayNative {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
}
'@
        }
        $null = [EarnOcrDisplayNative]::SetProcessDPIAware()
        $left = [EarnOcrDisplayNative]::GetSystemMetrics(76)
        $top = [EarnOcrDisplayNative]::GetSystemMetrics(77)
        $right = [long]$left + [EarnOcrDisplayNative]::GetSystemMetrics(78)
        $bottom = [long]$top + [EarnOcrDisplayNative]::GetSystemMetrics(79)
        if ($X -lt $left -or $Y -lt $top -or ([long]$X + $W) -gt $right -or ([long]$Y + $H) -gt $bottom) {
            throw "Capture rectangle is outside the physical desktop ($left,$top)-($right,$bottom)."
        }
        $region = New-Object Drawing.Bitmap $W, $H
        $graphics = [Drawing.Graphics]::FromImage($region)
        $graphics.CopyFromScreen($X, $Y, 0, 0, $region.Size)
        $graphics.Dispose()
        $graphics = $null
    }

    if ($WhiteText) {
        # Vinewood footers place white text over translucent scenery. Keep only
        # bright pixels in all RGB channels, then OCR dark glyphs on plain white.
        # Run before scaling so the same physical pixel threshold applies at all scales.
        if (-not ('EarnOcrImageFilter' -as [Type])) {
            Add-Type -ReferencedAssemblies System.Drawing @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class EarnOcrImageFilter {
    public static void WhiteText(Bitmap image) {
        Rectangle rectangle = new Rectangle(0, 0, image.Width, image.Height);
        BitmapData data = image.LockBits(rectangle, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        try {
            byte[] row = new byte[image.Width * 4];
            for (int y = 0; y < image.Height; y++) {
                IntPtr address = IntPtr.Add(data.Scan0, y * data.Stride);
                Marshal.Copy(address, row, 0, row.Length);
                for (int x = 0; x < row.Length; x += 4) {
                    byte value = (byte)(row[x] >= 200 && row[x + 1] >= 200 && row[x + 2] >= 200 ? 0 : 255);
                    row[x] = row[x + 1] = row[x + 2] = value;
                    row[x + 3] = 255;
                }
                Marshal.Copy(row, 0, address, row.Length);
            }
        }
        finally { image.UnlockBits(data); }
    }
}
'@
        }
        [EarnOcrImageFilter]::WhiteText($region)
    }

    # Upscale small phone text, bounded by the recognizer's actual size limit.
    $maxDimension = [Windows.Media.Ocr.OcrEngine]::MaxImageDimension
    if ($W -gt $maxDimension -or $H -gt $maxDimension) {
        throw "OCR region exceeds the Windows OCR maximum dimension $maxDimension. Use a smaller crop."
    }
    $effectiveScale = [Math]::Min($Scale, [double]$maxDimension / [Math]::Max($W, $H))
    $scaledW = [Math]::Min($maxDimension, [int][Math]::Floor($W * $effectiveScale))
    $scaledH = [Math]::Min($maxDimension, [int][Math]::Floor($H * $effectiveScale))
    $scaled = New-Object Drawing.Bitmap $scaledW, $scaledH
    $graphics = [Drawing.Graphics]::FromImage($scaled)
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.DrawImage($region, 0, 0, $scaledW, $scaledH)
    $graphics.Dispose()
    $graphics = $null
    $bitmapFile = Join-Path ([IO.Path]::GetTempPath()) ('gta-earn-ocr-' + [Guid]::NewGuid().ToString('N') + '.png')
    $scaled.Save($bitmapFile, [Drawing.Imaging.ImageFormat]::Png)

    $storageFile = Wait-OcrOperation ([Windows.Storage.StorageFile]::GetFileFromPathAsync($bitmapFile)) ([Windows.Storage.StorageFile])
    $stream = Wait-OcrOperation ($storageFile.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    $decoder = Wait-OcrOperation ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $softwareBitmap = Wait-OcrOperation ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $result = Wait-OcrOperation ($engine.RecognizeAsync($softwareBitmap)) ([Windows.Media.Ocr.OcrResult])

    $rows = New-Object 'Collections.Generic.List[string]'
    $rows.Add("x`ty`tw`th`ttext")
    $scaleX = [double]$scaledW / $W
    $scaleY = [double]$scaledH / $H
    # WinRT boxes use its deskewed image coordinates. Rotate each word back
    # around the image center before mapping to physical/original-image pixels.
    # https://learn.microsoft.com/uwp/api/windows.media.ocr.ocrresult.textangle
    $textAngle = if ($null -eq $result.TextAngle) { 0.0 } else { [double]$result.TextAngle }
    $radians = $textAngle * [Math]::PI / 180
    $cosine = [Math]::Cos($radians)
    $sine = [Math]::Sin($radians)
    $rotationX = $scaledW / 2.0
    $rotationY = $scaledH / 2.0
    foreach ($line in $result.Lines) {
        if ($line.Words.Count -eq 0) { continue }
        $minX = [double]::PositiveInfinity
        $minY = [double]::PositiveInfinity
        $maxX = 0.0
        $maxY = 0.0
        foreach ($word in $line.Words) {
            $box = $word.BoundingRect
            foreach ($corner in @(
                @($box.X, $box.Y),
                @(($box.X + $box.Width), $box.Y),
                @($box.X, ($box.Y + $box.Height)),
                @(($box.X + $box.Width), ($box.Y + $box.Height))
            )) {
                $dx = $corner[0] - $rotationX
                $dy = $corner[1] - $rotationY
                $rotatedX = $rotationX + $dx * $cosine - $dy * $sine
                $rotatedY = $rotationY + $dx * $sine + $dy * $cosine
                $minX = [Math]::Min($minX, $rotatedX)
                $minY = [Math]::Min($minY, $rotatedY)
                $maxX = [Math]::Max($maxX, $rotatedX)
                $maxY = [Math]::Max($maxY, $rotatedY)
            }
        }
        $minX = [Math]::Max(0, $minX)
        $minY = [Math]::Max(0, $minY)
        $maxX = [Math]::Min($scaledW, $maxX)
        $maxY = [Math]::Min($scaledH, $maxY)
        if ($maxX -le $minX -or $maxY -le $minY) { continue }
        $centerX = $X + [int][Math]::Round(($minX + $maxX) / (2 * $scaleX))
        $centerY = $Y + [int][Math]::Round(($minY + $maxY) / (2 * $scaleY))
        $width = [int][Math]::Ceiling(($maxX - $minX) / $scaleX)
        $height = [int][Math]::Ceiling(($maxY - $minY) / $scaleY)
        $text = ($line.Text -replace '[\t\r\n\x00]', ' ').Trim()
        if ($text) { $rows.Add("$centerX`t$centerY`t$width`t$height`t$text") }
    }
    $stagingFile = $outputFile + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllLines($stagingFile, $rows, (New-Object Text.UTF8Encoding $true))
    [IO.File]::Move($stagingFile, $outputFile)
    $stagingFile = $null
    Write-Output ('OK en-US lines={0} region={1},{2},{3},{4} output={5}' -f ($rows.Count - 1), $X, $Y, $W, $H, $outputFile)
    $exitCode = 0
}
catch {
    [Console]::Error.WriteLine('EarnOcr: ' + $_.Exception.Message)
    if ($outputFile -and [IO.File]::Exists($outputFile) -and
        -not [string]::Equals($ImagePath, $outputFile, [StringComparison]::OrdinalIgnoreCase)) {
        [IO.File]::Delete($outputFile)
    }
}
finally {
    foreach ($disposable in @($graphics, $softwareBitmap, $stream, $scaled, $region, $source)) {
        if ($null -ne $disposable -and $disposable -is [IDisposable]) { $disposable.Dispose() }
    }
    foreach ($temporaryFile in @($stagingFile, $bitmapFile)) {
        if ($temporaryFile -and [IO.File]::Exists($temporaryFile)) { [IO.File]::Delete($temporaryFile) }
    }
}
exit $exitCode
