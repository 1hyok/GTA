; === 텔레포트 공통 변수 ===
global mcRunning := false
global keyPressed := ""
global altF4Running := false
global altF4StartTime := 0

; 텔레포트 공통 함수
IsTeleportRunning() {
    global mcRunning, altF4Running
    return mcRunning || altF4Running
}

; 메인 텔레포트 함수들
TeleportMC(key) {
    return ExecuteMCTeleport(key)
}

TeleportAltF4() {
    return ExecuteAltF4Teleport()
}