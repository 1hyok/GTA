; === 설정 로드 모듈 ===
; [Features]·[Settings] 는 기본값 표의 키를 읽고, [Hotkeys] 는 섹션 전체를 읽어 Map 에 넣는다.
; 새 기능은 Config.ini [Hotkeys] 한 줄 + HotkeyManager 액션 표 한 줄로 붙는다.
global config := Map()
config["Features"] := Map()
config["Hotkeys"] := Map()
config["Settings"] := Map()

; 값이 없거나 숫자가 아닐 때 쓰는 기본값. 값 줄 끝에 ; 주석을 붙이면 IniRead 가 주석까지 값으로 읽으므로 주석은 줄을 따로 쓴다.
global CONFIG_DEFAULTS := Map()
CONFIG_DEFAULTS["Features"] := Map(
    "Teleport", 1, "AltF4Teleport", 0, "Movement", 1, "AutoClick", 1, "Timer", 1,
    "CasinoFingerprint", 0, "ClawMachine", 1, "AntiAFK", 1, "SessionSwitch", 1, "MenuMacros", 1)
CONFIG_DEFAULTS["Settings"] := Map(
    "ClickInterval", 1, "ClickHoldTime", 50, "KeyHoldTime", 100,
    "ConfirmWindowMs", 2000, "HelpShowMs", 8000,
    "MenuOpenDelay", 50, "MenuControlDelay", 50,
    "PhoneOpenDelay", 1000, "PhoneControlDelay", 150, "MCDisbandDelay", 1000, "PhoneCloseDelay", 1000,
    "TeleportWaitTime", 38000, "TeleportTimerInterval", 100,
    "TeleportEnterDuration", 100000, "TeleportEnterInterval", 50, "TeleportClickToEnterDelay", 4000,
    "CayoCooldownMinutes", 48, "VellumDrivingCtrlInterval", 3000,
    "ClawForwardMs", 5000, "ClawRightMs", 5000, "ClawEnterTimeout", 15000, "ClawResultTimeout", 30000,
    "SessionMenuDelay", 600,
    "AFKUserIdleSec", 45, "AFKIntervalSec", 200, "AFKJitterSec", 20, "AFKTapMs", 150, "AFKGapMs", 250, "AFKOnStart", 1,
    "SnackMenuSteps", 4, "SnackSubSteps", 2, "SnackItemSteps", 0, "SnackCount", 1, "SnackCloseMenu", 1,
    "CEOMenuSteps", 1, "CEOSubSteps", 0, "CEOEnterCount", 2, "CEOCloseMenu", 1,
    "MCMenuSteps", 1, "MCSubSteps", 1, "MCEnterCount", 2, "MCCloseMenu", 1)

LoadConfig() {
    global config, CONFIG_DEFAULTS
    file := A_ScriptDir "\Config.ini"

    ; Config.ini 파일 존재 확인
    if (!FileExist(file)) {
        MsgBox("Config.ini 파일을 찾을 수 없습니다!")
        ExitApp()
    }
    StripConfigBom(file)

    ; Features / Settings: 기본값 표의 키만 읽는다. 숫자가 아니면 기본값을 쓰고 로그를 남긴다 (Integer() 예외로 시작이 막히지 않게).
    for section in ["Features", "Settings"] {
        for key, dflt in CONFIG_DEFAULTS[section] {
            value := IniRead(file, section, key, dflt)
            if (IsNumber(value)) {
                config[section][key] := Number(value)
            } else {
                config[section][key] := dflt
                MacroLog("config", section "." key "=" value " 는 숫자가 아니라 기본값 " dflt " 사용")
            }
        }
    }

    ; Hotkeys: 있는 줄을 전부 읽는다. 액션 표에 없는 이름은 등록 때 무시된다.
    for line in StrSplit(IniRead(file, "Hotkeys", , ""), "`n", "`r") {
        pos := InStr(line, "=")
        if (!pos)
            continue
        name := Trim(SubStr(line, 1, pos - 1))
        if (name = "" || SubStr(name, 1, 1) = ";")
            continue
        config["Hotkeys"][name] := Trim(SubStr(line, pos + 1))
    }
}

; UTF-8 BOM 이 있으면 IniRead 가 첫 섹션 이름을 못 읽는다(85009a1 실측). 발견하면 BOM 만 떼고 다시 저장한다.
StripConfigBom(file) {
    try {
        raw := FileRead(file, "RAW")
        if (raw.Size < 3 || NumGet(raw, 0, "UChar") != 0xEF || NumGet(raw, 1, "UChar") != 0xBB || NumGet(raw, 2, "UChar") != 0xBF)
            return
        text := FileRead(file, "UTF-8")
        f := FileOpen(file, "w", "UTF-8-RAW")
        f.Write(text)
        f.Close()
        MacroLog("config", "Config.ini 의 UTF-8 BOM 을 제거함")
    }
}
