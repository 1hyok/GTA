#Requires -Version 5.1
<#
Exercises the production ledger writer and confirmation wrapper with a temporary file.
No game input, screen reads, window activation, or Main.ahk execution.
#>
[CmdletBinding()]
param([string]$AhkPath = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $AhkPath -PathType Leaf)) {
    throw "AutoHotkey executable not found: $AhkPath"
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$corePath = Join-Path $root 'Features\Earn\EarnCore.ahk'
$ledgerPath = Join-Path $root 'Features\Earn\EarnLedger.ahk'
$coreText = Get-Content -LiteralPath $corePath -Raw -Encoding UTF8
$ledgerFunctionNames = @('EarnTransactionConfirmed', 'EarnTransactionCashConfirmed')
$coreFunctions = foreach ($name in $ledgerFunctionNames) {
    $match = [regex]::Match($coreText, ('(?ms)^' + [regex]::Escape($name) + '\([^\r\n]*\) \{.*?^\}'))
    if (-not $match.Success) { throw "Missing production function: $name" }
    $match.Value
}
$cashCallers = @('Features\Earn\EarnVinewood.ahk', 'Features\Earn\EarnTasks.ahk', 'Features\Earn\EarnStaff.ahk')
$cashCallCount = 0
$guardedCashCallCount = 0
foreach ($relativePath in $cashCallers) {
    $source = Get-Content -LiteralPath (Join-Path $root $relativePath) -Raw -Encoding UTF8
    $cashCallCount += [regex]::Matches($source, 'EarnTransactionCashConfirmed\(').Count
    $guardedCashCallCount += [regex]::Matches($source, '(?m)^\s*if\s*\(!EarnTransactionCashConfirmed\(').Count
}
if ($cashCallCount -ne 5 -or $guardedCashCallCount -ne $cashCallCount) {
    throw "All five production cash confirmations must stop when the ledger rejects a row (calls=$cashCallCount guarded=$guardedCashCallCount)."
}

$driver = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
#Include "__LEDGER_PATH__"

global ledgerNow := 100000, ledgerState := Map(), ledgerLogs := [], ledgerChecks := 0
EarnUnixNow() {
    global ledgerNow
    return ledgerNow
}
EarnStateGet(key, default := "") {
    global ledgerState
    return ledgerState.Get(key, default)
}
EarnStateSet(key, value) {
    global ledgerState
    ledgerState[key] := value
}
EarnLog(message) {
    global ledgerLogs
    ledgerLogs.Push(message)
}
__CORE_FUNCTIONS__

LedgerCheck(condition, label) {
    global ledgerChecks
    ledgerChecks += 1
    if (!condition)
        throw Error("FAIL " label)
}

path := A_Temp "\gta-earn-ledger-test-" DllCall("GetCurrentProcessId") "-" A_TickCount ".tsv"
try {
    ledgerState["pending_safe"] := "Nightclub $250,000 claim pending"
    LedgerCheck(EarnTransactionCashConfirmed("safe", "income", 250000, "Nightclub", "empty safe", path), "confirmed safe claim recorded")
    LedgerCheck(ledgerState.Get("pending_safe", "") = "", "confirmed transaction clears pending")

    ledgerNow := 100100
    ledgerState["pending_bunker"] := "Bunker $75,000 purchase pending"
    LedgerCheck(EarnTransactionCashConfirmed("bunker", "expense", 75000, "Bunker", "delivery pending", path), "confirmed bunker purchase recorded")

    ledgerNow := 90000
    LedgerCheck(EarnLedgerRecord("income", 300, "staff", "source`twith tab", "evidence`nline", path), "older row with delimited text recorded")
    FileAppend("broken row`tmissing fields`n", path, "UTF-8-RAW")
    ledgerNow := 100100
    summaryResult := EarnLedgerSummary(3600, path)
    LedgerCheck(summaryResult.available, "summary file read")
    LedgerCheck(summaryResult.count = 2 && summaryResult.income = 250000 && summaryResult.expense = 75000 && summaryResult.net = 175000, "rolling window and signed totals")
    LedgerCheck(summaryResult.invalid = 1, "malformed row reported")

    foundCleanRow := false
    for testLine in StrSplit(FileRead(path, "UTF-8"), "`n", "`r") {
        testFields := StrSplit(testLine, "`t")
        if (testFields.Length = 7 && testFields[5] = "staff" && testFields[6] = "source with tab" && testFields[7] = "evidence line")
            foundCleanRow := true
    }
    LedgerCheck(foundCleanRow, "ledger delimiters are escaped into a single row")
    LedgerCheck(EarnLedgerMoney(1234567) = "+$1,234,567" && EarnLedgerMoney(-5000) = "-$5,000", "signed currency formatting")

    before := FileRead(path, "UTF-8")
    LedgerCheck(!EarnTransactionCashConfirmed("staff", "expense", 7500, "Hangar", "no pending", path), "unstarted transaction is rejected")
    LedgerCheck(FileRead(path, "UTF-8") = before, "unstarted transaction adds no ledger row")
    LedgerCheck(ledgerState.Get("pending_staff", "") != "", "missing pending state is persisted as a hold")

    failurePath := A_Temp "\gta-earn-ledger-dir-" DllCall("GetCurrentProcessId") "-" A_TickCount
    DirCreate(failurePath)
    ledgerState["pending_failed"] := "purchase result confirmed, ledger write pending"
    LedgerCheck(!EarnTransactionCashConfirmed("failed", "expense", 7500, "Hangar", "delivery pending", failurePath), "ledger write failure is reported")
    LedgerCheck(ledgerState.Get("pending_failed", "") != "", "ledger write failure preserves pending hold")
    DirDelete(failurePath)
    FileAppend("PASS test-earnledger checks=" ledgerChecks "`n", "*")
} finally {
    if (FileExist(path))
        FileDelete(path)
}
ExitApp(0)
'@
$driver = $driver.Replace('__LEDGER_PATH__', $ledgerPath).Replace('__CORE_FUNCTIONS__', ($coreFunctions -join "`r`n`r`n"))
$scriptPath = Join-Path ([IO.Path]::GetTempPath()) ('test-earnledger-' + [Guid]::NewGuid().ToString('N') + '.ahk')
try {
    [IO.File]::WriteAllText($scriptPath, $driver, [Text.UTF8Encoding]::new($true))
    $output = (& $AhkPath /ErrorStdOut $scriptPath 2>&1 | Out-String).Trim()
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -or $output -notmatch '^PASS test-earnledger checks=\d+$') {
        throw "AutoHotkey ledger checks failed (exit=$exitCode): $output"
    }
    Write-Output $output
} finally {
    if (Test-Path -LiteralPath $scriptPath) { Remove-Item -LiteralPath $scriptPath -Force }
}
