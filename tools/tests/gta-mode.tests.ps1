#Requires -Version 5.1
# No game input, foreground changes, real config, powercfg or G-Helper calls.
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $root 'Core\gta-turbo.ps1') -LibraryOnly
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('gta-mode-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture
$script:MacroConfig = Join-Path $fixture 'Config.ini'
$script:StatePath = Join-Path $fixture 'state.json'
$script:Config = Join-Path $fixture 'config.json'
$script:Log = Join-Path $fixture 'watch.log'
$checks = 0
function Check($Ok, [string]$Name) { $script:checks++; if (-not $Ok) { throw "FAIL: $Name" } }
function Throws([scriptblock]$Action, [string]$Name) {
    $failed = $false
    try { & $Action } catch { $failed = $true }
    Check $failed $Name
}
function Set-FixtureAway([string]$Value) { [IO.File]::WriteAllText($script:MacroConfig, "[Settings]`r`nAwayMode=$Value`r`n") }
function Set-FixtureMode([int]$Value) { [IO.File]::WriteAllText($script:Config, (@{ performance_mode = $Value } | ConvertTo-Json)) }
try {
    foreach ($mode in @(0,1,2)) {
        $initial = New-ModeState
        $on = Get-ModePlan $initial $true $true $mode
        Check ($on.Target -eq 2 -and $on.Before.AwayActive -and $on.Before.RestoreMode -eq $mode) "capture $mode before Silent"
        Check (-not $initial.AwayActive) 'plan does not mutate input state'
        Save-ModeState $script:StatePath $on.Before
        $restarted = Read-ModeState $script:StatePath
        $again = Get-ModePlan $restarted $true $true 2
        Check ($again.Before.RestoreMode -eq $mode) 'restart/repeated ON cannot overwrite restore mode'
        $off = Get-ModePlan $again.Before $false $true 2
        Check ($off.Before.AwayActive -and -not $off.After.AwayActive -and $off.Target -eq $mode) 'restore remains pending until applied'
        $normal = Get-ModePlan $off.After $false $true $mode
        Check ($normal.Target -eq $mode) 'normal watcher does not overwrite restored mode with Turbo'
        $exit = Get-ModePlan $normal.After $false $false $mode
        Check ($exit.Target -eq 2) 'game exit retains Silent policy'
        Check ((Get-ModePlan $exit.After $false $true 2).Target -eq 1) 'next game start uses original Turbo default'
    }
    Check ($null -eq (Get-ModePlan (New-ModeState) $false $false 0).Target) 'no game and no transition means no mode request'
    Check ((Get-ModePlan (New-ModeState) $true $false 1).Target -eq 2) 'away without game is Silent too'
    Throws { Get-ModePlan (New-ModeState) $true $true 3 } 'unsupported custom mode is not overwritten'
    Set-FixtureAway '1'; Check (Read-AwayMode $script:MacroConfig) 'ON parses'
    Set-FixtureAway '0'; Check (-not (Read-AwayMode $script:MacroConfig)) 'OFF parses'
    foreach ($text in @('[Settings]', "[Other]`nAwayMode=1", "[Settings]`nAwayMode=1`nAwayMode=0", "[Settings]`nAwayMode=garbage")) {
        [IO.File]::WriteAllText($script:MacroConfig, $text)
        Throws { Read-AwayMode $script:MacroConfig } 'ambiguous/truncated config fails closed'
    }
    [IO.File]::WriteAllText($script:StatePath, '{}')
    Throws { Read-ModeState $script:StatePath } 'bad restore state is preserved'
    Check ([IO.File]::ReadAllText($script:StatePath) -eq '{}') 'corrupt state is not overwritten'
    Check (Test-ModeApplied 'new Mode = 2 : OK' 2) 'ACPI success accepted'
    Check (-not (Test-ModeApplied 'Mode = 2 : Failed' 2)) 'ACPI failure rejected'
    Check (-not (Test-ModeApplied "Mode = 2 : OK`nMode = 1 : OK" 2)) 'later conflicting mode rejected'

    # Replace only boundaries, exercising the real orchestration and durable store.
    $script:setCalls = 0; $script:cpuCalls = 0; $script:failMode = $false; $script:failCpu = $false
    $realSet = ${function:Set-GHelperMode}
    function Set-GHelperMode([int]$Target) {
        $script:setCalls++
        if ($script:failMode) { throw 'fixture ACPI failure' }
        $changed = (Get-Mode) -ne $Target
        Set-FixtureMode $Target
        return $changed
    }
    function Set-AwayCpuLimit {
        $script:cpuCalls++
        if ($script:failCpu) { throw 'fixture CPU failure' }
    }
    Save-ModeState $script:StatePath (New-ModeState)
    Set-FixtureMode 0; Set-FixtureAway '1'; $script:failMode = $true
    Throws { Invoke-ModeTick $true } 'failed mode application is not successful'
    Check ((Read-ModeState $script:StatePath).RestoreMode -eq 0) 'restore saved even when Silent apply fails'
    $script:failMode = $false; $script:failCpu = $true
    Throws { Invoke-ModeTick $true } 'CPU reassert failure is reported'
    $script:failCpu = $false
    Invoke-ModeTick $true
    Check ($script:cpuCalls -eq 2 -and (Get-Mode) -eq 2) 'CPU failure retried even when mode already Silent'
    Set-FixtureAway '0'; $script:failMode = $true
    Throws { Invoke-ModeTick $true } 'restore application failure propagates'
    Check ((Read-ModeState $script:StatePath).AwayActive) 'restore state remains pending after failed OFF'
    $script:failMode = $false
    Invoke-ModeTick $true; Invoke-ModeTick $true
    Check ((Get-Mode) -eq 0 -and -not (Read-ModeState $script:StatePath).AwayActive) 'successful OFF remains Balanced on subsequent tick'
    Set-FixtureAway ''; $beforeCalls = $script:setCalls
    Throws { Invoke-ModeTick $true } 'empty config does not invoke control'
    Check ($script:setCalls -eq $beforeCalls) 'no control on bad config'

    # Fake native class makes it impossible for even the real guard to send OS input.
    Add-Type -TypeDefinition @'
using System;
public static class GtaModeInput {
    public static bool Idle = false;
    public static int Sent = 0;
    public static bool IsIdle() { return Idle; }
    public static IntPtr GetForegroundWindow() { return new IntPtr(1); }
    public static uint GetWindowThreadProcessId(IntPtr window, out uint process) { process=1; return 1; }
    public static void SendMode(int mode) { Sent++; }
}
'@
    function Get-Process { param($Id, $Name, $ErrorAction) return [pscustomobject]@{ ProcessName='fixture'; Id=1; StartTime=[datetime]'2026-01-01' } }
    $guiName = 'Local\GtaModeTestGui-' + [guid]::NewGuid().ToString('N')
    $macroName = 'Local\GtaModeTestMacro-' + [guid]::NewGuid().ToString('N')
    $lease = [Threading.Mutex]::new($false, $guiName)
    try { Throws { Send-ModeHotkey 2 $guiName $macroName } 'existing GUI lease blocks mode key' } finally { $lease.Dispose() }
    Throws { Send-ModeHotkey 2 $guiName $macroName } 'recent input or held keys blocks mode key'
    Check ([GtaModeInput]::Sent -eq 0) 'blocked attempts emit no key'
    [GtaModeInput]::Idle = $true
    Send-ModeHotkey 2 $guiName $macroName
    Check ([GtaModeInput]::Sent -eq 1) 'guarded one-shot mode request'
    $created = $false; $lease = [Threading.Mutex]::new($false, $guiName, [ref]$created)
    try { Check $created 'GUI lease released after request' } finally { $lease.Dispose() }

    ${function:Set-GHelperMode} = $realSet
    $script:sendCalls = 0
    function Send-ModeHotkey([int]$Target) {
        $script:sendCalls++
        Set-FixtureMode $Target
        Add-Content -LiteralPath (Join-Path $fixture 'log.txt') "new Mode = $Target : OK"
    }
    function Start-Sleep { param($Milliseconds) }
    Set-FixtureMode 1; [IO.File]::WriteAllText((Join-Path $fixture 'log.txt'), "old Mode = 1 : OK`r`n")
    Check (Set-GHelperMode 2) 'real acknowledgement checker requires new success and config'
    Check (-not (Set-GHelperMode 2)) 'steady Silent does not generate more input'
    Check ($script:sendCalls -eq 1) 'one hotkey across repeated checks'
    [IO.File]::WriteAllText($script:Config, '{"performance_mode":1,"skip_hotkeys":1}')
    Throws { Set-GHelperMode 2 } 'disabled shortcut blocks input'
    Check ($script:sendCalls -eq 1) 'disabled shortcut emitted nothing'

    # Exercise real capture/parsing with a fixture, never the installed PresentMon.
    $script:Game = 'FixtureGTA'
    $script:PresentMon = Join-Path $fixture 'presentmon-fixture.ps1'
    $script:PmOut = Join-Path $fixture 'presentmon-fixture.csv'
    [IO.File]::WriteAllText($script:PresentMon, @'
$outputIndex = [Array]::IndexOf($args, '--output_file')
if ($outputIndex -lt 0) { throw 'fixture requires output_file' }
Write-Error 'fixture non-fatal elevation warning'
[IO.File]::WriteAllLines($args[$outputIndex + 1], @('MsBetweenDisplayChange') + (@('20') * 20))
'@)
    Check ((Get-Fps) -eq '50.0,50.0') 'non-fatal capture warning still returns average and low FPS'
    Check ($ErrorActionPreference -eq 'Stop') 'capture restores caller Stop error preference'
    Write-Output "PASS G-Helper away policy cases=$checks"
} finally {
    # Fixture only, never the real game or user settings.
    Get-ChildItem -LiteralPath $fixture -File | Remove-Item
    Remove-Item -LiteralPath $fixture
}
