local h = ...
local ns = h.load({ "Money.lua", "DB.lua", "LootParse.lua", "Prices.lua", "Sources/Vendor.lua",
  "Sources/TSM.lua", "Sources/Auctionator.lua", "Session.lua", "View.lua", "Core.lua" })
local Core = ns.Core

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

h.test("Core.seedDemoCache seeds fresh, stale and missing entries", function()
  local db = { cache = {} }
  Core.seedDemoCache(db, nil, 100000)
  h.eq(db.cache, {})
  Core.seedDemoCache(db, "EU-1", 100000)
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
  Core.recordLoot(Core.makeLink(2589, "Linen Cloth", "ffffff"), 3)
  _G.time = nil
  h.eq(ns.session.items[2589].qty, 3)
  h.eq(flashed, { 2589, "normal" })
  ns.Session.stop(ns.session, 10)
  flashed = nil
  _G.time = function() return 11 end
  Core.recordLoot(Core.makeLink(2589, "Linen Cloth", "ffffff"), 3)
  _G.time = nil
  h.eq(ns.session.items[2589].qty, 3)
  h.eq(flashed, nil)
end)

local function demoDb()
  return { cache = { ["EU-1"] = { [2589] = { price = 77, seenAt = 5 }, [999] = { price = 1, seenAt = 1 } } } }
end

h.test("Core.restoreDemoCache returns the cache to its original", function()
  Core.demoBackup = nil
  local db = demoDb()
  Core.seedDemoCache(db, "EU-1", 100000)
  h.eq(db.cache["EU-1"][2589].price, 55)
  Core.restoreDemoCache(db)
  h.eq(db.cache, demoDb().cache)
  h.eq(next(Core.demoBackup or {}), nil)
  -- bucket that did not exist at all
  local db2 = { cache = {} }
  Core.seedDemoCache(db2, "EU-2", 100000)
  Core.restoreDemoCache(db2)
  h.eq(db2.cache, {})
end)

h.test("a second demo seed keeps the original backup", function()
  Core.demoBackup = nil
  local db = demoDb()
  Core.seedDemoCache(db, "EU-1", 100000)
  Core.seedDemoCache(db, "EU-1", 200000)
  Core.restoreDemoCache(db)
  h.eq(db.cache, demoDb().cache)
end)

h.test("Core.resetSession restores the demo cache", function()
  Core.demoBackup = nil
  local db = demoDb()
  ns.db = db
  ns.session = ns.Session.new(0)
  ns.UI = { refresh = function() end }
  Core.seedDemoCache(db, "EU-1", 100000)
  _G.time = function() return 10 end
  Core.resetSession()
  _G.time = nil
  h.eq(db.cache, demoDb().cache)
end)

h.test("restoreDemoCache keeps a real price written after the demo seed", function()
  Core.demoBackup = nil
  local db = demoDb()
  Core.seedDemoCache(db, "EU-1", 100000)
  db.cache["EU-1"][2589] = { price = 777, seenAt = 150000 }
  Core.restoreDemoCache(db)
  h.eq(db.cache["EU-1"][2589], { price = 777, seenAt = 150000 })
  h.eq(db.cache["EU-1"][2592], nil)
  h.eq(db.cache["EU-1"][999], { price = 1, seenAt = 1 })
end)

h.test("restoreDemoCache keeps a real price when the original was absent", function()
  Core.demoBackup = nil
  local db = { cache = {} }
  Core.seedDemoCache(db, "EU-3", 100000)
  db.cache["EU-3"][2592] = { price = 777, seenAt = 150000 }
  Core.restoreDemoCache(db)
  h.eq(db.cache, { ["EU-3"] = { [2592] = { price = 777, seenAt = 150000 } } })
end)

h.test("second demo updates the seeded record, original backup stays", function()
  Core.demoBackup = nil
  local db = demoDb()
  Core.seedDemoCache(db, "EU-1", 100000)
  Core.seedDemoCache(db, "EU-1", 200000)
  Core.restoreDemoCache(db)
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
  Core.recordLoot(Core.makeLink(2589, "Linen Cloth", "ffffff"), 1)
  h.eq({ refreshes, flashes }, { 0, 1 })
  ns.UI.flash = nil
  Core.recordLoot(Core.makeLink(2589, "Linen Cloth", "ffffff"), 1)
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
