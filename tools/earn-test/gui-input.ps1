#Requires -Version 5.1
<#
Sends exactly one command to an already-running gui-input.ahk receiver.
The caller owns GTA input for the entire session and verifies the start state and meaningful segment results.
This helper never activates a window, starts AHK/Main/AFK, retries a command, or sends input itself.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SessionDir,
    [Parameter(Mandatory)][ValidateSet('tap','hold','look','click','wheel','navigate','stop')][string]$Action,
    [string]$Key = '',
    [string[]]$Keys = @(),
    [ValidateRange(150,500)][int]$InterKeyMs = 200,
    [ValidateRange(1,15000)][int]$HoldMs = 100,
    [ValidateRange(-10000,10000)][int]$Dx = 0,
    [ValidateRange(-10000,10000)][int]$Dy = 0,
    [ValidateRange(-65535,65535)][int]$X = 0,
    [ValidateRange(-65535,65535)][int]$Y = 0,
    [ValidateRange(-5,5)][int]$Ticks = 0,
    [ValidateRange(1,30)][int]$WaitSec = 25
)
$ErrorActionPreference = 'Stop'
$sessionPath = (Resolve-Path -LiteralPath $SessionDir).Path
$statePath = Join-Path $sessionPath 'state.txt'
$commandPath = Join-Path $sessionPath 'command.txt'
$senderLock = $null
try {
    # A second sender fails immediately instead of queueing a command behind unseen state.
    $senderLock = [IO.File]::Open((Join-Path $sessionPath 'sender.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $state = [IO.File]::ReadAllText($statePath).Split('|')
    if ($state.Length -ne 6 -or $state[2] -ne 'ready' -or $state[0] -notmatch '^[A-Za-z0-9_-]{8,64}$') {
        throw 'Receiver is not ready. Inspect state.txt; do not retry commands automatically.'
    }
    $receiverPid = [int]$state[1]
    if (-not (Get-Process -Id $receiverPid -ErrorAction SilentlyContinue)) { throw 'Receiver has exited.' }
    if (Test-Path -LiteralPath $commandPath) { throw 'An earlier command is still pending.' }
    $sequence = [int]$state[3] + 1
    switch ($Action) {
        'tap' {
            if ($Key -cnotmatch '^(P|M|E|Enter|Backspace|Up|Down|Left|Right|PgDn|PgUp|Caps|Space|LCtrl|RButton)$') { throw 'Tap key is not allowed.' }
            $argOne = $Key; $argTwo = '0'
        }
        'hold' {
            if ($Key -cnotmatch '^[WASD]$') { throw 'Hold requires W/A/S/D.' }
            $argOne = $Key; $argTwo = [string]$HoldMs
        }
        'look' {
            $distance = [Math]::Sqrt($Dx * $Dx + $Dy * $Dy)
            if ($distance -le 0 -or $distance -gt 10000) { throw 'Look distance must be 1-10000 units.' }
            $argOne = [string]$Dx; $argTwo = [string]$Dy
        }
        'click' {
            if (-not $PSBoundParameters.ContainsKey('X') -or -not $PSBoundParameters.ContainsKey('Y')) { throw 'Click requires explicit physical screen -X and -Y.' }
            $argOne = [string]$X; $argTwo = [string]$Y
        }
        'wheel' {
            if ($Ticks -eq 0) { throw 'Wheel requires nonzero -Ticks from -5 to 5; positive is up, negative is down.' }
            $argOne = [string]$Ticks; $argTwo = '0'
        }
        'navigate' {
            if ($Keys.Count -lt 1 -or $Keys.Count -gt 20) { throw 'Navigate requires 1-20 keys.' }
            foreach ($navigationKey in $Keys) {
                if ($navigationKey -cnotmatch '^(Up|Down|Left|Right|PgDn|PgUp)$') { throw 'Navigate accepts only Up/Down/Left/Right/PgDn/PgUp; confirmation and back keys are forbidden.' }
            }
            $argOne = $Keys -join '_'; $argTwo = [string]$InterKeyMs
        }
        'stop' { $argOne = '0'; $argTwo = '0' }
    }
    $resultPath = Join-Path $sessionPath ('result-' + $sequence + '.txt')
    if (Test-Path -LiteralPath $resultPath) { throw 'Result already exists. Use a fresh session directory.' }
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMddHHmmss')
    $commandText = @($state[0], $sequence, $stamp, $Action, $argOne, $argTwo) -join '|'
    $pendingPath = Join-Path $sessionPath ('command-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($pendingPath, $commandText, [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($pendingPath, $commandPath)
    $deadline = [DateTime]::UtcNow.AddSeconds($WaitSec)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $resultPath) {
            $result = [IO.File]::ReadAllText($resultPath).Split('|')
            if ($result.Length -ne 5 -or $result[0] -ne $state[0] -or [int]$result[1] -ne $sequence) { throw 'Invalid command result.' }
            [pscustomobject]@{ Sequence=$sequence; Status=$result[2]; UTC=$result[3]; Message=$result[4]; ResultPath=$resultPath }
            if ($result[2] -ne 'ok') { throw ('Command aborted: ' + $result[4]) }
            return
        }
        if (-not (Get-Process -Id $receiverPid -ErrorAction SilentlyContinue)) {
            throw ('Receiver exited before a result. Inspect ' + $statePath + ' and rejected.txt.')
        }
        Start-Sleep -Milliseconds 50
    }
    throw 'Result wait timed out. Do not resend. Inspect receiver state and the current screenshot.'
} finally {
    if ($senderLock) { $senderLock.Dispose() }
}
