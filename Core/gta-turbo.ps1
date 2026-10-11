#Requires -Version 5.1
# Canonical source for the existing Startup/GTA Turbo.lnk watcher.
# Dot-source with -LibraryOnly for input-free policy tests.
[CmdletBinding()]
param(
    [string]$MacroConfig = (Join-Path $env:USERPROFILE 'GTA\Config.ini'),
    [switch]$LibraryOnly
)

function Read-AwayMode([string]$Path) {
    $section = ''; $values = @()
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*\[([^]]+)\]\s*$') { $section = $Matches[1]; continue }
        if ($section -eq 'Settings' -and $line -match '^\s*AwayMode\s*=(.*)$') {
            $values += $Matches[1].Trim()
        }
    }
    # Never interpret an incomplete/unreadable save as permission to leave Silent.
    if ($values.Count -ne 1 -or $values[0] -notmatch '^[01]$') { throw 'AwayMode must occur once in [Settings] with value 0 or 1.' }
    return $values[0] -eq '1'
}

function New-ModeState {
    return @{ Version = 1; AwayActive = $false; RestoreMode = 1; NormalMode = 1; WasRunning = $false }
}

function Read-ModeState([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return New-ModeState }
    $raw = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
    if ($raw.Version -ne 1 -or $raw.AwayActive -isnot [bool] -or $raw.WasRunning -isnot [bool] -or
        $null -eq $raw.RestoreMode -or "$($raw.RestoreMode)" -notmatch '^[0-2]$' -or
        $null -eq $raw.NormalMode -or "$($raw.NormalMode)" -notmatch '^[0-2]$') { throw 'Invalid mode restore state; preserving it for recovery.' }
    $state = New-ModeState
    foreach ($key in @($state.Keys)) { $state[$key] = $raw.$key }
    return $state
}

function Save-ModeState([string]$Path, [hashtable]$State) {
    $temporary = $Path + '.pending'
    [IO.File]::WriteAllText($temporary, ($State | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
    else { [IO.File]::Move($temporary, $Path) }
}

function Get-ModePlan([hashtable]$State, [bool]$Away, [bool]$Running, [int]$Current) {
    if ($Current -lt 0 -or $Current -gt 2) { throw 'Automatic switching supports built-in G-Helper modes only.' }
    $before = $State.Clone(); $after = $State.Clone(); $target = $null
    if ($Away) {
        if (-not $before.AwayActive) {
            $before.AwayActive = $true
            $before.RestoreMode = $Current
        }
        $before.WasRunning = $Running
        $after = $before.Clone()
        $target = 2
    } elseif ($before.AwayActive) {
        $target = [int]$before.RestoreMode
        $after.AwayActive = $false
        $after.NormalMode = $target
        $after.WasRunning = $Running
    } elseif ($Running) {
        if (-not $before.WasRunning) { $after.NormalMode = 1 }
        $target = [int]$after.NormalMode
        $after.WasRunning = $true
    } elseif ($before.WasRunning) {
        $target = 2
        $after.WasRunning = $false
    }
    # Capture restoration BEFORE touching hardware; clear it only AFTER confirmed success.
    return @{ Before = $before; After = $after; Target = $target }
}

function Get-Mode {
    $value = ([IO.File]::ReadAllText($script:Config) | ConvertFrom-Json).performance_mode
    if ($null -eq $value -or "$value" -notmatch '^[0-4]$') { throw 'G-Helper mode unavailable.' }
    return [int]$value
}

function Invoke-ModeTick([bool]$Running) {
    $away = Read-AwayMode $script:MacroConfig
    $state = Read-ModeState $script:StatePath
    $plan = Get-ModePlan $state $away $Running (Get-Mode)
    if (($state | ConvertTo-Json -Compress) -ne ($plan.Before | ConvertTo-Json -Compress)) {
        Save-ModeState $script:StatePath $plan.Before
    }
    if ($null -ne $plan.Target) {
        $changed = Set-GHelperMode $plan.Target
        if ($changed -or -not $away) { $script:AwayCpuApplied = $false }
        if ($away -and -not $script:AwayCpuApplied) {
            Set-AwayCpuLimit
            $script:AwayCpuApplied = $true
        }
        if ($changed) { Add-Content -LiteralPath $script:Log "$(Get-Date -Format s) mode=$($plan.Target) away=$away applied; previous=$($plan.Before.RestoreMode)" }
    }
    if (($plan.Before | ConvertTo-Json -Compress) -ne ($plan.After | ConvertTo-Json -Compress)) {
        Save-ModeState $script:StatePath $plan.After
    }
}

function Test-ModeApplied([string]$Text, [int]$Target) {
    $records = [regex]::Matches($Text, 'Mode = (\d+) : ([^\r\n]+)')
    return $records.Count -gt 0 -and [int]$records[$records.Count - 1].Groups[1].Value -eq $Target -and
        $records[$records.Count - 1].Groups[2].Value.Trim() -eq 'OK'
}

function Initialize-ModeInput {
    if ('GtaModeInput' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GtaModeInput {
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint size, tick; }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public KEYBDINPUT key; [FieldOffset(0)] public MOUSEINPUT mouse; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int x,y; public uint data,flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION data; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO value);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll", SetLastError=true)] static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    public static bool IsIdle() {
        var info = new LASTINPUTINFO { size = 8 };
        if (!GetLastInputInfo(ref info) || unchecked((uint)Environment.TickCount - info.tick) < 3000) return false;
        for (int key=1; key<256; key++) if ((GetAsyncKeyState(key) & 0x8000) != 0) return false;
        return true;
    }
    static INPUT Key(ushort vk, bool up) {
        return new INPUT { type=1, data=new UNION { key=new KEYBDINPUT { vk=vk, flags=up?2u:0u } } };
    }
    public static void SendMode(int mode) {
        // Explicit modes, never the old F5 cycle. One batch releases every modifier.
        ushort key = (ushort)(mode==2 ? 0x7f : mode==0 ? 0x80 : 0x81);
        var inputs = new [] { Key(0x11,false), Key(0x10,false), Key(0x12,false), Key(key,false),
            Key(key,true), Key(0x12,true), Key(0x10,true), Key(0x11,true) };
        if (SendInput(8, inputs, Marshal.SizeOf(typeof(INPUT))) != 8) {
            var release = new [] { Key(key,true), Key(0x12,true), Key(0x10,true), Key(0x11,true) };
            SendInput(4, release, Marshal.SizeOf(typeof(INPUT)));
            throw new InvalidOperationException("G-Helper hotkey input incomplete.");
        }
    }
}
'@
}

function Send-ModeHotkey([int]$Target, [string]$GuiName = 'Local\GtaGuiInput', [string]$MacroName = 'Local\GtaMacroInput') {
    Initialize-ModeInput
    # GUI input uses mutex existence as a lease, AFK/earner also own the macro mutex.
    $created = $false; $owned = $false; $macro = $null
    $gui = [Threading.Mutex]::new($false, $GuiName, [ref]$created)
    try {
        if (-not $created) { throw 'GUI input is active; deferring mode hotkey.' }
        $macro = [Threading.Mutex]::new($false, $MacroName)
        try { $owned = $macro.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
        if (-not $owned -or -not [GtaModeInput]::IsIdle()) { throw 'Macro or user input is active; deferring mode hotkey.' }
        $foreground = [GtaModeInput]::GetForegroundWindow(); [uint32]$foregroundPid = 0
        $null = [GtaModeInput]::GetWindowThreadProcessId($foreground, [ref]$foregroundPid)
        $name = (Get-Process -Id $foregroundPid -ErrorAction Stop).ProcessName
        if ($name -in @('LockApp','LogonUI') -or $foreground -eq [IntPtr]::Zero) { throw 'Desktop unavailable; deferring mode hotkey.' }
        [GtaModeInput]::SendMode($Target)
    } finally {
        if ($owned) { $macro.ReleaseMutex() }
        if ($macro) { $macro.Dispose() }
        $gui.Dispose()
    }
}

function Set-GHelperMode([int]$Target) {
    if ($Target -notin @(0,1,2)) { throw 'Automatic restore supports built-in G-Helper modes only.' }
    $helpers = @(Get-Process -Name GHelper -ErrorAction SilentlyContinue)
    if ($helpers.Count -ne 1) { throw 'Expected one running G-Helper.' }
    $current = Get-Mode
    $helperLog = Join-Path (Split-Path $script:Config) 'log.txt'
    $existingLog = [IO.File]::ReadAllText($helperLog)
    if ($current -eq $Target -and (Test-ModeApplied $existingLog $Target)) { return $false }
    $settings = [IO.File]::ReadAllText($script:Config) | ConvertFrom-Json
    $expectedKey = @(128,129,127)[$Target]
    if ($settings.skip_hotkeys -eq 1 -or
        ($null -ne $settings.modifier_keybind_alt -and $settings.modifier_keybind_alt -ne 'control-shift-alt') -or
        ($null -ne $settings."keybind_profile_$Target" -and $settings."keybind_profile_$Target" -ne $expectedKey)) {
        throw 'G-Helper mode shortcuts are overridden or disabled; no keys sent.'
    }
    $attemptKey = "$($helpers[0].Id):$($helpers[0].StartTime.Ticks):$Target"
    if ($script:LastModeAttemptKey -eq $attemptKey -and (Get-Date) -lt $script:NextModeAttempt) {
        throw 'Awaiting G-Helper acknowledgement; hotkey retry is limited to once per five minutes.'
    }
    Send-ModeHotkey $Target
    $script:LastModeAttemptKey = $attemptKey
    $script:NextModeAttempt = (Get-Date).AddMinutes(5)
    # A config write precedes ACPI completion. Require a NEW final successful ACPI record too.
    $deadline = (Get-Date).AddSeconds(8)
    do {
        Start-Sleep -Milliseconds 250
        $text = [IO.File]::ReadAllText($helperLog)
        $tail = if ($text.StartsWith($existingLog)) { $text.Substring($existingLog.Length) } else { $text }
        if ((Get-Mode) -eq $Target -and (Test-ModeApplied $tail $Target)) {
            $script:LastModeAttemptKey = ''
            return $true
        }
    } while ((Get-Date) -lt $deadline)
    throw "G-Helper mode $Target is not confirmed by configuration and ACPI log."
}

function Set-AwayCpuLimit {
    # G-Helper may apply per-mode auto_boost. Reassert the existing away policy AFTER it.
    foreach ($supply in @('ac', 'dc')) {
        & powercfg "/set${supply}valueindex" SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 99 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not preserve away CPU maximum.' }
        & powercfg "/set${supply}valueindex" SCHEME_CURRENT SUB_PROCESSOR be337238-0d82-4146-a960-4f3749d470c7 0 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not preserve away CPU boost policy.' }
    }
    & powercfg /setactive SCHEME_CURRENT | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not activate away CPU policy.' }
}

# Preserve the existing performance CSV contract consumed by frame-watch.
function Get-Fps {
    if (-not (Test-Path -LiteralPath $script:PresentMon)) { return ',' }
    if (Test-Path -LiteralPath $script:PmOut) { Remove-Item -LiteralPath $script:PmOut }
    & $script:PresentMon --process_name "$($script:Game).exe" --output_file $script:PmOut --timed 2 --terminate_after_timed `
        --no_console_stats --stop_existing_session --session_name gta_perf 2>$null | Out-Null
    try {
        $ms = @(Import-Csv -LiteralPath $script:PmOut | Where-Object { $_.MsBetweenDisplayChange -ne 'NA' } |
            ForEach-Object { [double]$_.MsBetweenDisplayChange } | Where-Object { $_ -gt 0 })
    } catch { return ',' }
    if ($ms.Count -lt 10) { return ',' }
    $avg = 1000 / ($ms | Measure-Object -Average).Average
    $worst = $ms | Sort-Object -Descending | Select-Object -First ([math]::Max(1, [math]::Floor($ms.Count * 0.01)))
    $low = 1000 / ($worst | Measure-Object -Average).Average
    return [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0:F1},{1:F1}', $avg, $low)
}

function Write-Perf {
    $csv = Join-Path $script:PerfDir "$(Get-Date -Format yyyyMMdd).csv"
    if ((Test-Path -LiteralPath $csv) -and ((Get-Content -LiteralPath $csv -TotalCount 1) -ne $script:Header)) {
        Rename-Item -LiteralPath $csv -NewName ([IO.Path]::GetFileNameWithoutExtension($csv) + "-old$(Get-Date -Format HHmmss).csv")
    }
    if (-not (Test-Path -LiteralPath $csv)) { Add-Content -LiteralPath $csv $script:Header }
    $fps = Get-Fps
    $gpu = (& nvidia-smi --query-gpu=$script:Smi --format=csv,noheader,nounits 2>$null) -replace '\s', ''
    $cpu = [math]::Round((Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average)
    $mode = try { Get-Mode } catch { '' }
    Add-Content -LiteralPath $csv "$(Get-Date -Format s),$fps,$gpu,$cpu,$mode"
}

if ($LibraryOnly) { return }

$ErrorActionPreference = 'Stop'
$script:Game = 'GTA5_Enhanced'
$script:Config = Join-Path $env:APPDATA 'GHelper\config.json'
$script:StatePath = Join-Path $env:LOCALAPPDATA 'gta-power-mode-state.json'
$script:Log = Join-Path $env:LOCALAPPDATA 'gta-turbo.log'
$script:PerfDir = Join-Path $env:LOCALAPPDATA 'gta-perf'
$script:PresentMon = Join-Path $env:USERPROFILE 'scripts\tools\PresentMon.exe'
$script:PmOut = Join-Path $env:TEMP 'gta-perf-pm.csv'
$script:Smi = 'utilization.gpu,temperature.gpu,power.draw,clocks.gr,memory.used,memory.total,clocks_throttle_reasons.active'
$script:Header = 'time,fps_avg,fps_1pct_low,gpu_util_pct,gpu_temp_c,gpu_power_w,gpu_clock_mhz,vram_used_mb,vram_total_mb,throttle_reasons,cpu_util_pct,mode'
$singleton = [Threading.Mutex]::new($false, 'Local\GtaPerformanceWatch')
$owned = $false
try {
    try { $owned = $singleton.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) { throw 'GTA performance watcher already running.' }
    New-Item -ItemType Directory -Force -Path $script:PerfDir | Out-Null
    $tick = 0; $lastModeError = ''; $lastPerfError = ''
    Add-Content -LiteralPath $script:Log "$(Get-Date -Format s) watcher started pid=$PID config=$MacroConfig"
    while ($true) {
        $running = [bool](Get-Process -Name $script:Game -ErrorAction SilentlyContinue)
        try { Invoke-ModeTick $running; $lastModeError = '' }
        catch {
            if ($lastModeError -ne $_.Exception.Message) { Add-Content -LiteralPath $script:Log "$(Get-Date -Format s) mode pending: $($_.Exception.Message)" }
            $lastModeError = $_.Exception.Message
        }
        # A control failure must not stop telemetry, and a measurement failure must not stop control.
        if ($running -and ($tick++ % 2 -eq 0)) {
            try { Write-Perf; $lastPerfError = '' }
            catch {
                if ($lastPerfError -ne $_.Exception.Message) { Add-Content -LiteralPath $script:Log "$(Get-Date -Format s) telemetry failed: $($_.Exception.Message)" }
                $lastPerfError = $_.Exception.Message
            }
        }
        Start-Sleep -Seconds 5
    }
} finally {
    if ($owned) { $singleton.ReleaseMutex() }
    $singleton.Dispose()
}
