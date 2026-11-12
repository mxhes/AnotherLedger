local h = ...
local ns = h.load({ "Prices.lua", "Session.lua", "View.lua" })
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
