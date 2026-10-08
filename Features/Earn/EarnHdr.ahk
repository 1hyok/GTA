; Windows DisplayConfig only. No hotkeys, window activation, or game input.
; SDK structures: microsoft/win32metadata generation/WinSDK/RecompiledIdlHeaders/um/wingdi.h
global gEarnHdrLease := "", gEarnHdrRestoring := false, gEarnHdrMutex := 0, gEarnHdrPreparing := false

EarnHdrBegin() {
    global gEarnHdrLease, gEarnHdrPreparing
    if (!EarnHdrRestore("이전 복원 대기"))
        throw Error("HDR 원래 상태 복원 미확인. 수익 입력 중단")
    if (!EarnHdrInputAllowed())
        return false
    gEarnHdrPreparing := true
    try {
    if (!EarnHdrLock())
        throw Error("다른 프로세스가 HDR 복원을 소유 중")
    target := EarnHdrTarget()
    state := EarnHdrRead(target)
    if (!state.enabled) {
        ready := EarnHdrWait(target, false, true)
        EarnHdrUnlock()
        if (!ready && EarnHdrInputAllowed())
            throw Error("원래 HDR OFF의 실제 화면 모드 안정화 미확인")
        return ready
    }
    journal := target.adapter "|" target.id "|" state.api "|" target.path
    EarnStateSet("hdr_restore", journal)
    if (EarnStateGet("hdr_restore") != journal)
        throw Error("HDR 원래 상태 저장 실패. 화면 변경 안 함")
    ; timer가 원래 상태를 복원·기록 삭제한 뒤 이 스레드가 늦게 OFF를 보내는 경합을 막는다.
    ; 동기 Windows API 안에서는 물리 입력을 취소할 수 없으므로 반환 즉시 guard로 중단·복원한다.
    previousCritical := A_IsCritical
    Critical("On")
    try {
        if (!EarnHdrInputAllowed())
            return false
        gEarnHdrLease := {target:target, api:state.api}
        if (!EarnHdrWrite(target, state.api, false))
            throw Error("HDR OFF 요청 실패")
    } finally {
        Critical(previousCritical)
    }
    if (!EarnHdrWait(target, false, true)) {
        if (!EarnHdrInputAllowed())
            return false
        throw Error("HDR OFF 전환 확인 시간 초과")
    }
    EarnLog("HDR: 실제 수익 작업 시작, 게임 디스플레이 OFF 확인")
    return true
    } finally {
        gEarnHdrPreparing := false
        if (!EarnHdrInputAllowed())
            EarnHdrRestore("준비 중 사용자 중단")
    }
}

EarnHdrWait(target, enabled, guarded) {
    deadline := A_TickCount + 5000, stable := 0
    Loop {
        if (guarded && !EarnHdrInputAllowed())
            return false
        state := EarnHdrRead(target)
        if (state.enabled = enabled && state.active = enabled) {
            if (!stable)
                stable := A_TickCount
            if (A_TickCount - stable >= 500)
                return true
        } else
            stable := 0
        if (A_TickCount >= deadline)
            return false
        Sleep(50)
    }
}

EarnHdrInputAllowed() {
    global gEarnInputGuard
    return IsSet(gEarnInputGuard) && gEarnInputGuard.Call()
}

EarnHdrRestore(reason := "작업 종료") {
    global gEarnHdrLease, gEarnHdrRestoring, gEarnHdrPreparing
    if (gEarnHdrRestoring || gEarnHdrPreparing)
        return false
    gEarnHdrRestoring := true
    try {
    ; 수정한 상태의 소유 OS mutex는 복원 확인까지 유지한다. 다른 Main/단발 시험은 저널을 읽거나 소비하지 않는다.
    if (!EarnHdrLock()) {
        SetTimer(EarnHdrRetryRestore, 1000)
        return false
    }
    journal := EarnStateGet("hdr_restore")
    if (!IsObject(gEarnHdrLease) && journal = "") {
        EarnHdrUnlock()
        SetTimer(EarnHdrRetryRestore, 0)
        return true
    }
        if (!IsObject(gEarnHdrLease)) {
            fields := StrSplit(journal, "|")
            if (fields.Length != 4 || !IsNumber(fields[1]) || !IsNumber(fields[2])
                || (fields[3] != "16" && fields[3] != "10") || fields[4] = "")
                throw Error("HDR 복원 기록 형식 오류")
            gEarnHdrLease := {target:{adapter:Integer(fields[1]), id:Integer(fields[2]), path:fields[4]}, api:Integer(fields[3])}
        }
        lease := gEarnHdrLease
        state := EarnHdrRead(lease.target)
        if (!state.enabled && !EarnHdrWrite(lease.target, lease.api, true))
            throw Error("HDR 원래 ON 요청 실패")
        if (!EarnHdrWait(lease.target, true, false))
            throw Error("HDR 원래 ON 확인 시간 초과")
        EarnStateSet("hdr_restore", "")
        if (EarnStateGet("hdr_restore") != "")
            throw Error("HDR 복원 기록 삭제 확인 실패")
        gEarnHdrLease := ""
        EarnHdrUnlock()
        SetTimer(EarnHdrRetryRestore, 0)
        EarnLog("HDR: 원래 ON 복원 확인 (" reason ")")
        return true
    } catch as e {
        EarnLog("HDR 복원 대기: " e.Message)
        SetTimer(EarnHdrRetryRestore, 1000)
        return false
    } finally {
        gEarnHdrRestoring := false
    }
}

EarnHdrRetryRestore() => EarnHdrRestore("복원 재확인")
EarnHdrExit(*) {
    global gEarnHdrPreparing
    ReleaseHeldKeys()
    ; OnExit로 끊긴 준비 스레드는 돌아오지 않으므로 종료 callback이 복원 소유권을 인계받는다.
    gEarnHdrPreparing := false
    EarnHdrRestore("프로세스 종료")
    return 0
}

EarnHdrLock() {
    global gEarnHdrMutex
    if (gEarnHdrMutex)
        return true
    handle := DllCall("CreateMutexW", "ptr",0,"int",0,"str","Local\GtaEarnHdrLease", "ptr")
    if (!handle)
        throw Error("HDR 복원 소유 잠금 생성 실패")
    code := DllCall("WaitForSingleObject", "ptr",handle,"uint",0,"uint")
    if (code = 0 || code = 0x80) {
        gEarnHdrMutex := handle
        return true
    }
    DllCall("CloseHandle", "ptr",handle)
    if (code != 0x102)
        throw Error("HDR 복원 소유 잠금 확인 실패")
    return false
}

EarnHdrUnlock() {
    global gEarnHdrMutex
    if (!gEarnHdrMutex)
        return
    DllCall("ReleaseMutex", "ptr",gEarnHdrMutex)
    DllCall("CloseHandle", "ptr",gEarnHdrMutex)
    gEarnHdrMutex := 0
}

EarnHdrPacket(type, size, target) {
    packet := Buffer(size, 0)
    NumPut("uint", type, "uint", size, "int64", target.adapter, "uint", target.id, packet)
    return packet
}

EarnHdrDevicePath(target) {
    packet := EarnHdrPacket(2, 420, target)
    code := DllCall("User32\DisplayConfigGetDeviceInfo", "ptr", packet, "int")
    if (code)
        throw Error("HDR 디스플레이 신원 조회 실패: " code)
    return StrGet(packet.Ptr+164, 128, "UTF-16")
}

EarnHdrRead(target) {
    if (EarnHdrDevicePath(target) != target.path)
        throw Error("HDR 디스플레이 신원 변경. 다른 디스플레이 변경 금지")
    packet := EarnHdrPacket(15, 36, target)
    code := DllCall("User32\DisplayConfigGetDeviceInfo", "ptr", packet, "int")
    if (!code)
        return {enabled:!!(NumGet(packet,20,"uint") & 32), active:NumGet(packet,32,"uint") = 2, api:16}
    if (code != 87 && code != 50)
        throw Error("HDR 상태 조회 실패: " code)
    packet := EarnHdrPacket(9, 32, target)
    code := DllCall("User32\DisplayConfigGetDeviceInfo", "ptr", packet, "int")
    if (code)
        throw Error("HDR 구버전 상태 조회 실패: " code)
    bits := NumGet(packet,20,"uint")
    if (bits & 4)
        throw Error("HDR와 WCG를 구별할 수 없어 변경 안 함")
    return {enabled:!!(bits & 2), active:!!(bits & 2), api:10}
}

EarnHdrWrite(target, api, enabled) {
    if (EarnHdrDevicePath(target) != target.path)
        throw Error("HDR 대상 디스플레이 변경")
    packet := EarnHdrPacket(api, 24, target)
    NumPut("uint", enabled ? 1 : 0, packet, 20)
    return DllCall("User32\DisplayConfigSetDeviceInfo", "ptr", packet, "int") = 0
}

EarnHdrTarget() {
    hwnd := IsGTAActive()
    if (!hwnd)
        throw Error("HDR 대상 GTA 포커스 없음")
    monitor := DllCall("User32\MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")
    info := Buffer(104, 0), NumPut("uint", 104, info)
    if (!monitor || !DllCall("User32\GetMonitorInfoW", "ptr", monitor, "ptr", info))
        throw Error("HDR 게임 모니터 확인 실패")
    device := StrGet(info.Ptr+40, 32, "UTF-16")
    Loop 3 {
        pathCount := 0, modeCount := 0
        code := DllCall("User32\GetDisplayConfigBufferSizes", "uint", 2, "uint*", &pathCount, "uint*", &modeCount, "int")
        if (code)
            throw Error("HDR 활성 디스플레이 수 조회 실패: " code)
        paths := Buffer(pathCount*72, 0), modes := Buffer(modeCount*64, 0)
        code := DllCall("User32\QueryDisplayConfig", "uint", 2, "uint*", &pathCount, "ptr", paths,
            "uint*", &modeCount, "ptr", modes, "ptr", 0, "int")
        if (code = 122)
            continue
        if (code)
            throw Error("HDR 활성 경로 조회 실패: " code)
        matches := []
        Loop pathCount {
            offset := (A_Index-1)*72
            source := {adapter:NumGet(paths,offset,"int64"),id:NumGet(paths,offset+8,"uint")}
            packet := EarnHdrPacket(1,84,source)
            if (DllCall("User32\DisplayConfigGetDeviceInfo","ptr",packet,"int"))
                throw Error("HDR GDI 이름 조회 실패")
            if (StrGet(packet.Ptr+20,32,"UTF-16") != device)
                continue
            target := {adapter:NumGet(paths,offset+20,"int64"),id:NumGet(paths,offset+28,"uint")}
            target.path := EarnHdrDevicePath(target)
            matches.Push(target)
        }
        if (matches.Length != 1)
            throw Error("HDR 게임 디스플레이가 유일하지 않음: " matches.Length)
        return matches[1]
    }
    throw Error("HDR 디스플레이 경로가 계속 변경됨")
}
