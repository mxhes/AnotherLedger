local h = ...
local ns = h.load({ "Money.lua", "Prices.lua", "Theme.lua", "UI/Rows.lua" })
local R = ns.UI.Rows

h.test("rowText priced live", function()
  local t = R.rowText({ name = "Linen Cloth", quantity = 23, vendorTotal = 230, ahTotal = 12650, ahFromCache = false, stale = false })
  h.eq(t.name, "Linen Cloth")
  h.eq(t.qty, "x23")
  h.eq(t.vendorText, "Vendor: 2s 30c")
  h.eq(t.ahText, "AH: 1g 26s 50c")
  h.eq(t.tag, nil)
  h.eq(t.tagStale, false)
  local g = ns.Theme.colors
  h.eq(t.vendorColored, "Vendor: " .. ns.Money.formatColored(230, g))
  h.eq(t.ahColored, "AH: " .. ns.Money.formatColored(12650, g))
  h.eq((t.ahColored:find("|cff", 1, true)) ~= nil, true)
end)

h.test("rowText unpriced AH shows n/a", function()
  local t = R.rowText({ name = "X", quantity = 1, vendorTotal = 5, ahTotal = nil, ahFromCache = false, stale = false })
  h.eq(t.ahText, "AH: n/a")
  h.eq(R.rowText({ name = "X", quantity = 1 }).vendorText, "Vendor: n/a")
  h.eq(t.ahColored, "AH: n/a")
end)

h.test("rowText age tag only for cached prices", function()
  local t = R.rowText({ name = "K", quantity = 6, ahTotal = 9000, ahFromCache = true, ahAge = 14 * 3600, stale = true })
  h.eq(t.tag, "(14h)")
  h.eq(t.tagStale, true)
  local f = R.rowText({ name = "K", quantity = 6, ahTotal = 9000, ahFromCache = true, ahAge = 300, stale = false })
  h.eq(f.tag, "(5m)")
  h.eq(f.tagStale, false)
  h.eq(R.rowText({ name = "K", quantity = 6, ahTotal = 9000, ahFromCache = true }).tag, nil)
end)

h.test("visibleCount", function()
  h.eq(R.visibleCount(100, 28), 3)
  h.eq(R.visibleCount(10, 28), 1)
  h.eq(R.visibleCount(0, 28), 1)
  h.eq(R.visibleCount(nil, 28), 1)
end)

h.test("clampOffset", function()
  h.eq(R.clampOffset(5, 10, 4), 5)
  h.eq(R.clampOffset(9, 10, 4), 6)
  h.eq(R.clampOffset(-2, 10, 4), 0)
  h.eq(R.clampOffset(3, 2, 4), 0)
  h.eq(R.clampOffset(nil, 10, 4), 0)
end)

h.test("offsetFor scrolls minimally", function()
  h.eq(R.offsetFor(1, 0, 4, 10), 0)
  h.eq(R.offsetFor(4, 0, 4, 10), 0)
  h.eq(R.offsetFor(5, 0, 4, 10), 1)
  h.eq(R.offsetFor(10, 0, 4, 10), 6)
  h.eq(R.offsetFor(2, 5, 4, 10), 1)
  h.eq(R.offsetFor(7, 5, 4, 10), 5)
  h.eq(R.offsetFor(nil, 5, 4, 10), 5)
end)

h.test("rowText separate columns", function()
  local t = R.rowText({ name = "X", quantity = 1, vendorTotal = 5, ahTotal = nil })
  h.eq(t.vendorLabel, "Vendor: ")
  h.eq(t.ahLabel, "AH: ")
  h.eq(t.ahAmount, "n/a")
  h.eq(t.vendorAmount, "5c")
end)

h.test("columnLayout: no overlap, minimums, shared right edge", function()
  local S = ns.Theme.sizes
  local minContent = S.minWidth - S.rowChrome - S.rowTextLeft - S.rowRightInset
  for _, w in ipairs({ minContent, 400, 700 }) do
    local c = R.columnLayout(w)
    h.eq(c.vendorLabelX >= 0, true)
    h.eq(c.vendorColX >= c.vendorLabelX + c.vendorLabelW, true)
    h.eq(c.ahLabelX >= c.vendorColX + c.vendorColW, true)
    h.eq(c.tagX >= c.ahLabelX + c.ahLabelW, true)
    h.eq(c.ahColX >= c.tagX + c.tagW, true)
    h.eq(c.ahColX + c.ahColW, w)
    h.eq(c.rightEdge, w)
    h.eq(c.vendorColW >= S.rowVendorColW, true)
    h.eq(c.ahColW >= S.rowAhColW, true)
    h.eq(c.tagW >= S.rowTagW, true)
    h.eq(c.qtyW >= S.rowQtyW, true)
    h.eq(c.vendorLabelW, S.rowVendorLabelW)
    h.eq(c.ahLabelW, S.rowAhLabelW)
  end
end)

h.test("columnLayout: worst-case budget at minWidth", function()
  local S = ns.Theme.sizes
  local minContent = S.minWidth - S.rowChrome - S.rowTextLeft - S.rowRightInset
  h.eq(minContent, 279)
  -- 15 chars ("123456g 78s 90c") at 5.5 px; "Vendor:" 7, "AH:" 3, "(999d)" 6.
  h.eq(S.rowVendorColW >= 15 * S.markerCharPx, true)
  h.eq(S.rowAhColW >= 15 * S.markerCharPx, true)
  h.eq(S.rowVendorLabelW >= 7 * S.markerCharPx, true)
  h.eq(S.rowAhLabelW >= 3 * S.markerCharPx, true)
  h.eq(S.rowTagW >= 6 * S.markerCharPx, true)
  local c = R.columnLayout(minContent)
  h.eq(c.ahLabelX - (c.vendorColX + c.vendorColW) >= S.rowGapMid, true)
  h.eq(c.ahColX + c.ahColW <= minContent, true)
end)

h.test("columnLayout: extra width grows columns and gap, not labels", function()
  local a, b = R.columnLayout(279), R.columnLayout(700)
  h.eq(b.vendorColW > a.vendorColW, true)
  h.eq(b.ahColW > a.ahColW, true)
  h.eq(b.vendorLabelW, a.vendorLabelW)
  h.eq(b.ahLabelW, a.ahLabelW)
  h.eq(b.ahLabelX - (b.vendorColX + b.vendorColW) > a.ahLabelX - (a.vendorColX + a.vendorColW), true)
end)

-- A WIDER font than the one the old fixed widths assumed.
local WIDE = { vendorLabel = 50, ahLabel = 26, tag = 40, amount = 98 }

local function noOverlap(h, c, w)
  h.eq(c.vendorLabelX >= 0, true)
  h.eq(c.vendorColX >= c.vendorLabelX + c.vendorLabelW, true)
  h.eq(c.ahLabelX >= c.vendorColX + c.vendorColW, true)
  h.eq(c.tagX >= c.ahLabelX + c.ahLabelW, true)
  h.eq(c.ahColX >= c.tagX + c.tagW, true)
  h.eq(c.ahColX + c.ahColW, w)
  h.eq(c.rightEdge, w)
end

h.test("columnLayout measured: wide font, required is the sum plus gaps", function()
  local S = ns.Theme.sizes
  local p = S.rowMeasurePad
  local expect = (50 + p) + S.rowLabelGap + (98 + p) + S.rowGapMid + (26 + p) + (40 + p) + (98 + p)
  local c = R.columnLayout(nil, WIDE)
  h.eq(c.required, expect)
  h.eq(c.fallback, false)
  for _, w in ipairs({ expect, expect + 1, 400, 700 }) do
    local l = R.columnLayout(w, WIDE)
    noOverlap(h, l, w)
    h.eq(l.vendorLabelW, 50 + p)
    h.eq(l.ahLabelW, 26 + p)
    h.eq(l.tagW, 40 + p)
    h.eq(l.vendorColW >= 98 + p, true)
    h.eq(l.ahColW >= 98 + p, true)
    h.eq(l.ahColX + l.ahColW <= w, true)
    h.eq(l.required, expect)
  end
end)

h.test("columnLayout measured: extra width goes to amounts and gap, labels fixed", function()
  local a, b = R.columnLayout(R.columnLayout(nil, WIDE).required, WIDE), R.columnLayout(700, WIDE)
  h.eq(b.vendorColW > a.vendorColW, true)
  h.eq(b.ahColW > a.ahColW, true)
  h.eq(b.vendorLabelW, a.vendorLabelW)
  h.eq(b.ahLabelW, a.ahLabelW)
  h.eq(b.ahLabelX - (b.vendorColX + b.vendorColW) > a.ahLabelX - (a.vendorColX + a.vendorColW), true)
end)

h.test("columnLayout measured: gaps shrink to the floor before clipping", function()
  local S = ns.Theme.sizes
  local req = R.columnLayout(nil, WIDE).required
  local c = R.columnLayout(req - 3, WIDE)
  local midGap = c.ahLabelX - (c.vendorColX + c.vendorColW)
  h.eq(midGap, S.rowGapMid - 3)
  noOverlap(h, c, req - 3)
  h.eq(c.vendorColX, c.vendorLabelW + S.rowLabelGap)
  -- Gap floor reached: the gap stays at the floor, no overlap of the right part.
  local f = R.columnLayout(req - (S.rowGapMid - S.rowGapFloor), WIDE)
  h.eq(f.ahLabelX - (f.vendorColX + f.vendorColW), S.rowGapFloor)
  local tight = R.columnLayout(req - 100, WIDE)
  h.eq(tight.ahLabelX - (tight.vendorColX + tight.vendorColW) <= S.rowGapFloor, true)
  h.eq(tight.vendorColX >= tight.vendorLabelW + S.rowGapFloor, true)
  h.eq(tight.ahColX + tight.ahColW, req - 100)
end)

h.test("columnLayout: nil / zero measured fields use the Theme fallbacks", function()
  local S = ns.Theme.sizes
  local c = R.columnLayout(279, nil)
  h.eq(c.fallback, true)
  h.eq(c.vendorLabelW, S.rowVendorLabelW)
  h.eq(c.ahLabelW, S.rowAhLabelW)
  h.eq(c.tagW, S.rowTagW)
  local part = R.columnLayout(300, { vendorLabel = 50, ahLabel = 0, tag = nil, amount = 98 })
  h.eq(part.fallback, true)
  h.eq(part.vendorLabelW, 50 + S.rowMeasurePad)
  h.eq(part.ahLabelW, S.rowAhLabelW)
  h.eq(part.tagW, S.rowTagW)
end)

h.test("requiredRowWidth adds the text inset and window chrome", function()
  local S = ns.Theme.sizes
  h.eq(R.requiredRowWidth(WIDE), R.columnLayout(nil, WIDE).required + S.rowTextLeft + S.rowRightInset + S.rowChrome)
  h.eq(R.requiredRowWidth(WIDE) > R.requiredRowWidth(nil), true)
end)
