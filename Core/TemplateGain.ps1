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

    // 밝힌 사본이 대부분 순백이면 흰 벽·하늘 어디에나 맞는다. 그런 사본은 글자에서 2칸 넘게 떨어진 투명 칸 중
    // 최대 16곳을 바탕 표본으로 남겨, 찾은 자리의 바탕이 순백이 아닌지 호출자가 확인하게 한다.
    // 반환: null = 확인 불필요, 빈 배열 = 표본이 모자라 사본을 쓰면 안 됨.
    public static int[][] BackgroundSamples(string gainPng, double whiteLimit) {
        using (var bmp = new Bitmap(gainPng)) {
            int w = bmp.Width, h = bmp.Height, opaque = 0, white = 0;
            var solid = new bool[w, h];
            for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
                Color c = bmp.GetPixel(x, y);
                if (c.R == 255 && c.G == 0 && c.B == 255) continue;
                solid[x, y] = true; opaque++;
                if (c.R >= 250 && c.G >= 250 && c.B >= 250) white++;
            }
            if (opaque == 0 || white < opaque * whiteLimit) return null;
            var points = new System.Collections.Generic.List<int[]>();
            for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
                if (solid[x, y]) continue;
                bool far = true;
                for (int dy = -2; dy <= 2 && far; dy++) for (int dx = -2; dx <= 2; dx++) {
                    int xx = x + dx, yy = y + dy;
                    if (xx >= 0 && yy >= 0 && xx < w && yy < h && solid[xx, yy]) { far = false; break; }
                }
                if (far) points.Add(new int[] { x, y });
            }
            if (points.Count < 6) return new int[0][];
            int take = Math.Min(16, points.Count);
            var picked = new int[take][];
            for (int i = 0; i < take; i++) picked[i] = points[(int)((long)i * points.Count / take)];
            return picked;
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
$checked = 0
$skipped = 0
foreach ($file in [IO.Directory]::GetFiles($Source, '*.png')) {
    $out = Join-Path $Destination ([IO.Path]::GetFileName($file))
    $tmp = $out + '.tmp'
    [GtaTemplateGain]::Apply($file, $tmp, $Gain)
    $samples = [GtaTemplateGain]::BackgroundSamples($tmp, 0.9)
    $bgFile = $out + '.bg'
    if ($null -ne $samples -and $samples.Length -eq 0) {
        # 바탕을 확인할 길이 없는 순백 사본은 오인식만 늘리므로 만들지 않는다.
        Remove-Item -LiteralPath $tmp -Force
        foreach ($stale in @($out, $bgFile)) { if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Force } }
        $skipped++
        continue
    }
    Move-Item -LiteralPath $tmp -Destination $out -Force
    if ($null -ne $samples) {
        [IO.File]::WriteAllLines($bgFile, [string[]]@($samples | ForEach-Object { '{0},{1}' -f $_[0], $_[1] }))
        $checked++
    } elseif (Test-Path -LiteralPath $bgFile) {
        Remove-Item -LiteralPath $bgFile -Force
    }
    $count++
}
Write-Output "gain=$Gain templates=$count background-checked=$checked skipped=$skipped -> $Destination"
