#Requires -Version 5.1
<#
Execute the real warehouse orchestration, stock parser and policy against a
stateful fake warehouse. Only the pixel sampler and external game APIs are
replaced. No desktop capture, game input or Main.ahk execution occurs.
#>
[CmdletBinding()]
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$production = Get-Content -LiteralPath (Join-Path $root 'Features\Earn\EarnWarehouse.ahk') -Raw -Encoding UTF8
$pixelPattern = '(?ms)^EarnWarehouseBrightLabel\([^\r\n]*\) \{.*?^\}'
if ([regex]::Matches($production, $pixelPattern).Count -ne 1) { throw 'Expected one production pixel sampler.' }
$production = [regex]::Replace($production, $pixelPattern, '')
$dialogPattern = '(?ms)^EarnWarehouseDialogClick\([^
]*\) \{.*?^\}'
if ([regex]::Matches($production, $dialogPattern).Count -ne 1) { throw 'Expected one production dialog click.' }
$production = [regex]::Replace($production, $dialogPattern, '')
$production += "`n" + (Get-Content -LiteralPath (Join-Path $root 'Features\Earn\EarnPolicy.ahk') -Raw -Encoding UTF8)
$production += "`n" + (Get-Content -LiteralPath (Join-Path $root 'Features\Earn\EarnWarehouseRead.ahk') -Raw -Encoding UTF8)
$fixture = Join-Path $PSScriptRoot 'test-earnwarehouse-read-fixtures\stock.tsv'
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
global whTests := 0, whMode, whState, whAssigned, whCounts, whActive, whSelected,
    whSelections, whAttempts, whMoves, whBegins, whEnds, whError, whHistory,
    whPending := "", whCancels := 0, whTooltips := 0
try {
    RunWarehouseTests()
    RunScheduleTests()
    FileAppend("PASS EarnWarehouse cases=" whTests " (no game input)`n", "*")
    ExitApp(0)
} catch as testFailure {
    FileAppend("FAIL EarnWarehouse: " testFailure.Message "`n", "**")
    ExitApp(1)
}

RunWarehouseTests() {
    global whAssigned, whCounts, whActive, whAttempts, whMoves, whBegins, whEnds, whSelections, whState, whHistory, whTooltips, whCancels
    scenarios := [
        ["normal",true,1], ["two_moves",true,2], ["no_full",true,1],
        ["no_available",true,0], ["idle_staff",false,0], ["stock_noocr",false,0],
        ["labels_noocr",false,0], ["source_changed",false,0],
        ["target_inactive",false,0], ["move_noocr",false,0],
        ["move_noresult",false,1], ["move_rejected",false,1],
        ["missing_staff",false,0], ["ambiguous_identity",false,0],
        ["end_rejected",false,1], ["begin_rejected",false,0],
        ["full_staff",true,1], ["full_missing",false,0], ["full_ambiguous",false,0],
        ["dialog_missing",false,1], ["stock_none_full",true,0], ["stock_all_full",true,0]
    ]
    for scenario in scenarios {
        ResetWarehouse(scenario[1])
        actual := EarnWarehouseTask()
        Check(actual = scenario[2] && whAttempts = scenario[3], scenario[1] " result=" actual " attempts=" whAttempts)
        Check(whBegins = 1 && whEnds = (scenario[1] = "begin_rejected" ? 0 : 1), scenario[1] " MCT lifetime")
        Check(whAssigned[3] = (scenario[1] = "idle_staff" ? "" : scenario[1] = "full_staff" ? "pharmaceutical" : "organic")
            && whAssigned[4] = (scenario[1] = "no_full" ? "pharmaceutical" : "printing") && whAssigned[5] = "cash", scenario[1] " producing and idle staff preserved")
        Check(whAttempts <= 2, scenario[1] " no repeated assignment requests")
        if (scenario[1] = "stock_none_full" || scenario[1] = "stock_all_full")
            Check(whSelections = 0 && whState = "mct", scenario[1] " decides from Sell Goods stock without opening staff management")
        if (scenario[1] = "no_full")
            Check(whMoves = 1 && whHistory[1] = "printing:pharmaceutical" && whState = "mct",
                "cheapest producing technician moves to empty higher value Pharmaceutical")
        if (scenario[1] = "normal")
            Check(whAssigned[1] = "pharmaceutical" && whMoves = 1 && whState = "mct", "full source moves once then reobserves")
        if (scenario[1] = "two_moves")
            Check(whHistory.Length = 2 && whHistory[1] = "cargo:south_american"
                && whHistory[2] = "sporting:pharmaceutical", "each move recomputes after changed screen")
        if (scenario[1] = "full_staff")
            Check(whMoves = 1 && whHistory[1] = "organic:pharmaceutical" && whState = "mct",
                "observed full gray technician 3 moves only from Organic 80/80 to Pharmaceutical 16/20")
        if (scenario[1] = "move_noresult" || scenario[1] = "move_rejected")
            Check(whAssigned[1] = "cargo" && whAttempts = 1, scenario[1] " never retries unconfirmed click")
        if (scenario[1] = "move_noresult")
            Check(whCancels = 1 && whState = "warehouse", "unconfirmed assignment dialog is cancelled once before cleanup")
    }

    ; Three or more full goods: notify once per change and keep it for the overlay.
    global gEarnSellNotice := ""
    three := [{id:"south_american",count:10,capacity:10}, {id:"organic",count:80,capacity:80},
        {id:"cash",count:40,capacity:40}, {id:"cargo",count:31,capacity:50}]
    two := [{id:"south_american",count:10,capacity:10}, {id:"organic",count:80,capacity:80},
        {id:"cash",count:39,capacity:40}]
    whTooltips := 0
    Check(EarnWarehouseSellNotice(three) = 3 && InStr(gEarnSellNotice, "판매 필요") && whTooltips = 1,
        "three full goods raise a sell notice")
    Check(EarnWarehouseSellNotice(three) = 3 && whTooltips = 1, "unchanged sell notice is not repeated")
    Check(EarnWarehouseSellNotice(two) = 2 && gEarnSellNotice = "", "two full goods clear the sell notice")
    Check(EarnWarehouseSellNotice(three) = 3 && whTooltips = 2, "notice returns after goods fill again")

    ; A native click/pixel exception must still leave the shared MCT lifetime.
    ; Error handling inside the real MCT End is covered in test-earntasks.ps1.
    for mode in ["entry_throw", "assignment_throw"] {
        ResetWarehouse(mode)
        caught := ""
        try EarnWarehouseTask()
        catch as e
            caught := e.Message
        Check(caught = "warehouse native exception", mode " original exception retained")
        Check(whBegins = 1 && whEnds = 1, mode " MCT cleanup called once")
        Check(whAttempts = (mode = "entry_throw" ? 0 : 1) && whMoves = 0,
            mode " failed request is not sent again")
    }

    ; A scheduler batch owns the already-open MCT session. The same real body
    ; must run, return failures and propagate exceptions without acquiring or
    ; closing that session, even when either standalone lifetime hook rejects.
    for scenario in [["normal",true,1,""], ["stock_noocr",false,0,""],
        ["begin_rejected",true,1,""], ["end_rejected",true,1,""],
        ["entry_throw",false,0,"warehouse native exception"],
        ["assignment_throw",false,1,"warehouse native exception"]] {
        ResetWarehouse(scenario[1])
        actual := false, caught := ""
        try actual := EarnWarehouseTask(false)
        catch as e
            caught := e.Message
        Check(actual = scenario[2] && caught = scenario[4], "batch " scenario[1] " body result or exception preserved")
        Check(whBegins = 0 && whEnds = 0, "batch " scenario[1] " leaves MCT lifetime to its caller")
        Check(whAttempts = scenario[3] && (!actual || whState = "mct"),
            "batch " scenario[1] " executes the body once and returns successful work to MCT")
    }

    ResetWarehouse("normal")
    Check(!EarnWarehouseAvailable("pharmaceutical", false), "false OCR does not throw or authorize")
    Check(!EarnWarehouseAvailable("unknown", []), "unknown target does not throw or authorize")
    Check(!EarnWarehouseAvailable("pharmaceutical", []), "empty OCR does not authorize")
    labels := ManagementLines()
    Check(EarnWarehouseAvailable("pharmaceutical", labels), "observed two-line long label is accepted")
    Check(!EarnWarehouseAvailable("cargo", labels), "inactive assigned label is rejected")
    for label in labels {
        if (label.id = "pharmaceutical")
            label.bright := false
    }
    Check(!EarnWarehouseAvailable("pharmaceutical", labels), "dark target labels are rejected")
    ResetWarehouse("normal")
    labels := ManagementLines()
    labels.Push(LabelLine("Pharmaceutical", 828, 674, 170, 23, "pharmaceutical"))
    Check(!EarnWarehouseAvailable("pharmaceutical", labels), "duplicate label is not a valid target")
    ResetWarehouse("normal")
    labels := ManagementLines()
    for label in labels {
        if (label.id = "pharmaceutical" && label.text = "Research")
            label.text := "Research t"
    }
    Check(!EarnWarehouseAvailable("pharmaceutical", labels), "icon merged into label is rejected")
    ResetWarehouse("normal")
    invalidMove := {from:"pharmaceutical",to:"cargo",technician:1}
    goods := [
        {id:"pharmaceutical",count:16,capacity:20,technician:1,unlocked:1},
        {id:"cargo",count:30,capacity:50,technician:0,unlocked:1}
    ]
    Check(!EarnWarehouseMove(invalidMove, goods) && whAttempts = 0 && whSelections = 0, "producing source cannot move to cheaper goods")
    goods[1].count := 20, goods[2].technician := 2
    Check(!EarnWarehouseMove(invalidMove, goods) && whAttempts = 0 && whSelections = 0, "occupied target cannot be overwritten")
    goods[2].technician := 0, goods[2].count := 50
    Check(!EarnWarehouseMove(invalidMove, goods) && whAttempts = 0 && whSelections = 0, "full target cannot be assigned")
}

ResetWarehouse(mode) {
    global whMode, whState, whAssigned, whCounts, whActive, whSelected, whSelections,
        whAttempts, whMoves, whBegins, whEnds, whError, whHistory, whPending, whCancels
    whMode := mode, whState := "mct", whAssigned := ["cargo","sporting","organic","printing","cash"]
    whCounts := Map("cargo",50,"sporting",51,"south_american",10,"pharmaceutical",16,"organic",70,"printing",44,"cash",29)
    whActive := Map("cargo",true,"sporting",true,"south_american",true,"pharmaceutical",true,"organic",true,"printing",true,"cash",true)
    if (mode = "no_full")
        whCounts["cargo"] := 29
    if (mode = "no_available")
        whActive["pharmaceutical"] := false
    if (mode = "idle_staff")
        whAssigned[3] := ""
    if (mode = "two_moves")
        whCounts["sporting"] := 100, whCounts["south_american"] := 5
    if (mode = "stock_none_full")
        whCounts["cargo"] := 29, whCounts["south_american"] := 9
    if (mode = "stock_all_full")
        whCounts := Map("cargo",50,"sporting",100,"south_american",10,"pharmaceutical",20,"organic",80,"printing",60,"cash",40)
    if (InStr(mode,"full_") = 1) {
        ; 2026-10-03 actual stock when the selected Organic person turned gray.
        whCounts["cargo"] := 31, whCounts["sporting"] := 56, whCounts["organic"] := 80,
            whCounts["printing"] := 58, whCounts["cash"] := 36
    }
    ; 직원 화면을 이미 읽은 뒤 재고 변화가 없는 상황. 그 밖에는 처음 보는 상태로 시작한다.
    EarnWarehouseNeedStaff("reset")
    if (mode = "stock_none_full") {
        caps := Map("cargo",50,"sporting",100,"south_american",10,"pharmaceutical",20,"organic",80,"printing",60,"cash",40)
        seen := []
        for id, count in whCounts
            seen.Push({id: id, count: count, capacity: caps[id]})
        EarnWarehouseNeedStaff(seen, true)
    }
    whSelected := 0, whSelections := 0, whAttempts := 0, whMoves := 0,
        whBegins := 0, whEnds := 0, whError := "", whHistory := [], whPending := "", whCancels := 0
}

EarnTaskMCTBegin() {
    global whBegins, whMode
    whBegins++
    return whMode != "begin_rejected"
}
EarnTaskMCTEnd() {
    global whEnds, whMode
    whEnds++
    return whMode != "end_rejected"
}
EarnUIClick(name, x, y, *) {
    global whState, whSelected, whSelections, whAttempts, whMoves, whAssigned, whMode, whHistory, whPending
    if (name = "mct_nightclub_card") {
        if (whMode = "entry_throw")
            throw Error("warehouse native exception")
        whState := "club"
        return true
    }
    if (name = "nc_dj_menu") {
        if (x != 500 || (y != 920 && y != 840 && y != 596))
            throw Error("Unexpected navigation click")
        whState := y = 920 ? "stock" : y = 840 ? "warehouse" : "home"
        return true
    }
    if (name != "warehouse_title" || whState != "warehouse")
        throw Error("Unexpected warehouse click")
    if (y = 300) {
        technician := Round((x-808)/179)+1
        if (technician < 1 || technician > 5)
            throw Error("Attempted a hire or invalid technician")
        whSelected := technician, whSelections++
        return true
    }
    destination := ""
    for id, tile in EarnWarehouseTiles()
        if (x = tile[1]+120 && y = tile[2]+38)
            destination := id
    if (destination = "")
        throw Error("Unexpected reassignment coordinate")
    whAttempts++
    if (whMode = "assignment_throw")
        throw Error("warehouse native exception")
    if (whMode = "move_rejected")
        return false
    ; The real UI asks for confirmation before changing the assignment.
    if (whMode != "dialog_missing")
        whState := "dialog", whPending := destination
    return true
}
EarnWarehouseDialogClick(x, y) {
    global whState, whPending, whSelected, whAssigned, whMoves, whHistory, whMode, whCancels
    if (whState != "dialog" || y != 612 || (x != 1160 && x != 756))
        throw Error("Unexpected dialog click")
    if (x = 756) {
        whState := "warehouse", whCancels++
        return true
    }
    if (whMode = "move_noresult")
        return true
    whHistory.Push(whAssigned[whSelected] ":" whPending)
    whAssigned[whSelected] := whPending, whMoves++, whState := "warehouse"
    return true
}
ShowTooltip(*) {
    global whTooltips
    whTooltips++
}
EarnUIReady(name, *) {
    global whState
    return name = "warehouse_title" && whState = "warehouse"
}
EarnWaitSeen(name, *) {
    global whState
    return (name = "nc_dj_menu" && whState = "club") || (name = "warehouse_title" && whState = "warehouse")
}
EarnSeen(name, area, *) {
    global whMode, whSelected, whAssigned, whSelections
    if (InStr(name, "warehouse_staff_") = 1)
        return whMode != "missing_staff" || name != "warehouse_staff_3"
    if (name != "warehouse_person_foot" && name != "warehouse_person_full_foot")
        throw Error("Unexpected template " name)
    requestedId := ""
    for id, tile in EarnWarehouseTiles()
        if (Abs(area[1]*1920-(tile[1]+230)) < 0.1 && Abs(area[2]*1080-(tile[2]+43)) < 0.1)
            requestedId := id
    if (requestedId = "")
        throw Error("Unexpected identity scan area")
    if (whMode = "ambiguous_identity" && whSelected = 1)
        return requestedId = "cargo" || requestedId = "pharmaceutical"
    identity := whMode = "source_changed" && whSelections > 5 ? "cash" : whAssigned[whSelected]
    if (name = "warehouse_person_full_foot") {
        if (whMode = "full_ambiguous" && whSelected = 3)
            return requestedId = "organic" || requestedId = "south_american"
        return whMode = "full_staff" && identity = "organic" && requestedId = identity
    }
    if (InStr(whMode,"full_") = 1 && identity = "organic")
        return false
    return requestedId = identity
}
EarnReadScreen(area) {
    global whMode, whCounts, whSelections
    if (area[2] = 130) {
        if (whMode = "stock_noocr")
            return false
        rows := []
        replacement := Map("29/50",["cargo",50],"51/100",["sporting",100],"10/10",["south_american",10],
            "16/20",["pharmaceutical",20],"70/80",["organic",80],"44/60",["printing",60],"29/40",["cash",40])
        for rawLine in StrSplit(FileRead(A_Args[1], "UTF-8"), "`n", "`r") {
            if (rawLine = "" || rawLine = "x`ty`tw`th`ttext")
                continue
            columns := StrSplit(rawLine, "`t")
            text := columns[5]
            if (replacement.Has(text)) {
                value := replacement[text]
                text := whCounts[value[1]] "/" value[2]
            }
            rows.Push({x:Integer(columns[1]),y:Integer(columns[2]),w:Integer(columns[3]),h:Integer(columns[4]),text:text})
        }
        return rows
    }
    if (area[2] = 420) {
        global whState
        return whState = "dialog" ? [{text:"Assign Technician"},
            {text:"Are you sure you'd like to assign this technician to accrue Meth?"}] : []
    }
    if (area[2] != 548)
        throw Error("Unexpected OCR area")
    if (whMode = "labels_noocr" || (whMode = "move_noocr" && whSelections > 5))
        return false
    return ManagementLines()
}
ManagementLines() {
    return [LabelLine("Cargo and",799,584,117,27,"cargo"), LabelLine("Shipments",799,608,117,24,"cargo"),
        LabelLine("Pharmaceutical",828,674,170,23,"pharmaceutical"), LabelLine("Research",795,698,103,21,"pharmaceutical"),
        LabelLine("Cash Creation",823,780,157,21,"cash"), LabelLine("Sporting Goods",1125,590,174,27,"sporting"),
        LabelLine("Organic Produce",1134,682,187,27,"organic"), LabelLine("South American",1421,570,174,20,"south_american"),
        LabelLine("Imports",1377,597,82,23,"south_american"), LabelLine("Printing & Copying",1440,676,204,26,"printing")]
}
LabelLine(text,x,y,w,h,id) {
    global whAssigned, whActive, whMode, whSelections
    bright := whActive[id]
    for assignedId in whAssigned
        if (assignedId = id)
            bright := false
    if (whMode = "target_inactive" && whSelections > 5 && id = "pharmaceutical")
        bright := false
    return {text:text,x:x,y:y,w:w,h:h,id:id,bright:bright}
}
EarnWarehouseBrightLabel(row) {
    return row.bright
}
EarnSleep(*) {
    global whAttempts, whMode
    return !(whAttempts && whMode = "move_noresult")
}
EarnUIBackToMCT(*) {
    global whState
    whState := "mct"
    return true
}
EarnFail(reason) {
    global whError
    whError := reason
    return false
}
EarnScheduleNext(*) => true
global whStore
EarnStateGet(key, default := "") {
    global whStore
    return IsSet(whStore) && whStore.Has(key) ? whStore[key] : default
}
EarnStateSet(key, value) {
    global whStore
    if (!IsSet(whStore))
        whStore := Map()
    whStore[key] := value
}
RunScheduleTests() {
    global whStore
    base := 10000000, m := 60000
    for cap in [50, 13] {
        whStore := Map()
        EarnWarehouseTrack("reset")
        t := 0
        while (t <= 160) {
            EarnWarehouseTrack([{id: "cargo", count: 10 + t // 70, capacity: cap}, {id: "cash", count: 0, capacity: 20}], base + t*m)
            if (t = 140)
                Check(EarnWarehouseTrack(, base + t*m) = 0, "schedule: unknown goods under 150 min use default interval (cap " cap ")")
            t += 10
        }
        ms := EarnWarehouseTrack(, base + 160*m)
        Check(ms = (cap = 50 ? 240*m : 40*m), "schedule: measured 70 min/unit predicts fill (cap " cap ", got " ms ")")
    }
    Check(whStore.Get("wh_rate_cargo", 0) = 70*m, "schedule: measured rate is saved for the next restart")
    ; 재시작: 메모리는 비고 저장된 속도만 남는다. 직원 없는 cash 를 150분 기다리지 않는다.
    EarnWarehouseTrack("reset")
    EarnWarehouseTrack([{id: "cargo", count: 47, capacity: 50}, {id: "cash", count: 0, capacity: 20}], base)
    Check(EarnWarehouseTrack(, base) = 140*m, "schedule: saved rate predicts fill right after restart, one unit early")
    Check(EarnWarehouseTrack(, base + 161*m) = 0, "schedule: saved-rate good that never rose is treated as unstaffed")
    EarnWarehouseTrack("reset")
    EarnWarehouseTrack([{id: "cargo", count: 10, capacity: 50}, {id: "cash", count: 0, capacity: 20}], base)
    Check(EarnWarehouseTrack(, base) = 240*m, "schedule: restart with saved rate caps the wait at four hours")
    whStore := Map()
    EarnWarehouseTrack("reset")
    EarnWarehouseTrack([{id: "cargo", count: 49, capacity: 50}], base)
    EarnWarehouseTrack([{id: "cargo", count: 50, capacity: 50}], base + 10*m)
    Check(EarnWarehouseTrack(, base + 20*m) = 0, "schedule: rising good without a rate uses default interval")
}EarnLog(*) {
}
Check(condition, description) {
    global whTests, whError
    if (!condition)
        throw Error(description " detail=" whError)
    whTests++
}
'@
$testFile = Join-Path ([IO.Path]::GetTempPath()) ('gta-warehouse-flow-test-' + [Guid]::NewGuid().ToString('N') + '.ahk')
[IO.File]::WriteAllText($testFile, $driver + "`n" + $production, (New-Object Text.UTF8Encoding($true)))
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $AhkPath
$info.Arguments = '/ErrorStdOut /CP65001 "' + $testFile + '" "' + $fixture + '"'
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
$info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
$process = [Diagnostics.Process]::Start($info)
try {
    if (-not $process.WaitForExit(10000)) {
        $process.Kill()
        $process.WaitForExit()
        throw 'Warehouse flow test timed out.'
    }
    $stdout = $process.StandardOutput.ReadToEnd().Trim()
    $stderr = $process.StandardError.ReadToEnd().Trim()
    if ($process.ExitCode -ne 0 -or $stderr -ne '' -or $stdout -ne 'PASS EarnWarehouse cases=145 (no game input)') {
        throw "Warehouse flow failed (exit=$($process.ExitCode))`nstdout: $stdout`nstderr: $stderr"
    }
    Write-Output $stdout
}
finally {
    if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    $process.Dispose()
    if ([IO.File]::Exists($testFile)) { [IO.File]::Delete($testFile) }
}
