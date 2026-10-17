; === GTA 메모리 보호 ===
; 1010 14:21 GTA5_Enhanced 가 14시간 넘게 돌며 가상 메모리(커밋)를 66GB 까지 키웠고, 커밋 한도(RAM 31GB + 페이지 파일 32GB)에
; 닿은 직후 블루스크린(0x13A)으로 PC 가 재부팅돼 매크로와 GTA 가 함께 죽었다.
; 1분마다 시스템 커밋 사용률과 GTA 개인 메모리를 재서 %TEMP%\gta-mem.log 에 10분마다(단계가 바뀌면 바로) 남긴다.
; 사용률이 MemWarnPct(기본 80) 이상이면 한 번 알리고, 5%p 아래까지 회복해야 다시 알린다. MemClosePct 도달은 별도 상향 경고다.
; MemClosePct(기본 92) 이상이면서 GTA 가 MemCloseMinGB(기본 25)
; 이상을 쥐고 있으면 수익 자동화를 끄고 GTA 를 닫는다. PC 전체가 죽는 것보다 게임만 닫히는 쪽이 낫다. MemClosePct 0 이면 닫지 않는다.
global gMemGuardLevel := "ok"
global gMemGuardLastLog := 0
global gMemGuardPID := 0
global gMemGuardWarning := "ok"
global gMemGuardCreated := 0, gMemGuardPolicy := ""
global gMemGuardStatePath := A_Temp "\gta-mem-state.txt"
global gMemGuardPrevGB := -1, gMemGuardPrevTick := 0
global gMemGuardNotePath := A_Temp "\gta-mem-note.txt"

MemGuardLevel(commitPct, gtaGB, warnPct, closePct, minGB) {
    if (closePct > 0 && commitPct >= closePct && gtaGB >= minGB)
        return "close"
    if (warnPct > 0 && commitPct >= warnPct)
        return "warn"
    return "ok"
}

; 측정 단계와 별개로 이번 메모리 압박 구간의 최고 알림 단계를 유지한다. 보호 종료 판정에는 쓰지 않는다.
MemGuardWarningLevel(commitPct, warnPct, closePct, previous) {
    if (warnPct <= 0 || commitPct <= Max(0, warnPct - 5))
        return "ok"
    if (commitPct >= warnPct && closePct > 0 && commitPct >= closePct)
        return "high"
    if (commitPct >= warnPct && previous = "ok")
        return "warn"
    return previous
}

; 프로세스 내용은 읽지 않는다. PID 재사용을 구분하는 OS 생성 FILETIME만 조회한다.
MemGuardProcessCreated(pid) {
    h := DllCall("OpenProcess", "uint", 0x1000, "int", false, "uint", pid, "ptr")
    if (!h)
        return 0
    try {
        times := Buffer(32, 0)
        if (!DllCall("GetProcessTimes", "ptr", h, "ptr", times, "ptr", times.Ptr + 8,
            "ptr", times.Ptr + 16, "ptr", times.Ptr + 24))
            return 0
        return NumGet(times, 0, "int64")
    } finally {
        DllCall("CloseHandle", "ptr", h)
    }
}

MemGuardUtcNow() {
    time := Buffer(8, 0)
    DllCall("GetSystemTimeAsFileTime", "ptr", time)
    return NumGet(time, 0, "int64")
}

; 저장 형식: v1|PID|생성 FILETIME|관측 FILETIME|warnPct|closePct|minGB|alert.
; 15분 넘게 관측이 비었거나 정책이 바뀌면 새 측정으로 경고한다. 보호 종료는 이 이력과 무관하다.
MemGuardParseState(text, pid, created, policy, now) {
    fields := StrSplit(Trim(text, "`r`n"), "|")
    if (fields.Length != 8 || fields[1] != "v1"
        || !RegExMatch(fields[2], "^[1-9][0-9]{0,9}\z") || fields[2] > 4294967295
        || !RegExMatch(fields[3], "^[1-9][0-9]{0,17}\z")
        || !RegExMatch(fields[4], "^[1-9][0-9]{0,17}\z"))
        return ""
    for index in [5, 6, 7] {
        if (!RegExMatch(fields[index], "^(?:0|[1-9][0-9]{0,3})(?:\.[0-9]{1,6})?\z")
            || fields[index] > (index = 7 ? 4096 : 100))
            return ""
    }
    if (fields[2] != pid || fields[3] != created || created <= 0 || created > fields[4]
        || fields[4] > now || now - fields[4] > 9000000000
        || (fields[5] "|" fields[6] "|" fields[7]) != policy
        || !RegExMatch(fields[8], "^(ok|warn|high)\z")
        || (fields[8] != "ok" && fields[5] = 0)
        || (fields[8] = "high" && fields[6] = 0))
        return ""
    return fields[8]
}

MemGuardLoadState(path, pid, created, policy, now) {
    if (!FileExist(path))
        return "ok"
    try {
        if (InStr(FileGetAttrib(path), "R"))
            throw Error("read-only state cannot track recovery")
        if (FileGetSize(path) > 512)
            throw Error("state exceeds 512 bytes")
        warning := MemGuardParseState(FileRead(path, "UTF-8"), pid, created, policy, now)
        if (warning = "")
            throw Error("identity, policy, time or format mismatch")
        return warning
    } catch as err {
        MemGuardLog("경고 이력 무시: " err.Message)
        return "ok"
    }
}

MemGuardSaveState(path, pid, created, policy, warning, now) {
    text := "v1|" pid "|" created "|" now "|" policy "|" warning
    if (MemGuardParseState(text, pid, created, policy, now) = "")
        return false
    tmp := path "." DllCall("GetCurrentProcessId") ".tmp"
    try {
        stateFile := FileOpen(tmp, "w", "UTF-8-RAW")
        try {
            if (stateFile.Write(text) != StrLen(text))
                throw Error("incomplete state write")
        }
        finally stateFile.Close()
        FileMove(tmp, path, 1)
        return true
    } catch as err {
        ; 실패한 회복 기록보다 오래된 억제 상태를 다음 Main이 읽지 않도록 가능한 경우 폐기한다.
        try FileDelete(path)
        MemGuardLog("경고 이력 저장 실패(다음 측정에서 재시도): " err.Message)
        return false
    } finally {
        try FileDelete(tmp)
    }
}

MemGuardForgetState(path) {
    if (!FileExist(path))
        return
    try FileDelete(path)
    catch as err
        MemGuardLog("경고 이력 삭제 실패: " err.Message)
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

; 0925 실측: 외장 1080p 모니터에서는 GTA 커밋이 분당 2~6MB, 노트북 패널(2560x1600)로 옮긴 뒤 125~140MB 늘었다(두 짧은 구간).
; 화면 상태별 증가 속도를 가르려고 모니터 수, GTA 창 위치·크기, 앞 창 여부를 함께 남긴다.
MemGuardDisplayNote() {
    global GTA_WIN
    note := "모니터 " MonitorGetCount()
    try {
        WinGetPos(&x, &y, &w, &h, GTA_WIN)
        note .= ", 창 " x "," y " " w "x" h
    }
    try note .= WinActive(GTA_WIN) ? ", 앞" : ", 뒤"
    return note
}

; 10분 기록에 붙는 맥락: 직전 기록 대비 GTA 증가 속도(MB/분), 수익 자동화 상태, 사용자 메모.
; 1016 실측: GTA 커밋은 캐릭터가 밖에 있을 때만 분당 110~160MB 늘고 실내(테러바이트·사업장)에 있으면 멈춘다.
; 세션 종류(초대 전용·공개)처럼 매크로가 모르는 조건은 사용자가 %TEMP%\gta-mem-note.txt 첫 줄에 적어 두면 그대로 붙는다.
MemGuardRateNote(gtaGB) {
    global gMemGuardPrevGB, gMemGuardPrevTick
    note := ""
    if (gMemGuardPrevGB >= 0 && gtaGB >= 0 && gMemGuardPrevTick) {
        elapsedMin := (A_TickCount - gMemGuardPrevTick) / 60000
        if (elapsedMin >= 0.5)
            note := "증가 " Round((gtaGB - gMemGuardPrevGB) * 1024 / elapsedMin) "MB/분"
    }
    gMemGuardPrevGB := gtaGB
    gMemGuardPrevTick := A_TickCount
    return note
}

MemGuardEarnNote() {
    global gEarnOn, gEarnBusy, gEarnCurrent
    if (!IsSet(gEarnOn) || !gEarnOn)
        return "수익 꺼짐"
    task := IsSet(gEarnCurrent) && gEarnCurrent != "" ? gEarnCurrent : (IsSet(gEarnBusy) && gEarnBusy ? "작업 중" : "대기")
    return "수익 켜짐(" task ")"
}

MemGuardUserNote() {
    global gMemGuardNotePath
    try {
        if (!FileExist(gMemGuardNotePath) || FileGetSize(gMemGuardNotePath) > 4096)
            return ""
        text := Trim(StrSplit(FileRead(gMemGuardNotePath, "UTF-8"), "`n")[1], " `t`r")
        return text = "" ? "" : "메모 " SubStr(text, 1, 60)
    } catch {
        return ""
    }
}

MemGuardContextNote(gtaGB) {
    parts := []
    for part in [MemGuardRateNote(gtaGB), MemGuardEarnNote(), MemGuardUserNote()]
        if (part != "")
            parts.Push(part)
    note := ""
    for part in parts
        note .= (note = "" ? "" : ", ") part
    return note
}

MemGuardLog(msg) {
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " msg "`n", A_Temp "\gta-mem.log", "UTF-8")
}

MemGuardTick() {
    global config, gMemGuardLevel, gMemGuardLastLog, gMemGuardPID, gMemGuardWarning
    global gMemGuardCreated, gMemGuardPolicy, gMemGuardStatePath, gMemGuardPrevGB, gMemGuardPrevTick
    s := config["Settings"]
    pid := ProcessExist("GTA5_Enhanced.exe")
    created := pid ? MemGuardProcessCreated(pid) : 0
    now := MemGuardUtcNow()
    policy := s.Get("MemWarnPct", 80) "|" s.Get("MemClosePct", 92) "|" s.Get("MemCloseMinGB", 25)
    if (pid != gMemGuardPID || !pid || created != gMemGuardCreated || policy != gMemGuardPolicy) {
        gMemGuardPID := pid
        gMemGuardCreated := created
        gMemGuardPolicy := policy
        gMemGuardLevel := "ok"
        gMemGuardWarning := created > 0 ? MemGuardLoadState(gMemGuardStatePath, pid, created, policy, now) : "ok"
        gMemGuardLastLog := 0
        gMemGuardPrevGB := -1, gMemGuardPrevTick := 0
    }
    if (!pid) {
        MemGuardForgetState(gMemGuardStatePath)
        return
    }
    if (!MemGuardSystemCommit(&used, &limit))
        return
    gta := MemGuardProcessGB(pid)
    pct := Round(used * 100 / limit)
    level := MemGuardLevel(pct, gta, s.Get("MemWarnPct", 80), s.Get("MemClosePct", 92), s.Get("MemCloseMinGB", 25))
    warning := MemGuardWarningLevel(pct, s.Get("MemWarnPct", 80), s.Get("MemClosePct", 92), gMemGuardWarning)
    alertChanged := warning != gMemGuardWarning
    line := "커밋 " Round(used, 1) "/" Round(limit, 1) "GB(" pct "%), GTA " (gta < 0 ? "?" : Round(gta, 1)) "GB"
    if (level != gMemGuardLevel || alertChanged || !gMemGuardLastLog || A_TickCount - gMemGuardLastLog >= 600000) {
        MemGuardLog(line " " level " alert=" warning " " MemGuardDisplayNote() " " MemGuardContextNote(gta))
        gMemGuardLastLog := A_TickCount
    }
    gMemGuardLevel := level
    gMemGuardWarning := warning
    if (level = "close")
        MemGuardCloseGame(pid, line)
    else if (alertChanged && warning = "high")
        EarnLog("메모리 위험: " line ". 시스템 커밋이 보호 기준 이상. GTA 종료 조건 미충족, 전체 프로세스 메모리 확인 필요")
    else if (alertChanged && warning = "warn")
        EarnLog("메모리 경고: " line ". 시스템 전체 커밋 증가. GTA 단독 원인이나 누수로 확정하지 않음")
    if (created > 0)
        MemGuardSaveState(gMemGuardStatePath, pid, created, policy, warning, now)
}

MemGuardCloseGame(pid, line) {
    global gEarnOn, gEarnBusy
    EarnLog("메모리 보호: " line ", 블루스크린을 막으려고 수익 자동화를 끄고 GTA 를 닫음")
    ; F9 안전 정리 중에도 메모리 보호가 우선한다. 종료 사유를 남기고 정리 입력이 다시 시작되지 않게 한다.
    if (IsSet(gEarnOn) && (gEarnOn || (IsSet(gEarnBusy) && gEarnBusy)))
        SetEarner(false, "메모리 보호")
    ReleaseHeldKeys()
    ProcessClose(pid)
    left := ProcessWaitClose(pid, 30)
    MemGuardLog("GTA 종료 요청 pid=" pid " → " (left ? "30초 안에 안 닫힘" : "닫힘"))
}

SetTimer(MemGuardTick, 60000)
