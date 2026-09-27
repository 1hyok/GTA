param(
  [string]$EvidenceDir = (Join-Path $PSScriptRoot '..\docs\evidence\2026-09-27-jobwarp'),
  [switch]$TestOnly
)
# F11 퀵 조인 준비(Features\Teleport\QuickJoinPrep.ahk)가 쓰는 템플릿을 실측 스크린샷에서 잘라 Images\JobWarp\1920x1080\ 에 만들고,
# 코드와 같은 영역·옵션(*40 *Trans0xFF00FF)으로 모든 원본에 대 보아 맞는 상태에서만 찾히는지 표로 확인한다. 게임에는 아무 키도 보내지 않는다.
#
# 원본(docs\evidence\2026-09-27-jobwarp): <상태>.png 는 코드가 찾는 영역을 그대로 잘라 둔 무손실 조각, <상태>.jpg 는 같은 순간의 전체 화면이다.
#   m-*, after-*, *-menu : 상호작용 메뉴 영역 JW_MENU_AREA [0,0,0.27,0.55] = 화면 (0,0) 518x594
#   ph-*, qj-*, phone-*, *-phone : 폰 영역 JW_PHONE_AREA [0.6,0.3,1,1] = 화면 (1152,324) 768x756
# 아래 사각형은 전체 화면(1920x1080) 좌표다. 추측한 UI 가 아니라 2026-09-27 22:51~23:00 에 찍은 화면(저택 안, 해제 상태에서 시작)에서 잰 값만 적는다.
# run-*.jpg 는 F11 실제 시험(23:09 설정 미로드로 Alt+F4 경로, 23:12 퀵 조인 준비 ok)과 그 뒤 손으로 Retire 한 화면, macro-log.txt 는 그때 로그다.
# mask: -1 = 그대로(메뉴 제목 줄·선택 줄·폰 화면은 불투명), 0 = 흰 글자만 남기고 FF00FF(선택 안 된 줄은 반투명이라 뒤 배경이 비친다),
#       N = 위에서 N 줄은 그대로 두고 그 아래만 흰 글자로.
# 메뉴 제목 "SecuroServ CEO" 선택 줄은 등록 하위 메뉴(REGISTER AS A BOSS)와 보스 메인 메뉴(INTERACTION MENU)에서 글자·자리가 같다.
# 그래서 m_ceo_sel·m_securo_sel·m_securo 는 바로 위 제목 줄까지 같이 떠서 서로를 대신하지 못하게 한다.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$EvidenceDir = (Resolve-Path $EvidenceDir).Path
$target = Join-Path $PSScriptRoot '..\Images\JobWarp\1920x1080'
$earnTitle = Join-Path $PSScriptRoot '..\Images\Earn\1920x1080\m_title.png'
New-Item -ItemType Directory -Force -Path $target | Out-Null
$target = (Resolve-Path $target).Path

$menuArea = @(0, 0, 518, 594)
$phoneArea = @(1152, 324, 768, 756)
function Get-Area([string]$state) {
  if ($state -match '^(ph-|qj-|phone-)' -or $state -like '*-phone') { return $phoneArea }
  return $menuArea
}

$items = @(
  # 이름, 원본 상태, x, y, w, h, mask
  @('m_boss',           'm-main-free',                 38, 233, 184, 27,  0),   # 선택 안 된 "Register as a Boss" (부동산 안에서는 3번째 줄, 밖에서는 2번째 줄)
  @('m_boss_sel',       'm-main-free-boss-sel',        38, 233, 184, 27, -1),
  @('m_ceo_sel',        'm-register-boss-ceo-sel',     37, 123, 214, 58, -1),   # 제목 REGISTER AS A BOSS + 선택된 SecuroServ CEO
  @('m_start_org_sel',  'm-securoserv-start-org-sel',  38, 158, 208, 27, -1),   # 제목 SECUROSERV 아래 선택된 Start an Organization
  @('m_securo_sel',     'm-main-ceo-securo-sel',       37, 123, 214, 58, -1),   # 제목 INTERACTION MENU + 선택된 SecuroServ CEO(맨 위 줄)
  @('m_securo',         'm-main-ceo-securo',           37, 123, 214, 58, 29),   # 같은 자리, 줄은 선택 안 됨(제목 줄 29px 는 불투명이라 그대로)
  @('m_retire_sel',     'm-ceo-menu-retire-sel',       38, 383,  80, 22, -1),   # SECUROSERV CEO 하위 메뉴 맨 아래(7번째) 줄
  @('m_sub_boss',       'm-register-boss-ceo-sel',     37, 123, 214, 21, -1),   # 하위 메뉴 제목 REGISTER AS A BOSS (메뉴 열림 확인용)
  @('m_sub_securo',     'm-securoserv-start-org-sel',  37, 123, 140, 21, -1),   # 하위 메뉴 제목 SECUROSERV (SECUROSERV CEO 도 앞 글자가 같아 함께 잡는다)
  @('ph_quickjoin_sel', 'ph-home2-quickjoin-sel',    1636, 783,  60, 60, -1),   # 홈 2쪽 첫 칸, 골라지면 아이콘이 커지고 테두리가 빛난다
  @('qj_random_sel',    'qj-list-random-sel',        1618, 966,  78, 30, -1),   # Quick Join 목록 맨 아래 줄
  @('qj_alone_sel',     'qj-random-alone-sel',       1618, 820,  56, 30, -1),   # Random 아래 두 줄 중 두 번째
  @('qj_yes_sel',       'qj-yes-sel',                1618, 772, 162, 34, -1)    # 폰 안의 확인 줄 "Are you sure?" (화면 가운데 알림이 아니다)
)

if (-not $TestOnly) {
  foreach ($item in $items) {
    $area = Get-Area $item[1]
    $source = [Drawing.Bitmap]::FromFile((Join-Path $EvidenceDir ($item[1] + '.png')))
    try {
      $rect = New-Object Drawing.Rectangle ([int]$item[2] - $area[0]), ([int]$item[3] - $area[1]), ([int]$item[4]), ([int]$item[5])
      $crop = $source.Clone($rect, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
      try {
        if ($item[6] -ge 0) {
          for ($y = [int]$item[6]; $y -lt $crop.Height; $y++) {
            for ($x = 0; $x -lt $crop.Width; $x++) {
              $c = $crop.GetPixel($x, $y)
              $mn = [Math]::Min($c.R, [Math]::Min($c.G, $c.B)); $mx = [Math]::Max($c.R, [Math]::Max($c.G, $c.B))
              if ($mn -lt 170 -or ($mx - $mn) -gt 35) { $crop.SetPixel($x, $y, [Drawing.Color]::FromArgb(255, 0, 255)) }
            }
          }
        }
        $crop.Save((Join-Path $target ($item[0] + '.png')), [Drawing.Imaging.ImageFormat]::Png)
      } finally { $crop.Dispose() }
    } finally { $source.Dispose() }
  }
  "만든 템플릿 $($items.Count)개: $target"
}

# --- 오프라인 시험: AutoHotkey ImageSearch 의 *n *TransN 규칙(투명색 칸은 건너뛰고, 나머지 칸은 R·G·B 가 각각 ±n 안) 그대로, 코드와 같은 영역 조각에서 찾는다 ---
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class JWSearch {
  public static int[] Load(string path, out int w, out int h) {
    using (var src = new Bitmap(path)) {
      w = src.Width; h = src.Height;
      var data = src.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
      var px = new int[w * h];
      for (int y = 0; y < h; y++) Marshal.Copy(data.Scan0 + y * data.Stride, px, y * w, w);
      src.UnlockBits(data);
      return px;
    }
  }
  public static bool Find(int[] hay, int hw, int hh, int[] nd, int nw, int nh, int v, int trans, out int fx, out int fy) {
    fx = -1; fy = -1;
    for (int y = 0; y + nh <= hh; y++)
      for (int x = 0; x + nw <= hw; x++) {
        bool ok = true;
        for (int j = 0; j < nh && ok; j++)
          for (int i = 0; i < nw; i++) {
            int n = nd[j * nw + i] & 0xFFFFFF;
            if (n == trans) continue;
            int s = hay[(y + j) * hw + x + i];
            if (Math.Abs(((s >> 16) & 255) - ((n >> 16) & 255)) > v || Math.Abs(((s >> 8) & 255) - ((n >> 8) & 255)) > v || Math.Abs((s & 255) - (n & 255)) > v) { ok = false; break; }
          }
        if (ok) { fx = x; fy = y; return true; }
      }
    return false;
  }
}
'@

# 상태마다 찾혀야 하는 템플릿. 여기 없는 템플릿은 그 상태에서 안 찾혀야 한다
$expect = [ordered]@{
  '0-start-freemode-menu'           = @()
  'm-main-free'                     = @('m_title', 'm_boss')
  'm-main-free-quickgps-sel'        = @('m_title', 'm_boss')
  'm-main-free-boss-row-hidden'     = @('m_title')                       # 앉았다 일어나는 동안 Register as a Boss 줄이 잠깐 빠졌다(11줄)
  'm-main-free-boss-sel'            = @('m_title', 'm_boss_sel')
  'm-register-boss-ceo-sel'         = @('m_sub_boss', 'm_ceo_sel')
  'm-securoserv-start-org-sel'      = @('m_sub_securo', 'm_start_org_sel')
  'after-start-org'                 = @()
  'm-main-ceo-securo-sel'           = @('m_title', 'm_securo_sel')
  'm-main-ceo-securo-sel-2'         = @('m_title', 'm_securo_sel')
  'm-main-ceo-securo'               = @('m_title', 'm_securo')
  'm-ceo-menu-hire-sel'             = @('m_sub_securo')
  'm-ceo-menu-retire-sel'           = @('m_sub_securo', 'm_retire_sel')
  'after-retire-you-quit'           = @()
  'm-main-free-after-retire'        = @('m_title', 'm_boss')
  'm-main-free-final'               = @('m_title', 'm_boss')              # F11 실제 시험 뒤 손으로 Retire 한 마지막 상태(23:15)
  'm-mansion-mgmt-sub'              = @()
  '0-start-freemode-phone'          = @()
  'ph-home1-joblist-sel'            = @()
  'ph-home1-vinewood-sel'           = @()
  'ph-home1-contacts-sel'           = @()
  'ph-home1-securoserv-sel'         = @()
  'ph-home2-quickjoin-sel'          = @('ph_quickjoin_sel')
  'ph-home2-quickjoin-sel-from-row3' = @('ph_quickjoin_sel')
  'ph-home2-quickjoin-sel-after-back' = @('ph_quickjoin_sel')
  'ph-home2-settings-sel'           = @()
  'qj-list-series-sel'              = @()
  'qj-list-random-sel'              = @('qj_random_sel')
  'qj-random-friends-sel'           = @()
  'qj-random-alone-sel'             = @('qj_alone_sel')
  'qj-yes-sel'                      = @('qj_yes_sel')
  'phone-closed'                    = @()
}
$menuNames = @('m_title', 'm_sub_boss', 'm_sub_securo', 'm_boss', 'm_boss_sel', 'm_ceo_sel', 'm_start_org_sel', 'm_securo', 'm_securo_sel', 'm_retire_sel')
$phoneNames = @('ph_quickjoin_sel', 'qj_random_sel', 'qj_alone_sel', 'qj_yes_sel')
$tpl = @{}
foreach ($n in $menuNames + $phoneNames) {
  $p = if ($n -eq 'm_title') { $earnTitle } else { Join-Path $target "$n.png" }
  $w = 0; $h = 0; $px = [JWSearch]::Load($p, [ref]$w, [ref]$h)
  $tpl[$n] = @{ px = $px; w = $w; h = $h }
}
$fail = 0; $rows = @()
foreach ($state in $expect.Keys) {
  $w = 0; $h = 0; $hay = [JWSearch]::Load((Join-Path $EvidenceDir "$state.png"), [ref]$w, [ref]$h)
  $names = if ((Get-Area $state)[0] -eq 0) { $menuNames } else { $phoneNames }
  $cells = @()
  foreach ($n in $names) {
    $t = $tpl[$n]; $fx = 0; $fy = 0
    $found = [JWSearch]::Find($hay, $w, $h, $t.px, $t.w, $t.h, 40, 0xFF00FF, [ref]$fx, [ref]$fy)
    $want = $expect[$state] -contains $n
    if ($found -ne $want) { $fail++; $cells += "$n=$(if ($found) { '찾음' } else { '없음' })(틀림)" }
    elseif ($found) { $cells += "$n@$($fx + (Get-Area $state)[0]),$($fy + (Get-Area $state)[1])" }
  }
  $rows += '{0,-36} {1}' -f $state, ($(if ($cells) { $cells -join '  ' } else { '(찾힌 것 없음, 기대대로)' }))
}
$rows
$total = ($expect.Keys | ForEach-Object { if ((Get-Area $_)[0] -eq 0) { $menuNames.Count } else { $phoneNames.Count } } | Measure-Object -Sum).Sum
if ($fail) { "FAIL: $fail / $total 칸이 기대와 다름"; exit 1 }
"PASS: $($expect.Count) 상태 x 템플릿 $total 칸이 전부 기대대로 (찾혀야 할 곳에서만 찾힘)"
