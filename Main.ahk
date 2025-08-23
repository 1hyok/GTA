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

; Config.ini 파일 존재 확인
if (!FileExist("Config.ini")) {
    MsgBox("Config.ini 파일을 찾을 수 없습니다!")
    ExitApp()
}

; Features 섹션
config["Features"]["Teleport"] := IniRead("Config.ini", "Features", "Teleport")
config["Features"]["Movement"] := IniRead("Config.ini", "Features", "Movement")
config["Features"]["AutoClick"] := IniRead("Config.ini", "Features", "AutoClick")
config["Features"]["Timer"] := IniRead("Config.ini", "Features", "Timer")

; Hotkeys 섹션
config["Hotkeys"]["TeleportMoca1"] := IniRead("Config.ini", "Hotkeys", "TeleportMoca1")
config["Hotkeys"]["TeleportMoca2"] := IniRead("Config.ini", "Hotkeys", "TeleportMoca2")
config["Hotkeys"]["TeleportAltF4"] := IniRead("Config.ini", "Hotkeys", "TeleportAltF4")
config["Hotkeys"]["AutoClick"] := IniRead("Config.ini", "Hotkeys", "AutoClick")
config["Hotkeys"]["Walk"] := IniRead("Config.ini", "Hotkeys", "Walk")
config["Hotkeys"]["Run"] := IniRead("Config.ini", "Hotkeys", "Run")
config["Hotkeys"]["WalkCtrl"] := IniRead("Config.ini", "Hotkeys", "WalkCtrl")
config["Hotkeys"]["Timer48"] := IniRead("Config.ini", "Hotkeys", "Timer48")
config["Hotkeys"]["Exit"] := IniRead("Config.ini", "Hotkeys", "Exit")

; Settings 섹션
config["Settings"]["ClickInterval"] := IniRead("Config.ini", "Settings", "ClickInterval")
config["Settings"]["ClickHoldTime"] := IniRead("Config.ini", "Settings", "ClickHoldTime")
config["Settings"]["KeyHoldTime"] := IniRead("Config.ini", "Settings", "KeyHoldTime")
config["Settings"]["KeyInterval"] := IniRead("Config.ini", "Settings", "KeyInterval")
config["Settings"]["Timer48Minutes"] := IniRead("Config.ini", "Settings", "Timer48Minutes")
config["Settings"]["CtrlInterval"] := IniRead("Config.ini", "Settings", "CtrlInterval")

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
        Hotkey(config["Hotkeys"]["WalkCtrl"], (*) => ToggleWalkWithCtrl())
    }
    
    if (config["Features"]["AutoClick"]) {
        Hotkey(config["Hotkeys"]["AutoClick"], (*) => ToggleAutoClick())
    }
    
    if (config["Features"]["Timer"]) {
        Hotkey(config["Hotkeys"]["Timer48"], (*) => Toggle48MinTimer())
    }
    
    Hotkey(config["Hotkeys"]["Exit"], (*) => ExitAll())
}