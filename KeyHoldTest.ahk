#Requires AutoHotkey v2.0
#SingleInstance Force

; === 코어 모듈 로드 ===
#Include Core\PressKey.ahk
#Include Core\Common.ahk
#Include Core\ConfigLoader.ahk

; === 초기화 ===
LoadConfig()

; === 테스트용 단축키 ===
Hotkey("F10", (*) => TestMCMenuOpen())

TestMCMenuOpen() {
   global config
   
   if (!IsGTAActive())
       return
   
   ; 설정값 로드
   menuOpenDelay := config["Settings"]["MenuOpenDelay"]
   menuControlDelay := config["Settings"]["MenuControlDelay"]
   
   ShowTooltip("🧪 MC 메뉴 테스트 시작", 1000)
   
   ShowTooltip("📋 상호작용 메뉴 열기...", 800)
   PressKey("m")
;    Sleep(menuOpenDelay)

   
   ShowTooltip("🏍️ 모터사이클 클럽 두목 선택 시도...", 1000)
   PressKey("Enter")
   Sleep(menuControlDelay)
   
   ShowTooltip("✅ 테스트 완료 - 메뉴가 열렸는지 확인하세요", 3000)
}

; === 시작 메시지 ===
ShowTooltip("🧪 MC 메뉴 테스트 준비완료`nF10: 테스트 실행 | F12: 종료", 3000)

; === 종료 단축키 ===
Hotkey("F12", (*) => ExitApp())