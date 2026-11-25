local h = ...
local ns = h.load({ "Util.lua", "Money.lua", "DB.lua", "LootParse.lua", "Prices.lua", "Sources/Sources.lua", "Sources/Vendor.lua",
  "Sources/TSM.lua", "Sources/Auctionator.lua", "Session.lua", "View.lua", "ViewZones.lua", "ViewTrade.lua", "Slash.lua", "Demo.lua", "Core.lua", "CorePrices.lua", "CoreLists.lua", "CoreHistory.lua" })
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
    { "Arena" }) -- a place, but no instance key: only dungeons and raids split
  h.eq({ Core.placeOf({ GetInstanceInfo = function() return "Molten Core", "raid", 9, "40 Player" end }) },
    { "Molten Core (40 Player)", "Molten Core" })
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
  -- a client without the calls uses a fixed part instead of waiting for good
  h.eq(Core.evalKey({}), "any-any")
  h.eq(Core.evalKey({ GetCurrentRegionName = function() return "EU" end }), "EU-any")
  -- a call that answers nothing yet: not known yet (asked again later)
  h.eq(Core.evalKey({
    GetCurrentRegionName = function() return "EU" end,
    C_GameRules = { GetCurrentGameModeRecordID = function() return nil end },
  }), nil)
  h.eq(Core.evalKey({
    GetCurrentRegionName = function() return "EU" end,
    C_GameRules = { GetCurrentGameModeRecordID = function() return 7 end },
  }), "EU-7")
  h.eq(Core.evalKey({
    GetCurrentRegionName = function() error("boom") end,
    C_GameRules = { GetCurrentGameModeRecordID = function() return 7 end },
  }), nil)
end)

h.test("Core.priceAddonHint: once without TSM or Auctionator, again after one went", function()
  local said = {}
  local say = function(msg) said[#said + 1] = msg end
  local db = {}
  h.eq(Core.priceAddonHint({}, db, say), true)
  h.eq(#said, 1)
  h.eq(said[1]:find("TSM or Auctionator", 1, true) ~= nil, true)
  h.eq(Core.priceAddonHint({}, db, say), false) -- only once
  -- either addon loaded: no line, and the mark is cleared
  h.eq(Core.priceAddonHint({ TSM_API = {} }, db, say), false)
  h.eq(db.priceHintShown, nil)
  h.eq(Core.priceAddonHint({ Auctionator = { API = {} } }, db, say), false)
  h.eq(#said, 1)
  h.eq(Core.priceAddonHint({}, db, say), true)
end)

h.test("Core.buildPrices wires sources, vendor, live TSM source and cache", function()
  local db = ns.DB.applyDefaults(nil, ns.DB.defaults)
  db.settings.ahCut = false -- raw AH prices here (the cut has its own test)
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
  db.settings.ahCut = false
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
  -- The disenchant value is TSM's and stays with the AH source on Auctionator
  -- (only the option Destroy values turns it off).
  h.eq(p:lookup(5).de, 40)
  h.eq(p:lookup(5).ah, 222)
end)

h.test("Core.buildPrices: the disenchant value falls back to Auctionator without TSM", function()
  local db = ns.DB.applyDefaults(nil, ns.DB.defaults)
  local env = {
    Auctionator = { API = { v1 = {
      GetAuctionPriceByItemID = function() return 222 end,
      GetAuctionAgeByItemID = function() return 3 end,
      GetDisenchantPriceByItemLink = function() return 55 end,
    } } },
  }
  local p = Core.buildPrices(env, db, function() return 1000000 end, function() return "EU-1" end)
  local r = p:lookup(5, "|Hitem:5|h")
  h.eq(r.de, 55)
  h.eq(r.ahSource, "Auctionator")
  h.eq(r.ahAge, 3 * 86400)
  h.eq(r.ahAged, true)
  env.TSM_API = { GetCustomPriceValue = function(src) return src == "Destroy" and 40 or nil end }
  h.eq(p:lookup(5, "|Hitem:5|h").de, 40) -- TSM first
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
  -- resting in a city (passed like a flight) never becomes the session's zone
  st = {}
  h.eq(Core.zoneSwitch(st, "Badlands", 0, false, 120), false)
  h.eq(Core.zoneSwitch(st, "Orgrimmar", 10, true, 120), false)
  h.eq(Core.zoneSwitch(st, "Orgrimmar", 900, true, 120), false)
  h.eq(st.zone, "Badlands")
  h.eq(Core.zoneSwitch(st, "Badlands", 950, false, 120), false) -- back: same session
end)

h.test("Core.professions reads the destroy professions of the character", function()
  local env = {
    GetProfessions = function() return 1, 2 end,
    GetProfessionInfo = function(i)
      if i == 1 then return "Enchanting", 0, 100, 150, 0, 0, 333 end
      return "Herbalism", 0, 100, 150, 0, 0, 182
    end,
  }
  local set = Core.professions(env)
  h.eq(set.enchanting, true)
  h.eq(set.inscription, nil)
  h.eq(next(Core.professions({})), nil)
end)

h.test("Core.isShort: under the minimum minutes, 0 = off", function()
  local s = ns.Session.new(1000)
  h.eq(Core.isShort(s, 1022, 2), true)
  h.eq(Core.isShort(s, 1120, 2), false)
  h.eq(Core.isShort(s, 1022, 0), false)
  -- a saved session: only its elapsedBase counts (no `now`)
  h.eq(Core.isShort({ elapsedBase = 60, running = true, runningSince = 5 }, nil, 2), true)
  h.eq(Core.isShort({ elapsedBase = 1800, running = false }, nil, 2), false)
end)

h.test("Core.levelFits: the map's level range against the player level", function()
  local env = { C_Map = { GetMapLevels = function(mapID) if mapID == 7 then return 35, 45 end end } }
  h.eq(Core.levelFits(env, 7, 42), true)
  h.eq(Core.levelFits(env, 7, 50), false)
  h.eq(Core.levelFits(env, 8, 42), nil) -- no range for that map
  h.eq(Core.levelFits({}, 7, 42), nil)
  h.eq(Core.levelFits(env, 7, nil), nil)
end)

h.test("Core.watchMatch: by item ID or a text the name contains, case ignored", function()
  h.eq(Core.watchMatch(5, "Copper Ore", { [5] = "Copper Ore" }, {}), true)
  h.eq(Core.watchMatch(6, "Pattern: Mooncloth", {}, { ["pattern:"] = "Pattern:" }), true)
  h.eq(Core.watchMatch(6, "Linen Cloth", { [5] = true }, { ["pattern:"] = "Pattern:" }), false)
  h.eq(Core.watchMatch(nil, nil, nil, nil), false)
end)

h.test("Core.transportMoved: carried faster than the own speed, not falling or teleporting", function()
  local function at(x, y, t, map) return { x = x, y = y, t = t, map = map or 0 } end
  h.eq(Core.transportMoved(at(0, 0, 0), at(60, 0, 5), 0, false), true) -- 12 yd/s standing on a boat
  h.eq(Core.transportMoved(at(0, 0, 0), at(30, 40, 5), 7, false), true) -- 10 yd/s, walking 7: 3 more
  h.eq(Core.transportMoved(at(0, 0, 0), at(35, 0, 5), 7, false), false) -- own running
  h.eq(Core.transportMoved(at(0, 0, 0), at(60, 0, 5), 0, true), false) -- falling
  h.eq(Core.transportMoved(at(0, 0, 0), at(1000, 0, 5), 0, false), false) -- teleport
  h.eq(Core.transportMoved(at(0, 0, 0), at(60, 0, 5, 1), 0, false), false) -- another map
  h.eq(Core.transportMoved(false, at(60, 0, 5), 0, false), false)
  h.eq(Core.transportMoved(at(0, 0, 5), at(60, 0, 5), 0, false), false) -- no time passed
end)
