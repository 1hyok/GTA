param(
  [string]$OutDir = (Join-Path $env:TEMP 'claude\jobwarp'),
  [int]$X = 0, [int]$Y = 0, [int]$W = 1920, [int]$H = 1080,
  [int]$IntervalMs = 400,
  [int]$MaxMinutes = 60
)
# F11 퀵 조인 준비(Features\Teleport\QuickJoinPrep.ahk) 템플릿을 뜨기 위한 캡처 도구.
# 백그라운드로 띄워 두면, 켜져 있는 동안만 게임 모니터를 IntervalMs 마다 찍고 앞 장과 달라진 화면만 남긴다.
# 켜고 끄는 키는 App menu 키(오른쪽 클릭 메뉴 키) 한 번씩이다. ScrollLock 이 켜져 있어도 찍는다(ScrollLock 키가 없는 키보드가 있어 App menu 키를 더했다, 0927 K860).
# 사용자는 App menu 키를 누르고 평소처럼 손으로 보스 해제 → 폰 Quick Join → Random → Alone → Yes → 보스 등록을 한 뒤 App menu 키를 다시 누른다.
# 게임에는 아무 키도 보내지 않는다. 남은 장에서 선택된 줄을 잘라 Images\JobWarp\1920x1080\ 템플릿을 만든다.
$ErrorActionPreference = 'Stop'
Add-Type 'using System;using System.Runtime.InteropServices;public class JWDpi{[DllImport("user32.dll")]public static extern bool SetProcessDPIAware();[DllImport("user32.dll")]public static extern short GetAsyncKeyState(int vk);}'
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
$appsOn = $false
$appsDown = $false
"$(Get-Date -Format HH:mm:ss) 대기: App menu 키(또는 ScrollLock)를 켜면 $OutDir 에 찍는다 (최대 $MaxMinutes 분)"
while ((Get-Date) -lt $deadline) {
  # App menu 키(VK_APPS 0x5D)는 누를 때마다 켜고 끈다. 떼었다 다시 눌러야 한 번으로 센다
  $down = ([JWDpi]::GetAsyncKeyState(0x5D) -band 0x8000) -ne 0
  if ($down -and -not $appsDown) { $appsOn = -not $appsOn }
  $appsDown = $down
  $on = $appsOn -or [System.Windows.Forms.Control]::IsKeyLocked([System.Windows.Forms.Keys]::Scroll)
  if ($on -ne $wasOn) { "$(Get-Date -Format HH:mm:ss) 캡처 " + ($(if ($on) { '켜짐: 찍기 시작' } else { '꺼짐: 멈춤' })); $wasOn = $on }
  if (-not $on) { Start-Sleep -Milliseconds 100; continue }
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
