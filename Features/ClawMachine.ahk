; === 아케이드 인형 뽑기 (Shiny Wasabi Kitty Claw) ===
; 기계 앞 "Press E to play" 상태에서 사용한다.
; 게임 안내: W 로 앞(안쪽) 이동 → D 로 오른쪽 이동 → Enter 로 내리기. 한 판은 약 8초.
; ClawForwardMs / ClawRightMs 로 집게가 멈추는 위치를 맞춘다.
global clawLoopRunning := false

ClawAttempt() {
    global config

    if (!IsGTAActive())
        return

    s := config["Settings"]

    PressKey(s["ClawStartKey"])
    Sleep(s["ClawStartWait"])

    Send("{" s["ClawForwardKey"] " down}")
    Sleep(s["ClawForwardMs"])
    Send("{" s["ClawForwardKey"] " up}")
    Sleep(500)

    Send("{" s["ClawRightKey"] " down}")
    Sleep(s["ClawRightMs"])
    Send("{" s["ClawRightKey"] " up}")
    Sleep(500)

    PressKey(s["ClawDropKey"])
}

ToggleClawLoop() {
    global clawLoopRunning

    if (!IsGTAActive())
        return

    clawLoopRunning := !clawLoopRunning
    if (clawLoopRunning) {
        ShowTooltip("🧸 인형 뽑기 반복 시작 - 다시 누르면 중지")
        SetTimer(ClawLoopStep, -1)
    } else {
        SetTimer(ClawLoopStep, 0)
        ShowTooltip("🧸 인형 뽑기 반복 중지", 1500)
    }
}

ClawLoopStep() {
    global clawLoopRunning, config

    if (!clawLoopRunning || !IsGTAActive()) {
        clawLoopRunning := false
        return
    }

    ClawAttempt()
    SetTimer(ClawLoopStep, -config["Settings"]["ClawDropWait"])
}
