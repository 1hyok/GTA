# Windows PowerShell 5.1. 게임 입력 없음, 다운로드 없음.
# Source 폴더의 템플릿 PNG 를 밝기 배율(Gain)만큼 밝힌 사본으로 Destination 에 만든다.
# 화면 밝기가 템플릿을 뜬 때와 달라졌을 때 TemplateSeen 이 원본 다음으로 이 사본을 찾는다.
# FF00FF(투명) 칸은 그대로 두고, 나머지 칸은 채널마다 min(255, round(값 * Gain)).
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][double]$Gain
)
$ErrorActionPreference = 'Stop'
if ($Gain -le 0 -or $Gain -gt 4) { throw 'Gain must be in (0, 4].' }
Add-Type -AssemblyName System.Drawing
if (-not ('GtaTemplateGain' -as [type])) {
    Add-Type -ReferencedAssemblies System.Drawing @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class GtaTemplateGain {
    public static void Apply(string src, string dst, double gain) {
        using (var loaded = new Bitmap(src))
        using (var bmp = new Bitmap(loaded.Width, loaded.Height, PixelFormat.Format32bppArgb)) {
            using (var g = Graphics.FromImage(bmp)) g.DrawImageUnscaled(loaded, 0, 0);
            var rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
            var data = bmp.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            try {
                int bytes = data.Stride * data.Height;
                var px = new byte[bytes];
                Marshal.Copy(data.Scan0, px, 0, bytes);
                for (int i = 0; i + 3 < bytes; i += 4) {
                    byte b = px[i], gr = px[i + 1], r = px[i + 2];
                    if (r == 255 && gr == 0 && b == 255) continue;
                    px[i] = Scale(b, gain); px[i + 1] = Scale(gr, gain); px[i + 2] = Scale(r, gain);
                    // 밝힌 결과가 우연히 투명색이 되지 않게 한다.
                    if (px[i + 2] == 255 && px[i + 1] == 0 && px[i] == 255) px[i + 1] = 1;
                }
                Marshal.Copy(px, 0, data.Scan0, bytes);
            } finally { bmp.UnlockBits(data); }
            bmp.Save(dst, ImageFormat.Png);
        }
    }
    static byte Scale(byte v, double gain) {
        double s = Math.Round(v * gain);
        return (byte)(s > 255 ? 255 : (s < 0 ? 0 : s));
    }
}
'@
}
$Source = [IO.Path]::GetFullPath($Source)
$Destination = [IO.Path]::GetFullPath($Destination)
if (-not [IO.Directory]::Exists($Source)) { throw "Source folder not found: $Source" }
[void][IO.Directory]::CreateDirectory($Destination)
$count = 0
foreach ($file in [IO.Directory]::GetFiles($Source, '*.png')) {
    $out = Join-Path $Destination ([IO.Path]::GetFileName($file))
    $tmp = $out + '.tmp'
    [GtaTemplateGain]::Apply($file, $tmp, $Gain)
    Move-Item -LiteralPath $tmp -Destination $out -Force
    $count++
}
Write-Output "gain=$Gain templates=$count -> $Destination"
