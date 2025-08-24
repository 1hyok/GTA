; === 설정 로드 모듈 ===
global config := Map()
config["Features"] := Map()
config["Hotkeys"] := Map()
config["Settings"] := Map()

LoadConfig() {
    global config
    
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
    config["Hotkeys"]["PauseToggle"] := IniRead("Config.ini", "Hotkeys", "PauseToggle")
    
    ; Settings 섹션
    config["Settings"]["ClickInterval"] := IniRead("Config.ini", "Settings", "ClickInterval")
    config["Settings"]["ClickHoldTime"] := IniRead("Config.ini", "Settings", "ClickHoldTime")
    config["Settings"]["KeyHoldTime"] := IniRead("Config.ini", "Settings", "KeyHoldTime")
    config["Settings"]["PhoneOpenDelay"] := IniRead("Config.ini", "Settings", "PhoneOpenDelay")
    config["Settings"]["PhoneNavigationDelay"] := IniRead("Config.ini", "Settings", "PhoneNavigationDelay")
    config["Settings"]["InteractionMenuOpenDelay"] := IniRead("Config.ini", "Settings", "InteractionMenuOpenDelay")
    config["Settings"]["InteractionMenuDelay"] := IniRead("Config.ini", "Settings", "InteractionMenuDelay")
    config["Settings"]["DisbandToPhoneDelay"] := IniRead("Config.ini", "Settings", "DisbandToPhoneDelay")
    config["Settings"]["PhoneToMenuDelay"] := IniRead("Config.ini", "Settings", "PhoneToMenuDelay")
    config["Settings"]["TeleportWaitTime"] := IniRead("Config.ini", "Settings", "TeleportWaitTime")
    config["Settings"]["TeleportTimerInterval"] := IniRead("Config.ini", "Settings", "TeleportTimerInterval")
    config["Settings"]["Timer48Minutes"] := IniRead("Config.ini", "Settings", "Timer48Minutes")
    config["Settings"]["CtrlInterval"] := IniRead("Config.ini", "Settings", "CtrlInterval")
}