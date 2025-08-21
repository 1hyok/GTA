#Requires AutoHotkey v2.0
#SingleInstance Force

; === 코어 모듈 로드 (순서 중요!) ===
#Include Core\PressKey.ahk
#Include Core\ClickMouse.ahk
#Include Core\Common.ahk

; === 설정 로드 ===
global config := Map()
config["Features"] := Map()
config["Hotkeys"] := Map()
config["Settings"] := Map()

; Features 섹션
config["Features"]["Teleport"] := IniRead("Config.ini", "Features", "Teleport", 1)
config["Features"]["Movement"] := IniRead("Config.ini", "Features", "Movement", 1)
config["Features"]["AutoClick"] := IniRead("Config.ini", "Features", "AutoClick", 1)
config["Features"]["Timer"] := IniRead("Config.ini", "Features", "Timer", 1)

; Hotkeys 섹션
config["Hotkeys"]["TeleportMoca1"] := IniRead("Config.ini", "Hotkeys", "TeleportMoca1", "F4")
config["Hotkeys"]["TeleportMoca2"] := IniRead("Config.ini", "Hotkeys", "TeleportMoca2", "F5")
config["Hotkeys"]["TeleportAltF4"] := IniRead("Config.ini", "Hotkeys", "TeleportAltF4", "F6")
config["Hotkeys"]["AutoClick"] := IniRead("Config.ini", "Hotkeys", "AutoClick", "F7")
config["Hotkeys"]["Walk"] := IniRead("Config.ini", "Hotkeys", "Walk", "F8")
config["Hotkeys"]["Run"] := IniRead("Config.ini", "Hotkeys", "Run", "F9")
config["Hotkeys"]["WalkNumpad"] := IniRead("Config.ini", "Hotkeys", "WalkNumpad", "F10")
config["Hotkeys"]["Timer48"] := IniRead("Config.ini", "Hotkeys", "Timer48", "F11")
config["Hotkeys"]["Exit"] := IniRead("Config.ini", "Hotkeys", "Exit", "F12")

; Settings 섹션
config["Settings"]["ClickDelay"] := IniRead("Config.ini", "Settings", "ClickDelay", 1)
config["Settings"]["Timer48Minutes"] := IniRead("Config.ini", "Settings", "Timer48Minutes", 48)
config["Settings"]["NumpadInterval"] := IniRead("Config.ini", "Settings", "NumpadInterval", 4000)

; === 기능 모듈 로드 ===
#Include Features\Teleport.ahk
#Include Features\Movement.ahk
#Include Features\AutoClick.ahk
#Include Features\Timer.ahk

; === 동적 단축키 설정 ===
SetupHotkeys()

SetupHotkeys() {
    global config
    
    if (config["Features"]["Teleport"]) {
        Hotkey(config["Hotkeys"]["TeleportMoca1"], (*) => TeleportMoca("F4"))
        Hotkey(config["Hotkeys"]["TeleportMoca2"], (*) => TeleportMoca("F5"))
        Hotkey(config["Hotkeys"]["TeleportAltF4"], (*) => TeleportAltF4())
    }
    
    if (config["Features"]["Movement"]) {
        Hotkey(config["Hotkeys"]["Walk"], (*) => ToggleWalk())
        Hotkey(config["Hotkeys"]["Run"], (*) => ToggleRun())
        Hotkey(config["Hotkeys"]["WalkNumpad"], (*) => ToggleWalkWithNumpad())
    }
    
    if (config["Features"]["AutoClick"]) {
        Hotkey(config["Hotkeys"]["AutoClick"], (*) => ToggleAutoClick())
    }
    
    if (config["Features"]["Timer"]) {
        Hotkey(config["Hotkeys"]["Timer48"], (*) => Toggle48MinTimer())
    }
    
    Hotkey(config["Hotkeys"]["Exit"], (*) => ExitAll())
}