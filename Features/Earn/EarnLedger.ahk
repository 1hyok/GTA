; Confirmed automation cash movements. This is not a whole-game wallet ledger:
; user-initiated warehouse sales are outside the automation's observation path.
EarnLedgerRecord(direction, amount, transaction, source, evidence, path := "") {
    if (direction != "income" && direction != "expense") {
        EarnLog("원장: 알 수 없는 거래 방향 " direction)
        return false
    }
    if (!IsNumber(amount) || amount <= 0 || Mod(amount, 1) != 0) {
        EarnLog("원장: 금액이 정수가 아니거나 0 이하라 기록하지 않음 (" amount ")")
        return false
    }
    if (path = "")
        path := A_Temp "\gta-earn-ledger.tsv"

    delta := direction = "income" ? Round(amount) : -Round(amount)
    epoch := EarnUnixNow()
    row := epoch "`t" FormatTime(, "yyyy-MM-dd HH:mm:ss") "`t" delta "`t" direction "`t"
        . EarnLedgerClean(transaction) "`t" EarnLedgerClean(source) "`t" EarnLedgerClean(evidence) "`n"
    try {
        if (!FileExist(path))
            FileAppend("unix_epoch`tlocal_time`tcash_delta`tdirection`ttransaction`tsource`tevidence`n", path, "UTF-8-RAW")
        FileAppend(row, path, "UTF-8-RAW")
    } catch as e {
        EarnLog("원장: " path " 저장 실패 (" e.Message ")")
        return false
    }

    EarnLog("원장: " transaction " " EarnLedgerMoney(delta) " (" EarnLedgerClean(source) "; " EarnLedgerClean(evidence) ")")
    totals := EarnLedgerSummary(3600, path)
    if (!totals.available) {
        EarnLog("원장: 최근 60분 집계 읽기 실패")
        return true
    }
    EarnLog("최근 60분 자동화 현금흐름: 수입 +$" EarnLedgerThousands(totals.income)
        . ", 지출 -$" EarnLedgerThousands(totals.expense)
        . ", 순액 " EarnLedgerMoney(totals.net) " (" totals.count "건, 제외 " totals.invalid "행, 수동 창고 판매 미포함)")
    return true
}

EarnLedgerSummary(windowSeconds := 3600, path := "") {
    totals := {income: 0, expense: 0, net: 0, count: 0, invalid: 0, available: false}
    if (!IsNumber(windowSeconds) || windowSeconds <= 0)
        return totals
    if (path = "")
        path := A_Temp "\gta-earn-ledger.tsv"
    if (!FileExist(path)) {
        totals.available := true
        return totals
    }
    try text := FileRead(path, "UTF-8")
    catch {
        return totals
    }

    totals.available := true
    now := EarnUnixNow(), earliest := now - windowSeconds
    for line in StrSplit(text, "`n", "`r") {
        if (line = "" || InStr(line, "unix_epoch`t") = 1)
            continue
        fields := StrSplit(line, "`t")
        if (fields.Length != 7 || !IsNumber(fields[1]) || !IsNumber(fields[3])) {
            totals.invalid += 1
            continue
        }
        epoch := Number(fields[1]), delta := Number(fields[3])
        if (epoch < earliest || epoch > now)
            continue
        if (delta = 0 || Mod(delta, 1) != 0) {
            totals.invalid += 1
            continue
        }
        if ((fields[4] = "income" && delta < 0) || (fields[4] = "expense" && delta > 0)) {
            totals.invalid += 1
            continue
        }
        if (fields[4] != "income" && fields[4] != "expense") {
            totals.invalid += 1
            continue
        }
        totals.net += delta
        totals.count += 1
        if (delta > 0)
            totals.income += delta
        else
            totals.expense -= delta
    }
    return totals
}

EarnLedgerClean(value) {
    value := StrReplace(value, "`t", " ")
    value := StrReplace(value, "`r", " ")
    value := StrReplace(value, "`n", " ")
    return Trim(value)
}

EarnLedgerThousands(value) {
    value := Format("{:d}", Round(Abs(value)))
    grouped := ""
    while (StrLen(value) > 3) {
        grouped := "," SubStr(value, -3) grouped
        value := SubStr(value, 1, StrLen(value) - 3)
    }
    return value grouped
}

EarnLedgerMoney(delta) {
    sign := delta < 0 ? "-$" : delta > 0 ? "+$" : "$"
    return sign EarnLedgerThousands(delta)
}
