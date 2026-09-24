; === 아케이드 인형 뽑기 (Shiny Wasabi Kitty Claw) ===
; 기계 앞 "Press E to play" 안내가 떠 있는 상태에서 사용한다.
; 단계마다 화면 왼쪽 위 안내 문구(Images\Claw\*.png)를 확인하고 나서 다음 키를 누른다.
; 안내가 안 보이면 아무 키도 누르지 않고 멈춘다 — 캐릭터가 걸어가 버리는 사고를 막는다.
; 안내 문구 이미지는 2560x1600 기준이다. 해상도가 바뀌면 다시 캡처해야 한다.
global clawLoopRunning := false
global clawTries := 0

ClawLog(msg) {
    FileAppend(FormatTime(, "HH:mm:ss") " " msg "`n", A_Temp "\gta-claw.log", "UTF-8")
}

ClawSeen(name) {
    CoordMode("Pixel", "Screen")
    img := A_ScriptDir "\Images\Claw\" name ".png"
    try {
        return ImageSearch(&x, &y, 0, 0, 900, 250, "*50 *Trans0xFF00FF " img)
    } catch as e {
        ClawLog("ImageSearch 오류 " name ": " e.Message)
        return false
    }
}

ClawWaitFor(name, timeoutMs) {
    deadline := A_TickCount + timeoutMs
    while (A_TickCount < deadline) {
        if (ClawSeen(name))
            return true
        Sleep(100)
    }
    return false
}

ClawHold(key, ms) {
    Send("{" key " down}")
    Sleep(ms)
    Send("{" key " up}")
}

; 한 판을 끝까지 진행하고 성공하면 true, 어느 단계든 안내가 안 보이면 false
ClawAttempt() {
    global config, clawTries

    if (!IsGTAActive())
        return false

    s := config["Settings"]

    if (!ClawWaitFor("play", 2000)) {
        ClawLog("중지: Press E 안내 없음")
        ShowTooltip("🧸 기계 앞이 아님 (Press E 안내 없음) - 중지", 2500)
        return false
    }

    PressKey("e")
    if (!ClawWaitFor("forward", s["ClawEnterTimeout"])) {
        ClawLog("중지: 게임 시작 안내 없음")
        ShowTooltip("🧸 게임 시작 확인 실패 - 이동하지 않고 중지", 2500)
        return false
    }

    ClawHold("w", s["ClawForwardMs"])
    if (!ClawWaitFor("right", 3000)) {
        ClawLog("중지: 오른쪽 단계 안내 없음")
        ShowTooltip("🧸 오른쪽 이동 단계 확인 실패 - 중지", 2500)
        return false
    }

    ClawHold("d", s["ClawRightMs"])
    if (!ClawWaitFor("down", 3000)) {
        ClawLog("중지: 내리기 단계 안내 없음")
        ShowTooltip("🧸 내리기 단계 확인 실패 - 중지", 2500)
        return false
    }

    PressKey("Enter")
    clawTries += 1

    ; 집게가 내려갔다 올라오고 다시 "Press E" 안내가 뜰 때까지 기다린다
    Sleep(3000)
    if (!ClawWaitFor("play", s["ClawResultTimeout"])) {
        ShowTooltip("🧸 결과 후 기계 앞 복귀 확인 실패 - 중지", 2500)
        return false
    }
    return true
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
        ShowTooltip("🧸 인형 뽑기 반복 중지 (이번 판까지 진행)", 1500)
    }
}

ClawLoopStep() {
    global clawLoopRunning, clawTries

    if (!clawLoopRunning)
        return

    if (!ClawAttempt()) {
        clawLoopRunning := false
        return
    }
    ShowTooltip("🧸 " clawTries "판 완료", 1500)
    SetTimer(ClawLoopStep, -1000)
}
