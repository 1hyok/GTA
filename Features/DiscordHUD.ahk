; === 디스코드 오버레이(DiscordChatHUD) 함께 띄우기 ===
; DiscordChatHUD 는 남이 만든 별도 프로그램이다(실행 파일만 배포, hud.wukwookoock.online). Main 을 켜면 같이 띄워 따로 실행할 필요를 없앤다.
; 이미 떠 있으면(HUD 본체나 설정·로그인 창) 건드리지 않는다. 경로가 비었거나 파일이 없으면 아무것도 안 한다.
; 띄우면 시작 때 자동 업데이트·로그인 창이 GTA 포커스를 가져간다(1003 19:55 실측: 업데이트 뒤 설정 창이 떠 수익 작업이 중단됐다).
; GTA 가 앞이었으면 1분 동안 HUD 창이 앞으로 올 때마다 GTA 를 다시 앞으로 가져온다. 로그인 창은 작업 표시줄에 남는다.
StartDiscordHUD() {
    global config, GTA_WIN
    path := config["Settings"]["DiscordHUDPath"]
    if (path = "")
        return false
    path := StrReplace(path, "%LOCALAPPDATA%", EnvGet("LOCALAPPDATA"))
    if (!FileExist(path))
        return false
    if (ProcessExist("DiscordChatHUD.exe") || ProcessExist("DiscordChatHUD_Config.exe"))
        return false
    SplitPath(path, , &dir)
    gtaWasActive := WinExist(GTA_WIN) && WinActive(GTA_WIN)
    try Run('"' path '"', dir)
    catch as e {
        MacroLog("hud", "디코 오버레이 실행 실패: " e.Message)
        return false
    }
    MacroLog("hud", "디코 오버레이 실행: " path)
    if (gtaWasActive)
        DiscordHUDKeepGTAFront(A_TickCount + 60000)
    return true
}

DiscordHUDKeepGTAFront(deadline) {
    global GTA_WIN
    static loginNoticed := false
    ; 로그인 창(제목 "계정 연결")이 뜨면 GTA 뒤로 숨기 전에 한 번 알린다(1003 20:22 실측: 강제 종료 뒤 새로 띄우자 다시 로그인을 물었다).
    if (!loginNoticed && WinExist("계정 연결 ahk_exe DiscordChatHUD.exe")) {
        loginNoticed := true
        MacroLog("hud", "디코 오버레이가 로그인을 기다림")
        ShowTooltip("💬 디코 오버레이 로그인 필요: 작업 표시줄의 DiscordChatHUD 창", 8000)
    }
    if (A_TickCount >= deadline || !WinExist(GTA_WIN))
        return
    if (WinActive("ahk_exe DiscordChatHUD.exe") || WinActive("ahk_exe DiscordChatHUD_Config.exe")) {
        WinActivate(GTA_WIN)
        MacroLog("hud", "디코 오버레이 창이 앞으로 와서 GTA 를 다시 앞으로")
    }
    SetTimer(() => DiscordHUDKeepGTAFront(deadline), -500)
}