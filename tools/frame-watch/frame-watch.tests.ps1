$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'frame-watch.ps1') -LibraryOnly
$count = 0
function Check($Condition, $Message) {
    $script:count++
    if (-not $Condition) { throw "FAIL: $Message" }
}
function Sample($Stamp, $Fps, $Eligible = $true, $Session = 'game-1') {
    [pscustomobject]@{ session = $Session; eligible = $Eligible; fps_time = "$Stamp"; fps = $Fps }
}
$state = New-DropState
1..6 | ForEach-Object { $null = Update-DropState $state (Sample $_ 90) }
Check ($null -eq (Update-DropState $state (Sample 7 30))) 'one low sample is not persistent'
$null = Update-DropState $state (Sample 7 30)
Check ($state.Low -eq 1) 'duplicate row counts once'
$null = Update-DropState $state (Sample 8 30 $false)
Check ($state.Low -eq 0) 'background sample breaks streak'
$null = Update-DropState $state (Sample 9 30)
$null = Update-DropState $state (Sample 10 30)
$drop = Update-DropState $state (Sample 11 30)
Check ($drop.baseline_fps -eq 90 -and $drop.consecutive_samples -eq 3) 'fresh foreground collapse detected'
12..20 | ForEach-Object { Check ($null -eq (Update-DropState $state (Sample $_ 30))) 'no incident spam' }
21..23 | ForEach-Object { $null = Update-DropState $state (Sample $_ 90) }
Check ($state.Armed) 'recovery rearms detection'
$null = Update-DropState $state (Sample 24 30)
$null = Update-DropState $state (Sample 25 30)
Check ($null -ne (Update-DropState $state (Sample 26 30))) 'recurrence triggers again'
$null = Update-DropState $state (Sample 27 30 $true 'game-2')
Check ($state.Healthy.Count -eq 1 -and $state.Armed) 'restart resets baseline'
$now = [datetime]'2026-10-08T23:00:00'
$perf = [pscustomobject]@{ Time = $now.AddSeconds(-5) }
Check (Test-FpsEligibility $perf $now.AddMinutes(-5) $now.AddMinutes(-1) $now $true) 'stable capture eligible'
Check (-not (Test-FpsEligibility $perf $now.AddMinutes(-5) $now.AddSeconds(-10) $now $true)) 'focus transition excluded'
Check (-not (Test-FpsEligibility $perf $now.AddSeconds(-10) $now.AddMinutes(-1) $now $true)) 'old PID FPS excluded'
Check (-not (Test-FpsEligibility $null $now.AddMinutes(-5) $now.AddMinutes(-1) $now $true)) 'missing FPS not zero'
$perf.Time = $now.AddSeconds(-40)
Check (-not (Test-FpsEligibility $perf $now.AddMinutes(-5) $now.AddMinutes(-1) $now $true)) 'stale FPS excluded'
$dir = Join-Path $env:TEMP ('frame-watch-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $dir
@('time,fps_avg,fps_1pct_low', '2026-10-08T22:59:50,89.5,70', '2026-10-08T22:59:59,') | Set-Content (Join-Path $dir '20261008.csv')
Check ((Read-LatestPerf $dir $now).Fps -eq 89.5) 'partial CSV row tolerated'
Check ($null -eq (Read-LatestPerf $dir $now.AddMinutes(2))) 'stale file unavailable'
Save-Json @{ state = 'verified' } (Join-Path $dir 'result.json')
Check ((Get-Content (Join-Path $dir 'result.json') -Raw | ConvertFrom-Json).state -eq 'verified') 'atomic evidence write'
Write-Output "PASS frame-watch cases=$count evidence=$dir"
