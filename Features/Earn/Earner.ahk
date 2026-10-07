; === 수익 자동화 스케줄러 (Vinewood 금고·직원 파견 · 벙커 보급 · DJ 교체 · 창고 직원) ===
; 단축키(기본 F9) 두 번으로 켜고 끈다. End(전체 멈춤)도 끈다. 켜 두면 1초마다 할 일을 본다.
; 때가 된 벙커·DJ·창고는 MCT를 한 번 열어 묶어 처리하고 한 번 닫는다. 금고·앱 파견은 그다음 별도로 한다.
; 사용자 물리 입력이 EarnUserIdleSec 동안 없고 GTA가 앞일 때만 시작한다. 진행 중 사용자 입력·포커스 이탈 시 중단한다.
; 어느 단계든 화면 확인이 안 되면 자동화 전체를 끄고(멈춤 까닭은 %TEMP%\gta-earn.log·오버레이·설정 창) AFK 방지는 켜 둔다.
; 게임 종료·재시작 시 끄고, 사용자가 다시 켜야 새 게임 상태에서 예약을 시작한다.
global gEarnOn := false
global gEarnDue := Map()        ; 작업 id → 다음 실행 시각(A_TickCount)
global gEarnDone := Map()       ; 작업 id → 켠 뒤 성공 횟수
global gEarnCurrent := ""       ; 지금 하는 작업 이름
global gEarnSellNotice := ""    ; 창고 만재 3개 이상일 때 판매 필요 알림(EarnWarehouseSellNotice)
global gEarnTasks := []
global gEarnNextDue := Map()   ; 작업이 스스로 정한 다음 실행 시각(A_TickCount). 없으면 시작 시각 + 간격
global gEarnSoftFails := Map()   ; 작업별 연속 "다시 하기" 횟수. EarnSoftFailMax 를 넘으면 그때 끈다
global gEarnGuardArmed := false
global gEarnGuardStartedTick := 0
global gEarnUserAbort := false
global gEarnInputGuard := EarnInputAllowed
global gEarnGamePID := 0

EarnTaskList() {
    global config
    s := config["Settings"]
    return [
        {id: "bunker", label: "벙커 보급", on: s["EarnBunker"], every: s["EarnBunkerIntervalSec"] * 1000, fn: EarnBunkerTask},
        {id: "dj", label: "DJ 교체", on: s["EarnDJ"], every: s["EarnDJIntervalMin"] * 60000, fn: EarnDJTask},
        {id: "warehouse", label: "창고 직원", on: s.Get("EarnWarehouse", 1), every: s.Get("EarnWarehouseIntervalMin", 10) * 60000, fn: EarnWarehouseTask},
        {id: "safe", label: "사업장 금고", on: s["EarnSafe"], every: s["EarnSafeIntervalMin"] * 60000, fn: EarnVinewoodSafeTask},
        {id: "staff", label: "앱 직원 파견", on: s.Get("EarnBailAgents", 1) || s.Get("EarnCargoStaff", 1) || s.Get("EarnHangarStaff", 1), every: s.Get("EarnStaffIntervalMin", 5) * 60000, fn: EarnVinewoodStaffTask},
        {id: "dispatch", label: "현장 파견", on: s["EarnDispatch"] && !s.Get("EarnMCTOnly", 0), every: s["EarnDispatchIntervalMin"] * 60000, fn: EarnDispatchTask}
    ]
}

ToggleEarner(*) {
    global gEarnOn
    SetEarner(!gEarnOn)
}

SetEarner(on, reason := "") {
    global gEarnOn, gEarnDue, gEarnDone, gEarnFail, gEarnTasks, gEarnNextDue, gEarnSoftFails, gEarnRetryIn, gEarnBusy, gAbort, gEarnGamePID, gEarnBunkerFull, config, afkOn
    if (on) {
        gEarnGamePID := EarnGamePID()
        if (!gEarnGamePID)
            on := false, reason := "GTA 게임 창 없음. 게임에 들어간 뒤 다시 켜기"
    }
    gEarnOn := on
    if (on) {
        InstallKeybdHook()
        InstallMouseHook()
        gEarnFail := ""
        gEarnTasks := EarnTaskList()
        gEarnDue := Map(), gEarnDone := Map(), gEarnNextDue := Map(), gEarnSoftFails := Map()
        gEarnRetryIn := 0
        ; 끈 사이에 벙커를 팔았을 수 있다. 첫 확인은 벙커 카드로 새로 읽는다.
        gEarnBunkerFull := false
        now := A_TickCount
        s := config["Settings"]
        for t in gEarnTasks {
            gEarnDone[t.id] := 0
            ; 창고·벙커·DJ는 즉시 확인. 금고와 파견은 설정한 첫 대기를 따른다.
            first := t.id = "safe" ? s["EarnSafeFirstMin"] * 60000 : t.id = "dispatch" ? s["EarnDispatchFirstMin"] * 60000 : 0
            gEarnDue[t.id] := now + first
        }
        if (config["Features"]["AntiAFK"] && !afkOn)
            SetAntiAFK(true)
        SetTimer(EarnTick, 1000)
        if (s["EarnSafe"])
            SetTimer(EarnSafeFeedWatch, 4000)
        ShowTooltip("💰 수익 자동화 켜짐 (" KeyLabelFor("Earner") " 두 번: 끄기, End: 멈춤)", 2500)
        EarnLog("켜짐: " EarnEnabledText())
    } else {
        SetTimer(EarnTick, 0)
        SetTimer(EarnSafeFeedWatch, 0)
        if (reason != "")
            gEarnFail := reason
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
    global gEarnOn, gEarnBusy, gEarnDue, gEarnDone, gEarnTasks, gEarnCurrent, gEarnFail, gEarnNextDue, gEarnSoftFails, gEarnRetryIn, gAbort, gEarnGamePID, gEarnUserAbort, config, afkOn
    if (!gEarnOn || gEarnBusy)
        return
    if (!gEarnGamePID || EarnGamePID() != gEarnGamePID) {
        SetEarner(false, "GTA 종료 또는 재시작 감지. 현재 화면을 확인하고 다시 켜기")
        return
    }
    ; 실제 사용자 입력을 기다린다. 자동 입력은 물리 유휴 시간을 초기화하지 않는다.
    if (A_TimeIdlePhysical < config["Settings"]["EarnUserIdleSec"] * 1000)
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
    ; 시작 시점에 실행할 차례이거나 EarnMCTBatchAheadSec(기본 120초) 안에 차례가 될 MCT 작업을 묶는다. 진행 중 새로 due가 된 작업은 다음 회차다.
    ; 1005 14:10·14:20 에 DJ 가 묶음을 정한 순간보다 몇 초 늦게 due 가 되어, 창고만 하고 나온 뒤 1분 안에 나이트클럽에 다시 들어갔다.
    mctSession := EarnIsMCTTask(task.id)
    dueTasks := [task]
    if (mctSession) {
        dueTasks := []
        ahead := config["Settings"].Get("EarnMCTBatchAheadSec", 120) * 1000
        for t in gEarnTasks {
            if (t.on && EarnIsMCTTask(t.id) && gEarnDue[t.id] <= now + ahead)
                dueTasks.Push(t)
        }
    }
    if (!IsGTAActive()) {
        EarnLog(task.label ": GTA 포커스가 돌아오면 다시 (30초 대기)")
        gEarnDue[task.id] := now + 30000
        return
    }
    try inputLock := EarnInputLockAcquire()
    catch as e {
        SetEarner(false, "입력 잠금 오류: " e.Message)
        return
    }
    if (!IsObject(inputLock))
        return
    gEarnBusy := true
    gAbort := false
    gEarnUserAbort := false
    gEarnCurrent := task.label
    ; 이 작업이 보내는 키를 방치 판정(AFKOthersIdleMs)이 남의 입력으로 세지 않게 한다. 안 그러면 몇 분마다 도는 MCT 작업 때문에
    ; 방치 5분에 닿지 못해 CPU 부스트·프레임 제한이 한 번도 안 걸렸다(1005 13:10~16:30, 핫스팟 95°C. 제한 때는 62~67°C).
    try %"AFKSelfInput"%(true)
    outcome := {results: [], cleanupOK: true}
    fatalReason := ""
    try {
        EarnInputGuardStart()
        if (EarnInputAllowed()) {
            if (mctSession)
                outcome := EarnRunMCTBatch(dueTasks)
            else
                outcome.results.Push(EarnRunScheduledTask(task))
        }
        ; 마지막 단계에서 사용자가 개입한 경우 성공/자동 재시도로 덮지 않는다.
        if (!EarnInputAllowed()) {
            fatalReason := gEarnFail = "" ? task.label " 중단" : gEarnFail
            gEarnRetryIn := 0
        }
    } catch as e {
        fatalReason := task.label " 오류: " e.Message " (" e.File ":" e.Line ")"
        EarnFail(fatalReason)
    } finally {
        try {
            EarnInputGuardStop()
            ReleaseHeldKeys()
        } finally {
            try %"AFKSelfInput"%(false)
            gEarnBusy := false
            gEarnCurrent := ""
            EarnInputLockRelease(inputLock)
        }
    }
    ; 사용자가 손을 댄 중단은 끄지 않고 3분 뒤 다시 한다. 다음 시도도 손을 뗀 뒤에만 시작하고,
    ; MCT 작업은 시작할 때 위치를 다시 확인하므로 정리가 덜 됐어도 여기서 멈추지 않는다.
    ; (1004 18:36 사용자가 잠깐 만져 자동화가 통째로 꺼졌다. 밤새 켜 두는 용도라 매번 F9 를 다시 눌러야 했다)
    if (gEarnUserAbort) {
        gAbort := false
        finished := Map()
        for result in outcome.results {
            if (result.ok) {
                EarnFinishScheduledTask(result)
                finished[result.task.id] := true
            }
        }
        for t in dueTasks {
            if (finished.Has(t.id))
                continue
            if (gEarnNextDue.Has(t.id))
                gEarnNextDue.Delete(t.id)
            gEarnDue[t.id] := A_TickCount + 3 * 60000
        }
        EarnLog(task.label ": 사용자 입력 또는 GTA 포커스 이탈로 중단 → 3분 뒤 다시")
        ShowTooltip("💰 사용자 입력으로 중단 → 3분 뒤 다시", 4000)
        return
    }
    if (fatalReason != "" || !outcome.cleanupOK) {
        why := fatalReason != "" ? fatalReason : "MCT 정리 실패: " (gEarnFail = "" ? "종료 또는 CEO 해제 미확인" : gEarnFail)
        EarnStopAfterFailure(why)
        return
    }
    ; 재시도로 미룬 작업이 있어도 묶음의 나머지 결과를 마저 확정한다. 자동화가 꺼졌을 때만 멈춘다.
    for result in outcome.results {
        EarnFinishScheduledTask(result)
        if (!gEarnOn)
            return
    }
}

EarnIsMCTTask(id) {
    return id = "bunker" || id = "dj" || id = "warehouse"
}

; 각 본문은 자기 예약을 유지한다. 완료 횟수·최종 로그는 공동 MCT 정리가 끝난 뒤 확정한다.
EarnRunScheduledTask(task, mctSession := false) {
    global gEarnCurrent, gEarnFail, gEarnRetryIn
    result := {task: task, startTick: A_TickCount, ok: false, retryIn: 0, reason: ""}
    gEarnCurrent := task.label
    gEarnRetryIn := 0
    gEarnFail := ""
    try {
        EarnLog("시작: " task.label)
        if (EarnInputAllowed())
            result.ok := mctSession ? task.fn.Call(false) : task.fn.Call()
    } catch as e {
        EarnFail(task.label " 오류: " e.Message " (" e.File ":" e.Line ")")
    }
    if (!EarnInputAllowed()) {
        result.ok := false
        gEarnRetryIn := 0
    }
    result.reason := gEarnFail
    result.retryIn := result.ok ? 0 : gEarnRetryIn
    gEarnRetryIn := 0
    if (result.ok && mctSession)
        EarnLog("본문 완료: " task.label " (MCT 정리 대기)")
    return result
}

EarnRunMCTBatch(tasks) {
    global gEarnCurrent, gEarnFail, gEarnRetryIn
    outcome := {results: [], cleanupOK: true}
    opened := false
    currentTask := tasks[1]
    gEarnCurrent := "MCT 작업 묶음"
    gEarnFail := ""
    gEarnRetryIn := 0
    try {
        ; Begin은 진입 실패·예외를 자체 정리한다. 성공한 세션만 여기서 닫는다.
        opened := EarnTaskMCTBegin()
        if (opened) {
            for task in tasks {
                currentTask := task
                result := EarnRunScheduledTask(task, true)
                outcome.results.Push(result)
                if (!result.ok)
                    break
            }
        } else {
            ; 진입 전 위치 확인처럼 위험하지 않은 실패는 Begin 이 재시도 시간을 채워 둔다.
            ; 묶음의 작업 모두에 같은 결과를 남겨야 남은 작업이 다음 틱에 바로 다시 시도되지 않는다.
            for task in tasks
                outcome.results.Push({task: task, startTick: A_TickCount, ok: false, retryIn: gEarnRetryIn, reason: gEarnFail})
        }
    } catch as e {
        EarnFail("MCT 작업 오류: " e.Message " (" e.File ":" e.Line ")")
        outcome.results.Push({task: currentTask, startTick: A_TickCount, ok: false, retryIn: 0, reason: gEarnFail})
    } finally {
        if (opened) {
            try outcome.cleanupOK := EarnTaskMCTEnd()
            catch as e {
                outcome.cleanupOK := false
                EarnFail("MCT 정리 오류: " e.Message " (" e.File ":" e.Line ")")
            }
        }
        gEarnRetryIn := 0
    }
    return outcome
}

EarnFinishScheduledTask(result) {
    global gEarnDue, gEarnDone, gEarnSoftFails, gEarnNextDue, config
    task := result.task
    if (result.ok) {
        gEarnSoftFails[task.id] := 0
        ; 주기는 확인을 시작한 때부터 잰다. 작업이 현재 화면에서 정한 다음 확인 시각이 있으면 그 값을 쓴다.
        gEarnDue[task.id] := gEarnNextDue.Has(task.id) ? gEarnNextDue.Delete(task.id) : result.startTick + task.every
        gEarnDone[task.id] += 1
        secondsUntilDue := Floor(Max(0, gEarnDue[task.id] - A_TickCount) / 1000)
        EarnLog("끝: " task.label " (" gEarnDone[task.id] "회째, 다음 " FormatTime(DateAdd(A_Now, secondsUntilDue, "Seconds"), "HH:mm:ss") ")")
        return true
    }
    ; 위험하지 않은 실패(길을 못 찾음·재접속 자리가 나쁨)는 작업이 gEarnRetryIn 을 채워 두었다 → 끄지 않고 그때 다시 한다. 연속 EarnSoftFailMax 번이면 그때 끈다
    if (gEarnNextDue.Has(task.id))
        gEarnNextDue.Delete(task.id)
    if (result.retryIn) {
        n := gEarnSoftFails.Get(task.id, 0) + 1
        gEarnSoftFails[task.id] := n
        if (n <= config["Settings"]["EarnSoftFailMax"]) {
            gEarnDue[task.id] := A_TickCount + result.retryIn
            EarnLog(task.label ": 이번엔 못 함 (" result.reason ") → " Round(result.retryIn / 60000) "분 뒤 다시 (" n "/" config["Settings"]["EarnSoftFailMax"] ")")
            ShowTooltip("💰 " task.label ": " Round(result.retryIn / 60000) "분 뒤 다시 (" n "/" config["Settings"]["EarnSoftFailMax"] ")", 4000)
            return false
        }
    }
    EarnStopAfterFailure(result.reason = "" ? task.label " 확인 실패" : result.reason)
    return false
}

EarnStopAfterFailure(why) {
    global gEarnFail, config, afkOn
    ; 실패: 전부 끄고 AFK 방지는 켜 둔다
    SetEarner(false, why)
    gEarnFail := why
    if (config["Features"]["AntiAFK"] && !afkOn)
        SetAntiAFK(true)
    ShowTooltip("⚠ 수익 자동화 멈춤: " why, 8000)
}

; 물리 키보드/마우스 입력만 본다. 자동 클릭·카메라 입력은 유휴 시간을 초기화하지 않는다.
EarnInputGuardStart() {
    global gEarnGuardArmed, gEarnGuardStartedTick
    gEarnGuardStartedTick := A_TickCount
    gEarnGuardArmed := true
    SetTimer(EarnInputWatch, 25)
}

EarnInputGuardStop() {
    global gEarnGuardArmed
    gEarnGuardArmed := false
    SetTimer(EarnInputWatch, 0)
}

EarnInputWatch() {
    EarnInputAllowed()
}

EarnInputAllowed() {
    global gEarnGuardArmed, gEarnGuardStartedTick, gAbort, gEarnRetryIn, gEarnGamePID, gEarnUserAbort
    if (!gEarnGuardArmed)
        return !gAbort
    if (!gAbort && (!gEarnGamePID || EarnGamePID() != gEarnGamePID)) {
        gAbort := true
        gEarnRetryIn := 0
        EarnFail("GTA 종료 또는 재시작으로 중단. 현재 화면을 확인하고 다시 켜기")
        ReleaseHeldKeys()
    } else if (!gAbort && (A_TimeIdlePhysical < Max(1, A_TickCount - gEarnGuardStartedTick) || !IsGTAActive())) {
        ; 긴 OCR 호출 중 발생한 입력도 시작 이후 경과 시간과 비교해 감지한다.
        ; 끄지 않는다. EarnTick 이 3분 뒤로 미룬다.
        gAbort := true
        gEarnUserAbort := true
        gEarnRetryIn := 0
        EarnFail("사용자 입력 또는 GTA 포커스 이탈로 중단")
        ReleaseHeldKeys()
    }
    return !gAbort
}

EarnGamePID() {
    global GTA_WIN
    hwnd := WinExist(GTA_WIN)
    if (!hwnd)
        return 0
    try return WinGetPID("ahk_id " hwnd)
    catch
        return 0
}

; GUI 수신기는 이름의 존재로 배타화한다. 이 이름을 작업 동안 예약해 새 수신기 시작과의 경합도 막는다.
; 실제 검사는 별도 이름을 넘겨 현재 게임 입력 잠금에 닿지 않는다.
EarnInputLockAcquire(macroName := "Local\GtaMacroInput", guiName := "Local\GtaGuiInput") {
    guiHandle := DllCall("CreateMutexW", "ptr", 0, "int", 0, "str", guiName, "ptr")
    existed := A_LastError = 183
    if (!guiHandle)
        throw Error("GUI 입력 잠금을 만들지 못함")
    if (existed) {
        DllCall("CloseHandle", "ptr", guiHandle)
        return 0
    }
    macroHandle := 0
    try {
        macroHandle := DllCall("CreateMutexW", "ptr", 0, "int", 0, "str", macroName, "ptr")
        if (!macroHandle)
            throw Error("매크로 입력 잠금을 만들지 못함")
        acquired := DllCall("WaitForSingleObject", "ptr", macroHandle, "uint", 0, "uint")
        if (acquired = 0 || acquired = 0x80)
            return {macro: macroHandle, gui: guiHandle}
        if (acquired != 0x102)
            throw Error("매크로 입력 잠금 상태를 확인하지 못함")
    } catch as e {
        if (macroHandle)
            DllCall("CloseHandle", "ptr", macroHandle)
        DllCall("CloseHandle", "ptr", guiHandle)
        throw e
    }
    DllCall("CloseHandle", "ptr", macroHandle)
    DllCall("CloseHandle", "ptr", guiHandle)
    return 0
}

EarnInputLockRelease(inputLock) {
    try {
        DllCall("ReleaseMutex", "ptr", inputLock.macro)
    } finally {
        DllCall("CloseHandle", "ptr", inputLock.macro)
        DllCall("CloseHandle", "ptr", inputLock.gui)
    }
}

; 다른 매크로가 게임에 키를 보내는 중이면 true. 작텔(Alt+F4·MC·스팀 봇)은 IsTeleportRunning 이 묶어서 본다
EarnOtherMacroBusy() {
    global clawLoopRunning, gMenuBusy, gAFKBusy
    return (IsSet(clawLoopRunning) && clawLoopRunning) || (IsSet(gMenuBusy) && gMenuBusy)
        || (IsSet(gAFKBusy) && gAFKBusy)
        || IsTeleportRunning() || AnyInputToggleOn()
}

; 오버레이·설정 창 한 줄 상태
EarnStatusText() {
    global gEarnOn, gEarnDue, gEarnTasks, gEarnCurrent, gEarnFail, config
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
    if (nextIn <= 0) {
        if (!IsGTAActive())
            return "수익: GTA 포커스 대기"
        idleLeft := config["Settings"]["EarnUserIdleSec"] * 1000 - A_TimeIdlePhysical
        if (idleLeft > 0)
            return "수익: 입력 안정 대기 " Ceil(idleLeft / 1000) "초"
        if (EarnOtherMacroBusy())
            return "수익: 다른 매크로 종료 대기"
        return "수익: " nextLabel " 시작 대기"
    }
    sec := Max(0, Ceil(nextIn / 1000))
    return "수익: 다음 " nextLabel " " Format("{:d}:{:02d}", sec // 60, Mod(sec, 60)) " 뒤"
}
