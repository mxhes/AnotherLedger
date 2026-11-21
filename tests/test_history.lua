local h = ...
-- (History.csv / details / snapshot places are tested at the end of this file)
local ns = h.load({ "Util.lua", "Money.lua", "Theme.lua", "Tooltip.lua", "LootParse.lua", "Prices.lua", "Session.lua",
  "Mobs.lua", "History.lua" })
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
  h.eq(e.unpriced, nil)
  h.eq(e.items[1].price, { vendor = 10, ah = 100 }) -- the prices the totals use
  h.eq(e.items[2].price, { vendor = 5 })
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

h.test("History.itemCount: one item, many items", function()
  h.eq(ns.History.itemCount(1), "1 item")
  h.eq(ns.History.itemCount(12), "12 items")
  h.eq(ns.History.itemCount(0), "0 items")
end)

h.test("History.shortDate: today, yesterday, weekday, then the date", function()
  local function utc(f, t) return os.date("!" .. f, t) end
  local now = 20000 * 86400 + 12 * 3600 -- Friday 2024-10-04 12:00 UTC
  local sd = ns.History.shortDate
  h.eq(sd(now - 3600, now, utc), "Today 11:00")
  h.eq(sd(now - 86400, now, utc), "Yesterday 12:00")
  h.eq(sd(now - 3 * 86400, now, utc), "Tue 12:00")
  h.eq(sd(now - 10 * 86400, now, utc), "2024-09-24")
  h.eq(sd(now + 86400 * 3, now, utc), "2024-10-07") -- a clock set back: the date
  h.eq(sd("x", now, utc), "x")
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
  h.eq(e.items["5:9"].price, { vendor = 10, de = 50 })
  h.eq(e.items[1].price, { vendor = 1, ah = 70 })
  h.eq(e.items["5:9"].id, 5)
  h.eq(e.currencies[3008].qty, 4)
  h.eq(e.places, { "Stonevault (Heroic)", "Dornogal" })
  -- currencies alone are worth keeping
  h.eq(ns.History.snapshot({ items = {}, currencies = { [1] = { qty = 1 } }, gold = 0 }, nil, 0) ~= nil, true)
end)

h.test("History.csv: header plus one line per valid session", function()
  local list = {
    { startedAt = 1, elapsed = 3600, gold = 10000, nItems = 2, vendor = 5000, ah = 20000, best = 30000,
      places = { "A, B", "C" }, items = {},
      currencies = { [3] = { id = 3, qty = 2, link = "|Hcurrency:3|h[Valor]|h" }, [1] = { id = 1, qty = 5 } } },
    "junk",
    { startedAt = 2, elapsed = 30, gold = 0, nItems = 0, vendor = 0, ah = 0, items = {} },
  }
  local csv = ns.History.csv(list, function(t) return "day" .. t end)
  local lines = {}
  for line in (csv .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
  h.eq(#lines, 3)
  h.eq(lines[1], ns.History.CSV_HEADER)
  h.eq(lines[2], 'day1,60.0,"A, B; C",2,0.5000,2.0000,3.0000,1.0000,4.0000,Currency 1 x5; Valor x2,')
  h.eq(lines[3], "day2,0.5,,0,0.0000,0.0000,0.0000,0.0000,,,")
end)

h.test("History.csv: the note column and the ignore list", function()
  local e = { startedAt = 1, elapsed = 3600, gold = 0, nItems = 2, vendor = 500, ah = 3000, best = 3000, items = {
    [1] = { id = 1, qty = 2, price = { vendor = 100, ah = 1000 } },
    [2] = { id = 2, qty = 1, price = { vendor = 300, ah = 1000 } },
  } }
  ns.History.setNote(e, 'Herbs, "fast"')
  local csv = ns.History.csv({ e }, tostring, { [1] = "Ore" })
  local line = csv:match("\n(.*)$")
  h.eq(line, '1,60.0,,1,0.0300,0.1000,0.1000,0.0000,0.1000,,"Herbs, ""fast"""')
end)

h.test("History.totals: ignored items leave the saved totals", function()
  local e = { startedAt = 1, elapsed = 60, gold = 0, nItems = 2, vendor = 500, ah = 3000, best = 3000, items = {
    a = { id = 1, qty = 2, price = { vendor = 100, ah = 1000 } },
    b = { id = 2, qty = 1, price = { vendor = 300, ah = 1000, de = 1500 } },
  } }
  h.eq({ ns.History.totals(e) }, { 500, 3000, 3000, 2 })
  h.eq({ ns.History.totals(e, {}) }, { 500, 3000, 3000, 2 })
  h.eq({ ns.History.totals(e, { [2] = true }) }, { 200, 2000, 1500, 1 })
  h.eq({ ns.History.totals(e, { [1] = "x", [2] = "y" }) }, { 0, 0, 0, 0 })
end)

h.test("History.setNote: trimmed, one line, cut by characters, empty removes", function()
  local e = {}
  h.eq(ns.History.setNote(e, "  Wingrest\nherbs  "), "Wingrest herbs")
  h.eq(ns.History.note(e), "Wingrest herbs")
  h.eq(ns.History.setNote(e, "   "), nil)
  h.eq(e.note, nil)
  local long = string.rep("\195\164", ns.History.NOTE_MAX + 5) -- "ä" twice the bytes
  local cut = ns.History.setNote(e, long)
  h.eq(cut, string.rep("\195\164", ns.History.NOTE_MAX))
end)

h.test("History.setLabel: a session's own place name; the real place stays", function()
  local e = { startedAt = 10, elapsed = 600, gold = 0, nItems = 0, vendor = 0, ah = 0, items = {}, places = { "Feralas" } }
  h.eq(ns.History.setLabel(e, "  Woodpaw camp "), "Woodpaw camp")
  h.eq(ns.History.label(e), "Woodpaw camp")
  h.eq(ns.History.place(e), "Feralas")
  h.eq(ns.History.setLabel(e, ""), nil)
  h.eq(ns.History.label(e), nil)
  h.eq(#ns.History.setLabel(e, string.rep("x", 50)), ns.History.LABEL_MAX)
end)

h.test("History.restore, adopt and combine", function()
  local list = { { startedAt = 5 }, { startedAt = 1 } }
  h.eq(ns.History.restore(list, { { startedAt = 3 } }), 1)
  h.eq({ list[1].startedAt, list[2].startedAt, list[3].startedAt }, { 5, 3, 1 })

  local histories = {}
  local own = { { startedAt = 2 }, { startedAt = 1 } }
  local mine = ns.History.adopt(histories, "Me-Realm", own)
  h.eq(histories["Me-Realm"] == mine, true)
  h.eq(#mine, 2)
  -- A second login with the same list adds nothing twice.
  h.eq(ns.History.adopt(histories, "Me-Realm", { { startedAt = 2 }, { startedAt = 3 } }) == mine, true)
  h.eq({ mine[1].startedAt, mine[2].startedAt, mine[3].startedAt }, { 3, 2, 1 })
  h.eq(ns.History.adopt(histories, "Me-Realm", mine) == mine, true)
  h.eq(#mine, 3)

  histories["Alt-Realm"] = { { startedAt = 9 } }
  local all, key = ns.History.combine(histories)
  h.eq(#all, 4)
  h.eq(all[1].startedAt, 9) -- Alt before Me (by name)
  local _, again = ns.History.combine(histories)
  h.eq(again, key)
  table.insert(histories["Alt-Realm"], 1, { startedAt = 10 })
  local _, changed = ns.History.combine(histories)
  h.eq(changed ~= key, true)
end)

h.test("History.details: lines for when, where and the rates", function()
  local e = { startedAt = 1, elapsed = 7200, gold = 20000, nItems = 3, vendor = 0, ah = 40000, places = { "X" }, items = {} }
  local tip = ns.History.details(e, function() return "D" end)
  h.eq(tip.title, "D")
  h.eq(ns.Tooltip.text(tip), "D\n2h 0m, 3 items\nPlaces: X\nVendor: 0c  (0c/h)\nAH: 4g  (2g/h)\nBest: 4g  (2g/h)\nRaw gold: 2g  (1g/h)")
end)

h.test("History.details lists the currencies of a session", function()
  local e = { startedAt = 1, elapsed = 60, gold = 0, nItems = 0, vendor = 0, ah = 0, items = {},
    currencies = { [9] = { id = 9, qty = 3, link = "|Hcurrency:9|h[Kej]|h" } } }
  h.eq(ns.Tooltip.text(ns.History.details(e)):find("Currencies: Kej x3", 1, true) ~= nil, true)
  h.eq(ns.History.currencyText({ currencies = {} }), nil)
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

h.test("History.merge: one session of two, the time between them never counts", function()
  local newer = { startedAt = 5000, elapsed = 600, gold = 300, nItems = 2, vendor = 200, ah = 1000, best = 1100,
    places = { "Deadmines (Normal)" }, note = "run 2",
    items = { [7] = { id = 7, key = 7, qty = 2, lastSeen = 5500, price = { vendor = 50, ah = 400 } },
      [8] = { id = 8, key = 8, qty = 1, lastSeen = 5400, price = { vendor = 100, ah = 200, de = 300 } } },
    currencies = { [3] = { id = 3, qty = 2 } },
    zones = { ["Deadmines (Normal)"] = { subs = { Mast = { time = 600, gold = 300, items = { [7] = 2, [8] = 1 },
      pos = {} } } } } }
  local older = { startedAt = 1000, elapsed = 900, gold = 100, nItems = 1, vendor = 100, ah = 400, best = 400,
    places = { "Deadmines (Normal)", "Westfall" }, note = "run 1",
    items = { [7] = { id = 7, key = 7, qty = 2, lastSeen = 1500, price = { vendor = 50, ah = 200 } } },
    currencies = { [3] = { id = 3, qty = 1 } },
    zones = { ["Deadmines (Normal)"] = { subs = { Mast = { time = 900, gold = 100, items = { [7] = 2 },
      pos = { [36] = { x = 1, y = 1, n = 2 } } } } } } }
  local m = ns.History.merge(newer, older)
  h.eq(ns.History.valid(m), true)
  h.eq({ m.startedAt, m.elapsed, m.gold, m.nItems }, { 1000, 1500, 400, 2 })
  h.eq({ m.vendor, m.ah, m.best }, { 300, 1400, 1500 })
  h.eq(m.items[7].qty, 4)
  h.eq(m.items[7].price, { vendor = 50, ah = 300 }) -- weighted by quantity
  h.eq(m.items[7].lastSeen, 5500)
  h.eq(m.items[8].price, { vendor = 100, ah = 200, de = 300 })
  h.eq(m.currencies[3].qty, 3)
  h.eq(m.places, { "Deadmines (Normal)", "Westfall" })
  local mast = m.zones["Deadmines (Normal)"].subs.Mast
  h.eq({ mast.time, mast.gold, mast.items[7], mast.items[8] }, { 1500, 400, 4, 1 })
  h.eq(mast.pos[36], { x = 1, y = 1, n = 2 })
  h.eq(m.note, "run 1 / run 2")
  -- The inputs stay as they were (undo puts them back).
  h.eq(newer.items[7].qty, 2); h.eq(older.zones["Deadmines (Normal)"].subs.Mast.time, 900)
  h.eq(ns.History.merge(newer, "junk"), nil)
end)

h.test("snapshot / totals: Auction from decides each item's best value", function()
  -- item 1: vendor 10, ah 100 (+900%); item 2: vendor 5 only
  local s = session({ { 1, 3 }, { 2, 4 } }, 0)
  h.eq(H.snapshot(s, lookup, 1000).best, 300 + 20)
  local e = H.snapshot(s, lookup, 1000, 1000) -- AH must beat vendor by 1000%: it doesn't
  h.eq(e.best, 30 + 20)
  -- totals: an ignored item leaves with the value the rule gave it
  local _, _, best = H.totals(e, { [1] = true }, 1000)
  h.eq(best, 20)
end)

h.test("History.isoWeek: ISO 8601 weeks, Monday first", function()
  h.eq(H.isoWeek(2026, 11, 17), 47)
  h.eq(H.isoWeek(2027, 1, 1), 53)
  h.eq(H.isoWeek(2026, 1, 1), 1)
  h.eq(H.isoWeek(2024, 12, 30), 1) -- belongs to 2025's first week
  h.eq(select(2, H.isoWeek(2024, 12, 30)), 2025)
end)

h.test("History.period: today, yesterday, this week's days, then ISO weeks", function()
  local function utc(f, t) return os.date("!" .. f, t) end
  local now = 20774 * 86400 + 12 * 3600 -- Tuesday 2026-11-17 12:00 UTC
  local key, label = H.period(now - 3600, now, utc)
  h.eq({ key, label }, { "d:2026-11-17", "Today" })
  key, label = H.period(now - 86400, now, utc) -- Monday 16th
  h.eq({ key, label }, { "d:2026-11-16", "Yesterday" })
  key, label = H.period(now - 2 * 86400, now, utc) -- Sunday 15th: last week
  h.eq({ key, label }, { "w:2026-46", "Week 46" })
  key, label = H.period(now + 7 * 86400 + 6 * 86400, now, utc) -- Monday 30th (a clock set back)
  h.eq(key, "w:2026-49")
  -- this week, not today or yesterday: the weekday
  local fri = 20777 * 86400 + 12 * 3600 -- Friday 2026-11-20
  key, label = H.period(now, fri, utc)
  h.eq({ key, label }, { "d:2026-11-17", "Tuesday" })
end)

h.test("History.snapshot keeps the mobs, merge adds them up", function()
  local s = session({ { 1, 2 } })
  s.mobs = { ["npc:1"] = { name = "Kobold", kind = "npc", kills = 2, looted = 1, gold = 5,
    items = { [1] = 2 }, places = { Elwynn = 1 } } }
  local e = H.snapshot(s, nil, 200)
  h.eq(e.mobs["npc:1"].kills, 2)
  s.mobs["npc:1"].kills = 9
  h.eq(e.mobs["npc:1"].kills, 2) -- a copy
  local other = H.snapshot(session({ { 1, 1 } }), nil, 200)
  other.startedAt = 50
  other.mobs = { ["npc:1"] = { kind = "npc", kills = 1, looted = 1, gold = 0, items = { [1] = 1 }, places = {} } }
  local m = H.merge(e, other)
  h.eq(m.mobs["npc:1"].kills, 3)
  h.eq(m.mobs["npc:1"].items[1], 3)
  -- entries saved before mobs were kept merge fine
  e.mobs = nil
  h.eq(H.merge(e, other).mobs["npc:1"].kills, 1)
end)

h.test("History.period: a week of another year names its year", function()
  local function utc(f, t) return os.date("!" .. f, t) end
  local now = 20774 * 86400 + 12 * 3600 -- Tuesday 2026-11-17
  local key, label = H.period(now - 365 * 86400, now, utc) -- Monday 2025-11-17
  h.eq({ key, label }, { "w:2025-47", "Week 47, 2025" })
end)

h.test("History.snapshot: keeps the Auction from it was saved with", function()
  local session = { startedAt = 10, elapsedBase = 60, running = false, gold = 0,
    items = { [1] = { id = 1, qty = 1, lastSeen = 1, price = { vendor = 100, ah = 300 } } } }
  local e = ns.History.snapshot(session, nil, 100, 300)
  h.eq(e.ahMinGain, 300)
  h.eq(e.best, 100) -- 300 does not beat 100 by 300%
  e = ns.History.snapshot(session, nil, 100, 0)
  h.eq(e.ahMinGain, 0)
end)

h.test("History.totals: ignored items leave at the session's own Auction from", function()
  local function entry(gain, best)
    return { startedAt = 1, elapsed = 60, gold = 0, nItems = 2, vendor = 110, ah = 1300, best = best,
      ahMinGain = gain, items = {
        a = { id = 1, qty = 1, price = { vendor = 100, ah = 300 } },
        b = { id = 2, qty = 1, price = { vendor = 10, ah = 1000 } },
      } }
  end
  -- saved with +300%: item 1 was worth its vendor 100
  h.eq(select(3, ns.History.totals(entry(300, 1100), { [1] = true })), 1000)
  -- saved before the option (no ahMinGain): plain best, 300
  h.eq(select(3, ns.History.totals(entry(nil, 1300), { [1] = true }, 300)), 1000)
end)

h.test("History.merge: the newer session's Auction from, the best worked out again at it", function()
  -- item 1: vendor 100, AH 120 (20% over vendor)
  local function entry(t, gain, id)
    local best = gain >= 50 and 100 or 120
    return { startedAt = t, elapsed = 60, gold = 0, nItems = 1, vendor = 100, ah = 120, best = best,
      items = { [id] = { id = id, key = id, qty = 1, price = { vendor = 100, ah = 120 } } }, ahMinGain = gain }
  end
  local m = ns.History.merge(entry(1, 50, 1), entry(2, 50, 2))
  h.eq(m.ahMinGain, 50); h.eq(m.best, 200)
  -- older +50% (vendor counts), newer Off (AH counts): both items at Off
  m = ns.History.merge(entry(1, 50, 1), entry(2, 0, 2))
  h.eq(m.ahMinGain, 0); h.eq(m.best, 240)
  h.eq(select(3, ns.History.totals(m, { [1] = true })), 120)
  -- the same item, an AH price in only one session: it counts for that one's quantity only
  local a = { startedAt = 1, elapsed = 60, gold = 0, nItems = 1, vendor = 50, ah = 1000, best = 1000, ahMinGain = 0,
    items = { [7] = { id = 7, key = 7, qty = 10, price = { vendor = 5, ah = 100 } } } }
  local b = { startedAt = 2, elapsed = 60, gold = 0, nItems = 1, vendor = 50, ah = 0, best = 50, ahMinGain = 0,
    items = { [7] = { id = 7, key = 7, qty = 10, price = { vendor = 5 } } } }
  h.eq(ns.History.merge(a, b).best, 1050)
end)

h.test("History: an AH price after the 5% cut is marked per item, also through merges", function()
  local session = { startedAt = 10, elapsedBase = 60, running = false, gold = 0, items = {
    [1] = { id = 1, qty = 1, lastSeen = 1, price = { ah = 95, cut = true } },
    [2] = { id = 2, qty = 1, lastSeen = 1, price = { ah = 100 } },
    [3] = { id = 3, qty = 1, lastSeen = 1 },
  } }
  local e = ns.History.snapshot(session, function(id) if id == 3 then return { ah = 950, ahGross = 1000 } end end, 100)
  h.eq(e.items[1].price.cut, true)
  h.eq(e.items[2].price.cut, nil)
  h.eq(e.items[3].price.cut, true)
  local other = ns.History.snapshot({ startedAt = 20, elapsedBase = 60, running = false, gold = 0, items = {
    [1] = { id = 1, qty = 1, lastSeen = 1, price = { ah = 100 } },
    [3] = { id = 3, qty = 1, lastSeen = 1, price = { ah = 950, cut = true } },
  } }, nil, 100)
  local m = ns.History.merge(e, other)
  h.eq(m.items[1].price.cut, nil) -- one of them was not cut
  h.eq(m.items[3].price.cut, true)
end)

h.test("History.dropMobs drops the mob data of older sessions only", function()
  local list = { { startedAt = 300, mobs = { a = {} } }, { startedAt = 200, mobs = { b = {} } }, { startedAt = 100 } }
  local v = ns.History.version
  h.eq(ns.History.dropMobs(list, 250, true), 1)
  h.eq(list[2].mobs ~= nil, true)
  h.eq(ns.History.version, v)
  h.eq(ns.History.dropMobs(list, 250), 1)
  h.eq(list[2].mobs, nil)
  h.eq(list[1].mobs ~= nil, true)
  h.eq(ns.History.version, v + 1)
  h.eq(ns.History.dropMobs(list, 250), 0)
end)
