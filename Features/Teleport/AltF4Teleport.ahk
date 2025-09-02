; === 새로운 F4 텔레포트 (Enter-Home-Click-Enter연타) ===

; 새로운 F4 텔레포트 실행 함수
ExecuteAltF4Teleport() {
   global config, altF4Running
   
   if (!IsGTAActive() || altF4Running)
       return
   
   altF4Running := true
   
   ; 설정값들
   mouseX := 1600  ; 하드코딩된 X 좌표
   mouseY := 250   ; 첫 번째 Y 좌표
   mouseY2 := 350  ; 두 번째 Y 좌표
   clickToEnterDelay := config["Settings"]["TeleportClickToEnterDelay"]  ; 클릭 후 엔터 연타 전 딜레이
   enterDuration := config["Settings"]["TeleportEnterDuration"]  ; 엔터 연타 지속시간 (ms)
   enterInterval := config["Settings"]["TeleportEnterInterval"]  ; 엔터 간격 (ms)
   
   ShowAltF4Message("🚀 새 F4 텔레포트 시작")
   
   ; 1. Enter 키 입력
   ShowAltF4Message("⏎ Enter 키 입력...", 300)
   PressKey("Enter")
   
   ; 2. Home 키 입력
   ShowAltF4Message("🏠 Home 키 입력...", 300)
   PressKey("Home")
   Sleep(6000)
   
   ; 3. 두 좌표 모두 클릭
   ShowAltF4Message("🖱️ 첫 번째 위치 클릭...", 300)
   Click(mouseX, mouseY)
   Sleep(100)
   
   ShowAltF4Message("🖱️ 두 번째 위치 클릭...", 300)
   Click(mouseX, mouseY2)
   
   ; 4. 클릭 후 대기
   ShowAltF4Message("⏳ 로딩 대기 중...", clickToEnterDelay)
   Sleep(clickToEnterDelay)
   
   ; 5. Enter 연타
   ShowAltF4Message("🔁 Enter 연타 시작...", 1000)
   startTime := A_TickCount
   while ((A_TickCount - startTime) < enterDuration) {
       PressKey("Enter")
       Sleep(enterInterval)
   }
   
   ShowAltF4Message("✅ 새 F4 텔레포트 완료!", 2000)
   altF4Running := false
}