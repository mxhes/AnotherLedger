local h = ...
local ns = h.load({ "Money.lua", "Session.lua", "History.lua" })
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
