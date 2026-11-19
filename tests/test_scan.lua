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
