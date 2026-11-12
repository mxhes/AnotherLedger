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

h.test("footer fits its two stacked lines", function()
  local T = ns.Theme.sizes
  -- two 12 pt lines (about 14 px each) plus the 1 px insets
  h.eq(T.footerHeight >= 2 * 14 + 2, true)
end)
