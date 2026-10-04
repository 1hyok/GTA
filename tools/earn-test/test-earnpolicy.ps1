#Requires -Version 5.1
<#
Runs the production EarnPolicy.ahk in an isolated AHK interpreter.
No Main.ahk, game input, screen capture, window activation, or timer execution.
Run: powershell -NoProfile -ExecutionPolicy Bypass -File tools/earn-test/test-earnpolicy.ps1
#>
[CmdletBinding()]
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")

$ErrorActionPreference = 'Stop'
$policyPath = Join-Path $PSScriptRoot '..\..\Features\Earn\EarnPolicy.ahk'
$production = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8
if (-not (Test-Path -LiteralPath $AhkPath -PathType Leaf)) {
    throw "AutoHotkey executable not found: $AhkPath"
}
$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
OnError(PolicyRuntimeFailure)
PolicyRuntimeFailure(failure, *) {
    FileAppend("FAIL policy runtime: " failure.Message "`n", "**")
    ExitApp(1)
}
global assertions := 0

; Name, supply, stock, requested seconds, buy, bars, wait milliseconds, reason.
cases := [
    ["112 minute full", 1, 0, 6720, false, 4, 6720000, "wait_boundary"],
    ["112 minute half", 0.5, 0.4, 6720, false, 4, 2520000, "wait_boundary"],
    ["112 minute remaining one bar", 0.2, 0.4, 6720, true, 4, 0, "boundary"],
    ["112 minute observed after delivery", 0.99, 0.4, 6720, false, 4, 6636000, "wait_boundary"],
    ["explicit 140 minute full", 1, 0, 8400, false, 5, 8400000, "wait_boundary"],
    ["explicit 140 minute half", 0.5, 0.4, 8400, false, 5, 4200000, "wait_boundary"],
    ["explicit 140 minute does not buy one bar", 0.8, 0.4, 8400, false, 5, 6720000, "wait_boundary"],
    ["explicit 140 minute empty", 0, 0.4, 8400, true, 5, 0, "boundary"],
    ["explicit 140 minute nearly empty waits", 0.002, 0.4, 8400, false, 5, 16800, "wait_boundary"],
    ["one bar", 0.8, 0.4, 1680, true, 1, 0, "boundary"],
    ["two bars", 0.6, 0.4, 3360, true, 2, 0, "boundary"],
    ["three bars", 0.4, 0.4, 5040, true, 3, 0, "boundary"],
    ["four bars", 0.2, 0.4, 6720, true, 4, 0, "boundary"],
    ["five bars", 0, 0.4, 8400, true, 5, 0, "boundary"],
    ["one bar configured catches later two", 0.6, 0.4, 1680, true, 2, 0, "boundary"],
    ["one bar configured catches empty", 0, 0.4, 1680, true, 5, 0, "boundary"],
    ["two bars configured waits at one", 0.8, 0.4, 3360, false, 2, 1680000, "wait_boundary"],
    ["late poll 75", 0.75, 0.4, 1680, false, 2, 1260000, "wait_boundary"],
    ["late poll 55", 0.55, 0.4, 3360, false, 3, 1260000, "wait_boundary"],
    ["late poll 35", 0.35, 0.4, 5040, false, 4, 1260000, "wait_boundary"],
    ["late poll 15", 0.15, 0.4, 6720, false, 5, 1260000, "wait_boundary"],
    ["too early 81", 0.81, 0.4, 1680, false, 1, 84000, "wait_boundary"],
    ["missed one bar 79", 0.79, 0.4, 1680, false, 2, 1596000, "wait_boundary"],
    ["sub-boundary observation waits", 0.802, 0.4, 1680, false, 1, 16800, "wait_boundary"],
    ["small lag candidate", 0.798, 0.4, 1680, true, 1, 0, "boundary"],
    ["stock full", 0, 1, 8400, false, 0, 300000, "stock_full"],
    ["stock full safety threshold", 0, 0.97, 8400, false, 0, 300000, "stock_full"],
    ["invalid supply sentinel", -1, 0.4, 8400, false, 0, 300000, "invalid_read"],
    ["invalid stock sentinel", 0, -1, 8400, false, 0, 300000, "invalid_read"],
    ["invalid supply overfull", 1.001, 0.4, 8400, false, 0, 300000, "invalid_read"],
    ["invalid stock overfull", 0, 1.001, 8400, false, 0, 300000, "invalid_read"],
    ["invalid text read", "unknown", 0.4, 8400, false, 0, 300000, "invalid_read"],
    ["invalid empty read", "", 0.4, 8400, false, 0, 300000, "invalid_read"],
    ["invalid short interval", 0, 0.4, 300, false, 0, 300000, "invalid_interval"],
    ["invalid zero interval", 0, 0.4, 0, false, 0, 300000, "invalid_interval"],
    ["invalid twenty seven minutes", 0, 0.4, 1620, false, 0, 300000, "invalid_interval"],
    ["invalid thirty minutes", 0, 0.4, 1800, false, 0, 300000, "invalid_interval"],
    ["invalid fractional interval", 0, 0.4, 1680.5, false, 0, 300000, "invalid_interval"],
    ["invalid beyond full", 0, 0.4, 10080, false, 0, 300000, "invalid_interval"],
    ["invalid text interval", 0, 0.4, "unknown", false, 0, 300000, "invalid_interval"]
]
for c in cases {
    plan := EarnBunkerOrderPlan(c[2], c[3], c[4])
    Check(plan.buy = c[5] && plan.bars = c[6] && plan.waitMs = c[7] && plan.reason = c[8], c[1])
}
plan := EarnBunkerOrderPlan(0.8, 0.4)
Check(!plan.buy && plan.bars = 4, "omitted interval defaults to 112 minutes")
plan := EarnBunkerOrderPlan(0.21, 0.4)
Check(!plan.buy && plan.bars = 4 && plan.waitMs = 84000, "default waits one production tick before remaining 20 percent")
plan := EarnBunkerOrderPlan(0.19, 0.4)
Check(!plan.buy && plan.bars = 5, "missed final nonempty boundary does not silently allow rounded spending")

priceCases := [
    [15000, 1, true], [30000, 2, true], [45000, 3, true], [60000, 4, true], [75000, 5, true],
    [30000, 1, false], [45000, 2, false], [60000, 3, false], [75000, 4, false],
    [15001, 1, false], [14999, 1, false], [15000.1, 1, false],
    [0, 1, false], [-1, 1, false], ["", 1, false], ["$15,000", 1, false],
    [15000, 0, false], [90000, 6, false], [22500, 1.5, false], [15000, "unknown", false],
    ["15000", 1, true], [12000, 1, false]
]
for c in priceCases
    Check(EarnBunkerPriceAllowed(c[1], c[2]) = c[3], "price " A_Index)
plan := EarnBunkerOrderPlan(0.798, 0.4, 1680)
Check(plan.buy && !EarnBunkerPriceAllowed(30000, plan.bars), "rounded-up price blocks pixel-tolerant candidate")
plan := EarnBunkerOrderPlan(0.75, 0.4, 1680)
Check(!plan.buy && EarnBunkerPriceAllowed(30000, plan.bars), "valid price alone cannot authorize an intermediate fill")
plan := EarnBunkerOrderPlan(0.802, 0.4, 1680)
Check(!plan.buy && EarnBunkerPriceAllowed(15000, plan.bars), "matching price cannot authorize buying before the consumption boundary")
; The actual bar reader samples 130 positions. Every 20 percent is exactly 26 samples.
Loop 4 {
    requested := A_Index * 1680
    atSample := (130 - 26 * A_Index) / 130
    plan := EarnBunkerOrderPlan(atSample, 0.4, requested)
    Check(plan.buy && plan.bars = A_Index, "exact sampled boundary " A_Index)
    plan := EarnBunkerOrderPlan(atSample + 1 / 130, 0.4, requested)
    Check(!plan.buy && plan.bars = A_Index && plan.waitMs > 0, "one sample before boundary waits " A_Index)
    plan := EarnBunkerOrderPlan(atSample - 1 / 130, 0.4, requested)
    Check(!plan.buy && plan.bars = A_Index + 1 && plan.waitMs > 0, "one sample after boundary waits for next " A_Index)
}

RunWarehouseTests()
RunWarehouseTests() {
goods := WarehouseFixture()
moves := EarnWarehousePlan(goods)
Check(moves.Length = 2 && moves[1].technician = 1 && moves[1].from = "south_american"
    && moves[1].to = "organic" && moves[2].technician = 2 && moves[2].to = "printing", "three full sources move to two available targets")
Check(goods[1].technician = 1 && goods[6].technician = 0, "warehouse plan preserves its input")
ApplyMoves(goods, moves)
Check(EarnWarehousePlan(goods).Length = 0, "replay after applying moves does not duplicate assignments")
goods := WarehouseFixture()
goods[6].count := goods[6].capacity
goods[7].count := goods[7].capacity
Check(EarnWarehousePlan(goods).Length = 0, "no destinations keeps assignments")
goods := WarehouseFixture()
goods[6].unlocked := false
moves := EarnWarehousePlan(goods)
Check(moves.Length = 1 && moves[1].to = "printing", "locked destination is excluded")
goods := WarehouseFixture()
goods[5].technician := 0
goods[6].technician := 5
moves := EarnWarehousePlan(goods)
Check(moves.Length = 2 && moves[1].to = "sporting" && moves[2].to = "printing", "assigned organic excluded and higher value sporting selected")
goods := WarehouseFixture()
for row in goods
    row.count := 0
Check(EarnWarehousePlan(goods).Length = 0, "empty warehouse does not reorder producing staff")
goods := WarehouseFixture()
goods[1].count := 1
goods[2].count := 1
goods[3].count := 1
Check(EarnWarehousePlan(goods).Length = 0, "partly filled source keeps producing")
goods := WarehouseFixture()
for row in goods {
    row.capacity := 2
    row.count := row.technician >= 1 && row.technician <= 3 ? 2 : 0
}
Check(EarnWarehousePlan(goods).Length = 2, "small observed capacities need no floor count")
goods := WarehouseFixture()
goods[1].technician := 0
goods[1].count := 0
goods[2].technician := 0
goods[2].count := 0
goods[6].technician := 1
goods[6].count := goods[6].capacity
goods[7].technician := 2
goods[7].count := goods[7].capacity
moves := EarnWarehousePlan(goods)
Check(moves.Length = 2 && moves[1].to = "south_american" && moves[2].to = "pharmaceutical", "destination order starts with highest value goods")
goods := WarehouseFixture()
reversed := []
Loop goods.Length
    reversed.Push(goods[goods.Length - A_Index + 1])
moves := EarnWarehousePlan(reversed)
Check(moves.Length = 2 && moves[1].from = "south_american" && moves[1].to = "organic", "input row order does not change priority")
goods := WarehouseFixture()
for row in goods
    row.technician := 0
Check(EarnWarehousePlan(goods).Length = 0, "unassigned technicians are not fabricated as full sources")
; 판매로 남미가 비면 가장 싼 생산 중 품목(유기농)의 직원을 데려온다.
goods := [
    {id: "south_american", count: 0, capacity: 10, unlocked: true, technician: 0},
    {id: "pharmaceutical", count: 5, capacity: 20, unlocked: true, technician: 1},
    {id: "cash", count: 5, capacity: 40, unlocked: true, technician: 2},
    {id: "cargo", count: 5, capacity: 50, unlocked: true, technician: 3},
    {id: "sporting", count: 5, capacity: 100, unlocked: true, technician: 4},
    {id: "organic", count: 5, capacity: 80, unlocked: true, technician: 5},
    {id: "printing", count: 0, capacity: 60, unlocked: true, technician: 0}
]
moves := EarnWarehousePlan(goods)
Check(moves.Length = 1 && moves[1].technician = 5 && moves[1].from = "organic" && moves[1].to = "south_american",
    "sold high value goods pull the cheapest producing technician")
ApplyMoves(goods, moves)
Check(EarnWarehousePlan(goods).Length = 0, "top five producing goods are stable")
; 만재 직원이 먼저 쓰이고, 남는 비싼 빈자리에만 생산 중 직원을 옮긴다.
goods[1].count := 10
goods[2].count := 0, goods[2].technician := 0
goods[7].technician := 1
moves := EarnWarehousePlan(goods)
Check(moves.Length = 2 && moves[1].from = "south_american" && moves[1].to = "pharmaceutical"
    && moves[2].from = "printing" && moves[2].to = "organic", "full source first, then cheapest producer fills next value slot")
; 잠긴 비싼 품목은 목적지가 아니다.
goods := WarehouseFixture()
for row in goods
    row.count := 0
goods[1].technician := 0, goods[1].unlocked := false
goods[6].technician := 1
Check(EarnWarehousePlan(goods).Length = 0, "locked high value goods do not pull producers")
Check(EarnWarehouseMoveJustified("organic", "south_american", false) && !EarnWarehouseMoveJustified("south_american", "organic", false)
    && EarnWarehouseMoveJustified("south_american", "organic", true), "move justification follows value order unless source is full")
ExpectWarehouseInvalid([], "missing goods")
ExpectWarehouseInvalid(Map(), "non-array goods")
goods := WarehouseFixture()
goods[7].id := "organic"
ExpectWarehouseInvalid(goods, "duplicate good")
goods := WarehouseFixture()
goods[7].id := "unknown"
ExpectWarehouseInvalid(goods, "unknown good")
goods := WarehouseFixture()
goods[7].DeleteProp("capacity")
ExpectWarehouseInvalid(goods, "missing capacity")
goods := WarehouseFixture()
goods[7].count := -1
ExpectWarehouseInvalid(goods, "negative count")
goods := WarehouseFixture()
goods[7].count := goods[7].capacity + 1
ExpectWarehouseInvalid(goods, "overfull count")
goods := WarehouseFixture()
goods[7].capacity := 0
ExpectWarehouseInvalid(goods, "zero capacity")
goods := WarehouseFixture()
goods[7].count := 0.5
ExpectWarehouseInvalid(goods, "fractional count")
goods := WarehouseFixture()
goods[7].capacity := 10.5
ExpectWarehouseInvalid(goods, "fractional capacity")
goods := WarehouseFixture()
goods[7].unlocked := 2
ExpectWarehouseInvalid(goods, "invalid unlocked state")
goods := WarehouseFixture()
goods[7].technician := 1
ExpectWarehouseInvalid(goods, "duplicate technician")
goods := WarehouseFixture()
goods[7].technician := 6
ExpectWarehouseInvalid(goods, "out of range technician")
goods := WarehouseFixture()
goods[7].technician := 1.5
ExpectWarehouseInvalid(goods, "fractional technician")
goods := WarehouseFixture()
goods[7] := "unread"
ExpectWarehouseInvalid(goods, "non-object good")
}

FileAppend("PASS EarnPolicy cases=" assertions Chr(10), "*", "UTF-8")
ExitApp(0)
WarehouseFixture() {
    return [
        {id: "south_american", count: 10, capacity: 10, unlocked: true, technician: 1},
        {id: "pharmaceutical", count: 20, capacity: 20, unlocked: true, technician: 2},
        {id: "cash", count: 40, capacity: 40, unlocked: true, technician: 3},
        {id: "cargo", count: 10, capacity: 50, unlocked: true, technician: 4},
        {id: "sporting", count: 10, capacity: 50, unlocked: true, technician: 5},
        {id: "organic", count: 0, capacity: 80, unlocked: true, technician: 0},
        {id: "printing", count: 0, capacity: 80, unlocked: true, technician: 0}
    ]
}
ApplyMoves(goods, moves) {
    for move in moves {
        for row in goods {
            if (row.id = move.from)
                row.technician := 0
            if (row.id = move.to)
                row.technician := move.technician
        }
    }
}
ExpectWarehouseInvalid(goods, name) {
    rejected := false
    try EarnWarehousePlan(goods)
    catch ValueError
        rejected := true
    Check(rejected, name)
}
Check(ok, name) {
    global assertions
    assertions += 1
    if (!ok) {
        FileAppend("FAIL " name Chr(10), "*", "UTF-8")
        ExitApp(1)
    }
}
'@

$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $AhkPath
$testPath = Join-Path ([IO.Path]::GetTempPath()) ('gta-earn-policy-' + [Guid]::NewGuid().ToString('N') + '.ahk')
$info.Arguments = '/ErrorStdOut /CP65001 "' + $testPath + '"'
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
$info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
$testProcess = $null
try {
    # A temp file avoids Windows PowerShell's BOM behavior when writing to AHK stdin.
    [IO.File]::WriteAllText($testPath, $driver + "`n" + $production + "`n", (New-Object Text.UTF8Encoding($true)))
    $testProcess = [Diagnostics.Process]::Start($info)
    if (-not $testProcess.WaitForExit(10000)) {
        $testProcess.Kill()
        $testProcess.WaitForExit()
        throw 'EarnPolicy check timed out after 10 seconds'
    }
    $stdout = $testProcess.StandardOutput.ReadToEnd().Trim()
    $stderr = $testProcess.StandardError.ReadToEnd().Trim()
    if ($testProcess.ExitCode -ne 0 -or $stderr -ne '' -or $stdout -ne 'PASS EarnPolicy cases=107') {
        throw "EarnPolicy failed (exit=$($testProcess.ExitCode))`nstdout: $stdout`nstderr: $stderr"
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
