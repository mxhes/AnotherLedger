local h = ...
local ns = h.load({ "Util.lua", "LootParse.lua", "Scan.lua" })
local S = ns.Scan

-- ---------------------------------------------------------------------------
-- Listing math

h.test("Scan market is the cheapest 15% of units", function()
  -- 20 units: the cheapest 3 units are 100, 100, 200 -> 133
  local m, l = S.listingValues({ { unit = 900, qty = 10 }, { unit = 100, qty = 2 }, { unit = 200, qty = 8 } })
  h.eq(m, 133); h.eq(l, 100)
end)

h.test("Scan market takes at least one unit", function()
  h.eq({ S.listingValues({ { unit = 700, qty = 1 }, { unit = 500, qty = 1 } }) }, { 500, 500 })
end)

h.test("Scan market counts units, not auctions", function()
  local list = { { unit = 1, qty = 200 } }
  for i = 1, 10 do list[#list + 1] = { unit = 500000, qty = 1 } end
  h.eq(S.listingValues(list), 1)
end)

h.test("Scan listing values of nothing", function()
  h.eq({ S.listingValues({}) }, {})
  h.eq({ S.listingValues(nil) }, {})
end)

-- ---------------------------------------------------------------------------
-- Daily average and packed storage

local D = 86400

h.test("Scan pack round trip", function()
  local e = { t = 5 * D + 7, m = 123456, l = 99, am = 120000, al = 90, ad = 4, aw = 1.5 }
  h.eq(S.unpack(S.pack(e)), e)
  h.eq(S.unpack(S.pack({ t = 1, m = 2, l = 3 })), { t = 1, m = 2, l = 3 })
  h.eq(S.unpack("zz,!"), nil)
  h.eq(S.unpack(nil), nil)
end)

h.test("Scan same day replaces today's value", function()
  local items = {}
  S.record(items, 5, 1000, 900, 10 * D)
  S.record(items, 5, 2000, 1800, 10 * D + 3600)
  h.eq({ S.price(items, 5, "market", 10 * D + 3600) }, { 2000, 0 })
  h.eq({ S.price(items, 5, "lowest", 10 * D + 7200) }, { 1800, 3600 })
end)

h.test("Scan a later scan without the item keeps its value", function()
  local items = {}
  S.record(items, 5, 1000, 900, 10 * D)
  S.record(items, 6, 50, 40, 10 * D + 600)
  h.eq(S.price(items, 5, "lowest", 10 * D + 600), 900)
end)

h.test("Scan next day weighs the old average", function()
  local items = {}
  S.record(items, 5, 1000, 1000, 10 * D)
  S.record(items, 5, 2000, 2000, 11 * D)
  local w = 0.5 ^ (1 / 5)
  h.eq(S.price(items, 5, "market", 11 * D), math.floor((1000 * w + 2000) / (w + 1)))
end)

h.test("Scan long gap lets today dominate", function()
  local items = {}
  S.record(items, 5, 1000, 1000, 10 * D)
  S.record(items, 5, 2000, 2000, 20 * D)
  h.eq(S.price(items, 5, "market", 20 * D), 1800)
end)

h.test("Scan third day folds into the running average", function()
  local items = {}
  S.record(items, 5, 1000, 1000, 10 * D)
  S.record(items, 5, 2000, 2000, 15 * D) -- average of day 10 alone: 1000, weight 1
  S.record(items, 5, 3000, 3000, 20 * D) -- day 15 folds in: weight 1.5, (500 + 2000) / 1.5
  local am, aw = (1000 * 0.5 + 2000) / 1.5, 1.5
  h.eq(S.price(items, 5, "market", 20 * D), math.floor((am * aw * 0.5 + 3000) / (aw * 0.5 + 1)))
end)

h.test("Scan one odd first day is diluted like any other day", function()
  local items = {}
  S.record(items, 5, 1000000, 1000000, 1 * D) -- a spike on the first day
  for d = 2, 6 do S.record(items, 5, 200000, 200000, d * D) end
  local p = S.price(items, 5, "market", 6 * D)
  h.eq(p < 350000, true, "price " .. tostring(p))
end)

h.test("Scan old values are not answered and pruned", function()
  local items = {}
  S.record(items, 5, 1000, 900, 0)
  S.record(items, 6, 1000, 900, 14 * D)
  items[7] = "garbage!"
  h.eq(S.price(items, 5, "market", 14 * D + 1), nil)
  h.eq(S.prune(items, 14 * D + 1), 2)
  h.eq(items[5], nil); h.eq(items[7], nil); h.eq(type(items[6]), "string")
end)

h.test("Scan lookup takes the variant, then the plain item", function()
  local items = {}
  S.record(items, "50:1477:4802", 7000, 7000, 0)
  S.record(items, 50, 5000, 5000, 0)
  local link = "|Hitem:50::::::::60::::2:4802:1477::::::|h[Sword]|h"
  h.eq(S.lookup(items, 50, link, "market", 0), 7000)
  h.eq(S.lookup(items, 50, nil, "market", 0), 5000)
  h.eq(S.lookup(items, 51, nil, "market", 0), nil)
  h.eq(S.lookup(nil, 50, nil, "market", 0), nil)
end)

-- ---------------------------------------------------------------------------
-- Price source

local function sourceNs()
  return h.load({ "Util.lua", "LootParse.lua", "Scan.lua", "Sources/Sources.lua", "Sources/Vendor.lua",
    "Sources/TSM.lua", "Sources/Auctionator.lua", "Sources/Scan.lua" })
end

h.test("Scan source answers with the chosen kind and its age", function()
  local sn = sourceNs()
  sn.db = { scan = {} }
  sn.Scan.currentRealmKey = function() return "EU-7-Realm" end
  local b = sn.Scan.bucket(sn.db, "EU-7-Realm", true)
  sn.Scan.record(b.items, 5, 1000, 800, 100)
  local kind = "lowest"
  local spec
  for _, s in ipairs(sn.Sources.list()) do if s.key == "scan" then spec = s end end
  local src = spec.create({ time = function() return 400 end }, function(k) if k == "scanPrice" then return kind end end)
  h.eq(src.name, "AnotherLedger scan")
  h.eq({ src.get(5) }, { 800, 300 })
  kind = "market"
  h.eq(src.get(5), 1000)
  h.eq(src.get(6), nil)
  sn.Scan.currentRealmKey = function() return nil end
  h.eq(src.get(5), nil)
end)

h.test("Scan source is asked after Auctionator", function()
  local sn = sourceNs()
  local keys = {}
  for _, s in ipairs(sn.Sources.list()) do keys[#keys + 1] = s.key end
  h.eq(keys, { "tsm", "auctionator", "scan" })
  h.eq(sn.Sources.choices()[1].label, "Auto (TSM, then Auctionator, then AnotherLedger scan)")
end)

h.test("Scan realm key and bucket", function()
  h.eq(S.realmKey("EU-7", "Realm"), "EU-7-Realm")
  h.eq(S.realmKey(nil, "Realm"), nil); h.eq(S.realmKey("EU-7", nil), nil)
  local db = {}
  h.eq(S.bucket(db, "k"), nil)
  local b = S.bucket(db, "k", true)
  h.eq(type(b.items), "table"); h.eq(S.bucket(db, "k"), b)
  h.eq(S.bucket(db, nil, true), nil)
end)

-- ---------------------------------------------------------------------------
-- Chunked reader

local function fakeAH(rows) -- rows: { { qty, buyout, itemID, link }, ... }
  return function() return #rows end,
    function(i) local r = rows[i + 1]; return r[1], r[2], r[3], r[4] end
end

local function reader(rows)
  local count, info = fakeAH(rows)
  local t = { timers = {}, progress = {}, dones = 0 }
  t.r = S.newReader({ count = count, info = info,
    after = function(_, fn) t.timers[#t.timers + 1] = fn end,
    now = function() return 0 end,
    onProgress = function(f) t.progress[#t.progress + 1] = f end,
    onDone = function(s) t.done = s; t.dones = t.dones + 1 end })
  function t.step() local fn = table.remove(t.timers, 1); if fn then fn() end; return fn ~= nil end
  function t.run() while t.step() do end end
  return t
end

local function rows4500()
  local rows = {}
  for i = 1, 4500 do rows[i] = { 1, 100, 5, nil } end
  rows[1] = { 2, 400, 6, nil }       -- unit 200
  rows[2] = { 1, 0, 7, nil }         -- no buyout: skipped
  rows[3] = { 1, 999, 82800, nil }   -- pet cage: skipped
  rows[4] = { 1, 700, 50, "|Hitem:50::::::::60::::2:4802:1477::::::|h[Sword]|h" }
  return rows
end

h.test("Scan reader reads in chunks and aggregates per key", function()
  local t = reader(rows4500())
  t.r:start()
  h.eq(t.done, nil) -- nothing read yet: the first chunk waits for a frame
  t.run()
  h.eq(#t.progress >= 3, true)
  h.eq(t.dones, 1); h.eq(t.done.read, 4500); h.eq(t.done.total, 4500); h.eq(t.done.stopped, false)
  h.eq(t.done.sets[6], { { unit = 200, qty = 2 } })
  h.eq(t.done.sets[7], nil); h.eq(t.done.sets[82800], nil)
  h.eq(t.done.sets["50:1477:4802"], { { unit = 700, qty = 1 } })
  h.eq(t.done.sets[5], { { unit = 100, qty = 4496 } }) -- same unit price: one listing
end)

h.test("Scan reader stop keeps what it read and ends once", function()
  local t = reader(rows4500())
  t.r:start()
  t.step()
  t.r:stop()
  h.eq(t.dones, 1); h.eq(t.done.stopped, true); h.eq(t.done.read, S.CHUNK)
  t.run()
  t.r:stop()
  h.eq(t.dones, 1)
end)

h.test("Scan reader drops a link-less item ID set when the scan has its variants", function()
  local link = "|Hitem:50::::::::60::::2:4802:1477::::::|h[Sword]|h"
  local t = reader({ { 1, 700, 50, link }, { 1, 100, 50, nil }, { 1, 300, 9, nil } })
  t.r:start(); t.run()
  h.eq(t.done.sets[50], nil)
  h.eq(t.done.sets["50:1477:4802"], { { unit = 700, qty = 1 } })
  h.eq(t.done.sets[9], { { unit = 300, qty = 1 } })
end)

h.test("Scan lookup never prices the battle pet cage", function()
  local items = {}
  S.record(items, 82800, 5000, 5000, 0)
  h.eq(S.lookup(items, 82800, nil, "market", 0), nil)
end)

h.test("Scan reader of an empty auction house", function()
  local t = reader({})
  t.r:start(); t.run()
  h.eq(t.dones, 1); h.eq(t.done.read, 0); h.eq(next(t.done.sets), nil)
end)

h.test("Scan commit records every set", function()
  local b = { items = {} }
  h.eq(S.commit(b, { [5] = { { unit = 100, qty = 1 } }, [6] = { { unit = 50, qty = 3 } } }, 0), 2)
  h.eq(S.price(b.items, 6, "lowest", 0), 50)
end)

h.test("Scan wait", function()
  h.eq(S.waitLeft(nil, 100), 0); h.eq(S.waitLeft(100, 400), 600); h.eq(S.waitLeft(100, 2000), 0)
end)

-- ---------------------------------------------------------------------------
-- Scan button text

h.test("ScanButton text: ready, reading, waiting", function()
  local un = h.load({ "Util.lua", "UI/ScanButton.lua" })
  local T = un.UI.ScanButton.text
  h.eq(T({ running = false, fraction = 0, waitLeft = 0 }), "AnotherLedger scan")
  h.eq(T({ running = true, fraction = 0.423, waitLeft = 900 }), "Reading 42%")
  h.eq(T({ running = false, fraction = 1, waitLeft = 760 }), "AnotherLedger scan 12:40")
  h.eq(T({ running = false, fraction = 1, waitLeft = 5 }), "AnotherLedger scan 0:05")
end)
