; === 화면 템플릿 확인 (공용) ===
; Images\<folder>\<가로>x<세로>\<name>.png 를 GTA 클라이언트 영역 안에서 찾는다. 해상도 폴더에 템플릿이 없으면 false(찾지 못함)로 본다.
; 템플릿의 FF00FF 칸은 투명으로 친다(반투명 메뉴 바탕 위 글자는 글자와 어두운 바탕만 남기고 가장자리는 투명으로 떠 둔다).
global gImageRoot := A_ScriptDir "\Images"   ; 템플릿 폴더 뿌리 (시험 스크립트가 바꿔 쓸 수 있게 전역)

; 실측 체력 막대의 가로 연속성. HUD 존재만 확인하며 전화·메뉴 제외는 소비자가 수행한다.
HealthHudVisible() {
    hwnd := IsGTAActive()
    if (!hwnd)
        return false
    previous := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        if (cw != 1920 || ch != 1080)
            return false
        CoordMode("Pixel", "Screen")
        colors := []
        Loop 16
            colors.Push(PixelGetColor(cx + 40 + (A_Index-1)*3, cy + 1053))
        return HealthHudColors(colors)
    } catch {
        return false
    } finally {
        if (previous)
            DllCall("SetThreadDpiAwarenessContext", "ptr", previous, "ptr")
    }
}

HealthHudColors(colors) {
    if (colors.Length != 16)
        return false
    green := 0
    for color in colors {
        r := (color >> 16) & 255, g := (color >> 8) & 255, b := color & 255
        green += g >= 100 && g-r >= 40 && g-b >= 40 && Abs(r-b) <= 25
    }
    return green >= 12
}

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
            ; 같은 템플릿은 한 번만 적는다 (선택/비선택 두 벌 중 하나만 있는 줄 템플릿처럼 없는 게 정상인 경우가 있다)
            static missing := Map()
            if (!missing.Has(img)) {
                missing[img] := 1
                MacroLog("screen", "템플릿 없음: " folder "\" cw "x" ch "\" name ".png")
            }
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

; TemplateSeen 이 찾은 자리(x, y)에서 name 템플릿이 정확히 같은 자리에 맞는지 본다.
; 글자만 남긴 템플릿 짝(<name>_bg: 글자에서 떨어진 바탕만 검정)으로 안내 상자의 어두운 바탕을 확인하는 데 쓴다.
TemplateAt(folder, name, x, y, variation := 90) {
    global gImageRoot
    hwnd := IsGTAActive()
    if (!hwnd)
        return false
    prev := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        img := gImageRoot "\" folder "\" cw "x" ch "\" name ".png"
        if (!FileExist(img))
            return false
        CoordMode("Pixel", "Screen")
        ; 검색은 한 줄씩 왼쪽부터라, 같은 자리에서 맞으면 첫 결과가 바로 (x, y)다.
        try {
            ; HDR MCT title backgrounds are 536px wide. The old 401px search
            ; rectangle could never contain them. Keep the exact-origin check.
            if (ImageSearch(&fx, &fy, x, y, Min(x + cw - 1, cx + cw - 1), Min(y + 60, cy + ch - 1),
                "*" variation " *Trans0xFF00FF " img))
                return fx = x && fy = y
        } catch as e {
            MacroLog("screen", "ImageSearch 오류 " folder "\" name ": " e.Message)
        }
        return false
    } finally {
        if (prev)
            DllCall("SetThreadDpiAwarenessContext", "ptr", prev, "ptr")
    }
}
