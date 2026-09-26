<#
gta-perf-watch.ps1 - GTA V Enhanced 그래픽 변경(A·B 묶음) 적용과 성능 감시.

작업 스케줄러 "GTA Perf Watch" 가 10분마다 gta-perf-watch.vbs 로 숨겨서 실행한다.
게임 창에는 키·클릭·포커스 변경을 하나도 보내지 않는다. 읽기(PresentMon ETW, nvidia-smi,
GetForegroundWindow, GetLastInputInfo, 이벤트 로그)와 게임이 꺼져 있을 때의 settings.xml 수정만 한다.

상태 파일은 저장소 밖 %LOCALAPPDATA%\gta-perf 에 둔다.
  config.json   {"until": "..."}               감시 끝 시각. 판정 루틴이 늘릴 수 있다.
  pending.json  {"reason": "...", "set": {...}} 게임이 꺼진 순간 settings.xml 에 쓸 값. 적용되면 지운다.
  state.json    직전 실행의 GTA 시작 시각과 이벤트 로그 확인 시각.
  perf.csv      실행마다 한 줄(캡처·background·not_running·applied·manual·expired).
  crashes.csv   GTA5_Enhanced 의 Application Error(1000)·WER(1001)·Hang(1002) 이벤트.
  applied.log   settings.xml 을 바꾼 기록과 백업 경로.
  watch.log     오류와 진행 로그.

수동 기록: -ImportPresentMonCsv <csv> -ImportTime "yyyy-MM-dd HH:mm:ss" [-ImportNote ...]
#>
[CmdletBinding()]
param(
    [string]$ImportPresentMonCsv,
    [string]$ImportTime,
    [string]$ImportNote = 'manual'
)

$ErrorActionPreference = 'Stop'
$Dir         = Join-Path $env:LOCALAPPDATA 'gta-perf'
$null        = New-Item -ItemType Directory -Force -Path $Dir
$CapDir      = Join-Path $Dir 'captures'
$null        = New-Item -ItemType Directory -Force -Path $CapDir
$LogFile     = Join-Path $Dir 'watch.log'
$PerfCsv     = Join-Path $Dir 'perf.csv'
$CrashCsv    = Join-Path $Dir 'crashes.csv'
$ConfigFile  = Join-Path $Dir 'config.json'
$StateFile   = Join-Path $Dir 'state.json'
$PendingFile = Join-Path $Dir 'pending.json'
$AppliedLog  = Join-Path $Dir 'applied.log'
$PresentMon  = Join-Path $Dir 'PresentMon-2.6.0-x64.exe'
$Settings    = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rockstar Games\GTAV Enhanced\settings.xml'
$TaskName    = 'GTA Perf Watch'
$GameProc    = 'GTA5_Enhanced'
$CaptureSec  = 60
$SampleSec   = 5
$ActiveIdleS = 10   # 표본 시점에 마지막 입력이 이 초보다 최근이면 그 표본은 "입력 있음"
$Inv         = [Globalization.CultureInfo]::InvariantCulture

$Keys = @('Tessellation', 'WaterQuality', 'Shadow_LongShadows',
          'RTIndirectDiffuse_SecondBounce_Enabled', 'RTReflection_FullRes_Enabled')
$Profiles = [ordered]@{
    'before'  = '2|2|false|false|false'
    'after'   = '3|3|true|true|true'
    'after-A' = '3|3|true|false|false'
}
$Columns = @('time', 'status', 'label') + $Keys + @(
    'span_s', 'disp_fps', 'disp_1pct_low_p99', 'frames_over_100ms', 'max_frametime_ms', 'present_fps',
    'gpu_util_pct', 'gpu_power_w', 'gpu_temp_c', 'vram_used_mib', 'gpu_clock_mhz',
    'idle_start_s', 'idle_end_s', 'idle_min_s', 'active_samples', 'samples', 'fg_ratio', 'macro_activity',
    'gta_start', 'gta_restart', 'crash_events_new', 'note')

function Write-Log([string]$msg) {
    $line = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + ' ' + $msg
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Read-JsonFile([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Write-JsonFile($obj, [string]$path) {
    $tmp = "$path.tmp"
    $obj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

function Add-PerfRow([hashtable]$values) {
    $row = [ordered]@{}
    foreach ($c in $Columns) { $row[$c] = '' }
    foreach ($k in $values.Keys) { $row[$k] = $values[$k] }
    [pscustomobject]$row | Export-Csv -LiteralPath $PerfCsv -Append -NoTypeInformation -Encoding UTF8
}

function Get-SettingValues {
    $result = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Settings)) { return $null }
    $text = [IO.File]::ReadAllText($Settings)
    foreach ($k in $Keys) {
        $m = [regex]::Matches($text, '<' + $k + '\s+value="([^"]*)"')
        if ($m.Count -eq 1) { $result[$k] = $m[0].Groups[1].Value } else { $result[$k] = "?($($m.Count))" }
    }
    return $result
}

function Get-Label($vals) {
    if (-not $vals) { return 'unknown' }
    $sig = ($Keys | ForEach-Object { $vals[$_] }) -join '|'
    foreach ($name in $Profiles.Keys) { if ($Profiles[$name] -eq $sig) { return $name } }
    return 'other'
}

function Test-GameRunning {
    return [bool](Get-Process -Name $GameProc, 'PlayGTAV' -ErrorAction SilentlyContinue)
}

function Invoke-PendingApply {
    $p = Read-JsonFile $PendingFile
    if (-not $p) { return $false }
    if (Test-GameRunning) { return $false }
    $age = (Get-Date) - (Get-Item -LiteralPath $Settings).LastWriteTime
    if ($age.TotalSeconds -lt 15) { Write-Log "pending: settings.xml 이 방금 바뀌어 다음 실행으로 미룸"; return $false }

    $stamp  = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $backup = Join-Path $Dir "settings.pre-apply-$stamp.xml"
    Copy-Item -LiteralPath $Settings -Destination $backup -Force
    $beforeVals = Get-SettingValues

    $bytes  = [IO.File]::ReadAllBytes($Settings)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text   = [IO.File]::ReadAllText($Settings)
    $targets = @{}
    foreach ($prop in $p.set.PSObject.Properties) { $targets[$prop.Name] = [string]$prop.Value }
    foreach ($k in $targets.Keys) {
        $pattern = '(<' + [regex]::Escape($k) + '\s+value=")[^"]*(")'
        if ([regex]::Matches($text, $pattern).Count -ne 1) {
            Write-Log "pending: 키 $k 가 settings.xml 에 정확히 한 번 있지 않아 적용 중단"
            return $false
        }
        $text = [regex]::Replace($text, $pattern, '${1}' + $targets[$k] + '${2}')
    }
    if (Test-GameRunning) { Write-Log 'pending: 쓰기 직전에 게임이 떠서 중단'; return $false }
    [IO.File]::WriteAllText($Settings, $text, (New-Object Text.UTF8Encoding($hasBom)))

    $afterVals = Get-SettingValues
    $bad = @($targets.Keys | Where-Object { $afterVals[$_] -ne $targets[$_] })
    if ($bad.Count -gt 0) {
        Copy-Item -LiteralPath $backup -Destination $Settings -Force
        Write-Log ("pending: 적용 뒤 확인 실패(" + ($bad -join ',') + "), 백업으로 되돌림")
        return $false
    }
    Remove-Item -LiteralPath $PendingFile -Force
    $desc = ($targets.Keys | Sort-Object | ForEach-Object { "$_ $($beforeVals[$_])->$($targets[$_])" }) -join '; '
    Add-Content -LiteralPath $AppliedLog -Encoding UTF8 -Value ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + " [$($p.reason)] $desc | backup $backup")
    $row = @{ time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); status = 'applied'; label = (Get-Label $afterVals); note = "$($p.reason) | backup $backup" }
    foreach ($k in $Keys) { $row[$k] = $afterVals[$k] }
    Add-PerfRow $row
    Write-Log "pending 적용 완료: $desc"
    return $true
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
    $fpid = [GtaPerfNative]::ForegroundPid()
    $p = Get-Process -Id $fpid -ErrorAction SilentlyContinue
    if ($p) { return $p.ProcessName } else { return '' }
}

function ConvertTo-Num($v) {
    $d = 0.0
    if ([double]::TryParse([string]$v, [Globalization.NumberStyles]::Float, $Inv, [ref]$d)) { return $d }
    return [double]::NaN
}

function Get-Percentile($sorted, [double]$p) {
    $n = $sorted.Count
    if ($n -eq 0) { return [double]::NaN }
    $idx = $p / 100.0 * ($n - 1)
    $lo = [math]::Floor($idx); $hi = [math]::Ceiling($idx)
    return $sorted[$lo] + ($sorted[$hi] - $sorted[$lo]) * ($idx - $lo)
}

function Get-PresentMonStats([string]$csvPath) {
    $rows = @(Import-Csv -LiteralPath $csvPath)
    if ($rows.Count -lt 10) { return $null }
    $t0 = ConvertTo-Num $rows[0].TimeInMs
    $t1 = ConvertTo-Num $rows[$rows.Count - 1].TimeInMs
    $span = ($t1 - $t0) / 1000.0
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
    $over = @($disp | Where-Object { $_ -gt 100 }).Count
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

function Get-GpuSample {
    try {
        $line = (& nvidia-smi --query-gpu=utilization.gpu,power.draw,temperature.gpu,memory.used,clocks.gr --format=csv,noheader,nounits 2>$null | Select-Object -First 1)
        $f = $line -split ','
        if ($f.Count -lt 5) { return $null }
        return @(($f | ForEach-Object { ConvertTo-Num $_.Trim() }))
    } catch { return $null }
}

function Get-MacroActivity([datetime]$since) {
    $names = @()
    foreach ($n in 'gta-afk', 'gta-claw', 'gta-macro') {
        $f = Join-Path $env:TEMP "$n.log"
        if ((Test-Path -LiteralPath $f) -and (Get-Item -LiteralPath $f).LastWriteTime -ge $since) { $names += $n }
    }
    return ($names -join '+')
}

function Invoke-Capture([string]$gtaStart) {
    if (-not (Test-Path -LiteralPath $PresentMon)) {
        $src = Join-Path $env:TEMP 'claude\PresentMon-2.6.0-x64.exe'
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $PresentMon -Force }
        else { Write-Log 'PresentMon 없음'; return @{ status = 'error'; note = 'PresentMon missing' } }
    }
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $csv = Join-Path $CapDir "cap-$stamp.csv"
    $start = Get-Date
    $pmArgs = "--process_name $GameProc.exe --timed $CaptureSec --terminate_after_timed --output_file `"$csv`" --session_name GtaPerfWatch --stop_existing_session --no_console_stats"
    $pm = Start-Process -FilePath $PresentMon -ArgumentList $pmArgs -NoNewWindow -PassThru `
        -RedirectStandardOutput (Join-Path $CapDir 'pm-out.txt') -RedirectStandardError (Join-Path $CapDir 'pm-err.txt')

    $gpu = New-Object System.Collections.Generic.List[object]
    $idles = New-Object 'System.Collections.Generic.List[double]'
    $fgHits = 0; $samples = 0
    $idleStart = [GtaPerfNative]::IdleSeconds()
    $deadline = $start.AddSeconds($CaptureSec + 20)
    while (-not $pm.HasExited -and (Get-Date) -lt $deadline) {
        $g = Get-GpuSample; if ($g) { $gpu.Add($g) }
        $idles.Add([GtaPerfNative]::IdleSeconds())
        if ((Get-ForegroundName) -eq $GameProc) { $fgHits++ }
        $samples++
        Start-Sleep -Seconds $SampleSec
    }
    if (-not $pm.HasExited) { $null = $pm.WaitForExit(15000) }
    if (-not $pm.HasExited) { Stop-Process -Id $pm.Id -Force -ErrorAction SilentlyContinue; Write-Log 'PresentMon 시간 초과로 종료' }
    $idleEnd = [GtaPerfNative]::IdleSeconds()

    $row = @{ status = 'capture' }
    if (Test-Path -LiteralPath $csv) {
        $s = Get-PresentMonStats $csv
        if ($s) { foreach ($k in $s.Keys) { $row[$k] = $s[$k] } } else { $row.status = 'capture-empty' }
    } else { $row.status = 'capture-failed'; $row.note = (Get-Content (Join-Path $CapDir 'pm-err.txt') -Raw -ErrorAction SilentlyContinue) }
    if ($gpu.Count) {
        foreach ($i in 0..4) {
            $vals = @($gpu | ForEach-Object { $_[$i] } | Where-Object { -not [double]::IsNaN($_) })
            $avg = ''; if ($vals.Count) { $avg = [math]::Round(($vals | Measure-Object -Average).Average, 1) }
            $row[@('gpu_util_pct', 'gpu_power_w', 'gpu_temp_c', 'vram_used_mib', 'gpu_clock_mhz')[$i]] = $avg
        }
    }
    $row.idle_start_s   = [math]::Round($idleStart, 1)
    $row.idle_end_s     = [math]::Round($idleEnd, 1)
    $row.idle_min_s     = $(if ($idles.Count) { [math]::Round(($idles | Measure-Object -Minimum).Minimum, 1) } else { '' })
    $row.active_samples = @($idles | Where-Object { $_ -ge 0 -and $_ -lt $ActiveIdleS }).Count
    $row.samples        = $samples
    $row.fg_ratio       = $(if ($samples) { [math]::Round($fgHits / $samples, 2) } else { '' })
    $row.macro_activity = Get-MacroActivity $start

    # 캡처 CSV 는 최근 12개만 남긴다(한 개 수 MB).
    Get-ChildItem -LiteralPath $CapDir -Filter 'cap-*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 12 |
        Remove-Item -Force -ErrorAction SilentlyContinue
    return $row
}

function Update-CrashState($state, [string]$gtaStart) {
    $result = @{ gta_restart = ''; crash_events_new = 0 }
    $prevStart = [string]$state.lastGtaStart
    if ($prevStart -and $gtaStart -and $prevStart -ne $gtaStart) { $result.gta_restart = "restarted (prev $prevStart)" }
    elseif ($prevStart -and -not $gtaStart) { $result.gta_restart = "exited (prev $prevStart)" }

    $since = (Get-Date).AddMinutes(-15)
    if ($state.lastEventCheck) { $since = [datetime]::ParseExact([string]$state.lastEventCheck, 'yyyy-MM-dd HH:mm:ss', $Inv) }
    $now = Get-Date
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000, 1001, 1002; StartTime = $since } -ErrorAction Stop |
            Where-Object { $_.Message -match 'GTA5_Enhanced' })
    } catch { $events = @() }
    foreach ($e in $events) {
        [pscustomobject]@{
            time = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'); id = $e.Id; provider = $e.ProviderName
            summary = (($e.Message -split "`r?`n") | Select-Object -First 3) -join ' / '
        } | Export-Csv -LiteralPath $CrashCsv -Append -NoTypeInformation -Encoding UTF8
    }
    $result.crash_events_new = $events.Count
    $state | Add-Member -NotePropertyName lastGtaStart -NotePropertyValue $gtaStart -Force
    $state | Add-Member -NotePropertyName lastEventCheck -NotePropertyValue $now.ToString('yyyy-MM-dd HH:mm:ss') -Force
    return $result
}

# ---------- 수동 기록 모드 ----------
if ($ImportPresentMonCsv) {
    $s = Get-PresentMonStats $ImportPresentMonCsv
    $vals = Get-SettingValues
    $row = @{ time = $ImportTime; status = 'manual'; label = (Get-Label $vals); note = $ImportNote }
    foreach ($k in $Keys) { $row[$k] = $vals[$k] }
    foreach ($k in $s.Keys) { $row[$k] = $s[$k] }
    Add-PerfRow $row
    Write-Log "manual row: $ImportTime $ImportNote"
    return
}

# ---------- 정기 실행 ----------
$mutex = New-Object Threading.Mutex($false, 'Local\GtaPerfWatch')
if (-not $mutex.WaitOne(0)) { exit 0 }
try {
    $config = Read-JsonFile $ConfigFile
    $until = [datetimeoffset]::MaxValue
    if ($config -and $config.until) { $until = [datetimeoffset]::Parse([string]$config.until, $Inv) }
    $expired = [datetimeoffset]::Now -gt $until

    $state = Read-JsonFile $StateFile
    if (-not $state) { $state = [pscustomobject]@{} }
    $g = Get-Process -Name $GameProc -ErrorAction SilentlyContinue | Select-Object -First 1
    $gtaStart = ''
    if ($g) { try { $gtaStart = $g.StartTime.ToString('yyyy-MM-dd HH:mm:ss') } catch { $gtaStart = 'unknown' } }
    $crash = Update-CrashState $state $gtaStart
    Write-JsonFile $state $StateFile

    $now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $vals = Get-SettingValues
    $base = @{ time = $now; label = (Get-Label $vals); gta_start = $gtaStart; gta_restart = $crash.gta_restart; crash_events_new = $crash.crash_events_new }
    foreach ($k in $Keys) { $base[$k] = $vals[$k] }

    if (-not $g) {
        $applied = Invoke-PendingApply
        $base.status = 'not_running'
        if ($applied) { $base.note = 'pending applied this run' } elseif (Test-Path -LiteralPath $PendingFile) { $base.note = 'pending waiting' }
        Add-PerfRow $base
    } elseif ($expired) {
        $base.status = 'expired-skip'; $base.note = 'watch window over; capture skipped'
        Add-PerfRow $base
    } else {
        $fg = Get-ForegroundName
        if ($fg -eq $GameProc -and -not [GtaPerfNative]::ForegroundMinimized()) {
            $cap = Invoke-Capture $gtaStart
            foreach ($k in $cap.Keys) { $base[$k] = $cap[$k] }
            if (Test-Path -LiteralPath $PendingFile) { $base.note = (($base.note, 'pending waiting') | Where-Object { $_ }) -join ' | ' }
        } else {
            $base.status = 'background'; $base.note = "foreground=$fg"
        }
        Add-PerfRow $base
    }

    if ($expired -and -not (Test-Path -LiteralPath $PendingFile)) {
        Write-Log "감시 기간($($config.until)) 끝, 작업 삭제"
        Add-PerfRow @{ time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); status = 'expired'; note = "until $($config.until)" }
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
} catch {
    Write-Log ("오류: " + $_.Exception.Message + ' @ ' + $_.InvocationInfo.PositionMessage)
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
