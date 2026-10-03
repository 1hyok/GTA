; === 판매 대기열 차례 알림 ===
; 디코 오버레이(DiscordChatHUD)가 채팅 아래에 판매 대기자를 위에서부터 띄운다(1003 실측: "NKGANCHUP / Dancing_Rock_ / Cosongi" 와 오른쪽 "대기 2명").
; HUD 는 남의 프로그램이라 알림을 넣을 수 없어, 그 자리를 주기적으로 읽어 맨 위 이름이 SaleAlertName 이 되는 순간 한 번 알린다.
; 이름이 한글일 수 있어 한국어 OCR 을 쓴다(영어 OCR 은 "대기 2명" 을 못 읽었다). 밑줄은 "Dancing-Rock—" 처럼 깨지므로 글자·숫자만 비교한다.
global gSaleTop := false

SetSaleQueueAlert() {
    global config
    s := config["Settings"]
    if (Trim(s["SaleAlertName"]) = "")
        return
    SetTimer(SaleQueueTick, Max(5, s["SaleAlertIntervalSec"]) * 1000)
}

SaleQueueTick() {
    global config, gSaleTop, GTA_WIN
    static busy := false
    if (busy || !WinActive(GTA_WIN) || !ProcessExist("DiscordChatHUD.exe"))
        return
    if (IsSet(gEarnBusy) && gEarnBusy)
        return
    busy := true
    try {
        lines := SaleQueueRead()
        if (!IsObject(lines))
            return
        top := SaleQueueTop(lines)
        mine := top != "" && SaleNameMatches(top, config["Settings"]["SaleAlertName"])
        if (mine && !gSaleTop) {
            MacroLog("sale", "판매 대기열 맨 위: " top)
            ShowTooltip("🔔 판매 차례: 대기열 맨 위에 " top, 10000)
            Loop 3 {
                SoundBeep(1200, 180)
                Sleep(120)
            }
        }
        gSaleTop := mine
    } finally {
        busy := false
    }
}

; HUD 채팅 상자 바로 아래(1920x1080 기준 x 1600~1920, y 640~780)를 한국어 OCR 로 읽는다. 실패하면 false.
SaleQueueRead() {
    global GTA_WIN
    hwnd := WinExist(GTA_WIN)
    if (!hwnd)
        return false
    try WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
    catch
        return false
    if (cw != 1920 || ch != 1080)
        return false
    output := A_Temp "\gta-sale-ocr-" DllCall("GetCurrentProcessId") ".tsv"
    script := A_ScriptDir "\Core\EarnOcr.ps1"
    try FileDelete(output)
    try RunWait('"' A_WinDir '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "' script
        . '" -X ' (cx+1600) ' -Y ' (cy+640) ' -W 320 -H 140 -OcrLanguage ko -OutputPath "' output '"', , "Hide")
    catch
        return false
    if (!FileExist(output))
        return false
    lines := []
    for row in StrSplit(FileRead(output, "UTF-8"), "`n", "`r") {
        cols := StrSplit(row, "`t")
        if (cols.Length != 5 || !IsNumber(cols[1]) || !IsNumber(cols[2]))
            continue
        lines.Push({x: cols[1] - cx, y: cols[2] - cy, w: cols[3], h: cols[4], text: cols[5]})
    }
    return lines
}

; 대기열의 맨 위 이름. "대기 N명" 줄과, 맨 위에서 줄 간격(약 19px)보다 크게 떨어진 아래 줄(게임 전화기 등)은 뺀다.
SaleQueueTop(lines) {
    names := []
    for line in lines {
        if (RegExMatch(line.text, "대기\s*\d+\s*명"))
            continue
        if (SaleNormalize(line.text) = "")
            continue
        names.Push(line)
    }
    if (!names.Length)
        return ""
    top := names[1]
    for line in names
        if (line.y < top.y)
            top := line
    ; 채팅 상자 아래 첫 줄이어야 한다. 너무 아래에서 처음 나온 줄은 대기열이 아니다(목록이 비면 전화기 글자만 남는다).
    if (top.y > 690)
        return ""
    return RegExReplace(top.text, "^[^\p{L}\p{N}]+")
}

SaleNameMatches(seen, wanted) {
    a := SaleNormalize(seen), b := SaleNormalize(wanted)
    return b != "" && (a = b || (StrLen(b) >= 3 && InStr(a, b)))
}

SaleNormalize(text) {
    return StrLower(RegExReplace(text, "[^\p{L}\p{N}]"))
}