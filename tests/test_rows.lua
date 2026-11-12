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

local WIDE = { vendorLabel = 50, ahLabel = 26, tag = 40, amount = 98, qtyWorst = 30 }

local function checkBlock(c, w)
  local S = ns.Theme.sizes
  -- Block flush right, name column ends at least the Theme gap before it.
  h.eq(c.blockX + c.blockW, w)
  h.eq(c.rightEdge, w)
  h.eq(c.nameX + c.nameW + S.rowNameGap <= c.blockX, true)
  -- Labels share one x; amounts share one x after the wider label + gap.
  h.eq(c.labelX, c.blockX)
  h.eq(c.amountX, c.labelX + c.labelW + S.rowLabelGap)
  -- Block holds label column, amount and tag with gaps.
  h.eq(c.blockW, c.labelW + S.rowLabelGap + c.amountW + S.rowTagGap + c.tagW)
end

h.test("columnLayout: block flush right, no overlap, shared x (fallback widths)", function()
  local S = ns.Theme.sizes
  local req = R.columnLayout(nil, nil).required
  for _, w in ipairs({ req, req + 1, 400, 700 }) do
    local c = R.columnLayout(w)
    checkBlock(c, w)
    h.eq(c.labelW, math.max(S.rowVendorLabelW, S.rowAhLabelW))
    h.eq(c.amountW, S.rowVendorColW)
    h.eq(c.tagW, S.rowTagW)
    h.eq(c.nameW >= S.rowNameMin, true)
  end
end)

h.test("columnLayout measured: labels/amounts line up after the wider label", function()
  local S = ns.Theme.sizes
  local p = S.rowMeasurePad
  local c = R.columnLayout(500, WIDE)
  checkBlock(c, 500)
  h.eq(c.fallback, false)
  h.eq(c.labelW, 50 + p)
  h.eq(c.amountX - c.labelX, 50 + p + S.rowLabelGap)
  h.eq(c.amountW, 98 + p)
  h.eq(c.tagW, 40 + p)
  h.eq(c.tagGap, S.rowTagGap)
  h.eq(c.qtyW, 30 + p)
  -- The AH label may be the wider one.
  local d = R.columnLayout(500, { vendorLabel = 20, ahLabel = 44, tag = 40, amount = 98 })
  h.eq(d.labelW, 44 + p)
  h.eq(d.amountX, d.labelX + 44 + p + S.rowLabelGap)
end)

h.test("columnLayout: extra width goes only to the name column", function()
  local a = R.columnLayout(R.columnLayout(nil, WIDE).required, WIDE)
  local b = R.columnLayout(R.columnLayout(nil, WIDE).required + 150, WIDE)
  h.eq(b.nameW, a.nameW + 150)
  h.eq(b.blockW, a.blockW)
  h.eq(b.labelW, a.labelW)
  h.eq(b.amountW, a.amountW)
  h.eq(b.tagW, a.tagW)
  h.eq(b.labelX - a.labelX, 150)
  h.eq(b.amountX - b.labelX, a.amountX - a.labelX)
end)

h.test("columnLayout: required = rowNameMin + gap + blockW; name column hits rowNameMin", function()
  local S = ns.Theme.sizes
  local c = R.columnLayout(nil, WIDE)
  h.eq(c.required, S.rowNameMin + S.rowNameGap + c.blockW)
  h.eq(c.blockW, 50 + S.rowMeasurePad + S.rowLabelGap + 98 + S.rowMeasurePad + S.rowTagGap + 40 + S.rowMeasurePad)
  local m = R.columnLayout(c.required, WIDE)
  h.eq(m.nameW, S.rowNameMin)
  checkBlock(m, c.required)
end)

h.test("columnLayout: block width covers the worst-case amount and tag", function()
  local c = R.columnLayout(600, WIDE)
  h.eq(c.blockW >= c.labelW + c.amountW + c.tagW, true)
  h.eq(c.amountX + c.amountW + c.tagGap + c.tagW, c.blockX + c.blockW)
end)

h.test("columnLayout: nil / zero measured fields use the Theme fallbacks", function()
  local S = ns.Theme.sizes
  local c = R.columnLayout(400, nil)
  h.eq(c.fallback, true)
  h.eq(c.labelW, math.max(S.rowVendorLabelW, S.rowAhLabelW))
  h.eq(c.amountW, S.rowVendorColW)
  h.eq(c.tagW, S.rowTagW)
  h.eq(c.qtyW, S.rowQtyW)
  local part = R.columnLayout(400, { vendorLabel = 50, ahLabel = 0, tag = nil, amount = 98, qtyWorst = 30 })
  h.eq(part.fallback, true)
  h.eq(part.labelW, 50 + S.rowMeasurePad)
  h.eq(part.amountW, 98 + S.rowMeasurePad)
  h.eq(part.tagW, S.rowTagW)
  -- A missing quantity measurement alone also counts as a fallback.
  h.eq(R.columnLayout(400, { vendorLabel = 50, ahLabel = 26, tag = 40, amount = 98 }).fallback, true)
end)

h.test("nameFit clips long names, keeps the quantity visible", function()
  local S = ns.Theme.sizes
  -- Short name: natural width (+1 rounding slack).
  h.eq(R.nameFit(200, 30, 60), 61)
  -- Long name: clipped so name + gap + quantity fit the column.
  h.eq(R.nameFit(200, 30, 500), 200 - 30 - S.rowQtyGap)
  h.eq(R.nameFit(200, 30, nil), 200 - 30 - S.rowQtyGap)
  -- Never below 1.
  h.eq(R.nameFit(10, 30, 50), 1)
end)

h.test("requiredRowWidth adds the text inset and window chrome", function()
  local S = ns.Theme.sizes
  local c = R.columnLayout(nil, WIDE)
  h.eq(R.requiredRowWidth(WIDE), S.rowNameMin + S.rowNameGap + c.blockW + S.rowTextLeft + S.rowRightInset + S.rowChrome)
  h.eq(R.requiredRowWidth(WIDE) > R.requiredRowWidth(nil), true)
end)
