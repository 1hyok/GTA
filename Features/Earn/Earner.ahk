; === 수익 자동화 스케줄러 (벙커 보급 · DJ 교체 · 나이트클럽 금고 · 현장 파견) ===
; 단축키(기본 F9) 두 번으로 켜고 끈다. End(전체 멈춤)도 끈다. 켜 두면 5초마다 할 일을 보고, 때가 된 것 하나를 끝까지 한 뒤 다음으로 넘어간다.
; 한 번에 하나만 한다: 금고 가느라 부동산을 떠나 있는 동안 벙커 보급은 멈췄다가, 돌아와 터미널이 열리는 것을 확인한 뒤 이어서 한다.
; 사용자가 키보드·마우스를 만지는 동안(EarnUserIdleSec 초 안)은 시작하지 않는다. 다른 도구가 게임에 키를 보내는 동안도 같다.
; 어느 단계든 화면 확인이 안 되면 자동화 전체를 끄고(멈춤 까닭은 %TEMP%\gta-earn.log·오버레이·설정 창) AFK 방지는 켜 둔다.
; 거점은 아케이드 지하 마스터 컨트롤 터미널(MCT) 앞이다. 켜기 전에 캐릭터를 MCT 앞("Press E" 안내가 보이는 자리)에 세워 둔다.
global gEarnOn := false
global gEarnDue := Map()        ; 작업 id → 다음 실행 시각(A_TickCount)
global gEarnDone := Map()       ; 작업 id → 켠 뒤 성공 횟수
global gEarnCurrent := ""       ; 지금 하는 작업 이름
global gEarnTasks := []
global gEarnNextDue := Map()   ; 작업이 스스로 정한 다음 실행 시각(A_TickCount). 없으면 시작 시각 + 간격
global gEarnSoftFails := Map()   ; 작업별 연속 "다시 하기" 횟수. EarnSoftFailMax 를 넘으면 그때 끈다

EarnTaskList() {
    global config
    s := config["Settings"]
    return [
        {id: "bunker", label: "벙커 보급", on: s["EarnBunker"], every: s["EarnBunkerIntervalSec"] * 1000, fn: EarnBunkerTask},
        {id: "dj", label: "DJ 교체", on: s["EarnDJ"], every: s["EarnDJIntervalMin"] * 60000, fn: EarnDJTask},
        {id: "safe", label: "나이트클럽 금고", on: s["EarnSafe"], every: s["EarnSafeIntervalMin"] * 60000, fn: EarnSafeTask},
        {id: "dispatch", label: "현장 파견", on: s["EarnDispatch"], every: s["EarnDispatchIntervalMin"] * 60000, fn: EarnDispatchTask}
    ]
}

ToggleEarner(*) {
    global gEarnOn
    SetEarner(!gEarnOn)
}

SetEarner(on, reason := "") {
    global gEarnOn, gEarnDue, gEarnDone, gEarnFail, gEarnTasks, gEarnNextDue, gEarnSoftFails, gEarnRetryIn, gEarnBusy, gAbort, gBunkerFullSince, config, afkOn
    gEarnOn := on
    if (on) {
        gEarnFail := ""
        gEarnTasks := EarnTaskList()
        gEarnDue := Map(), gEarnDone := Map(), gEarnNextDue := Map(), gEarnSoftFails := Map()
        gEarnRetryIn := 0
        gBunkerFullSince := 0
        now := A_TickCount
        s := config["Settings"]
        for t in gEarnTasks {
            gEarnDone[t.id] := 0
            ; 켜자마자 할 일: 벙커 보급·DJ 교체. 금고·파견은 설정한 첫 대기 뒤 (방금 비웠을 수 있으므로)
            first := t.id = "safe" ? s["EarnSafeFirstMin"] * 60000 : t.id = "dispatch" ? s["EarnDispatchFirstMin"] * 60000 : 0
            gEarnDue[t.id] := now + first
        }
        if (config["Features"]["AntiAFK"] && !afkOn)
            SetAntiAFK(true)
        SetTimer(EarnTick, 5000)
        ShowTooltip("💰 수익 자동화 켜짐 (" KeyLabelFor("Earner") " 두 번: 끄기, End: 멈춤)", 2500)
        EarnLog("켜짐: " EarnEnabledText())
    } else {
        SetTimer(EarnTick, 0)
        ; 작업이 도는 중이면 그 자리에서 멈추게 한다 (End 와 같게). 안 그러면 F9 로 꺼도 하던 작업이 끝까지 키를 보낸다
        if (gEarnBusy)
            gAbort := true
        ShowTooltip("💰 수익 자동화 꺼짐" (reason = "" ? "" : ": " reason), 3000)
        EarnLog("꺼짐" (reason = "" ? "" : ": " reason))
    }
}

EarnEnabledText() {
    global gEarnTasks
    list := ""
    for t in gEarnTasks
        if (t.on)
            list .= (list = "" ? "" : ", ") t.label
    return list = "" ? "켜진 작업 없음" : list
}

EarnTick() {
    global gEarnOn, gEarnBusy, gEarnDue, gEarnDone, gEarnTasks, gEarnCurrent, gEarnFail, gEarnNextDue, gEarnSoftFails, gEarnRetryIn, gAbort, config, GTA_WIN, afkOn
    if (!gEarnOn || gEarnBusy)
        return
    if (!WinExist(GTA_WIN))
        return
    ; 사람이 쓰는 중이면 기다린다 (다른 도구가 보내는 키도 여기에 잡힌다)
    if (A_TimeIdle < config["Settings"]["EarnUserIdleSec"] * 1000)
        return
    ; 다른 매크로가 게임에 키를 보내는 중이면 기다린다
    if (EarnOtherMacroBusy())
        return
    now := A_TickCount
    task := ""
    for t in gEarnTasks {
        if (t.on && gEarnDue[t.id] <= now) {
            task := t
            break
        }
    }
    if (!IsObject(task))
        return
    if (!IsGTAActive() && !BringGTAToFront()) {
        EarnLog(task.label ": GTA 를 앞으로 가져오지 못해 30초 뒤 다시")
        gEarnDue[task.id] := now + 30000
        return
    }
    gEarnBusy := true
    gAbort := false
    gEarnCurrent := task.label
    startTick := A_TickCount
    ok := false
    EarnLog("시작: " task.label)
    try {
        ok := task.fn.Call()
    } catch as e {
        ok := EarnFail(task.label " 오류: " e.Message " (" e.File ":" e.Line ")")
    } finally {
        ReleaseHeldKeys()
        gEarnBusy := false
        gEarnCurrent := ""
    }
    if (ok) {
        gEarnSoftFails[task.id] := 0
        gEarnRetryIn := 0
        ; 주기는 작업을 시작한 때부터 잰다(작업에 든 시간은 주기에서 빠진다). 작업이 다음 시각을 따로 정했으면(벙커: 구매한 순간부터 28분) 그 값을 쓴다
        gEarnDue[task.id] := gEarnNextDue.Has(task.id) ? gEarnNextDue.Delete(task.id) : startTick + task.every
        gEarnDone[task.id] += 1
        EarnLog("끝: " task.label " (" gEarnDone[task.id] "회째, 다음 " FormatTime(DateAdd(A_Now, Max(0, gEarnDue[task.id] - A_TickCount) // 1000, "Seconds"), "HH:mm:ss") ")")
        return
    }
    ; 위험하지 않은 실패(길을 못 찾음·재접속 자리가 나쁨)는 작업이 gEarnRetryIn 을 채워 두었다 → 끄지 않고 그때 다시 한다. 연속 EarnSoftFailMax 번이면 그때 끈다
    if (gEarnRetryIn) {
        n := gEarnSoftFails.Get(task.id, 0) + 1
        gEarnSoftFails[task.id] := n
        if (n <= config["Settings"]["EarnSoftFailMax"]) {
            gEarnDue[task.id] := A_TickCount + gEarnRetryIn
            EarnLog(task.label ": 이번엔 못 함 (" gEarnFail ") → " Round(gEarnRetryIn / 60000) "분 뒤 다시 (" n "/" config["Settings"]["EarnSoftFailMax"] ")")
            ShowTooltip("💰 " task.label ": " Round(gEarnRetryIn / 60000) "분 뒤 다시 (" n "/" config["Settings"]["EarnSoftFailMax"] ")", 4000)
            gEarnRetryIn := 0
            return
        }
        gEarnRetryIn := 0
    }
    ; 실패: 전부 끄고 AFK 방지는 켜 둔다
    why := gEarnFail = "" ? task.label " 확인 실패" : gEarnFail
    SetEarner(false, why)
    gEarnFail := why
    if (config["Features"]["AntiAFK"] && !afkOn)
        SetAntiAFK(true)
    ShowTooltip("⚠ 수익 자동화 멈춤: " why, 8000)
}

; 다른 매크로가 게임에 키를 보내는 중이면 true. 작텔(Alt+F4·MC·스팀 봇)은 IsTeleportRunning 이 묶어서 본다
EarnOtherMacroBusy() {
    global clawLoopRunning, gMenuBusy
    return (IsSet(clawLoopRunning) && clawLoopRunning) || (IsSet(gMenuBusy) && gMenuBusy)
        || IsTeleportRunning() || AnyInputToggleOn()
}

; 오버레이·설정 창 한 줄 상태
EarnStatusText() {
    global gEarnOn, gEarnDue, gEarnTasks, gEarnCurrent, gEarnFail
    if (!gEarnOn)
        return gEarnFail = "" ? "" : "수익 멈춤: " gEarnFail
    if (gEarnCurrent != "")
        return "수익: " gEarnCurrent " 진행 중"
    nextLabel := "", nextIn := 0
    for t in gEarnTasks {
        if (!t.on)
            continue
        left := gEarnDue[t.id] - A_TickCount
        if (nextLabel = "" || left < nextIn)
            nextLabel := t.label, nextIn := left
    }
    if (nextLabel = "")
        return "수익: 켜진 작업 없음"
    sec := Max(0, Ceil(nextIn / 1000))
    return "수익: 다음 " nextLabel " " Format("{:d}:{:02d}", sec // 60, Mod(sec, 60)) " 뒤"
}
