; 1920x1080 영어 나이트클럽 웹 UI. 판매 탭은 수량을 읽는 데만 쓴다.
; 재고는 OCR, 직원 연결은 선택된 품목의 사람 아이콘으로 각각 확인한다.
EarnWarehouseTask(manageSession := true) {
    if (manageSession && !EarnTaskMCTBegin())
        return false
    try {
        ok := EarnWarehouseManage()
    } finally {
        ended := manageSession ? EarnTaskMCTEnd() : true
    }
    return ok && ended
}

EarnWarehouseManage() {
    if (!EarnUIClick("mct_nightclub_card", 520, 525)
        || !EarnWaitSeen("nc_dj_menu", "", 5000))
        return EarnFail("창고: 나이트클럽 진입 실패")
    ; 한 번에 직원 하나를 옮기고, 다음 계획은 바뀐 전체 화면에서 새로 만든다.
    Loop 6 {
        goods := EarnWarehouseObserve(&stockOnly)
        if (!goods)
            return false
        EarnWarehouseSellNotice(goods)
        if (stockOnly) {
            EarnLog("창고: 판매 탭 재고상 옮길 일 없음(만재 품목과 빈자리 품목이 함께 있지 않음), 직원 관리 화면 생략")
            return EarnWarehouseReturn()
        }
        try moves := EarnWarehousePlan(goods)
        catch as e
            return EarnFail("창고: " e.Message)
        if (!moves.Length) {
            EarnLog("창고: 이동할 만재 담당 직원 또는 빈 목적지 없음")
            return EarnWarehouseReturn()
        }
        if (A_Index = 6)
            return EarnFail("창고: 직원 5명 재배정 뒤 상태 불일치")
        move := moves[1]
        if (!EarnWarehouseMove(move, goods))
            return false
        EarnLog("창고: 직원 " move.technician " " move.from " → " move.to " 배정 확인")
    }
    return false
}

; 직원을 옮기려면 만재 품목(옮길 직원)과 빈자리 품목(옮겨 갈 곳)이 함께 있어야 한다.
; 판매 탭 재고만으로 그렇지 않다고 나오면 직원 관리 화면에 들어가지 않고 stockOnly 로 알린다.
EarnWarehouseObserve(&stockOnly := false) {
    stockOnly := false
    if (!EarnUIClick("nc_dj_menu", 500, 920) || !EarnSleep(400))
        return false
    goods := EarnWarehouseReadStock(EarnReadScreen([728,130,880,420]))
    if (!goods)
        return EarnFail("창고: 7품목 현재/최대 재고 판독 실패")
    full := 0, open := 0
    for row in goods {
        if (row.count >= row.capacity)
            full += 1
        else
            open += 1
    }
    if (!full || !open) {
        stockOnly := true
        return goods
    }
    if (!EarnUIClick("nc_dj_menu", 500, 840)
        || !EarnWaitSeen("warehouse_title", [0.37,0.13,0.58,0.19], 3000))
        return EarnFail("창고: 직원 관리 화면 미확인")
    Loop 5 {
        technician := A_Index
        if (!EarnWarehouseSelect(technician))
            return false
        selected := EarnWarehouseSelectedGood()
        if (!selected)
            return EarnFail("창고: 직원 " technician "의 담당 품목 미확인")
        for row in goods {
            if (row.id = selected) {
                if (row.technician)
                    return EarnFail("창고: 같은 품목에 직원이 중복 판독됨")
                row.technician := technician
                row.unlocked := 1
            }
        }
    }
    ; 미배정 목적지는 글자가 밝고, 사람/체크 아이콘이 없는 활성 타일만 허용한다.
    lines := EarnReadScreen([728,548,876,264])
    if (!lines)
        return false
    for row in goods {
        if (!row.technician && row.count < row.capacity)
            row.unlocked := EarnWarehouseAvailable(row.id, lines) ? 1 : 0
    }
    return goods
}

EarnWarehouseTiles() {
    static tiles := Map(
        "cargo", [728,548,282,78,"Cargo and Shipments"],
        "sporting", [1025,548,282,78,"Sporting Goods"],
        "south_american", [1322,548,282,78,"South American Imports"],
        "pharmaceutical", [728,641,282,78,"Pharmaceutical Research"],
        "organic", [1025,641,282,78,"Organic Produce"],
        "printing", [1322,641,282,78,"Printing & Copying"],
        "cash", [728,734,282,78,"Cash Creation"])
    return tiles
}

EarnWarehouseSelect(technician) {
    if (technician < 1 || technician > 5)
        return false
    x := 728 + (technician-1)*179
    area := [x/1920,228/1080,(x+166)/1920,392/1080]
    ; 보유 중인 다섯 직원의 얼굴을 확인한다. 고용 버튼이나 금액에는 클릭하지 않는다.
    if (!EarnUIReady("warehouse_title", [0.37,0.13,0.58,0.19])
        || !EarnSeen("warehouse_staff_" technician, area))
        return EarnFail("창고: 보유 직원 " technician " 화면 미확인")
    return EarnUIClick("warehouse_title", x+80, 300, [0.37,0.13,0.58,0.19])
        && EarnSleep(200)
}

EarnWarehouseSelectedGood() {
    if (!EarnUIReady("warehouse_title", [0.37,0.13,0.58,0.19]))
        return ""
    selected := ""
    for id, tile in EarnWarehouseTiles() {
        ; 사람 아이콘 하단은 체크/만재 느낌표의 원보다 아래에 있다.
        ; 만재 품목의 선택된 사람은 회색이고 느낌표가 겹친다. 관측한 하단 모양을 별도로 확인한다.
        area := [(tile[1]+230)/1920,(tile[2]+43)/1080,
            (tile[1]+270)/1920,(tile[2]+70)/1080]
        if (EarnSeen("warehouse_person_foot", area, , , 45)
            || EarnSeen("warehouse_person_full_foot", area, , , 45)) {
            if (selected != "")
                return ""
            selected := id
        }
    }
    return selected
}

EarnWarehouseAvailable(id, lines) {
    if (!(lines is Array) || !EarnWarehouseTiles().Has(id))
        return false
    tile := EarnWarehouseTiles()[id], found := [], text := ""
    for row in lines {
        if (row.x >= tile[1]+5 && row.x <= tile[1]+222
            && row.y > tile[2]+6 && row.y < tile[2]+tile[4]-6) {
            text .= (text = "" ? "" : " ") row.text
            found.Push(row)
        }
    }
    if (text != tile[5] || !found.Length)
        return false
    for row in found
        if (!EarnWarehouseBrightLabel(row))
            return false
    return true
}

EarnWarehouseBrightLabel(row) {
    if (EarnAborted())
        return false
    previous := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        hwnd := IsGTAActive()
        if (!hwnd)
            return false
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        if (cw != 1920 || ch != 1080)
            return false
        CoordMode("Pixel", "Screen")
        bright := 0, total := 0
        y := Ceil(row.y-row.h/2)
        while (y < row.y+row.h/2) {
            x := Ceil(row.x-row.w/2)
            while (x < row.x+row.w/2) {
                color := PixelGetColor(cx+x, cy+y)
                bright += Min((color>>16)&255,(color>>8)&255,color&255) >= 210
                total += 1
                x += 2
            }
            y += 2
        }
        return total && bright >= 8 && bright/total >= 0.04
    } catch {
        return false
    } finally DllCall("SetThreadDpiAwarenessContext", "ptr", previous, "ptr")
}

EarnWarehouseMove(move, goods) {
    source := false, target := false
    for row in goods {
        if (row.id = move.from)
            source := row
        if (row.id = move.to)
            target := row
    }
    if (!source || !target || source.count != source.capacity
        || source.technician != move.technician || !target.unlocked
        || target.technician || target.count >= target.capacity)
        return EarnFail("창고: 재배정 조건 불일치")
    if (!EarnWarehouseSelect(move.technician) || EarnWarehouseSelectedGood() != move.from)
        return EarnFail("창고: 이동 직전 직원의 원래 담당 미확인")
    if (!EarnWarehouseAvailable(move.to, EarnReadScreen([728,548,876,264])))
        return EarnFail("창고: 이동 직전 목적지 활성 상태 미확인")
    tile := EarnWarehouseTiles()[move.to]
    if (!EarnUIClick("warehouse_title", tile[1]+120, tile[2]+38, [0.37,0.13,0.58,0.19]))
        return false
    ; 품목을 누르면 'Assign Technician' 확인창이 뜬다(1003 실측: Pharmaceutical → "accrue Meth?").
    ; 그 문구를 읽은 뒤에만 Confirm 을 한 번 누른다. 요청·확정은 다시 보내지 않는다.
    if (!EarnWarehouseAssignDialog(3000))
        return EarnFail("창고: 배정 확인창 미확인. 재배정 재전송 중단")
    if (!EarnWarehouseDialogClick(1160, 612))
        return false
    deadline := A_TickCount + 5000
    Loop {
        if (EarnWarehouseSelectedGood() = move.to)
            return true
        if (A_TickCount >= deadline || !EarnSleep(200)) {
            ; 확인창이 남아 있으면 Cancel 로 닫아 AFK 방지가 읽을 수 있는 화면으로 돌린다.
            if (EarnWarehouseAssignDialog(0))
                EarnWarehouseDialogClick(756, 612)
            return EarnFail("창고: 새 담당 품목 미확인. 재배정 재전송 중단")
        }
    }
}

; 확인창 영역 OCR 에 제목과 질문 문구가 함께 있어야 한다. waitMs=0 이면 한 번만 읽는다.
EarnWarehouseAssignDialog(waitMs) {
    deadline := A_TickCount + waitMs
    Loop {
        lines := EarnReadScreen([540,420,810,140])
        text := ""
        if (lines is Array)
            for row in lines
                text .= " " row.text
        if (InStr(text, "Assign Technician") && InStr(text, "assign this technician")) {
            EarnLog("창고: 배정 확인창 확인 (" Trim(text) ")")
            return true
        }
        if (A_TickCount >= deadline || !EarnSleep(200))
            return false
    }
}

; 확인창에는 템플릿 대신 위 OCR 확인을 쓴다. 좌표는 1920x1080 클라이언트 기준.
EarnWarehouseDialogClick(x, y) {
    if (EarnAborted())
        return false
    hwnd := IsGTAActive()
    if (!hwnd)
        return EarnFail("창고: 확인창 클릭 전 GTA 포커스 없음")
    previous := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        if (cw != 1920 || ch != 1080)
            return EarnFail("창고: 미지원 해상도")
        DllCall("SetCursorPos", "int", cx+x, "int", cy+y)
        if (!EarnSleep(80))
            return false
        SendEvent("{Blind}{LButton down}")
        try Sleep(100)
        finally SendEvent("{Blind}{LButton up}")
        DllCall("SetCursorPos", "int", cx+1880, "int", cy+1040)
        return EarnSleep(450)
    } finally {
        DllCall("SetThreadDpiAwarenessContext", "ptr", previous, "ptr")
    }
}

; 만재 품목이 셋 이상이면 직원을 옮겨도 생산이 막히므로 판매가 필요하다고 알린다.
; 만재 수가 바뀔 때만 로그·툴팁을 다시 띄우고, 오버레이에는 계속 표시한다.
EarnWarehouseSellNotice(goods) {
    global gEarnSellNotice
    previous := IsSet(gEarnSellNotice) ? gEarnSellNotice : ""
    full := ""
    count := 0
    for row in goods {
        if (row.capacity && row.count >= row.capacity)
            count += 1, full .= (full = "" ? "" : ", ") row.id
    }
    gEarnSellNotice := count >= 3 ? "나이트클럽 창고 만재 " count "개: 판매 필요" : ""
    if (gEarnSellNotice != "" && gEarnSellNotice != previous) {
        EarnLog("창고: " gEarnSellNotice " (" full ")")
        ShowTooltip("💰 " gEarnSellNotice, 10000)
    }
    return count
}

EarnWarehouseReturn() {
    return EarnUIClick("nc_dj_menu", 500, 596) && EarnSleep(500)
        && EarnUIBackToMCT("nc_dj_menu", 1)
}
