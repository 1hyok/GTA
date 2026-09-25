; === MC 등록 ===
; M → Register as a Boss(Motorcycle Club) → Motorcycle Club President → Start a Motorcycle Club.
; 칸 수 기본값(Down 1, Down 1, Enter 2)은 gtabase 상호작용 메뉴 문서 기준이고 이 PC 에서 실측하지 않았다.
; 안 맞으면 Config.ini [Settings] MCMenuSteps / MCSubSteps / MCEnterCount 를 고친다.
RegisterMC() {
    global config
    s := config["Settings"]
    ok := RunMenuPath("MC 등록", [s["MCMenuSteps"], s["MCSubSteps"]], s["MCEnterCount"], s["MCCloseMenu"])
    ShowTooltip(ok ? "🏍️ MC 등록 입력 완료" : "MC 등록: 중단됨 (창 포커스 또는 전체 멈춤)", 1500)
}
