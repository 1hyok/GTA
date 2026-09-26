; === 화면 템플릿 확인 (공용) ===
; Images\<folder>\<가로>x<세로>\<name>.png 를 GTA 클라이언트 영역 안에서 찾는다. 해상도 폴더에 템플릿이 없으면 false(찾지 못함)로 본다.
; 템플릿의 FF00FF 칸은 투명으로 친다(반투명 메뉴 바탕 위 글자는 글자와 어두운 바탕만 남기고 가장자리는 투명으로 떠 둔다).
global gImageRoot := A_ScriptDir "\Images"   ; 템플릿 폴더 뿌리 (시험 스크립트가 바꿔 쓸 수 있게 전역)

; area 는 클라이언트 비율 [x1, y1, x2, y2] (0~1). 찾은 자리(화면 좌표)는 &fx, &fy.
TemplateSeen(folder, name, area := "", &fx := 0, &fy := 0, variation := 40) {
    global gImageRoot
    hwnd := IsGTAActive()
    if (!hwnd)
        return false
    ; 배율이나 모니터가 바뀌어도 창 크기 조회와 이미지 검색을 같은 물리 픽셀 좌표로 한다 (인형 뽑기와 같은 방식)
    prev := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        img := gImageRoot "\" folder "\" cw "x" ch "\" name ".png"
        if (!FileExist(img)) {
            MacroLog("screen", "템플릿 없음: " folder "\" cw "x" ch "\" name ".png")
            return false
        }
        a := IsObject(area) ? area : [0, 0, 1, 1]
        CoordMode("Pixel", "Screen")
        found := false
        try {
            found := ImageSearch(&fx, &fy, cx + Round(cw * a[1]), cy + Round(ch * a[2]),
                cx + Round(cw * a[3]) - 1, cy + Round(ch * a[4]) - 1, "*" variation " *Trans0xFF00FF " img)
        } catch as e {
            MacroLog("screen", "ImageSearch 오류 " folder "\" name ": " e.Message)
        }
        return found
    } finally {
        if (prev)
            DllCall("SetThreadDpiAwarenessContext", "ptr", prev, "ptr")
    }
}
