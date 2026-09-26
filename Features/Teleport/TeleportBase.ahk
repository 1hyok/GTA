; === 텔레포트 공통 변수 ===
global mcRunning := false
global altF4Running := false
global altF4StartTime := 0
; 작텔 종료창 대기의 시작 시각(A_TickCount, 대기 중이 아니면 0)과 No 를 누르기 전 최소 대기. 오버레이가 "작텔 대기 N/60초" 로 읽는다
global gJobWarpStart := 0
global gJobWarpMinMs := 0

; 텔레포트 공통 함수
IsTeleportRunning() {
    global mcRunning, altF4Running
    return mcRunning || altF4Running
}

; 메인 텔레포트 함수들. role 은 "CEO" 또는 "MC" (재등록할 보스 종류)
TeleportMC(role) {
    return ExecuteMCTeleport(role)
}

TeleportAltF4() {
    return ExecuteAltF4Teleport()
}
