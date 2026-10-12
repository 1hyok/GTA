; 일반 모드는 수익 자동화가 켜져 있고 사람 입력이 CpuBoostIdleSec(기본 300초) 넘게 없을 때 CPU 부스트를 끈다. 사람이 만지면 다음 확인 때 다시 켠다.
; 1005 실측: 방치 중 부스트 클럭으로 CPU 전력이 12W 에서 25~30W, 온도가 73°C 에서 95°C 까지 올랐다. 부스트를 끄자 12W·66~73°C.
; MCT 메뉴만 오가는 방치 작업은 부스트가 없어도 느려지지 않는다. CpuBoostIdleSec 을 0 으로 두면 일반 모드의 자동 전환을 끈다.
; 같은 때 GTA 프레임도 IdleFpsLimit(기본 30, 0 이면 제한 안 함)으로 묶고, 사람이 만지면 제한을 푼다.
; 수동 외출 모드(AwayMode=1)는 수익 자동화·입력 유휴 설정과 별개로 부스트 끔·30 FPS 요청을 유지한다.
; AutoAwayIdleSec > 0이면 사람 입력이 없을 때 같은 저부하 정책을 적용하고, 조작 재개 시 일반 정책으로 복원한다.
; 실제 적용은 관리자 예약 작업 「GTA FPS Helper」(RTSS 설치 폴더의 gta-fps-helper.ps1)가 %USERPROFILE%\.gta-fps-want 의 숫자를 읽어 RTSS 프로필에 반영한다.
; 1005 실측: RTSS 30fps 제한으로 게임을 켠 채 GPU 전력 96W → 24~29W.
global gCpuBoostState := ""
global gCpuBoostFps := ""
global gCpuBoostLastActive := 0
global gCpuBoostWorking := false
global gCpuBoostError := ""
global gCpuBoostAutoAway := false
global gCpuBoostPublishError := ""

CpuBoostWanted(earnOn, idleMs, idleSec, away := false) => !away && !(earnOn && idleSec > 0 && idleMs >= idleSec * 1000)

; 한 번 본 사람 입력 시각은 뒤로 물리지 않는다. 매크로가 자기 입력 구간을 표시하면 그 앞의 원격(주입) 입력이 가려져
; 유휴가 다시 길게 계산됐다(1005 16:52:58 제한 해제 → 16:53:28 사람이 만지는 중에 다시 제한).
CpuBoostLastActive(prev, now, idleMs) => Max(prev, now - idleMs)
CpuBoostAutoAway(idleMs, sec, held := false) => sec > 0 && !held && idleMs >= sec * 1000
CpuBoostUptime() => DllCall("GetTickCount64", "UInt64")

CpuBoostDesired() {
    global gEarnOn, config, gCpuBoostLastActive
    sec := config["Settings"].Get("CpuBoostIdleSec", 300)
    autoSec := config["Settings"].Get("AutoAwayIdleSec", 0)
    manualAway := config["Settings"].Get("AwayMode", 0) = 1
    phys := AFKPhysicalIdleMs(), others := AFKOthersIdleMs()
    now := CpuBoostUptime()
    held := AFKKeysHeld()
    gCpuBoostLastActive := CpuBoostLastActive(gCpuBoostLastActive, now, held ? 0 : Min(phys, others))
    autoAway := CpuBoostAutoAway(now - gCpuBoostLastActive, autoSec, held)
    away := manualAway || autoAway
    want := CpuBoostWanted(gEarnOn, now - gCpuBoostLastActive, sec, away) ? "on" : "off"
    fps := away ? 30 : (want = "on" ? 0 : config["Settings"].Get("IdleFpsLimit", 30))
    return {autoAway: autoAway, manualAway: manualAway, phys: phys, others: others, now: now, want: want, fps: fps}
}

; 긴 수익 작업 중에도 heartbeat는 유지한다. 입력·powercfg·FPS 조작 없이 상태 판정과 짧은 파일 쓰기만 한다.
CpuBoostPublishTick() {
    global gCpuBoostPublishError
    try {
        policy := CpuBoostDesired()
        CpuBoostWriteAway(policy.autoAway, policy.want = "on", policy.now)
        gCpuBoostPublishError := ""
        return true
    } catch as err {
        failure := "자동 외출 상태 저장 실패: " err.Message
        if (failure != gCpuBoostPublishError)
            EarnLog(failure " (2초 간격 재시도)")
        gCpuBoostPublishError := failure
        return false
    }
}

CpuBoostTick() {
    global config, gCpuBoostState, gCpuBoostFps, gCpuBoostWorking, gCpuBoostError, gCpuBoostAutoAway, gCpuBoostPublishError
    if (gCpuBoostWorking)
        return false
    if (config["Settings"].Get("AwayMode", 0) != 1 && config["Settings"].Get("AutoAwayIdleSec", 0) <= 0
        && config["Settings"].Get("CpuBoostIdleSec", 300) <= 0 && gCpuBoostState = "" && gCpuBoostFps = "" && gCpuBoostError = "")
        return true
    policy := CpuBoostDesired()
    want := policy.want, fps := policy.fps, autoAway := policy.autoAway
    ; 감시 프로그램의 stale 해제와 heartbeat 복구가 교차해도 마지막 파일 값으로 수렴한다.
    ; 메모리 캐시만 같다고 실제 FPS 요청까지 같은 것으로 간주하지 않는다.
    if (fps = gCpuBoostFps) {
        try {
            if (FileRead(EnvGet("USERPROFILE") "\.gta-fps-want", "UTF-8") != String(fps))
                gCpuBoostFps := ""
        } catch {
            gCpuBoostFps := ""
        }
    }
    unchanged := want = gCpuBoostState && fps = gCpuBoostFps && autoAway = gCpuBoostAutoAway && gCpuBoostError = ""
    gCpuBoostWorking := true
    try {
        failure := gCpuBoostPublishError
        if (unchanged && failure = "")
            return true
        try {
            if (want != gCpuBoostState) {
                CpuBoostApply(want = "on")
                gCpuBoostState := want
            }
        } catch as err {
            ; 일부 명령만 반영됐을 수 있으므로 이전 정책도 다시 적용할 수 있게 한다.
            gCpuBoostState := ""
            failure .= (failure = "" ? "" : "; ") "CPU 부스트 적용 실패: " err.Message
        }
        ; CPU 명령이 실패해도 FPS 요청은 따로 시도한다. 성공한 쪽은 반복하지 않는다.
        try {
            if (fps != gCpuBoostFps) {
                CpuBoostWriteFps(fps)
                gCpuBoostFps := fps
            }
        } catch as err {
            ; 쓰기/읽기 확인 실패 시 파일이 이전 요청을 보존했다고 가정하지 않는다.
            gCpuBoostFps := ""
            failure .= (failure = "" ? "" : "; ") "FPS 요청 저장 실패: " err.Message
        }
        if (failure != "") {
            if (failure != gCpuBoostError)
                EarnLog(failure " (2초 간격 재시도)")
            gCpuBoostError := failure
            CpuBoostUpdateTray()
            return false
        }
        gCpuBoostError := ""
        gCpuBoostAutoAway := autoAway
        ; RTSS helper의 실제 적용과 구분해 요청값으로 기록한다.
        EarnLog("CPU 부스트 " (want = "on" ? "켬" : "끔") ", FPS 요청 " fps
            " (" (policy.manualAway ? "수동 외출 저부하" : autoAway ? "자동 외출 저부하" : "일반 자동 정책") ", 물리 유휴 " Round(policy.phys / 1000)
            "초, 주입 포함 " Round(policy.others / 1000) "초)")
        CpuBoostUpdateTray()
        return true
    } finally {
        gCpuBoostWorking := false
    }
}

CpuBoostWriteAway(autoAway, boost, now) {
    file := EnvGet("USERPROFILE") "\.gta-away-want"
    text := "v1|" DllCall("GetCurrentProcessId") "|" now "|" (autoAway ? 1 : 0) "|" (boost ? 1 : 0)
    temp := file ".tmp"
    f := FileOpen(temp, "w", "UTF-8-RAW")
    try {
        if (f.Write(text) != StrLen(text))
            throw Error("자동 외출 상태를 끝까지 쓰지 못함")
    } finally {
        f.Close()
    }
    FileMove(temp, file, 1)
}

; 켬은 Windows 균형 조정 기본값(최대 상태 100%, 부스트 모드 AC 공격적 2·DC 사용 1), 끔은 99%·부스트 사용 안 함 0.
CpuBoostApply(on) {
    boost := "be337238-0d82-4146-a960-4f3749d470c7"
    pc := "powercfg /set{1}valueindex SCHEME_CURRENT SUB_PROCESSOR {2} {3}"
    cmds := [Format(pc, "ac", "PROCTHROTTLEMAX", on ? 100 : 99), Format(pc, "dc", "PROCTHROTTLEMAX", on ? 100 : 99),
        Format(pc, "ac", boost, on ? 2 : 0), Format(pc, "dc", boost, on ? 1 : 0), "powercfg /setactive SCHEME_CURRENT"]
    line := ""
    for c in cmds
        line .= (line = "" ? "" : " && ") c
    code := RunWait(A_ComSpec ' /c ' line, , "Hide")
    if (code != 0)
        throw Error("powercfg exit=" code)
}

CpuBoostWriteFps(fps) {
    file := EnvGet("USERPROFILE") "\.gta-fps-want"
    text := String(fps)
    f := FileOpen(file, "w", "UTF-8-RAW")
    try {
        if (f.Write(text) != StrLen(text))
            throw Error("FPS 요청을 끝까지 쓰지 못함")
    } finally {
        f.Close()
    }
    if (FileRead(file, "UTF-8") != text)
        throw Error("FPS 요청 읽기 확인 불일치")
}

; 저장에 실패하면 메모리 설정을 바꾸거나 성공 툴팁을 띄우지 않는다.
SetAwayMode(on) {
    global config
    try SetConfigValue("Settings", "AwayMode", on ? 1 : 0)
    catch as err {
        MacroLog("away", "외출 모드 저장 실패: " err.Message)
        ShowTooltip("외출 모드 변경 실패: Config.ini를 저장하지 못했습니다", 5000)
        return false
    }
    CpuBoostUpdateTray()
    ; 트레이 콜백에서 powercfg를 기다리면 진행 중인 게임 키 해제가 늦어질 수 있다.
    ; 저장만 하고 낮은 우선순위 타이머가 입력 구간 사이에 적용하도록 맡긴다.
    ShowTooltip(on ? "외출 저부하 설정 저장됨: CPU 부스트 끔·30 FPS 적용 대기"
        : "일반 복귀 설정 저장됨: 기존 자동 정책 적용 대기", 4000)
    return true
}

CpuBoostUpdateTray() {
    global config, gCpuBoostError, gCpuBoostAutoAway
    away := config["Settings"].Get("AwayMode", 0) = 1
    tray := A_TrayMenu
    ; 시작 시 타이머가 트레이 생성보다 먼저 돌아도 전력 정책은 계속 적용한다.
    try tray.Uncheck(away ? "외출 저부하 끄기 (일반 복귀)" : "외출 저부하 켜기 (30 FPS)")
    try tray.Check(away ? "외출 저부하 켜기 (30 FPS)" : "외출 저부하 끄기 (일반 복귀)")
    A_IconTip := "GTA 매크로 | " (away ? "수동 외출: 켬 (30 FPS 요청)" : gCpuBoostAutoAway ? "자동 외출: 켬 (30 FPS 요청)" : "외출 저부하: 꺼짐")
        (gCpuBoostError = "" ? "" : " | 전력/FPS 적용 재시도 중")
}

; 2초마다 확인하되 게임 입력 스레드를 선점하지 않는다. 적용 실패는 상태를 확정하지 않고 다시 시도한다.
SetTimer(CpuBoostTick, 2000, -10)
; 자기 입력을 제외한 활동 상태 발행은 전력 명령과 분리해 일반 우선순위 작업 중에도 갱신한다.
SetTimer(CpuBoostPublishTick, 2000)
