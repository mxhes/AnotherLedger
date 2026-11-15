local h = ...
local ns = h.load({ "Util.lua", "Money.lua", "Theme.lua", "History.lua", "UI/DailyFarm.lua" })
local DF = ns.UI.DailyFarm

local function farm()
  return {
    best = { zone = "Z", sub = "A", time = 3600, value = 40000, perHour = 40000 },
    runnersUp = { { zone = "Y", sub = "Y", time = 1800, value = 10000, perHour = 20000 } },
  }
end

h.test("DailyFarm.label names the subzone and zone with the rate", function()
  local f = farm()
  local s = DF.label(f)
  h.eq(s:find("A (Z)", 1, true) ~= nil, true)
  h.eq(s:find(ns.Money.format(40000), 1, true) ~= nil, true)
  h.eq(s:find(ns.L["slow selling"], 1, true), nil)
  f.best.sub = "Z"
  h.eq(DF.label(f):find("(Z)", 1, true), nil)
  f.slow = { names = { "Ore" } }
  h.eq(DF.label(f):find(ns.L["slow selling"], 1, true) ~= nil, true)
end)

h.test("DailyFarm.hint lists the place, the runner-ups and the slow sellers", function()
  local f = farm()
  local s = DF.hint(f)
  h.eq(s:find("Z", 1, true) ~= nil, true)
  h.eq(s:find(ns.L["Also good:"], 1, true) ~= nil, true)
  h.eq(s:find("  Y  ~", 1, true) ~= nil, true) -- the runner-up is its own zone
  h.eq(s:find(ns.L["Sells slowly: "], 1, true), nil)
  f.slow = { names = { "Ore", "Herb" } }
  f.runnersUp = {}
  s = DF.hint(f)
  h.eq(s:find("Ore, Herb", 1, true) ~= nil, true)
  h.eq(s:find(ns.L["Also good:"], 1, true), nil)
end)
