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
    lines := EarnReadScreen([25,15,450,850])
    amount := EarnVinewoodNightclubAmount(lines)
    if (amount < 0 || amount > 250000)
        return EarnFail("금고: 나이트클럽 금액 판독 실패")
    EarnLog("금고: 나이트클럽 $" amount)
    if (amount < 250000)
        return EarnVinewoodClose()
    if (EarnVinewoodNightclubAmount(EarnReadScreen([25,15,450,850])) != 250000)
        return EarnFail("금고: 수거 직전 나이트클럽 $250,000 선택 미확인")
    ; 다른 사업장의 수익이나 Claim All은 선택하지 않는다.
    if (!EarnPress("Enter") || !EarnSleep(1000))
        return false
    deadline := A_TickCount + 15000
    Loop {
        lines := EarnReadScreen([25,15,450,850])
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

; 금액을 다른 사업장의 설명이나 Nightclub 이름 옆의 임의 숫자에서 추측하지 않는다.
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
        } else if (RegExMatch(line.text, "i)^Claim \$[0-9,]+ from your Nightclub safe\.$")) {
            amount := EarnReadDollars(line.text)
            matches += 1
        }
    }
    return matches = 1 ? amount : -1
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
        if (!EarnSeen("mct_sit", [0,0,0.3,0.1]))
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
        if (EarnSeen("mct_sit", [0,0,0.3,0.1]))
            return true
        ; 앱이 닫혀도 MCT 접근 안내가 약 1초 뒤 나타날 수 있다. 미확인 화면에는 입력하지 않는다.
        if (!EarnSleep(300))
            return false
    }
    return EarnFail("금고: 앱 메뉴 닫기 제한")
}
