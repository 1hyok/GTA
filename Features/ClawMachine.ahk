; === 아케이드 인형 뽑기 (Shiny Wasabi Kitty Claw) ===
; 기계 앞에서 게임을 시작한 뒤 사용한다.
; ClawForwardMs / ClawRightMs 를 조정해 집게가 멈추는 위치를 맞춘다.
global clawLoopRunning := false

ClawAttempt() {
    global config

    if (!IsGTAActive())
        return

    key := config["Settings"]["ClawKey"]

    ; 앞으로 이동
    Send("{" key " down}")
    Sleep(config["Settings"]["ClawForwardMs"])
    Send("{" key " up}")
    Sleep(400)

    ; 오른쪽으로 이동
    Send("{" key " down}")
    Sleep(config["Settings"]["ClawRightMs"])
    Send("{" key " up}")
    Sleep(600)

    ; 내리기
    PressKey(key)
}

ToggleClawLoop() {
    global clawLoopRunning, config

    if (!IsGTAActive())
        return

    clawLoopRunning := !clawLoopRunning
    if (clawLoopRunning) {
        ShowTooltip("🧸 인형 뽑기 반복 시작 - 다시 누르면 중지")
        ClawLoopStep()
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
    ; 집게가 내려갔다 돌아오는 시간 뒤 다음 판을 시작
    SetTimer(() => (clawLoopRunning ? (PressKey(config["Settings"]["ClawKey"]), SetTimer(ClawLoopStep, -1500)) : 0), -config["Settings"]["ClawDropWait"])
}
