param(
  [string]$OutDir = (Join-Path $env:TEMP 'claude\jobwarp'),
  [int]$X = 0, [int]$Y = 0, [int]$W = 1920, [int]$H = 1080,
  [int]$IntervalMs = 400,
  [int]$MaxMinutes = 60
)
# F11 퀵 조인 준비(Features\Teleport\QuickJoinPrep.ahk) 템플릿을 뜨기 위한 캡처 도구.
# 백그라운드로 띄워 두면, ScrollLock 이 켜져 있는 동안만 게임 모니터를 IntervalMs 마다 찍고 앞 장과 달라진 화면만 남긴다.
# 사용자는 ScrollLock 을 켜고 평소처럼 손으로 보스 해제 → 폰 Quick Join → Random → Alone → Yes → 보스 등록을 한 뒤 ScrollLock 을 끈다.
# 게임에는 아무 키도 보내지 않는다. 남은 장에서 선택된 줄을 잘라 Images\JobWarp\1920x1080\ 템플릿을 만든다.
$ErrorActionPreference = 'Stop'
Add-Type 'using System;using System.Runtime.InteropServices;public class JWDpi{[DllImport("user32.dll")]public static extern bool SetProcessDPIAware();}'
[JWDpi]::SetProcessDPIAware() | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# 64x36 로 줄인 밝기 값. 앞 장과 평균 차이가 작으면 같은 화면으로 보고 버린다
function Get-Thumb([System.Drawing.Bitmap]$bmp) {
  $t = New-Object System.Drawing.Bitmap $bmp, 64, 36
  $v = New-Object 'int[]' (64 * 36)
  for ($j = 0; $j -lt 36; $j++) { for ($i = 0; $i -lt 64; $i++) { $c = $t.GetPixel($i, $j); $v[$j * 64 + $i] = ($c.R + $c.G + $c.B) / 3 } }
  $t.Dispose()
  return ,$v
}

$deadline = (Get-Date).AddMinutes($MaxMinutes)
$prev = $null
$n = (Get-ChildItem $OutDir -Filter 'f*.png' -ErrorAction SilentlyContinue).Count
$wasOn = $false
"$(Get-Date -Format HH:mm:ss) 대기: ScrollLock 을 켜면 $OutDir 에 찍는다 (최대 $MaxMinutes 분)"
while ((Get-Date) -lt $deadline) {
  $on = [System.Windows.Forms.Control]::IsKeyLocked([System.Windows.Forms.Keys]::Scroll)
  if ($on -ne $wasOn) { "$(Get-Date -Format HH:mm:ss) ScrollLock " + ($(if ($on) { '켜짐: 찍기 시작' } else { '꺼짐: 멈춤' })); $wasOn = $on }
  if (-not $on) { Start-Sleep -Milliseconds 200; continue }
  $b = New-Object System.Drawing.Bitmap $W, $H
  $g = [System.Drawing.Graphics]::FromImage($b); $g.CopyFromScreen($X, $Y, 0, 0, $b.Size); $g.Dispose()
  $thumb = Get-Thumb $b
  $keep = $true
  if ($prev) {
    $d = 0; for ($k = 0; $k -lt $thumb.Length; $k++) { $d += [Math]::Abs($thumb[$k] - $prev[$k]) }
    $keep = ($d / $thumb.Length) -ge 1.5
  }
  if ($keep) {
    $n++
    $p = Join-Path $OutDir ('f{0:d4}-{1}.png' -f $n, (Get-Date -Format HHmmss))
    $b.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
    $prev = $thumb
  }
  $b.Dispose()
  Start-Sleep -Milliseconds $IntervalMs
}
"$(Get-Date -Format HH:mm:ss) 끝: $n 장"
