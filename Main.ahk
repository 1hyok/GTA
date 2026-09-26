#Requires AutoHotkey v2.0
#SingleInstance Force
; Send 는 기본값에서 보내기 전 CapsLock 을 껐다가 되돌린다 → CapsLock 이 켜져 있으면 W/S 앞뒤로 CapsLock 눌림이 게임에 들어가 특수 능력이 발동한다 (0926 원인 확정). 끈다.
SetStoreCapsLockMode false
; Alt/Win 이 든 조합 뒤에 기본 마스크 키(LCtrl)가 끼어 게임에서 웅크리기가 되는 일을 막는다. vkE8 은 할당되지 않은 가상 키다.
A_MenuMaskKey := "vkE8"

; === 코어 모듈 로드 ===
#Include Core\PressKey.ahk
#Include Core\ClickMouse.ahk
#Include Core\Common.ahk
#Include Core\ConfigLoader.ahk
#Include Core\HotkeyManager.ahk
#Include Core\Menu.ahk
#Include Core\Screen.ahk

; === 기능 모듈 로드 ===
#Include Features\Teleport\TeleportBase.ahk
#Include Features\Teleport\TeleportMessages.ahk
#Include Features\Teleport\MCTeleport.ahk
#Include Features\Teleport\AltF4Teleport.ahk
#Include Features\Movement.ahk
#Include Features\AutoClick.ahk
#Include Features\CayoPericoTimer.ahk
#Include Features\Hacks\CasinoFingerprint.ahk
#Include Features\ClawMachine.ahk
#Include Features\SessionSwitch.ahk
#Include Features\AntiAFK.ahk
#Include Features\Snack.ahk
#Include Features\RegisterCEO.ahk
#Include Features\RegisterMC.ahk
#Include Features\StopAll.ahk
#Include Features\Help.ahk
#Include Features\Overlay.ahk
#Include Features\Panel.ahk

; === 초기화 ===
; 스크립트가 이동 키를 누른 채로 종료되면 캐릭터가 계속 걸어가 버린다(실측). 종료 시 항상 뗀다.
OnExit((*) => (ReleaseHeldKeys(), 0))
; 실행 중 오류는 대화상자 대신 로그(%TEMP%\gta-macro.log)와 툴팁으로 알린다. 대화상자는 게임 포커스를 빼앗아 AFK 방지까지 막는다.
OnError(OnScriptError)
OnScriptError(err, mode) {
    try ReleaseHeldKeys()
    MacroLog("error", mode ": " err.Message " (" err.File ":" err.Line ") " err.What)
    try ShowTooltip("⚠ 매크로 오류: " err.Message "`n" err.File ":" err.Line, 5000)
    return 1
}
LoadConfig()
SetupHotkeys()
SetupTrayMenu()
if (config["Features"]["AntiAFK"] && config["Settings"]["AFKOnStart"])
    SetAntiAFK(true)
; 게임 화면 오른쪽 위 상태 표시 (클릭 통과·포커스 안 가져감). 설정 창은 트레이 메뉴 또는 도움말 키 두 번.
if (config["Settings"]["OverlayEnabled"])
    SetOverlay(true)

; === 시작 메시지 ===
ShowTooltip("✅ GTA 매크로 시작됨 (게임 창에서만 동작)`n" KeyLabelFor("Help") ": 단축키 보기 (두 번: 설정 창) | " KeyLabelFor("StopAll") ": 전체 멈춤 | " KeyLabelFor("Exit") ": 종료", 3000)
