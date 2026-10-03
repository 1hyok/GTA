; Parse one 1920x1080 Sell Goods screenshot. All coordinates are client-relative.
; The seven normal stock tiles end above y=540; special orders are not inventory.
; Return false for an incomplete/ambiguous read. UI assignment state is filled in
; separately by the caller after observing Warehouse Management.
EarnWarehouseReadStock(lines) {
    if (!(lines is Array))
        return false
    tiles := [
        {id: "cargo", name: "Cargo and Shipments", x: 728, y: 135, w: 430},
        {id: "sporting", name: "Sporting Goods", x: 1173, y: 135, w: 431},
        {id: "south_american", name: "South American Imports", x: 728, y: 240, w: 430},
        {id: "pharmaceutical", name: "Pharmaceutical Research", x: 1173, y: 240, w: 431},
        {id: "organic", name: "Organic Produce", x: 728, y: 345, w: 430},
        {id: "printing", name: "Printing & Copying", x: 1173, y: 345, w: 431},
        {id: "cash", name: "Cash Creation", x: 728, y: 450, w: 430}
    ]
    for line in lines {
        if (!IsObject(line))
            return false
        for field in ["x", "y", "w", "h", "text"]
            if (!line.HasOwnProp(field))
                return false
        if (Type(line.x) != "Integer" || Type(line.y) != "Integer" || Type(line.w) != "Integer"
            || Type(line.h) != "Integer" || line.w <= 0 || line.h <= 0 || Type(line.text) != "String")
            return false
    }
    goods := []
    for tile in tiles {
        names := 0, quantities := 0, count := 0, capacity := 0
        for line in lines {
            if (line.x < tile.x || line.x >= tile.x+tile.w || line.y < tile.y || line.y >= tile.y+90)
                continue
            if (line.text == tile.name) {
                names++
            } else if (RegExMatch(line.text, "^(0|[1-9][0-9]{0,2})\h*/\h*(0|[1-9][0-9]{0,2})$", &quantity)) {
                quantities++
                count := Integer(quantity[1]), capacity := Integer(quantity[2])
            } else {
                if (InStr(line.text, "/"))
                    return false
                for knownTile in tiles
                    if (line.text == knownTile.name)
                        return false
            }
        }
        if (names != 1 || quantities != 1 || capacity <= 0 || count > capacity)
            return false
        goods.Push({id: tile.id, count: count, capacity: capacity, unlocked: 0, technician: 0})
    }
    return goods
}
