<#
gta-perf-watch.ps1 - GTA V Enhanced 그래픽 사다리(0~4단계) 적용·판정과 성능 감시.

작업 스케줄러 "GTA Perf Watch" 가 10분마다 gta-perf-watch.vbs 로 숨겨서 실행한다.
게임 창에는 키·클릭·포커스 변경을 보내지 않는다. 하는 일은 읽기(PresentMon ETW, nvidia-smi,
GetForegroundWindow, GetLastInputInfo, 이벤트 로그)와, 게임이 꺼져 있을 때의 settings.xml 수정뿐이다.

상태 파일은 %USERPROFILE%\gta-perf(C:\Users\rlfjr\gta-perf)에 둔다. AppData 는 Claude 앱 가상화 때문에 쓰지 않는다.
  ladder.json   사다리 정의와 진행 상태(phase, stage, expected, since, kept, reverted, history).
                없으면 사다리 없이 기록만 한다(stage 열 = pre).
  pending.json  {"reason","created","set":{키:값}} 게임이 꺼진 순간 settings.xml 에 쓸 값.
  config.json   {"until": ...} 사다리가 없을 때의 감시 끝 시각.
  cooling.txt   첫 줄을 cooling 열에 적는다(없으면 flat).
  perf.csv      실행마다 한 줄(obs 열: 캡처 시작·끝에 obs64.exe 가 떠 있었으면 yes, 그 캡처는 판정에서 뺀다). crashes.csv, applied.log, ladder.log, watch.log, launch.log.

판정(사다리 phase=measure/confirm): 지금 조합(expected)과 디스크 값이 같은 전경 캡처가 minCaptures 개 모이면
  표시 FPS 시간 가중 평균 >= fpsTarget, 캡처 중 VRAM 최대 <= vramLimitMiB, 그 단계 동안 GTA 비정상 종료 없음
  (디스플레이 장치 변화로 설명되는 종료는 뺌) 이면 통과. 실패한 단계만 revert 값으로 되돌리고 다음 단계로 간다.
  마지막 단계 뒤에는 confirm 으로 남은 조합을 한 번 더 재고, 실패하면 가장 최근에 남긴 단계를 되돌려 다시 잰다.

수동 기록: -ImportPresentMonCsv <csv> -ImportTime "yyyy-MM-dd HH:mm:ss" [-ImportNote ...]
#>
[CmdletBinding()]
param(
    [string]$ImportPresentMonCsv,
    [string]$ImportTime,
    [string]$ImportNote = 'manual'
)

$ErrorActionPreference = 'Stop'
# AppData 에 두지 않는다: Claude 앱(MSIX)에서 띄운 프로세스가 AppData 에 쓰면 패키지 전용 폴더로 가상화돼
# 작업 스케줄러 쪽과 서로 다른 파일을 보게 된다(0926 실측).
$Dir         = Join-Path $env:USERPROFILE 'gta-perf'
$CapDir      = Join-Path $Dir 'captures'
$null        = New-Item -ItemType Directory -Force -Path $CapDir
$LogFile     = Join-Path $Dir 'watch.log'
$PerfCsv     = Join-Path $Dir 'perf.csv'
$CrashCsv    = Join-Path $Dir 'crashes.csv'
$ConfigFile  = Join-Path $Dir 'config.json'
$StateFile   = Join-Path $Dir 'state.json'
$PendingFile = Join-Path $Dir 'pending.json'
$LadderFile  = Join-Path $Dir 'ladder.json'
$LadderLog   = Join-Path $Dir 'ladder.log'
$AppliedLog  = Join-Path $Dir 'applied.log'
$CoolingFile = Join-Path $Dir 'cooling.txt'
$PresentMon  = Join-Path $Dir 'PresentMon-2.6.0-x64.exe'
$Settings    = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rockstar Games\GTAV Enhanced\settings.xml'
$TaskName    = 'GTA Perf Watch'
$GameProc    = 'GTA5_Enhanced'
$CaptureSec  = 60
$SampleSec   = 5
$ActiveIdleS = 10
$Inv         = [Globalization.CultureInfo]::InvariantCulture

$Keys = @('dlssQuality', 'ResScalingType', 'AAType',
          'Tessellation', 'WaterQuality', 'Shadow_LongShadows',
          'RTIndirectDiffuse_SecondBounce_Enabled', 'RTReflection_FullRes_Enabled',
          'ParticleQuality', 'ShadowQuality', 'GrassQuality', 'UltraShadows_Enabled')
$Columns = @('time', 'status', 'stage', 'cooling', 'obs') + $Keys + @(
    'span_s', 'disp_fps', 'disp_1pct_low_p99', 'frames_over_100ms', 'max_frametime_ms', 'present_fps',
    'gpu_util_pct', 'gpu_power_w', 'gpu_temp_c', 'vram_used_mib', 'vram_max_mib', 'gpu_clock_mhz',
    'gpu_samples', 'temp_max_c', 'temp_median_c', 'power_median_w', 'power_limit_median_w', 'clock_median_mhz',
    'thr_swpower_s', 'thr_swthermal_s', 'thr_hwthermal_s', 'thr_reliability_s',
    'idle_start_s', 'idle_end_s', 'idle_min_s', 'active_samples', 'samples', 'fg_ratio', 'macro_activity',
    'gta_start', 'gta_restart', 'crash_events_new', 'note')

function Write-Log([string]$msg) {
    Add-Content -LiteralPath $LogFile -Encoding UTF8 -Value ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + ' ' + $msg)
}
trap { try { Write-Log ('치명 오류: ' + $_.Exception.Message + ' @ ' + $_.InvocationInfo.PositionMessage) } catch {}; exit 1 }

function Read-JsonFile([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { Write-Log "JSON 읽기 실패 $path : $($_.Exception.Message)"; return $null }
}

function Write-JsonFile($obj, [string]$path) {
    $tmp = "$path.tmp"
    $obj | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

function ConvertTo-Hashtable($obj) {
    $h = [ordered]@{}
    if ($obj) { foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = [string]$p.Value } }
    return $h
}

function Add-PerfRow($values) {
    $row = [ordered]@{}
    foreach ($c in $Columns) { $row[$c] = '' }
    foreach ($k in $values.Keys) { if ($row.Contains($k)) { $row[$k] = $values[$k] } }
    [pscustomobject]$row | Export-Csv -LiteralPath $PerfCsv -Append -NoTypeInformation -Encoding UTF8
}

function Read-SettingsText {
    # 게임이 같은 순간에 저장해도 막지 않도록 쓰기·삭제 공유로 연다.
    $fs = New-Object IO.FileStream($Settings, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try { $sr = New-Object IO.StreamReader($fs, (New-Object Text.UTF8Encoding($false)), $true); return $sr.ReadToEnd() }
    finally { $fs.Dispose() }
}

function Get-SettingValues {
    $result = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Settings)) { return $null }
    $text = Read-SettingsText
    foreach ($k in $Keys) {
        $m = [regex]::Matches($text, '<' + $k + '\s+value="([^"]*)"')
        if ($m.Count -eq 1) { $result[$k] = $m[0].Groups[1].Value } else { $result[$k] = "?($($m.Count))" }
    }
    return $result
}

function Test-GameRunning { return [bool](Get-Process -Name $GameProc, 'PlayGTAV' -ErrorAction SilentlyContinue) }

function Get-Cooling {
    if (Test-Path -LiteralPath $CoolingFile) {
        $first = Get-Content -LiteralPath $CoolingFile -TotalCount 1 -Encoding UTF8
        if ($first -and $first.Trim()) { return $first.Trim() }
    }
    return 'flat'
}

function Invoke-PendingApply {
    $p = Read-JsonFile $PendingFile
    if (-not $p) { return $false }
    if (Test-GameRunning) { return $false }
    # 게임이 종료하며 settings.xml 을 쓰는 중일 수 있어, 마지막 쓰기 뒤 8초가 지날 때까지 기다린다(최대 30초).
    for ($w = 0; $w -lt 30; $w++) {
        if (((Get-Date) - (Get-Item -LiteralPath $Settings).LastWriteTime).TotalSeconds -ge 8) { break }
        Start-Sleep -Seconds 1
    }
    if (Test-GameRunning) { return $false }

    $targets = ConvertTo-Hashtable $p.set
    foreach ($k in $targets.Keys) {
        if ($targets[$k] -cnotmatch '^[a-z0-9.]+$') { Write-Log "pending: 값 형식 거부 $k=$($targets[$k])"; return $false }
    }
    $stamp  = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $backup = Join-Path $Dir "settings.pre-apply-$stamp.xml"
    Copy-Item -LiteralPath $Settings -Destination $backup -Force
    $beforeVals = Get-SettingValues
    $bytes  = [IO.File]::ReadAllBytes($Settings)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text   = Read-SettingsText
    foreach ($k in $targets.Keys) {
        $pattern = '(<' + [regex]::Escape($k) + '\s+value=")[^"]*(")'
        if ([regex]::Matches($text, $pattern).Count -ne 1) { Write-Log "pending: 키 $k 가 정확히 한 번 있지 않아 적용 중단"; return $false }
        $text = [regex]::Replace($text, $pattern, '${1}' + $targets[$k] + '${2}')
    }
    if (Test-GameRunning) { Write-Log 'pending: 쓰기 직전에 게임이 떠서 중단'; return $false }
    $tmp = "$Settings.gpw.tmp"
    try {
        [IO.File]::WriteAllText($tmp, $text, (New-Object Text.UTF8Encoding($hasBom)))
        [IO.File]::Replace($tmp, $Settings, [NullString]::Value)
    } catch {
        Copy-Item -LiteralPath $backup -Destination $Settings -Force
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        Write-Log "pending: 쓰기 실패로 백업 복원 ($($_.Exception.Message))"
        return $false
    }
    $afterVals = Get-SettingValues
    $bad = @($targets.Keys | Where-Object { $afterVals[$_] -cne $targets[$_] })
    if ($bad.Count -gt 0) {
        Copy-Item -LiteralPath $backup -Destination $Settings -Force
        Write-Log ('pending: 적용 뒤 확인 실패(' + ($bad -join ',') + '), 백업으로 되돌림')
        return $false
    }
    Remove-Item -LiteralPath $PendingFile -Force
    $desc = ($targets.Keys | ForEach-Object { "$_ $($beforeVals[$_])->$($targets[$_])" }) -join '; '
    Add-Content -LiteralPath $AppliedLog -Encoding UTF8 -Value ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + " [$($p.reason)] $desc | backup $backup")
    Write-Log "pending 적용 완료: $desc"
    return $true
}

function Set-Pending([hashtable]$set, [string]$reason) {
    if ($set.Count -eq 0) { if (Test-Path -LiteralPath $PendingFile) { Remove-Item -LiteralPath $PendingFile -Force }; return }
    Write-JsonFile ([ordered]@{ reason = $reason; created = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); set = $set }) $PendingFile
}

if (-not ('GtaPerfNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GtaPerfNative {
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    [DllImport("kernel32.dll")] static extern uint GetTickCount();
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    public static double IdleSeconds() {
        LASTINPUTINFO l = new LASTINPUTINFO(); l.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        if (!GetLastInputInfo(ref l)) return -1;
        return (uint)(GetTickCount() - l.dwTime) / 1000.0;
    }
    public static int ForegroundPid() { int pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid); return pid; }
    public static bool ForegroundMinimized() { return IsIconic(GetForegroundWindow()); }
}
'@
}

function Get-ForegroundName {
    $p = Get-Process -Id ([GtaPerfNative]::ForegroundPid()) -ErrorAction SilentlyContinue
    if ($p) { return $p.ProcessName } else { return '' }
}

function ConvertTo-Num($v) {
    $d = 0.0
    if ([double]::TryParse(([string]$v).Trim(), [Globalization.NumberStyles]::Float, $Inv, [ref]$d)) { return $d }
    return [double]::NaN
}

function Get-Percentile($sorted, [double]$p) {
    $n = $sorted.Count
    if ($n -eq 0) { return [double]::NaN }
    $idx = $p / 100.0 * ($n - 1)
    $lo = [int][math]::Floor($idx); $hi = [int][math]::Ceiling($idx)
    return $sorted[$lo] + ($sorted[$hi] - $sorted[$lo]) * ($idx - $lo)
}

function Get-Median($values) {
    $l = New-Object 'System.Collections.Generic.List[double]'
    foreach ($v in $values) { if (-not [double]::IsNaN($v)) { $l.Add($v) } }
    if ($l.Count -eq 0) { return '' }
    $l.Sort()
    return [math]::Round((Get-Percentile $l 50), 1)
}

function Get-PresentMonStats([string]$csvPath) {
    $rows = @(Import-Csv -LiteralPath $csvPath)
    if ($rows.Count -lt 10) { return $null }
    $span = ((ConvertTo-Num $rows[$rows.Count - 1].TimeInMs) - (ConvertTo-Num $rows[0].TimeInMs)) / 1000.0
    if ($span -le 0) { return $null }
    $disp = New-Object 'System.Collections.Generic.List[double]'
    $pres = New-Object 'System.Collections.Generic.List[double]'
    foreach ($r in $rows) {
        $u = ConvertTo-Num $r.MsUntilDisplayed
        $d = ConvertTo-Num $r.MsBetweenDisplayChange
        if (-not [double]::IsNaN($u) -and -not [double]::IsNaN($d) -and $d -gt 0) { $disp.Add($d) }
        $pp = ConvertTo-Num $r.MsBetweenPresents
        if (-not [double]::IsNaN($pp) -and $pp -gt 0) { $pres.Add($pp) }
    }
    $disp.Sort()
    $p99 = Get-Percentile $disp 99
    $over = 0; foreach ($d in $disp) { if ($d -gt 100) { $over++ } }
    $max = 0.0; if ($disp.Count) { $max = $disp[$disp.Count - 1] }
    return @{
        span_s            = [math]::Round($span, 2)
        disp_fps          = [math]::Round($disp.Count / $span, 1)
        disp_1pct_low_p99 = $(if ($p99 -gt 0) { [math]::Round(1000.0 / $p99, 1) } else { '' })
        frames_over_100ms = $over
        max_frametime_ms  = [math]::Round($max, 1)
        present_fps       = [math]::Round($pres.Count / $span, 1)
    }
}

function Get-GpuStats([string]$smiFile) {
    # nvidia-smi -lms 1000 출력: util, power, temp, mem.used, clock, reasons(hex), enforced power limit
    $out = @{}
    if (-not (Test-Path -LiteralPath $smiFile)) { return $out }
    $util = @(); $pow = @(); $temp = @(); $mem = @(); $clk = @(); $lim = @()
    $sw = 0; $swt = 0; $hwt = 0; $rel = 0; $n = 0
    foreach ($line in (Get-Content -LiteralPath $smiFile)) {
        $f = $line -split ','
        if ($f.Count -lt 7) { continue }
        $n++
        $util += ConvertTo-Num $f[0]; $pow += ConvertTo-Num $f[1]; $temp += ConvertTo-Num $f[2]
        $mem += ConvertTo-Num $f[3]; $clk += ConvertTo-Num $f[4]; $lim += ConvertTo-Num $f[6]
        $hex = $f[5].Trim()
        if ($hex -match '^0x[0-9A-Fa-f]+$') {
            $bits = [Convert]::ToUInt64($hex.Substring(2), 16)
            if ($bits -band 0x4)   { $sw++ }
            if ($bits -band 0x20)  { $swt++ }
            if ($bits -band 0x40)  { $hwt++ }
            if ($bits -band 0x400) { $rel++ }
        }
    }
    if ($n -eq 0) { return $out }
    $avg = { param($a) $v = @($a | Where-Object { -not [double]::IsNaN($_) }); if ($v.Count) { [math]::Round(($v | Measure-Object -Average).Average, 1) } else { '' } }
    $mx  = { param($a) $v = @($a | Where-Object { -not [double]::IsNaN($_) }); if ($v.Count) { [math]::Round(($v | Measure-Object -Maximum).Maximum, 1) } else { '' } }
    $out.gpu_samples          = $n
    $out.gpu_util_pct         = & $avg $util
    $out.gpu_power_w          = & $avg $pow
    $out.gpu_temp_c           = & $avg $temp
    $out.vram_used_mib        = & $avg $mem
    $out.vram_max_mib         = & $mx $mem
    $out.gpu_clock_mhz        = & $avg $clk
    $out.temp_max_c           = & $mx $temp
    $out.temp_median_c        = Get-Median $temp
    $out.power_median_w       = Get-Median $pow
    $out.power_limit_median_w = Get-Median $lim
    $out.clock_median_mhz     = Get-Median $clk
    $out.thr_swpower_s        = $sw
    $out.thr_swthermal_s      = $swt
    $out.thr_hwthermal_s      = $hwt
    $out.thr_reliability_s    = $rel
    return $out
}

function Test-ObsRunning { return [bool](Get-Process -Name 'obs64' -ErrorAction SilentlyContinue) }

function Get-MacroActivity([datetime]$since) {
    $names = @()
    foreach ($n in 'gta-afk', 'gta-claw', 'gta-macro') {
        $f = Join-Path $env:TEMP "$n.log"
        if ((Test-Path -LiteralPath $f) -and (Get-Item -LiteralPath $f).LastWriteTime -ge $since) { $names += $n }
    }
    return ($names -join '+')
}

function Invoke-Capture {
    if (-not (Test-Path -LiteralPath $PresentMon)) {
        $src = Join-Path $env:TEMP 'claude\PresentMon-2.6.0-x64.exe'
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $PresentMon -Force }
        else { Write-Log 'PresentMon 없음'; return @{ status = 'error'; note = 'PresentMon missing' } }
    }
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $csv = Join-Path $CapDir "cap-$stamp.csv"
    $smiFile = Join-Path $CapDir "smi-$stamp.csv"
    $start = Get-Date
    $obsAtStart = Test-ObsRunning
    $pmArgs = "--process_name $GameProc.exe --timed $CaptureSec --terminate_after_timed --output_file `"$csv`" --session_name GtaPerfWatch --stop_existing_session --no_console_stats"
    $pm = Start-Process -FilePath $PresentMon -ArgumentList $pmArgs -NoNewWindow -PassThru `
        -RedirectStandardOutput (Join-Path $CapDir 'pm-out.txt') -RedirectStandardError (Join-Path $CapDir 'pm-err.txt')
    $smi = Start-Process -FilePath 'nvidia-smi.exe' -NoNewWindow -PassThru -RedirectStandardOutput $smiFile -RedirectStandardError (Join-Path $CapDir 'smi-err.txt') `
        -ArgumentList '--query-gpu=utilization.gpu,power.draw,temperature.gpu,memory.used,clocks.gr,clocks_event_reasons.active,enforced.power.limit --format=csv,noheader,nounits -lms 1000'

    $idles = New-Object 'System.Collections.Generic.List[double]'
    $fgHits = 0; $samples = 0
    $idleStart = [GtaPerfNative]::IdleSeconds()
    $deadline = $start.AddSeconds($CaptureSec + 20)
    while (-not $pm.HasExited -and (Get-Date) -lt $deadline) {
        $idles.Add([GtaPerfNative]::IdleSeconds())
        if ((Get-ForegroundName) -eq $GameProc) { $fgHits++ }
        $samples++
        Start-Sleep -Seconds $SampleSec
    }
    if (-not $pm.HasExited) { $null = $pm.WaitForExit(15000) }
    if (-not $pm.HasExited) { Stop-Process -Id $pm.Id -Force -ErrorAction SilentlyContinue; Write-Log 'PresentMon 시간 초과로 종료' }
    if (-not $smi.HasExited) { Stop-Process -Id $smi.Id -Force -ErrorAction SilentlyContinue }
    $idleEnd = [GtaPerfNative]::IdleSeconds()

    $row = @{ status = 'capture' }
    $row.obs = $(if ($obsAtStart -or (Test-ObsRunning)) { 'yes' } else { 'no' })
    if (Test-Path -LiteralPath $csv) {
        $s = Get-PresentMonStats $csv
        if ($s) { foreach ($k in $s.Keys) { $row[$k] = $s[$k] } } else { $row.status = 'capture-empty' }
    } else {
        $row.status = 'capture-failed'
        $row.note = (Get-Content (Join-Path $CapDir 'pm-err.txt') -Raw -ErrorAction SilentlyContinue)
    }
    $g = Get-GpuStats $smiFile
    foreach ($k in $g.Keys) { $row[$k] = $g[$k] }
    $row.idle_start_s   = [math]::Round($idleStart, 1)
    $row.idle_end_s     = [math]::Round($idleEnd, 1)
    $row.idle_min_s     = $(if ($idles.Count) { [math]::Round(($idles | Measure-Object -Minimum).Minimum, 1) } else { '' })
    $row.active_samples = @($idles | Where-Object { $_ -ge 0 -and $_ -lt $ActiveIdleS }).Count
    $row.samples        = $samples
    $row.fg_ratio       = $(if ($samples) { [math]::Round($fgHits / $samples, 2) } else { '' })
    $row.macro_activity = Get-MacroActivity $start
    Get-ChildItem -LiteralPath $CapDir -Filter '*-2*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 24 |
        Remove-Item -Force -ErrorAction SilentlyContinue
    return $row
}

function Update-CrashState($state, [string]$gtaStart) {
    $result = @{ gta_restart = ''; crash_events_new = 0 }
    $prevStart = [string]$state.lastGtaStart
    if ($prevStart -and $gtaStart -and $prevStart -ne $gtaStart) { $result.gta_restart = "restarted (prev $prevStart)" }
    elseif ($prevStart -and -not $gtaStart) { $result.gta_restart = "exited (prev $prevStart)" }
    $lastId = 0; if ($state.lastRecordId) { $lastId = [long]$state.lastRecordId }
    $since = (Get-Date).AddMinutes(-15)
    if ($state.lastEventCheck) { try { $since = [datetime]::ParseExact([string]$state.lastEventCheck, 'yyyy-MM-dd HH:mm:ss', $Inv).AddMinutes(-2) } catch {} }
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000, 1001, 1002; StartTime = $since } -ErrorAction Stop |
            Where-Object { $_.RecordId -gt $lastId -and $_.Message -match 'GTA5_Enhanced' } | Sort-Object RecordId)
    } catch { $events = @() }
    foreach ($e in $events) {
        [pscustomobject]@{
            time = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'); id = $e.Id; provider = $e.ProviderName; recordId = $e.RecordId
            summary = (($e.Message -split "`r?`n") | Select-Object -First 3) -join ' / '
        } | Export-Csv -LiteralPath $CrashCsv -Append -NoTypeInformation -Encoding UTF8
        if ($e.RecordId -gt $lastId) { $lastId = $e.RecordId }
    }
    # 한 번의 충돌이 1000 과 1001 을 같이 남기므로 1000·1002 만 센다.
    $result.crash_events_new = @($events | Where-Object { $_.Id -ne 1001 }).Count
    $state | Add-Member -NotePropertyName lastGtaStart -NotePropertyValue $gtaStart -Force
    $state | Add-Member -NotePropertyName lastEventCheck -NotePropertyValue (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') -Force
    $state | Add-Member -NotePropertyName lastRecordId -NotePropertyValue $lastId -Force
    return $result
}

function Get-KnownCrashCause([datetime]$t) {
    try {
        $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $t.AddMinutes(-2); EndTime = $t.AddMinutes(2) } -ErrorAction Stop |
            Where-Object { $_.Message -match 'DISPLAY\\|MONITOR\\|디스플레이|display' })
        if ($ev.Count) { return "display change $($ev[0].TimeCreated.ToString('HH:mm:ss')) $($ev[0].ProviderName)" }
    } catch {}
    return ''
}

function Get-ComboSig($vals) { return (($Keys | ForEach-Object { "$_=$($vals[$_])" }) -join ';') }

function Test-Matches($vals, $expected) {
    foreach ($p in $expected.PSObject.Properties) { if ($vals[$p.Name] -cne [string]$p.Value) { return $false } }
    return $true
}

function Get-StageLabel($ladder) {
    if (-not $ladder) { return 'pre' }
    switch ($ladder.state.phase) {
        'measure' { return 'S' + $ladder.state.stage }
        'confirm' { return 'confirm' + $ladder.state.round }
        default   { return 'done' }
    }
}

function Write-LadderLog([string]$msg) {
    Add-Content -LiteralPath $LadderLog -Encoding UTF8 -Value ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + ' ' + $msg)
}

function Invoke-LadderJudge($ladder) {
    $st = $ladder.state
    $label = Get-StageLabel $ladder
    $since = [datetime]::ParseExact([string]$st.since, 'yyyy-MM-dd HH:mm:ss', $Inv)
    $rows = @(Import-Csv -LiteralPath $PerfCsv | Where-Object {
        $_.status -eq 'capture' -and $_.obs -eq 'no' -and $_.stage -eq $label -and (ConvertTo-Num $_.fg_ratio) -ge 0.9 -and
        [datetime]::ParseExact($_.time, 'yyyy-MM-dd HH:mm:ss', $Inv) -ge $since })
    if ($rows.Count -lt [int]$ladder.minCaptures) { return }

    $spanSum = 0.0; $frameSum = 0.0; $vmax = 0.0
    foreach ($r in $rows) {
        $sp = ConvertTo-Num $r.span_s; $fps = ConvertTo-Num $r.disp_fps
        if (-not [double]::IsNaN($sp) -and -not [double]::IsNaN($fps)) { $spanSum += $sp; $frameSum += $sp * $fps }
        $vm = ConvertTo-Num $r.vram_max_mib; if ([double]::IsNaN($vm)) { $vm = ConvertTo-Num $r.vram_used_mib }
        if (-not [double]::IsNaN($vm) -and $vm -gt $vmax) { $vmax = $vm }
    }
    $avgFps = 0.0; if ($spanSum -gt 0) { $avgFps = $frameSum / $spanSum }
    $crashes = @(); $excluded = @()
    if (Test-Path -LiteralPath $CrashCsv) {
        foreach ($c in (Import-Csv -LiteralPath $CrashCsv | Where-Object { $_.id -ne '1001' })) {
            $ct = [datetime]::ParseExact($c.time, 'yyyy-MM-dd HH:mm:ss', $Inv)
            if ($ct -lt $since) { continue }
            $cause = Get-KnownCrashCause $ct
            if ($cause) { $excluded += "$($c.time) ($cause)" } else { $crashes += $c.time }
        }
    }
    $reasons = @()
    if ($avgFps -lt [double]$ladder.fpsTarget) { $reasons += ('avg FPS {0:N1} < {1}' -f $avgFps, $ladder.fpsTarget) }
    if ($vmax -gt [double]$ladder.vramLimitMiB) { $reasons += ('VRAM {0:N0} MiB > {1}' -f $vmax, $ladder.vramLimitMiB) }
    if ($crashes.Count) { $reasons += ('crash ' + ($crashes -join ',')) }
    $pass = ($reasons.Count -eq 0)

    $stages = @($ladder.stages)
    $current = Get-SettingValues
    $expected = ConvertTo-Hashtable $st.expected
    $entry = [ordered]@{
        time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); label = $label; phase = [string]$st.phase; stage = $st.stage
        result = $(if ($pass) { 'pass' } else { 'fail' }); avgFps = [math]::Round($avgFps, 1); captures = $rows.Count
        spanSec = [math]::Round($spanSum, 0); maxVramMiB = [math]::Round($vmax, 0); crashes = ($crashes -join ','); excludedCrashes = ($excluded -join ',')
        reason = ($reasons -join '; '); action = ''
    }
    $kept = @($st.kept | Where-Object { $_ -ne $null }); $reverted = @($st.reverted | Where-Object { $_ -ne $null })

    if ($st.phase -eq 'measure') {
        $sid = [int]$st.stage
        if ($pass) { $kept += $sid }
        else {
            $reverted += $sid
            foreach ($p in $stages[$sid].revert.PSObject.Properties) { $expected[$p.Name] = [string]$p.Value }
        }
        $next = $sid + 1
        if ($next -lt $stages.Count) {
            foreach ($p in $stages[$next].set.PSObject.Properties) { $expected[$p.Name] = [string]$p.Value }
            $st.stage = $next
            $entry.action = $(if ($pass) { "keep S$sid, apply S$next" } else { "revert S$sid, apply S$next" })
        } else {
            $st.phase = 'confirm'; $st | Add-Member -NotePropertyName round -NotePropertyValue 1 -Force
            $entry.action = $(if ($pass) { "keep S$sid, confirm final combo" } else { "revert S$sid, confirm final combo" })
        }
    } elseif ($st.phase -eq 'confirm') {
        if ($pass) {
            $st.phase = 'done'
            $entry.action = 'final combo confirmed, ladder done'
        } elseif ($kept.Count -gt 0) {
            $last = $kept[$kept.Count - 1]
            $kept = @($kept | Select-Object -First ($kept.Count - 1)); $reverted += $last
            foreach ($p in $stages[$last].revert.PSObject.Properties) { $expected[$p.Name] = [string]$p.Value }
            $st.round = [int]$st.round + 1
            $entry.action = "confirm failed, revert S$last and confirm again"
        } else {
            $st.phase = 'done'
            $entry.action = 'confirm failed with nothing left to revert, ladder done'
        }
    }
    $st.expected = [pscustomobject]$expected
    $st.kept = $kept; $st.reverted = $reverted
    $st.since = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $hist = @($st.history | Where-Object { $_ -ne $null }); $hist += [pscustomobject]$entry; $st.history = $hist

    $diff = [ordered]@{}
    foreach ($k in $expected.Keys) { if ($current[$k] -cne $expected[$k]) { $diff[$k] = $expected[$k] } }
    if ($diff.Count) { Set-Pending $diff "ladder: $($entry.action)" }
    Write-JsonFile $ladder $LadderFile
    Write-LadderLog ("$label $($entry.result) avg={0:N1}fps n={1} vramMax={2:N0} crashes={3} -> {4}{5}" -f $avgFps, $rows.Count, $vmax, $crashes.Count, $entry.action, $(if ($reasons.Count) { " [$($entry.reason)]" } else { '' }))
}

# ---------- 수동 기록 모드 ----------
if ($ImportPresentMonCsv) {
    $s = Get-PresentMonStats $ImportPresentMonCsv
    $vals = Get-SettingValues
    $row = @{ time = $ImportTime; status = 'manual'; stage = 'pre'; cooling = (Get-Cooling); obs = 'no'; note = $ImportNote }
    foreach ($k in $Keys) { $row[$k] = $vals[$k] }
    foreach ($k in $s.Keys) { $row[$k] = $s[$k] }
    Add-PerfRow $row
    Write-Log "manual row: $ImportTime $ImportNote"
    return
}

# ---------- 정기 실행 ----------
$mutex = New-Object Threading.Mutex($false, 'Local\GtaPerfWatch')
$got = $false
try { $got = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $got = $true }
if (-not $got) { exit 0 }
$RunStart = Get-Date
try {
    $ladder = Read-JsonFile $LadderFile
    $deadline = [datetimeoffset]::MaxValue
    try {
        if ($ladder -and $ladder.deadline) { $deadline = [datetimeoffset]::Parse([string]$ladder.deadline, $Inv) }
        else { $config = Read-JsonFile $ConfigFile; if ($config -and $config.until) { $deadline = [datetimeoffset]::Parse([string]$config.until, $Inv) } }
    } catch { Write-Log "끝 시각 해석 실패: $($_.Exception.Message)" }
    $expired = [datetimeoffset]::Now -gt $deadline

    $state = Read-JsonFile $StateFile
    if (-not $state) { $state = [pscustomobject]@{} }
    $g = Get-Process -Name $GameProc -ErrorAction SilentlyContinue | Select-Object -First 1
    $gtaStart = ''
    if ($g) { try { $gtaStart = $g.StartTime.ToString('yyyy-MM-dd HH:mm:ss') } catch { $gtaStart = 'unknown' } }
    $crash = Update-CrashState $state $gtaStart
    Write-JsonFile $state $StateFile

    $applied = $false
    $note = @()
    if (-not $g) {
        $applied = Invoke-PendingApply
        if ($applied) { $note += 'pending applied this run' }
        # 게임이 값을 되돌렸으면 다시 올린다(같은 조합에서 두 번까지).
        if ($ladder -and $ladder.state.phase -ne 'done' -and -not (Test-Path -LiteralPath $PendingFile)) {
            $vals = Get-SettingValues
            if (-not (Test-Matches $vals $ladder.state.expected)) {
                $sig = Get-ComboSig (ConvertTo-Hashtable $ladder.state.expected)
                $count = 0; if ($state.reapplySig -eq $sig) { $count = [int]$state.reapplyCount }
                if ($count -lt 2) {
                    $diff = [ordered]@{}
                    foreach ($p in $ladder.state.expected.PSObject.Properties) { if ($vals[$p.Name] -cne [string]$p.Value) { $diff[$p.Name] = [string]$p.Value } }
                    Set-Pending $diff 'ladder: game changed values, reapply'
                    $state | Add-Member -NotePropertyName reapplySig -NotePropertyValue $sig -Force
                    $state | Add-Member -NotePropertyName reapplyCount -NotePropertyValue ($count + 1) -Force
                    Write-JsonFile $state $StateFile
                    $note += ('game changed values: ' + (($diff.Keys | ForEach-Object { "$_ $($vals[$_])->$($diff[$_])" }) -join ', '))
                    Write-LadderLog ('mismatch after restart, reapply: ' + ($diff.Keys -join ','))
                    if (Invoke-PendingApply) { $applied = $true; $note += 'reapplied' }
                } else {
                    $note += 'game keeps rejecting values; giving up reapply'
                    Write-LadderLog "reapply gave up for $sig"
                }
            }
        }
    }

    $vals = Get-SettingValues
    $stageLabel = Get-StageLabel $ladder
    if ($ladder -and $ladder.state.phase -ne 'done' -and -not (Test-Matches $vals $ladder.state.expected)) { $stageLabel = $(if (Test-Path -LiteralPath $PendingFile) { 'waiting-apply' } else { 'mismatch' }) }
    $base = @{ time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); stage = $stageLabel; cooling = (Get-Cooling); obs = $(if (Test-ObsRunning) { 'yes' } else { 'no' })
               gta_start = $gtaStart; gta_restart = $crash.gta_restart; crash_events_new = $crash.crash_events_new }
    foreach ($k in $Keys) { $base[$k] = $vals[$k] }

    if (-not $g) {
        $base.status = 'not_running'
    } elseif ($expired) {
        $base.status = 'expired-skip'; $note += 'watch window over; capture skipped'
    } elseif ((Get-ForegroundName) -eq $GameProc -and -not [GtaPerfNative]::ForegroundMinimized()) {
        $cap = Invoke-Capture
        foreach ($k in $cap.Keys) { if ($k -eq 'note') { if ($cap.note) { $note += $cap.note } } else { $base[$k] = $cap[$k] } }
    } else {
        $base.status = 'background'; $note += ('foreground=' + (Get-ForegroundName))
    }
    if (Test-Path -LiteralPath $PendingFile) { $note += 'pending waiting' }
    $base.note = ($note -join ' | ')
    Add-PerfRow $base

    if ($ladder -and $base.status -eq 'capture' -and $stageLabel -ne 'mismatch' -and $ladder.state.phase -in @('measure', 'confirm') -and -not $expired) {
        Invoke-LadderJudge $ladder
    }

    # 적용 대기가 있고 게임이 떠 있으면, 이 실행이 9분까지 3초 간격으로 게임 종료를 지켜보다가 꺼지는 즉시 적용한다.
    # (10분 간격 실행만으로는 0926 13:59~14:00 처럼 1분 안에 다시 켜는 경우를 놓친다.)
    if ((Test-Path -LiteralPath $PendingFile) -and (Test-GameRunning) -and -not $expired) {
        $pollEnd = $RunStart.AddMinutes(9)
        while ((Get-Date) -lt $pollEnd -and (Test-Path -LiteralPath $PendingFile)) {
            if (-not (Test-GameRunning)) {
                if (Invoke-PendingApply) {
                    $applied = $true
                    $v2 = Get-SettingValues
                    $r2 = @{ time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); status = 'applied'; stage = (Get-StageLabel $ladder); cooling = (Get-Cooling); obs = $(if (Test-ObsRunning) { 'yes' } else { 'no' }); note = 'applied right after game exit (poll)' }
                    foreach ($k in $Keys) { $r2[$k] = $v2[$k] }
                    Add-PerfRow $r2
                }
                break
            }
            Start-Sleep -Seconds 3
        }
    }
    $ladderDone = ($ladder -and $ladder.state.phase -eq 'done')
    if (($expired -or $ladderDone) -and -not $applied -and -not (Test-Path -LiteralPath $PendingFile)) {
        $why = $(if ($ladderDone) { 'ladder done' } else { "deadline $deadline" })
        Write-Log "감시 종료($why), 작업 삭제"
        if ($ladder) { Write-LadderLog "watch ended ($why)" }
        Add-PerfRow @{ time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); status = 'expired'; stage = $stageLabel; note = $why }
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
} catch {
    Write-Log ('오류: ' + $_.Exception.Message + ' @ ' + $_.InvocationInfo.PositionMessage)
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
