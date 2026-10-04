; 바인우드 앱의 모든 사업장 금고를 확인한다. 사업장에 걷거나 재접속하지 않는다.
; 금고마다 한도와 게임 하루(48분) 최대 입금이 다르다. 다음 입금이 한도를 넘길 수 있는 금고만 수거한다.
; 값은 1004 조사(timesaver.gg 등 공략 정리). 출처마다 다르거나 업그레이드로 바뀌는 값은 일찍 수거하는 쪽으로 잡았다.
EarnSafeLimits() {
    static limits := Map(
        "Nightclub", [250000, 50000],         ; 1003 실측: 17:38 $195,000 → 18:12 $245,000
        "Arcade", [100000, 5000],
        "Agency", [250000, 20000],
        "Salvage Yard", [100000, 24000],      ; 벽 금고 업그레이드가 있으면 한도 $250,000. 확인 전이라 작게
        "Bail Office", [100000, 20000],       ; 요원 둘이 각각 최대 $10,000 (앱 직원 파견이 보낸다)
        "Garment Factory", [100000, 2500])   ; 1004 실측: 06:51 $49,750 → 11:34 $61,150, 48분당 약 $2,400
    return limits
}

; 쓰지 않는 사업장. 목록에 있어도 읽기만 건너뛰고 수거·다음 확인 계산에서 뺀다.
; 세차장은 활성화하지 않는다(1004 사용자 결정). 금고가 $0 으로 남는다.
EarnSafeIgnored() {
    static ignored := Map("Hands On Car Wash", true)
    return ignored
}

EarnVinewoodSafeTask() {
    safes := EarnSafeLimits()
    if (!EarnVinewoodOpen())
        return false
    lines := EarnReadScreen([25,15,450,850])
    if (!IsObject(lines) || !EarnFindText(lines, "i)^THE VINEWOOD CLUB APP$"))
        return false
    if (EarnFindText(lines, "i)^No earnings to claim\.?$")) {
        EarnLog("금고: 바인우드 앱에 수거할 수익 없음")
        EarnVinewoodSafeScheduleAll(Map())
        return EarnVinewoodClose()
    }
    ; 앱 메인과 수익 하위 목록은 제목이 같다. 이미 하위 목록이면 다시 Enter를 보내지 않는다.
    if (EarnFindText(lines, "i)^Claim Business Earnings$")) {
        row := EarnSelectText("i)^Claim Business Earnings$", "i)^THE VINEWOOD CLUB APP$", 6)
        if (!row || !EarnPress("Enter") || !EarnSleep(700))
            return EarnFail("금고: 수익 목록 진입 실패")
    }
    ; 목록은 맨 아래에서 Down 을 누르면 맨 위로 돈다(1004 실측: 7개 행). 처음 본 행이 다시 선택되면 한 바퀴다.
    amounts := Map(), seen := Map()
    Loop 12 {
        lines := EarnVinewoodReadSelected(&name, &amount)
        if (!IsObject(lines))
            return false
        if (name = "") {
            EarnLog("금고: 판독한 줄 " EarnVinewoodAmountDebug(lines))
            return EarnFail("금고: 수익 목록에서 선택한 사업장을 확인하지 못함")
        }
        if (seen.Has(name))
            break
        seen[name] := true
        if (EarnSafeIgnored().Has(name)) {
            ; 쓰지 않는 사업장은 금액을 기록하지 않는다.
        } else if (!safes.Has(name)) {
            ; 모르는 사업장은 한도를 모르므로 금액만 남기고 수거하지 않는다.
            EarnLog("금고: 모르는 사업장 " name (amount >= 0 ? " $" amount : "") ", 수거 안 함")
            amounts[name] := -1
        } else if (amount < 0 || amount > safes[name][1]) {
            EarnLog("금고: " name " 금액 판독 실패. 판독한 줄 " EarnVinewoodAmountDebug(lines))
            amounts[name] := -1
        } else {
            EarnLog("금고: " name " $" amount)
            if (amount > 0 && EarnVinewoodSafeClaimDue(amount, safes[name]*)) {
                if (!EarnVinewoodClaim(name, amount))
                    return false
                amount := 0
            }
            amounts[name] := amount
        }
        if (!EarnPress("Down") || !EarnSleep(700))
            return false
    }
    if (!seen.Count)
        return EarnFail("금고: 수익 목록이 비어 있음")
    EarnVinewoodSafeScheduleAll(amounts)
    return EarnVinewoodClose()
}

; 선택한 행의 금고를 수거하고 같은 행의 빈 금고 문구를 확인한다. 다른 사업장이나 Claim All 은 고르지 않는다.
EarnVinewoodClaim(name, amount) {
    EarnVinewoodReadSelected(&again, &againAmount)
    if (again != name || againAmount != amount)
        return EarnFail("금고: 수거 직전 " name " $" amount " 선택 미확인")
    if (!EarnPress("Enter") || !EarnSleep(1000))
        return false
    deadline := A_TickCount + 15000
    Loop {
        lines := EarnVinewoodReadSelected(&after, &left)
        if (!IsObject(lines))
            return false
        if (after = name && left = 0) {
            EarnLog("금고: " name " $" amount " 수거 뒤 빈 금고 확인")
            return true
        }
        ; 모르는 확인창에서 다시 Enter를 보내지 않는다. 한 번 요청한 수거는 자동 재전송하지 않는다.
        if (A_TickCount >= deadline || !EarnSleep(300))
            return EarnFail("금고: " name " 수거 후 $0 미확인. 자동 재수거 중단")
    }
}

; 다음 입금이 한도를 넘길 수 있으면 지금 수거한다. 꽉 찰 때까지 기다리면 넘치는 입금이 버려진다.
EarnVinewoodSafeClaimDue(amount, cap := 250000, daily := 50000) {
    return amount + daily > cap
}

; 수거할 때가 되려면 입금이 몇 번 더 들어와야 하는지로 다음 확인을 미룬다. 매번 앱을 열지 않는다.
; k번째 입금이 수거 금액(> 한도-하루 입금)을 만든다면 그 입금은 빨라야 (k-1)×48분 뒤이고, 늦어도 k×48분 뒤다.
; 수거는 그 입금과 다음 입금 사이 48분 안에 하면 되므로 k×48-8분 뒤에 본다. 아직이면 그때 k=1 로 40분 뒤 다시 본다.
; 실제 입금이 최대보다 작으면 더 늦게 차므로 일찍 보는 쪽으로만 어긋난다.
EarnVinewoodSafeNextMs(amount, cap := 250000, daily := 50000) {
    due := cap - daily
    deposits := amount > due ? 1 : (due - amount) // daily + 1
    return Max(300000, (deposits * 48 - 8) * 60000)
}

; 금고마다 다음 확인 시각을 구해 가장 이른 것으로 미룬다. 판독 못 한 금고가 있으면 40분 안에 다시 본다.
; 목록을 못 봤으면(수거할 수익 없음) 아는 금고가 모두 $0 이라고 보고 계산한다.
EarnVinewoodSafeScheduleAll(amounts) {
    safes := EarnSafeLimits()
    if (!amounts.Count)
        for name in safes
            amounts[name] := 0
    ms := 0, first := ""
    for name, amount in amounts {
        next := amount < 0 || !safes.Has(name) ? 40 * 60000 : EarnVinewoodSafeNextMs(amount, safes[name]*)
        if (!ms || next < ms)
            ms := next, first := name
    }
    EarnLog("금고: 다음 확인 " Round(ms / 60000) "분 뒤 (" first " 기준)")
    return EarnScheduleNext("safe", ms)
}

; 선택한 행의 사업장 이름과 그 금고 금액을 읽는다. 한 번의 판독이 깨지면(1003 19:22 실측) 흰 글자 전처리와 재판독으로 세 번까지 본다.
; 테러바이트처럼 밝은 배경 위의 반투명 설명은 일반 OCR 이 깨뜨린다(1003 17:28 실측: "yOürNightclub").
EarnVinewoodReadSelected(&name, &amount) {
    name := "", amount := -1, lines := false
    Loop 3 {
        for white in [false, true] {
            read := EarnReadScreen([25,15,450,850], white)
            if (!IsObject(read))
                continue
            lines := read
            name := EarnVinewoodSelectedSafe(read)
            amount := name = "" ? -1 : EarnVinewoodSafeAmountOf(read, name)
            if (amount >= 0)
                return read
        }
        if (A_Index = 3 || !EarnSleep(500))
            break
    }
    return lines
}

; 선택 막대가 걸린 행의 이름. 왼쪽 끝이 기호로 읽힐 때가 있다(1003 19:38 실측: ": Nightclub").
; 아는 사업장 이름은 대소문자를 무시하고 표준 이름으로 돌려준다.
EarnVinewoodSelectedSafe(lines) {
    safes := EarnSafeLimits()
    if (!IsObject(lines) || !EarnFindText(lines, "i)^THE VINEWOOD CLUB APP$"))
        return ""
    for line in lines {
        text := Trim(RegExReplace(line.text, "^[^A-Za-z0-9$]+"))
        if (text = "" || RegExMatch(text, "i)^(the vinewood club|claim |your )") || !EarnMenuRowSelected(line))
            continue
        for known in safes
            if (text = known)
                return known
        return text
    }
    return ""
}

; 금액을 다른 사업장의 설명이나 이름 옆의 임의 숫자에서 추측하지 않는다. 선택한 행과 같은 사업장 문구 하나만 쓴다.
; "your" 는 반투명 배경에서 깨지거나 앞 단어에 붙는다(1003·1004 실측: "ydÜr", "fromyour"). 금액과 "<사업장> safe." 는 그대로 요구한다.
; 긴 이름은 문구가 두 줄로 넘어간다(1004 실측: "Claim $35720 from your Garment Factory" / "safe.").
EarnVinewoodSafeAmountOf(lines, name) {
    if (!IsObject(lines) || name = "")
        return -1
    claimed := "i)^Claim \$[0-9,]+ from\s*\S+\s*\Q" name "\E safe\.$"
    empty := "i)^Your \Q" name "\E safe is empty\.$"
    amount := -1, matches := 0
    for i, line in lines {
        texts := [line.text]
        if (i < lines.Length)
            texts.Push(line.text " " lines[i + 1].text)
        for text in texts {
            if (RegExMatch(text, empty)) {
                amount := 0, matches += 1
            } else if (RegExMatch(text, claimed)) {
                amount := EarnReadDollars(text), matches += 1
            }
        }
    }
    return matches = 1 ? amount : -1
}

; 이전 시험·로그와 같은 이름으로 나이트클럽 금액만 읽는다.
EarnVinewoodNightclubAmount(lines) {
    return EarnVinewoodSelectedSafe(lines) = "Nightclub" ? EarnVinewoodSafeAmountOf(lines, "Nightclub") : -1
}

; 실패 원인을 녹화 없이도 가릴 수 있게 앱 제목·선택 행·금고 문구만 한 줄로 남긴다.
EarnVinewoodAmountDebug(lines) {
    if (!IsObject(lines))
        return "(OCR 실패)"
    out := ""
    for line in lines {
        if (!RegExMatch(line.text, "i)vinewood club app|claim|safe") && !EarnMenuRowSelected(line))
            continue
        out .= (out = "" ? "" : " | ") line.text (EarnMenuRowSelected(line) ? "[선택]" : "")
    }
    return out = "" ? "(해당 줄 없음)" : out
}

EarnVinewoodOpen() {
    lines := EarnReadScreen([25,15,450,500])
    if (!IsObject(lines))
        return false
    if (EarnFindText(lines, "i)^THE VINEWOOD CLUB APP$"))
        return true
    if (!EarnSeen("ph_joblist_sel", [0.83,0.66,0.98,0.73])
        && !EarnSeen("ph_vinewood_sel", [0.83,0.66,0.98,0.73])) {
        if (EarnAtMCT() && !EarnMCTClose())
            return false
        if (!EarnSeen("mct_sit", [0,0,0.3,0.1]) && !EarnSeen("mct_terrorbyte"))
            return EarnFail("금고: MCT 앞 대기 위치를 확인하지 못함")
        if (!EarnCEO(false) || !EarnPress("Up") || !EarnSleep(700))
            return false
    }
    ; 휴대폰이 다 올라오기까지 1초 넘게 걸릴 때가 있다(1004 14:20 녹화). 홈의 선택 제목이 보일 때까지 기다린다.
    deadline := A_TickCount + 4000
    while (!EarnSeen("ph_joblist_sel", [0.83,0.66,0.98,0.73]) && !EarnSeen("ph_vinewood_sel", [0.83,0.66,0.98,0.73])) {
        if (A_TickCount >= deadline || !EarnSleep(200))
            return EarnFail("금고: 전화 홈 화면 미확인")
    }
    if (EarnSeen("ph_joblist_sel", [0.83,0.66,0.98,0.73])) {
        if (!EarnPress("Right"))
            return false
    }
    if (!EarnWaitSeen("ph_vinewood_sel", [0.83,0.66,0.98,0.73], 3000))
        return EarnFail("금고: 전화 홈에서 Vinewood Club 앱 선택 미확인")
    if (!EarnPress("Enter") || !EarnSleep(700))
        return false
    return EarnFindText(EarnReadScreen([25,15,450,500]), "i)^THE VINEWOOD CLUB APP$")
        ? true : EarnFail("금고: Vinewood Club 앱이 열리지 않음")
}

EarnVinewoodClose() {
    backCount := 0
    Loop 8 {
        lines := EarnReadScreen([25,15,450,850])
        if (!IsObject(lines))
            return false
        if (EarnFindText(lines, "i)^THE VINEWOOD CLUB APP$")
            || EarnSeen("ph_vinewood_sel", [0.83,0.66,0.98,0.73])
            || EarnSeen("ph_joblist_sel", [0.83,0.66,0.98,0.73])) {
            if (backCount >= 4 || !EarnPress("Backspace") || !EarnSleep(1000))
                return false
            backCount += 1
            continue
        }
        if (EarnSeen("mct_sit", [0,0,0.3,0.1]) || EarnSeen("mct_terrorbyte"))
            return true
        ; 앱이 닫혀도 MCT 접근 안내가 약 1초 뒤 나타날 수 있다. 미확인 화면에는 입력하지 않는다.
        if (!EarnSleep(300))
            return false
    }
    return EarnFail("금고: 앱 메뉴 닫기 제한")
}
