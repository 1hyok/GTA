#Requires -Version 5.1
<#
Dot-source to get Compare-PngPixels. Builder reproduction is compared by decoded
pixels, not file hashes: the GDI+ PNG encoder on the GitHub Windows runner writes
different bytes for the same pixels, so a hash check fails there while passing
locally. Returns '' when identical, otherwise a description of the first difference.
#>
Add-Type -AssemblyName System.Drawing
function Compare-PngPixels([string]$ExpectedPath, [string]$ActualPath) {
    $expected = [Drawing.Bitmap]::FromFile($ExpectedPath)
    $actual = [Drawing.Bitmap]::FromFile($ActualPath)
    try {
        if ($expected.Width -ne $actual.Width -or $expected.Height -ne $actual.Height) {
            return "size $($actual.Width)x$($actual.Height) != $($expected.Width)x$($expected.Height)"
        }
        for ($y = 0; $y -lt $expected.Height; $y++) {
            for ($x = 0; $x -lt $expected.Width; $x++) {
                $e = $expected.GetPixel($x, $y).ToArgb()
                $a = $actual.GetPixel($x, $y).ToArgb()
                if ($e -ne $a) { return ('pixel {0},{1} {2:X8} != {3:X8}' -f $x, $y, $a, $e) }
            }
        }
        return ''
    }
    finally { $expected.Dispose(); $actual.Dispose() }
}
