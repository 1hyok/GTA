; 바인우드 앱의 실제 금고 금액을 확인한다. 나이트클럽에 걷거나 재접속하지 않는다.
EarnVinewoodSafeTask() {
    if (!EarnVinewoodOpen())
        return false
    lines := EarnReadScreen([25,15,450,850])
    if (!IsObject(lines) || !EarnFindText(lines, "i)^THE VINEWOOD CLUB APP$"))
        return false
    if (EarnFindText(lines, "i)^No earnings to claim\.?$")) {
        EarnLog("금고: 바인우드 앱에 수거할 수익 없음")
        return EarnVinewoodClose()
    }
    ; 앱 메인과 수익 하위 목록은 제목이 같다. 이미 하위 목록이면 다시 Enter를 보내지 않는다.
    if (!EarnFindText(lines, "i)^Nightclub$")) {
        row := EarnSelectText("i)^Claim Business Earnings$", "i)^THE VINEWOOD CLUB APP$", 6)
        if (!row || !EarnPress("Enter") || !EarnSleep(700))
            return EarnFail("금고: 수익 목록 진입 실패")
    }
    if (!EarnSelectText("i)^Nightclub$", "i)^THE VINEWOOD CLUB APP$", 7))
        return EarnFail("금고: 수익 목록에서 나이트클럽 선택 미확인")
    ; 행에는 금액이 없다. 선택한 행과 하단의 나이트클럽 전용 설명을 같은 화면에서 읽는다.
    ; 한 번의 판독이 깨져도(1003 19:22 실측) 같은 화면을 세 번까지 다시 읽고, 끝내 실패하면 읽은 줄을 남긴다.
    Loop 3 {
        lines := EarnVinewoodAmountLines()
        amount := EarnVinewoodNightclubAmount(lines)
        if (amount >= 0 || !IsObject(lines) || A_Index = 3 || !EarnSleep(500))
            break
    }
    if (amount < 0 || amount > 250000) {
        EarnLog("금고: 판독한 줄 " EarnVinewoodAmountDebug(lines))
        return EarnFail("금고: 나이트클럽 금액 판독 실패")
    }
    EarnLog("금고: 나이트클럽 $" amount)
    if (amount = 0 || !EarnVinewoodSafeClaimDue(amount))
        return EarnVinewoodClose()
    if (EarnVinewoodNightclubAmount(EarnVinewoodAmountLines()) != amount)
        return EarnFail("금고: 수거 직전 나이트클럽 $" amount " 선택 미확인")
    ; 다른 사업장의 수익이나 Claim All은 선택하지 않는다.
    if (!EarnPress("Enter") || !EarnSleep(1000))
        return false
    deadline := A_TickCount + 15000
    Loop {
        lines := EarnVinewoodAmountLines()
        if (!IsObject(lines))
            return false
        if (EarnVinewoodNightclubAmount(lines) = 0
            && EarnFindText(lines, "i)^Your Nightclub safe is empty\.$")) {
            EarnLog("금고: 나이트클럽 수거 뒤 빈 금고 확인")
            return EarnVinewoodClose()
        }
        ; 모르는 확인창에서 다시 Enter를 보내지 않는다. 한 번 요청한 수거는 자동 재전송하지 않는다.
        if (A_TickCount >= deadline || !EarnSleep(300))
            return EarnFail("금고: 수거 후 $0 미확인. 자동 재수거 중단")
    }
}


; 금고는 한도 $250,000 이고 입금은 게임 하루(48분)마다 한 번에 최대 $50,000 이다(1003 실측: 17:38 $195,000 → 18:12 $245,000).
; 꽉 찰 때까지 기다리면 넘치는 입금이 버려지므로, 다음 입금이 넘칠 금액이면 지금 수거한다.
EarnVinewoodSafeClaimDue(amount) {
    return amount + 50000 > 250000
}

; 테러바이트처럼 밝은 배경 위의 반투명 설명은 일반 OCR 이 깨뜨린다(1003 17:28 실측: "yOürNightclub").
; 일반 판독으로 금액이 안 나올 때만 흰 글자 전처리로 다시 읽는다.
EarnVinewoodAmountLines() {
    lines := EarnReadScreen([25,15,450,850])
    if (EarnVinewoodNightclubAmount(lines) >= 0)
        return lines
    white := EarnReadScreen([25,15,450,850], true)
    return IsObject(white) ? white : lines
}

; 금액을 다른 사업장의 설명이나 Nightclub 이름 옆의 임의 숫자에서 추측하지 않는다.
; "your" 는 반투명 배경에서 자주 깨진다(1003 실측: "ydÜr"). 금액과 Nightclub safe 는 그대로 요구한다.
EarnVinewoodNightclubAmount(lines) {
    if (!IsObject(lines) || !EarnFindText(lines, "i)^THE VINEWOOD CLUB APP$"))
        return -1
    selected := EarnFindText(lines, "i)^Nightclub$")
    if (!selected || !EarnMenuRowSelected(selected))
        return -1
    amount := -1, matches := 0
    for line in lines {
        if (RegExMatch(line.text, "i)^Your Nightclub safe is empty\.$")) {
            amount := 0
            matches += 1
        } else if (RegExMatch(line.text, "i)^Claim \$[0-9,]+ from \S+ Nightclub safe\.$")) {
            amount := EarnReadDollars(line.text)
            matches += 1
        }
    }
    return matches = 1 ? amount : -1
}

; 실패 원인을 녹화 없이도 가릴 수 있게 앱 제목·나이트클럽 행 선택·하단 설명만 한 줄로 남긴다.
EarnVinewoodAmountDebug(lines) {
    if (!IsObject(lines))
        return "(OCR 실패)"
    out := ""
    for line in lines {
        if (!RegExMatch(line.text, "i)vinewood club app|nightclub|claim|safe"))
            continue
        out .= (out = "" ? "" : " | ") line.text
        if (RegExMatch(line.text, "i)^Nightclub$"))
            out .= EarnMenuRowSelected(line) ? "[선택]" : "[미선택]"
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
