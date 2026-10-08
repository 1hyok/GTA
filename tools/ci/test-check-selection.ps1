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

$ci = Get-CiCheckPlan @('tools/ci/run-checks.ps1')
Check ($ci.Full -and $ci.Suites.Count -eq 34 -and $ci.PackageRequired) 'CI harness change runs full suite and package validation'

$workflow = Get-CiCheckPlan @('.github/workflows/ci.yml')
Check ($workflow.Full -and $workflow.Suites.Count -eq 34 -and $workflow.PackageRequired) 'workflow change runs full suite and package validation'

$gitStylePath = Get-CiCheckPlan @('./Features/Earn/EarnStaff.ahk')
Check (($gitStylePath.Suites -join ',') -eq 'test-earner,test-earnvinewood,test-earnstaff') 'leading ./ is normalized without losing dot-prefixed paths'

$unknown = Get-CiCheckPlan @('Features/NewFeature.ahk')
Check ($unknown.Full -and $unknown.Suites.Count -eq 34) 'unknown production paths conservatively run all suites'

$hdr = Get-CiCheckPlan @('Features/Earn/EarnHdr.ahk')
Check (-not $hdr.Full -and ($hdr.Suites -join ',') -eq 'test-earner,test-earnhdr') 'HDR controller selects lease and scheduler consumers'

Write-Output "PASS CI check selection cases=$checks"
