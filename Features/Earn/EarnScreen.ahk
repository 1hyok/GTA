; 화면 OCR은 Windows의 영어 인식기를 사용한다. 실패/시간 초과는 빈 결과가 아닌 false다.
; 결제에는 문맥, 금액, 마지막 화면 재확인을 함께 요구한다.
EarnReadScreen(area, whiteText := false, deadlineTick := 0) {
    if (EarnAborted())
        return false
    if (deadlineTick && A_TickCount >= deadlineTick)
        return EarnFail("화면 판독 마감 시각 경과")
    if (!IsObject(area) || area.Length != 4 || area[1] < 0 || area[2] < 0
        || area[3] <= 0 || area[4] <= 0 || area[1]+area[3] > 1920 || area[2]+area[4] > 1080)
        return EarnFail("화면 판독 영역 오류")
    hwnd := IsGTAActive()
    if (!hwnd)
        return false
    previous := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
    catch as e
        return EarnFail("화면 판독 창 확인 실패: " e.Message)
    finally DllCall("SetThreadDpiAwarenessContext", "ptr", previous, "ptr")
    if (cw != 1920 || ch != 1080)
        return EarnFail("화면 판독: 1920x1080 클라이언트가 필요함")
    SplitPath(A_LineFile, , &sourceDir)
    script := sourceDir "\..\..\Core\EarnOcr.ps1"
    output := A_Temp "\gta-earn-ocr-" DllCall("GetCurrentProcessId") "-" A_TickCount ".tsv"
    command := '"' A_WinDir '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "'
        . script '" -X ' (cx+area[1]) ' -Y ' (cy+area[2]) ' -W ' area[3] ' -H ' area[4]
        . (whiteText ? ' -WhiteText' : '') ' -OutputPath "' output '"'
    handle := 0, processId := 0
    try {
        ; A caller can share one absolute deadline across several OCR reads.
        ; Window checks and command preparation must not launch work after it.
        deadline := deadlineTick ? Min(deadlineTick, A_TickCount + 15000) : A_TickCount + 15000
        if (A_TickCount >= deadline)
            return EarnFail("화면 판독 마감 시각 경과")
        Run(command, , "Hide", &processId)
        handle := DllCall("OpenProcess", "uint", 0x101001, "int", false, "uint", processId, "ptr")
        if (!handle) {
            if (ProcessExist(processId))
                ProcessClose(processId)
            return EarnFail("화면 판독 프로세스 확인 실패")
        }
        while (DllCall("WaitForSingleObject", "ptr", handle, "uint", 0, "uint") = 0x102) {
            if (EarnAborted() || A_TickCount >= deadline) {
                DllCall("TerminateProcess", "ptr", handle, "uint", 1)
                DllCall("WaitForSingleObject", "ptr", handle, "uint", 2000)
                return EarnFail("화면 판독 중단 또는 시간 초과")
            }
            Sleep(Min(50, Max(1, deadline - A_TickCount)))
        }
        if (EarnAborted() || A_TickCount >= deadline)
            return EarnFail("화면 판독 중단 또는 시간 초과")
        code := 1
        if (!DllCall("GetExitCodeProcess", "ptr", handle, "uint*", &code) || code || !FileExist(output))
            return EarnFail("화면 OCR 실패: 영어 인식기와 로그 확인 필요")
        result := []
        for line in StrSplit(FileRead(output, "UTF-8"), "`n", "`r") {
            cols := StrSplit(line, "`t")
            if (line = "" || line = "x`ty`tw`th`ttext")
                continue
            if (cols.Length != 5 || !IsNumber(cols[1]) || !IsNumber(cols[2])
                || !IsNumber(cols[3]) || !IsNumber(cols[4]))
                return EarnFail("화면 OCR 좌표 형식 오류")
            if (Number(cols[1])-cx < area[1] || Number(cols[1])-cx > area[1]+area[3]
                || Number(cols[2])-cy < area[2] || Number(cols[2])-cy > area[2]+area[4]
                || Number(cols[3]) <= 0 || Number(cols[4]) <= 0)
                return EarnFail("화면 OCR 좌표 범위 오류")
            result.Push({x: Number(cols[1])-cx, y: Number(cols[2])-cy,
                w: Number(cols[3]), h: Number(cols[4]), text: cols[5]})
        }
        if (EarnAborted() || A_TickCount >= deadline)
            return EarnFail("화면 판독 중단 또는 시간 초과")
        return result
    } catch as e {
        if (handle && DllCall("WaitForSingleObject", "ptr", handle, "uint", 0, "uint") = 0x102) {
            DllCall("TerminateProcess", "ptr", handle, "uint", 1)
            DllCall("WaitForSingleObject", "ptr", handle, "uint", 2000)
        }
        return EarnFail("화면 OCR 오류: " e.Message)
    } finally {
        if (handle)
            DllCall("CloseHandle", "ptr", handle)
        if (FileExist(output))
            FileDelete(output)
    }
}

EarnFindText(lines, pattern) {
    if (!IsObject(lines))
        return false
    for row in lines
        if (RegExMatch(row.text, pattern))
            return row
    return false
}

EarnScreenText(lines) {
    text := ""
    if (IsObject(lines))
        for row in lines
            text .= row.text "`n"
    return text
}

; 금액은 $와 정수를 요구한다. OCR의 O/I를 숫자로 바꿔 금액을 추측하지 않는다.
EarnReadDollars(text) {
    ; Multiple prices, split digits and OCR letters must never become a cheaper quote.
    if (StrLen(text) - StrLen(StrReplace(text, "$")) != 1)
        return -1
    if (!RegExMatch(text, "\$\h*(0|[1-9][0-9]{0,2}(?:,[0-9]{3})+|[1-9][0-9]*)(?![\p{L}\p{N}_,.+-]|\s+[0-9])", &m))
        return -1
    digits := StrReplace(m[1], ",")
    if (StrLen(digits) > 19 || (StrLen(digits) = 19 && StrCompare(digits, "9223372036854775807") > 0))
        return -1
    try return Integer(digits)
    catch
        return -1
}

EarnMenuRowSelected(row) {
    if (!IsObject(row) || EarnAborted())
        return false
    hwnd := IsGTAActive()
    if (!hwnd)
        return false
    previous := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        CoordMode("Pixel", "Screen")
        WinGetClientPos(&cx, &cy, , , "ahk_id " hwnd)
        c := PixelGetColor(cx+32, cy+Round(row.y))
        return ((c >> 16) & 255) > 170 && ((c >> 8) & 255) > 170 && (c & 255) > 170
    } catch {
        return false
    } finally DllCall("SetThreadDpiAwarenessContext", "ptr", previous, "ptr")
}

; 이미 판독한 메뉴에서 목표 줄만 고른다. Enter는 호출자가 새 화면으로 확인한다.
EarnSelectText(pattern, heading, maxPress := 12) {
    Loop maxPress + 1 {
        lines := EarnReadScreen([25,15,450,800])
        if (!IsObject(lines) || !EarnFindText(lines, heading))
            return false
        row := EarnFindText(lines, pattern)
        if (row && EarnMenuRowSelected(row))
            return row
        if (A_Index > maxPress || !EarnPress("Down"))
            return false
    }
    return false
}
