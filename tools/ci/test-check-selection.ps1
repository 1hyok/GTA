#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'check-selection.ps1')
$checks = 0
function Check($ok, [string]$message) {
    $script:checks++
    if (-not $ok) { throw "FAIL $message" }
}

$staff = Get-CiCheckPlan @('Features/Earn/EarnStaff.ahk')
Check (-not $staff.Full) 'staff source should be targeted'
Check (($staff.Suites -join ',') -eq 'test-earner,test-earnvinewood,test-earnstaff') 'staff source selects its dependent suites'
Check ($staff.PackageRequired) 'macro source requires package validation'

$safe = Get-CiCheckPlan @('Features/Earn/EarnVinewood.ahk')
Check (($safe.Suites -join ',') -eq 'test-earner,test-earnvinewood,test-earnstaff') 'Vinewood changes test vault, scheduler, and shared staff close path'

$testOnly = Get-CiCheckPlan @('tools/earn-test/test-earnstaff.ps1')
Check (($testOnly.Suites -join ',') -eq 'test-earnstaff') 'single suite change runs the matching test'
Check (-not $testOnly.PackageRequired) 'test-only changes do not package macro sources'

$docs = Get-CiCheckPlan @('docs/earner-policy.md')
Check ($docs.Suites.Count -eq 0 -and -not $docs.PackageRequired) 'documentation-only change skips regression suites and packaging'

$djTest = Get-CiCheckPlan @('tools/earn-test/test-dj-templates.ps1')
Check (-not $djTest.Full -and ($djTest.Suites -join ',') -eq 'test-dj-templates') 'DJ template regression selects itself'
$djTemplate = Get-CiCheckPlan @('Images/Earn/1920x1080/dj_confirm_tale.png')
Check (-not $djTemplate.Full -and ($djTemplate.Suites -join ',') -eq 'test-dj-templates' -and $djTemplate.PackageRequired) 'DJ confirmation pixels select their visual regression and package'
$earnCore = Get-CiCheckPlan @('Features/Earn/EarnCore.ahk')
Check ($earnCore.Suites -contains 'test-dj-templates') 'EarnSeen search-area changes include DJ pixel regression'
$otherImage = Get-CiCheckPlan @('Images/Earn/1920x1080/unknown.png')
Check ($otherImage.Suites -contains 'test-dj-templates') 'other shared image changes preserve DJ regression coverage'

$ci = Get-CiCheckPlan @('tools/ci/run-checks.ps1')
Check ($ci.Full -and $ci.Suites.Count -eq 37 -and $ci.PackageRequired) 'CI harness change runs full suite and package validation'

$workflow = Get-CiCheckPlan @('.github/workflows/ci.yml')
Check ($workflow.Full -and $workflow.Suites.Count -eq 37 -and $workflow.PackageRequired) 'workflow change runs full suite and package validation'

$gitStylePath = Get-CiCheckPlan @('./Features/Earn/EarnStaff.ahk')
Check (($gitStylePath.Suites -join ',') -eq 'test-earner,test-earnvinewood,test-earnstaff') 'leading ./ is normalized without losing dot-prefixed paths'

$unknown = Get-CiCheckPlan @('Features/NewFeature.ahk')
Check ($unknown.Full -and $unknown.Suites.Count -eq 37) 'unknown production paths conservatively run all suites'

$frameWatch = Get-CiCheckPlan @('tools/frame-watch/frame-watch.ps1')
Check (-not $frameWatch.Full -and ($frameWatch.Suites -join ',') -eq 'test-perf-watch') 'frame watcher selects performance regressions'
$hud = Get-CiCheckPlan @('Features/DiscordHUD.ahk')
Check (-not $hud.Full -and ($hud.Suites -join ',') -eq 'test-earner,test-discord-hud' -and $hud.PackageRequired) 'HUD source selects lifecycle and visibility regressions'
$earner = Get-CiCheckPlan @('Features/Earn/Earner.ahk')
Check (($earner.Suites -join ',') -eq 'test-earner,test-discord-hud') 'scheduler hooks select HUD regression'
$hudTest = Get-CiCheckPlan @('tools/earn-test/test-discord-hud.ps1')
Check (($hudTest.Suites -join ',') -eq 'test-discord-hud') 'HUD test selects its registered suite'
Write-Output "PASS CI check selection cases=$checks"
