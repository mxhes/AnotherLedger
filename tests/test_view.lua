local h = ...
local ns = h.load({ "Util.lua", "Money.lua", "Theme.lua", "Tooltip.lua", "Prices.lua", "Session.lua", "History.lua", "View.lua" })
local function tipText(row) return ns.Tooltip.text(row.hint) end
local V = ns.View

local function link(name) return "|cff0070dd|Hitem:1::|h[" .. name .. "]|h|r" end

-- items: {id, name, qty, lastSeen}
local function session(items, elapsed)
  local s = { running = false, elapsedBase = elapsed or 3600, items = {} }
  for _, it in ipairs(items) do
    s.items[it[1]] = { id = it[1], link = link(it[2]), qty = it[3], lastSeen = it[4] or 0 }
  end
  return s
end

local PRICES = {}   -- id -> {vendor, ah, ahSource, ahAge}
local INFO = {}     -- id -> {name, quality}
local function opts(extra)
  local o = {
    now = 10000,
    lookup = function(id) return PRICES[id] end,
    itemInfo = function(id) return INFO[id] end,
  }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end
local function reset()
  PRICES, INFO = {}, {}
  PRICES[1] = { vendor = 10, ah = 500, ahSource = "TSM", ahAge = 0 }
  PRICES[2] = { vendor = 100, ah = 300, ahSource = "TSM", ahAge = 0 }
  PRICES[3] = { vendor = 500 } -- AH n/a
  INFO[1] = { name = "Kingsblood", quality = 1 }
  INFO[2] = { name = "Arcane Dust", quality = 3 }
  INFO[3] = { name = "Zinc Bar", quality = 2 }
end
local function three(elapsed)
  return session({ { 1, "Kingsblood", 4, 30 }, { 2, "Arcane Dust", 2, 20 }, { 3, "Zinc Bar", 1, 10 } }, elapsed)
end
local function ids(rows)
  local t = {}
  for i, r in ipairs(rows) do t[i] = r.id end
  return t
end

h.test("View rows aggregate per item with prices", function()
  reset()
  local v = V.build(three(), opts())
  h.eq(#v.rows, 3)
  local r = v.rows[1]
  h.eq(r.id, 1); h.eq(r.name, "Kingsblood"); h.eq(r.quality, 1); h.eq(r.quantity, 4)
  h.eq(r.vendorEach, 10); h.eq(r.vendorTotal, 40); h.eq(r.ahEach, 500); h.eq(r.ahTotal, 2000)
  h.eq(r.value, 2000); h.eq(r.lastSeen, 30); h.eq(r.ahFromCache, false); h.eq(r.stale, false)
  h.eq(r.link, link("Kingsblood"))
end)

h.test("View default sort is AH total desc, ties by name then id", function()
  reset()
  local v = V.build(three(), opts())
  h.eq(ids(v.rows), { 1, 2, 3 }) -- 2000, 600, none
  PRICES[2] = { vendor = 1, ah = 1000 } -- 2*1000 = 2000 == item 1
  v = V.build(three(), opts())
  h.eq(ids(v.rows), { 2, 1, 3 }) -- "Arcane Dust" < "Kingsblood"
  INFO[2].name = "Kingsblood"
  v = V.build(three(), opts())
  h.eq(ids(v.rows), { 1, 2, 3 }) -- same name -> id
end)

h.test("View sort vendor, name, recent", function()
  reset()
  h.eq(ids(V.build(three(), opts({ sort = "vendor" })).rows), { 3, 2, 1 }) -- 500, 200, 40
  h.eq(ids(V.build(three(), opts({ sort = "name" })).rows), { 2, 1, 3 })
  h.eq(ids(V.build(three(), opts({ sort = "recent" })).rows), { 1, 2, 3 })
  local s = three()
  s.items[3].lastSeen = 99
  h.eq(ids(V.build(s, opts({ sort = "recent" })).rows), { 3, 1, 2 })
end)

h.test("View unknown sort falls back to ah", function()
  reset()
  h.eq(ids(V.build(three(), opts({ sort = "bogus" })).rows), ids(V.build(three(), opts({ sort = "ah" })).rows))
end)

h.test("View filter by quality", function()
  reset()
  local v = V.build(three(), opts({ filter = { qualities = { [3] = true } } }))
  h.eq(ids(v.rows), { 2 })
  h.eq(v.totals.filtered, true)
end)

h.test("View minValue compares value (vendor fallback)", function()
  reset()
  h.eq(ids(V.build(three(), opts({ filter = { minValue = 500 } })).rows), { 1, 2, 3 }) -- 2000, 600, vendor 500
  h.eq(ids(V.build(three(), opts({ filter = { minValue = 550 } })).rows), { 1, 2 })
end)

h.test("View search is case-insensitive and literal", function()
  reset()
  h.eq(ids(V.build(three(), opts({ filter = { search = "kings" } })).rows), { 1 })
  INFO[3].name = "Bar (rare)"
  INFO[2].name = "100% Dust [x]"
  local s = three()
  h.eq(ids(V.build(s, opts({ filter = { search = "(" } })).rows), { 3 })
  h.eq(ids(V.build(s, opts({ filter = { search = "%" } })).rows), { 2 })
  h.eq(ids(V.build(s, opts({ filter = { search = "[X" } })).rows), { 2 })
  h.eq(ids(V.build(s, opts({ filter = { search = ".*" } })).rows), {})
end)

h.test("View.isFiltered", function()
  h.eq(V.isFiltered({ minValue = 0, search = "", qualities = nil }), false)
  h.eq(V.isFiltered(nil), false)
  h.eq(V.isFiltered({}), false)
  local all = {}
  for q = 0, 7 do all[q] = true end
  h.eq(V.isFiltered({ qualities = all }), false)
  h.eq(V.isFiltered({ qualities = { [3] = true } }), true)
  h.eq(V.isFiltered({ minValue = 1 }), true)
  h.eq(V.isFiltered({ search = "a" }), true)
end)

h.test("View nil filter and opts.filter mean no filtering", function()
  reset()
  local v = V.build(three(), opts())
  h.eq(#v.rows, 3); h.eq(v.totals.filtered, false)
end)

h.test("View totals follow visible rows", function()
  reset()
  local all = V.build(three(), opts())
  h.eq(all.totals.vendor, 40 + 200 + 500)
  h.eq(all.totals.ah, 2000 + 600)
  h.eq(all.totals.unpriced, 1)
  h.eq(all.totals.filtered, false)
  local f = V.build(three(), opts({ filter = { qualities = { [1] = true, [3] = true } } }))
  h.eq(#f.rows, 2)
  h.eq(f.totals.vendor, 240); h.eq(f.totals.ah, 2600); h.eq(f.totals.unpriced, 0)
  h.eq(f.totals.filtered, true)
end)

h.test("View per hour rates", function()
  reset()
  PRICES[1] = { vendor = 0, ah = 300000 }
  local v = V.build(three(3600), opts())
  h.eq(v.totals.ahPerHour, 1200000 + 600)
  h.eq(v.totals.vendorPerHour, 0 + 200 + 500)
  h.eq(V.build(three(30), opts()).totals.ahPerHour, nil)
  h.eq(V.build(three(30), opts()).totals.vendorPerHour, nil)
  h.eq(V.build(three(0), opts()).totals.ahPerHour, nil)
  h.eq(V.build(three(0), opts()).totals.vendorPerHour, nil)
  h.eq(V.build(three(60), opts()).totals.ahPerHour ~= nil, true)
end)

h.test("View top finds", function()
  reset()
  local s = session({ { 1, "A", 1 }, { 2, "B", 1 }, { 3, "C", 1 }, { 4, "D", 1 }, { 5, "E", 1 } })
  for i = 1, 5 do INFO[i] = { name = string.char(64 + i), quality = 1 } end
  PRICES = {
    [1] = { ah = 100 }, [2] = { ah = 900 }, [3] = { ah = 900 }, [4] = { ah = 500 }, [5] = {},
  }
  local v = V.build(s, opts())
  h.eq(ids(v.top), { 2, 3, 4 })
  h.eq(V.TOP_COUNT, 3)
  local z = V.build(session({ { 5, "E", 1 } }), opts())
  h.eq(#z.top, 0) -- zero-value excluded
  local f = V.build(s, opts({ filter = { search = "d" } }))
  h.eq(ids(f.top), { 4 })
end)

h.test("View handles missing itemInfo", function()
  reset()
  INFO = {}
  local v = V.build(three(), opts())
  local r = v.rows[1]
  h.eq(r.name, "Kingsblood"); h.eq(r.quality, 1)
end)

h.test("View handles all-nil and nil lookup", function()
  reset()
  PRICES = { [1] = {}, [2] = false }
  local v = V.build(three(), opts())
  for _, r in ipairs(v.rows) do
    h.eq(r.value, 0); h.eq(r.ahEach, nil); h.eq(r.vendorEach, nil)
  end
  h.eq(v.totals.unpriced, 3)
end)

h.test("View stale flag", function()
  reset()
  PRICES[1] = { ah = 500, ahSource = "cache", ahAge = 50400 }
  PRICES[2] = { ah = 300, ahSource = "cache", ahAge = 100 }
  PRICES[3] = { ah = 300, ahSource = "TSM", ahAge = 99999 }
  local v = V.build(three(), opts())
  local by = {}
  for _, r in ipairs(v.rows) do by[r.id] = r end
  h.eq(by[1].stale, true); h.eq(by[1].ahFromCache, true); h.eq(by[1].ahAge, 50400)
  h.eq(by[2].stale, false); h.eq(by[2].ahFromCache, true)
  h.eq(by[3].stale, false); h.eq(by[3].ahFromCache, false)
end)

h.test("View skips zero or missing qty", function()
  reset()
  local s = three()
  s.items[2].qty = 0
  s.items[3].qty = nil
  h.eq(ids(V.build(s, opts()).rows), { 1 })
end)

h.test("View indexOf and flashLevel", function()
  reset()
  local v = V.build(three(), opts())
  h.eq(V.indexOf(v.rows, 2), 2)
  h.eq(V.indexOf(v.rows, 99), nil)
  h.eq(V.flashLevel(60000, 2), "strong")
  h.eq(V.flashLevel(1000, 5), "normal")
  h.eq(V.flashLevel(nil, 1), "normal")
  h.eq(V.flashLevel(100000, 1), "strong")
  h.eq(V.STRONG_FLASH_VALUE, 100000); h.eq(V.MIN_RATE_SECONDS, 60)
end)

local function withGold(s, total)
  s.gold = total
  return s
end

h.test("View gold-only session", function()
  reset()
  local v = V.build(withGold(session({}, 3600), 15000), opts())
  h.eq(v.gold.total, 15000)
  h.eq(v.gold.perHour, 15000)
  h.eq(v.combined.vendor, 15000); h.eq(v.combined.ah, 15000)
  h.eq(v.combined.vendorPerHour, 15000); h.eq(v.combined.ahPerHour, 15000)
  h.eq(v.totals.vendor, 0)
end)

h.test("View items-only session has zero gold", function()
  reset()
  local v = V.build(three(3600), opts())
  h.eq(v.gold.total, 0); h.eq(v.gold.perHour, 0)
  h.eq(v.combined.vendor, v.totals.vendor); h.eq(v.combined.ah, v.totals.ah)
  h.eq(v.combined.ahPerHour, v.totals.ahPerHour)
  -- sessions without a gold field (old records, tests) behave the same
  local s = three(3600)
  s.gold = nil
  h.eq(V.build(s, opts()).gold, { total = 0, perHour = 0 })
end)

h.test("View combined = items + gold on both sides", function()
  reset()
  local v = V.build(withGold(three(7200), 1200), opts())
  h.eq(v.totals.vendor, 740); h.eq(v.totals.ah, 2600)
  h.eq(v.combined.vendor, 740 + 1200); h.eq(v.combined.ah, 2600 + 1200)
  h.near(v.combined.vendorPerHour, (740 + 1200) / 2)
  h.near(v.combined.ahPerHour, (2600 + 1200) / 2)
  h.near(v.gold.perHour, 600)
end)

h.test("View unpriced items still count 0 on the AH side of the combined total", function()
  reset()
  PRICES = { [3] = { vendor = 500 } }
  local v = V.build(withGold(session({ { 3, "Zinc Bar", 2 } }, 3600), 100), opts())
  h.eq(v.combined.ah, 100)
  h.eq(v.combined.vendor, 1100)
  h.eq(v.totals.unpriced, 1)
end)

h.test("View combined item part follows the filter, gold does not", function()
  reset()
  local s = withGold(three(3600), 1000)
  local f = V.build(s, opts({ filter = { qualities = { [1] = true, [3] = true } } }))
  h.eq(f.totals.vendor, 240); h.eq(f.totals.ah, 2600)
  h.eq(f.combined.vendor, 1240); h.eq(f.combined.ah, 3600)
  h.eq(f.gold.total, 1000)
  h.eq(f.totals.filtered, true)
  local none = V.build(s, opts({ filter = { search = "zzzz" } }))
  h.eq(#none.rows, 0)
  h.eq(none.combined.vendor, 1000); h.eq(none.combined.ah, 1000)
  h.eq(none.gold.total, 1000)
end)

h.test("View gold rates: stopped time excluded, nil under 60 s", function()
  reset()
  local s = withGold({ running = true, runningSince = 9000, elapsedBase = 1800, items = {} }, 3600)
  local v = V.build(s, opts({ now = 10800 })) -- 1800 + 1800 running
  h.eq(v.gold.perHour, 3600)
  s.running, s.runningSince = false, nil
  h.eq(V.build(s, opts({ now = 999999 })).gold.perHour, 7200)
  local young = V.build(withGold(session({}, 59), 10000), opts())
  h.eq(young.gold.perHour, nil)
  h.eq(young.combined.vendorPerHour, nil); h.eq(young.combined.ahPerHour, nil)
  h.eq(young.gold.total, 10000)
  h.eq(V.build(withGold(session({}, 60), 5000), opts()).gold.perHour, 300000)
end)

h.test("View ignores malformed gold fields", function()
  reset()
  local s = three(3600)
  s.gold = -5
  local v = V.build(s, opts())
  h.eq(v.gold.total, 0)
  s.gold = "oops"
  h.eq(V.build(s, opts()).gold.total, 0)
end)

h.test("View.buildInventory: rows and totals like the session, no rates or gold", function()
  reset()
  local s = three()
  local v = V.buildInventory(s.items, opts({ sort = "ah" }))
  h.eq(v.kind, "inventory")
  h.eq(ids(v.rows), { 1, 2, 3 })
  h.eq(v.totals.ah, 4 * 500 + 2 * 300)
  h.eq(v.totals.vendor, 4 * 10 + 2 * 100 + 500)
  h.eq(v.totals.unpriced, 1)
  h.eq(v.totals.vendorPerHour, nil)
  h.eq(v.gold, nil)
  h.eq(v.top, {})
  -- filters apply
  local f = V.buildInventory(s.items, opts({ filter = { search = "zinc" } }))
  h.eq(ids(f.rows), { 3 })
  h.eq(f.totals.filtered, true)
end)

h.test("View rows carry the disenchant value times quantity", function()
  local session = { startedAt = 0, running = true, runningSince = 0, elapsedBase = 0, gold = 0,
    items = { [7] = { id = 7, link = "[A]", qty = 3, lastSeen = 1 } } }
  local v = ns.View.build(session, { now = 10, sort = "ah",
    lookup = function() return { ah = 100, de = 40 } end })
  h.eq(v.rows[1].deEach, 40); h.eq(v.rows[1].deTotal, 120)
  v = ns.View.build(session, { now = 10, sort = "ah", lookup = function() return { ah = 100 } end })
  h.eq(v.rows[1].deTotal, nil)
end)

h.test("View.buildHistory: one row per archived session with totals", function()
  local list = {
    { startedAt = 200, elapsed = 3600, gold = 40, nItems = 3, vendor = 10, ah = 100, items = {} },
    { startedAt = 100, elapsed = 60, gold = 0, nItems = 1, vendor = 5, ah = 20, items = {} },
    "garbage",
  }
  local v = ns.View.buildHistory(list, { formatDate = function(t) return "d" .. t end })
  h.eq(#v.rows, 2)
  h.eq(v.rows[1].name, "+ d200  1h 0m"); h.eq(v.rows[1].historyIndex, 1)
  h.eq(v.rows[1].ahTotal, 100); h.eq(v.rows[1].deTotal, nil); h.eq(v.rows[1].bestLineTotal, 100)
  h.eq(v.rows[2].historyIndex, 2)
  h.eq(v.totals.vendor, 15); h.eq(v.totals.ah, 120)
  h.eq(v.kind, "history")
  h.eq(v.gold.total, 40)
  h.eq(v.combined.ah, 160)
  h.near(v.totals.ahPerHour, 120 * 3600 / 3660)
  h.eq(#ns.View.buildHistory(nil, {}).rows, 0)
end)

h.test("View.buildHistory: an opened session lists its items at the saved prices", function()
  local list = {
    { startedAt = 1, elapsed = 3600, gold = 0, nItems = 2, vendor = 20, ah = 300, best = 320, items = {
      [1] = { id = 1, key = 1, qty = 2, lastSeen = 1, price = { vendor = 10, ah = 150 } },
      [2] = { id = 2, key = 2, qty = 1, lastSeen = 1 }, -- saved before prices were kept
    } },
  }
  local live = { [1] = { vendor = 10, ah = 999, ahSource = "TSM", ahAge = 0 },
    [2] = { vendor = 7, ah = 20, ahSource = "cache", ahAge = 7200 } }
  local v = ns.View.buildHistory(list, { now = 9000, lookup = function(id) return live[id] end }, 1)
  local byID = {}
  for _, r in ipairs(v.rows) do if r.id > 0 then byID[r.id] = r end end
  h.eq(byID[1].ahTotal, 300) -- saved, not today's 999
  h.eq(byID[1].ahFromCache, false); h.eq(byID[1].ahAge, nil)
  h.eq(byID[2].ahTotal, 20) -- nothing saved: today's price with its age
  h.eq(byID[2].ahAge, 7200)
end)

h.test("View.buildHistory: the place joins the name, the details the hint", function()
  local list = {
    { startedAt = 200, elapsed = 3600, gold = 10000, nItems = 1, vendor = 10, ah = 100, best = 150,
      places = { "The Stonevault (Heroic)", "Dornogal" }, items = {} },
  }
  local v = ns.View.buildHistory(list, { formatDate = function() return "D" end })
  h.eq(v.rows[1].name, "+ D  1h 0m  The Stonevault (Heroic)")
  h.eq(v.rows[1].value, 150)
  h.eq(v.totals.best, 150)
  h.eq(tipText(v.rows[1]):find("Places: The Stonevault (Heroic), Dornogal", 1, true) ~= nil, true)
  h.eq(tipText(v.rows[1]):find("Raw gold: 1g  (1g/h)", 1, true) ~= nil, true)
end)

h.test("View: the best of vendor, AH and disenchant is the row value", function()
  local session = { startedAt = 0, running = true, runningSince = 0, elapsedBase = 0, gold = 0,
    items = {
      [1] = { id = 1, link = "[A]", qty = 2, lastSeen = 1 },
      [2] = { id = 2, link = "[B]", qty = 1, lastSeen = 1 },
      [3] = { id = 3, link = "[C]", qty = 1, lastSeen = 1 },
    } }
  local prices = { [1] = { vendor = 50, ah = 10 }, [2] = { vendor = 5, ah = 100, de = 300 }, [3] = { vendor = 1, ah = 70 } }
  local v = ns.View.build(session, { now = 10, sort = "ah", lookup = function(id) return prices[id] end })
  h.eq(v.rows[1].id, 2); h.eq(v.rows[1].bestKind, "de"); h.eq(v.rows[1].value, 300)
  h.eq(v.rows[2].id, 1); h.eq(v.rows[2].bestKind, "vendor"); h.eq(v.rows[2].value, 100)
  h.eq(v.rows[3].bestKind, "ah")
  h.eq(v.totals.best, 470)
  h.eq(v.combined.best, 470)
  h.eq(v.top[1].id, 2)
end)

h.test("View: bound items are not counted as unpriced", function()
  local session = { startedAt = 0, running = true, runningSince = 0, elapsedBase = 0, gold = 0,
    items = { [1] = { id = 1, link = "[A]", qty = 1, lastSeen = 1 }, [2] = { id = 2, link = "[B]", qty = 1, lastSeen = 1 } } }
  local v = ns.View.build(session, { now = 10, lookup = function() return { vendor = 5 } end,
    itemInfo = function(id) return { name = "x" .. id, quality = 1, bound = id == 1 } end })
  h.eq(v.totals.unpriced, 1)
end)

h.test("View: loot-time prices fill in a missing live price with their age", function()
  local session = { startedAt = 0, running = true, runningSince = 0, elapsedBase = 0, gold = 0,
    items = { [1] = { id = 1, link = "[A]", qty = 2, lastSeen = 100, price = { ah = 40, vendor = 3 } } } }
  local v = ns.View.build(session, { now = 3700, lookup = function() return {} end })
  h.eq(v.rows[1].ahTotal, 80); h.eq(v.rows[1].ahFromCache, true); h.eq(v.rows[1].ahAge, 3600)
  h.eq(v.rows[1].vendorTotal, 6)
end)

h.test("View: variants have their own rows and keys; currencies follow the items", function()
  local session = { startedAt = 0, running = true, runningSince = 0, elapsedBase = 0, gold = 0,
    items = {
      [50] = { id = 50, key = 50, link = "[S]", qty = 1, lastSeen = 1 },
      ["50:1477"] = { id = 50, key = "50:1477", link = "[S]", qty = 1, lastSeen = 1 },
    },
    currencies = { [3008] = { id = 3008, link = "|Hcurrency:3008|h[Valorstones]|h", qty = 15 } } }
  local linkSeen = {}
  local v = ns.View.build(session, { now = 10, lookup = function(id, link) linkSeen[#linkSeen + 1] = link
    return { ah = 10 } end })
  h.eq(#v.rows, 3)
  h.eq(v.rows[3].isCurrency, true); h.eq(v.rows[3].name, "Valorstones"); h.eq(v.rows[3].quantity, 15)
  h.eq(v.rows[3].key, "c:3008")
  h.eq(ns.View.indexOf(v.rows, "50:1477") ~= nil, true)
  h.eq(linkSeen[1], "[S]")
  h.eq(v.totals.unpriced, 0)
  v = ns.View.build(session, { now = 10, showCurrencies = false, lookup = function() return { ah = 10 } end })
  h.eq(#v.rows, 2)
end)

h.test("View.buildHistory: the opened session moves to the top with its items under it", function()
  local list = {
    { startedAt = 200, elapsed = 60, gold = 0, nItems = 1, vendor = 5, ah = 20, items = {} },
    { startedAt = 100, elapsed = 120, gold = 12400, nItems = 2, vendor = 40, ah = 2000, items = {
      [7] = { id = 7, link = "[A]", qty = 4, lastSeen = 1 },
      [8] = { id = 8, link = "[B]", qty = 1, lastSeen = 1 } } },
  }
  local opts = { formatDate = function() return "D" end,
    lookup = function(id) return { vendor = 1, ah = id == 7 and 500 or 100 } end }
  local v = ns.View.buildHistory(list, opts, 2)
  h.eq(#v.rows, 4)
  h.eq(v.rows[1].historyIndex, 2); h.eq(v.rows[1].name, "- D  2m")
  h.eq(tipText(v.rows[1]):match("[^\n]+$"), "Click to collapse")
  h.eq(v.rows[2].id, 7); h.eq(v.rows[2].ahTotal, 2000) -- items, best AH value first
  h.eq(v.rows[3].id, 8)
  h.eq(v.rows[4].historyIndex, 1) -- the other session follows
  h.eq(v.totals.ah, 2020) -- totals still cover every session
  -- an index that is not in the list opens nothing
  h.eq(#ns.View.buildHistory(list, opts, 9).rows, 2)
end)

h.test("View.applyRates recomputes only the rates and clears them for a young session", function()
  local s = ns.Session.new(0)
  ns.Session.add(s, 1, "|Hitem:1|h[A]|h", 2, 0)
  ns.Session.addGold(s, 500, 0)
  local opts = { now = 3600, lookup = function() return { vendor = 10, ah = 100 } end }
  local v = ns.View.build(s, opts)
  h.near(v.totals.ahPerHour, 200)
  h.near(v.gold.perHour, 500)
  h.near(v.combined.vendorPerHour, 520)
  local rows = v.rows
  h.eq(ns.View.applyRates(v, 7200) == v, true)
  h.eq(v.rows == rows, true) -- rows are not rebuilt
  h.near(v.totals.ahPerHour, 100)
  h.near(v.totals.vendorPerHour, 10)
  h.near(v.gold.perHour, 250)
  h.near(v.combined.ahPerHour, 350)
  ns.View.applyRates(v, 30) -- below MIN_RATE_SECONDS
  h.eq(v.totals.ahPerHour, nil)
  h.eq(v.gold.perHour, nil)
  h.eq(v.combined.vendorPerHour, nil)
  h.eq(v.totals.ah, 200) -- totals untouched
end)

h.test("top finds: best three by value, ties by name, zero value left out", function()
  local s = ns.Session.new(0)
  local values = { [1] = 50, [2] = 900, [3] = 0, [4] = 50, [5] = 300, [6] = 10 }
  local names = { [1] = "Zinc", [2] = "Ruby", [3] = "Dust", [4] = "Amber", [5] = "Opal", [6] = "Clay" }
  for id in pairs(values) do ns.Session.add(s, id, nil, 1, 0) end
  local v = ns.View.build(s, {
    now = 10,
    lookup = function(id) return { ah = values[id] > 0 and values[id] or nil } end,
    itemInfo = function(id) return { name = names[id], quality = 1 } end,
  })
  h.eq(#v.top, 3)
  h.eq({ v.top[1].id, v.top[2].id, v.top[3].id }, { 2, 5, 4 }) -- Amber before Zinc at 50
end)

h.test("search and name sort ignore case", function()
  local s = ns.Session.new(0)
  local names = { [1] = "banana", [2] = "Apple", [3] = "cherry" }
  for id in pairs(names) do ns.Session.add(s, id, nil, 1, 0) end
  local function info(id) return { name = names[id], quality = 1 } end
  local v = ns.View.build(s, { now = 10, sort = "name", itemInfo = info })
  h.eq({ v.rows[1].name, v.rows[2].name, v.rows[3].name }, { "Apple", "banana", "cherry" })
  local f = ns.View.build(s, { now = 10, sort = "name", itemInfo = info, filter = { search = "APP" } })
  h.eq(#f.rows, 1)
  h.eq(f.rows[1].name, "Apple")
end)

h.test("View.build: includeGold = false leaves the gold out of the combined totals", function()
  local session = { startedAt = 0, running = true, runningSince = 0, elapsedBase = 0, gold = 5000,
    items = { [7] = { id = 7, link = "[A]", qty = 1, lastSeen = 1 } } }
  local function build(extra)
    local o = { now = 10, sort = "ah", lookup = function() return { ah = 100, vendor = 10 } end }
    for k, v in pairs(extra or {}) do o[k] = v end
    return ns.View.build(session, o)
  end
  local on = build()
  h.eq(on.combined.ah, 5100)
  h.eq(on.noCombined, nil)
  local off = build({ includeGold = false })
  h.eq(off.combined.ah, 100)
  h.eq(off.combined.vendor, 10)
  h.eq(off.noCombined, true)
  h.eq(off.gold.total, 5000)
end)

h.test("View.marketLevels: three levels each, unknown values and no cutoffs give nil", function()
  local t = { rateGood = 0.1, rateOk = 0.03, soldHigh = 20, soldMedium = 2 }
  h.eq({ V.marketLevels(0.1, 20, t) }, { "good", "high" })
  h.eq({ V.marketLevels(0.05, 2, t) }, { "ok", "medium" })
  h.eq({ V.marketLevels(0.01, 0.5, t) }, { "bad", "low" })
  h.eq({ V.marketLevels(nil, 5, t) }, { nil, "medium" })
  h.eq({ V.marketLevels(0.5, 5, nil) }, {})
  -- a negative cutoff ("unlimited") is never reached
  h.eq(select(2, V.marketLevels(nil, 1e6, { soldHigh = -1, soldMedium = -1 })), "low")
end)

h.test("View.build: rows carry the sale info levels only with cutoffs", function()
  local s = session({ { 5, "Ore", 3 } })
  local lookup = function() return { ah = 100, saleRate = 0.2, soldPerDay = 1 } end
  local t = { rateGood = 0.1, rateOk = 0.03, soldHigh = 20, soldMedium = 2 }
  local row = V.build(s, { now = 10, sort = "ah", lookup = lookup, market = t }).rows[1]
  h.eq(row.rateLevel, "good")
  h.eq(row.volumeLevel, "low")
  row = V.build(s, { now = 10, sort = "ah", lookup = lookup }).rows[1]
  h.eq(row.rateLevel, nil)
  h.eq(row.volumeLevel, nil)
end)

-- ---------------------------------------------------------------------------
-- History Zones

local zprices = { [1] = { ah = 100 }, [2] = { vendor = 10 }, [3] = { ah = 1000 } }
local function zlookup(id) return zprices[id] end

-- A History entry: items = { [id] = qty } (all of them in `zones` when given).
local function zentry(items, zones, places, gold)
  local e = { startedAt = 1, elapsed = 0, gold = gold or 0, nItems = 0, vendor = 0, ah = 0,
    items = {}, zones = zones, places = places }
  for id, qty in pairs(items) do
    e.items[id] = { id = id, key = id, link = link("I" .. id), qty = qty, lastSeen = 5 }
  end
  return e
end
local function zsub(time, items, gold) return { time = time, gold = gold or 0, items = items } end

local function twoZones()
  local a = zentry({ [1] = 2 }, { Z = { subs = { A = zsub(1800, { [1] = 2 }) } } })
  local b = zentry({ [1] = 2, [2] = 1 }, {
    Z = { subs = { A = zsub(1800, { [1] = 2 }) } },
    Y = { subs = { B = zsub(3600, { [2] = 1 }, 50) } },
  })
  return { a, b }
end

h.test("View.buildZones adds up places across sessions and ranks them", function()
  local v = V.buildZones(twoZones(), { lookup = zlookup, sort = "ah" }, {})
  h.eq(#v.rows, 2)
  h.eq(v.rows[1].zoneKey, "Z")
  h.eq(v.rows[1].value, 400)
  h.eq(v.rows[1].placeTime, 3600)
  h.eq(v.rows[1].perHour, 400)
  h.eq(v.rows[2].zoneKey, "Y")
  h.eq(v.rows[2].value, 60)
  h.eq(v.kind, "zones")
  h.eq(v.totals.best, 410)
  h.eq(v.gold.total, 50)
end)

h.test("View.buildZones opens a zone into subzones and a subzone into items", function()
  local v = V.buildZones(twoZones(), { lookup = zlookup, sort = "ah" }, { zone = "Z" })
  h.eq(v.rows[2].subKey, "A")
  h.eq(v.rows[2].zoneKey, "Z")
  h.eq(#v.rows, 3)
  v = V.buildZones(twoZones(), { lookup = zlookup, sort = "ah" }, { zone = "Z", sub = "A" })
  h.eq(v.rows[3].id, 1)
  h.eq(v.rows[3].quantity, 4)
  h.eq(v.rows[4].zoneKey, "Y")
end)

h.test("View.buildZones sorts by gold per hour, places without time last", function()
  local list = {
    zentry({ [2] = 1 }, { P = { subs = { A = zsub(3600, { [2] = 1 }) } } }),
    zentry({ [3] = 1 }, nil, { "Q" }),
  }
  local v = V.buildZones(list, { lookup = zlookup, sort = "perHour" }, {})
  h.eq(v.rows[1].zoneKey, "P")
  h.eq(v.rows[1].perHour, 10)
  h.eq(v.rows[2].zoneKey, "Q")
  h.eq(v.rows[2].perHour, nil)
  v = V.buildZones(list, { lookup = zlookup, sort = "ah" }, {})
  h.eq(v.rows[1].zoneKey, "Q")
end)

h.test("View.buildZones puts old sessions under their only place or Unknown place, without time", function()
  local list = {
    zentry({ [1] = 1 }, { Z = { subs = { A = zsub(3600, { [1] = 1 }) } } }),
    zentry({ [1] = 1 }, nil, { "Z" }),
    zentry({ [2] = 1 }, nil, { "Z", "Y" }),
  }
  local v = V.buildZones(list, { lookup = zlookup, sort = "ah" }, { zone = "Z" })
  h.eq(v.rows[1].zoneKey, "Z")
  h.eq(v.rows[1].value, 200)
  h.eq(v.rows[1].perHour, 100) -- only the timed loot
  local subs = {}
  for _, r in ipairs(v.rows) do if r.subKey then subs[r.subKey] = r end end
  h.eq(subs.A.perHour, 100)
  h.eq(subs[V.NO_TIME_SUB].perHour, nil)
  h.eq(subs[V.NO_TIME_SUB].value, 100)
  h.eq(v.rows[#v.rows].zoneKey, V.UNKNOWN_ZONE)
  h.eq(V.UNKNOWN_ZONE, ns.Session.UNKNOWN_PLACE)
end)

h.test("View.buildZones groups quest items last, outside the totals", function()
  local list = { zentry({ [1] = 1, [3] = 1 }, { Z = { subs = { A = zsub(3600, { [1] = 1, [3] = 1 }) } } }) }
  local v = V.buildZones(list, { lookup = zlookup, sort = "ah", isQuest = function(id) return id == 3 end }, {})
  h.eq(#v.rows, 2)
  h.eq(v.rows[1].value, 100)
  h.eq(v.rows[2].zoneKey, V.QUEST_ZONE)
  h.eq(v.rows[2].value, 1000)
  h.eq(v.totals.best, 100)
  v = V.buildZones(list, { lookup = zlookup, sort = "ah", isQuest = function(id) return id == 3 end },
    { zone = V.QUEST_ZONE })
  h.eq(v.rows[3].id, 3)
end)

h.test("View.buildZones honors includeGold", function()
  local v = V.buildZones(twoZones(), { lookup = zlookup, sort = "ah", includeGold = false }, {})
  h.eq(v.rows[2].value, 10)
  h.eq(v.noCombined, true)
end)

h.test("View.buildZones skips broken entries and takes the running session", function()
  local live = { live = true, items = { [2] = { id = 2, key = 2, qty = 1, lastSeen = 9 } },
    zones = { Y = { subs = { B = zsub(60, { [2] = 1 }) } } } }
  local v = V.buildZones({ { startedAt = "x" }, live }, { lookup = zlookup, sort = "ah" }, {})
  h.eq(#v.rows, 1)
  h.eq(v.rows[1].zoneKey, "Y")
  h.eq(v.rows[1].lastSeen, 9)
end)

h.test("collect sorts items by value under the perHour sort", function()
  local items = {
    [2] = { id = 2, key = 2, link = link("Aa"), qty = 1, lastSeen = 0 }, -- first by name
    [3] = { id = 3, key = 3, link = link("Zz"), qty = 1, lastSeen = 0 }, -- first by value
  }
  local v = V.buildInventory(items, { lookup = zlookup, sort = "perHour" })
  h.eq(v.rows[1].id, 3)
  h.eq(v.rows[2].id, 2)
end)

h.test("View.buildZones places an archived old session under its only place", function()
  local old = { startedAt = 1, running = false, elapsedBase = 60, gold = 0, places = { Elwynn = 3 },
    items = { [1] = { id = 1, key = 1, qty = 2, lastSeen = 5 } } }
  local e = ns.History.snapshot(old, zlookup, 100)
  e.zones = nil -- saved before places were kept
  local v = V.buildZones({ e }, { lookup = zlookup, sort = "ah" }, { zone = "Elwynn" })
  h.eq(v.rows[1].zoneKey, "Elwynn")
  h.eq(v.rows[2].subKey, V.NO_TIME_SUB)
end)

h.test("View.buildZones: a short stay shows its time, not 'No time recorded'", function()
  local list = { zentry({ [1] = 1 }, { Z = { subs = { A = zsub(45, { [1] = 1 }) } } }) }
  local v = V.buildZones(list, { lookup = zlookup, sort = "ah" }, {})
  h.eq(v.rows[1].perHour, nil)
  h.eq(tipText(v.rows[1]):find(ns.L["No time recorded"], 1, true), nil)
end)

-- ---------------------------------------------------------------------------
-- Daily farm

local function farmEntries()
  return {
    zentry({ [1] = 4, [3] = 1 }, {
      Z = { subs = { A = zsub(3600, { [1] = 4 }), Short = zsub(60, { [3] = 1 }) } },
      Y = { subs = { B = zsub(1800, {}, 300) } },
    }),
  }
end

h.test("View.dailyFarm picks the subzone with the best gold per hour", function()
  local f = V.dailyFarm(farmEntries(), { lookup = zlookup }, 1200)
  h.eq(f.best.zone, "Y"); h.eq(f.best.sub, "B")
  h.eq(f.best.perHour, 600); h.eq(f.best.time, 1800); h.eq(f.best.value, 300)
  h.eq(#f.runnersUp, 1)
  h.eq(f.runnersUp[1].sub, "A"); h.eq(f.runnersUp[1].perHour, 400)
end)

h.test("View.dailyFarm skips places under the minimum time, quest items and no-time loot", function()
  -- "Short" (60 s, 1000c/min) would win without the minimum.
  local f = V.dailyFarm(farmEntries(), { lookup = zlookup }, 1200)
  for _, p in ipairs(f.runnersUp) do h.eq(p.sub ~= "Short", true) end
  h.eq(V.dailyFarm(farmEntries(), { lookup = zlookup }, 0).best.sub, "Short")
  local quest = V.dailyFarm(farmEntries(), { lookup = zlookup, isQuest = function(id) return id == 1 end }, 1200)
  h.eq(quest.best.sub, "B"); h.eq(#quest.runnersUp, 0) -- A is worth nothing without its quest items
  h.eq(V.dailyFarm({ zentry({ [1] = 9 }, nil, { "Z" }) }, { lookup = zlookup }, 0), nil)
end)

h.test("View.dailyFarm returns nil without qualifying places", function()
  h.eq(V.dailyFarm({}, { lookup = zlookup }, 1200), nil)
  h.eq(V.dailyFarm(farmEntries(), { lookup = zlookup }, 7200), nil)
  h.eq(V.dailyFarm(nil, {}, 0), nil)
end)

h.test("View.dailyFarm keeps at most two runner-ups, ties go to more time", function()
  local e = zentry({ [1] = 8 }, { Z = { subs = {
    A = zsub(3600, { [1] = 2 }), B = zsub(7200, { [1] = 4 }), C = zsub(1800, { [1] = 1 }), D = zsub(1800, {}),
  } } })
  local f = V.dailyFarm({ e }, { lookup = zlookup }, 0)
  h.eq(f.best.sub, "B") -- 200/h like A and C, most time
  h.eq(#f.runnersUp, 2)
  h.eq(f.runnersUp[1].sub, "A"); h.eq(f.runnersUp[2].sub, "C")
end)

h.test("View.dailyFarm ignores the filter and raw gold follows includeGold", function()
  local filter = { search = "nothing" }
  local f = V.dailyFarm(farmEntries(), { lookup = zlookup, filter = filter }, 1200)
  h.eq(f.best.sub, "B"); h.eq(f.runnersUp[1].perHour, 400)
  f = V.dailyFarm(farmEntries(), { lookup = zlookup, includeGold = false }, 1200)
  h.eq(f.best.sub, "A")
end)

h.test("View.dailyFarm flags slow selling only with market data", function()
  local lookup = function(id)
    if id == 1 then return { ah = 100, saleRate = 0.01 } end
    return { ah = 50, saleRate = 0.9 }
  end
  local e = zentry({ [1] = 2, [2] = 1 }, { Z = { subs = { A = zsub(3600, { [1] = 2, [2] = 1 }) } } })
  local t = { rateGood = 0.5, rateOk = 0.1 }
  local f = V.dailyFarm({ e }, { lookup = lookup, market = t }, 0)
  h.eq(#f.slow.names, 1); h.eq(f.slow.names[1], "I1")
  h.eq(V.dailyFarm({ e }, { lookup = lookup }, 0).slow, nil)
  local fast = function() return { ah = 100, saleRate = 0.9 } end
  h.eq(V.dailyFarm({ e }, { lookup = fast, market = t }, 0).slow, nil)
  local unpriced = V.dailyFarm({ zentry({ [9] = 1 }, { Z = { subs = { A = zsub(3600, { [9] = 1 }) } } }) },
    { lookup = function() return nil end, market = t }, 0)
  h.eq(unpriced, nil) -- a place worth nothing is never the daily farm
end)

h.test("View.dailyFarm never picks or lists a place that earned nothing", function()
  local e = zentry({ [9] = 3 }, { Z = { subs = { A = zsub(3600, { [9] = 3 }), B = zsub(3600, {}) } } })
  h.eq(V.dailyFarm({ e }, { lookup = zlookup }, 0), nil)
  e.zones.Y = { subs = { C = zsub(3600, {}, 10) } }
  local f = V.dailyFarm({ e }, { lookup = zlookup }, 0)
  h.eq(f.best.sub, "C"); h.eq(#f.runnersUp, 0)
end)

h.test("View.buildZones keeps the opened subzone even when the filter hides its items", function()
  local opts = { lookup = zlookup, sort = "ah", filter = { search = "nothing matches" } }
  local v = V.buildZones(twoZones(), opts, { zone = "Z", sub = "A" })
  local found
  for _, r in ipairs(v.rows) do if r.subKey == "A" then found = r end end
  h.eq(found ~= nil, true)
  h.eq(found.zoneKey, "Z")
  -- not opened: hidden like before (only Y, which has raw gold, stays)
  local rows = V.buildZones(twoZones(), opts, {}).rows
  h.eq(#rows, 1); h.eq(rows[1].zoneKey, "Y")
end)

h.test("View.dailyFarm gives each place the averaged spot of its main map", function()
  local a = zentry({ [1] = 4 }, { Z = { subs = { A = { time = 3600, gold = 0, items = { [1] = 4 },
    pos = { [2022] = { x = 0.8, y = 1.2, n = 2 }, [2023] = { x = 0.5, y = 0.5, n = 1 } } } } } })
  local b = zentry({ [1] = 1 }, { Z = { subs = { A = { time = 600, gold = 0, items = { [1] = 1 },
    pos = { [2022] = { x = 0.4, y = 0.6, n = 1 }, [7] = { x = "bad", y = 1, n = 1 } } } } } })
  local f = V.dailyFarm({ a, b }, { lookup = zlookup }, 0)
  h.eq(f.best.pos.mapID, 2022)
  h.near(f.best.pos.x, 0.4); h.near(f.best.pos.y, 0.6)
  -- equal counts: the lower map ID
  local c = zentry({ [1] = 1 }, { Z = { subs = { A = { time = 600, gold = 0, items = { [1] = 1 },
    pos = { [30] = { x = 0.2, y = 0.2, n = 1 }, [20] = { x = 0.6, y = 0.6, n = 1 } } } } } })
  h.eq(V.dailyFarm({ c }, { lookup = zlookup }, 0).best.pos.mapID, 20)
  local old = V.dailyFarm({ zentry({ [1] = 4 }, { Z = { subs = { A = zsub(3600, { [1] = 4 }) } } }) },
    { lookup = zlookup }, 0)
  h.eq(old.best.pos, nil)
  local broken = zentry({ [1] = 4 }, { Z = { subs = { A = { time = 3600, gold = 0, items = { [1] = 4 }, pos = "x" } } } })
  h.eq(V.dailyFarm({ broken }, { lookup = zlookup }, 0).best.pos, nil)
end)

h.test("View.dailyFarm keeps a spot from corrupt sums on the map (0..1)", function()
  local e = zentry({ [1] = 4 }, { Z = { subs = { A = { time = 3600, gold = 0, items = { [1] = 4 },
    pos = { [2022] = { x = 5, y = -2, n = 1 } } } } } })
  local p = V.dailyFarm({ e }, { lookup = zlookup }, 0).best.pos
  h.eq(p.mapID, 2022); h.eq(p.x, 1); h.eq(p.y, 0)
end)

-- ---------------------------------------------------------------------------
-- Compact view

local function compactSession()
  local s = { items = {}, gold = 500, running = true, runningSince = 0, elapsedBase = 0, recent = {} }
  s.items[1] = { id = 1, key = 1, link = link("Ore"), qty = 6, lastSeen = 5 }
  s.items[3] = { id = 3, key = 3, link = link("Gem"), qty = 1, lastSeen = 6 }
  s.recent = { { key = 1, qty = 2, at = 9 }, { key = 3, qty = 1, at = 8 }, { key = 1, qty = 4, at = 7 },
    { key = 99, qty = 1, at = 6 } }
  return s
end

h.test("View.buildCompact: unfiltered total with raw gold and its rate", function()
  local s = compactSession()
  local opts = { lookup = zlookup, now = 3600, filter = { search = "nothing matches" } }
  local c = V.buildCompact(s, opts)
  h.eq(c.total, 6 * 100 + 1000 + 500)
  h.eq(c.perHour, 2100)
  h.eq(c.running, true)
  opts.includeGold = false
  h.eq(V.buildCompact(s, opts).total, 1600)
end)

h.test("View.buildCompact: each drop worth its own quantity, newest first", function()
  local c = V.buildCompact(compactSession(), { lookup = zlookup, now = 3600 })
  h.eq(#c.drops, 3) -- the gone item 99 is skipped
  h.eq(c.drops[1].quantity, 2); h.eq(c.drops[1].value, 200)
  h.eq(c.drops[2].id, 3); h.eq(c.drops[2].value, 1000)
  h.eq(c.drops[3].quantity, 4); h.eq(c.drops[3].value, 400)
end)

h.test("View.buildCompact: compactDrops limits the list, no rate under a minute", function()
  h.eq(#V.buildCompact(compactSession(), { lookup = zlookup, now = 3600, compactDrops = 1 }).drops, 1)
  h.eq(#V.buildCompact(compactSession(), { lookup = zlookup, now = 3600, compactDrops = 0 }).drops, 0)
  h.eq(V.buildCompact(compactSession(), { lookup = zlookup, now = 30 }).perHour, nil)
  local stopped = compactSession(); stopped.running = false; stopped.runningSince = nil; stopped.elapsedBase = 7200
  local c = V.buildCompact(stopped, { lookup = zlookup, now = 99999 })
  h.eq(c.running, false); h.eq(c.perHour, 1050)
  local empty = V.buildCompact({ items = {}, gold = 0, running = true, runningSince = 0, elapsedBase = 0 },
    { lookup = zlookup, now = 3600 })
  h.eq(empty.total, 0); h.eq(#empty.drops, 0)
end)
