; === 텔레포트 공통 변수 ===
global mocaRunning := false
global keyPressed := ""
global altF4Running := false
global altF4StartTime := 0

; 텔레포트 공통 함수
IsTeleportRunning() {
    global mocaRunning, altF4Running
    return mocaRunning || altF4Running
}

; 메인 텔레포트 함수들
TeleportMoca(key) {
    return ExecuteMocaTeleport(key)
}

TeleportAltF4() {
    return ExecuteAltF4Teleport()
}