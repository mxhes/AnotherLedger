local h = ...
local ns = h.load({ "Util.lua", "Sources/Sources.lua", "Sources/Vendor.lua", "Sources/TSM.lua", "Sources/Auctionator.lua" })
local S = ns.Sources

-- Vendor
h.test("Vendor returns the 11th GetItemInfo value", function()
  local env = { C_Item = { GetItemInfo = function(id)
    return 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 1200
  end } }
  h.eq(S.Vendor.get(env, 5), 1200)
end)
h.test("Vendor missing C_Item or env is nil", function()
  h.eq(S.Vendor.get({}, 5), nil)
  h.eq(S.Vendor.get(nil, 5), nil)
  h.eq(S.Vendor.get({ C_Item = {} }, 5), nil)
end)
h.test("Vendor empty GetItemInfo is nil", function()
  h.eq(S.Vendor.get({ C_Item = { GetItemInfo = function() end } }, 5), nil)
end)
h.test("Vendor error and non-number are nil", function()
  h.eq(S.Vendor.get({ C_Item = { GetItemInfo = function() error("x") end } }, 5), nil)
  h.eq(S.Vendor.get({ C_Item = { GetItemInfo = function() return 1,2,3,4,5,6,7,8,9,10,"12" end } }, 5), nil)
end)

-- TSM
h.test("TSM passes source and i:ID, returns number", function()
  local got
  local env = { TSM_API = { GetCustomPriceValue = function(s, i) got = { s, i }; return 777 end } }
  local src = S.TSM.new(env, function() return "DBMarket" end)
  h.eq(src.name, "TSM")
  h.eq(src.get(5), 777)
  h.eq(got, { "DBMarket", "i:5" })
end)
h.test("TSM missing API is nil", function()
  local src = S.TSM.new({}, function() return "DBMarket" end)
  h.eq(src.get(5), nil)
  h.eq(S.TSM.new(nil, function() return "x" end).get(5), nil)
  h.eq(S.TSM.new({ TSM_API = {} }, function() return "x" end).get(5), nil)
end)
h.test("TSM erroring API is nil", function()
  local env = { TSM_API = { GetCustomPriceValue = function() error("boom") end } }
  h.eq(S.TSM.new(env, function() return "DBMarket" end).get(5), nil)
end)
h.test("TSM returning nil or non-number is nil", function()
  local env = { TSM_API = { GetCustomPriceValue = function() return nil end } }
  h.eq(S.TSM.new(env, function() return "DBMarket" end).get(5), nil)
  env = { TSM_API = { GetCustomPriceValue = function() return "5" end } }
  h.eq(S.TSM.new(env, function() return "DBMarket" end).get(5), nil)
end)
h.test("TSM getSource nil or throwing is nil", function()
  local called = false
  local env = { TSM_API = { GetCustomPriceValue = function() called = true; return 1 end } }
  h.eq(S.TSM.new(env, function() return nil end).get(5), nil)
  h.eq(S.TSM.new(env, function() error("no") end).get(5), nil)
  h.eq(called, false)
end)

-- Auctionator
h.test("Auctionator passes caller id and item ID", function()
  local got
  local env = { Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(c, i)
    got = { c, i }; return 4200
  end } } } }
  local src = S.Auctionator.new(env)
  h.eq(src.name, "Auctionator")
  h.eq(src.get(9), 4200)
  h.eq(got, { "AnotherLedger", 9 })
end)
h.test("Auctionator missing tables are nil", function()
  h.eq(S.Auctionator.new({}).get(9), nil)
  h.eq(S.Auctionator.new(nil).get(9), nil)
  h.eq(S.Auctionator.new({ Auctionator = {} }).get(9), nil)
  h.eq(S.Auctionator.new({ Auctionator = { API = {} } }).get(9), nil)
  h.eq(S.Auctionator.new({ Auctionator = { API = { v1 = {} } } }).get(9), nil)
end)
h.test("Auctionator error and non-number are nil", function()
  local function mk(f) return { Auctionator = { API = { v1 = { GetAuctionPriceByItemID = f } } } } end
  h.eq(S.Auctionator.new(mk(function() error("x") end)).get(9), nil)
  h.eq(S.Auctionator.new(mk(function() return nil end)).get(9), nil)
  h.eq(S.Auctionator.new(mk(function() return "9" end)).get(9), nil)
end)

h.test("Sources registry: order, choices and the source built from a spec", function()
  local keys = {}
  for i, spec in ipairs(S.list()) do keys[i] = spec.key end
  h.eq(keys, { "tsm", "auctionator" })
  h.eq(S.choices(), {
    { value = "auto", label = "Auto (TSM, then Auctionator)", short = "Auto" },
    { value = "tsm", label = "TSM" },
    { value = "auctionator", label = "Auctionator" },
  })
  local asked
  local env = { TSM_API = { GetCustomPriceValue = function(src) asked = src return 5 end } }
  local settings = { tsmSource = "DBMarket" }
  local src = S.list()[1].create(env, function(key) return settings[key] end)
  h.eq(src.get(1), 5); h.eq(asked, "DBMarket")
  settings.tsmSource = "DBMinBuyout" -- read live
  src.get(1); h.eq(asked, "DBMinBuyout")
  S.list()[1].createDisenchant(env).get(1); h.eq(asked, "Destroy")
end)

h.test("Sources.register: a new source joins the list and the choices, a repeat replaces", function()
  local count = #S.list()
  S.register({ key = "extra", label = "Extra", create = function() return { name = "Extra", get = function() return 1 end } end })
  h.eq(#S.list(), count + 1)
  local choices = S.choices()
  h.eq(choices[#choices], { value = "extra", label = "Extra" })
  h.eq(choices[1].label, "Auto (TSM, then Auctionator, then Extra)")
  h.eq(S.allowed("extra", "tsm"), false)
  S.register({ key = "extra", label = "Extra 2", create = function() end })
  h.eq(#S.list(), count + 1)
  h.eq(pcall(S.register, { key = "bad" }), false)
end)

h.test("TSM.market asks scaled region sale rate and sold per day", function()
  local asked = {}
  local env = { TSM_API = { GetCustomPriceValue = function(s, i)
    asked[#asked + 1] = s .. "|" .. i
    if s:find("SaleRate", 1, true) then return 123 end
    return 4550
  end } }
  local m = S.TSM.market(env, 7)
  h.near(m.saleRate, 0.123)
  h.near(m.soldPerDay, 45.5)
  h.eq(asked, { "DBRegionSaleRate * 1000|i:7", "DBRegionSoldPerDay * 100|i:7" })
end)

h.test("TSM.market: a rate already scaled by 1000 is brought back to 0..1; no data is nil", function()
  local env = { TSM_API = { GetCustomPriceValue = function(s)
    if s:find("SaleRate", 1, true) then return 250000 end
    return nil
  end } }
  local m = S.TSM.market(env, 7)
  h.near(m.saleRate, 0.25)
  h.eq(m.soldPerDay, nil)
  h.eq(S.TSM.market({ TSM_API = { GetCustomPriceValue = function() error("x") end } }, 7), nil)
  h.eq(S.TSM.market({}, 7), nil)
  h.eq(S.TSM.market(nil, 7), nil)
end)

-- Own sales (Sources/Sales.lua)
local ns2 = h.load({ "Util.lua", "LootParse.lua", "Sources/Sources.lua", "Sources/TSM.lua", "Sources/Auctionator.lua",
  "Scan.lua", "Sources/Scan.lua", "Trade.lua", "Sources/Sales.lua" })

h.test("Sources: sales comes right after scan", function()
  local keys = {}
  for _, spec in ipairs(ns2.Sources.list()) do keys[#keys + 1] = spec.key end
  local at
  for i, k in ipairs(keys) do if k == "scan" then at = i end end
  h.eq(keys[at + 1], "sales")
end)

h.test("Sources: sales answers the own sale price with its age", function()
  ns2.db = {}
  local b = ns2.Trade.bucket(ns2.db, "k-R", true)
  ns2.Trade.add(b, { t = 100, kind = "sale", key = 5, id = 5, n = 2, gold = 300, cut = 15 })
  ns2.Scan.currentRealmKey = function() return "k-R" end
  local spec
  for _, s in ipairs(ns2.Sources.list()) do if s.key == "sales" then spec = s end end
  local src = spec.create({ time = function() return 160 end }, function() end)
  local price, age = src.get(5)
  h.eq(price, 150); h.eq(age, 60)
  h.eq(src.get(6), nil)
  ns2.Scan.currentRealmKey = function() return nil end
  h.eq(src.get(5), nil)
end)

-- Auctionator price age and disenchant value
h.test("Auctionator gives the age of its price in seconds (days * 86400)", function()
  local env = { Auctionator = { API = { v1 = {
    GetAuctionPriceByItemLink = function() return 500 end,
    GetAuctionAgeByItemLink = function(c, l) h.eq(c, "AnotherLedger"); return 2 end,
    GetAuctionPriceByItemID = function() return 400 end,
    GetAuctionAgeByItemID = function() return 0 end,
  } } } }
  local src = S.Auctionator.new(env)
  local v, age = src.get(9, "|Hitem:9|h")
  h.eq(v, 500); h.eq(age, 2 * 86400)
  v, age = src.get(9)
  h.eq(v, 400); h.eq(age, 0)
  env.Auctionator.API.v1.GetAuctionAgeByItemID = nil -- older Auctionator: live
  v, age = src.get(9)
  h.eq(v, 400); h.eq(age, 0)
  env.Auctionator.API.v1.GetAuctionAgeByItemID = function() error("x") end
  h.eq(select(2, src.get(9)), 0)
end)

h.test("Auctionator disenchant asks by link, finds the link without one", function()
  local asked
  local env = {
    Auctionator = { API = { v1 = { GetDisenchantPriceByItemLink = function(c, l) asked = l; return 3000 end } } },
    C_Item = { GetItemInfo = function(id) return "Sword", "|Hitem:" .. id .. "|h" end },
  }
  local de = S.Auctionator.disenchant(env)
  h.eq(de.get(4, "|Hitem:4:1|h"), 3000); h.eq(asked, "|Hitem:4:1|h")
  h.eq(de.get(4), 3000); h.eq(asked, "|Hitem:4|h")
  env.C_Item = nil
  h.eq(de.get(4), nil)
  env.Auctionator.API.v1.GetDisenchantPriceByItemLink = function() return 0 end
  h.eq(de.get(4, "x"), nil)
  h.eq(S.Auctionator.disenchant({}).get(4, "x"), nil)
end)

-- Presence: a selected source that is not loaded acts as Auto
h.test("Sources.isPresent, effective, allowed with env and offers", function()
  local tsm, auc = S.list()[1], S.list()[2]
  h.eq(S.isPresent(tsm, {}), false)
  h.eq(S.isPresent(tsm, { TSM_API = {} }), true)
  h.eq(S.isPresent({ key = "scan" }, {}), true) -- no present check
  h.eq(S.isPresent({ present = function() error("x") end }, {}), false)
  h.eq(S.effective("tsm", {}), "auto")
  h.eq(S.effective("tsm", { TSM_API = {} }), "tsm")
  h.eq(S.effective("auto", {}), "auto")
  h.eq(S.allowed("tsm", "auctionator", {}), true)
  h.eq(S.allowed("tsm", "auctionator", { TSM_API = {} }), false)
  h.eq(S.allowed("tsm", "auctionator"), false) -- without env: strict
  h.eq(S.offers("createDisenchant", {}), false)
  h.eq(S.offers("createDisenchant", { Auctionator = { API = {} } }), true)
  h.eq(S.offers("createMarket", { Auctionator = { API = {} } }), false)
  h.eq(S.offers("createMarket", { TSM_API = {} }), true)
  local choices = S.choices({ TSM_API = {} })
  h.eq(choices[2].label, "TSM")
  h.eq(choices[3].label, "Auctionator (not loaded)")
  h.eq(auc.key, "auctionator")
end)

h.test("Sources.gate with env: a missing selected addon lets every source answer", function()
  local selected = "tsm"
  local env = {}
  local src = S.gate({ name = "A", get = function() return 5 end }, "auctionator", function() return selected end, env)
  h.eq(src.get(1), 5)
  env.TSM_API = {}
  h.eq(src.get(1), nil)
end)
