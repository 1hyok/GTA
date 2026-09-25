; === 카요 페리코 쿨타임 타이머 변수 ===
global cayoTimerRunning := false
global cayoGUI := ""

ToggleCayoPericoTimer() {
    global cayoTimerRunning, cayoGUI, config

    if (!cayoTimerRunning) {
        cayoTimerRunning := true

        cayoCooldownMinutes := config["Settings"]["CayoCooldownMinutes"]

        ; 완료 예정 시각 계산
        endDateTime := DateAdd(A_Now, cayoCooldownMinutes, "Minutes")
        endTime := FormatTime(endDateTime, "HH:mm")

        ; GUI로 완료 예정 시각 표시
        cayoGUI := Gui("+AlwaysOnTop -MaximizeBox", "🏝️ 카요 페리코")
        cayoGUI.SetFont("s11 Bold")
        cayoGUI.Add("Text", "x10 y10 w150 h30 Center", "완료 예정: " . endTime)
        cayoGUI.Show("x-180 y100 w170 h50")

        ; 완료 시각에 알림
        SetTimer(CayoCompleted, cayoCooldownMinutes * 60000)

    } else {
        cayoTimerRunning := false
        SetTimer(CayoCompleted, 0)

        ; GUI 닫기
        if (cayoGUI != "") {
            cayoGUI.Close()
            cayoGUI := ""
        }

        ShowTooltip("🏝️ 타이머 중지", 1000)
    }
}

CayoCompleted() {
    global cayoTimerRunning, cayoGUI

    cayoTimerRunning := false
    SetTimer(CayoCompleted, 0)

    ; GUI 닫기
    if (cayoGUI != "") {
        cayoGUI.Close()
        cayoGUI := ""
    }

    TrayTip("🏝️ 카요 페리코 완료!", "준비됨", "Iconi")
    SoundBeep(1500, 500)
}
