local h = ...
local ns = h.load({ "Util.lua", "Money.lua", "DB.lua", "LootParse.lua", "Prices.lua", "Sources/Sources.lua", "Sources/Vendor.lua",
  "Sources/TSM.lua", "Sources/Auctionator.lua", "Session.lua", "View.lua", "Slash.lua", "Demo.lua", "Core.lua" })
local Demo = ns.Demo
local Core = ns.Core

h.test("Core.countsAsLoot: crafted and bought items only with the option", function()
  h.eq(Core.countsAsLoot("loot", false, false), true)
  h.eq(Core.countsAsLoot("loot", false, true), true)
  h.eq(Core.countsAsLoot("pushed", false, false), true)
  h.eq(Core.countsAsLoot("pushed", false, true), false)
  h.eq(Core.countsAsLoot("created", false, false), false)
  h.eq(Core.countsAsLoot("created", true, false), true)
  h.eq(Core.countsAsLoot("pushed", true, true), true)
  h.eq(Core.countsAsLoot(nil, false, true), true)
end)

h.test("Core.subzoneOf uses the subzone, else the zone", function()
  h.eq(Core.subzoneOf({ GetSubZoneText = function() return "Hall" end }, "Zone"), "Hall")
  h.eq(Core.subzoneOf({ GetSubZoneText = function() return "" end }, "Zone"), "Zone")
  h.eq(Core.subzoneOf({}, "Zone"), "Zone")
  h.eq(Core.subzoneOf({ GetSubZoneText = function() error("no") end }, "Zone"), "Zone")
end)

h.test("Core.placeOf: zone outside, instance with difficulty inside", function()
  h.eq({ Core.placeOf({ GetRealZoneText = function() return "Dornogal" end,
    GetInstanceInfo = function() return "Khaz Algar", "none" end }) }, { "Dornogal" })
  h.eq({ Core.placeOf({ GetInstanceInfo = function() return "The Stonevault", "party", 23, "Mythic" end }) },
    { "The Stonevault (Mythic)", "The Stonevault" })
  h.eq({ Core.placeOf({ GetInstanceInfo = function() return "Arena", "arena", 0, "" end }) },
    { "Arena", "Arena" })
  h.eq({ Core.placeOf({ GetInstanceInfo = function() error("x") end }) }, {})
  h.eq({ Core.placeOf({}) }, {})
end)

h.test("Core.placeOf: a missing difficulty name never splits one dungeon into two places", function()
  -- GetDifficultyInfo fills in a missing name
  local env = { GetInstanceInfo = function() return "Razorfen Downs", "party", 1, "" end,
    GetDifficultyInfo = function(id) return id == 1 and "Normal" or nil end }
  h.eq(Core.placeOf(env), "Razorfen Downs (Normal)")
  -- without it, the last name seen in that instance
  local remembered = {}
  local name = "Normal"
  env = { GetInstanceInfo = function() return "Razorfen Downs", "party", 1, name end }
  h.eq(Core.placeOf(env, remembered), "Razorfen Downs (Normal)")
  name = nil
  h.eq(Core.placeOf(env, remembered), "Razorfen Downs (Normal)")
  h.eq(Core.placeOf(env), "Razorfen Downs")
end)

h.test("Core loads without a client and exposes helpers", function()
  h.eq(type(Core.buildPrices), "function")
  h.eq(Core.frame, nil)
end)

h.test("Core.evalKey needs both parts and survives errors", function()
  h.eq(Core.evalKey({}), nil)
  h.eq(Core.evalKey({ GetCurrentRegionName = function() return "EU" end }), nil)
  h.eq(Core.evalKey({
    GetCurrentRegionName = function() return "EU" end,
    C_GameRules = { GetCurrentGameModeRecordID = function() return 7 end },
  }), "EU-7")
  h.eq(Core.evalKey({
    GetCurrentRegionName = function() error("boom") end,
    C_GameRules = { GetCurrentGameModeRecordID = function() return 7 end },
  }), nil)
end)

h.test("Core.buildPrices wires sources, vendor, live TSM source and cache", function()
  local db = ns.DB.applyDefaults(nil, ns.DB.defaults)
  local askedSource
  local env = {
    C_Item = { GetItemInfo = function() return 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 25 end },
    TSM_API = { GetCustomPriceValue = function(src) askedSource = src return 900 end },
  }
  local now = 1000
  local p = Core.buildPrices(env, db, function() return now end, function() return "EU-1" end)
  local r = p:lookup(2589)
  h.eq(r.vendor, 25)
  h.eq(r.ah, 900)
  h.eq(r.ahSource, "TSM")
  h.eq(askedSource, "DBMarket")
  h.eq(db.cache["EU-1"][2589].price, 900)
  db.settings.tsmSource = "DBMinBuyout"
  now = 2000
  p:lookup(2589)
  h.eq(askedSource, "DBMinBuyout")
end)

h.test("Demo.seedCache seeds fresh, stale and missing entries", function()
  local db = { cache = {} }
  Demo.seedCache(db, nil, 100000)
  h.eq(db.cache, {})
  Demo.seedCache(db, "EU-1", 100000)
  local b = db.cache["EU-1"]
  h.eq(b[2589].seenAt, 100000)
  h.eq(b[3356].seenAt, 100000 - 14 * 3600)
  h.eq(b[2318], nil)
end)

h.test("Core.recordLoot adds to the session and flashes", function()
  local flashed
  ns.session = ns.Session.new(0)
  ns.UI = { flash = function(id, lvl) flashed = { id, lvl } end, refresh = function() end }
  ns.prices = { lookup = function() return { vendor = 5 } end }
  _G.time = function() return 10 end
  Core.recordLoot(Demo.makeLink(2589, "Linen Cloth", "ffffff"), 3)
  _G.time = nil
  h.eq(ns.session.items[2589].qty, 3)
  h.eq(flashed, { 2589, "normal" })
  ns.Session.stop(ns.session, 10)
  flashed = nil
  _G.time = function() return 11 end
  Core.recordLoot(Demo.makeLink(2589, "Linen Cloth", "ffffff"), 3)
  _G.time = nil
  h.eq(ns.session.items[2589].qty, 3)
  h.eq(flashed, nil)
end)

local function demoDb()
  return { cache = { ["EU-1"] = { [2589] = { price = 77, seenAt = 5 }, [999] = { price = 1, seenAt = 1 } } } }
end

h.test("Demo.restoreCache returns the cache to its original", function()
  Demo.backup = nil
  local db = demoDb()
  Demo.seedCache(db, "EU-1", 100000)
  h.eq(db.cache["EU-1"][2589].price, 55)
  Demo.restoreCache(db)
  h.eq(db.cache, demoDb().cache)
  h.eq(next(Demo.backup or {}), nil)
  -- bucket that did not exist at all
  local db2 = { cache = {} }
  Demo.seedCache(db2, "EU-2", 100000)
  Demo.restoreCache(db2)
  h.eq(db2.cache, {})
end)

h.test("a second demo seed keeps the original backup", function()
  Demo.backup = nil
  local db = demoDb()
  Demo.seedCache(db, "EU-1", 100000)
  Demo.seedCache(db, "EU-1", 200000)
  Demo.restoreCache(db)
  h.eq(db.cache, demoDb().cache)
end)

h.test("Core.resetSession restores the demo cache", function()
  Demo.backup = nil
  local db = demoDb()
  ns.db = db
  ns.session = ns.Session.new(0)
  ns.UI = { refresh = function() end }
  Demo.seedCache(db, "EU-1", 100000)
  _G.time = function() return 10 end
  Core.resetSession()
  _G.time = nil
  h.eq(db.cache, demoDb().cache)
end)

h.test("Demo.restoreCache keeps a real price written after the demo seed", function()
  Demo.backup = nil
  local db = demoDb()
  Demo.seedCache(db, "EU-1", 100000)
  db.cache["EU-1"][2589] = { price = 777, seenAt = 150000 }
  Demo.restoreCache(db)
  h.eq(db.cache["EU-1"][2589], { price = 777, seenAt = 150000 })
  h.eq(db.cache["EU-1"][2592], nil)
  h.eq(db.cache["EU-1"][999], { price = 1, seenAt = 1 })
end)

h.test("Demo.restoreCache keeps a real price when the original was absent", function()
  Demo.backup = nil
  local db = { cache = {} }
  Demo.seedCache(db, "EU-3", 100000)
  db.cache["EU-3"][2592] = { price = 777, seenAt = 150000 }
  Demo.restoreCache(db)
  h.eq(db.cache, { ["EU-3"] = { [2592] = { price = 777, seenAt = 150000 } } })
end)

h.test("second demo updates the seeded record, original backup stays", function()
  Demo.backup = nil
  local db = demoDb()
  Demo.seedCache(db, "EU-1", 100000)
  Demo.seedCache(db, "EU-1", 200000)
  Demo.restoreCache(db)
  h.eq(db.cache, demoDb().cache)
end)

h.test("Core.evalKey rejects non string/number parts", function()
  h.eq(Core.evalKey({
    GetCurrentRegionName = function() return {} end,
    C_GameRules = { GetCurrentGameModeRecordID = function() return 7 end },
  }), nil)
  h.eq(Core.evalKey({
    GetCurrentRegionName = function() return "EU" end,
    C_GameRules = { GetCurrentGameModeRecordID = function() return true end },
  }), nil)
end)

h.test("Core.keyFromState retries a nil key at most every 10 s", function()
  local calls = 0
  local ready = false
  local env = {
    GetCurrentRegionName = function() calls = calls + 1 return ready and "EU" or nil end,
    C_GameRules = { GetCurrentGameModeRecordID = function() return 7 end },
  }
  local state = {}
  h.eq(Core.keyFromState(state, env, 100), nil)
  h.eq(calls, 1)
  ready = true
  h.eq(Core.keyFromState(state, env, 105), nil) -- throttled
  h.eq(calls, 1)
  h.eq(Core.keyFromState(state, env, 110), "EU-7")
  h.eq(calls, 2)
  h.eq(Core.keyFromState(state, env, 500), "EU-7") -- cached, no re-eval
  h.eq(calls, 2)
end)

h.test("GET_ITEM_INFO_RECEIVED only refreshes for items in the session", function()
  local pending = {}
  _G.C_Timer = { After = function(_, fn) pending[#pending + 1] = fn end }
  local refreshed = 0
  ns.UI = { refresh = function() refreshed = refreshed + 1 end }
  ns.session = ns.Session.new(0)
  ns.Session.add(ns.session, 2589, "l", 1, 0)
  Core.events.GET_ITEM_INFO_RECEIVED(999)
  h.eq(#pending, 0)
  Core.events.GET_ITEM_INFO_RECEIVED(2589)
  h.eq(#pending, 1)
  pending[1]()
  h.eq(refreshed, 1)
  ns.session = nil
  Core.events.GET_ITEM_INFO_RECEIVED(2589)
  h.eq(#pending, 1)
  _G.C_Timer = nil
end)

h.test("recordLoot refreshes once", function()
  local refreshes, flashes = 0, 0
  ns.session = ns.Session.new(0)
  ns.UI = {
    refresh = function() refreshes = refreshes + 1 end,
    flash = function() flashes = flashes + 1 end,
  }
  ns.prices = nil
  _G.time = function() return 10 end
  Core.recordLoot(Demo.makeLink(2589, "Linen Cloth", "ffffff"), 1)
  h.eq({ refreshes, flashes }, { 0, 1 })
  ns.UI.flash = nil
  Core.recordLoot(Demo.makeLink(2589, "Linen Cloth", "ffffff"), 1)
  _G.time = nil
  h.eq({ refreshes, flashes }, { 1, 1 })
end)

h.test("Core.recordGold adds, refreshes once and ignores bad input", function()
  local refreshes = 0
  ns.session = ns.Session.new(0)
  ns.UI = { refresh = function() refreshes = refreshes + 1 end }
  _G.time = function() return 10 end
  Core.recordGold(250)
  Core.recordGold(0)
  Core.recordGold(nil)
  Core.recordGold("5")
  h.eq(ns.session.gold, 250)
  h.eq(refreshes, 1)
  ns.session = nil
  Core.recordGold(5)
  _G.time = nil
  h.eq(refreshes, 1)
end)

h.test("Sources.allowed / gate follow the price source option", function()
  local S = ns.Sources
  h.eq(S.allowed("auto", "tsm"), true)
  h.eq(S.allowed("auto", "auctionator"), true)
  h.eq(S.allowed("tsm", "tsm"), true)
  h.eq(S.allowed("tsm", "auctionator"), false)
  h.eq(S.allowed("auctionator", "tsm"), false)
  h.eq(S.allowed(nil, "tsm"), true) -- unknown value behaves like auto
  h.eq(S.allowed("zzz", "tsm"), true)
  local selected = "tsm"
  local src = S.gate({ name = "TSM", get = function() return 99 end }, "tsm", function() return selected end)
  h.eq(src.name, "TSM")
  h.eq(src.get(1), 99)
  selected = "auctionator"
  h.eq(src.get(1), nil)
  h.eq(S.gate({ name = "x", get = function() return 1 end }, "tsm", function() error("boom") end).get(1), nil)
end)

h.test("Core.buildPrices asks the sources in order and takes the disenchant value from TSM", function()
  local db = ns.DB.applyDefaults(nil, ns.DB.defaults)
  local env = {
    TSM_API = { GetCustomPriceValue = function(src) return src == "Destroy" and 40 or nil end },
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return 222 end } } },
  }
  local p = Core.buildPrices(env, db, function() return 1000 end, function() return "EU-1" end)
  local r = p:lookup(5)
  h.eq(r.ah, 222) -- TSM has no price, Auctionator answers
  h.eq(r.ahSource, "Auctionator")
  h.eq(r.de, 40)
  db.settings.priceSource = "auctionator"
  h.eq(p:lookup(5).de, nil) -- the disenchant value is TSM's: silent with TSM off
end)

h.test("Core.lookupPrice never errors", function()
  ns.prices = nil
  h.eq(Core.lookupPrice(1), nil)
  ns.prices = { lookup = function() error("boom") end }
  h.eq(Core.lookupPrice(1), nil)
  ns.prices = { lookup = function(_, id) return { vendor = id } end }
  h.eq(Core.lookupPrice(7).vendor, 7)
  ns.prices = nil
end)

h.test("Core.alertWorthy: drop value against the gold threshold", function()
  h.eq(Core.alertWorthy(50000, 2, 10), true)  -- 10 g exactly
  h.eq(Core.alertWorthy(49999, 2, 10), false)
  h.eq(Core.alertWorthy(10 ^ 9, 1, 0), false)  -- 0 = off
  h.eq(Core.alertWorthy(10 ^ 9, 1, -1), false) -- unlimited = off
  h.eq(Core.alertWorthy(nil, 1, 10), false)
  h.eq(Core.alertWorthy(100, nil, 10), false)
end)

h.test("Core.buildPrices adds TSM sale info, also with Auctionator as the price source", function()
  local db = ns.DB.applyDefaults(nil, ns.DB.defaults)
  local env = {
    TSM_API = { GetCustomPriceValue = function(src)
      if src:find("SaleRate", 1, true) then return 80 end
      if src:find("SoldPerDay", 1, true) then return 1200 end
      return nil
    end },
  }
  db.settings.priceSource = "auctionator"
  local p = Core.buildPrices(env, db, function() return 1000 end, function() return "EU-1" end)
  local r = p:lookup(5)
  h.near(r.saleRate, 0.08)
  h.near(r.soldPerDay, 12)
end)

h.test("Core.positionOf reads the player's map position", function()
  local pos = { GetXY = function() return 0.452, 0.618 end }
  local env = { C_Map = { GetBestMapForUnit = function(u) h.eq(u, "player"); return 2022 end,
    GetPlayerMapPosition = function(m, u) h.eq(m, 2022); h.eq(u, "player"); return pos end } }
  local m, x, y = Core.positionOf(env)
  h.eq(m, 2022); h.near(x, 0.452); h.near(y, 0.618)
end)

h.test("Core.positionOf gives nil without a usable position", function()
  h.eq(Core.positionOf({}), nil)
  h.eq(Core.positionOf({ C_Map = { GetBestMapForUnit = function() return nil end } }), nil)
  local function env(px, py)
    return { C_Map = { GetBestMapForUnit = function() return 1 end,
      GetPlayerMapPosition = function() return { GetXY = function() return px, py end } end } }
  end
  h.eq(Core.positionOf(env(0, 0)), nil)
  h.eq(Core.positionOf(env(1.5, 0.2)), nil)
  h.eq(Core.positionOf(env(nil, nil)), nil)
  h.eq(Core.positionOf({ C_Map = { GetBestMapForUnit = function() return 1 end,
    GetPlayerMapPosition = function() return nil end } }), nil)
  h.eq(Core.positionOf({ C_Map = { GetBestMapForUnit = function() error("x") end } }), nil)
end)

h.test("Core.positionOf gives nil inside any instance, also scenarios and delves", function()
  local function env(instanceType)
    return { GetInstanceInfo = function() return "Somewhere", instanceType, 1, "Normal" end,
      C_Map = { GetBestMapForUnit = function() return 1 end,
        GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end } }
  end
  h.eq(Core.positionOf(env("scenario")), nil)
  h.eq(Core.positionOf(env("party")), nil)
  h.eq(Core.positionOf(env("none")), 1)
  h.eq(Core.positionOf(env(nil)), 1)
end)

h.test("Core.goalsReached: each goal once per goal value; 0 is off", function()
  local r = Core.goalsReached(10000, 59, 1, 1, {})
  h.eq(r, { gold = true, time = false })
  h.eq(Core.goalsReached(10000, 60, 1, 1, { gold = 1 }), { gold = false, time = true })
  h.eq(Core.goalsReached(10000, 60, 1, 1, { gold = 1, time = 1 }), { gold = false, time = false })
  h.eq(Core.goalsReached(20000, 60, 2, 1, { gold = 1, time = 1 }).gold, true) -- a new goal counts anew
  h.eq(Core.goalsReached(nil, 600, 1, 0, {}), { gold = false, time = false })
  h.eq(Core.goalsReached(99999, 600, -1, -1, {}), { gold = false, time = false })
end)

h.test("Core.characterKey: Name-Realm, the name alone, or nil", function()
  h.eq(Core.characterKey({ UnitName = function() return "Me" end, GetRealmName = function() return "Realm" end }), "Me-Realm")
  h.eq(Core.characterKey({ UnitName = function() return "Me" end }), "Me")
  h.eq(Core.characterKey({}), nil)
  h.eq(Core.characterKey({ UnitName = function() return "" end }), nil)
end)

h.test("Core.zoneSwitch: a new zone counts after the grace time, flights and detours never", function()
  local st = {}
  h.eq(Core.zoneSwitch(st, "Dornogal", 0, false, 120), false)
  h.eq(st.zone, "Dornogal")
  h.eq(Core.zoneSwitch(st, nil, 10, false, 120), false) -- no zone known: nothing changes
  h.eq(Core.zoneSwitch(st, "Isle of Dorn", 100, false, 120), false)
  h.eq(Core.zoneSwitch(st, "Isle of Dorn", 219, false, 120), false)
  h.eq(Core.zoneSwitch(st, "Dornogal", 230, false, 120), false) -- back in time: a detour
  h.eq(Core.zoneSwitch(st, "Isle of Dorn", 400, false, 120), false)
  h.eq(Core.zoneSwitch(st, "Isle of Dorn", 600, true, 120), false) -- on a flight the wait starts over
  h.eq(Core.zoneSwitch(st, "Isle of Dorn", 610, false, 120), false)
  h.eq(Core.zoneSwitch(st, "Isle of Dorn", 730, false, 120), true)
  h.eq(st.zone, "Isle of Dorn")
  h.eq(Core.zoneSwitch(st, "Isle of Dorn", 900, false, 120), false)
end)
