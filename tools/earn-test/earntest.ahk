#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
SetStoreCapsLockMode false
InstallKeybdHook()
InstallMouseHook()
; 시험 하네스: 저장소의 수익 자동화 함수를 Main.ahk 없이 직접 부른다. 인자: 함수 이름과 인자 최대 셋
; 예) AutoHotkey64.exe tools\earn-test\earntest.ahk EarnSafeTask > out.txt   (결과 한 줄은 표준 출력, 과정은 %TEMP%\gta-earn.log)
; 예) ... earntest.ahk Census Nightclub 8 Left   (다시 들어가며 스폰 자리 조사, 걷지 않음)
#Include %A_ScriptDir%\..\..\Core\PressKey.ahk
#Include %A_ScriptDir%\..\..\Core\Common.ahk
#Include %A_ScriptDir%\..\..\Core\Screen.ahk
#Include %A_ScriptDir%\..\..\Features\SessionSwitch.ahk
#Include %A_ScriptDir%\SessionGuard.ahk
#Include %A_ScriptDir%\..\..\Features\Earn\EarnCore.ahk
#Include %A_ScriptDir%\..\..\Features\Earn\EarnScreen.ahk
#Include %A_ScriptDir%\..\..\Features\Earn\EarnPolicy.ahk
#Include %A_ScriptDir%\..\..\Features\Earn\EarnTasks.ahk
#Include %A_ScriptDir%\..\..\Features\Earn\EarnVinewood.ahk
#Include %A_ScriptDir%\..\..\Features\Earn\EarnStaff.ahk
#Include %A_ScriptDir%\..\..\Features\Earn\EarnWarehouseRead.ahk
#Include %A_ScriptDir%\..\..\Features\Earn\EarnWarehouse.ahk
StopAll(*) {
    global gAbort, gTestArmed
    gAbort := true
    EarnLog("시험 중단: End")
    if (gTestArmed)
        ReleaseHeldKeys()
}
global gAbort := false
global gEarnNextDue := Map()
global gEarnBusy := false
global gTestArmed := false
global gTestInputMutex := 0
global gEarnInputGuard := EarnTestInputAllowed
global gSessionInputGuard := EarnTestSessionAllowed
OnExit(EarnTestExit)
OnError(EarnTestError)
Hotkey("~End", StopAll)
; Earner.ahk 는 포함하지 않는다(핫키·타이머). 그 파일의 전역만 여기서 선언한다
global gImageRoot := A_ScriptDir "\..\..\Images"
global config := Map("Settings", Map("KeyHoldTime", 100, "EarnKeyDelay", 350, "SessionMenuDelay", 600, "EarnLoadMinSec", 8, "EarnLoadTimeoutSec", 240, "EarnTurnUnitsPerDeg", 29, "EarnRerollMax", 12, "EarnReachPx", 14, "EarnWalkRetry", 3, "EarnSafeRetryMin", 15, "EarnSoftFailMax", 12))
config["Settings"]["EarnDJPopularityPct"] := 95
config["Settings"]["EarnBunkerIntervalSec"] := 8400
config["Settings"]["EarnBailAgents"] := 1
config["Settings"]["EarnCargoStaff"] := 1
if (!A_Args.Length) {
    FileAppend("함수 이름이 필요합니다. 읽기 전용 상태: Status`n", "*", "UTF-8")
    ExitApp(2)
}
fn := A_Args[1], arg := A_Args.Length > 1 ? A_Args[2] : "", arg2 := A_Args.Length > 2 ? A_Args[3] : "", arg3 := A_Args.Length > 3 ? A_Args[4] : ""
global gTestIdleMs := 8000
t0 := A_TickCount
if (fn != "MCTStatus" && fn != "Idle" && fn != "Status" && fn != "SessionInfo" && fn != "BlipInfo" && fn != "NavInfo" && fn != "EarnSpawnRoute" && !EarnTestPrepare()) {
    FileAppend(fn " = not started fail=" gEarnFail "`n", "*", "UTF-8")
    ExitApp(3)
}
testResult := arg = "" ? %fn%() : arg2 = "" ? %fn%(arg) : arg3 = "" ? %fn%(arg, arg2) : %fn%(arg, arg2, arg3)
FileAppend(fn "(" arg ") = " testResult " in " (A_TickCount - t0) "ms fail=" gEarnFail "`n", "*", "UTF-8")
ExitApp(gAbort || testResult = false ? 1 : 0)

; 판정은 템플릿/픽셀 결과만 출력한다. 화면 저장과 키 입력은 하지 않는다.
Status() {
    global GTA_WIN
    hwnd := WinExist(GTA_WIN)
    systemIdle := Idle()
    return "pid=" (hwnd ? WinGetPID("ahk_id " hwnd) : 0)
        . " active=" (IsGTAActive() ? 1 : 0) " systemIdleMs=" systemIdle " physicalIdleMs=" A_TimeIdlePhysical
        . " hud=" EarnHudVisible() " menu=" EarnMenuIsOpen()
        . " safeHud=" EarnSeen("hud_safe_label", [0.82, 0.9, 0.95, 0.97]) " safeZero=" EarnSeen("hud_safe_zero", [0.93, 0.9, 1, 0.97])
        . " laptop=" BlipInfo("laptop") " safe=" BlipInfo("safe")
}

Idle() {
    li := Buffer(8, 0)
    NumPut("uint", 8, li)
    return DllCall("GetLastInputInfo", "ptr", li) ? (A_TickCount - NumGet(li, 4, "uint")) & 0xFFFFFFFF : -1
}

Probe() {
    return Status()
}

MCTStatus() {
    return "mct=" EarnSeen("mct_title", [0.3,0,0.7,0.1])
        . " bunkerPage=" EarnSeen("bunker_page") " bunkerPageExplicit=" EarnSeen("bunker_page", [0.15,0,0.35,0.12])
        . " bunkerBuy=" EarnSeen("bunker_buy") " bunkerConfirm=" EarnSeen("bunker_confirm") " bunkerPending=" EarnSeen("bunker_pending")
        . " bunkerCard=" EarnSeen("mct_bunker_card") " nightclubCard=" EarnSeen("mct_nightclub_card")
        . " popularity=" EarnPopularityMCTPct()
        . " stock=" EarnBarFill(766,1154,555,"green") " supply=" EarnBarFill(766,1154,577,"blue")
}

MCTSmoke() {
    global config
    config["Settings"]["EarnDJPopularityPct"] := 95
    if (EarnSeen("bunker_entry") && !EarnUIBackToMCT("bunker_entry", 1))
        return false
    if (!EarnBunkerBuy())
        return false
    return EarnDJSwapLoop(EarnPopularityMCTPct())
}

; 복귀 경로 시험: 아케이드로 한 번 이동한 뒤 실제 MCT 전용 안내까지 확인한다.
; 경로 실패로 다시 접속하지 않으며 Main/AFK를 실행하지 않는다.
ArcadeReturnSmoke() {
    return EarnReloadInto("Arcade", "Right") && EarnWalkToMCT()
}

RecoverIdleKick() {
    if (!EarnSeen("idle_kick", [0.30,0.50,0.70,0.60]))
        return EarnFail("AFK 복구: 유휴 추방 안내가 아님")
    if (!EarnPress("Enter") || !EarnSleep(8000))
        return false
    deadline := A_TickCount + 180000
    while (A_TickCount < deadline) {
        if (EarnAborted())
            return false
        if (EarnHudVisible())
            return true
        Sleep(1000)
    }
    return EarnFail("AFK 복구: 온라인 HUD 대기 시간 초과")
}

MCTTasksSmoke() {
    global config
    if (!EarnUIClearCursor())
        return false
    config["Settings"]["EarnMCTOnly"] := 1
    config["Settings"]["EarnDJPopularityPct"] := 95
    config["Settings"]["EarnBunkerIntervalSec"] := 8400
    if (EarnSeen("nc_home")) {
        EarnLog("DJ 복귀: Tale Resident=" EarnSeen("dj_resident_right", [0.61,0.50,0.835,0.58]))
        if (!EarnUIClick("nc_home", 495, 596) || !EarnUIBackToMCT("nc_dj_menu", 1))
            return false
    }
    if (EarnSeen("bunker_confirm")) {
        if (!EarnUIClick("bunker_confirm", 850, 619)
            || !EarnWaitGone("bunker_confirm", "", 3000)
            || !EarnUIBackToMCT("bunker_page", 2))
            return false
    }
    if (EarnSeen("bunker_entry") && !EarnUIBackToMCT("bunker_entry", 1))
        return false
    if (EarnSeen("bunker_page") && !EarnUIBackToMCT("bunker_page", 2))
        return false
    return EarnBunkerTask() && EarnDJTask()
}

SessionInfo() {
    global SESSION_TABS_AREA, SESSION_LIST_AREA
    return "map=" SessionScreenSeen("pause_map_selected", SESSION_TABS_AREA)
        . " onlineTab=" SessionScreenSeen("pause_online_selected", SESSION_TABS_AREA)
        . " onlineList=" SessionScreenSeen("pause_online_list", SESSION_LIST_AREA)
        . " quitGame=" SessionScreenSeen("quit_game", [0.33, 0.5, 0.67, 0.59]) " hud=" EarnHudVisible()
}

GuardedTap(key, guard) {
    if (key = "Esc" || key = "Escape" || (guard = "quit_game" && key != "Backspace"))
        return EarnFail("시험 입력 금지: Esc 또는 게임 종료 확인")
    return SessionStep(key, 1, 600, guard)
}

; Main.ahk/AFK를 실행하지 않는다. 사용자가 PC를 쓰면 전면화도 하지 않고 기다린다.
EarnTestPrepare() {
    global GTA_WIN, gAbort, gTestArmed, gTestIdleMs, gTestInputMutex
    deadline := A_TickCount + 120000
    EarnLog("시험 준비: " gTestIdleMs // 1000 "초 물리 입력 유휴 대기")
    while (A_TimeIdlePhysical < gTestIdleMs || Idle() < gTestIdleMs) {
        if (gAbort)
            return EarnFail("시험 준비: End로 중단")
        if (A_TickCount >= deadline)
            return EarnFail("시험 대기: 사용자가 PC를 사용 중, 키를 보내지 않음")
        Sleep(200)
    }
    if (!WinExist(GTA_WIN))
        return EarnFail("시험 준비: GTA 실행 창 없음")
    gTestInputMutex := DllCall("CreateMutexW", "ptr",0,"int",0,"str","Local\GtaMacroInput", "ptr")
    acquired := gTestInputMutex ? DllCall("WaitForSingleObject", "ptr",gTestInputMutex,"uint",5000,"uint") : -1
    if (acquired != 0 && acquired != 0x80)
        return EarnFail("시험 준비: 다른 매크로가 입력 중")
    gTestArmed := true
    SetTimer(EarnTestTimeout, -25 * 60 * 1000)
    if (!IsGTAActive()) {
        WinActivate(GTA_WIN)
        if (!WinWaitActive(GTA_WIN, , 2))
            return EarnFail("시험 준비: GTA 전면화 실패, 키를 보내지 않음")
    }
    if (gAbort || A_TimeIdlePhysical < gTestIdleMs || Idle() < gTestIdleMs)
        return EarnFail("시험 준비: 사용자 입력 재개, 키를 보내지 않음")
    SetTimer(EarnTestWatch, 25)
    EarnLog("시험 시작: pid=" WinGetPID(GTA_WIN) " idleMs=" A_TimeIdlePhysical)
    return true
}

; 실행 중 입력이 들어오면 남은 시퀀스를 버린다. 다음 실행에서 유휴 대기와 화면 확인부터 다시 한다.
EarnTestWatch() {
    EarnTestInputAllowed()
}

EarnTestInputAllowed() {
    global gAbort, gTestArmed, gTestIdleMs
    if (!gTestArmed)
        return !gAbort
    if (!gAbort && (A_TimeIdlePhysical < gTestIdleMs || !IsGTAActive())) {
        gAbort := true
        EarnFail("시험 중단: 사용자 입력 또는 GTA 포커스 이탈")
        ReleaseHeldKeys()
    }
    return !gAbort
}

EarnTestSessionAllowed(guard, area) {
    return EarnTestInputAllowed() && SessionScreenSeen(guard, area) && EarnTestInputAllowed()
}

EarnTestTimeout() {
    EarnFail("시험 시간 제한: 25분")
    FileAppend("timeout=25min`n", "*", "UTF-8")
    ExitApp(124)
}

EarnTestExit(*) {
    global gTestArmed, gTestInputMutex
    if (gTestArmed)
        ReleaseHeldKeys()
    if (gTestInputMutex) {
        DllCall("ReleaseMutex", "ptr",gTestInputMutex)
        DllCall("CloseHandle", "ptr",gTestInputMutex)
    }
}

EarnTestError(err, mode) {
    EarnFail("시험 오류: " err.Message " (" err.File ":" err.Line ")")
    FileAppend("error=" err.Message " line=" err.Line "`n", "*", "UTF-8")
    ExitApp(2)
}
BlipInfo(name) {
    ok := EarnBlip(name, &a, &d)
    return ok ? Format("{:.0f}/{:.0f}", a, d) : "none"
}

NavInfo(name) {
    ok := EarnNavPlan(name, &ta, &sp, &gp)
    return ok ? Format("turn {:.0f} step {:.0f} goal {:.0f}", ta, sp, gp) : "no path"
}

; 스폰 자리 조사: 스폰을 place 로 두고 n 번 다시 들어가며, 자리마다 블립(각도/거리, 길 끝 거리)과 안내 글자만 로그에 남긴다 (캡처 없음)
Census(place, n, dir) {
    if (!EarnSetSpawn(place, dir))
        return "spawn set fail"
    Loop n {
        if (!EarnRejoin(place)) {
            EarnLog("census: rejoin fail")
            return "rejoin fail at " A_Index
        }
        Sleep(2500)
        s := "census " place " #" A_Index ":"
        for b in ["laptop", "safe", "mct"] {
            if (EarnBlip(b, &a, &d)) {
                gp := EarnNavPlan(b, &ta, &sp, &g) ? Round(g) : "nopath"
                s .= " " b "=" Round(a) "/" Round(d) " end=" gp
            } else {
                s .= " " b "=none"
            }
        }
        s .= " mctsit=" (EarnSeen("mct_sit", [0, 0, 0.3, 0.1]) ? 1 : 0) " bedsit=" (EarnSeen("bed_sit", [0, 0, 0.3, 0.1]) ? 1 : 0)
        EarnLog(s)
    }
    return "done"
}
