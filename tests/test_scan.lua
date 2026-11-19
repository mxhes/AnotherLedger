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
  local e = { t = 5 * D + 7, m = 123456, l = 99, am = 120000, al = 90, ad = 4 }
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
  h.eq(S.price(items, 5, "market", 11 * D), math.floor(1000 * w + 2000 * (1 - w)))
end)

h.test("Scan long gap lets today dominate", function()
  local items = {}
  S.record(items, 5, 1000, 1000, 10 * D)
  S.record(items, 5, 2000, 2000, 20 * D)
  h.eq(S.price(items, 5, "market", 20 * D), 1750)
end)

h.test("Scan third day folds into the running average", function()
  local items = {}
  S.record(items, 5, 1000, 1000, 10 * D)
  S.record(items, 5, 2000, 2000, 15 * D) -- average of day 10 alone: 1000
  S.record(items, 5, 3000, 3000, 20 * D) -- day 15 folds in: 1000 * 0.5 + 2000 * 0.5 = 1500
  h.eq(S.price(items, 5, "market", 20 * D), math.floor(1500 * 0.5 + 3000 * 0.5))
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
  h.eq(src.name, "LootLedger scan")
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
  h.eq(sn.Sources.choices()[1].label, "Auto (TSM, then Auctionator, then LootLedger scan)")
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
