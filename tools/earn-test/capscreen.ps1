param([string]$Name = "cap", [int]$X = 1920, [int]$Y = 0, [int]$W = 2560, [int]$H = 1600, [double]$Scale = 0.5)
# DPI-aware capture in physical pixels. Default = laptop panel (2560x1600) to the right of the 1920x1080 main monitor.
Add-Type 'using System;using System.Runtime.InteropServices;public class DA3{[DllImport("user32.dll")]public static extern bool SetProcessDPIAware();}'
[DA3]::SetProcessDPIAware() | Out-Null
Add-Type -AssemblyName System.Drawing
$b = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($b); $g.CopyFromScreen($X, $Y, 0, 0, $b.Size); $g.Dispose()
$s = New-Object System.Drawing.Bitmap $b, ([int]($W * $Scale)), ([int]($H * $Scale))
$p = Join-Path $env:TEMP "claude\$Name.png"; $s.Save($p, [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose(); $s.Dispose()
"$(Get-Date -Format HH:mm:ss) saved $p region=$X,$Y ${W}x$H scale=$Scale"
