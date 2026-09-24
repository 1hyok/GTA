; === 단축키 관리 모듈 ===
global isPaused := false

SetupHotkeys() {
    global config
    
    if (config["Features"]["Teleport"]) {
        if (config["Hotkeys"]["TeleportMC1"] != "")
            Hotkey(config["Hotkeys"]["TeleportMC1"], (*) => TeleportMC(config["Hotkeys"]["TeleportMC1"]))
        if (config["Hotkeys"]["TeleportMC2"] != "")
            Hotkey(config["Hotkeys"]["TeleportMC2"], (*) => TeleportMC(config["Hotkeys"]["TeleportMC2"]))
        if (config["Hotkeys"]["TeleportAltF4"] != "")
            Hotkey(config["Hotkeys"]["TeleportAltF4"], (*) => TeleportAltF4())
    }
    
    if (config["Features"]["Movement"]) {
        if (config["Hotkeys"]["Walk"] != "")
            Hotkey(config["Hotkeys"]["Walk"], (*) => ToggleWalk())
        if (config["Hotkeys"]["Run"] != "")
            Hotkey(config["Hotkeys"]["Run"], (*) => ToggleRun())
        if (config["Hotkeys"]["WalkCtrl"] != "")
            Hotkey(config["Hotkeys"]["WalkCtrl"], (*) => ToggleVellumDriving())
    }
    
    if (config["Features"]["AutoClick"]) {
        if (config["Hotkeys"]["AutoClick"] != "")
            Hotkey(config["Hotkeys"]["AutoClick"], (*) => ToggleAutoClick())
    }
    
    if (config["Features"]["Timer"]) {
        if (config["Hotkeys"]["CayoPericoTimer"] != "")
            Hotkey(config["Hotkeys"]["CayoPericoTimer"], (*) => ToggleCayoPericoTimer())
    }
    
    if (config["Features"]["CasinoFingerprint"]) {
        if (config["Hotkeys"]["CasinoFingerprint"] != "")
            Hotkey(config["Hotkeys"]["CasinoFingerprint"], (*) => ExecuteCasinoFingerprint())
    }

    if (config["Features"]["ClawMachine"]) {
        if (config["Hotkeys"]["ClawAttempt"] != "")
            Hotkey(config["Hotkeys"]["ClawAttempt"], (*) => ClawAttempt())
        if (config["Hotkeys"]["ClawLoop"] != "")
            Hotkey(config["Hotkeys"]["ClawLoop"], (*) => ToggleClawLoop())
    }

    ; 일시정지/재개 단축키
    if (config["Hotkeys"]["PauseToggle"] != "")
        Hotkey(config["Hotkeys"]["PauseToggle"], (*) => TogglePause())
    
    ; 종료 단축키
    if (config["Hotkeys"]["Exit"] != "")
        Hotkey(config["Hotkeys"]["Exit"], (*) => ExitAll())
}

TogglePause() {
    global isPaused
    
    isPaused := !isPaused
    
    if (isPaused) {
        Pause(1)
        ShowTooltip("⏸️ 일시정지", 1500)
    } else {
        Pause(0)
        ShowTooltip("▶️ 재개", 1500)
    }
}