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
