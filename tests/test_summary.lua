local h = ...
local ns = h.load({ "Util.lua", "Money.lua", "Theme.lua", "View.lua", "UI/Summary.lua" })
local S = ns.UI.Summary
local M = ns.Money

h.test("rateText: money per hour, em dash without a rate", function()
  h.eq(S.rateText(5000, M.format), "50s") -- the column title says per hour
  h.eq(S.rateText(nil, M.format), "\226\128\148")
  h.eq(S.rateText(nil), "\226\128\148")
  h.eq(S.rateText(5000), M.formatColored(5000, ns.Theme.colors))
end)

h.test("topLines", function()
  h.eq(#S.topLines({}), 0)
  h.eq(#S.topLines(nil), 0)
  local l = S.topLines({ { name = "Ore", quantity = 4, value = 500, quality = 2 } })
  h.eq(#l, 1)
  h.eq(l[1].name, "Ore")
  h.eq(l[1].qty, "x4")
  h.eq(l[1].value, M.formatColored(500, ns.Theme.colors))
  h.eq(S.topLines({ { name = "Ore", quantity = 4, value = 500 } }, M.format)[1].value, M.format(500))
  h.eq(l[1].quality, 2)
end)

h.test("topBoxHeight", function()
  h.eq(S.topBoxHeight(0), 0)
  h.eq(S.topBoxHeight(nil), 0)
  local T = ns.Theme.sizes
  h.eq(S.topBoxHeight(1), T.topHeaderHeight + T.topRowHeight + T.padding / 2 + T.dividerHeight)
  h.eq(S.topBoxHeight(3), T.topHeaderHeight + 3 * T.topRowHeight + T.padding / 2 + T.dividerHeight)
  h.eq(S.topBoxHeight(3), 22 + 3 * 20 + 4 + 2)
  h.eq(S.topBoxHeight(5), S.topBoxHeight(3))
end)

h.test("minHeight leaves the list at least four rows beside a full Top finds block", function()
  local T = ns.Theme.sizes
  h.eq(T.minListRows, 4)
  h.eq(S.requiredWindowHeight(), 24 + 84 + 88 + 4 * 30 + 72)
  h.eq(T.minHeight >= S.requiredWindowHeight(), true)
  h.eq(T.minHeight, 388)
  h.eq(T.footerHeight, 72)
end)

h.test("topLines carries a tooltip link when Rows is loaded", function()
  local rows = { { name = "A", quantity = 1, value = 5, quality = 1, id = 7, link = "L" } }
  h.eq(S.topLines(rows)[1].tooltipLink, nil) -- test namespace has no Rows
  ns.UI.Rows = { tooltipLink = function(r) return r.link end }
  h.eq(S.topLines(rows)[1].tooltipLink, "L")
  ns.UI.Rows = nil
end)

h.test("tableLayout: session, inventory, noCombined", function()
  local r = ns.Theme.sizes.footerRowHeight
  local s = S.tableLayout({ totals = {} })
  h.eq(s.rows, { "items", "gold", "total" })
  h.eq(s.rates, true)
  h.eq(s.titles, true)
  h.eq(s.height, 72)
  h.eq(4 * r, 72)
  h.eq(S.tableLayout(nil).height, 72)
  local inv = S.tableLayout({ kind = "inventory", totals = {} })
  h.eq(inv.rows, { "items" })
  h.eq(inv.rates, false)
  h.eq(inv.titles, false)
  h.eq(inv.height, 18)
  h.eq(S.tableLayout({ noCombined = true, totals = {} }).rows, { "items", "gold" })
  h.eq(S.tableLayout({ noCombined = true, totals = {} }).height, 54)
  h.eq(S.tableLayout({ kind = "inventory", note = "x", totals = {} }).height, 18 + 16)
  h.eq(S.tableLayout({ totals = { unpriced = 1 } }).notes, true)
end)

h.test("rowTexts: best value and rate per row, em dash without a rate", function()
  local t = S.rowTexts({ totals = { best = 1000, bestPerHour = 300 }, gold = { total = 50 },
    combined = { best = 1050, bestPerHour = 320 } }, M.format)
  h.eq(t.items.value, M.format(1000))
  h.eq(t.items.rate, M.format(300))
  h.eq(t.gold.value, M.format(50))
  h.eq(t.gold.rate, "\226\128\148")
  h.eq(t.total.value, M.format(1050))
  h.eq(t.total.rate, M.format(320))
  local e = S.rowTexts({}, M.format)
  h.eq(e.items.value, "0c")
  h.eq(e.total.rate, "\226\128\148")
  for _, row in pairs(e) do h.eq(row.rate:find("n/a", 1, true), nil) end
  h.eq(S.rowTexts(nil, M.format).gold.value, "0c")
end)

h.test("notesText: markers and bank note on one line", function()
  h.eq(S.notesText({ totals = {} }), nil)
  h.eq(S.notesText(nil), nil)
  local text, orange = S.notesText({ totals = { filtered = true, unpriced = 3 } })
  h.eq(text, "filtered \194\183 3 unpriced (marked ?)")
  h.eq(orange, true)
  text, orange = S.notesText({ kind = "inventory", totals = {}, note = "Scanned 3h ago" })
  h.eq(text, "Scanned 3h ago")
  h.eq(orange, false)
  text, orange = S.notesText({ totals = { unpriced = 2 }, note = "Scanned 2d ago", noteStale = true })
  h.eq(text, "2 unpriced (marked ?) \194\183 Scanned 2d ago")
  h.eq(orange, true)
end)

h.test("tooltipLines: items and items + gold with rates; inventory without", function()
  local view = { totals = { vendor = 1, ah = 2, best = 2, vendorPerHour = 10, ahPerHour = 20, bestPerHour = 20 },
    combined = { vendor = 3, ah = 4, best = 4 } }
  local l = S.tooltipLines(view, M.format)
  h.eq(l[1], { "Items", "" })
  h.eq(l[2], { "Vendor: ", M.format(1) .. "  " .. M.format(10) .. "/h", "vendor" })
  h.eq(l[3][3], "ah")
  h.eq(l[4], { "Best: ", M.format(2) .. "  " .. M.format(20) .. "/h" })
  h.eq(l[5], { "Total", "" })
  h.eq(l[6], { "Vendor: ", M.format(3) .. "  " .. "\226\128\148", "vendor" })
  h.eq(#l, 8)
  local inv = S.tooltipLines({ kind = "inventory", totals = { vendor = 1, ah = 2, best = 2 } }, M.format)
  h.eq(#inv, 4)
  h.eq(inv[2], { "Vendor: ", M.format(1), "vendor" })
  h.eq(#S.tooltipLines({ noCombined = true, totals = view.totals, combined = view.combined }, M.format), 4)
end)

h.test("table worst case fits the minimum window width", function()
  local T = ns.Theme.sizes
  h.eq(S.tableWorstWidth() <= T.minWidth - 2 * (T.padding + 4), true)
end)

h.test("notesText: Zones and Mobs say where the unpriced items are, like Bags", function()
  h.eq(S.notesText({ history = true, kind = "zones", totals = { unpriced = 2 } }), "2 unpriced (marked ?)")
end)

h.test("tooltipLines end with what a History view counts, as a wrapping line", function()
  local lines = S.tooltipLines({ kind = "zones", history = true, totals = { best = 1 }, scope = "Counts X." }, M.format)
  h.eq(lines[#lines][1], "Counts X.")
  h.eq(lines[#lines].wrap, true)
  h.eq(S.tooltipLines({ totals = {} }, M.format)[1].wrap, nil)
end)

h.test("tooltipLines keep the per hour suffix on rates", function()
  local lines = S.tooltipLines({ totals = { best = 1000, bestPerHour = 300 } }, M.format)
  local found = false
  for _, l in ipairs(lines) do if l[2]:find(M.format(300) .. "/h", 1, true) then found = true end end
  h.eq(found, true)
end)

h.test("tableLayout: raw gold In Total only drops the Raw gold row", function()
  ns.Options, ns.db = { get = function(_, key) if key == "rawGold" then return "total" end end }, {}
  local ok, err = pcall(function()
    h.eq(S.tableLayout({ totals = {} }).rows, { "items", "total" })
    h.eq(S.tableLayout({ noCombined = true, totals = {} }).rows, { "items" })
    h.eq(S.tableLayout({ totals = {} }).height, 3 * ns.Theme.sizes.footerRowHeight)
  end)
  ns.Options, ns.db = nil, nil
  assert(ok, err)
end)

h.test("table worst case still fits the minimum width with coin icons", function()
  local T = ns.Theme.sizes
  local plain = S.tableWorstWidth()
  M.setIcons(true)
  local ok, err = pcall(function()
    h.eq(S.tableWorstWidth() > plain, true)
    h.eq(S.tableWorstWidth() <= T.minWidth - 2 * (T.padding + 4), true)
  end)
  M.setIcons(false)
  assert(ok, err)
end)

h.test("tableLayout: History and Zones show the session table", function()
  for _, kind in ipairs({ "history", "zones" }) do
    local l = S.tableLayout({ kind = kind, history = true, totals = { unpriced = 2, filtered = true } })
    h.eq(l.rows, { "items", "gold", "total" }, kind)
    h.eq(l.titles, true, kind)
    h.eq(l.rates, true, kind)
    h.eq(l.notes, true, kind)
    h.eq(l.height > 0, true, kind)
  end
end)

h.test("notesText: the session goal in percent, reached at 100", function()
  h.eq(S.notesText({ totals = {}, goal = { value = 2500, goal = 10000 } }), "Goal 25%")
  h.eq(S.notesText({ totals = {}, goal = { value = 20000, goal = 10000 } }), "Goal reached")
end)

h.test("tableLayout: Bags with kept items show Kept and Sellable", function()
  local layout = S.tableLayout({ kind = "inventory", totals = { best = 800, kept = 500, sellable = 300 } })
  h.eq(layout.rows, { "items", "kept", "sellable" })
  h.eq(layout.height, 3 * ns.Theme.sizes.footerRowHeight)
  h.eq(S.tableLayout({ kind = "inventory", totals = { best = 800 } }).rows, { "items" })
  local t = S.rowTexts({ totals = { best = 800, kept = 500, sellable = 300 } }, M.format)
  h.eq({ t.kept.value, t.sellable.value }, { "5s", "3s" })
end)

h.test("tooltipLines: lists the unpriced items and how many more", function()
  local l = S.tooltipLines({ history = true, totals = { vendor = 1, ah = 2, best = 2, unpriced = 3,
    unpricedNames = { "Ore x2" } } }, M.format)
  local n = #l
  h.eq(l[n - 2][1], "Unpriced")
  h.eq(l[n - 1][1], "Ore x2")
  h.eq(l[n][1], "and 2 more")
end)

h.test("rowTexts / notesText: an unscanned bank shows a dash, no note", function()
  local view = { kind = "inventory", unscanned = true, totals = { best = 0 } }
  h.eq(S.rowTexts(view, M.format).items.value, "\226\128\148")
  h.eq(S.notesText(view), nil)
end)

h.test("tableLayout: Bags with gold on hand adds Gold on hand and Net worth; tooltip has the sell split", function()
  h.eq(S.tableLayout({ kind = "inventory", totals = { kept = 1, sellable = 2, money = 5, worth = 8 } }).rows,
    { "items", "kept", "sellable", "money", "worth" })
  h.eq(S.tableLayout({ kind = "inventory", totals = { money = 5, worth = 8 } }).rows, { "items", "money", "worth" })
  local t = S.rowTexts({ kind = "inventory", totals = { best = 3, money = 5, worth = 8 } }, M.format)
  h.eq(t.money.value, M.format(5))
  h.eq(t.worth.value, M.format(8))
  local lines = S.tooltipLines({ kind = "inventory",
    totals = { vendor = 1, ah = 2, best = 2, sellSplit = { vendor = 10, ah = 20, de = 30 } } }, M.format)
  h.eq(lines[5], { "Sell split", "" })
  h.eq(lines[6], { "Vendor: ", M.format(10), "vendor" })
  h.eq(lines[7], { "AH: ", M.format(20), "ah" })
  h.eq(lines[8], { "Destroy: ", M.format(30), "de" })
end)
