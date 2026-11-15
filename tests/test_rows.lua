local h = ...
local ns = h.load({ "Util.lua", "Money.lua", "Prices.lua", "Theme.lua", "UI/Rows.lua" })
local R = ns.UI.Rows

local WIDE = { source = 50, tag = 40, amount = 98, qtyWorst = 30 }
local P = ns.Theme.sizes.rowMeasurePad

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
  local textLeft = S.rowIconInset + S.iconSize + S.rowIconGap
  h.eq(R.requiredRowWidth(WIDE), S.rowNameMin + S.rowNameGap + c.blockW + textLeft + S.rowRightInset + S.rowChrome)
  h.eq(R.requiredRowWidth(WIDE) > R.requiredRowWidth(nil), true)
end)

h.test("without item icons the text starts near the left edge and the row needs less width", function()
  local S = ns.Theme.sizes
  local withIcons = R.requiredRowWidth(WIDE)
  local textLeft = S.rowIconInset + S.iconSize + S.rowIconGap
  h.eq(R.textLeft(), textLeft)
  ns.Options, ns.db = { get = function(_, key) if key == "showIcons" then return false end end }, {}
  local ok, err = pcall(function()
    h.eq(R.showIcons(), false)
    h.eq(R.textLeft(), S.rowTextLeftNoIcon)
    h.eq(R.requiredRowWidth(WIDE), withIcons - textLeft + S.rowTextLeftNoIcon)
  end)
  ns.Options, ns.db = nil, nil
  assert(ok, err)
end)

h.test("Rows.tooltipLink: the row link, else an item string, else nil", function()
  local link = "|cffffffff|Hitem:2589::::::::60:::::::::|h[Linen Cloth]|h|r"
  h.eq(ns.UI.Rows.tooltipLink({ id = 2589, link = link }), link)
  h.eq(ns.UI.Rows.tooltipLink({ id = 2589 }), "item:2589")
  h.eq(ns.UI.Rows.tooltipLink({ id = 2589, link = "" }), "item:2589")
  h.eq(ns.UI.Rows.tooltipLink({}), nil)
  h.eq(ns.UI.Rows.tooltipLink(nil), nil)
end)

h.test("rowText: a row's detail fills line 2, no quantity shows none", function()
  local t = R.rowText({ name = "+ Today 9:00", detail = "1h 0m", bestLineTotal = 100, rateLevel = "good" },
    ns.Money.format)
  h.eq(t.market, "1h 0m"); h.eq(t.isDetail, true)
  h.eq(t.qty, "")
  h.eq(R.rowText({ name = "X", quantity = 2 }).isDetail, false)
end)

h.test("marketText: levels in order, plain or colored, nil without levels", function()
  h.eq(R.marketText({ rateLevel = "good", volumeLevel = "low" }), "Sells well, Low volume")
  h.eq(R.marketText({ volumeLevel = "medium" }), "Medium volume")
  h.eq(R.marketText({}), nil)
  local colored = R.marketText({ rateLevel = "bad" }, ns.Theme.colors)
  h.eq(colored, ns.Money.colorCode(ns.Theme.colors.marketBad) .. "Sells poorly|r")
  h.eq(R.rowText({ name = "X", quantity = 1, rateLevel = "ok" }).market,
    ns.Money.colorCode(ns.Theme.colors.marketOk) .. "Sells okay|r")
  h.eq(R.rowText({ name = "X", quantity = 1 }).market, nil)
  h.eq(R.rowText({ name = "C", quantity = 1, isCurrency = true, rateLevel = "ok" }).market, nil)
end)

-- ---------------------------------------------------------------------------
-- One counted value with its source

local fm = ns.Money.format

h.test("rowText: the counted value with its source, colored coins by default", function()
  local row = { name = "Linen Cloth", quantity = 23, vendorTotal = 230, ahEach = 550, ahTotal = 12650,
    value = 12650, bestKind = "ah" }
  local t = R.rowText(row)
  h.eq(t.name, "Linen Cloth"); h.eq(t.qty, "x23")
  h.eq(t.amount, ns.Money.formatColored(12650, ns.Theme.colors))
  h.eq(t.source, "ah"); h.eq(t.sourceText, "Auction"); h.eq(t.unpriced, false)
  h.eq(R.rowText(row, fm).amount, "1g 26s 50c")
end)

h.test("rowText: vendor beats a lower DE, no AH price marks it unpriced", function()
  local t = R.rowText({ name = "Sword", quantity = 1, value = 18003, bestKind = "vendor",
    vendorTotal = 18003, deTotal = 8803 }, fm)
  h.eq(t.amount, fm(18003)); h.eq(t.source, "vendor"); h.eq(t.sourceText, "Vendor")
  h.eq(t.unpriced, true)
  local d = R.rowText({ name = "X", quantity = 2, value = 500, bestKind = "de", deTotal = 500, ahEach = 100,
    ahTotal = 200 }, fm)
  h.eq(d.source, "de"); h.eq(d.sourceText, "Destroy"); h.eq(d.unpriced, false)
end)

h.test("rowText: bound, nothing, currency and rows with their own total", function()
  local b = R.rowText({ name = "B", quantity = 1, value = 0, bound = true }, fm)
  h.eq(b.amount, "bound"); h.eq(b.source, nil); h.eq(b.unpriced, false)
  local bv = R.rowText({ name = "B", quantity = 1, value = 500, bestKind = "vendor", vendorTotal = 500, bound = true }, fm)
  h.eq(bv.amount, "5s"); h.eq(bv.source, "vendor"); h.eq(bv.unpriced, false)
  local none = R.rowText({ name = "N", quantity = 1, value = 0 }, fm)
  h.eq(none.amount, "?"); h.eq(none.source, nil); h.eq(none.unpriced, true)
  local c = R.rowText({ name = "C", quantity = 3, isCurrency = true }, fm)
  h.eq(c.amount, ""); h.eq(c.source, nil); h.eq(c.unpriced, false)
  local own = R.rowText({ name = "S", quantity = 4, value = 700, ahTotal = 9, bestLineTotal = 700 }, fm)
  h.eq(own.amount, "7s"); h.eq(own.source, nil); h.eq(own.unpriced, false)
end)

h.test("rowText: the age tag only on a cached AH value that counts", function()
  local t = R.rowText({ name = "K", quantity = 6, ahEach = 1500, ahTotal = 9000, value = 9000, bestKind = "ah",
    ahFromCache = true, ahAge = 14 * 3600, stale = true })
  h.eq(t.tag, "(14h)"); h.eq(t.tagStale, true)
  local f = R.rowText({ name = "K", quantity = 6, ahEach = 1500, ahTotal = 9000, value = 9000, bestKind = "ah",
    ahFromCache = true, ahAge = 300 })
  h.eq(f.tag, "(5m)"); h.eq(f.tagStale, false)
  h.eq(R.rowText({ name = "K", quantity = 6, ahTotal = 9000, value = 9000, bestKind = "ah", ahFromCache = true }).tag, nil)
  local de = R.rowText({ name = "X", quantity = 2, ahEach = 150, ahTotal = 300, deTotal = 500, value = 500,
    bestKind = "de", ahFromCache = true, ahAge = 3600 }, fm)
  h.eq(de.tag, nil)
end)

h.test("Rows.tooltipLines: every known value, per unit with more than one", function()
  local lines = R.tooltipLines({ quantity = 2, vendorTotal = 100, vendorEach = 50, ahTotal = 300, ahEach = 150,
    bestKind = "ah" }, fm)
  h.eq(#lines, 2)
  h.eq(lines[1]:find("Vendor", 1, true) ~= nil, true)
  h.eq(lines[1]:find(fm(100), 1, true) ~= nil, true)
  h.eq(lines[1]:find(fm(50), 1, true) ~= nil, true)
  h.eq(lines[2]:find(fm(150), 1, true) ~= nil, true)
  local one = R.tooltipLines({ quantity = 1, vendorTotal = 100, vendorEach = 100, deTotal = 80, deEach = 80,
    bestKind = "vendor" }, fm)
  h.eq(#one, 2)
  h.eq(one[1]:find("each", 1, true), nil)
  h.eq(#R.tooltipLines({ quantity = 3, isCurrency = true }, fm), 0)
end)

-- ---------------------------------------------------------------------------
-- Right block: amount column, source tag column, age tag


local function checkBlock(c, w)
  local S = ns.Theme.sizes
  h.eq(c.blockX + c.blockW, w)
  h.eq(c.rightEdge, w)
  h.eq(c.nameX + c.nameW + S.rowNameGap <= c.blockX, true)
  h.eq(c.amountX, c.blockX)
end

h.test("blockLayout: amount first, then the source tag column", function()
  local S = ns.Theme.sizes
  local c = R.blockLayout(500, 50, 40, nil)
  checkBlock(c, 500)
  h.eq(c.amountW, 40 + P)
  h.eq(c.labelX, c.amountX + 40 + P + S.rowLabelGap)
  h.eq(c.blockW, 40 + P + S.rowLabelGap + 50 + P)
  h.eq(c.tagGap, 0); h.eq(c.tagW, 0)
  local wide = R.blockLayout(500, 50, 98, nil)
  checkBlock(wide, 500)
  h.eq(wide.blockW - c.blockW, 58)
end)

h.test("blockLayout: a longer amount moves the block left by exactly the growth", function()
  local a = R.blockLayout(500, 50, 60, 30)
  local b = R.blockLayout(500, 50, 85, 30)
  checkBlock(a, 500); checkBlock(b, 500)
  h.eq(a.blockX - b.blockX, 25)
  h.eq(b.nameW, a.nameW - 25)
  h.eq(a.labelX, b.labelX) -- the tag column stays put
  local c = R.blockLayout(620, 50, 60, 30)
  h.eq(c.blockW, a.blockW); h.eq(c.blockX - a.blockX, 120)
end)

h.test("blockLayout: age tag gap and width only when a rendered row has one", function()
  local S = ns.Theme.sizes
  local none = R.blockLayout(500, 50, 60, nil)
  local tag = R.blockLayout(500, 50, 60, 36)
  h.eq(R.blockLayout(500, 50, 60, 0).blockW, none.blockW)
  h.eq(tag.tagGap, S.rowTagGap); h.eq(tag.tagW, 36 + P)
  h.eq(tag.blockW, none.blockW + S.rowTagGap + 36 + P)
  checkBlock(tag, 500)
end)

h.test("blockLayout: nil / 0 measurements use the Theme fallbacks", function()
  local S = ns.Theme.sizes
  local c = R.blockLayout(500, nil, 0, nil)
  checkBlock(c, 500)
  h.eq(c.blockW, S.rowVendorColW + S.rowLabelGap + S.rowSourceW)
  h.eq(R.blockLayout(500, 0 / 0, nil, nil).blockW, c.blockW)
end)

h.test("blockLayout: block never takes the name column below rowNameMin", function()
  local S = ns.Theme.sizes
  local c = R.blockLayout(200, 50, 400, 40)
  checkBlock(c, 200)
  h.eq(c.blockW, 200 - S.rowNameMin - S.rowNameGap)
  h.eq(c.nameW, S.rowNameMin)
  local u = R.blockLayout(nil, 50, 60, 30)
  checkBlock(u, u.rightEdge)
  h.eq(u.nameW, S.rowNameMin)
end)

h.test("worstCase: required = rowNameMin + gap + blockW, fits blockLayout", function()
  local S = ns.Theme.sizes
  local c = R.worstCase(WIDE)
  h.eq(c.fallback, false)
  h.eq(c.labelW, 50 + P); h.eq(c.amountW, 98 + P); h.eq(c.tagW, 40 + P); h.eq(c.qtyW, 30 + P)
  h.eq(c.blockW, 98 + P + S.rowLabelGap + 50 + P + S.rowTagGap + 40 + P)
  h.eq(c.required, S.rowNameMin + S.rowNameGap + c.blockW)
  local b = R.blockLayout(c.required, WIDE.source, WIDE.amount, WIDE.tag)
  h.eq(b.blockW, c.blockW); h.eq(b.nameW, S.rowNameMin)
end)

h.test("worstCase: nil / zero measured fields use the Theme fallbacks", function()
  local S = ns.Theme.sizes
  local c = R.worstCase(nil)
  h.eq(c.fallback, true)
  h.eq(c.labelW, S.rowSourceW); h.eq(c.amountW, S.rowVendorColW); h.eq(c.tagW, S.rowTagW); h.eq(c.qtyW, S.rowQtyW)
  h.eq(R.worstCase({ source = 0, tag = 40, amount = 98, qtyWorst = 30 }).labelW, S.rowSourceW)
end)

h.test("Rows.modifiedClick hands a real link to the game only on a modified click", function()
  local handled
  _G.HandleModifiedItemClick = function(link) handled = link return true end
  _G.IsModifiedClick = function() return false end
  h.eq(ns.UI.Rows.modifiedClick("|Hitem:1|h[A]|h"), false)
  _G.IsModifiedClick = function() return true end
  h.eq(ns.UI.Rows.modifiedClick(nil), false) -- History / Zones rows have no link
  h.eq(handled, nil)
  h.eq(ns.UI.Rows.modifiedClick("|Hitem:1|h[A]|h"), true)
  h.eq(handled, "|Hitem:1|h[A]|h")
  _G.HandleModifiedItemClick, _G.IsModifiedClick = nil, nil
end)

h.test("sourceBoxWidth: every box as wide as the widest tag, own text before measuring", function()
  local Rows, S = ns.UI.Rows, ns.Theme.sizes
  h.eq(Rows.sourceBoxWidth(50, 20), 50)
  h.eq(Rows.sourceBoxWidth(50, 44), 50)
  h.eq(Rows.sourceBoxWidth(nil, 20), 20 + 2 * S.rowTagPad)
  h.eq(Rows.sourceBoxWidth(nil, nil), S.rowSourceW + 2 * S.rowTagPad)
  -- never narrower than its own text
  h.eq(Rows.sourceBoxWidth(10, 20), 20 + 2 * S.rowTagPad)
end)

h.test("rowText: the price per unit option shows one item of a stack", function()
  local row = { name = "Ore", quantity = 4, bestKind = "ah", value = 2000, ahEach = 500, ahTotal = 2000 }
  h.eq(R.rowText(row, ns.Money.format, false).amount, ns.Money.format(2000))
  h.eq(R.rowText(row, ns.Money.format, true).amount, ns.Money.format(500))
  row.quantity = 1
  h.eq(R.rowText(row, ns.Money.format, true).amount, ns.Money.format(2000))
end)
