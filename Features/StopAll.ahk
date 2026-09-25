; === 전체 멈춤 ===
; 돌고 있는 것을 전부 멈추고 누르고 있던 키를 뗀다. AFK 방지는 유지한다 (자리를 비운 채 멈춰 두는 용도이므로).
; gAbort 는 진행 중인 시퀀스(인형 뽑기 단계 대기·메뉴 매크로·세션 이동)에 즉시 멈추라는 신호다. 각 시퀀스가 시작할 때 false 로 되돌린다.
global gAbort := false

StopAll(reason := "hotkey") {
    global gAbort, clawLoopRunning, clickRunning, wRunning, shiftWRunning, vellumDrivingRunning, cayoTimerRunning
    gAbort := true
    stopped := []

    if (IsSet(clawLoopRunning) && clawLoopRunning) {
        clawLoopRunning := false
        stopped.Push("인형 반복")
    }
    if (IsSet(clickRunning) && clickRunning) {
        StopAutoClick()
        stopped.Push("자동 클릭")
    }
    if (IsSet(wRunning) && wRunning) {
        wRunning := false
        stopped.Push("걷기")
    }
    if (IsSet(shiftWRunning) && shiftWRunning) {
        shiftWRunning := false
        stopped.Push("달리기")
    }
    if (IsSet(vellumDrivingRunning) && vellumDrivingRunning) {
        vellumDrivingRunning := false
        SetTimer(PressLCtrlForVellum, 0)
        stopped.Push("벨럼")
    }
    if (IsSet(cayoTimerRunning) && cayoTimerRunning) {
        ToggleCayoPericoTimer()
        stopped.Push("카요 타이머")
    }
    ReleaseHeldKeys()

    list := ""
    for name in stopped
        list .= (list = "" ? "" : ", ") name
    MacroLog("stop", reason ": " (list = "" ? "멈출 것 없음" : list))
    if (reason != "exit")
        ShowTooltip(list = "" ? "⏹ 멈출 것 없음 (AFK 방지는 유지)" : "⏹ 전체 멈춤: " list " (AFK 방지는 유지)", 2000)
}
