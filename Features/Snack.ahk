; === 스낵 먹기 ===
; M → Inventory(옛 이름 Health & Ammo) → Snacks → 첫 항목에서 Enter 를 SnackCount 번 → M 으로 닫기.
; 칸 수 기본값(Down 4, Down 2, 0)은 공개 매크로 두 개(2024-05, 2026-03)가 같은 값을 써서 가져왔고 이 PC 에서 실측하지 않았다.
; 안 맞으면 Config.ini [Settings] SnackMenuSteps / SnackSubSteps / SnackItemSteps 를 고친다.
EatSnack() {
    global config
    s := config["Settings"]
    ok := RunMenuPath("스낵", [s["SnackMenuSteps"], s["SnackSubSteps"], s["SnackItemSteps"]], s["SnackCount"], s["SnackCloseMenu"])
    ShowTooltip(ok ? "🍫 스낵 " s["SnackCount"] "개 입력 완료" : "스낵: 중단됨 (창 포커스 또는 전체 멈춤)", 1500)
}
