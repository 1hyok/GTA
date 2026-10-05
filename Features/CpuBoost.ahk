; 수익 자동화가 켜져 있고 사람 입력이 CpuBoostIdleSec(기본 300초) 넘게 없을 때만 CPU 부스트를 끈다. 사람이 만지면 다음 확인(30초) 때 다시 켠다.
; 1005 실측: 방치 중 부스트 클럭으로 CPU 전력이 12W 에서 25~30W, 온도가 73°C 에서 95°C 까지 올랐다. 부스트를 끄자 12W·66~73°C.
; MCT 메뉴만 오가는 방치 작업은 부스트가 없어도 느려지지 않는다. CpuBoostIdleSec 을 0 으로 두면 이 기능은 아무것도 바꾸지 않는다.
global gCpuBoostState := ""

CpuBoostWanted(earnOn, idleMs, idleSec) => !(earnOn && idleSec > 0 && idleMs >= idleSec * 1000)

CpuBoostTick() {
    global gEarnOn, config, gCpuBoostState
    sec := config["Settings"].Get("CpuBoostIdleSec", 300)
    if (sec <= 0 && gCpuBoostState = "")
        return
    want := CpuBoostWanted(gEarnOn, Min(AFKPhysicalIdleMs(), AFKOthersIdleMs()), sec) ? "on" : "off"
    if (want = gCpuBoostState)
        return
    CpuBoostApply(want = "on")
    gCpuBoostState := want
    EarnLog("CPU 부스트 " (want = "on" ? "켬" : "끔(방치 중)"))
}

; 켬은 Windows 균형 조정 기본값(최대 상태 100%, 부스트 모드 AC 공격적 2·DC 사용 1), 끔은 99%·부스트 사용 안 함 0.
CpuBoostApply(on) {
    boost := "be337238-0d82-4146-a960-4f3749d470c7"
    pc := "powercfg /set{1}valueindex SCHEME_CURRENT SUB_PROCESSOR {2} {3}"
    cmds := [Format(pc, "ac", "PROCTHROTTLEMAX", on ? 100 : 99), Format(pc, "dc", "PROCTHROTTLEMAX", on ? 100 : 99),
        Format(pc, "ac", boost, on ? 2 : 0), Format(pc, "dc", boost, on ? 1 : 0), "powercfg /setactive SCHEME_CURRENT"]
    line := ""
    for c in cmds
        line .= (line = "" ? "" : " & ") c
    try Run(A_ComSpec ' /c ' line, , "Hide")
}

SetTimer(CpuBoostTick, 30000)
