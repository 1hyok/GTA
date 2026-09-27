; === 수익 자동화 작업 ===
; 각 작업은 성공하면 true, 화면 확인이 안 되면 EarnFail(까닭) 으로 false 를 돌려준다.
; MCT 전용 모드는 열려 있는 터미널에 머문다. 이동 모드는 아케이드 MCT를 거점으로 쓴다.

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

; MCT 전용 접근 안내나 사업장 목록으로 도착을 확인한다. 일반 앉기 안내는 공통이라 쓰지 않는다.
EarnAtMCT() {
    global EARN_PROMPT_AREA
    return EarnSeen("mct_seated", EARN_PROMPT_AREA)
        || EarnSeen("mct_title", [0.3,0,0.7,0.1])
}

; 다른 부동산에서만 아케이드로 한 번 이동한다. 아케이드 안의 경로 실패로 다시 접속하지 않는다.
EarnGoHome() {
    if (EarnSeen("arcade_laptop_seated", [0,0,0.3,0.1])) {
        if (EarnAborted())
            return false
        Click("Right Down")
        try Sleep(100)
        finally Click("Right Up")
        if (!EarnWaitGone("arcade_laptop_seated", [0,0,0.3,0.1], 5000))
            return EarnFail("복귀: 일반 노트북에서 일어서지 못함")
        if (!EarnSleep(1000))
            return false
    }
    if (EarnAtMCT())
        return true
    ; 아케이드에 도착한 뒤 길찾기 실패를 스폰 실패로 취급하지 않는다.
    ; 다른 층의 MCT까지 미니맵 길이 이어질 때까지 재접속해도 계단 경로는 해결되지 않는다.
    if (!EarnInPlace("Arcade") && !EarnReloadInto("Arcade", "Right"))
        return false
    if (!EarnWalkToMCT())
        return false
    EarnLog("MCT 복귀 완료 (전용 접근 안내 확인)")
    return true
}

; 지금 자리에서 MCT 앞까지. MCT 블립이 보이면 바로, 아니면 노트북까지 간 뒤 MCT. 둘 다 안 보이면 false (EarnFail 없이, 다시 들어갈지는 부르는 쪽이 정한다)
EarnWalkToMCT() {
    ; 차고 스폰은 정면 계단을 먼저 오른다. 다른 층의 블립 방향으로 꺾지 않는다.
    if (EarnSeen("arcade_basement_spawn", [0.48,0.45,0.64,0.68]))
        return EarnArcadeBasementToMCT()
    if (EarnBlip("mct", &a, &d))
        return EarnNavTo("mct", "mct_sit") && EarnConfirmMCTSeat()
    if (!EarnBlip("laptop", &a, &d))
        return false
    EarnLog("MCT 블립이 안 보여 기획실 노트북(" Round(a) "도 " Round(d) "px)까지 먼저 감")
    if (!EarnNavTo("laptop", "", 18))
        return false
    if (!EarnBlip("mct", &a, &d))
        return EarnFail("노트북 옆까지 갔는데 MCT 블립이 안 보임")
    return EarnNavTo("mct", "mct_sit") && EarnConfirmMCTSeat()
}

; 아케이드 차고의 고정 스폰에서 정면 계단으로 간다. 시작 화면이 같은 경우에만 실행한다.
EarnArcadeBasementToMCT() {
    if (!EarnSeen("arcade_basement_spawn", [0.48,0.45,0.64,0.68]))
        return EarnFail("아케이드: 지하 고정 스폰 화면이 아님")
    EarnLog("아케이드 지하: 정면 계단까지 직진")
    if (!EarnWalk("w:6500") || !EarnSleep(1300))
        return false
    if (!EarnBlip("mct", &angle, &distance) || distance >= 999
        || !EarnNavPlan("mct", &turn, &step, &goal) || goal > 14)
        return EarnFail("아케이드: 계단을 오른 뒤 MCT 층의 경로를 확인하지 못함")
    EarnLog("아케이드 지하: 계단 통과, MCT까지 " Round(distance) "px")
    return EarnNavTo("mct", "mct_sit") && EarnConfirmMCTSeat()
}

; 일반 노트북도 같은 앉기 안내를 쓴다. MCT 전용 접근 안내까지 확인해야 복귀 성공이다.
EarnConfirmMCTSeat() {
    global EARN_PROMPT_AREA
    if (!EarnSeen("mct_sit", EARN_PROMPT_AREA) || !EarnPress("e"))
        return false
    return EarnWaitSeen("mct_seated", EARN_PROMPT_AREA, 8000)
        || EarnFail("복귀: MCT 전용 접근 안내가 아님")
}

; --- 나이트클럽 금고 ---
; 나이트클럽 금고를 열어 수거하고 WALL SAFE $0을 확인한다. 금고는 열어 둔 채 아케이드 MCT로 돌아온다.
; 보스 등록·해제는 포함하지 않는다. 사용자가 시작 전에 해제할 수 있다.
; 0926 17:43 수동 실측: 금고 $250,000 → $0, 현금 +$250,000. 0927 00:48 매크로(EarnSafeCollect) 실측: $12,000 → $0.
; 스폰 자리는 매번 다르다(1층 바·댄스 플로어·화장실, 2층 난간·뒷방, 침대 옆). 미니맵은 지금 층만 그려서 1층에서는 2층 사무실까지 길이 안 이어진다(0927 실측: 3번 중 1번만 닿음).
; 그래서 들어간 자리에서 금고($ 블립)나 사무실 노트북 쪽으로 길이 보일 때 걷는다. 가장자리 노트북은 방향을 따라가며 길을 다시 찾고, 길이 없으면 다시 들어간다. 자리는 같은 곳이 몇 번씩 이어지므로
; EarnRerollMax 번 안에 못 만나면 EarnSafeRetryMin 분 뒤에 다시 한다(스케줄러는 끄지 않는다).
; 미니맵 $ 블립은 금고에 돈이 있을 때만 뜬다($0 이면 사라짐). HUD 가 $0 이면 갈 필요가 없어 건너뛴다.
global gSafeCollectedTick := 0   ; 마지막으로 금고가 비었음을 확인한 시각. 그 뒤 복귀에 실패해 다시 돌 때 금고를 또 찾지 않게

EarnSafeTask() {
    global config, gEarnFail, gSafeCollectedTick
    s := config["Settings"]
    ; 방금(한 시간 안에) 비었음을 확인했는데 복귀만 못 한 경우: 복귀부터
    if (gSafeCollectedTick && A_TickCount - gSafeCollectedTick < 3600000)
        return EarnGoHome() ? true : EarnSoftFail(gEarnFail, s["EarnSafeRetryMin"])
    if (!EarnInPlace("Nightclub") && !EarnReloadInto("Nightclub", "Left"))
        return EarnSoftFail(gEarnFail, s["EarnSafeRetryMin"])
    Loop s["EarnRerollMax"] {
        if (EarnAborted())
            return EarnFail("금고: 멈춤·포커스 이탈")
        if (EarnSeen("hud_safe_label", [0.82, 0.9, 0.95, 0.97]) && EarnSeen("hud_safe_zero", [0.93, 0.9, 1, 0.97])) {
            EarnLog("금고: WALL SAFE $0 이라 이번엔 건너뜀")
            gSafeCollectedTick := A_TickCount
            return EarnGoHome() ? true : EarnSoftFail(gEarnFail, s["EarnSafeRetryMin"])
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

; 지금 자리에서 금고로 가는 길이 미니맵에 보이는지. "safe" = $ 블립까지 길이 있음, "laptop" = 노트북까지 또는 가장자리 노트북 방향으로 길이 있음, "" = 길 없음
EarnSpawnRoute() {
    global config
    if (EarnBlip("safe", &a, &d) && d < 999 && EarnNavPlan("safe", &ta, &sp, &gp) && gp <= config["Settings"]["EarnReachPx"])
        return "safe"
    ; 가장자리 노트북(거리 999)은 위치를 모르므로 gp 로 도착 가능성을 가르지 않는다. EarnNavTo 가 걸음마다 길 끝 거리로 진척을 확인한다.
    if (EarnBlip("laptop", &a, &d) && EarnNavPlan("laptop", &ta, &sp, &gp) && (d >= 999 || gp <= 30))
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
    return EarnMenuClose() && here
}
; "Press E to open your Safe" 가 보이는 자리에서: E → 판넬이 열리는 동작(약 4초) → 금고 쪽을 보고 걸어 들어가 줍는다.
; 열린 금고에서는 E를 다시 누르지 않는다. 닫기 안내와 WALL SAFE $0으로 수거 완료를 확인한다.
EarnSafeCollect() {
    global EARN_PROMPT_AREA
    ; 열린 금고에 다시 왔으면 E를 누르지 않는다. E는 열린 판넬을 닫는다.
    if (!EarnSeen("safe_close_prompt", EARN_PROMPT_AREA)) {
        if (!EarnSeen("safe_prompt", EARN_PROMPT_AREA))
            return EarnFail("금고: 열기·닫기 안내가 안 보임")
        if (!EarnPress("e"))
            return false
        if (!EarnSleep(4500))
            return false
    }
    collected := false
    Loop 4 {
        if (EarnSeen("hud_safe_zero") && EarnSeen("safe_close_prompt", EARN_PROMPT_AREA)) {
            collected := true
            break
        }
        if (!EarnFace("safe", 0, 8))
            return EarnFail("금고: 금고 방향을 확인하지 못해 걷지 않음")
        if (!EarnWalk("w:600"))
            return false
        if (!EarnSleep(1200))
            return false
    }
    if (!collected)
        return EarnFail("금고: 판넬을 연 뒤 WALL SAFE $0 과 닫기 안내를 확인하지 못함")
    EarnLog("금고 비움 (WALL SAFE $0 확인)")
    return true
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
    if (!EarnTaskMCTBegin())
        return false
    interval := s.Get("EarnMCTOnly", 0) ? Min(300, s["EarnBunkerIntervalSec"]) : s["EarnBunkerIntervalSec"]
    stock := EarnBarFill(766, 1154, 555, "green")
    supply := EarnBarFill(766, 1154, 577, "blue")
    EarnLog(Format("벙커: 재고 {:.0f}% 보급 {:.0f}%", stock * 100, supply * 100))
    if (stock < 0 || supply < 0) {
        EarnTaskMCTEnd()
        return EarnFail("벙커: 막대를 읽지 못함")
    }
    ; 재고가 가득: 생산이 멈춘 상태. 사지 않고 다음 확인만 잡는다
    if (stock >= 0.97) {
        gBunkerFullSince := 0
        EarnLog("벙커: 재고 가득 → 생산 정지 중이라 사지 않음 (재고를 판 뒤 다시 센다)")
        gEarnNextDue["bunker"] := A_TickCount + interval * 1000
        return EarnTaskMCTEnd()
    }
    ; 보급이 가득: 시각만 기록하고 다음 확인은 28분 뒤
    if (supply >= 0.97) {
        if (!gBunkerFullSince)
            gBunkerFullSince := A_TickCount
        EarnLog("벙커: 보급 가득, " Round(interval / 60) "분 뒤 다시 봄")
        ; 가득 찬 것을 본 시각이 오래됐어도(껐다 켠 뒤) 최소 5분 뒤에 다시 본다
        gEarnNextDue["bunker"] := Max(A_TickCount + 5 * 60000, gBunkerFullSince + interval * 1000)
        return EarnTaskMCTEnd()
    }
    ; 한 칸(20%) 이상 통째로 비었을 때만 산다
    if (supply > 0.81) {
        EarnLog("벙커: 보급이 한 칸 다 비지 않아(" Round(supply * 100) "%) 이번엔 사지 않음")
        gEarnNextDue["bunker"] := A_TickCount + 5 * 60000
        return EarnTaskMCTEnd()
    }
    if (!EarnBunkerBuy()) {
        return false
    }
    gBunkerFullSince := A_TickCount
    gEarnNextDue["bunker"] := A_TickCount + interval * 1000
    return EarnTaskMCTEnd()
}

; MCT에서 시작해 MCT로 복귀한다. 0927 저택 MCT 화면 기준.
EarnBunkerBuy() {
    if (!EarnUIReady("mct_bunker_card"))
        return EarnFail("벙커: MCT 카드 없음")
    stock := EarnBarFill(766, 1154, 555, "green")
    supply := EarnBarFill(766, 1154, 577, "blue")
    if (stock < 0 || supply < 0)
        return EarnFail("벙커: 막대 판독 실패")
    if (stock >= 0.97 || supply > 0.81)
        return true
    if (!EarnUIClick("mct_bunker_card", 960, 525))
        return false
    deadline := A_TickCount + 8000
    while (!EarnSeen("bunker_page", [0.15,0,0.35,0.12])) {
        if (EarnSeen("bunker_entry", [0.34,0.54,0.64,0.64])) {
            if (!EarnUIClick("bunker_entry", 1150, 650))
                return false
            break
        }
        if (!EarnSleep(100) || A_TickCount >= deadline)
            return EarnFail("벙커: 시작 화면 미확인")
    }
    if (!EarnWaitSeen("bunker_page", [0.15,0,0.35,0.12], 5000)
        || !EarnUIClick("bunker_resupply", 460, 490)
        || !EarnWaitSeen("bunker_buy", "", 3000)
        || !EarnUIClick("bunker_buy", 1150, 795))
        return EarnFail("벙커: 구매 화면 이동 실패")
    ; 이미 배송 중이면 결제하지 않는다. 확인창 불명확시 재시도하지 않는다.
    deadline := A_TickCount + 5000
    while (!EarnSeen("bunker_pending") && !EarnSeen("bunker_confirm")) {
        if (!EarnSleep(100) || A_TickCount >= deadline)
            return EarnFail("벙커: 구매/배송 안내 없음")
    }
    if (EarnSeen("bunker_confirm")) {
        if (!EarnUIClick("bunker_confirm", 1065, 619)
            || !EarnWaitGone("bunker_confirm", "", 15000)
            || !EarnWaitSeen("bunker_buy", "", 5000))
            return EarnFail("벙커: 거래 결과 미확인, 재구매 금지")
        ; 재진입해서 배송 중 안내를 확인한다. 새 결제 확인창은 확정하지 않는다.
        if (!EarnUIClick("bunker_buy", 1150, 795)
            || !EarnWaitSeen("bunker_pending", "", 5000))
            return EarnFail("벙커: 배송 접수 미확인, 재구매 금지")
    }
    if (!EarnUIClick("bunker_pending", 960, 619)
        || !EarnWaitGone("bunker_pending", "", 3000))
        return false
    EarnLog("벙커: 보급 배송 중 확인")
    return EarnUIBackToMCT("bunker_page", 2)
}

; --- 나이트클럽 DJ 교체 (규칙은 사용자 지시 0926) ---
; 수입 최고 구간(95% 이상)을 목표로 기존 DJ를 $10,000에 교체(+10%p).
; 교체마다 인기도가 올랐는지 화면으로 확인하고, 한 번이라도 오르지 않았거나 못 읽으면 즉시 멈춘다. 처음 부르는 DJ($100,000) 줄은 절대 고르지 않는다.
EarnDJTask() {
    global config
    s := config["Settings"]
    if (!EarnTaskMCTBegin())
        return false
    pop := EarnPopularityMCTPct()
    EarnLog("DJ: 인기도 " pop "%")
    if (pop < 0) {
        EarnTaskMCTEnd()
        return EarnFail("DJ: 인기도를 읽지 못함")
    }
    if (!EarnDJNeedsRebook(pop, s["EarnDJPopularityPct"])) {
        EarnLog("DJ: 목표 인기도 도달로 교체 안 함")
        return EarnTaskMCTEnd()
    }
    ok := EarnDJSwapLoop(pop)
    return ok && EarnTaskMCTEnd()
}

EarnTaskMCTBegin() {
    global config
    if (config["Settings"].Get("EarnMCTOnly", 0)) {
        if (!EarnUIReady("mct_title", [0.3,0,0.7,0.1]))
            return EarnFail("MCT 전용: 먼저 사업장 목록을 열어야 함")
        return EarnMCTRefresh()
    }
    return EarnGoHome() && EarnMCTOpen()
}

; MCT 막대는 화면에 재진입해 갱신한다. 사업장 진입 화면에서는 결제 없이 뒤로 돌아온다.
EarnMCTRefresh() {
    if (!EarnUIClick("mct_bunker_card", 960, 525))
        return false
    deadline := A_TickCount + 8000
    Loop {
        if (EarnSeen("bunker_entry", [0.34,0.54,0.64,0.64]))
            return EarnUIBackToMCT("bunker_entry", 1)
        if (EarnSeen("bunker_page", [0.15,0,0.35,0.12]))
            return EarnUIBackToMCT("bunker_page", 2)
        if (!EarnSleep(100) || A_TickCount >= deadline)
            return EarnFail("MCT: 상태 갱신 화면 미확인")
    }
}

EarnTaskMCTEnd() {
    global config
    if (config["Settings"].Get("EarnMCTOnly", 0))
        return EarnUIReady("mct_title", [0.3,0,0.7,0.1]) || EarnFail("MCT 전용: 목록 복귀 미확인")
    return EarnMCTClose()
}

EarnDJSwapLoop(pop) {
    global config
    Loop 10 {
        pop := EarnPopularityMCTPct()
        if (pop < 0)
            return EarnFail("DJ: MCT 인기도 미확인")
        if (!EarnDJNeedsRebook(pop, config["Settings"]["EarnDJPopularityPct"]))
            return true
        if (!EarnUIClick("mct_nightclub_card", 520, 525)
            || !EarnWaitSeen("nc_dj_menu", "", 5000)
            || !EarnUIClick("nc_dj_menu", 495, 759)
            || !EarnWaitSeen("dj_solomun", "", 5000))
            return EarnFail("DJ: 목록 이동 실패")
        ; 캡처로 확인한 $10,000 Rebook만 클릭. 신규 고용은 선택하지 않는다.
        area := [0.38, 0.50, 0.603, 0.58]
        rebook := "dj_rebook_10k"
        resident := "dj_resident"
        targetX := 1100, confirmation := "dj_confirm_solomun"
        if (!EarnSeen(rebook, area)) {
            area := [0.61, 0.50, 0.835, 0.58]
            rebook := "dj_rebook_10k_right"
            resident := "dj_resident_right"
            targetX := 1540, confirmation := "dj_confirm_tale"
        }
        if (!EarnSeen(rebook, area))
            return EarnFail("DJ: 기존 DJ $10,000 재고용 버튼 없음")
        if (!EarnUIClick(rebook, targetX, 584, area)
            || !EarnWaitSeen(confirmation, "", 3000)
            || !EarnUIClick(confirmation, 1160, 628)
            || !EarnWaitGone(confirmation, "", 15000)
            || !EarnWaitSeen(resident, area, 5000))
            return EarnFail("DJ: 교체 결과 미확인")
        if (!EarnUIClick("nc_home", 495, 596)
            || !EarnSleep(500) || !EarnUIBackToMCT("nc_dj_menu", 1))
            return false
        updated := EarnPopularityMCTPct()
        EarnLog("DJ: 인기도 " pop " → " updated)
        if (updated <= pop)
            return EarnFail("DJ: 교체 후 인기도 증가 미확인")
    }
    return EarnFail("DJ: 교체 10회 제한")
}

EarnUIReady(name, area := "") {
    return !EarnAborted() && EarnSeen(name, area)
}

EarnDJNeedsRebook(pop, target := 95) {
    return pop >= 0 && pop < target
}

; 현재 확인된 웹 화면에서만 클릭. 해상도가 달라지면 템플릿 확인에서 중단.
EarnUIClick(guard, x, y, area := "") {
    if (!EarnUIReady(guard, area))
        return EarnFail("MCT 클릭 전 확인 실패: " guard)
    hwnd := IsGTAActive()
    previous := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        if (cw != 1920 || ch != 1080)
            return EarnFail("MCT: 미지원 해상도")
        DllCall("SetCursorPos", "int", cx+x, "int", cy+y)
        if (!EarnSleep(80))
            return false
        if (!EarnUIReady(guard, area))
            return EarnFail("MCT: 커서 이동 후 화면 확인 실패: " guard)
        SendEvent("{Blind}{LButton down}")
        try {
            Sleep(100)
        } finally {
            SendEvent("{Blind}{LButton up}")
        }
        DllCall("SetCursorPos", "int", cx+40, "int", cy+130)
        return EarnSleep(450)
    } finally {
        DllCall("SetThreadDpiAwarenessContext", "ptr", previous, "ptr")
    }
}

EarnUIClearCursor() {
    if (EarnAborted())
        return false
    hwnd := IsGTAActive()
    previous := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        DllCall("SetCursorPos", "int", cx+40, "int", cy+130)
        return EarnSleep(100)
    } finally {
        DllCall("SetThreadDpiAwarenessContext", "ptr", previous, "ptr")
    }
}

EarnUIBackToMCT(guard, maxPress) {
    Loop maxPress {
        if (EarnSeen("mct_title", [0.3, 0, 0.7, 0.1]))
            return true
        if (!EarnUIReady(guard) || !EarnPress("Backspace") || !EarnSleep(650))
            return false
    }
    return EarnWaitSeen("mct_title", [0.3, 0, 0.7, 0.1], 3000)
}

EarnDispatchTask() {
    return EarnFail("현장 파견: 아직 만들지 않음")
}
