; === 화면 템플릿 확인 (공용) ===
; Images\<folder>\<가로>x<세로>\<name>.png 를 GTA 클라이언트 영역 안에서 찾는다. 해상도 폴더에 템플릿이 없으면 false(찾지 못함)로 본다.
; 템플릿의 FF00FF 칸은 투명으로 친다(반투명 메뉴 바탕 위 글자는 글자와 어두운 바탕만 남기고 가장자리는 투명으로 떠 둔다).
global gImageRoot := A_ScriptDir "\Images"   ; 템플릿 폴더 뿌리 (시험 스크립트가 바꿔 쓸 수 있게 전역)
; 원본 템플릿이 안 맞을 때 차례로 찾아볼 밝기 사본 배율.
; 1010 실측: HDR 화면이 예전 템플릿보다 채널마다 약 1.55배 밝았다(템플릿 값 165 이상은 255로 포화).
; 이 배율 사본으로 MCT·벙커·DJ·창고 템플릿 16종이 차이 0~8로 맞았고, 다른 화면에는 맞지 않았다.
global gTemplateGains := ["1.55"]

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
        x1 := cx + Round(cw * a[1]), y1 := cy + Round(ch * a[2])
        x2 := cx + Round(cw * a[3]) - 1, y2 := cy + Round(ch * a[4]) - 1
        try {
            found := ImageSearch(&fx, &fy, x1, y1, x2, y2, "*" variation " *Trans0xFF00FF " img)
        } catch as e {
            MacroLog("screen", "ImageSearch 오류 " folder "\" name ": " e.Message)
        }
        if (!found) {
            ; 화면 밝기가 템플릿을 뜰 때와 다르면 같은 그림을 밝힌 사본으로 한 번 더 찾는다.
            for gainImg in TemplateGainImages(folder, cw "x" ch, name) {
                try found := ImageSearch(&fx, &fy, x1, y1, x2, y2, "*" variation " *Trans0xFF00FF " gainImg)
                if (found)
                    break
            }
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
                "*" variation " *Trans0xFF00FF " img) && fx = x && fy = y)
                return true
        } catch as e {
            MacroLog("screen", "ImageSearch 오류 " folder "\" name ": " e.Message)
        }
        for gainImg in TemplateGainImages(folder, cw "x" ch, name) {
            try {
                if (ImageSearch(&fx, &fy, x, y, Min(x + cw - 1, cx + cw - 1), Min(y + 60, cy + ch - 1),
                    "*" variation " *Trans0xFF00FF " gainImg) && fx = x && fy = y)
                    return true
            }
        }
        return false
    } finally {
        if (prev)
            DllCall("SetThreadDpiAwarenessContext", "ptr", prev, "ptr")
    }
}

; 원본 템플릿 대신 찾아볼 밝기 사본들의 경로. 사본은 %TEMP%\gta-template-gain\<배율>\<folder>\<해상도> 에
; 폴더 단위로 한 번 만들고, 원본 폴더의 파일 수·최근 수정 시각이 바뀌면 다시 만든다.
TemplateGainImages(folder, res, name) {
    global gImageRoot, gTemplateGains
    static ready := Map()
    out := []
    if (!IsSet(gTemplateGains) || !(gTemplateGains is Array))
        return out
    for gain in gTemplateGains {
        dst := A_Temp "\gta-template-gain\" gain "\" folder "\" res
        if (!ready.Has(dst))
            ready[dst] := TemplateGainBuild(gImageRoot "\" folder "\" res, dst, gain)
        if (ready[dst] && FileExist(dst "\" name ".png"))
            out.Push(dst "\" name ".png")
    }
    return out
}

TemplateGainBuild(src, dst, gain) {
    if (!DirExist(src))
        return false
    count := 0, newest := ""
    Loop Files src "\*.png" {
        count++
        if (StrCompare(A_LoopFileTimeModified, newest) > 0)
            newest := A_LoopFileTimeModified
    }
    stamp := count "|" newest "|" gain
    marker := dst "\.stamp"
    try {
        if (FileExist(marker) && FileRead(marker, "UTF-8") = stamp)
            return true
    }
    SplitPath(A_LineFile, , &coreDir)
    command := '"' A_WinDir '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "'
        . coreDir '\TemplateGain.ps1" -Source "' src '" -Destination "' dst '" -Gain ' gain
    try exitCode := RunWait(command, , "Hide")
    catch as e {
        MacroLog("screen", "밝기 사본 생성 실패 " dst ": " e.Message)
        return false
    }
    if (exitCode != 0) {
        MacroLog("screen", "밝기 사본 생성 실패 " dst ": exit=" exitCode)
        return false
    }
    try FileDelete(marker)
    try FileAppend(stamp, marker, "UTF-8")
    MacroLog("screen", "밝기 사본 생성 " dst)
    return true
}
