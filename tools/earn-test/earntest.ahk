#Requires AutoHotkey v2.0
#SingleInstance Off
; 시험 하네스: 저장소의 수익 자동화 함수를 Main.ahk 없이 직접 부른다. 인자: 함수 이름과 인자 최대 셋
; 예) AutoHotkey64.exe tools\earn-test\earntest.ahk EarnSafeTask > out.txt   (결과 한 줄은 표준 출력, 과정은 %TEMP%\gta-earn.log)
; 예) ... earntest.ahk Census Nightclub 8 Left   (다시 들어가며 스폰 자리 조사, 걷지 않음)
#Include %A_ScriptDir%\..\..\Core\PressKey.ahk
#Include %A_ScriptDir%\..\..\Core\Common.ahk
#Include %A_ScriptDir%\..\..\Core\Screen.ahk
#Include %A_ScriptDir%\..\..\Features\SessionSwitch.ahk
#Include %A_ScriptDir%\..\..\Features\Earn\EarnCore.ahk
#Include %A_ScriptDir%\..\..\Features\Earn\EarnTasks.ahk
StopAll(*) {
}
global gAbort := false
global gEarnNextDue := Map()
global gEarnBusy := false
; Earner.ahk 는 포함하지 않는다(핫키·타이머). 그 파일의 전역만 여기서 선언한다
global gImageRoot := A_ScriptDir "\..\..\Images"
global config := Map("Settings", Map("KeyHoldTime", 100, "EarnKeyDelay", 350, "SessionMenuDelay", 600, "EarnLoadMinSec", 8, "EarnLoadTimeoutSec", 240, "EarnTurnUnitsPerDeg", 29, "EarnRerollMax", 12, "EarnReachPx", 14, "EarnWalkRetry", 3, "EarnSafeRetryMin", 15, "EarnSoftFailMax", 12))
fn := A_Args[1], arg := A_Args.Length > 1 ? A_Args[2] : "", arg2 := A_Args.Length > 2 ? A_Args[3] : "", arg3 := A_Args.Length > 3 ? A_Args[4] : ""
t0 := A_TickCount
r := arg = "" ? %fn%() : arg2 = "" ? %fn%(arg) : arg3 = "" ? %fn%(arg, arg2) : %fn%(arg, arg2, arg3)
FileAppend(fn "(" arg ") = " r " in " (A_TickCount - t0) "ms fail=" gEarnFail "`n", "*", "UTF-8")
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