; MC 텔레포트 메시지 표시
ShowMCMessage(text, duration := 1000) {
    ToolTip(text, 0, 0)
    SetTimer(() => ToolTip(), duration)
}

; Alt+F4 텔레포트 메시지 표시
ShowAltF4Message(text, duration := 1000) {
    ToolTip(text, 0, 0)
    SetTimer(() => ToolTip(), duration)
}

; Alt+F4 진행 상황 표시
ShowAltF4Progress() {
    global config, altF4StartTime, altF4Running
    
    if (!altF4Running) {
        SetTimer(ShowAltF4Progress, 0)
        return
    }
    
    teleportWaitTime := config["Settings"]["TeleportWaitTime"]
    elapsed := A_TickCount - altF4StartTime
    remaining := (teleportWaitTime - elapsed) / 1000
    
    if (remaining <= 0) {
        SetTimer(ShowAltF4Progress, 0)
        return
    }
    
    ; 진행률 계산
    progressData := CalculateProgress(elapsed, teleportWaitTime, remaining)
    
    ; 메시지 표시
    DisplayProgressMessage(progressData)
}

; 진행률 계산 함수
CalculateProgress(elapsed, teleportWaitTime, remaining) {
    remainingSec := Round(remaining, 1)
    progressPercent := (elapsed / teleportWaitTime) * 100
    
    ; 진행 바 생성
    barLength := 20
    filledLength := Round(progressPercent / 100 * barLength)
    progressBar := ""
    
    Loop filledLength
        progressBar .= "█"
    Loop (barLength - filledLength)
        progressBar .= "░"
    
    ; 단계별 메시지
    stageMessage := GetStageMessage(remainingSec)
    
    return {
        remainingSec: remainingSec,
        progressPercent: progressPercent,
        progressBar: progressBar,
        stageMessage: stageMessage
    }
}

; 단계별 메시지 반환
GetStageMessage(remainingSec) {
    if (remainingSec > 30)
        return "🔄 게임 종료 대기 중..."
    else if (remainingSec > 15)
        return "⏳ 로딩 화면 대기 중..."
    else if (remainingSec > 5)
        return "🌐 온라인 모드 로딩 중..."
    else
        return "🏁 거의 완료!"
}

; 진행 상황 메시지 표시
DisplayProgressMessage(progressData) {
    ToolTip("🚀 Alt+F4 텔레포트 진행중`n" 
          . progressData.stageMessage . "`n"
          . progressData.progressBar . " " . Round(progressData.progressPercent, 1) . "%`n"
          . "⏱️ 남은 시간: " . progressData.remainingSec . "초", 10, 10)
}