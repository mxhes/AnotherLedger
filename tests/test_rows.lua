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
  h.eq(c.labelX, c.blockX)
end

local P = ns.Theme.sizes.rowMeasurePad

h.test("blockLayout: right edge flush, narrow amounts give a narrow block", function()
  local S = ns.Theme.sizes
  local c = R.blockLayout(500, 50, 40, nil)
  checkBlock(c, 500)
  h.eq(c.amountX, c.labelX + 50 + P + S.rowLabelGap)
  h.eq(c.blockW, 50 + P + S.rowLabelGap + 40 + P)
  h.eq(c.tagGap, 0)
  h.eq(c.tagW, 0)
  local wide = R.blockLayout(500, 50, 98, nil)
  checkBlock(wide, 500)
  h.eq(wide.blockW > c.blockW, true)
  h.eq(wide.amountX - wide.labelX, c.amountX - c.labelX)
end)

h.test("blockLayout: a longer amount moves blockX left by exactly the growth", function()
  local a = R.blockLayout(500, 50, 60, 30)
  local b = R.blockLayout(500, 50, 85, 30)
  checkBlock(a, 500)
  checkBlock(b, 500)
  h.eq(a.blockX - b.blockX, 25)
  h.eq(a.amountX - b.amountX, 25)
  h.eq(b.nameW, a.nameW - 25)
  -- Width of the content does not change the block, only shifts it.
  local c = R.blockLayout(620, 50, 60, 30)
  h.eq(c.blockW, a.blockW)
  h.eq(c.blockX - a.blockX, 120)
end)

h.test("blockLayout: tag gap and width only when a rendered row has a tag", function()
  local S = ns.Theme.sizes
  local none = R.blockLayout(500, 50, 60, nil)
  local zero = R.blockLayout(500, 50, 60, 0)
  local tag = R.blockLayout(500, 50, 60, 36)
  h.eq(none.blockW, zero.blockW)
  h.eq(none.tagGap, 0)
  h.eq(tag.tagGap, S.rowTagGap)
  h.eq(tag.tagW, 36 + P)
  h.eq(tag.blockW, none.blockW + S.rowTagGap + 36 + P)
  -- The amount column x depends on the label column only.
  h.eq(tag.amountX - tag.labelX, none.amountX - none.labelX)
  checkBlock(tag, 500)
end)

h.test("blockLayout: nil / 0 measurements use the Theme fallbacks", function()
  local S = ns.Theme.sizes
  local c = R.blockLayout(500, nil, 0, nil)
  checkBlock(c, 500)
  h.eq(c.amountX - c.labelX, math.max(S.rowVendorLabelW, S.rowAhLabelW) + S.rowLabelGap)
  h.eq(c.blockW, math.max(S.rowVendorLabelW, S.rowAhLabelW) + S.rowLabelGap + S.rowVendorColW)
  h.eq(R.blockLayout(500, 0 / 0, nil, nil).blockW, c.blockW)
end)

h.test("blockLayout: block never takes the name column below rowNameMin", function()
  local S = ns.Theme.sizes
  local c = R.blockLayout(200, 50, 400, 40)
  checkBlock(c, 200)
  h.eq(c.blockW, 200 - S.rowNameMin - S.rowNameGap)
  h.eq(c.nameW, S.rowNameMin)
  -- Unknown content width: the natural block plus the minimum name column.
  local u = R.blockLayout(nil, 50, 60, 30)
  checkBlock(u, u.rightEdge)
  h.eq(u.nameW, S.rowNameMin)
end)

h.test("blockLayout: worst case fits at the window's required width", function()
  local S = ns.Theme.sizes
  local wc = R.worstCase(WIDE)
  local c = R.blockLayout(wc.required, WIDE.vendorLabel, WIDE.amount, WIDE.tag)
  h.eq(c.blockW, wc.blockW)
  h.eq(c.nameW, S.rowNameMin)
  checkBlock(c, wc.required)
end)

h.test("worstCase: required = rowNameMin + gap + blockW", function()
  local S = ns.Theme.sizes
  local c = R.worstCase(WIDE)
  h.eq(c.fallback, false)
  h.eq(c.labelW, 50 + P)
  h.eq(c.amountW, 98 + P)
  h.eq(c.tagW, 40 + P)
  h.eq(c.qtyW, 30 + P)
  h.eq(c.blockW, 50 + P + S.rowLabelGap + 98 + P + S.rowTagGap + 40 + P)
  h.eq(c.required, S.rowNameMin + S.rowNameGap + c.blockW)
  -- The AH label may be the wider one.
  h.eq(R.worstCase({ vendorLabel = 20, ahLabel = 44, tag = 40, amount = 98 }).labelW, 44 + P)
end)

h.test("worstCase: nil / zero measured fields use the Theme fallbacks", function()
  local S = ns.Theme.sizes
  local c = R.worstCase(nil)
  h.eq(c.fallback, true)
  h.eq(c.labelW, math.max(S.rowVendorLabelW, S.rowAhLabelW))
  h.eq(c.amountW, S.rowVendorColW)
  h.eq(c.tagW, S.rowTagW)
  h.eq(c.qtyW, S.rowQtyW)
  local part = R.worstCase({ vendorLabel = 50, ahLabel = 0, tag = nil, amount = 98, qtyWorst = 30 })
  h.eq(part.fallback, true)
  h.eq(part.labelW, 50 + P)
  h.eq(part.tagW, S.rowTagW)
  h.eq(R.worstCase({ vendorLabel = 50, ahLabel = 26, tag = 40, amount = 98 }).fallback, true)
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
  local c = R.worstCase(WIDE)
  h.eq(R.requiredRowWidth(WIDE), S.rowNameMin + S.rowNameGap + c.blockW + S.rowTextLeft + S.rowRightInset + S.rowChrome)
  h.eq(R.requiredRowWidth(WIDE) > R.requiredRowWidth(nil), true)
end)
