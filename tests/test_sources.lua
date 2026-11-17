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
  h.eq(got, { "LootLedger", 9 })
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
    { value = "auto", label = "Auto (TSM, then Auctionator)" },
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
