; === 수익 자동화 작업 ===
; 각 작업은 성공하면 true, 화면 확인이 안 되면 EarnFail(까닭) 으로 false 를 돌려준다.
; 거점은 아케이드 지하 마스터 컨트롤 터미널(MCT) 앞이다. 금고처럼 다른 부동산에 다녀오는 작업은 끝에 MCT 앞으로 돌아와야 성공이다.

; --- 부동산 오가기 ---
; 스폰 위치를 place 로 바꾸고 초대 전용 세션으로 다시 들어간다. 스폰 자리가 매번 달라(0926 실측: 나이트클럽 안 여러 곳·가끔 건물 밖,
; 아케이드 1층·지하) 목표 블립까지 미니맵 길이 보이는 자리가 나올 때까지 EarnRerollMax 번까지 다시 들어간다.
EarnGoTo(place, dir, blip, altBlip := "") {
    global config
    if (!EarnReloadInto(place, dir))
        return false
    tries := config["Settings"]["EarnRerollMax"]
    reach := config["Settings"]["EarnReachPx"]
    Loop tries {
        if (EarnNavPlan(blip, &ta, &sp, &gp) && gp <= reach)
            return true
        ; 목표 블립이 안 보여도 대신 갈 수 있는 블립(같은 방의 다른 아이콘)이 보이면 그 자리로 친다
        if (altBlip != "" && EarnNavPlan(altBlip, &ta, &sp, &gp) && gp <= reach)
            return true
        if (EarnAborted())
            return EarnFail(place ": 멈춤·포커스 이탈")
        if (A_Index = tries)
            break
        seen := EarnBlip(blip, &ba, &bd) ? Format("{:.0f}도 {:.0f}px, 길 끝 {:.0f}px", ba, bd, gp) : "블립 없음"
        EarnLog(place " 스폰 자리에서 " blip " 까지 길이 안 보여 다시 들어감 (" A_Index "/" tries ", " seen ")")
        EarnSnapMinimap(place "_" A_Index)
        if (!EarnRejoin(place))
            return false
    }
    return EarnFail(place ": " tries "번 다시 들어가도 " blip " 까지 길이 보이는 자리가 안 나옴")
}

; 스폰 위치는 그대로 두고 초대 전용 세션으로 다시 들어가 place 안인지 확인한다.
EarnRejoin(place) {
    global config
    s := config["Settings"]
    if (EarnAborted())
        return EarnFail("재접속: 멈춤·포커스 이탈")
    if (!JoinInviteOnlySession(false))
        return EarnFail("세션 이동 메뉴를 확인하지 못함 (" place ")")
    if (!EarnSleep(s["EarnLoadMinSec"] * 1000))
        return EarnFail("재접속 대기 중 멈춤·포커스 이탈")
    deadline := A_TickCount + s["EarnLoadTimeoutSec"] * 1000
    streak := 0
    while (A_TickCount < deadline) {
        if (EarnAborted())
            return EarnFail("재접속 대기 중 멈춤·포커스 이탈")
        streak := EarnHudVisible() ? streak + 1 : 0
        if (streak >= 2)
            break
        Sleep(2000)
    }
    if (streak < 2)
        return EarnFail("재접속: " s["EarnLoadTimeoutSec"] "초 안에 게임 화면(체력 막대)이 안 보임")
    if (!EarnSleep(2000))
        return false
    return EarnCheckPlace(place)
}

; MCT 앞("Press E to sit down" 안내)에 서 있는지. 아니면 아케이드로 다시 들어가 MCT 까지 걸어간다.
EarnAtMCT() {
    global EARN_PROMPT_AREA
    return EarnSeen("mct_sit", EARN_PROMPT_AREA)
}

; MCT 아이콘은 같은 층에서만 미니맵에 뜬다. 안 보이면 같은 방의 기획실 노트북(laptop)부터 찾아가고 거기서 다시 MCT 를 찾는다(0926 실측: 지하 차고 스폰에서는 노트북만 보임).
EarnGoHome() {
    global config
    if (EarnAtMCT())
        return true
    ; 이미 아케이드 안이면 다시 들어가지 않고 걸어가 본다
    if (EarnWalkToMCT())
        return true
    ; 아케이드 스폰은 나이트클럽에서 Right 두 칸 (스폰 목록 순서)
    if (!EarnGoTo("Arcade", "Right", "mct", "laptop"))
        return false
    Loop config["Settings"]["EarnWalkRetry"] {
        if (EarnWalkToMCT())
            break
        if (EarnAborted())
            return EarnFail("MCT: 멈춤·포커스 이탈")
        if (A_Index = config["Settings"]["EarnWalkRetry"])
            return EarnFail("MCT: " A_Index "번 다시 들어가도 MCT 앞에 못 닿음")
        EarnLog("MCT: 걸어서 못 닿아 다시 들어감 (" A_Index "/" config["Settings"]["EarnWalkRetry"] ")")
        if (!EarnRejoin("Arcade"))
            return false
    }
    EarnLog("MCT 앞 도착")
    return true
}

; 지금 자리에서 MCT 앞까지. MCT 블립이 보이면 바로, 아니면 노트북까지 간 뒤 MCT. 둘 다 안 보이면 false (EarnFail 없이, 다시 들어갈지는 부르는 쪽이 정한다)
EarnWalkToMCT() {
    if (EarnBlip("mct", &a, &d))
        return EarnNavTo("mct", "mct_sit")
    if (!EarnBlip("laptop", &a, &d))
        return false
    EarnLog("MCT 블립이 안 보여 기획실 노트북(" Round(a) "도 " Round(d) "px)까지 먼저 감")
    if (!EarnNavTo("laptop", "", 18))
        return false
    if (!EarnBlip("mct", &a, &d))
        return EarnFail("노트북 옆까지 갔는데 MCT 블립이 안 보임")
    return EarnNavTo("mct", "mct_sit")
}

; --- 나이트클럽 금고 ---
; 나이트클럽에 들어가 금고까지 걸어가 E → 판넬이 열리면 안으로 걸어 들어가 줍고 → 오른쪽 아래 WALL SAFE 가 $0 인지 확인 → E 로 닫는다. 그다음 아케이드 MCT 앞으로 돌아온다.
; 0926 17:43 수동 실측: 금고 $250,000 → $0, 현금 +$250,000. 0927 00:48 매크로(EarnSafeCollect) 실측: $12,000 → $0.
; 스폰 자리는 매번 다르다(1층 바·댄스 플로어·화장실, 2층 난간·뒷방, 침대 옆). 미니맵은 지금 층만 그려서 1층에서는 2층 사무실까지 길이 안 이어진다(0927 실측: 3번 중 1번만 닿음).
; 그래서 들어간 자리에서 금고($ 블립)나 사무실 노트북(같은 층일 때만 미니맵 안에 보임)까지 길이 보일 때만 걷고, 아니면 다시 들어간다. 자리는 같은 곳이 몇 번씩 이어지므로
; EarnRerollMax 번 안에 못 만나면 EarnSafeRetryMin 분 뒤에 다시 한다(스케줄러는 끄지 않는다).
; 미니맵 $ 블립은 금고에 돈이 있을 때만 뜬다($0 이면 사라짐). HUD 가 $0 이면 갈 필요가 없어 건너뛴다.
global gSafeCollectedTick := 0   ; 마지막으로 금고를 비운 시각. 그 뒤 복귀에 실패해 다시 돌 때 금고를 또 찾지 않게

EarnSafeTask() {
    global config, gEarnFail, gSafeCollectedTick
    s := config["Settings"]
    ; 방금(한 시간 안에) 비웠는데 복귀만 못 한 경우: 복귀부터
    if (gSafeCollectedTick && A_TickCount - gSafeCollectedTick < 3600000)
        return EarnGoHome() ? true : EarnSoftFail(gEarnFail, s["EarnSafeRetryMin"])
    if (!EarnInPlace("Nightclub") && !EarnReloadInto("Nightclub", "Left"))
        return EarnSoftFail(gEarnFail, s["EarnSafeRetryMin"])
    Loop s["EarnRerollMax"] {
        if (EarnAborted())
            return EarnFail("금고: 멈춤·포커스 이탈")
        if (EarnSeen("hud_safe_label", [0.82, 0.9, 0.95, 0.97]) && EarnSeen("hud_safe_zero", [0.93, 0.9, 1, 0.97])) {
            EarnLog("금고: WALL SAFE $0 이라 이번엔 건너뜀")
            return true
        }
        r := EarnSpawnRoute()
        if (r != "" && EarnWalkToSafeVia(r))
            break
        if (EarnAborted())
            return EarnFail("금고: 멈춤·포커스 이탈")
        if (A_Index = s["EarnRerollMax"])
            return EarnSoftFail("금고: " A_Index "번 다시 들어가도 금고까지 길이 보이는 자리가 안 나옴", s["EarnSafeRetryMin"])
        EarnLog("금고: 이 자리에서는 못 감(" (r = "" ? "길 없음" : r " 경로 실패") ") → 다시 들어감 (" A_Index "/" s["EarnRerollMax"] ")")
        if (!EarnRejoin("Nightclub"))
            return EarnSoftFail(gEarnFail, s["EarnSafeRetryMin"])
    }
    if (!EarnSafeCollect())
        return false
    gSafeCollectedTick := A_TickCount
    return EarnGoHome() ? true : EarnSoftFail(gEarnFail, s["EarnSafeRetryMin"])
}

; 지금 자리에서 금고로 가는 길이 미니맵에 보이는지. "safe" = $ 블립까지 길이 있음, "laptop" = 사무실 노트북이 미니맵 안(같은 층)이고 길이 있음, "" = 못 감(1층 등)
EarnSpawnRoute() {
    global config
    if (EarnBlip("safe", &a, &d) && d < 999 && EarnNavPlan("safe", &ta, &sp, &gp) && gp <= config["Settings"]["EarnReachPx"])
        return "safe"
    if (EarnBlip("laptop", &a, &d) && d < 999 && EarnNavPlan("laptop", &ta, &sp, &gp) && gp <= 30)
        return "laptop"
    return ""
}

EarnWalkToSafeVia(r) {
    if (r = "safe")
        return EarnNavTo("safe", "safe_prompt", 12, 30)
    if (!EarnNavTo("laptop", "", 30, 40))
        return false
    if (!EarnBlip("safe", &a, &d))
        return EarnFail("금고: 사무실 노트북 옆에서도 $ 블립이 안 보임")
    return EarnNavTo("safe", "safe_prompt", 12, 30)
}

; 상호작용 메뉴 맨 윗줄로 place 안인지 본다 (EarnCheckPlace 와 달리 아니어도 멈춤 까닭을 남기지 않는다)
EarnInPlace(place) {
    global EARN_MENU_AREA
    if (!EarnMenuOpen())
        return false
    here := EarnSeen("mgmt_" place, EARN_MENU_AREA) || EarnSeen("mgmt_" place "_sel", EARN_MENU_AREA)
    EarnMenuClose()
    return here
}
; "Press E to open your Safe" 가 보이는 자리에서: E → 판넬이 열리는 동작(약 4초) → 금고 쪽을 보고 걸어 들어가 줍는다.
; 주우면 "Press E to close your Safe" 가 뜨고 오른쪽 아래 WALL SAFE 가 $0 이 된다 → E 로 닫는다.
EarnSafeCollect() {
    global EARN_PROMPT_AREA
    if (!EarnSeen("safe_prompt", EARN_PROMPT_AREA))
        return EarnFail("금고: Press E to open your Safe 안내가 안 보임")
    if (!EarnPress("e"))
        return false
    if (!EarnSleep(4500))
        return false
    collected := false
    Loop 4 {
        if (EarnSeen("hud_safe_zero") && EarnSeen("safe_close_prompt", EARN_PROMPT_AREA)) {
            collected := true
            break
        }
        EarnFace("safe", 0, 8)
        if (!EarnWalk("w:600"))
            return false
        EarnSleep(1200)
    }
    if (!collected)
        return EarnFail("금고: 판넬을 연 뒤 WALL SAFE $0 과 닫기 안내를 확인하지 못함")
    EarnLog("금고 비움 (WALL SAFE $0 확인)")
    if (!EarnPress("e"))
        return false
    if (!EarnWaitGone("safe_close_prompt", EARN_PROMPT_AREA, 6000))
        return EarnFail("금고: 닫기 안내가 사라지지 않음")
    return EarnSleep(2000)
}

; --- 벙커 보급 (규칙은 사용자 지시 0926) ---
; 풀업그레이드 벙커는 보급 한 칸(20%)을 28분에 쓴다. 구매 값은 빈 양을 20% 단위로 올려 매기고 넘치는 양은 버리므로, 한 칸이 통째로 비었을 때만 산다.
; 재고가 가득 차면 생산이 멈춰 보급이 줄지 않는다 → 그동안은 사지 않고 타이머를 멈춘다. 재고를 판 뒤 보급이 가득 찬 시점부터 다시 센다.
; 막대는 MCT 첫 화면 벙커 카드(재고 초록 y 555, 보급 파랑 y 577, x 766~1154)에서 읽는다. 판단이 안 되면 사지 않고 로그만 남긴다.
; 산 뒤 다음 시각은 구매 순간 + EarnBunkerIntervalSec (매크로 실행 시간은 주기에서 빠진다).
global gBunkerFullSince := 0   ; 보급이 가득 찬 것을 마지막으로 본 시각 (A_TickCount). 0 이면 모름

EarnBunkerTask() {
    global config, gEarnNextDue, gBunkerFullSince
    s := config["Settings"]
    if (!EarnGoHome())
        return false
    if (!EarnMCTOpen())
        return false
    stock := EarnBarFill(766, 1154, 555, "green")
    supply := EarnBarFill(766, 1154, 577, "blue")
    EarnLog(Format("벙커: 재고 {:.0f}% 보급 {:.0f}%", stock * 100, supply * 100))
    if (stock < 0 || supply < 0) {
        EarnMCTClose()
        return EarnFail("벙커: 막대를 읽지 못함")
    }
    ; 재고가 가득: 생산이 멈춘 상태. 사지 않고 다음 확인만 잡는다
    if (stock >= 0.97) {
        gBunkerFullSince := 0
        EarnLog("벙커: 재고 가득 → 생산 정지 중이라 사지 않음 (재고를 판 뒤 다시 센다)")
        gEarnNextDue["bunker"] := A_TickCount + s["EarnBunkerIntervalSec"] * 1000
        return EarnMCTClose()
    }
    ; 보급이 가득: 시각만 기록하고 다음 확인은 28분 뒤
    if (supply >= 0.97) {
        if (!gBunkerFullSince)
            gBunkerFullSince := A_TickCount
        EarnLog("벙커: 보급 가득, " Round(s["EarnBunkerIntervalSec"] / 60) "분 뒤 다시 봄")
        ; 가득 찬 것을 본 시각이 오래됐어도(껐다 켠 뒤) 최소 5분 뒤에 다시 본다
        gEarnNextDue["bunker"] := Max(A_TickCount + 5 * 60000, gBunkerFullSince + s["EarnBunkerIntervalSec"] * 1000)
        return EarnMCTClose()
    }
    ; 한 칸(20%) 이상 통째로 비었을 때만 산다
    if (supply > 0.81) {
        EarnLog("벙커: 보급이 한 칸 다 비지 않아(" Round(supply * 100) "%) 이번엔 사지 않음")
        gEarnNextDue["bunker"] := A_TickCount + 5 * 60000
        return EarnMCTClose()
    }
    if (!EarnBunkerBuy()) {
        EarnMCTClose()
        return false
    }
    gBunkerFullSince := A_TickCount
    gEarnNextDue["bunker"] := A_TickCount + s["EarnBunkerIntervalSec"] * 1000
    return EarnMCTClose()
}

; MCT 벙커 카드 → 관리 화면 → 보급 구매. CEO 여야 한다. 화면 좌표·템플릿은 0926 실측으로 채운다
EarnBunkerBuy() {
    return EarnFail("벙커 구매 화면: 아직 실측 전")
}

; --- 나이트클럽 DJ 교체 (규칙은 사용자 지시 0926) ---
; 인기도가 EarnDJPopularityPct(95) 미만이면 이미 불렀던 DJ 둘을 번갈아 골라($10,000, +10%) 95% 이상이 될 때까지, 한 번 실행에 최대 10회.
; 교체마다 인기도가 올랐는지 화면으로 확인하고, 한 번이라도 오르지 않았거나 못 읽으면 즉시 멈춘다. 처음 부르는 DJ($100,000) 줄은 절대 고르지 않는다.
EarnDJTask() {
    global config
    s := config["Settings"]
    if (!EarnGoHome())
        return false
    if (!EarnMCTOpen())
        return false
    pop := EarnPopularityMCTPct()
    EarnLog("DJ: 인기도 " pop "%")
    if (pop < 0) {
        EarnMCTClose()
        return EarnFail("DJ: 인기도를 읽지 못함")
    }
    if (pop >= s["EarnDJPopularityPct"]) {
        EarnLog("DJ: " s["EarnDJPopularityPct"] "% 이상이라 교체 안 함")
        return EarnMCTClose()
    }
    ok := EarnDJSwapLoop(pop)
    EarnMCTClose()
    return ok
}

EarnDJSwapLoop(pop) {
    return EarnFail("DJ 교체 화면: 아직 실측 전")
}

EarnDispatchTask() {
    return EarnFail("현장 파견: 아직 만들지 않음")
}
