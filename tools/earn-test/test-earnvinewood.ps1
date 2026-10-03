#Requires -Version 5.1
<#
Runs the real Vinewood flow and text-selection/parser helpers against a fake menu.
No game input, screen capture, window activation, or Main.ahk execution.
#>
[CmdletBinding()]
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$production = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnVinewood.ahk') -Raw -Encoding UTF8
$screen = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnScreen.ahk') -Raw -Encoding UTF8
foreach ($functionName in @('EarnFindText', 'EarnReadDollars', 'EarnSelectText', 'EarnMenuStepKey')) {
    $match = [regex]::Matches($screen, ('(?ms)^' + $functionName + '\([^\r\n]*\) \{.*?^\}'))
    if ($match.Count -ne 1) { throw "Expected exactly one screen helper: $functionName" }
    $production += "`n" + $match[0].Value
}
if (-not (Test-Path -LiteralPath $AhkPath -PathType Leaf)) { throw "AutoHotkey executable not found: $AhkPath" }
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global gMode, gState, gSelected, gDetailReads, gClaims, gClaimAttempts, gKeys, gStandWaits, gMctCloses, gCEOCalls, gFailure, gTests := 0
RunTests()
FileAppend("PASS EarnVinewood cases=" gTests Chr(10), "*", "UTF-8")
ExitApp(0)

RunTests() {
    global gClaims, gClaimAttempts, gKeys, gState, gMctCloses, gCEOCalls, gFailure
    ; mode, starting screen, success, successful nightclub claims, final screen.
    cases := [
        ["full", "main", true, 1, "standing"],
        ["not_full", "main", true, 0, "standing"],
        ["near_full", "main", true, 1, "standing"],
        ["empty", "main", true, 0, "standing"],
        ["no_earnings", "main", true, 0, "standing"],
        ["full", "earnings", true, 1, "standing"],
        ["empty", "earnings", true, 0, "standing"],
        ["wrong_business", "main", false, 0, "earnings"],
        ["unreadable", "main", false, 0, "earnings"],
        ["malformed_amount", "main", false, 0, "earnings"],
        ["too_large", "main", false, 0, "earnings"],
        ["duplicate_details", "main", false, 0, "earnings"],
        ["recheck_amount", "main", false, 0, "earnings"],
        ["recheck_selection", "main", false, 0, "earnings"],
        ["cancel_claim", "main", false, 0, "earnings"],
        ["post_unconfirmed", "main", false, 1, "earnings"],
        ["post_no_earnings", "main", false, 1, "main"],
        ["post_claim_zero", "main", false, 1, "earnings"],
        ["prompt_delay", "main", true, 1, "standing"],
        ["close_unknown", "main", false, 1, "unknown"],
        ["close_cancel", "main", false, 1, "earnings"],
        ["select_cancel", "main", false, 0, "earnings"],
        ["full", "standing", true, 1, "standing"],
        ["full", "mct", true, 1, "standing"],
        ["full", "phone_job", true, 1, "standing"],
        ["full", "phone_vinewood", true, 1, "standing"],
        ["open_unreadable", "standing", false, 0, "standing"],
        ["open_unreadable", "phone_job", false, 0, "phone_job"],
        ["open_unreadable", "phone_vinewood", false, 0, "phone_vinewood"],
        ["full", "unknown", false, 0, "unknown"],
        ["wrong_phone", "standing", false, 0, "wrong_phone"]
    ]
    for c in cases {
        Reset(c[1], c[2])
        result := EarnVinewoodSafeTask()
        Check(result = c[3] && gClaims = c[4] && gState = c[5], c[1] "/" c[2] " result=" result " claims=" gClaims " state=" gState)
        Check(gClaimAttempts <= 1, c[1] " never replays collection")
        for key in gKeys
            Check(key != "Esc", c[1] " never sends Esc")
        if (c[2] = "mct")
            Check(gMctCloses = 1 && gCEOCalls = 1, "MCT start closes terminal before phone")
        if (c[2] = "phone_job" || c[2] = "phone_vinewood") {
            Check(gMctCloses = 0 && gCEOCalls = 0, "open phone does not repeat MCT or CEO setup")
            for key in gKeys
                Check(key != "Up", "open phone never sends the phone-opening Up key again")
        }
        if (c[1] = "open_unreadable" || c[2] = "unknown")
            Check(gKeys.Length = 0, "unknown opening screen sends no keys")
        if (c[1] = "no_earnings")
            Check(gClaimAttempts = 0 && gKeys.Length = 1 && gKeys[1] = "Backspace", "global empty skips entering business list")
    }
    Reset("close_stuck", "main")
    Check(!EarnVinewoodClose() && gKeys.Length = 4, "stuck app closing is bounded at four Backspaces")
    Reset("full", "phone_vinewood")
    Check(EarnVinewoodClose() && gState = "standing", "phone home is closed before reporting success")
    Reset("full", "phone_job")
    Check(EarnVinewoodOpen() && gState = "main" && gKeys.Length = 2
        && gKeys[1] = "Right" && gKeys[2] = "Enter", "Job List home only moves right and opens the selected app")
    Reset("full", "phone_vinewood")
    Check(EarnVinewoodOpen() && gState = "main" && gKeys.Length = 1
        && gKeys[1] = "Enter", "selected Vinewood home opens directly without changing phone selection")

    Reset("full", "earnings")
    lines := Frame("Claim $250,000 from your Nightclub safe.")
    Check(EarnVinewoodNightclubAmount(lines) = 250000, "comma-formatted detail amount")
    Check(EarnVinewoodNightclubAmount(Frame("Claim $250000 from your Nightclub safe.")) = 250000, "plain detail amount")
    Check(EarnVinewoodNightclubAmount(Frame("Your Nightclub safe is empty.")) = 0, "explicit nightclub empty detail")
    for text in ["Claim $250000 from your Arcade safe.", "Your Arcade safe is empty.", "Nightclub $250000", "Claim $25O000 from your Nightclub safe.", "Claim $250,00 from your Nightclub safe.", "Claim $250 000 from your Nightclub safe.", "Claim $250000 from your Nightclub safe. Confirm?"]
        Check(EarnVinewoodNightclubAmount(Frame(text)) = -1, "reject detail: " text)
    Check(EarnVinewoodNightclubAmount(false) = -1, "OCR failure is not an empty safe")
}

Reset(mode, state) {
    global gMode, gState, gSelected, gDetailReads, gClaims, gClaimAttempts, gKeys, gStandWaits, gMctCloses, gCEOCalls, gFailure
    gMode := mode, gState := state, gSelected := state = "earnings" ? "Nightclub" : "Claim Business Earnings"
    gDetailReads := 0, gClaims := 0, gClaimAttempts := 0, gKeys := [], gStandWaits := 0, gMctCloses := 0, gCEOCalls := 0, gFailure := ""
}

EarnReadScreen(*) {
    global gMode, gState, gSelected, gDetailReads, gClaims
    if (gMode = "open_unreadable")
        return false
    if (gState = "main") {
        lines := [FakeLine("THE VINEWOOD CLUB APP"), FakeLine("Claim Business Earnings"), FakeLine("Purchase Ammo")]
        if (gMode = "no_earnings" || (gMode = "post_no_earnings" && gClaims))
            lines.Push(FakeLine("No earnings to claim."))
        return lines
    }
    if (gState != "earnings")
        return []
    if (gSelected = "Nightclub")
        gDetailReads += 1
    if (gMode = "recheck_selection" && gDetailReads >= 3)
        gSelected := "Arcade"
    if (gSelected = "Arcade" || gMode = "wrong_business")
        return Frame("Claim $250000 from your Arcade safe.")
    if (gMode = "unreadable")
        return Frame("unread")
    if (gMode = "malformed_amount")
        return Frame("Claim $25O000 from your Nightclub safe.")
    if (gMode = "empty" || (gClaims && gMode != "post_unconfirmed" && gMode != "post_claim_zero"))
        return Frame("Your Nightclub safe is empty.")
    amount := gMode = "not_full" ? 200000 : gMode = "near_full" ? 245000 : gMode = "recheck_amount" && gDetailReads >= 3 ? 249999 : gMode = "too_large" ? 250001 : gMode = "post_claim_zero" && gClaims ? 0 : 250000
    lines := Frame("Claim $" amount " from your Nightclub safe.")
    if (gMode = "duplicate_details")
        lines.Push(FakeLine("Your Nightclub safe is empty."))
    return lines
}

Frame(detail) {
    return [FakeLine("THE VINEWOOD CLUB APP"), FakeLine("Nightclub"), FakeLine("Arcade"), FakeLine(detail)]
}
FakeLine(text) {
    return {text: text, x: 40, y: 180, w: 350, h: 22}
}
EarnMenuRowSelected(row) {
    global gSelected
    return row.text = gSelected
}
EarnPress(key) {
    global gMode, gState, gSelected, gClaims, gClaimAttempts, gKeys
    gKeys.Push(key)
    if (key = "Down") {
        if (gMode = "select_cancel")
            return false
        gSelected := gSelected = "Arcade" ? "Nightclub" : "Arcade"
    } else if (key = "Up") {
        if (gState != "standing")
            throw Error("Phone-opening Up is invalid when the phone is already open: " gState)
        gState := gMode = "wrong_phone" ? "wrong_phone" : "phone_job"
    } else if (key = "Right" && gState = "phone_job") {
        gState := "phone_vinewood"
    } else if (key = "Enter") {
        if (gState = "phone_vinewood") {
            gState := "main", gSelected := "Claim Business Earnings"
        } else if (gState = "main" && gSelected = "Claim Business Earnings") {
            gState := "earnings", gSelected := "Arcade"
        } else if (gState = "earnings") {
            gClaimAttempts += 1
            if (gMode = "cancel_claim")
                return false
            if (gSelected != "Nightclub")
                throw Error("Attempted collection from wrong business")
            gClaims += 1
            if (gMode = "post_no_earnings")
                gState := "main", gSelected := "Claim Business Earnings"
        } else {
            throw Error("Unexpected Enter state: " gState)
        }
    } else if (key = "Backspace") {
        if (gMode = "close_cancel")
            return false
        if (gMode = "close_stuck")
            return true
        if (gState = "earnings")
            gState := "main", gSelected := "Claim Business Earnings"
        else if (gState = "main" || gState = "phone_vinewood" || gState = "phone_job")
            gState := gMode = "close_unknown" ? "unknown" : gMode = "prompt_delay" ? "waiting_prompt" : "standing"
    }
    return true
}
EarnSleep(ms) {
    global gMode, gState, gClaims, gStandWaits
    if (gClaims && ms = 300 && (gMode = "post_unconfirmed" || gMode = "post_no_earnings" || gMode = "post_claim_zero"))
        return false
    if (gState = "waiting_prompt" && ms = 300 && ++gStandWaits >= 2)
        gState := "standing"
    return true
}
EarnSeen(name, *) {
    global gState
    return name = "mct_sit" ? gState = "standing" : name = "ph_joblist_sel" ? gState = "phone_job" : name = "ph_vinewood_sel" && gState = "phone_vinewood"
}
EarnWaitSeen(name, *) => EarnSeen(name)
EarnAtMCT() {
    global gState
    return gState = "mct"
}
EarnMCTClose() {
    global gState, gMctCloses
    gMctCloses += 1, gState := "standing"
    return true
}
EarnCEO(*) {
    global gCEOCalls
    gCEOCalls += 1
    return true
}
EarnFail(message) {
    global gFailure
    gFailure := message
    return false
}
EarnLog(*) {
}
Check(ok, name) {
    global gTests
    gTests += 1
    if (!ok) {
        FileAppend("FAIL " name Chr(10), "*", "UTF-8")
        ExitApp(1)
    }
}
'@

$testPath = Join-Path ([IO.Path]::GetTempPath()) ('gta-earn-vinewood-' + [Guid]::NewGuid().ToString('N') + '.ahk')
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $AhkPath
$info.Arguments = '/ErrorStdOut /CP65001 "' + $testPath + '"'
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
$info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
$testProcess = $null
try {
    [IO.File]::WriteAllText($testPath, $driver + "`n" + $production + "`n", (New-Object Text.UTF8Encoding($true)))
    $testProcess = [Diagnostics.Process]::Start($info)
    if (-not $testProcess.WaitForExit(10000)) {
        $testProcess.Kill()
        $testProcess.WaitForExit()
        throw 'EarnVinewood check timed out after 10 seconds'
    }
    $stdout = $testProcess.StandardOutput.ReadToEnd().Trim()
    $stderr = $testProcess.StandardError.ReadToEnd().Trim()
    if ($testProcess.ExitCode -ne 0 -or $stderr -ne '' -or $stdout -notmatch '^PASS EarnVinewood cases=\d+$') {
        throw "EarnVinewood failed (exit=$($testProcess.ExitCode))`nstdout: $stdout`nstderr: $stderr"
    }
    Write-Output $stdout
} finally {
    if ($null -ne $testProcess) {
        if (-not $testProcess.HasExited) {
            $testProcess.Kill()
            $testProcess.WaitForExit()
        }
        $testProcess.Dispose()
    }
    [IO.File]::Delete($testPath)
}
