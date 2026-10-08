#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $env:USERPROFILE 'gta-perf\frame-watch'),
    [string]$PerfDirectory = (Join-Path $env:LOCALAPPDATA 'gta-perf'),
    [string]$PresentMon = (Join-Path $env:USERPROFILE 'gta-perf\PresentMon-2.6.0-x64.exe'),
    [int]$RunSeconds = 0,
    [switch]$LibraryOnly
)
$ErrorActionPreference = 'Stop'

function New-DropState {
    @{ Session = ''; Seen = ''; Healthy = @(); Low = 0; Recovery = 0; Armed = $true; Reference = 0.0 }
}

function Update-DropState($State, $Sample) {
    if ($State.Session -ne $Sample.session) {
        $fresh = New-DropState
        foreach ($key in @($fresh.Keys)) { $State[$key] = $fresh[$key] }
        $State.Session = $Sample.session
    }
    if (-not $Sample.eligible) { $State.Low = 0; $State.Recovery = 0; return $null }
    if ($State.Seen -eq $Sample.fps_time) { return $null }
    $State.Seen = $Sample.fps_time
    $fps = [double]$Sample.fps
    if ($State.Healthy.Count -lt 6) {
        $State.Healthy += $fps
        return $null
    }
    $sorted = @($State.Healthy | Sort-Object)
    $reference = [double]$sorted[[int][Math]::Floor($sorted.Count / 2)]
    if (-not $State.Armed) {
        if ($fps -ge $State.Reference * 0.8) { $State.Recovery++ } else { $State.Recovery = 0 }
        if ($State.Recovery -ge 3) { $State.Armed = $true; $State.Low = 0 }
        return $null
    }
    if ($reference -ge 50 -and $fps -le $reference * 0.6 -and ($reference - $fps) -ge 20) {
        $State.Low++
        if ($State.Low -ge 3) {
            $State.Armed = $false
            $State.Reference = $reference
            return [pscustomobject]@{ baseline_fps = $reference; fps = $fps; consecutive_samples = $State.Low }
        }
    } else {
        $State.Low = 0
        # Do not teach a developing collapse as the normal baseline.
        if ($fps -ge $reference * 0.7) { $State.Healthy = @(@($State.Healthy + $fps) | Select-Object -Last 30) }
    }
    return $null
}

function Read-LatestPerf([string]$Directory, [datetime]$Now) {
    $path = Join-Path $Directory ($Now.ToString('yyyyMMdd') + '.csv')
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $header = Get-Content -LiteralPath $path -TotalCount 1
    $tail = @(Get-Content -LiteralPath $path -Tail 3)
    foreach ($line in @($tail | Select-Object -Last 3 | Sort-Object -Descending)) {
        try {
            $row = @($header, $line) | ConvertFrom-Csv
            $stamp = [datetime]::ParseExact($row.time, 'yyyy-MM-ddTHH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
            $fps = 0.0
            if (($Now - $stamp).TotalSeconds -ge 0 -and ($Now - $stamp).TotalSeconds -le 30 -and
                [double]::TryParse($row.fps_avg, [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture, [ref]$fps) -and $fps -gt 0) {
                return [pscustomobject]@{ Path = $path; Time = $stamp; Fps = $fps; Row = $row }
            }
        } catch { }
    }
    return $null
}

function Test-FpsEligibility($Perf, [datetime]$GameStarted, [datetime]$StableSince, [datetime]$Now, [bool]$Foreground) {
    # gta-turbo captures for two seconds before writing. Require a conservative
    # 20-second continuously observed foreground window, including capture time.
    return ($null -ne $Perf -and $Foreground -and $Perf.Time -gt $GameStarted.AddSeconds(20) -and
        $Perf.Time -ge $StableSince.AddSeconds(20) -and ($Now - $Perf.Time).TotalSeconds -le 30)
}

function Save-Json($Value, [string]$Path) {
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath ($Path + '.tmp') -Encoding UTF8
    Move-Item -LiteralPath ($Path + '.tmp') -Destination $Path -Force
}

function Append-Json($Value, [string]$Path) {
    $Value | ConvertTo-Json -Depth 8 -Compress | Add-Content -LiteralPath $Path -Encoding UTF8
}

function Start-FrameCapture([string]$Executable, [int]$GameId, [string]$Directory) {
    if (-not (Test-Path -LiteralPath $Executable)) { return @{ status = 'unavailable'; reason = 'PresentMon executable missing' } }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.Arguments = '--process_id ' + $GameId + ' --output_file "' + (Join-Path $Directory 'frames.csv') +
        '" --timed 15 --terminate_after_timed --no_console_stats --v2_metrics --session_name gta_drop_' + [guid]::NewGuid().ToString('N')
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    try {
        $process = [Diagnostics.Process]::Start($info)
        return @{ status = 'running'; process = $process; started = Get-Date
            stdout = $process.StandardOutput.ReadToEndAsync(); stderr = $process.StandardError.ReadToEndAsync() }
    } catch { return @{ status = 'failed'; reason = $_.Exception.Message } }
}

function Complete-FrameCapture($Capture, [string]$Directory) {
    if ($Capture.status -ne 'running') { return }
    if (-not $Capture.process.HasExited -and ((Get-Date) - $Capture.started).TotalSeconds -lt 25) { return }
    $timedOut = -not $Capture.process.HasExited
    if ($timedOut) { $Capture.process.Kill(); $null = $Capture.process.WaitForExit(3000) }
    $Capture.status = if ($timedOut) { 'timeout' } elseif ($Capture.process.ExitCode -eq 0) { 'exited' } else { 'failed' }
    $Capture.stdout.GetAwaiter().GetResult() | Set-Content (Join-Path $Directory 'presentmon.stdout.txt')
    $Capture.stderr.GetAwaiter().GetResult() | Set-Content (Join-Path $Directory 'presentmon.stderr.txt')
    $frames = Join-Path $Directory 'frames.csv'
    $rows = if (Test-Path $frames) { @(Import-Csv $frames).Count } else { 0 }
    Save-Json @{ status = $Capture.status; exit_code = $Capture.process.ExitCode; rows = $rows
        usable = ($Capture.status -eq 'exited' -and $rows -gt 10)
        limitation = 'ETW frame timings only; no kernel GPU memory eviction trace. Correlate foreground.jsonl.' } (Join-Path $Directory 'capture.json')
    $Capture.process.Dispose()
}

if ($LibraryOnly) { return }
$mutex = New-Object Threading.Mutex($false, 'Local\GTAFrameEvidenceWatch')
$ownsMutex = $false
try { $ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
if (-not $ownsMutex) { $mutex.Dispose(); exit 0 }
$null = New-Item -ItemType Directory -Force -Path $OutputDirectory
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FrameWatchNative {
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint id);
    public static uint ForegroundPid() { uint id; GetWindowThreadProcessId(GetForegroundWindow(), out id); return id; }
}
'@
$state = New-DropState
$ring = New-Object 'Collections.Generic.List[object]'
$stableSince = Get-Date
$lastForeground = -1
$lastPoll = Get-Date
$nextSample = Get-Date
$start = Get-Date
$incident = $null
$game = $null
$sourceHash = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
try {
    while ($RunSeconds -eq 0 -or ((Get-Date) - $start).TotalSeconds -lt $RunSeconds) {
        $now = Get-Date
        $foregroundId = [FrameWatchNative]::ForegroundPid()
        if ($foregroundId -ne $lastForeground -or ($now - $lastPoll).TotalSeconds -gt 3) {
            $stableSince = $now
            $change = @{ time = $now.ToString('o'); foreground_pid = $foregroundId; poll_gap_seconds = ($now - $lastPoll).TotalSeconds }
            Append-Json $change (Join-Path $OutputDirectory 'foreground.jsonl')
            if ($incident) { Append-Json $change (Join-Path $incident.Directory 'foreground.jsonl') }
            $lastForeground = $foregroundId
        }
        $lastPoll = $now
        if ($incident) { Complete-FrameCapture $incident.Capture $incident.Directory }
        if ($now -ge $nextSample) {
            $nextSample = $now.AddSeconds(5)
            try {
                $games = @(Get-Process -Name GTA5_Enhanced -ErrorAction SilentlyContinue)
                $game = if ($games.Count -eq 1) { $games[0] } else { $null }
                $perf = Read-LatestPerf $PerfDirectory $now
                $memory = @(); $memoryError = $null
                if ($game) {
                    try {
                        $counters = Get-Counter '\GPU Process Memory(*)\Dedicated Usage', '\GPU Process Memory(*)\Shared Usage', '\GPU Process Memory(*)\Total Committed' -ErrorAction Stop
                        $memory = @($counters.CounterSamples | Where-Object { $_.InstanceName -like "pid_$($game.Id)_*" } |
                            Select-Object InstanceName, Path, CookedValue, Status)
                        if (-not $memory.Count) { $memoryError = 'No counters for current GTA PID' }
                    } catch { $memoryError = $_.Exception.Message }
                }
                $session = if ($game) { "$($game.Id):$($game.StartTime.ToString('o'))" } else { '' }
                $eligible = $false
                if ($game) { $eligible = Test-FpsEligibility $perf $game.StartTime $stableSince $now ($foregroundId -eq $game.Id) }
                $sample = [pscustomobject]@{
                    time = $now.ToString('o'); session = $session; game_pid = $(if ($game) { $game.Id } else { $null })
                    foreground_pid = $foregroundId; eligible = $eligible
                    fps_time = $(if ($perf) { $perf.Time.ToString('o') } else { $null })
                    fps = $(if ($perf) { $perf.Fps } else { $null }); telemetry = $(if ($perf) { $perf.Row } else { $null })
                    gpu_memory = $memory; memory_error = $memoryError
                    source_status = $(if ($perf) { 'fresh' } else { 'missing_stale_or_invalid' })
                }
                Append-Json $sample (Join-Path $OutputDirectory ($now.ToString('yyyyMMdd') + '.jsonl'))
                $ring.Add($sample)
                while ($ring.Count -and ($now - [datetime]$ring[0].time).TotalSeconds -gt 120) { $ring.RemoveAt(0) }
                $drop = Update-DropState $state $sample
                if ($drop -and -not $incident) {
                    $directory = Join-Path $OutputDirectory ('incidents\' + $now.ToString('yyyyMMdd-HHmmss-fff'))
                    $null = New-Item -ItemType Directory -Force -Path $directory
                    foreach ($entry in $ring) { Append-Json $entry (Join-Path $directory 'samples.jsonl') }
                    Get-Content (Join-Path $OutputDirectory 'foreground.jsonl') -Tail 200 | Set-Content (Join-Path $directory 'foreground.jsonl') -Encoding UTF8
                    Save-Json @{ detected = $now.ToString('o'); kind = 'suspected_frame_drop'; session = $session
                        threshold = $drop; source = $perf.Path; source_hash = $sourceHash
                        limitation = 'Scene/menu/loading changes can also reduce FPS. This is evidence, not a root-cause verdict.'
                        gpu_kernel_trace = 'not_collected_requires_privileged_diagnostic_session' } (Join-Path $directory 'incident.json')
                    $capture = Start-FrameCapture $PresentMon $game.Id $directory
                    if ($capture.status -ne 'running') { Save-Json $capture (Join-Path $directory 'capture.json') }
                    $incident = @{ Directory = $directory; Until = $now.AddSeconds(120); Capture = $capture }
                    Append-Json @{ time = $now.ToString('o'); event = 'suspected_frame_drop'; directory = $directory; threshold = $drop } (Join-Path $OutputDirectory 'alerts.jsonl')
                } elseif ($incident) {
                    Append-Json $sample (Join-Path $incident.Directory 'samples.jsonl')
                    if ($now -ge $incident.Until) {
                        Save-Json @{ completed = $now.ToString('o'); capture_status = $incident.Capture.status } (Join-Path $incident.Directory 'complete.json')
                        $incident = $null
                    }
                }
                Save-Json @{ time = $now.ToString('o'); watcher_pid = $PID; source_hash = $sourceHash
                    session = $session; source_status = $sample.source_status; memory_error = $memoryError
                    eligible = $eligible; baseline_samples = $state.Healthy.Count; low_samples = $state.Low
                    incident = $(if ($incident) { $incident.Directory } else { $null }) } (Join-Path $OutputDirectory 'status.json')
            } catch {
                Append-Json @{ time = (Get-Date).ToString('o'); error = $_.Exception.ToString() } (Join-Path $OutputDirectory 'errors.jsonl')
            }
        }
        Start-Sleep -Milliseconds 750
    }
} finally {
    if ($incident -and $incident.Capture.status -eq 'running') {
        $incident.Capture.started = (Get-Date).AddSeconds(-30)
        Complete-FrameCapture $incident.Capture $incident.Directory
    }
    $mutex.ReleaseMutex(); $mutex.Dispose()
}
