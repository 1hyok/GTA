; === 텔레포트 공통 변수 ===
global mcRunning := false
global altF4Running := false
global altF4StartTime := 0
; 작텔 종료창 대기의 시작 시각(A_TickCount, 대기 중이 아니면 0)과 No 를 누르기 전 최소 대기. 오버레이가 "작텔 대기 N/60초" 로 읽는다
global gJobWarpStart := 0
global gJobWarpMinMs := 0
; 스팀 봇 작텔(BotWarp.ahk) 진행 중
global botWarpRunning := false

; 텔레포트 공통 함수. 작텔 둘이 겹치면 한쪽의 Enter 가 다른 쪽의 종료 확인창에 들어갈 수 있어 하나만 돌게 한다
IsTeleportRunning() {
    global mcRunning, altF4Running, botWarpRunning
    return mcRunning || altF4Running || botWarpRunning
}

; 메인 텔레포트 함수들. role 은 "CEO" 또는 "MC" (재등록할 보스 종류)
TeleportMC(role) {
    return ExecuteMCTeleport(role)
}

TeleportAltF4() {
    return ExecuteAltF4Teleport()
}

TeleportBotWarp() {
    return ExecuteBotWarp()
}

; 스팀 봇 작텔. Main.ahk 대신 여기서 포함한다 (이 파일 기준 경로)
#Include %A_LineFile%\..\BotWarp.ahk
