; === 텔레포트 공통 변수 ===
global mcRunning := false
global altF4Running := false
global altF4StartTime := 0

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
