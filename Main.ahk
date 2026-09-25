#Requires AutoHotkey v2.0
#SingleInstance Force

; === 코어 모듈 로드 ===
#Include Core\PressKey.ahk
#Include Core\ClickMouse.ahk
#Include Core\Common.ahk
#Include Core\ConfigLoader.ahk
#Include Core\HotkeyManager.ahk

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

; === 초기화 ===
LoadConfig()
SetupHotkeys()
if (config["Features"]["AntiAFK"] && config["Settings"]["AFKOnStart"])
    SetAntiAFK(true)

; === 시작 메시지 ===
ShowTooltip("✅ GTA 매크로 시작됨`n🏝️ F3: 카요 페리코 타이머`n" config["Hotkeys"]["AntiAFK"] ": AFK 방지 켜기/끄기 | F12: 종료", 3000)