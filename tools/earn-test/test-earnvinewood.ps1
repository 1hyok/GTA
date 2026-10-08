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
$commonScreen = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Core\Screen.ahk') -Raw -Encoding UTF8
foreach ($helper in @('HealthHudVisible', 'HealthHudColors')) {
    $match = [regex]::Match($commonScreen, ('(?ms)^' + $helper + '\([^\r\n]*\) \{.*?^\}'))
    if (-not $match.Success) { throw "Missing common HUD helper: $helper" }
    $production += "`n" + $match.Value
}
foreach ($functionName in @('EarnFindText', 'EarnReadDollars', 'EarnSelectText', 'EarnMenuStepKey')) {
    $match = [regex]::Matches($screen, ('(?ms)^' + $functionName + '\([^\r\n]*\) \{.*?^\}'))
    if ($match.Count -ne 1) { throw "Expected exactly one screen helper: $functionName" }
    $production += "`n" + $match[0].Value
}
# 빈 화면 시작의 물리 유휴는 시험 값으로 바꾼다(A_TimeIdlePhysical 은 이 프로세스의 실제 값이다).
$idleNeedle = 'A_TimeIdlePhysical < idleMs'
if (([regex]::Matches($production, [regex]::Escape($idleNeedle))).Count -ne 1) { throw "Expected one free-HUD idle check" }
$production = $production.Replace($idleNeedle, 'gPhysIdle < idleMs')
if (-not (Test-Path -LiteralPath $AhkPath -PathType Leaf)) { throw "AutoHotkey executable not found: $AhkPath" }
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global transactionPending := Map()
EarnTransactionBegin(id, reason) {
    transactionPending[id] := reason
    return true
}
EarnTransactionConfirmed(id) => transactionPending.Delete(id)
global gMode, gState, gSelected, gBiz, gIdx, gReads, gClaims, gClaimAttempts, gKeys, gStandWaits, gMctCloses, gCEOCalls, gFailure, gScheduled, gTests := 0
; 입금 알림 감시(EarnSafeFeedWatch)는 스케줄러 전역을 쓴다. 이 시험은 파서만 부른다.
global gEarnRetryIn := 0, gEarnOn := false, gEarnBusy := false, gEarnDue := Map(), gEarnNextDue := Map()
global config := Map("Settings", Map("EarnUserIdleSec", 45)), gPhysIdle := 600000, gOthersIdle := 600000
IsGTAActive() => false
RunTests()
FileAppend("PASS EarnVinewood cases=" gTests Chr(10), "*", "UTF-8")
ExitApp(0)

; 기본 목록은 1004 00:24 실측 순서와 금액이다(Car Wash 는 빈 금고).
DefaultBiz() => [["Nightclub",150000], ["Arcade",10000], ["Agency",80000], ["Salvage Yard",6300],
    ["Bail Office",12800], ["Garment Factory",35720], ["Hands On Car Wash",0]]

RunTests() {
    global gClaims, gClaimAttempts, gKeys, gState, gMctCloses, gCEOCalls, gScheduled, gBiz, gIdx, gSelected, gPhysIdle, gOthersIdle
    ; mode, starting screen, amounts to override, success, claimed names, final screen, scheduled minutes (0 = not checked)
    cases := [
        ["normal", "main", Map(), true, "", "standing", 88],
        ["empty_row_missing", "main", Map(), true, "", "standing", 88],
        ["empty_row_missing", "main", Map("Nightclub",0), true, "", "standing", 136],
        ["empty_row_missing", "main", Map("Nightclub",250000), true, "Nightclub", "standing", 136],
        ["normal", "main", Map("Nightclub",250000), true, "Nightclub", "standing", 136],
        ["normal", "main", Map("Nightclub",205000,"Arcade",96000,"Agency",235000,"Garment Factory",99000), true,
            "Nightclub,Arcade,Agency,Garment Factory", "standing", 136],
        ["normal", "main", Map("Arcade",95000), true, "", "standing", 40],
        ["normal", "main", Map("Arcade",95001), true, "Arcade", "standing", 88],
        ["normal", "main", Map("Hands On Car Wash",100000), true, "", "standing", 88],
        ["normal", "main", Map("Salvage Yard",76001,"Bail Office",80001), true, "Salvage Yard,Bail Office", "standing", 88],
        ["unknown_business", "main", Map(), true, "", "standing", 40],
        ["unreadable_agency", "main", Map(), true, "", "standing", 40],
        ["no_earnings", "main", Map(), true, "", "standing", 184],
        ["normal", "earnings_mid", Map("Nightclub",250000), true, "Nightclub", "standing", 136],
        ["recheck_amount", "main", Map("Nightclub",240000), false, "", "earnings", 0],
        ["cancel_claim", "main", Map("Nightclub",240000), false, "", "earnings", 0],
        ["post_unconfirmed", "main", Map("Nightclub",240000), false, "Nightclub", "earnings", 0],
        ["select_cancel", "main", Map(), false, "", "earnings", 0],
        ["no_selection", "main", Map(), false, "", "earnings", 0],
        ["close_unknown", "main", Map(), true, "", "unknown", 0],
        ["prompt_delay", "main", Map(), true, "", "standing", 0],
        ["normal", "standing", Map("Nightclub",250000), true, "Nightclub", "standing", 0],
        ["normal", "mct", Map("Nightclub",250000), true, "Nightclub", "standing", 0],
        ["normal", "phone_job", Map("Nightclub",250000), true, "Nightclub", "standing", 0],
        ["normal", "phone_vinewood", Map("Nightclub",250000), true, "Nightclub", "standing", 0],
        ["open_unreadable", "standing", Map(), false, "", "standing", 0],
        ["open_unreadable", "phone_job", Map(), false, "", "phone_job", 0],
        ["normal", "unknown", Map(), false, "", "unknown", 0],
        ["normal", "hud", Map("Nightclub",250000), true, "Nightclub", "standing", 0],
        ["wrong_phone", "standing", Map(), false, "", "wrong_phone", 0]
    ]
    for c in cases {
        Reset(c[1], c[2], c[3])
        result := EarnVinewoodSafeTask()
        claimed := ""
        for name in gClaims
            claimed .= (claimed = "" ? "" : ",") name
        label := c[1] "/" c[2] "/" claimed
        Check(result = c[4] && claimed = c[5] && gState = c[6], label " result=" result " claims=" claimed " state=" gState)
        if (c[7])
            Check(gScheduled = c[7] * 60000, label " scheduled " Round(gScheduled / 60000) " min, expected " c[7])
        Check(gClaimAttempts <= gClaims.Length + 1, label " never replays collection")
        if (c[1] = "post_unconfirmed" && !transactionPending.Has("safe"))
            throw Error("Unconfirmed collection must retain pending state")
        if (result && gClaims.Length && transactionPending.Has("safe"))
            throw Error("Confirmed collection must clear pending state")
        for key in gKeys
            Check(key != "Esc", label " never sends Esc")
        if (c[2] = "hud")
            Check(gMctCloses = 0 && gCEOCalls = 0, "free HUD start leaves CEO/MC state alone")
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
        if (result && c[1] != "no_earnings") {
            downs := 0
            for key in gKeys
                downs += key = "Down"
            Check(downs = gBiz.Length, label " visits every row once and stops on wrap (downs=" downs ")")
        }
    }
    Reset("close_stuck", "main")
    Check(!EarnVinewoodClose() && gKeys.Length = 4, "stuck app closing is bounded at four Backspaces")
    Reset("normal", "phone_vinewood")
    Check(EarnVinewoodClose() && gState = "standing", "phone home is closed before reporting success")
    Reset("normal", "pause_menu")
    RetryIn(0)
    Check(!EarnVinewoodOpen() && gKeys.Length = 0 && RetryIn() = 180000 && InStr(gFailure, "HUD"),
        "away from MCT retries in three minutes without input")
    for idle in [[1000, 600000, "physical"], [600000, 1000, "remote"]] {
        Reset("normal", "hud")
        RetryIn(0)
        gPhysIdle := idle[1], gOthersIdle := idle[2]
        Check(!EarnVinewoodOpen() && gKeys.Length = 0 && RetryIn() = 180000,
            "free HUD waits while recent " idle[3] " input exists")
        Check(!EarnVinewoodOpen(false) && gKeys.Length = 0, "staff preserves " idle[3] " input guard")
    }
    Reset("hud_menu", "hud")
    Check(!EarnVinewoodOpen() && gKeys.Length = 0, "free HUD with an open menu sends no keys")
    Check(!EarnVinewoodOpen(false) && gKeys.Length = 0, "staff also blocks an open menu")
    for color in [0x4C8F4C, 0x9BFF9F, 0xA5FFAC, 0xACFFB2, 0x000000, 0xFFFFFF, 0xFF3333, 0x3399FF] {
        samples := []
        Loop 16
            samples.Push(color)
        Check(EarnVinewoodHealthColors(samples) = (color = 0x4C8F4C || color = 0x9BFF9F || color = 0xA5FFAC || color = 0xACFFB2),
            "health bar accepts recorded normal/bright green and rejects other colors " color)
    }
    Check(!EarnVinewoodHealthColors([0x9BFF9F]), "one green pixel is not a health bar")
    sparse := []
    Loop 16
        sparse.Push(A_Index <= 11 ? 0xA5FFAC : 0xFFFFFF)
    Check(!EarnVinewoodHealthColors(sparse), "eleven HDR green samples do not establish the health bar")
    sparse[12] := 0xA5FFAC
    Check(EarnVinewoodHealthColors(sparse), "twelve HDR green samples establish the health bar")
    Reset("normal", "hud")
    Check(EarnVinewoodOpen() && gState = "main" && gKeys[1] = "Up" && gCEOCalls = 0, "free HUD opens the phone without CEO setup")
    Reset("normal", "hud")
    Check(EarnVinewoodOpen(false) && gState = "main" && gMctCloses = 0 && gCEOCalls = 0,
        "staff opens away from MCT without terminal or boss operations")
    Reset("normal", "standing")
    Check(!EarnVinewoodOpen(false) && gKeys.Length = 0 && gMctCloses = 0 && gCEOCalls = 0,
        "staff does not substitute MCT position for a verified free HUD")
    Reset("normal", "phone_job")
    Check(EarnVinewoodOpen() && gState = "main" && gKeys.Length = 2
        && gKeys[1] = "Right" && gKeys[2] = "Enter", "Job List home only moves right and opens the selected app")
    Reset("right_stuck", "phone_job")
    RetryIn(0)
    Check(!EarnVinewoodOpen() && gState = "standing" && gKeys.Length = 2 && gKeys[2] = "Backspace" && RetryIn() = 180000,
        "unconfirmed Vinewood selection closes the phone and retries in three minutes")
    Reset("normal", "phone_vinewood")
    Check(EarnVinewoodOpen() && gState = "main" && gKeys.Length = 1
        && gKeys[1] = "Enter", "selected Vinewood home opens directly without changing phone selection")

    Reset("normal", "earnings")
    Check(EarnVinewoodNightclubAmount(Frame("Claim $250,000 from your Nightclub safe.")) = 250000, "comma-formatted detail amount")
    Check(EarnVinewoodNightclubAmount(Frame("Claim $250000 from your Nightclub safe.")) = 250000, "plain detail amount")
    Check(EarnVinewoodNightclubAmount(Frame("Claim $50000 from ydÜr Nightclub safe.")) = 50000, "garbled your still reads amount")
    Check(EarnVinewoodNightclubAmount(Frame("Claim $150000 fromyour Nightclub safe.")) = 150000, "your glued to from still reads amount")
    gSelected := ": Nightclub"
    Check(EarnVinewoodNightclubAmount([FakeLine("THE VINEWOOD CLUB APP"), FakeLine(": Nightclub"), FakeLine("Claim $100000 from your Nightclub safe.")]) = 100000, "leading colon on selected Nightclub row")
    gSelected := "Garment Factory"
    wrapped := [FakeLine("THE VINEWOOD CLUB APP"), FakeLine("Garment Factory"), FakeLine("Claim $35720 from your Garment Factory"), FakeLine("safe.")]
    Check(EarnVinewoodSelectedSafe(wrapped) = "Garment Factory" && EarnVinewoodSafeAmountOf(wrapped, "Garment Factory") = 35720, "footer wrapped onto two lines")
    ; 입금 알림(1004 녹화의 흰 글자 판독 그대로). 깨진 금액은 -1, 가득 참은 full.
    feedCases := [
        [["Your daily Salvage Yard","earrnings have been added to","the office. safe _","Safe total: $11400"], "Salvage Yard", 11400, false],
        [["Galaxy","Your daily Nightclub take has","been added to the office","safe.","Safe total: $245000"], "Nightclub", 245000, false],
        [["Galaxy","Your daily Night.club take has","been added to the office","safe.","Safe total: $245c•oa"], "Nightclub", -1, false],
        [["kicked for idlina: 13rn0Qs","Galaxy","Your daily Nightclub take has","been added to the office","safe.","Safe total: $24500Q"], "Nightclub", -1, false],
        [["Galaxy","Your daily Nightclub take has","been added to the office","safe.","Safe total: $250000 (at","capacity)"], "Nightclub", 250000, true]]
    for c in feedCases {
        feed := []
        for text in c[1]
            feed.Push(FakeLine(text))
        notes := EarnSafeFeedParse(feed)
        Check(notes.Length = 1 && notes[1].name = c[2] && notes[1].total = c[3] && notes[1].full = c[4], "safe feed " c[2] " " c[3])
    }
    both := []
    for text in ["Your daily Salvage Yard","earnings have been added to","the office safe.","Safe total: $11700","Galaxy","Your daily Nightclub take has","been added to the office","safe.","Safe total: $250000 (at","capacity)"]
        both.Push(FakeLine(text))
    notes := EarnSafeFeedParse(both)
    Check(notes.Length = 2 && notes[1].name = "Salvage Yard" && notes[1].total = 11700 && !notes[1].full
        && notes[2].name = "Nightclub" && notes[2].total = 250000 && notes[2].full, "two stacked safe feeds")
    Check(!EarnSafeFeedParse([FakeLine("Your daily Hands On Car Wash earnings have been added"), FakeLine("Safe total: $90000")]).Length, "ignored or unknown business feed")
    Check(!EarnSafeFeedParse(false).Length, "unreadable feed")
    Check(EarnVinewoodSafeAmountOf(wrapped, "Nightclub") = -1, "another business footer is not this safe's amount")
    gSelected := "Nightclub"
    for item in [[0,232],[50000,184],[150000,88],[200000,40],[245000,40]]
        Check(EarnVinewoodSafeNextMs(item[1]) = item[2]*60000, "nightclub next check after $" item[1])
    for item in [[10000,100000,5000,856],[0,100000,30000,136],[35720,100000,2000,1528],[80000,250000,20000,376]]
        Check(EarnVinewoodSafeNextMs(item[1], item[2], item[3]) = item[4]*60000, "next check $" item[1] " cap " item[2] " daily " item[3])
    Check(EarnVinewoodNightclubAmount(Frame("Your Nightclub safe is empty.")) = 0, "explicit nightclub empty detail")
    Check(EarnVinewoodNightclubAmount(Frame("Your Nightclub safe is empty")) = 0, "empty detail read without its period (1006 06:51)")
    Check(EarnVinewoodNightclubAmount(Frame("Your Nightclub safe is empty now")) = -1, "empty detail with trailing words is rejected")
    for text in ["Claim $250000 from your Arcade safe.", "Your Arcade safe is empty.", "Nightclub $250000", "Claim $25O000 from your Nightclub safe.", "Claim $250,00 from your Nightclub safe.", "Claim $250 000 from your Nightclub safe.", "Claim $250000 from your Nightclub safe. Confirm?", "Claim $250000 from Nightclub safe.", "Claim $250000 from your Arcade Nightclub safe"]
        Check(EarnVinewoodNightclubAmount(Frame(text)) = -1, "reject detail: " text)
    Check(EarnVinewoodNightclubAmount(false) = -1, "OCR failure is not an empty safe")
    gSelected := ""
    for name in ["Nightclub", "Hands On Car Wash"] {
        empty := [FakeLine("THE VINEWOOD CLUB APP"), FakeLine("Your " name " safe is empty.")]
        Check(EarnVinewoodSelectedSafe(empty) = name, "missing gray label uses exact empty footer: " name)
        Check(EarnVinewoodSafeAmountOf(empty, name) = 0, "footer fallback is empty only")
    }
    for details in [["Claim $250000 from your Nightclub safe."],
        ["Your Nightclub safe is empty.", "Your Arcade safe is empty."],
        ["Your Nightclub safe is empty.", "Your Nightclub safe is empty."],
        ["Your Nightclub safe is empty.", "Claim $100 from your Arcade safe."],
        ["Your Unknown Shop safe is empty."], ["Your Nightclub safe is empty now"]] {
        missingRows := [FakeLine("THE VINEWOOD CLUB APP")]
        for detail in details
            missingRows.Push(FakeLine(detail))
        Check(EarnVinewoodSelectedSafe(missingRows) = "", "ambiguous or nonempty footer cannot identify missing row")
    }
    Check(EarnVinewoodSelectedSafe([FakeLine("Your Nightclub safe is empty.")]) = "", "empty footer requires app title")
    gSelected := "Arcade"
    Check(EarnVinewoodSelectedSafe(Frame("Your Nightclub safe is empty.")) = "Arcade",
        "visible selected row takes precedence over another safe footer")
}

Reset(mode, state, amounts := "") {
    global transactionPending := Map()
    global gMode, gState, gSelected, gBiz, gIdx, gReads, gClaims, gClaimAttempts, gKeys, gStandWaits, gMctCloses, gCEOCalls, gFailure, gScheduled, gPhysIdle, gOthersIdle
    gMode := mode, gState := state = "earnings_mid" ? "earnings" : state, gBiz := DefaultBiz(), gIdx := state = "earnings_mid" ? 4 : 1
    if (mode = "unknown_business")
        gBiz.InsertAt(3, ["Weed Shop", 50000])
    if (IsObject(amounts))
        for name, amount in amounts
            for biz in gBiz
                if (biz[1] = name)
                    biz[2] := amount
    gSelected := gState = "earnings" ? gBiz[gIdx][1] : "Claim Business Earnings"
    gReads := Map(), gClaims := [], gClaimAttempts := 0, gKeys := [], gStandWaits := 0, gMctCloses := 0, gCEOCalls := 0, gFailure := "", gScheduled := 0, gPhysIdle := 600000, gOthersIdle := 600000
}

EarnReadScreen(*) {
    global gMode, gState, gSelected, gBiz, gIdx, gReads
    if (gMode = "open_unreadable")
        return false
    if (gState = "main") {
        lines := [FakeLine("THE VINEWOOD CLUB APP"), FakeLine("Claim Business Earnings"), FakeLine("Purchase Ammo")]
        if (gMode = "no_earnings")
            lines.Push(FakeLine("No earnings to claim."))
        return lines
    }
    if (gState != "earnings")
        return []
    biz := gBiz[gIdx], name := biz[1], amount := biz[2]
    gSelected := gMode = "no_selection" ? "" : name
    gReads[name] := (gReads.Has(name) ? gReads[name] : 0) + 1
    lines := [FakeLine("THE VINEWOOD CLUB APP")]
    for row in gBiz
        lines.Push(FakeLine(row[1]))
    if (gMode = "empty_row_missing" && amount = 0) {
        gSelected := ""
        lines := [FakeLine("THE VINEWOOD CLUB APP")]
    }
    if (gMode = "unreadable_agency" && name = "Agency") {
        lines.Push(FakeLine("Claim $8O000 from your Agency safe."))
        return lines
    }
    if (gMode = "recheck_amount" && gReads[name] >= 2)
        amount += 1000
    if (amount = 0) {
        lines.Push(FakeLine("Your " name " safe is empty."))
    } else if (name = "Garment Factory") {
        lines.Push(FakeLine("Claim $" amount " from your Garment Factory"), FakeLine("safe."))
    } else {
        lines.Push(FakeLine("Claim $" amount " from your " name " safe."))
    }
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
    return gSelected != "" && row.text = gSelected
}
EarnPress(key) {
    global gMode, gState, gSelected, gBiz, gIdx, gClaims, gClaimAttempts, gKeys
    gKeys.Push(key)
    if (key = "Down") {
        if (gMode = "select_cancel")
            return false
        if (gState = "earnings")
            gIdx := Mod(gIdx, gBiz.Length) + 1, gSelected := gBiz[gIdx][1]
    } else if (key = "Up") {
        if (gState != "standing" && gState != "hud")
            throw Error("Phone-opening Up is invalid when the phone is already open: " gState)
        gState := gMode = "wrong_phone" ? "wrong_phone" : "phone_job"
    } else if (key = "Right" && gState = "phone_job") {
        gState := gMode = "right_stuck" ? "phone_other" : "phone_vinewood"
    } else if (key = "Backspace" && gState = "phone_other") {
        gState := "standing"
    } else if (key = "Enter") {
        if (gState = "phone_vinewood") {
            gState := "main", gSelected := "Claim Business Earnings"
        } else if (gState = "main" && gSelected = "Claim Business Earnings") {
            gState := "earnings", gIdx := 1, gSelected := gBiz[1][1]
        } else if (gState = "earnings") {
            gClaimAttempts += 1
            if (gMode = "cancel_claim")
                return false
            biz := gBiz[gIdx]
            limits := EarnSafeLimits().Has(biz[1]) ? EarnSafeLimits()[biz[1]] : ""
            if (!IsObject(limits) || biz[2] + limits[2] <= limits[1])
                throw Error("Attempted collection from a safe that is not due: " biz[1] " $" biz[2])
            gClaims.Push(biz[1])
            if (gMode != "post_unconfirmed")
                biz[2] := 0
        } else {
            throw Error("Unexpected Enter state: " gState)
        }
    } else if (key = "Backspace") {
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
    if (gClaims.Length && ms = 300 && gMode = "post_unconfirmed")
        return false
    if (gState = "waiting_prompt" && ms = 300 && ++gStandWaits >= 2)
        gState := "standing"
    return true
}
EarnSeen(name, *) {
    global gState, gMode
    if (name = "m_title")
        return gMode = "hud_menu"
    return name = "mct_sit" ? gState = "standing" : name = "ph_joblist_sel" ? gState = "phone_job" : name = "ph_vinewood_sel" && gState = "phone_vinewood"
}
EarnWaitSeen(name, *) => EarnSeen(name)
EarnHudVisible() {
    global gState
    return gState = "hud"
}
AFKOthersIdleMs() {
    global gOthersIdle
    return gOthersIdle
}
RetryIn(value := "") {
    global gEarnRetryIn
    if (value != "")
        gEarnRetryIn := value
    return gEarnRetryIn
}
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
EarnScheduleNext(id, ms) {
    global gScheduled
    if (id != "safe")
        throw Error("Unexpected schedule id " id)
    gScheduled := ms
    return true
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
