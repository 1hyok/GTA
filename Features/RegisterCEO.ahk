; === CEO 등록 ===
; M → Register as a Boss(SecuroServ) → SecuroServ CEO → Start an Organization.
; 칸 수 기본값(Down 1, Down 0, Enter 2)은 gtabase 상호작용 메뉴 문서 기준이고 이 PC 에서 실측하지 않았다.
; 안 맞으면 Config.ini [Settings] CEOMenuSteps / CEOSubSteps / CEOEnterCount 를 고친다.
RegisterCEO() {
    global config
    s := config["Settings"]
    ok := RunMenuPath("CEO 등록", [s["CEOMenuSteps"], s["CEOSubSteps"]], s["CEOEnterCount"], s["CEOCloseMenu"])
    ShowTooltip(ok ? "🏢 CEO 등록 입력 완료" : "CEO 등록: 중단됨 (창 포커스 또는 전체 멈춤)", 1500)
}
