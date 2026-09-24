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
    config["Features"]["CasinoFingerprint"] := IniRead("Config.ini", "Features", "CasinoFingerprint")
    config["Features"]["ClawMachine"] := IniRead("Config.ini", "Features", "ClawMachine", 0)
    
    ; Hotkeys 섹션
    config["Hotkeys"]["TeleportMC1"] := IniRead("Config.ini", "Hotkeys", "TeleportMC1")
    config["Hotkeys"]["TeleportMC2"] := IniRead("Config.ini", "Hotkeys", "TeleportMC2")
    config["Hotkeys"]["TeleportAltF4"] := IniRead("Config.ini", "Hotkeys", "TeleportAltF4")
    config["Hotkeys"]["AutoClick"] := IniRead("Config.ini", "Hotkeys", "AutoClick")
    config["Hotkeys"]["Walk"] := IniRead("Config.ini", "Hotkeys", "Walk")
    config["Hotkeys"]["Run"] := IniRead("Config.ini", "Hotkeys", "Run")
    config["Hotkeys"]["WalkCtrl"] := IniRead("Config.ini", "Hotkeys", "WalkCtrl")
    config["Hotkeys"]["CayoPericoTimer"] := IniRead("Config.ini", "Hotkeys", "CayoPericoTimer")
    config["Hotkeys"]["CasinoFingerprint"] := IniRead("Config.ini", "Hotkeys", "CasinoFingerprint")
    config["Hotkeys"]["ClawAttempt"] := IniRead("Config.ini", "Hotkeys", "ClawAttempt", "")
    config["Hotkeys"]["ClawLoop"] := IniRead("Config.ini", "Hotkeys", "ClawLoop", "")
    config["Hotkeys"]["Exit"] := IniRead("Config.ini", "Hotkeys", "Exit")
    config["Hotkeys"]["PauseToggle"] := IniRead("Config.ini", "Hotkeys", "PauseToggle")
    
    ; Settings 섹션
    config["Settings"]["ClickInterval"] := IniRead("Config.ini", "Settings", "ClickInterval")
    config["Settings"]["ClickHoldTime"] := IniRead("Config.ini", "Settings", "ClickHoldTime")
    config["Settings"]["KeyHoldTime"] := IniRead("Config.ini", "Settings", "KeyHoldTime")
    config["Settings"]["PhoneOpenDelay"] := IniRead("Config.ini", "Settings", "PhoneOpenDelay")
    config["Settings"]["PhoneControlDelay"] := IniRead("Config.ini", "Settings", "PhoneControlDelay")
    config["Settings"]["MenuOpenDelay"] := IniRead("Config.ini", "Settings", "MenuOpenDelay")
    config["Settings"]["MenuControlDelay"] := IniRead("Config.ini", "Settings", "MenuControlDelay")
    config["Settings"]["MCDisbandDelay"] := IniRead("Config.ini", "Settings", "MCDisbandDelay")
    config["Settings"]["PhoneCloseDelay"] := IniRead("Config.ini", "Settings", "PhoneCloseDelay")
    config["Settings"]["TeleportWaitTime"] := IniRead("Config.ini", "Settings", "TeleportWaitTime")
    config["Settings"]["TeleportTimerInterval"] := IniRead("Config.ini", "Settings", "TeleportTimerInterval")
    config["Settings"]["CayoCooldownMinutes"] := IniRead("Config.ini", "Settings", "CayoCooldownMinutes")
config["Settings"]["VellumDrivingCtrlInterval"] := IniRead("Config.ini", "Settings", "VellumDrivingCtrlInterval")
    
    config["Settings"]["TeleportClickToEnterDelay"] := IniRead("Config.ini", "Settings", "TeleportClickToEnterDelay")
    config["Settings"]["TeleportEnterDuration"] := IniRead("Config.ini", "Settings", "TeleportEnterDuration")
    config["Settings"]["TeleportEnterInterval"] := IniRead("Config.ini", "Settings", "TeleportEnterInterval")

    config["Settings"]["ClawKey"] := IniRead("Config.ini", "Settings", "ClawKey", "Space")
    config["Settings"]["ClawForwardMs"] := IniRead("Config.ini", "Settings", "ClawForwardMs", 1200)
    config["Settings"]["ClawRightMs"] := IniRead("Config.ini", "Settings", "ClawRightMs", 900)
    config["Settings"]["ClawDropWait"] := IniRead("Config.ini", "Settings", "ClawDropWait", 12000)
}