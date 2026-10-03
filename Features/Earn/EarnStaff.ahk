; Vinewood 앱 직원 파견. 화면의 선택·상세 문구와 파견 후 상태를 함께 확인한다.
EarnVinewoodStaffTask() {
    global config
    s := config["Settings"]
    bail := s["EarnBailAgents"], cargo := s["EarnCargoStaff"]
    if (!bail && !cargo)
        return true
    if (!EarnVinewoodOpen() || !EarnStaffRoot())
        return false
    if (bail && !EarnStaffBailAgents())
        return false
    if (cargo) {
        if (!EarnStaffRoot() || !EarnStaffCargoWarehouses())
            return false
    }
    return EarnVinewoodClose()
}

; 확인한 앱 메뉴만 거슬러 올라간다. 알 수 없는 화면에는 Backspace를 보내지 않는다.
EarnStaffRoot() {
    Loop 4 {
        lines := EarnReadScreen([25,125,450,263])
        if (!EarnStaffUniqueRow(lines, "i)^THE VINEWOOD CLUB APP$"))
            return EarnFail("직원: Vinewood 앱 제목 미확인")
        if (!EarnStaffUniqueRow(lines, "i)^Manage Staff Members$")
            && !(EarnStaffUniqueRow(lines, "i)^Warehouse$") && EarnStaffUniqueRow(lines, "i)^Bail Office$"))
            && !EarnStaffBailIdentity(lines, 1) && !EarnStaffBailIdentity(lines, 2)) {
            white := EarnReadScreen([25,125,450,263], true)
            if (!EarnStaffUniqueRow(white, "i)^THE VINEWOOD CLUB APP$"))
                return EarnFail("직원: Vinewood 앱 제목 재확인 실패")
            if (EarnStaffUniqueRow(white, "i)^Manage Staff Members$")
                || (EarnStaffUniqueRow(white, "i)^Warehouse$") && EarnStaffUniqueRow(white, "i)^Bail Office$")))
                lines := white
        }
        if (EarnStaffUniqueRow(lines, "i)^Warehouse$") && EarnStaffUniqueRow(lines, "i)^Bail Office$"))
            return true
        if (EarnStaffUniqueRow(lines, "i)^Manage Staff Members$")) {
            if (!EarnStaffSelectEnter("i)^Manage Staff Members$", 6))
                return EarnFail("직원: 직원 관리 목록 진입 실패")
            continue
        }
        if ((EarnStaffBailIdentity(lines, 1) || EarnStaffBailIdentity(lines, 2))
            || IsObject(EarnStaffReadCargo())) {
            if (!EarnPress("Backspace") || !EarnSleep(700))
                return false
            continue
        }
        return EarnFail("직원: 직원 관리 메뉴 위치 미확인")
    }
    return EarnFail("직원: 직원 관리 메뉴 복귀 제한")
}

EarnStaffBailAgents() {
    if (!EarnStaffSelectEnter("i)^Bail Office$", 3))
        return EarnFail("직원: 보석 사무소 목록 진입 실패")
    ; 두 요원이 모두 작업 중이면 Bail Office 줄이 회색이고 Enter 가 무시된다(1003 17:39 실측).
    ; 그대로 Agent 1 을 찾으면 Down 이 다른 줄로 넘어가므로, 목록이 그대로면 건너뛴다.
    if (!EarnStaffMenuTarget("i)^Agent 1$") && EarnStaffMenuTarget("i)^Warehouse$")
        && EarnStaffMenuTarget("i)^Bail Office$")) {
        EarnLog("직원: 보석 사무소 비활성(요원 모두 작업 중), 건너뜀")
        return true
    }
    Loop 2 {
        agent := A_Index
        if (!EarnStaffSelectText("i)^Agent " agent "$", 2))
            return EarnFail("직원: 보석 집행 요원 " agent " 선택 실패")
        state := EarnStaffReadBail(agent)
        if (state = "busy") {
            EarnLog("직원: 보석 집행 요원 " agent " 작업 중, 건너뜀")
            continue
        }
        if (state != "ready")
            return EarnFail("직원: 보석 집행 요원 " agent " 준비 문구 미확인")
        if (EarnStaffReadBail(agent) != "ready")
            return EarnFail("직원: 보석 집행 요원 " agent " 파견 직전 상태 변경")
        deadline := A_TickCount + 60000
        if (!EarnPress("Enter") || !EarnSleep(700))
            return false
        if (!EarnStaffWaitBusy("bail", agent, deadline))
            return EarnFail("직원: 보석 집행 요원 " agent " 파견 결과 미확인, 재요청 중단")
        EarnLog("직원: 보석 집행 요원 " agent " 파견 확인")
    }
    return true
}

EarnStaffCargoWarehouses() {
    if (!EarnStaffSelectEnter("i)^Warehouse$", 3))
        return EarnFail("직원: 스페셜 패키지 창고 목록 진입 실패")
    current := EarnStaffReadCargo()
    if (!IsObject(current) || current.index != 1)
        return EarnFail("직원: 스페셜 패키지 첫 창고·목록 판독 실패")
    count := current.count, visited := Map()
    Loop count {
        if (A_Index > 1)
            current := EarnStaffReadCargo()
        if (!IsObject(current) || current.index != A_Index || current.count != count
            || visited.Has(StrLower(current.name)))
            return EarnFail("직원: 스페셜 패키지 창고 순서·목록 변경")
        visited[StrLower(current.name)] := true
        if (current.state = "busy" || current.state = "full") {
            EarnLog("직원: " current.name (current.state = "busy" ? " 조달 중" : " 만재") ", 건너뜀")
        } else {
            if (current.state != "ready" || current.price != 7500)
                return EarnFail("직원: " current.name " 준비 문구 또는 $7,500 미확인")
            fresh := EarnStaffReadCargo()
            if (!EarnStaffSameWarehouse(fresh, current) || fresh.state != "ready" || fresh.price != 7500)
                return EarnFail("직원: " current.name " 조달 직전 선택·가격·상태 변경")
            deadline := A_TickCount + 60000
            if (!EarnPress("Enter") || !EarnSleep(700))
                return false
            if (!EarnStaffWaitBusy("cargo", current, deadline))
                return EarnFail("직원: " current.name " 조달 결과 미확인, 재구매 중단")
            EarnLog("직원: " current.name " $7,500 조달 확인")
        }
        if (A_Index < count && (!EarnPress("Down") || !EarnSleep(200)))
            return false
    }
    return true
}

; 주문 처리 중에는 준비 문구가 남을 수 있다. 한 번만 요청하고 최대 60초 관측한다.
EarnStaffWaitBusy(kind, target, deadline) {
    deadline := Min(deadline, A_TickCount + 60000)
    Loop 121 {
        if (A_TickCount >= deadline || EarnAborted())
            return false
        if (kind = "bail") {
            state := EarnStaffReadBail(target, &identityValid, deadline)
            if (!identityValid)
                return false
        } else {
            current := EarnStaffReadCargo(target, deadline)
            if (!EarnStaffSameWarehouse(current, target))
                return false
            state := current.state
        }
        if (A_TickCount >= deadline || EarnAborted())
            return false
        if (state = "busy")
            return true
        ; 같은 앱·대상 선택이 유지되면 일시적인 설명 OCR 실패에는 읽기만 재시도한다.
        if ((state != "ready" && state != "invalid") || !EarnSleep(Max(0, Min(500, deadline-A_TickCount))))
            return false
    }
    return false
}

EarnStaffSameWarehouse(current, expected) {
    return IsObject(current) && IsObject(expected) && current.name = expected.name
        && current.index = expected.index && current.count = expected.count
}

; 선택 행의 흰 배경에서 이름과 가격을 읽는다. 회색인 작업 중/만재 행은 가격이 없어도 건너뛴다.
EarnStaffReadCargo(pending := false, deadline := 0) {
    heading := EarnStaffUniqueRow(EarnReadScreen([25,125,450,40], false, deadline), "i)^THE VINEWOOD CLUB APP$")
    if (!heading)
        return false
    selectedIndex := 0
    Loop 5 {
        if (EarnMenuRowSelected({y:heading.y + 37*A_Index})) {
            if (selectedIndex)
                return false
            selectedIndex := A_Index
        }
    }
    if (!selectedIndex)
        return false
    rowY := heading.y + 37*selectedIndex
    label := EarnStaffCargoLabel(EarnReadScreen([28,Round(rowY-17),434,35], false, deadline), rowY)
    if (!label)
        return false
    detail := EarnStaffCargoDetail(EarnReadScreen([28,Round(heading.y+56),434,229], true, deadline), heading)
    if (!EarnMenuRowSelected({y:rowY}) || (deadline && A_TickCount >= deadline))
        return false
    if (!detail) {
        if (IsObject(pending) && pending.name = label.name && pending.index = selectedIndex)
            return {name:label.name, price:label.price, index:selectedIndex, count:pending.count, state:"invalid"}
        return false
    }
    if (selectedIndex > detail.count)
        return false
    if (detail.state = "ready" && label.price != 7500) {
        if (!IsObject(pending) || pending.name != label.name || pending.index != selectedIndex || label.price != -1)
            return false
        detail.state := "invalid"
    }
    return {name:label.name, price:label.price, index:selectedIndex, count:detail.count, state:detail.state}
}

EarnStaffCargoLabel(lines, rowY) {
    if (!(lines is Array))
        return false
    name := "", price := -1
    for row in lines {
        if (Abs(row.y-rowY) > 10)
            return false
        if (InStr(row.text, "$")) {
            if (price != -1 || (price := EarnReadDollars(row.text)) < 0)
                return false
            if (RegExMatch(row.text, "^(.+?)\h+\$[0-9,]+$", &match)) {
                if (name != "")
                    return false
                name := match[1]
            } else if (!RegExMatch(row.text, "^\$[0-9,]+$") || row.x < 360)
                return false
        } else {
            if (name != "" || row.x >= 360)
                return false
            name := row.text
        }
    }
    if (!RegExMatch(name, "^[A-Za-z0-9][A-Za-z0-9 '&().-]*$"))
        return false
    return {name:name, price:price}
}

; 상세 첫 줄의 위치와 37px 행 간격으로 실제 1~5개 목록의 끝을 확인한다.
EarnStaffCargoDetail(lines, heading) {
    if (!(lines is Array) || !heading)
        return false
    found := false
    for row in lines {
        if (!RegExMatch(row.text, "^(?:Send your Warehouse|Your Warehouse|There is no more room)"))
            continue
        count := Round((row.y-heading.y-44)/37)
        if (found || count < 1 || count > 5 || Abs(row.y-heading.y-37*count-44) > 8)
            return false
        detail := EarnStaffFooter(lines, {y:heading.y+37*count,h:22})
        state := detail = "Send your Warehouse staff member out on a job." ? "ready"
            : detail = "Your Warehouse staff member is currently out on a job." ? "busy"
            : detail = "There is no more room to store cargo for this property." ? "full" : "invalid"
        if (state = "invalid")
            return false
        found := {state:state,count:count}
    }
    return found
}

EarnStaffReadBail(agent, &identityValid := false, deadline := 0) {
    identityValid := false
    lines := EarnReadScreen([25,125,450,115], false, deadline)
    if (!EarnStaffBailIdentity(lines, agent))
        return "invalid"
    identityValid := true
    last := EarnStaffBailLastRow(lines)
    detail := EarnReadScreen([28,Round(last.y+22),434,75], true, deadline)
    identityValid := EarnStaffBailIdentity(lines, agent)
    if (!identityValid)
        return "invalid"
    if (deadline && A_TickCount >= deadline)
        return "invalid"
    if (!(detail is Array))
        return "invalid"
    for row in detail
        lines.Push(row)
    return EarnStaffBailState(lines, agent)
}

EarnStaffBailIdentity(lines, agent) {
    if (agent != 1 && agent != 2)
        return false
    heading := EarnStaffUniqueRow(lines, "i)^THE VINEWOOD CLUB APP$")
    if (!heading)
        return false
    observed := Map()
    for row in lines {
        if (!RegExMatch(row.text, "i)^Agent ([0-9]+)$", &match))
            continue
        agentNumber := Integer(match[1])
        if (agentNumber < 1 || agentNumber > 2 || observed.Has(agentNumber) || Abs(row.y-heading.y-37*agentNumber) > 8)
            return false
        observed[agentNumber] := row
    }
    if (!observed.Has(agent) || !EarnMenuRowSelected(observed[agent])
        || EarnMenuRowSelected({y:heading.y+37*(agent = 1 ? 2 : 1)}))
        return false
    return true
}

; 비선택 회색 요원명이 OCR에서 빠져도 선택된 요원 신원과 고정된 두 행 구조는 확인한다.
EarnStaffBailLastRow(lines) {
    last := EarnStaffUniqueRow(lines, "i)^Agent 2$")
    if (last)
        return last
    heading := EarnStaffUniqueRow(lines, "i)^THE VINEWOOD CLUB APP$")
    return heading ? {y:heading.y+74,h:22} : false
}

EarnStaffBailState(lines, agent) {
    if (!EarnStaffBailIdentity(lines, agent))
        return "invalid"
    second := EarnStaffBailLastRow(lines)
    detail := EarnStaffFooter(lines, second)
    if (detail = "Send your Bail Office staff member out on a job.")
        return "ready"
    if (detail = "Your Bail Office staff member is currently out on a job.")
        return "busy"
    return "invalid"
}

; 같은 이름의 행이 둘 이상이면 선택/금액 문맥을 특정할 수 없다.
EarnStaffUniqueRow(lines, pattern) {
    if (!(lines is Array))
        return false
    found := false
    for row in lines {
        if (!IsObject(row) || !row.HasOwnProp("text"))
            return false
        if (RegExMatch(row.text, pattern)) {
            if (found)
                return false
            found := row
        }
    }
    return found
}

; OCR은 가운데 좌표를 반환한다. 마지막 메뉴 행 아래의 설명만 위에서 아래로 합친다.
EarnStaffFooter(lines, lastRow) {
    if (!(lines is Array) || !IsObject(lastRow))
        return ""
    bottom := lastRow.y + lastRow.h / 2
    pieces := []
    for row in lines {
        if (row.y <= bottom + 8 || row.y >= bottom + 120)
            continue
        if (row.x - row.w / 2 < 25 || row.x + row.w / 2 > 475)
            return ""
        at := pieces.Length + 1
        Loop pieces.Length {
            if (row.y < pieces[A_Index].y) {
                at := A_Index
                break
            }
        }
        pieces.InsertAt(at, row)
    }
    detail := ""
    for row in pieces
        detail .= (detail = "" ? "" : " ") row.text
    return RegExReplace(Trim(detail), "\s+", " ")
}

; 이동 직후의 선택을 새 화면으로 다시 확인한 다음 Enter를 한 번 보낸다.
EarnStaffSelectEnter(pattern, maxPress) {
    if (!EarnStaffSelectText(pattern, maxPress))
        return false
    row := EarnStaffMenuTarget(pattern)
    if (!row || !EarnMenuRowSelected(row))
        return false
    return EarnPress("Enter") && EarnSleep(700)
}

; 투명 배경의 흰 메뉴 글자만 보완한다. 선택 행의 검정 글자는 일반 판독을 먼저 쓴다.
EarnStaffMenuTarget(pattern, &validMenu := false) {
    validMenu := false
    for whiteText in [false,true] {
        lines := EarnReadScreen([25,125,450,263], whiteText)
        heading := EarnStaffUniqueRow(lines, "i)^THE VINEWOOD CLUB APP$")
        if (!heading)
            return false
        found := false
        for row in lines {
            if (!RegExMatch(row.text, pattern))
                continue
            if (found)
                return false
            position := Round((row.y-heading.y)/37)
            if (position < 1 || position > 6 || Abs(row.y-heading.y-37*position) > 8)
                return false
            found := row
        }
        if (found) {
            validMenu := true
            return found
        }
    }
    validMenu := true
    return false
}

EarnStaffSelectText(pattern, maxPress) {
    Loop maxPress+1 {
        row := EarnStaffMenuTarget(pattern, &validMenu)
        if (!validMenu)
            return false
        if (row && EarnMenuRowSelected(row))
            return row
        if (A_Index > maxPress || !EarnPress("Down") || !EarnSleep(200))
            return false
    }
    return false
}
