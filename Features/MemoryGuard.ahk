; === GTA 메모리 보호 ===
; 1010 14:21 GTA5_Enhanced 가 14시간 넘게 돌며 가상 메모리(커밋)를 66GB 까지 키웠고, 커밋 한도(RAM 31GB + 페이지 파일 32GB)에
; 닿은 직후 블루스크린(0x13A)으로 PC 가 재부팅돼 매크로와 GTA 가 함께 죽었다.
; 1분마다 시스템 커밋 사용률과 GTA 개인 메모리를 재서 %TEMP%\gta-mem.log 에 10분마다(단계가 바뀌면 바로) 남긴다.
; 사용률이 MemWarnPct(기본 80) 이상이면 수익 로그에 한 번 알린다. MemClosePct(기본 92) 이상이면서 GTA 가 MemCloseMinGB(기본 25)
; 이상을 쥐고 있으면 수익 자동화를 끄고 GTA 를 닫는다. PC 전체가 죽는 것보다 게임만 닫히는 쪽이 낫다. MemClosePct 0 이면 닫지 않는다.
global gMemGuardLevel := "ok"
global gMemGuardLastLog := 0

MemGuardLevel(commitPct, gtaGB, warnPct, closePct, minGB) {
    if (closePct > 0 && commitPct >= closePct && gtaGB >= minGB)
        return "close"
    if (warnPct > 0 && commitPct >= warnPct)
        return "warn"
    return "ok"
}

; PERFORMANCE_INFORMATION(x64 104바이트): CommitTotal @8, CommitLimit @16, PageSize @80. 값은 페이지 수.
MemGuardSystemCommit(&usedGB, &limitGB) {
    buf := Buffer(104, 0)
    NumPut("uint", 104, buf, 0)
    if (!DllCall("psapi\GetPerformanceInfo", "ptr", buf, "uint", 104))
        return false
    page := NumGet(buf, 80, "uptr")
    usedGB := NumGet(buf, 8, "uptr") * page / 1073741824
    limitGB := NumGet(buf, 16, "uptr") * page / 1073741824
    return limitGB > 0
}

; PROCESS_MEMORY_COUNTERS_EX(x64 80바이트)의 PrivateUsage @72. 열 수 없으면 -1.
MemGuardProcessGB(pid) {
    h := DllCall("OpenProcess", "uint", 0x1000, "int", false, "uint", pid, "ptr")
    if (!h)
        return -1
    try {
        buf := Buffer(80, 0)
        NumPut("uint", 80, buf, 0)
        if (!DllCall("psapi\GetProcessMemoryInfo", "ptr", h, "ptr", buf, "uint", 80))
            return -1
        return NumGet(buf, 72, "uptr") / 1073741824
    } finally {
        DllCall("CloseHandle", "ptr", h)
    }
}

MemGuardLog(msg) {
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " msg "`n", A_Temp "\gta-mem.log", "UTF-8")
}

MemGuardTick() {
    global config, gMemGuardLevel, gMemGuardLastLog
    s := config["Settings"]
    pid := ProcessExist("GTA5_Enhanced.exe")
    if (!pid) {
        gMemGuardLevel := "ok"
        return
    }
    if (!MemGuardSystemCommit(&used, &limit))
        return
    gta := MemGuardProcessGB(pid)
    pct := Round(used * 100 / limit)
    level := MemGuardLevel(pct, gta, s.Get("MemWarnPct", 80), s.Get("MemClosePct", 92), s.Get("MemCloseMinGB", 25))
    line := "커밋 " Round(used, 1) "/" Round(limit, 1) "GB(" pct "%), GTA " (gta < 0 ? "?" : Round(gta, 1)) "GB"
    if (level != gMemGuardLevel || !gMemGuardLastLog || A_TickCount - gMemGuardLastLog >= 600000) {
        MemGuardLog(line " " level)
        gMemGuardLastLog := A_TickCount
    }
    changed := level != gMemGuardLevel
    gMemGuardLevel := level
    if (level = "warn" && changed)
        EarnLog("메모리 경고: " line ". 게임을 다시 켜 두는 것이 좋음")
    else if (level = "close")
        MemGuardCloseGame(pid, line)
}

MemGuardCloseGame(pid, line) {
    global gEarnOn
    EarnLog("메모리 보호: " line ", 블루스크린을 막으려고 수익 자동화를 끄고 GTA 를 닫음")
    if (IsSet(gEarnOn) && gEarnOn)
        SetEarner(false, "메모리 보호")
    ReleaseHeldKeys()
    ProcessClose(pid)
    left := ProcessWaitClose(pid, 30)
    MemGuardLog("GTA 종료 요청 pid=" pid " → " (left ? "30초 안에 안 닫힘" : "닫힘"))
}

SetTimer(MemGuardTick, 60000)
