local h = ...
local ns = h.load({ "Slash.lua" })
local P = ns.Slash.parse

local function pair(msg)
  local c, a = P(msg)
  return { c, a }
end

h.test("Slash.parse basics", function()
  h.eq(pair(""), { "toggle" })
  h.eq(pair("   "), { "toggle" })
  h.eq(pair("show"), { "show" })
  h.eq(pair("  reset "), { "reset" })
  h.eq(pair("SHOW"), { "show" })
end)

h.test("Slash.parse arguments keep case", function()
  h.eq(pair("KEEP on"), { "keep", "on" })
  h.eq(pair("tsm DBMinBuyout"), { "tsm", "DBMinBuyout" })
  h.eq(pair("tsm   DBMarket  "), { "tsm", "DBMarket" })
  h.eq(pair("tsm first(DBMarket, DBMinBuyout)"), { "tsm", "first(DBMarket, DBMinBuyout)" })
end)

h.test("Slash.parse non-string", function()
  h.eq(pair(nil), { "toggle" })
end)
