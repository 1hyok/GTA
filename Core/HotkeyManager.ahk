; === 단축키 관리 모듈 ===
global isPaused := false

SetupHotkeys() {
    global config
    
    if (config["Features"]["Teleport"]) {
        Hotkey(config["Hotkeys"]["TeleportMC1"], (*) => TeleportMC(config["Hotkeys"]["TeleportMC1"]))
        Hotkey(config["Hotkeys"]["TeleportMC2"], (*) => TeleportMC(config["Hotkeys"]["TeleportMC2"]))
        Hotkey(config["Hotkeys"]["TeleportAltF4"], (*) => TeleportAltF4())
    }
    
    if (config["Features"]["Movement"]) {
        Hotkey(config["Hotkeys"]["Walk"], (*) => ToggleWalk())
        Hotkey(config["Hotkeys"]["Run"], (*) => ToggleRun())
        Hotkey(config["Hotkeys"]["WalkCtrl"], (*) => ToggleVellumDriving())  ; 함수명 변경
    }
    
    if (config["Features"]["AutoClick"]) {
        Hotkey(config["Hotkeys"]["AutoClick"], (*) => ToggleAutoClick())
    }
    
    if (config["Features"]["Timer"]) {
        Hotkey(config["Hotkeys"]["CayoPericoTimer"], (*) => ToggleCayoPericoTimer())
    }
    
    if (config["Features"]["CasinoFingerprint"]) {
        Hotkey(config["Hotkeys"]["CasinoFingerprint"], (*) => ExecuteCasinoFingerprint())
    }
    
    ; 일시정지/재개 단축키
    Hotkey(config["Hotkeys"]["PauseToggle"], (*) => TogglePause())
    
    ; 종료 단축키
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