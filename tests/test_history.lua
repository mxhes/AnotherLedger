local h = ...
-- (History.csv / details / snapshot places are tested at the end of this file)
local ns = h.load({ "Util.lua", "Money.lua", "Session.lua", "History.lua" })
local H = ns.History

local function session(items, gold)
  local s = { startedAt = 100, running = false, elapsedBase = 3600, items = {}, gold = gold or 0 }
  for _, it in ipairs(items) do
    s.items[it[1]] = { id = it[1], link = "[" .. it[1] .. "]", qty = it[2], lastSeen = 150 }
  end
  return s
end
local prices = { [1] = { vendor = 10, ah = 100 }, [2] = { vendor = 5 } }
local function lookup(id) return prices[id] end

h.test("History.snapshot totals items at archive-time prices", function()
  local e = H.snapshot(session({ { 1, 3 }, { 2, 4 } }, 500), lookup, 1000)
  h.eq(e.vendor, 10 * 3 + 5 * 4)
  h.eq(e.ah, 300)
  h.eq(e.unpriced, 1)
  h.eq(e.gold, 500); h.eq(e.nItems, 2); h.eq(e.startedAt, 100); h.eq(e.elapsed, 3600)
  h.eq(e.items[1].qty, 3)
  h.eq(H.valid(e), true)
end)

h.test("History.snapshot skips empty sessions and bad input", function()
  h.eq(H.snapshot(session({}, 0), lookup, 1), nil)
  h.eq(H.snapshot(nil, lookup, 1), nil)
  h.eq(H.snapshot({ items = "x" }, lookup, 1), nil)
  h.eq(H.snapshot(session({}, 250), lookup, 1).gold, 250) -- gold only is kept
  h.eq(H.snapshot(session({ { 1, 1 } }), nil, 1).ah, 0) -- no lookup
end)

h.test("History.snapshot counts a running clock up to now", function()
  local s = session({ { 1, 1 } })
  s.running, s.runningSince, s.elapsedBase = true, 1000, 60
  h.eq(H.snapshot(s, lookup, 1100).elapsed, 160)
end)

h.test("History.add puts the newest first and honors the limit", function()
  local list = {}
  for i = 1, 5 do H.add(list, { n = i }, 3) end
  h.eq(#list, 3)
  h.eq(list[1].n, 5); h.eq(list[3].n, 3)
  h.eq(H.add(list, { n = 6 }, 0), false) -- 0 keeps nothing
  h.eq(#list, 3)
  for i = 1, 10 do H.add(list, { n = i }, -1) end -- unlimited
  h.eq(#list, 13)
end)

h.test("History.prune drops the oldest, never when unlimited", function()
  local list = { { n = 3 }, { n = 2 }, { n = 1 } }
  H.prune(list, -1); h.eq(#list, 3)
  H.prune(list, 2); h.eq(#list, 2); h.eq(list[2].n, 2)
  H.prune(list, 0); h.eq(#list, 0)
  H.prune(nil, 1) -- no error
end)

h.test("History.valid rejects malformed entries", function()
  h.eq(H.valid(nil), false)
  h.eq(H.valid({}), false)
  h.eq(H.valid({ startedAt = 1, elapsed = 1, gold = 1, nItems = 1, vendor = 1, ah = 1, items = "x" }), false)
end)

h.test("History.duration", function()
  h.eq(H.duration(45), "45s"); h.eq(H.duration(125), "2m")
  h.eq(H.duration(4320), "1h 12m"); h.eq(H.duration(-3), "0s"); h.eq(H.duration(nil), "0s")
end)

h.test("History.snapshot: best value, loot-time fallback, places, currencies", function()
  local session = { startedAt = 10, elapsedBase = 3600, running = false, gold = 500,
    items = {
      [1] = { id = 1, qty = 2, lastSeen = 1, price = { ah = 70, vendor = 1 } },
      ["5:9"] = { id = 5, key = "5:9", qty = 1, lastSeen = 1 },
    },
    currencies = { [3008] = { id = 3008, qty = 4 } },
    places = { Dornogal = 1, ["Stonevault (Heroic)"] = 3 } }
  local e = ns.History.snapshot(session, function(id) if id == 5 then return { vendor = 10, de = 50 } end end, 100)
  h.eq(e.ah, 140) -- item 1 from its loot-time price
  h.eq(e.vendor, 12)
  h.eq(e.best, 190)
  h.eq(e.unpriced, 1)
  h.eq(e.items["5:9"].id, 5)
  h.eq(e.currencies[3008].qty, 4)
  h.eq(e.places, { "Stonevault (Heroic)", "Dornogal" })
  -- currencies alone are worth keeping
  h.eq(ns.History.snapshot({ items = {}, currencies = { [1] = { qty = 1 } }, gold = 0 }, nil, 0) ~= nil, true)
end)

h.test("History.csv: header plus one line per valid session", function()
  local list = {
    { startedAt = 1, elapsed = 3600, gold = 10000, nItems = 2, vendor = 5000, ah = 20000, best = 30000,
      places = { "A, B", "C" }, items = {} },
    "junk",
    { startedAt = 2, elapsed = 30, gold = 0, nItems = 0, vendor = 0, ah = 0, items = {} },
  }
  local csv = ns.History.csv(list, function(t) return "day" .. t end)
  local lines = {}
  for line in (csv .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
  h.eq(#lines, 3)
  h.eq(lines[1], ns.History.CSV_HEADER)
  h.eq(lines[2], 'day1,60.0,"A, B; C",2,0.5000,2.0000,3.0000,1.0000,4.0000')
  h.eq(lines[3], "day2,0.5,,0,0.0000,0.0000,0.0000,0.0000,")
end)

h.test("History.details: lines for when, where and the rates", function()
  local e = { startedAt = 1, elapsed = 7200, gold = 20000, nItems = 3, vendor = 0, ah = 40000, places = { "X" }, items = {} }
  local text = ns.History.details(e, function() return "D" end)
  h.eq(text, "D  (2h 0m, 3 items)\nPlaces: X\nVendor: 0c  (0c/h)\nAH: 4g  (2g/h)\nBest: 4g  (2g/h)\nRaw gold: 2g  (1g/h)")
end)

h.test("History.snapshot keeps the time and loot per place", function()
  local s = session({ { 1, 3 } })
  s.zones = { Z = { subs = { A = { time = 10, gold = 5, items = { [1] = 3 } } } } }
  s.running, s.runningSince = true, 1000
  s.at = { zone = "Z", sub = "A", since = 1000 }
  local e = H.snapshot(s, lookup, 1100)
  h.eq(e.zones.Z.subs.A.time, 110)
  h.eq(e.zones.Z.subs.A.items[1], 3)
  h.eq(e.zones.Z.subs.A.gold, 5)
end)
