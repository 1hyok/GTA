# GTA 프레임 제한 도우미. 관리자 권한 예약 작업으로 로그온 때 뜬다.
# 사용자 파일(%USERPROFILE%\.gta-fps-want)에서 0·30·60 숫자 하나만 읽어, 바뀔 때만 RTSS 의 GTA5_Enhanced.exe 프로필에 반영한다.
# 이 스크립트는 관리자만 쓸 수 있는 RTSS 설치 폴더에 둔다.
$ErrorActionPreference = 'Continue'
$rtssDir = 'C:\Program Files (x86)\RivaTuner Statistics Server'
$want = 'C:\Users\rlfjr\.gta-fps-want'
$log = 'C:\Users\rlfjr\.gta-fps-helper.log'
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Rtss {
  [DllImport(@"$rtssDir\RTSSHooks64.dll", CharSet = CharSet.Ansi)] public static extern bool LoadProfile(string name);
  [DllImport(@"$rtssDir\RTSSHooks64.dll", CharSet = CharSet.Ansi)] public static extern bool SaveProfile(string name);
  [DllImport(@"$rtssDir\RTSSHooks64.dll", CharSet = CharSet.Ansi)] public static extern bool SetProfileProperty(string name, ref uint value, uint size);
  [DllImport(@"$rtssDir\RTSSHooks64.dll")] public static extern void UpdateProfiles();
}
"@
$applied = -1
$rtssStartDeferred = $false
while ($true) {
    if (-not (Get-Process RTSS -ErrorAction SilentlyContinue)) {
        # RTSS가 이미 켜져 있으면 프레임 제한을 계속 조절한다. 꺼진 RTSS만 실행 중인 GTA에 다시 붙이지 않고,
        # GTA가 끝난 뒤 시작해 다음 게임 실행부터 적용한다(1007 RTSS 시작 16초 뒤 GTA BEX64 충돌 회피).
        if (Get-Process GTA5_Enhanced -ErrorAction SilentlyContinue) {
            if (-not $rtssStartDeferred) {
                "$(Get-Date -Format s) RTSS start deferred until GTA exits" | Out-File $log -Append -Encoding utf8
                $rtssStartDeferred = $true
            }
            Start-Sleep 5
            continue
        }
        Start-Process "$rtssDir\RTSS.exe"
        Start-Sleep 5
        $rtssStartDeferred = $false
    }
    $fps = 0
    try { $t = ([IO.File]::ReadAllText($want)).Trim(); if ($t -match '^(0|30|60)$') { $fps = [int]$t } } catch {}
    if ($fps -ne $applied) {
        $v = [uint32]$fps
        [void][Rtss]::LoadProfile('GTA5_Enhanced.exe')
        [void][Rtss]::SetProfileProperty('FramerateLimit', [ref]$v, 4)
        [void][Rtss]::SaveProfile('GTA5_Enhanced.exe')
        [Rtss]::UpdateProfiles()
        $applied = $fps
        "$(Get-Date -Format s) fps=$fps" | Out-File $log -Append -Encoding utf8
    }
    Start-Sleep 5
}
