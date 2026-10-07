#Requires -Version 5.1
<#
Runs actual Vinewood staff functions with a fake screen and input sink.
No game input, screen capture, window activation, or Main.ahk execution.
#>
[CmdletBinding()]
param(
    [string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe",
    [string]$FixtureDirectory = ''
)
$ErrorActionPreference = 'Stop'
$production = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnStaff.ahk') -Raw -Encoding UTF8
$screen = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnScreen.ahk') -Raw -Encoding UTF8
foreach ($functionName in @('EarnFindText', 'EarnReadDollars', 'EarnMenuStepKey')) {
    $match = [regex]::Matches($screen, ('(?ms)^' + $functionName + '\([^\r\n]*\) \{.*?^\}'))
    if ($match.Count -ne 1) { throw "Expected exactly one screen helper: $functionName" }
    $production += "`n" + $match[0].Value
}
$vinewood = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\Features\Earn\EarnVinewood.ahk') -Raw -Encoding UTF8
$closeMatch = [regex]::Matches($vinewood, '(?ms)^EarnVinewoodClose\(\) \{.*?^\}')
if ($closeMatch.Count -ne 1) { throw 'Expected actual Vinewood close function' }
$production += "`n" + $closeMatch[0].Value
if (-not (Test-Path -LiteralPath $AhkPath -PathType Leaf)) { throw "AutoHotkey executable not found: $AhkPath" }
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global mode, screenState, selected, statuses, requests, keys, reads, failure, checks := 0
global config, cargoNames, cargoStatuses, cargoRequests, cargoReads, activeCount, opens, postReads
global fixtureData := Map(), fixtureKey := ""
global observedDeadlines := []
global menuReads := 0, mainNames := []
global hangarState := "ready", hangarRequests := 0, hangarReads := 0
global greyText := "", greyMissing := 0, flickerReads := 0
OnError(TestUnhandledError)
__FIXTURE_INIT__
try {
    RunTests()
    RunCargoTests()
    RunMenuTests()
    RunFixtureTests()
    RunScheduleTests()
} catch as testError {
    FileAppend(testError.Message " at line " testError.Line "`n" testError.Stack, "*")
    ExitApp(1)
}
FileAppend("PASS EarnStaff cases=" checks " (no game input)`n", "*")
ExitApp(0)

TestUnhandledError(error, *) {
    FileAppend(error.Message " at line " error.Line "`n" error.Stack, "*")
    ExitApp(1)
}

RunFixtureTests() {
    global mode, fixtureData, fixtureKey
    for key, fixture in fixtureData {
        mode := "fixture", fixtureKey := key
        if (fixture.kind = "menu") {
            target := EarnStaffMenuTarget("i)^Manage Staff Members$")
            Check(IsObject(target) && target.text = fixture.name, "actual OCR exact menu target " key)
            Check(Abs(target.y-366) <= 8, "actual OCR menu row position " key)
            Check(EarnMenuRowSelected(target) = (fixture.state = "selected"), "actual OCR menu selected state " key)
        } else if (fixture.kind = "bail") {
            Check(EarnStaffReadBail(fixture.index) = fixture.state, "actual OCR " key)
            Check(EarnStaffReadBail(fixture.index = 1 ? 2 : 1) = "invalid", "actual OCR wrong agent " key)
        } else {
            actual := EarnStaffReadCargo()
            Check(IsObject(actual), "actual OCR readable " key)
            Check(actual.state = fixture.state && actual.name = fixture.name, "actual OCR state/name " key)
            Check(actual.index = fixture.index && actual.count = 5, "actual OCR selection/count " key)
            Check(actual.price = fixture.price, "actual OCR exact price " key)
        }
    }
}

ReadFixture(path) {
    rows := []
    for index, line in StrSplit(Trim(FileRead(path,"UTF-8"), "`r`n"), "`n", "`r") {
        columns := StrSplit(line,"`t")
        if (index = 1)
            continue
        if (columns.Length != 5)
            throw Error("Invalid fixture row")
        rows.Push({x:Integer(columns[1]),y:Integer(columns[2]),w:Integer(columns[3]),h:Integer(columns[4]),text:columns[5]})
    }
    return rows
}

RunTests() {
    global screenState, selected, statuses, requests, keys, reads
    ; mode, initial agent statuses, expected success, confirmed request count.
    cases := [
        ["normal", ["ready","ready"], true, 2],
        ["normal", ["busy","ready"], true, 1],
        ["normal", ["ready","busy"], true, 1],
        ["normal", ["busy","busy"], true, 0],
        ["reverse_footer", ["ready","busy"], true, 1],
        ["wrong_business", ["ready","ready"], false, 0],
        ["duplicate_agent", ["ready","ready"], false, 0],
        ["no_heading", ["ready","ready"], false, 0],
        ["unreadable", ["ready","ready"], false, 0],
        ["changed_before", ["ready","ready"], false, 0],
        ["selection_before", ["ready","ready"], false, 0],
        ["cancel_request", ["ready","ready"], false, 1],
        ["unconfirmed", ["ready","ready"], false, 1],
        ["wrong_after", ["ready","ready"], false, 1],
        ["cancel_wait", ["ready","ready"], false, 1],
        ["transient_bail_footer", ["ready","busy"], true, 1],
        ["unknown_bail_footer", ["ready","busy"], false, 1],
        ["lost_bail_identity", ["ready","busy"], false, 1],
        ["cancel_bail_retry", ["ready","busy"], false, 1],
        ["missing_unselected_agent", ["ready","ready"], true, 2],
        ["missing_selected_agent", ["ready","busy"], false, 0],
        ["bail_double_selection", ["ready","busy"], false, 0],
        ["garbled_after_busy", ["ready","busy"], true, 1],
        ["cancel_select", ["ready","ready"], false, 0]
    ]
    for c in cases {
        Reset(c[1], c[2])
        result := EarnStaffBailAgents()
        Check(result = c[3], c[1] " success=" result)
        Check(requests[1] + requests[2] = c[4], c[1] " request count")
        Check(requests[1] <= 1 && requests[2] <= 1, c[1] " no repeated request")
        for key in keys
            Check(key != "Esc", c[1] " no Esc")
    }
    Reset("normal", ["busy","busy"])
    screenState := "bail", selected := "Agent 1"
    lines := BailFrame()
    Check(EarnStaffBailState(lines, 1) = "busy", "busy exact text")
    Check(EarnStaffBailState(lines, 2) = "invalid", "wrong selected agent")
    Check(EarnStaffBailState(lines, 0) = "invalid", "invalid agent number")
    Check(EarnStaffBailState(false, 1) = "invalid", "false OCR result")
    lines.Push(TextLine("Send your Bail Office staff member out on a job.", 315))
    Check(EarnStaffBailState(lines, 1) = "invalid", "two conflicting footer messages")
    lines := BailFrame()
    lines[4].text := "Your Bail Office staff member is currently"
    lines[5].text := "out on a job. Confirm?"
    Check(EarnStaffBailState(lines, 1) = "invalid", "unexpected footer suffix")
    lines := BailFrame()
    lines[4].x := 650
    Check(EarnStaffBailState(lines, 1) = "invalid", "text outside menu is not a footer")
    lines := BailFrame()
    lines[2].text := "Agent 3"
    Check(EarnStaffBailState(lines, 1) = "invalid", "missing known agent")
    selected := "Agent 2"
    lines := BailFrame(), lines.RemoveAt(2)
    Check(EarnStaffBailState(lines,2) = "busy", "unselected gray Agent1 may be missing")
    selected := "Agent 1"
    lines := BailFrame(), lines.RemoveAt(3)
    Check(EarnStaffBailState(lines,1) = "busy", "unselected gray Agent2 may be missing")
    lines := BailFrame(), lines[2].y += 17
    Check(EarnStaffBailState(lines,1) = "invalid", "agent identity requires observed row position")
    lines := BailFrame(), lines[3].text := "Agent 3"
    Check(EarnStaffBailState(lines,1) = "invalid", "unknown other agent is rejected")
    RunDeadlineTests()
}

RunDeadlineTests() {
    global mode, screenState, selected, requests, keys, reads, postReads, observedDeadlines
    Reset("normal",["busy","busy"])
    screenState := "bail", selected := "Agent 1"
    Check(!EarnStaffWaitBusy("bail",1,A_TickCount), "expired deadline rejected before read")
    Check(reads = 0 && keys.Length = 0, "expired wait has no reads or input")
    Reset("late_bail_busy",["busy","busy"])
    screenState := "bail", selected := "Agent 1", requests[1] := 1
    deadline := A_TickCount+10
    Check(!EarnStaffWaitBusy("bail",1,deadline), "busy after deadline is not accepted")
    Check(keys.Length = 0, "late result sends no input")
    for observed in observedDeadlines
        Check(observed = deadline, "absolute deadline propagated to every OCR read")
    Reset("unknown_bail_footer",["busy","busy"])
    screenState := "bail", selected := "Agent 1", requests[1] := 1
    Check(!EarnStaffWaitBusy("bail",1,A_TickCount+60000), "unknown footer has bounded read-only wait")
    Check(postReads = 121 && keys.Length = 0, "unknown footer never retries Enter")
    Reset("lost_bail_identity",["busy","busy"])
    screenState := "bail", selected := "Agent 1", requests[1] := 1
    Check(!EarnStaffWaitBusy("bail",1,A_TickCount+60000) && reads = 1, "missing title stops immediately")
}

RunMenuTests() {
    global mode, screenState, selected, keys
    for nextMode in ["truncated_menu_raw","missing_selected_menu_row","missing_menu_target","wrong_menu_heading","duplicate_menu_target","misplaced_menu_target","menu_changes_before_enter","menu_selection_before_enter"] {
        Reset(nextMode,["busy","busy"])
        screenState := "main", selected := "Claim Business Earnings"
        result := EarnStaffRoot()
        expected := nextMode = "truncated_menu_raw" || nextMode = "missing_selected_menu_row"
        Check(result = expected, nextMode " root result")
        enters := 0, downs := 0, ups := 0
        for key in keys {
            if (key = "Enter")
                enters += 1
            if (key = "Down")
                downs += 1
            if (key = "Up")
                ups += 1
        }
        Check(enters = (expected ? 1 : 0), nextMode " exact selected verification before Enter")
        Check(downs <= 6, nextMode " bounded menu traversal")
        if (expected)
            Check(screenState = "staff" && downs = 0 && ups = 1, "main menu reaches bottom row with one Up even when selected row OCR is missing")
    }
    ; 작업 중 요원 행의 일반 판독이 깨져도("I Agent 2", 1004 02:01 실측) 흰 글자 판독으로 위치를 확인하고 돌아간다.
    Reset("garbled_busy_root",["busy","busy"])
    screenState := "bail", selected := "Agent 2"
    Check(EarnStaffRoot() && screenState = "staff" && keys.Length = 1 && keys[1] = "Backspace", "garbled busy agent row returns by white-text OCR")
    ; 끝이 보이는 3줄 목록은 짧은 쪽으로 돌고, 아래가 잘린 6줄 메인 목록은 바로 위 줄일 때만 Up 을 쓴다.
    for c in [["staff","Warehouse","Hangar","Up"],["staff","Hangar","Bail Office","Up"],["staff","Bail Office","Hangar","Down"],
        ["staff","Hangar","Warehouse","Down"],["main","Manage Staff Members","Claim Business Earnings","Down"],
        ["main","Purchase Car Club Vehicles","Purchase Ammo","Up"]] {
        Reset("normal",["busy","busy"])
        screenState := c[1], selected := c[2]
        Check(EarnStaffSelectText("i)^" c[3] "$", 6) && selected = c[3] && keys.Length >= 1 && keys[1] = c[4],
            c[1] " " c[2] " -> " c[3] " first key " c[4])
    }
    ; 1007 13:08:41 실제 메뉴는 3줄인데 회색 Bail Office OCR이 빠져 2줄로 계산됐다.
    ; OCR 누락과 독립된 실제 3줄 키 입력 모델에서 최단 한 번으로 목표에 도달해야 한다.
    for c in [["missing_bail_row","Warehouse","Hangar","Up"],
        ["missing_warehouse_row","Bail Office","Hangar","Down"],
        ["missing_hangar_row","Bail Office","Warehouse","Up"]] {
        Reset(c[1],["busy","busy"])
        screenState := "staff", selected := c[2]
        Check(EarnStaffSelectText("i)^" c[3] "$",3) && selected = c[3], c[1] " reaches observed target")
        Check(keys.Length = 1 && keys[1] = c[4], c[1] " uses actual three-row selection positions")
    }
    Reset("missing_hangar_row",["busy","busy"])
    screenState := "staff", selected := "Warehouse"
    Check(!EarnStaffSelectText(EarnStaffHangarPattern(),3), "missing target text cannot be accepted from known slots")
    for key in keys
        Check(key != "Enter", "missing target sends no Enter")
}

RunCargoTests() {
    global hangarState, hangarRequests, hangarReads
    global mode, screenState, selected, statuses, requests, keys, config
    global cargoNames, cargoStatuses, cargoRequests, activeCount, opens
    ; mode, statuses, success, per-run cargo request count.
    cases := [
        ["normal",["ready","ready","full","ready","busy"],true,3],
        ["normal",["busy","busy","full","busy","busy"],true,0],
        ["delayed_cargo",["ready","busy","full","busy","busy"],true,1],
        ["merged_price",["ready","busy","full","busy","busy"],true,1],
        ["comma_price",["ready","busy","full","busy","busy"],true,1],
        ["cargo_price_change",["ready","busy","full","busy","busy"],true,0],
        ["cargo_selection_change",["ready","busy","full","busy","busy"],true,0],
        ["cargo_full_change",["ready","busy","full","busy","busy"],true,0],
        ["cargo_ocr_fail",["ready","busy","full","busy","busy"],false,0],
        ["cargo_bad_price",["ready","busy","full","busy","busy"],false,0],
        ["cargo_wrong_footer",["ready","busy","full","busy","busy"],false,0],
        ["cargo_unconfirmed",["ready","busy","full","busy","busy"],false,1],
        ["cargo_cancel",["ready","busy","full","busy","busy"],false,1],
        ["cargo_after_full",["ready","busy","full","busy","busy"],false,1]
        ,["transient_cargo_footer",["ready","busy","full","busy","busy"],true,1]
        ,["unknown_cargo_footer",["ready","busy","full","busy","busy"],false,1]
        ,["lost_cargo_identity",["ready","busy","full","busy","busy"],false,1]
        ,["cargo_read_glitch",["ready","busy","full","busy","busy"],true,1]
    ]
    for c in cases {
        Reset(c[1], ["busy","busy"])
        cargoStatuses := c[2].Clone()
        result := EarnStaffCargoWarehouses()
        Check(result = c[3], c[1] " cargo success=" result)
        Check(Sum(cargoRequests) = c[4], c[1] " cargo request count=" Sum(cargoRequests))
        for count in cargoRequests
            Check(count <= 1, c[1] " no duplicate warehouse request")
    }
    for count in [1,2,3,4,5] {
        Reset("normal",["busy","busy"])
        activeCount := count
        Check(EarnStaffCargoWarehouses() && Sum(cargoRequests) = count, "observed warehouse count " count)
    }
    Reset("normal",["busy","busy"])
    screenState := "cargo", selected := cargoNames[1]
    Check(EarnStaffReadCargo().count = 5, "infer five rows from observed footer position")
    Check(EarnStaffReadCargo().state = "ready", "exact selected cargo detail")
    for badPrice in ["$7,50","$7500 $7500","$75OO"] {
        lines := [TextLine(cargoNames[1],181,200,320),TextLine(badPrice,181,420,62)]
        Check(!EarnStaffCargoLabel(lines,181), "malformed price " badPrice)
    }
    lines := [TextLine(cargoNames[1],181,200,320),TextLine("$7500",199,420,62)]
    Check(!EarnStaffCargoLabel(lines,181), "price cannot attach to another row")
    lines := [TextLine(cargoNames[1],181,200,320),TextLine("$7500",181,420,62),TextLine("$7500",181,420,62)]
    Check(!EarnStaffCargoLabel(lines,181), "duplicated price column")
    lines := [TextLine("Unknown \\E injected",181,200,320),TextLine("$7500",181,420,62)]
    Check(!EarnStaffCargoLabel(lines,181), "reject regex control characters in name")
    Check(!EarnStaffCargoLabel(false,181), "cargo OCR failure")
    Check(!EarnStaffCargoDetail([TextLine("Send your Warehouse staff member out",373),TextLine("on a job. Confirm?",400)],TextLine("THE VINEWOOD CLUB APP",144)), "cargo suffix rejected")
    Check(!EarnStaffCargoDetail([TextLine("Send your Warehouse staff member out",410),TextLine("on a job.",437)],TextLine("THE VINEWOOD CLUB APP",144)), "six warehouses rejected")
    Check(!EarnStaffCargoDetail([TextLine("Send your Warehouse staff member out",350),TextLine("on a job.",377)],TextLine("THE VINEWOOD CLUB APP",144)), "footer between row positions rejected")
    for nextMode in ["cargo_repeat_name","cargo_stuck","cargo_no_selection","cargo_double_selection"] {
        Reset(nextMode,["busy","busy"])
        cargoStatuses := ["busy","busy","full","busy","busy"]
        skipped := EarnStaffCargoWarehouses()
        Check(Sum(cargoRequests) = 0, nextMode " does not order")
        if (skipped)
            Check(screenState = "staff", nextMode " soft skip leaves the warehouse list")
    }
    Reset("cargo_disabled_price",["busy","busy"])
    cargoStatuses := ["busy","busy","full","busy","busy"]
    Check(EarnStaffCargoWarehouses() && Sum(cargoRequests) = 0, "disabled price may be unreadable")

    ; Use actual task orchestration and actual bounded app-close implementation.
    for start in ["main","staff","bail","cargo"] {
        Reset("normal",["busy","ready"])
        screenState := start, selected := start = "bail" ? "Agent 1" : start = "cargo" ? cargoNames[1] : start = "main" ? "Claim Business Earnings" : "Hangar"
        cargoStatuses := ["busy","ready","full","busy","ready"]
        Check(EarnVinewoodStaffTask(), "combined task from " start)
        Check(screenState = "standing" && requests[2] = 1 && Sum(cargoRequests) = 2, "combined task final state " start)
        Check(opens = 1, "single app opening " start)
        for key in keys
            Check(key != "Esc", "combined task no Esc")
    }
    Reset("normal",["ready","ready"])
    config["Settings"]["EarnCargoStaff"] := 0
    Check(EarnVinewoodStaffTask() && Sum(requests) = 2 && Sum(cargoRequests) = 0, "bail only")
    Reset("normal",["ready","ready"])
    config["Settings"]["EarnBailAgents"] := 0
    Check(EarnVinewoodStaffTask() && Sum(requests) = 0 && Sum(cargoRequests) = 5, "cargo only")
    Reset("normal",["ready","ready"])
    config["Settings"]["EarnBailAgents"] := 0, config["Settings"]["EarnCargoStaff"] := 0
    Check(EarnVinewoodStaffTask() && opens = 0 && keys.Length = 0, "disabled task performs no UI work")
    Reset("open_fail",["ready","ready"])
    Check(!EarnVinewoodStaffTask() && keys.Length = 0, "open failure is not ignored")
    Reset("normal",["ready","ready"])
    screenState := "unknown"
    Check(!EarnVinewoodStaffTask() && keys.Length = 0, "unknown menu sends no input")
    Reset("grey_staff_menu",["busy","busy"])
    screenState := "main", selected := "Claim Business Earnings"
    config["Settings"]["EarnHangarStaff"] := 1
    Check(EarnStaffRoot() = "idle" && keys.Length = 0, "grey Manage Staff Members root is idle without input")
    Reset("busy_footer",["busy","busy"])
    screenState := "main", selected := "Manage Staff Members"
    Check(EarnStaffRoot() = "idle" && keys.Length = 0, "all-busy footer is idle without Enter")
    Reset("busy_footer",["busy","busy"])
    screenState := "main", selected := "Manage Staff Members"
    config["Settings"]["EarnHangarStaff"] := 1
    Check(EarnVinewoodStaffTask() && failure = "" && hangarRequests = 0 && Sum(requests) = 0, "all-busy footer skips every staff job")
    Reset("grey_staff_menu",["busy","busy"])
    screenState := "main", selected := "Claim Business Earnings"
    config["Settings"]["EarnHangarStaff"] := 1
    Check(EarnVinewoodStaffTask() && failure = "" && Sum(requests) = 0 && Sum(cargoRequests) = 0 && hangarRequests = 0
        && EarnStaffTrack() = 300000, "grey Manage Staff Members skips every staff job")
    ; 1005 19:24·20:01 녹화 프레임을 실제 판독기로 읽은 회색 줄
    for text in ["Manage Staff Mem ers", "Manage SfaffMem>ers", "Manage Staff _Members", "Manage StaffMembers", "Manage S!affMembers",
        "anageSta", "anag+t"] {   ; 1006 02:24 녹화: 첫 글자 M 이 빠짐
        Reset("grey_staff_split",["busy","busy"])
        greyText := text
        screenState := "main", selected := "Claim Business Earnings"
        Check(EarnStaffRoot() = "idle" && keys.Length = 0, "grey read " text " is idle without input")
    }
    Reset("grey_staff_split",["busy","busy"])
    global greyText, greyMissing
    greyText := "anageSta", greyMissing := 2   ; 처음 두 번은 회색 줄이 아예 안 읽힘
    screenState := "main", selected := "Claim Business Earnings"
    Check(EarnStaffRoot() = "idle" && keys.Length = 0, "grey row missing from two reads is reread without input")
    Reset("grey_staff_unread",["busy","busy"])   ; 1006 03:05: 회색 줄이 한 번도 안 읽힘
    screenState := "main", selected := "Claim Business Earnings"
    Check(EarnStaffRoot() = "idle" && keys.Length = 0, "never-read grey row is recognised by its grey pixels")
    Reset("missing_menu_target",["ready","ready"])
    screenState := "main", selected := "Claim Business Earnings"
    Check(!EarnStaffRoot() && keys.Length = 0, "unread row without grey pixels still fails without input")
    Reset("grey_staff_split",["busy","busy"])
    greyText := "Manage S!affMembers"
    screenState := "main", selected := "Claim Business Earnings"
    config["Settings"]["EarnHangarStaff"] := 1
    Check(EarnVinewoodStaffTask() && failure = "" && Sum(requests) = 0 && Sum(cargoRequests) = 0 && hangarRequests = 0
        && EarnStaffTrack() = 300000, "grey Manage Staff Mem ers split read skips every staff job, not a failure")
    Reset("grey_bail_root",["busy","busy"])
    Check(EarnStaffRoot() && keys.Length = 0, "grey Bail Office list is still the staff list")
    Reset("grey_bail_root",["ready","ready"])
    cargoStatuses := ["busy","busy","full","busy","busy"]
    Check(EarnVinewoodStaffTask() && Sum(requests) = 0, "grey Bail Office skips bail agents without entering")
    Reset("garbled_list",["ready","ready"])
    config["Settings"]["EarnCargoStaff"] := 0
    Check(EarnVinewoodStaffTask() && failure = "" && Sum(requests) = 2, "garbled Warehouse/Bail Office reads still reach both agents (1006 20:35)")
    Reset("garbled_list2",["ready","ready"])   ; 1006 21:30 녹화
    config["Settings"]["EarnCargoStaff"] := 0
    Check(EarnVinewoodStaffTask() && failure = "" && Sum(requests) = 2, "Warehous/ail Office reads still reach both agents (1006 21:30)")
    for item in [["Warehous","~Warehouse",1],["Wareho se","~Warehouse",1],["Warehoåse","~Warehouse",1],["ail Office","~Bail Office",1],
        ["Bail Offi","~Bail Office",1],["Hangar","~Hangar",1],["Hangr","~Hangar",1],["Hang","~Hangar",0],["Bail Office","~Warehouse",0],
        ["Manage Staff Members","~Warehouse",0],["","~Hangar",0]]
        Check(!!EarnStaffTextMatch(item[1], item[2]) = item[3], "fuzzy " item[1] " vs " item[2])
    Reset("bail_busy_selected",["busy","busy"])
    cargoStatuses := ["busy","busy","full","busy","busy"]
    Check(EarnVinewoodStaffTask() && failure = "" && Sum(requests) = 0, "busy footer under a selected Bail Office skips agents (1006 20:04)")
    Reset("grey_warehouse_root",["busy","busy"])
    Check(EarnVinewoodStaffTask() && Sum(cargoRequests) = 0, "grey Warehouse skips cargo staff without entering")
    for c in [["hangar_ready","ready",true,1,"busy"], ["hangar_busy","busy",true,0,"busy"],
        ["hangar_bad_price","ready",true,0,"ready"], ["hangar_unknown","odd",true,0,"odd"],
        ["hangar_unconfirmed","ready",false,1,"ready"], ["hangar_flaky","ready",true,0,"ready"],
        ; 1006 녹화: 설명 문구가 한두 글자 깨져도 보내고, 깨진 작업 중 문구에는 사지 않는다.
        ["hangar_garbled","ready",true,1,"busy"], ["hangar_garbled_busy","busy",true,0,"busy"]] {
        Reset(c[1],["busy","busy"])
        hangarState := c[2]
        config["Settings"]["EarnBailAgents"] := 0, config["Settings"]["EarnCargoStaff"] := 0, config["Settings"]["EarnHangarStaff"] := 1
        result := EarnVinewoodStaffTask()
        Check(result = c[3] && hangarRequests = c[4] && hangarState = c[5], c[1] " hangar result=" result " requests=" hangarRequests)
    }
    ; 1007 04:00: 키를 누른 직후 판독에서 앱 제목이 빠진다(일반·흰 글자 판독 한 번씩).
    Reset("heading_flicker",["busy","busy"])
    hangarState := "ready", screenState := "staff", selected := "Warehouse"
    Check(EarnStaffSelectText(EarnStaffHangarPattern(), 3) && selected = "Hangar", "app title dropped once after a key press is reread")
    Reset("close_fail",["busy","busy"])
    cargoStatuses := ["busy","busy","full","busy","busy"]
    Check(!EarnVinewoodStaffTask(), "app-close failure prevents success")
}
Sum(values) {
    total := 0
    for value in values
        total += value
    return total
}

Reset(nextMode, initial) {
    global mode, screenState, selected, statuses, requests, keys, reads, failure
    global config, cargoNames, cargoStatuses, cargoRequests, cargoReads, activeCount, opens, postReads
    global observedDeadlines
    global menuReads, mainNames, hangarState, hangarRequests, hangarReads, greyMissing, flickerReads
    greyMissing := 0, flickerReads := 0
    mode := nextMode, screenState := "staff", selected := "Hangar"
    hangarState := "ready", hangarRequests := 0, hangarReads := 0
    statuses := initial.Clone(), requests := [0,0], keys := [], reads := 0, failure := ""
    config := Map("Settings",Map("EarnBailAgents",1,"EarnCargoStaff",1))
    cargoNames := ["Discount Retail Unit","Railyard Warehouse","Foreclosed Garage","Darnell Bros Warehouse","West Vinewood Backlot"]
    cargoStatuses := ["ready","ready","ready","ready","ready"], cargoRequests := [0,0,0,0,0]
    cargoReads := 0, activeCount := 5, opens := 0, postReads := 0
    observedDeadlines := []
    menuReads := 0
    mainNames := ["Claim Business Earnings","Purchase Ammo","Request Car Club Vehicle","Purchase Car Club Vehicles","Claim Destroyed Vehicles","Manage Staff Members"]
}
EarnReadScreen(area, whiteText := false, deadline := 0) {
    global mode, fixtureData, fixtureKey
    global observedDeadlines
    if (deadline)
        observedDeadlines.Push(deadline)
    if (mode = "fixture") {
        fixture := fixtureData[fixtureKey]
        if (whiteText)
            return fixture.detail.Clone()
        return (area[4] = 35 ? fixture.label : fixture.heading).Clone()
    }
    rows := MockReadScreen(area, whiteText)
    if (!(rows is Array))
        return rows
    crop := []
    for row in rows {
        if (row.text != "" && row.y >= area[2] && row.y < area[2]+area[4])
            crop.Push(row)
    }
    return crop
}
MockReadScreen(area, whiteText) {
    global mode, screenState, selected, statuses, reads, requests
    global cargoNames, cargoStatuses, cargoRequests, cargoReads, postReads
    global menuReads, mainNames, hangarReads, greyText, greyMissing, flickerReads, keys
    if (screenState = "main") {
        if (area[4] = 263 || area[4] = 300)
            menuReads += 1
        rows := [TextLine("THE VINEWOOD CLUB APP",144)]
        for index, name in mainNames
            rows.Push(TextLine(name,144+37*index))
        ; 실제 로그처럼 첫 판독에서 선택 막대 안의 검은 글자 한 줄만 빠진다. 키를 누른 뒤에는 다시 읽힌다.
        if (mode = "missing_selected_menu_row" && keys.Length = 0) {
            for index, name in mainNames {
                if (name = selected) {
                    rows.RemoveAt(index+1)
                    break
                }
            }
        }
        if (mode = "truncated_menu_raw" && !whiteText || mode = "missing_menu_target")
            rows[7].text := "Manage Staff Mem"
        if (mode = "grey_staff_menu")
            rows[7].text := "Manage Staff Mempers"
        if (mode = "grey_staff_split")
            rows[7].text := greyText
        if (mode = "grey_staff_split" && greyMissing > 0 && greyMissing-- || mode = "grey_staff_unread")
            rows.RemoveAt(7)
        if (mode = "wrong_menu_heading" || mode = "menu_changes_before_enter" && menuReads >= 4)
            rows[1].text := "UNKNOWN MENU"
        if (mode = "duplicate_menu_target")
            rows.Push(TextLine("Manage Staff Members",329))
        if (mode = "busy_footer")
            rows.Push(TextLine("All of your staff members are currently",414), TextLine("busy.",440))
        else
            rows.Push(TextLine("Send your staff members out on jobs.",414))
        if (mode = "misplaced_menu_target")
            rows[7].y := 387
        if (mode = "menu_selection_before_enter" && menuReads >= 4)
            selected := "Claim Business Earnings"
        return rows
    }
    if (screenState = "staff") {
        rows := [TextLine(flickerReads > 0 && flickerReads-- ? "THE VINEWOOD" : "THE VINEWOOD CLUB APP",144),TextLine("Hangar",181),TextLine("Warehouse",218),TextLine("Bail Office",255),
            TextLine("Manage your Warehouse staff.",300)]
        ; 격납고 줄이 선택되면 같은 줄 오른쪽에 가격, 목록 아래에 상태 문구가 뜬다(1004 21:36 녹화).
        if (selected = "Hangar" && hangarState != "") {
            hangarReads += 1
            if (hangarState = "ready")
                rows.Push(TextLine(mode = "hangar_bad_price" || mode = "hangar_flaky" && hangarReads >= 2 ? "$250000" : "$25000",181,420,80))
            rows[5].text := hangarState = "ready" ? "Send your Hangar staff member out on a job."
                : hangarState = "busy" ? "Your Hangar staff member is currently out on a job." : "Something else."
            if (mode = "hangar_garbled" && hangarState = "ready")
                rows[5].text := "Fend yo r Hangar staff member out"   ; 1006 22:17 녹화: "on a job." 이 빠짐
            if (mode = "hangar_garbled_busy" && hangarState = "busy")
                rows[5].text := "Elour Hangar staff membei is currentl out on a job."
        }
        ; 1006 20:35 녹화: 밝은 배경 앞에서 고르지 않은 줄 판독이 깨진다.
        if (mode = "garbled_list" || mode = "garbled_list2") {
            if (selected != "Warehouse")
                rows[3].text := mode = "garbled_list" ? "Warehou e" : "Warehous"
            if (selected != "Bail Office")
                rows[4].text := mode = "garbled_list" ? "Bail Offic" : "ail Office"
        }
        ; 1006 20:04 녹화: 요원이 모두 나간 Bail Office 를 고르면 위 Warehouse 가 깨지고 아래에 바쁨 문구가 뜬다.
        if (mode = "bail_busy_selected" && selected = "Bail Office") {
            rows[3].text := "Wareho se"
            rows[5].text := "Your Bai Office staff member are"
            rows.Push(TextLine("currentl busy.",328))
        }
        ; 요원이 모두 나가 회색인 Bail Office: 일반 판독은 "pail Office", 흰 글자 판독은 줄이 빠진다(1004 15:04 녹화 실측).
        if (mode = "grey_bail_root") {
            if (whiteText)
                rows.RemoveAt(4)
            else
                rows[4].text := "pail Office"
        }
        if (mode = "missing_bail_row")
            rows.RemoveAt(4)
        if (mode = "missing_warehouse_row")
            rows.RemoveAt(3)
        if (mode = "missing_hangar_row")
            rows.RemoveAt(2)
        return rows
    }
    if (screenState = "cargo") {
        if (area[4] = 40)
            cargoReads += 1
        if (mode = "cargo_ocr_fail")
            return false
        ; 조달 Enter 뒤 제목 판독이 세 번 흔들린다(1005 22:14:42).
        if (mode = "cargo_read_glitch" && cargoRequests[1] && area[4] = 40 && ++postReads <= 3)
            return false
        if (mode = "delayed_cargo" && cargoRequests[1] && area[4] = 40 && ++postReads >= 80)
            cargoStatuses[1] := "busy"
        if (mode = "cargo_selection_change" && cargoReads >= 2)
            selected := cargoNames[2]
        if (mode = "cargo_full_change" && cargoReads >= 2)
            cargoStatuses[1] := "full"
        lines := CargoFrame()
        if (mode = "cargo_price_change" && cargoReads >= 2)
            lines[3].text := "$75000"
        if (mode = "cargo_bad_price")
            lines[3].text := "$75000"
        if (mode = "cargo_wrong_footer")
            lines[12].text := "Send your Hangar staff member out", lines[13].text := "on a job."
        if (mode = "cargo_repeat_name")
            lines[4].text := cargoNames[1]
        if (mode = "cargo_disabled_price") {
            Loop 5
                lines[2*A_Index+1].text := ""
        }
        if (cargoRequests[1]) {
            if (mode = "lost_cargo_identity" && area[4] = 35)
                lines[2].text := "Changed Warehouse"
            if (whiteText && (mode = "transient_cargo_footer" || mode = "unknown_cargo_footer")) {
                postReads += 1
                if (mode = "unknown_cargo_footer" || postReads <= 2)
                    return false
            }
        }
        if (whiteText && area[4] != 229 && area[4] != 263 && area[4] != 300 && area[4] != 80)
            throw Error("Cargo footer must use white-text OCR with all possible footer positions")
        if (!whiteText && area[4] = 229)
            return false
        return lines
    }
    if (screenState != "bail")
        return []
    if (area[4] = 115)
        reads += 1
    if (mode = "unreadable")
        return false
    if (mode = "changed_before" && reads >= 2)
        statuses[1] := "busy"
    if (mode = "selection_before" && reads >= 2)
        selected := "Agent 2"
    lines := BailFrame()
    if (mode = "duplicate_agent")
        lines.Push(TextLine("Agent 1",200))
    if (mode = "no_heading")
        lines[1].text := "OTHER APP"
    if (mode = "wrong_business")
        lines[4].text := "Send your Warehouse staff member out on", lines[5].text := "a job."
    if (mode = "reverse_footer") {
        last := lines.Pop(), previous := lines.Pop()
        lines.Push(last, previous)
    }
    if (mode = "missing_unselected_agent")
        lines.RemoveAt(selected = "Agent 1" ? 3 : 2)
    if (mode = "missing_selected_agent")
        lines.RemoveAt(selected = "Agent 1" ? 2 : 3)
    ; 1004 05:24 실측: 작업 중으로 바뀐 직후 일반 판독이 "j Agent 2" 처럼 깨진다.
    if (mode = "garbled_after_busy" && requests[1] && !whiteText && area[4] = 115)
        lines[selected = "Agent 1" ? 2 : 3].text := "j " selected
    if (mode = "garbled_busy_root" && !whiteText)
        lines[selected = "Agent 1" ? 2 : 3].text := "I " selected
    if (requests[1]) {
        if (mode = "lost_bail_identity")
            lines[1].text := "UNKNOWN CONFIRMATION"
        if (mode = "late_bail_busy")
            Sleep(20)
        if (whiteText && (mode = "transient_bail_footer" || mode = "unknown_bail_footer" || mode = "cancel_bail_retry")) {
            postReads += 1
            if (mode != "transient_bail_footer" || postReads <= 2)
                return false
        }
    }
    if (area[4] = 75 && !whiteText)
        return false
    return lines
}
CargoFrame() {
    global mode, selected, cargoNames, cargoStatuses, activeCount
    lines := [TextLine("THE VINEWOOD CLUB APP",144)]
    state := "ready"
    Loop activeCount {
        index := A_Index, y := 144+37*index
        if (mode = "merged_price")
            lines.Push(TextLine(cargoNames[index] " $7500",y))
        else
            lines.Push(TextLine(cargoNames[index],y,200,320),TextLine(mode = "comma_price" ? "$7,500" : "$7500",y,420,62))
        if (selected = cargoNames[index])
            state := cargoStatuses[index]
    }
    detail := state = "busy" ? ["Your Warehouse staff member is currently", "out on a job."]
        : state = "full" ? ["There is no more room to store cargo for", "this property."]
        : ["Send your Warehouse staff member out", "on a job."]
    lines.Push(TextLine(detail[1],144+37*activeCount+44),TextLine(detail[2],144+37*activeCount+71))
    return lines
}
BailFrame() {
    global selected, statuses
    index := selected = "Agent 1" ? 1 : 2
    if (statuses[index] = "busy")
        detail := ["Your Bail Office staff member is currently", "out on a job."]
    else
        detail := ["Send your Bail Office staff member out on", "a job."]
    return [TextLine("THE VINEWOOD CLUB APP",144),TextLine("Agent 1",181),TextLine("Agent 2",218),TextLine(detail[1],262),TextLine(detail[2],289)]
}
TextLine(text, y, x := 240, w := 400) => {text:text, x:x, y:y, w:w, h:22}
EarnMenuRowSelected(row) {
    global mode, screenState, selected, cargoNames, activeCount
    global fixtureData, fixtureKey
    if (mode = "fixture") {
        fixture := fixtureData[fixtureKey]
        return Abs(row.y-fixture.selectedY) < 8
    }
    if (!row.HasOwnProp("text")) {
        if (screenState = "staff") {
            names := ["Hangar","Warehouse","Bail Office"]
            for index, name in names {
                if (selected = name && Abs(row.y-144-37*index) < 8)
                    return true
            }
            return false
        }
        if (screenState = "bail")
            return mode = "bail_double_selection" || Abs(row.y-(selected = "Agent 1" ? 181 : 218)) < 8
        if (screenState != "cargo" || mode = "cargo_no_selection")
            return false
        if (mode = "cargo_double_selection")
            return row.y = 181 || row.y = 218
        Loop activeCount {
            if (selected = cargoNames[A_Index] && Abs(row.y-144-37*A_Index) < 8)
                return true
        }
        return false
    }
    return row.text = selected || row.text = selected " $7500"
}
EarnPress(key) {
    global mode, screenState, selected, statuses, requests, keys, hangarState, hangarRequests, hangarReads
    global cargoNames, cargoStatuses, cargoRequests, activeCount
    global mainNames
    keys.Push(key)
    global flickerReads
    if (mode = "heading_flicker" && (key = "Up" || key = "Down"))
        flickerReads := 2
    if (key = "Up") {
        ; 목록은 위 끝에서 아래 끝으로 돈다. Down 의 역방향이다.
        if (mode = "cancel_select")
            return false
        if (screenState = "main") {
            for index, name in mainNames {
                if (name = selected) {
                    selected := mainNames[Mod(index-2+mainNames.Length,mainNames.Length)+1]
                    break
                }
            }
        } else if (screenState = "staff")
            selected := selected = "Hangar" ? "Bail Office" : selected = "Bail Office" ? "Warehouse" : "Hangar"
        else if (screenState = "cargo") {
            Loop activeCount {
                if (selected = cargoNames[A_Index]) {
                    selected := cargoNames[Mod(A_Index-2+activeCount,activeCount)+1]
                    break
                }
            }
        }
        else
            selected := selected = "Agent 1" ? "Agent 2" : "Agent 1"
        return true
    }
    if (key = "Down") {
        if (mode = "cancel_select")
            return false
        if (screenState = "main") {
            for index, name in mainNames {
                if (name = selected) {
                    selected := mainNames[Mod(index,mainNames.Length)+1]
                    break
                }
            }
        } else if (screenState = "staff")
            selected := selected = "Hangar" ? "Warehouse" : selected = "Warehouse" ? "Bail Office" : "Hangar"
        else if (screenState = "cargo") {
            if (mode = "cargo_stuck")
                return true
            Loop activeCount {
                if (selected = cargoNames[A_Index]) {
                    selected := cargoNames[Mod(A_Index,activeCount)+1]
                    break
                }
            }
        }
        else
            selected := selected = "Agent 1" ? "Agent 2" : "Agent 1"
    } else if (key = "Enter") {
        if (screenState = "main" && selected = "Manage Staff Members") {
            screenState := "staff", selected := "Hangar"
        } else if (screenState = "staff") {
            if (selected = "Warehouse" && mode = "grey_warehouse_root") {
                ; 창고 직원이 모두 조달 중이면 Enter 가 무시되고 목록이 그대로다.
            } else if (selected = "Warehouse") {
                screenState := "cargo", selected := cargoNames[1]
            } else if (selected = "Bail Office" && mode = "bail_busy_selected") {
                ; 요원이 모두 나가 있으면 Enter 가 무시된다.
            } else if (selected = "Bail Office") {
                screenState := "bail", selected := "Agent 1"
            } else if (selected = "Hangar") {
                if (hangarState != "ready")
                    throw Error("Attempt to dispatch busy hangar staff")
                hangarRequests += 1
                if (mode != "hangar_unconfirmed")
                    hangarState := "busy"
            } else
                throw Error("Attempt to dispatch wrong business")
        } else if (screenState = "cargo") {
            Loop activeCount {
                if (selected != cargoNames[A_Index])
                    continue
                index := A_Index
                if (cargoStatuses[index] != "ready")
                    throw Error("Attempt to order busy/full warehouse")
                cargoRequests[index] += 1
                if (mode = "cargo_cancel")
                    return false
                if (mode != "cargo_unconfirmed" && mode != "delayed_cargo")
                    cargoStatuses[index] := mode = "cargo_after_full" ? "full" : "busy"
            }
        } else if (screenState = "bail") {
            index := selected = "Agent 1" ? 1 : 2
            if (statuses[index] != "ready")
                throw Error("Attempt to dispatch busy agent")
            requests[index] += 1
            if (mode = "cancel_request")
                return false
            if (mode != "unconfirmed")
                statuses[index] := "busy"
            if (mode = "wrong_after")
                selected := "Agent 2"
        }
    } else if (key = "Backspace") {
        if (mode = "close_fail")
            return false
        if (screenState = "bail" || screenState = "cargo")
            screenState := "staff", selected := "Hangar"
        else if (screenState = "staff")
            screenState := "main", selected := "Manage Staff Members"
        else if (screenState = "main")
            screenState := "standing"
    }
    return true
}
EarnSleep(*) {
    global mode, requests
    return !(mode = "cancel_wait" && requests[1])
}
EarnAborted() {
    global mode, postReads
    return mode = "cancel_bail_retry" && postReads >= 2
}
EarnSeen(name, *) {
    global screenState
    return name = "mct_sit" && screenState = "standing"
}
EarnWarehouseBrightLabel(row) {
    global mode
    return mode != "grey_staff_menu" && mode != "grey_staff_split"
}
EarnWarehouseGreyLabel(row) {
    global mode
    return mode = "grey_staff_unread" && row.y = 144 + 37 * 6
}
EarnVinewoodOpen() {
    global mode, opens
    opens += 1
    return mode != "open_fail"
}
EarnScheduleNext(*) => true
RunScheduleTests() {
    EarnStaffTrack("reset")
    Check(EarnStaffTrack() = 300000, "schedule: nothing seen uses 5 min")
    EarnStaffTrack("sched cargo", "full")
    Check(EarnStaffTrack() = 300000, "schedule: full warehouse alone uses 5 min")
    EarnStaffTrack("sched agent A", "busy")
    Check(EarnStaffTrack() = 300000, "schedule: busy with unknown send time rechecks in 5 min")
    EarnStaffTrack("sched agent B", "sent")
    ms := EarnStaffTrack()
    Check(ms > 48 * 60000 && ms <= 49 * 60000, "schedule: sent agent returns after about 49 min")
    EarnStaffTrack("sched agent B", "busy")
    EarnStaffTrack("sched agent A", "busy")
    Check(EarnStaffTrack() = 300000, "schedule: unknown busy agent wins over later known return")
    EarnStaffTrack("sched agent B", "busy")
    ms := EarnStaffTrack()
    Check(ms > 48 * 60000 && ms <= 49 * 60000, "schedule: known busy agent keeps its return time")
}
EarnLog(*) {
}
EarnFail(message) {
    global failure
    failure := message
    return false
}
Check(ok, name) {
    global checks
    checks += 1
    if (!ok)
        throw Error("FAIL " name)
}
'@

function ConvertTo-AhkString([string]$Value) {
    '"' + $Value.Replace('`','``').Replace('"','`"') + '"'
}

$testPath = Join-Path ([IO.Path]::GetTempPath()) ('gta-earn-staff-' + [Guid]::NewGuid().ToString('N') + '.ahk')
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
$fixtureFiles = New-Object Collections.Generic.List[string]
try {
    $fixtureInit = ''
    if ($FixtureDirectory) {
        Add-Type -AssemblyName System.Drawing
        $ocrPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\Core\EarnOcr.ps1'))
        $fixtureSpecs = @(
            @('earn-bail-agents','bail',1,'ready','',-1),
            @('earn-bail-agent1-sent','bail',1,'busy','',-1),
            @('earn-staff-agent2-result','bail',2,'busy','',-1),
            @('earn-cargo-warehouses','cargo',1,'ready','Discount Retail Unit',7500),
            @('earn-cargo-disabled','cargo',3,'full','Foreclosed Garage',-1),
            @('earn-cargo-first-result','cargo',1,'busy','Discount Retail Unit',-1),
            @('earn-staff-final','menu',1,'unselected','Manage Staff Members',-1),
            @('earn-staff-select','menu',6,'selected','Manage Staff Members',-1)
        )
        foreach ($spec in $fixtureSpecs) {
            $imagePath = [IO.Path]::GetFullPath((Join-Path $FixtureDirectory ($spec[0] + '.png')))
            if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) { throw "Fixture missing: $imagePath" }
            $fixtureBase = $testPath + '-' + $spec[0]
            $headingPath = $fixtureBase + '-heading.tsv'
            $detailPath = $fixtureBase + '-detail.tsv'
            $labelPath = $fixtureBase + '-label.tsv'
            $fixtureFiles.Add($headingPath)
            $fixtureFiles.Add($detailPath)
            $fixtureFiles.Add($labelPath)
            $headingHeight = if ($spec[1] -eq 'bail') {115} elseif ($spec[1] -eq 'menu') {263} else {40}
            $ocrResult = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ocrPath -ImagePath $imagePath -X 25 -Y 125 -W 450 -H $headingHeight -OutputPath $headingPath
            if ($LASTEXITCODE -ne 0) { throw "Fixture title OCR failed: $ocrResult" }
            $headingRows = @(Import-Csv -LiteralPath $headingPath -Delimiter "`t")
            $headingRowsMatching = @($headingRows | Where-Object { $_.text -eq 'THE VINEWOOD CLUB APP' })
            if ($headingRowsMatching.Count -ne 1) { throw "Fixture title missing: $imagePath" }
            $headingY = [int]$headingRowsMatching[0].y
            $selectedY = $headingY + 37 * $spec[2]
            $sourceBitmap = [Drawing.Bitmap]::FromFile($imagePath)
            try {
                $pixel = $sourceBitmap.GetPixel(32,$selectedY)
                if ($pixel.R -le 170 -or $pixel.G -le 170 -or $pixel.B -le 170) { throw "Fixture selected row not highlighted: $imagePath" }
            } finally { $sourceBitmap.Dispose() }
            if ($spec[1] -eq 'menu') {
                $detailY = 125
                $detailHeight = 263
                $labelExpression = '[]'
            } elseif ($spec[1] -eq 'bail') {
                $secondAgent = @($headingRows | Where-Object { $_.text -eq 'Agent 2' })
                if ($secondAgent.Count -ne 1) { throw "Fixture second agent missing: $imagePath" }
                $detailY = [int]$secondAgent[0].y + 22
                $detailHeight = 75
                $labelExpression = '[]'
            } else {
                $detailY = $headingY + 56
                $detailHeight = 229
                $ocrResult = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ocrPath -ImagePath $imagePath -X 28 -Y ($selectedY - 17) -W 434 -H 35 -OutputPath $labelPath
                if ($LASTEXITCODE -ne 0) { throw "Fixture selected row OCR failed: $ocrResult" }
                $labelExpression = 'ReadFixture(' + (ConvertTo-AhkString $labelPath) + ')'
            }
            $ocrResult = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ocrPath -ImagePath $imagePath -X 28 -Y $detailY -W 434 -H $detailHeight -WhiteText -OutputPath $detailPath
            if ($LASTEXITCODE -ne 0) { throw "Fixture footer OCR failed: $ocrResult" }
            $fixtureInit += 'fixtureData[' + (ConvertTo-AhkString $spec[0]) + '] := {kind:' + (ConvertTo-AhkString $spec[1]) + ',index:' + $spec[2] + ',state:' + (ConvertTo-AhkString $spec[3]) + ',name:' + (ConvertTo-AhkString $spec[4]) + ',price:' + $spec[5] + ',selectedY:' + $selectedY + ',heading:ReadFixture(' + (ConvertTo-AhkString $headingPath) + '),detail:ReadFixture(' + (ConvertTo-AhkString $detailPath) + '),label:' + $labelExpression + '}' + "`n"
        }
    }
    $driver = $driver.Replace('__FIXTURE_INIT__',$fixtureInit)
    [IO.File]::WriteAllText($testPath, $driver + "`n" + $production + "`n", (New-Object Text.UTF8Encoding($true)))
    $testProcess = [Diagnostics.Process]::Start($info)
    $stdoutRead = $testProcess.StandardOutput.ReadToEndAsync()
    $stderrRead = $testProcess.StandardError.ReadToEndAsync()
    if (-not $testProcess.WaitForExit(10000)) {
        $testProcess.Kill()
        $testProcess.WaitForExit()
        throw 'EarnStaff check timed out after 10 seconds'
    }
    $stdout = $stdoutRead.GetAwaiter().GetResult().Trim()
    $stderr = $stderrRead.GetAwaiter().GetResult().Trim()
    if ($testProcess.ExitCode -ne 0 -or $stderr -ne '' -or $stdout -notmatch '^PASS EarnStaff cases=\d+ \(no game input\)$') {
        throw "EarnStaff failed (exit=$($testProcess.ExitCode))`nstdout: $stdout`nstderr: $stderr"
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
    foreach ($fixtureFile in $fixtureFiles) { [IO.File]::Delete($fixtureFile) }
}
