local h = ...
local ns = h.load({ "Money.lua", "Theme.lua", "UI/Summary.lua" })
local S = ns.UI.Summary
local M = ns.Money

h.test("totalsText formats money and rates", function()
  local t = S.totalsText({ vendor = 12345, ah = 67890, unpriced = 0,
    vendorPerHour = 5000, ahPerHour = 10000, filtered = false })
  h.eq(t.vendor, "Vendor: " .. M.format(12345))
  h.eq(t.ah, "AH: " .. M.format(67890))
  h.eq(t.vendorRate, M.format(5000) .. "/h")
  h.eq(t.ahRate, M.format(10000) .. "/h")
  h.eq(t.unpriced, nil)
  h.eq(t.filtered, false)
  local c = ns.Theme.colors
  h.eq(t.vendorColored, "Vendor: " .. M.formatColored(12345, c))
  h.eq(t.ahColored, "AH: " .. M.formatColored(67890, c))
  h.eq(t.vendorRateColored, M.formatColored(5000, c) .. "/h")
  h.eq(t.ahRateColored, M.formatColored(10000, c) .. "/h")
end)

h.test("totalsText uses em dash for nil rates, never n/a", function()
  local t = S.totalsText({ vendor = 0, ah = 0, unpriced = 0, filtered = false })
  h.eq(t.vendorRate, "\226\128\148")
  h.eq(t.ahRate, "\226\128\148")
  h.eq(t.vendorRateColored, "\226\128\148")
  h.eq(t.ahRateColored, "\226\128\148")
  for _, v in pairs(t) do
    if type(v) == "string" then h.eq(v:find("n/a", 1, true), nil) end
  end
end)

h.test("totalsText unpriced only when positive", function()
  h.eq(S.totalsText({ vendor = 1, ah = 1, unpriced = 3 }).unpriced, "3 unpriced")
  h.eq(S.totalsText({ vendor = 1, ah = 1, unpriced = 0 }).unpriced, nil)
  h.eq(S.totalsText({ vendor = 1, ah = 1 }).unpriced, nil)
end)

h.test("totalsText filtered flag and nil tolerance", function()
  h.eq(S.totalsText({ filtered = true }).filtered, true)
  local t = S.totalsText(nil)
  h.eq(t.filtered, false)
  h.eq(t.vendor, "Vendor: " .. M.format(0))
end)

h.test("topLines", function()
  h.eq(#S.topLines({}), 0)
  h.eq(#S.topLines(nil), 0)
  local l = S.topLines({ { name = "Ore", quantity = 4, value = 500, quality = 2 } })
  h.eq(#l, 1)
  h.eq(l[1].name, "Ore")
  h.eq(l[1].qty, "x4")
  h.eq(l[1].valueText, M.format(500))
  h.eq(l[1].valueColored, M.formatColored(500, ns.Theme.colors))
  h.eq(l[1].quality, 2)
end)

h.test("topBoxHeight", function()
  h.eq(S.topBoxHeight(0), 0)
  h.eq(S.topBoxHeight(nil), 0)
  local T = ns.Theme.sizes
  h.eq(S.topBoxHeight(1), T.topHeaderHeight + T.topRowHeight + T.padding / 2 + T.dividerHeight)
  h.eq(S.topBoxHeight(3), T.topHeaderHeight + 3 * T.topRowHeight + T.padding / 2 + T.dividerHeight)
  h.eq(S.topBoxHeight(3), 18 + 3 * 20 + 4 + 2)
  h.eq(S.topBoxHeight(5), S.topBoxHeight(3))
end)

h.test("footer worst case fits at the minimum window width", function()
  local T = ns.Theme.sizes
  h.eq(S.footerHalfWidth(T.minWidth) >= S.footerWorstWidth(), true)
  -- One step narrower would clip: the minimum is the smallest 10 px multiple that fits.
  h.eq(S.footerHalfWidth(T.minWidth - 10) < S.footerWorstWidth(), true)
end)

h.test("footer blocks stack and add up to footerHeight", function()
  local T = ns.Theme.sizes
  local L = S.footerLayout()
  h.eq(L.items.top, 0)
  h.eq(L.gold.top, L.items.height)
  h.eq(L.total.top, L.items.height + L.gold.height)
  h.eq(L.items.contentTop, T.footerLabelHeight)
  h.eq(L.items.contentHeight, 38) -- the item block keeps its height
  h.eq(L.height, T.footerHeight)
  h.eq(L.height, 3 * T.footerLabelHeight + 38 + 16 + 38)
  h.eq(T.footerHeight, 146)
end)

h.test("two-line blocks fit their lines", function()
  local T = ns.Theme.sizes
  -- two 12 pt lines (about 14 px each) plus the 1 px insets
  h.eq(T.footerItemsHeight >= 2 * 14 + 2, true)
  h.eq(T.footerTotalHeight >= 2 * 14 + 2, true)
  -- gold: one 12 pt line (14) + insets
  h.eq(T.footerGoldHeight >= 14 + 2, true)
  h.eq(T.footerLabelHeight >= 18, true)
end)

h.test("gold line fits the content width at the minimum window width", function()
  local T = ns.Theme.sizes
  local content = T.minWidth - 2 * (T.padding + 4)
  -- "Gold " + "999g 59s 59c" left, "999g 59s 59c/h" right, 6 px gap
  h.eq((5 + 12) * T.summaryCharPx + 6 + 14 * T.summaryCharPx <= content, true)
end)

h.test("minHeight leaves the list at least four rows beside a full Top finds block", function()
  local T = ns.Theme.sizes
  h.eq(T.minListRows, 4)
  h.eq(S.requiredWindowHeight(), 24 + 56 + 84 + 4 * 28 + 146)
  h.eq(T.minHeight >= S.requiredWindowHeight(), true)
  h.eq(T.minHeight, 422)
end)

h.test("goldText formats total and rate", function()
  local t = S.goldText({ total = 37304, perHour = 1000 })
  h.eq(t.total, "Gold " .. M.format(37304))
  h.eq(t.rate, M.format(1000) .. "/h")
  local c = ns.Theme.colors
  h.eq(t.totalColored, "Gold " .. M.formatColored(37304, c))
  h.eq(t.rateColored, M.formatColored(1000, c) .. "/h")
  h.eq(t.breakdown, nil)
end)

h.test("goldText shows 0c when empty, em dash for nil rate, never n/a", function()
  local t = S.goldText({ total = 0 })
  h.eq(t.total, "Gold 0c")
  h.eq(t.rate, "\226\128\148")
  h.eq(t.rateColored, "\226\128\148")
  local n = S.goldText(nil)
  h.eq(n.total, "Gold 0c")
  for _, v in pairs(t) do h.eq(v:find("n/a", 1, true), nil) end
  for _, v in pairs(n) do h.eq(v:find("n/a", 1, true), nil) end
end)

h.test("combinedText formats like the item totals without markers", function()
  local t = S.combinedText({ vendor = 5000, ah = 9000, vendorPerHour = 100, ahPerHour = 200 })
  h.eq(t.vendor, "Vendor: " .. M.format(5000))
  h.eq(t.ah, "AH: " .. M.format(9000))
  h.eq(t.vendorRate, M.format(100) .. "/h")
  h.eq(t.ahRate, M.format(200) .. "/h")
  local c = ns.Theme.colors
  h.eq(t.vendorColored, "Vendor: " .. M.formatColored(5000, c))
  h.eq(t.ahRateColored, M.formatColored(200, c) .. "/h")
  h.eq(t.unpriced, nil)
  h.eq(t.filtered, nil)
  local e = S.combinedText({ vendor = 0, ah = 0 })
  h.eq(e.vendorRate, "\226\128\148")
  h.eq(e.ahRateColored, "\226\128\148")
  h.eq(S.combinedText(nil).vendor, "Vendor: 0c")
end)

h.test("Summary.footerHeightFor: session full, inventory items block plus note", function()
  local S = ns.UI.Summary
  local sz = ns.Theme.sizes
  h.eq(S.footerHeightFor({}), sz.footerHeight)
  h.eq(S.footerHeightFor(nil), sz.footerHeight)
  h.eq(S.footerHeightFor({ kind = "inventory" }), sz.footerLabelHeight + sz.footerItemsHeight)
  h.eq(S.footerHeightFor({ kind = "inventory", note = "x" }),
    sz.footerLabelHeight + sz.footerItemsHeight + sz.footerNoteHeight)
end)

h.test("topLines carries a tooltip link when Rows is loaded", function()
  local rows = { { name = "A", quantity = 1, value = 5, quality = 1, id = 7, link = "L" } }
  h.eq(S.topLines(rows)[1].tooltipLink, nil) -- test namespace has no Rows
  ns.UI.Rows = { tooltipLink = function(r) return r.link end }
  h.eq(S.topLines(rows)[1].tooltipLink, "L")
  ns.UI.Rows = nil
end)
