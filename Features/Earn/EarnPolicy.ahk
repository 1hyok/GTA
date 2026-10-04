; 벙커 구매 계획. 화면 판독값으로 다음 20% 소모 경계를 고른다.
; 기본 6720초는 풀업그레이드·제조 전용·기본 속도에서 112분(4칸)이다.
; 남은 1칸은 약 28분 생산분이므로 약 10분 배송 동안에도 생산을 이어간다.
; waitMs는 같은 조건의 예상 시간이다. 실제 소비처는 다시 화면을 읽어야 한다.
; buy=true도 결제 허가는 아니다. 배송 중이 아닌지 확인하고, 확인창의 실제
; 가격을 EarnBunkerPriceAllowed로 검사한 뒤에만 결제한다.
EarnBunkerOrderPlan(supplyFraction, stockFraction, requestedSeconds := 6720) {
    if (!IsNumber(supplyFraction) || !IsNumber(stockFraction)
        || supplyFraction < 0 || supplyFraction > 1 || stockFraction < 0 || stockFraction > 1)
        return {buy: false, bars: 0, waitMs: 300000, reason: "invalid_read"}
    if (!IsNumber(requestedSeconds) || requestedSeconds < 1680 || requestedSeconds > 8400
        || Mod(requestedSeconds, 1680) != 0)
        return {buy: false, bars: 0, waitMs: 300000, reason: "invalid_interval"}

    ; 기존 MCT 막대 판독의 가득 참 기준을 유지한다. 생산 중단 중에는 구매하지 않는다.
    if (stockFraction >= 0.97)
        return {buy: false, bars: 0, waitMs: 300000, reason: "stock_full"}

    requestedBars := Round(requestedSeconds / 1680)
    missing := 1 - supplyFraction
    nearestBars := Round(missing * 5)
    boundaryLag := missing - nearestBars / 5
    ; 소모 경계에 도달한 뒤의 작은 후행 오차만 허용한다. 경계보다 먼저 사지 않는다.
    ; 현재 막대는 3px 간격 130표본이며 20%는 26표본이다. 이 판독값은 내부 보급량이
    ; 아니므로 실제 가격 검사도 필요하다. 빈 경계는 0 판독을 요구한다.
    atBoundary := nearestBars >= requestedBars && nearestBars <= 5
        && (nearestBars = 5 ? supplyFraction = 0 : boundaryLag >= -1.0e-9 && boundaryLag <= 0.003)
    if (atBoundary)
        return {buy: true, bars: nearestBars, waitMs: 0, reason: "boundary"}

    ; 75%/55%처럼 이미 경계를 지나쳤다면 비싼 올림값으로 사지 않고 다음 경계를 기다린다.
    nextBars := Min(5, Max(requestedBars, Floor(missing * 5) + 1))
    remainingFraction := Max(0, nextBars / 5 - missing)
    return {buy: false, bars: nextBars, waitMs: Max(1000, Round(remainingFraction * 8400000)), reason: "wait_boundary"}
}

; OCR/화면 판독이 정확한 정수 금액을 돌려줄 때만 허용한다.
; 할인·이벤트 가격도 추측으로 허용하지 않는다. 알려진 가격 계약을 별도로 갱신해야 한다.
EarnBunkerPriceAllowed(price, bars) {
    return IsNumber(price) && IsNumber(bars) && bars >= 1 && bars <= 5
        && Mod(bars, 1) = 0 && price = bars * 15000
}

; 나이트클럽 창고 직원 재배정. 입력은 7품목의 현재 화면 판독 결과이며 변경하지 않는다.
; 각 행: {id, count, capacity, unlocked: 0/1, technician: 0..5}.
; 누락/중복/범위 오류는 ValueError. capacity는 화면값을 사용하고 저장층 수를 추정하지 않는다.
; 직원 수만큼 '시간당 판매가가 가장 높은, 만재가 아닌 활성 품목'에 직원을 둔다. 그 밖(만재·더 싼 품목)에 있는 직원이
; 그 안의 빈 품목으로 옮긴다. 판매 뒤 비싼 품목이 비면 싼 품목에서 생산 중인 직원도 데려온다.
; 시간당 판매가(장비 업그레이드, 단가/개당 생산 시간): 남미 27000/60분, 의약 11475/30분, 현금 4725/15분,
; 화물 10000/35분, 스포츠 5000/20분, 유기농 2025/10분, 인쇄 1350/7.5분
; → 27000 > 22950 > 18900 > 17143 > 15000 > 12150 > 10800 (gtaguide.net 창고 관리, 판매 단가는 위키 Sell Goods 표).
EarnWarehousePlan(goods) {
    priority := EarnWarehousePriority()
    if (!(goods is Array) || goods.Length != priority.Length)
        throw ValueError("EarnWarehousePlan: exactly seven goods are required")

    known := Map(), rows := Map(), assigned := Map()
    for id in priority
        known[id] := true
    for row in goods {
        if (!IsObject(row))
            throw ValueError("EarnWarehousePlan: each good must be an object")
        for field in ["id", "count", "capacity", "unlocked", "technician"] {
            if (!row.HasProp(field))
                throw ValueError("EarnWarehousePlan: missing " field)
        }
        if (Type(row.id) != "String" || !known.Has(row.id) || rows.Has(row.id))
            throw ValueError("EarnWarehousePlan: unknown or duplicate good")
        if (!IsInteger(row.count) || !IsInteger(row.capacity) || row.capacity <= 0
            || row.count < 0 || row.count > row.capacity)
            throw ValueError("EarnWarehousePlan: invalid count/capacity for " row.id)
        if (!IsInteger(row.unlocked) || (row.unlocked != 0 && row.unlocked != 1))
            throw ValueError("EarnWarehousePlan: unlocked must be 0 or 1")
        if (!IsInteger(row.technician) || row.technician < 0 || row.technician > 5)
            throw ValueError("EarnWarehousePlan: technician must be 0 through 5")
        if (row.technician && assigned.Has(row.technician))
            throw ValueError("EarnWarehousePlan: a technician is assigned more than once")
        if (row.technician)
            assigned[row.technician] := true
        ; 계획 작성 중에는 이 사본만 변경한다. 호출자의 관측 결과는 보존한다.
        rows[row.id] := {id: row.id, count: row.count, capacity: row.capacity,
            unlocked: row.unlocked, technician: row.technician}
    }

    ; 직원 수만큼 위에서부터 고른 목적 품목. 나머지 자리의 직원이 옮길 대상이다.
    staff := assigned.Count, wanted := Map()
    for id in priority {
        row := rows[id]
        if (wanted.Count < staff && row.unlocked && row.count < row.capacity)
            wanted[id] := true
    }
    ; 옮길 직원: 만재 품목을 비싼 순으로 먼저, 다음으로 목적 밖에서 생산 중인 품목을 싼 순으로.
    sources := []
    for id in priority
        if (rows[id].technician && rows[id].count >= rows[id].capacity)
            sources.Push(id)
    Loop priority.Length {
        id := priority[priority.Length - A_Index + 1]
        if (rows[id].technician && rows[id].count < rows[id].capacity && !wanted.Has(id))
            sources.Push(id)
    }
    moves := []
    for targetId in priority {
        target := rows[targetId]
        if (!wanted.Has(targetId) || target.technician || !sources.Length)
            continue
        source := rows[sources.RemoveAt(1)]
        moves.Push({technician: source.technician, from: source.id, to: targetId})
        target.technician := source.technician
        source.technician := 0
    }
    return moves
}

EarnWarehousePriority() {
    return ["south_american", "pharmaceutical", "cash", "cargo", "sporting", "organic", "printing"]
}

; 계획이 낸 이동인지 실행 직전에 다시 본다: 원래 품목이 만재이거나 목적지가 더 비싼 품목이어야 한다.
EarnWarehouseMoveJustified(fromId, toId, sourceFull) {
    if (sourceFull)
        return true
    rank := Map()
    for i, id in EarnWarehousePriority()
        rank[id] := i
    return rank.Has(fromId) && rank.Has(toId) && rank[toId] < rank[fromId]
}
