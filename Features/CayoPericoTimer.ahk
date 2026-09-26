; === 카요 페리코 쿨타임 타이머 변수 ===
global cayoTimerRunning := false
global cayoGUI := ""
global cayoEndTick := 0   ; 끝나는 시각(A_TickCount). 오버레이·설정 창이 남은 시간을 읽는다

ToggleCayoPericoTimer() {
    global cayoTimerRunning, cayoGUI, cayoEndTick, config

    if (!cayoTimerRunning) {
        cayoTimerRunning := true

        cayoCooldownMinutes := config["Settings"]["CayoCooldownMinutes"]
        cayoEndTick := A_TickCount + cayoCooldownMinutes * 60000

        ; 완료 예정 시각 계산
        endDateTime := DateAdd(A_Now, cayoCooldownMinutes, "Minutes")
        endTime := FormatTime(endDateTime, "HH:mm")

        ; GUI로 완료 예정 시각 표시
        cayoGUI := Gui("+AlwaysOnTop -MaximizeBox", "🏝️ 카요 페리코")
        cayoGUI.SetFont("s11 Bold")
        cayoGUI.Add("Text", "x10 y10 w150 h30 Center", "완료 예정: " . endTime)
        ; 게임 포커스를 뺏지 않게 NA 로, GTA 가 없는 모니터(노트북 화면) 오른쪽 위에 띄운다. 게임 안에서는 오버레이가 남은 시간을 보여 준다
        PanelTargetArea(&l, &t, &r, &b)
        cayoGUI.Show("NA x" (r - 360) " y" (t + 20) " w170 h50")

        ; 완료 시각에 알림
        SetTimer(CayoCompleted, cayoCooldownMinutes * 60000)

    } else {
        cayoTimerRunning := false
        SetTimer(CayoCompleted, 0)

        ; GUI 닫기
        if (IsObject(cayoGUI)) {
            cayoGUI.Destroy()   ; v2 Gui 에는 Close() 가 없다 (Destroy/Hide 만)
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
    if (IsObject(cayoGUI)) {
        cayoGUI.Destroy()
        cayoGUI := ""
    }

    TrayTip("🏝️ 카요 페리코 완료!", "준비됨", "Iconi")
    SoundBeep(1500, 500)
}
