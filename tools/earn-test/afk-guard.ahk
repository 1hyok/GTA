#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, StdOut
#Include %A_ScriptDir%\..\..\Core\Common.ahk
#Include %A_ScriptDir%\..\..\Core\Screen.ahk
#Include %A_ScriptDir%\..\..\Core\PressKey.ahk
#Include %A_ScriptDir%\..\..\Features\SessionSwitch.ahk
#Include %A_ScriptDir%\SessionGuard.ahk
#Include %A_ScriptDir%\..\..\Features\AntiAFK.ahk

; 코드 작업 중에도 살아 있는 AFK 전용 실행기. Main이나 수익 스케줄러는 실행하지 않는다.
Persistent()
SetStoreCapsLockMode(false)
InstallKeybdHook()
InstallMouseHook()
DetectHiddenWindows(true)
SetTitleMatchMode(2)
global config := Map("Settings", Map("AFKUserIdleSec",45,"AFKIntervalSec",120,
    "AFKJitterSec",0,"AFKTapMs",150,"AFKGapMs",150,"EarnMCTOnly",1))
global gImageRoot := A_ScriptDir "\..\..\Images"
global afkOn := true
global gAbort := false
global gGuardMutex := DllCall("CreateMutexW", "ptr",0,"int",0,"str","Local\GtaMacroInput", "ptr")
if (!gGuardMutex)
    ExitApp(2)
OnExit(GuardExit)
OnError(GuardError)
HotIfWinActive(GTA_WIN)
Hotkey("~F4", GuardToggle)
HotIf()
A_IconTip := "GTA 작업 AFK 보호 (F4: 켜기/끄기)"
AFKLog("작업 AFK 시작: 120초 주기, Main 없이 실행")
SetTimer(GuardTick, 5000)

GuardOtherMacroBusy() {
    return WinExist("earntest.ahk ahk_class AutoHotkey")
        || WinExist("gui-input.ahk ahk_class AutoHotkey")
        || WinExist("Main.ahk ahk_class AutoHotkey")
}
IsTeleportRunning() => GuardOtherMacroBusy()
KeyLabelFor(*) => "F4"
StopAll(*) => ReleaseHeldKeys()

GuardTick() {
    global afkOn, afkNextDue, config, gGuardMutex
    try {
        state := "time=" FormatTime(,"yyyy-MM-dd HH:mm:ss") "`nphysicalIdleMs=" A_TimeIdlePhysical
            . "`ngtaActive=" (IsGTAActive() ? 1 : 0) "`notherMacro=" (GuardOtherMacroBusy() ? 1 : 0)
            . "`non=" (afkOn ? 1 : 0) "`nnextInMs=" Max(0,afkNextDue-A_TickCount) "`n"
        FileOpen(A_Temp "\gta-afk-guard-state.txt", "w", "UTF-8").Write(state)
    }
    if (!afkOn || GuardOtherMacroBusy() || A_TimeIdlePhysical < 45000)
        return
    acquired := DllCall("WaitForSingleObject", "ptr",gGuardMutex,"uint",0,"uint")
    if (acquired != 0 && acquired != 0x80)
        return
    try {
        if (GuardOtherMacroBusy() || A_TimeIdlePhysical < 45000)
            return
        ; 사용자가 자리를 비운 동안에는 코드 창 뒤로 간 GTA를 복구해 유휴 추방을 막는다.
        if (!IsGTAActive()) {
            if (!WinExist(GTA_WIN))
                return
            ; 크롬 원격 데스크톱·computer-use·코덱스의 입력은 주입 입력이라 A_TimeIdlePhysical 에 안 잡힌다. 그 입력이 45초 안에 있었으면
            ; 누가 다른 창을 쓰는 중이므로 GTA 를 가져오지 않는다(가져오면 그 클릭·타이핑이 게임으로 들어간다). A_TimeIdle 은 이 실행기의
            ; 메뉴 입력과 WinActivate 가 실패 때 누를 수 있는 Alt 도 세므로, 그 뒤 45초는 다시 가져오지 않는다.
            if (A_TimeIdle < 45000)
                return
            WinActivate(GTA_WIN)
            if (!WinWaitActive(GTA_WIN,,2) || A_TimeIdlePhysical < 45000)
                return
        }
        if (!AFKMenuSeen("mct_title") && !AFKMenuSeen("mct_seated")
            && !AFKMenuSeen("mct_sit") && !AFKFreeHud())
            return
        config["Settings"]["EarnMCTOnly"] := 1
        AntiAFKTick()
    } finally {
        DllCall("ReleaseMutex", "ptr",gGuardMutex)
    }
}
GuardToggle(*) {
    global afkOn, afkNextDue
    afkOn := !afkOn
    afkNextDue := 0
    AFKLog("작업 AFK " (afkOn ? "켜짐" : "꺼짐"))
    ShowTooltip("작업 AFK " (afkOn ? "켜짐" : "꺼짐"), 1500)
}
GuardExit(*) {
    global gGuardMutex
    ReleaseHeldKeys()
    if (gGuardMutex)
        DllCall("CloseHandle", "ptr",gGuardMutex)
    AFKLog("작업 AFK 종료")
}
GuardError(error, *) {
    AFKLog("작업 AFK 오류: " error.Message)
    ReleaseHeldKeys()
    return 1
}
