local h = ...
local ns = h.load({ "Util.lua", "Money.lua", "Theme.lua", "Tooltip.lua", "History.lua", "View.lua", "Waypoint.lua", "UI/Rows.lua", "UI/DailyFarm.lua", "UI/Compact.lua" })
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
  local tip = DF.hint(f)
  h.eq(tip.title, "A (Z)")
  local s = ns.Tooltip.text(tip)
  h.eq(s:find(ns.L["Also good:"], 1, true) ~= nil, true)
  h.eq(s:find("\n  Y " .. ns.Money.format(20000), 1, true) ~= nil, true) -- the runner-up is its own zone
  h.eq(s:find("~", 1, true), nil)
  h.eq(s:find(ns.L["Sells slowly: "], 1, true), nil)
  f.slow = { names = { "Ore", "Herb" } }
  f.runnersUp = {}
  s = ns.Tooltip.text(DF.hint(f))
  h.eq(s:find("Ore, Herb", 1, true) ~= nil, true)
  h.eq(s:find(ns.L["Also good:"], 1, true), nil)
end)

h.test("DailyFarm.label rounds the rate to whole gold from 1 gold up", function()
  local f = farm()
  f.best.perHour = 12345678
  local s = DF.label(f)
  h.eq(s:find(ns.Money.format(12350000), 1, true) ~= nil, true)
  f.best.perHour = 5555 -- under 1 gold: in full
  h.eq(DF.label(f):find(ns.Money.format(5555), 1, true) ~= nil, true)
end)

h.test("DailyFarm.hint lists the clicks: waypoint ones only with a spot", function()
  local f = farm()
  local s = ns.Tooltip.text(DF.hint(f))
  h.eq(s:find(ns.L["Click to open it in Zones"], 1, true) ~= nil, true)
  h.eq(s:find(ns.L["Click: waypoint"], 1, true), nil)
  f.best.pos = { mapID = 1, x = 0.5, y = 0.5 }
  s = ns.Tooltip.text(DF.hint(f))
  h.eq(s:find(ns.L["Click: waypoint"], 1, true) ~= nil, true)
  h.eq(s:find(ns.L["Shift-click: open it in Zones"], 1, true) ~= nil, true)
  h.eq(s:find(ns.L["Right-click: copy the /way line"], 1, true) ~= nil, true)
  h.eq(s:find(ns.L["Click to open it in Zones"], 1, true), nil)
end)

h.test("DailyFarm.label puts the rate first so a narrow window cuts the place", function()
  local f = farm()
  local s = DF.label(f)
  -- Short prefix and no tilde (it sits raised in the game font).
  h.eq(s:sub(1, #ns.L["Daily: "]), ns.L["Daily: "])
  h.eq(s:find("~", 1, true), nil)
  h.eq(s:find(ns.L["/h"], 1, true) < s:find("A (Z)", 1, true), true)
  f.slow = { names = { "Ore" } }
  local slow = DF.label(f)
  h.eq(slow:find(ns.L["slow selling"], 1, true) > slow:find("A (Z)", 1, true), true)
end)

h.test("Compact fits its body at the minimum window height", function()
  local C = ns.UI.Compact
  h.eq(C ~= nil, true)
  local S = ns.Theme.sizes
  h.eq(S.compactMinHeight >= C.requiredHeight(), true)
  h.eq(S.compactHeight >= S.compactMinHeight, true)
end)

h.test("Compact.rateText: money per hour, a dash per hour without a rate", function()
  h.eq(ns.UI.Compact.rateText(nil), "\226\128\148/h")
  h.eq(ns.UI.Compact.rateText(0), "\226\128\148/h") -- nothing earned yet
  h.eq(ns.UI.Compact.rateText(5000.4, ns.Money.format), ns.Money.format(5000) .. "/h")
end)

h.test("Compact.titleText: why there are no drops; no title with the list turned off", function()
  local C = ns.UI.Compact
  h.eq(C.titleText({ drops = { {} }, running = true, dropLimit = 4 }), "Last drops")
  h.eq(C.titleText({ drops = {}, running = true, dropLimit = 4 }), "No drops yet.")
  h.eq(C.titleText({ drops = {}, running = true, dropLimit = 0 }), nil)
  h.eq(C.titleText({ drops = {}, running = false, dropLimit = 0 }), "Paused: click the clock to start.")
end)

h.test("View.recentRate: the last 15 minutes from the newest sample that old", function()
  local V = ns.View
  local samples = { { t = 60, v = 100 }, { t = 600, v = 1000 }, { t = 1200, v = 4000 }, { t = 1800, v = 5000 } }
  -- at 2100 s: the sample at 1200 (900 s back), 4000 -> 7000 in 900 s
  h.eq(V.recentRate(samples, 2100, 7000), 12000)
  -- younger than 15 minutes: none
  h.eq(V.recentRate(samples, 800, 2000), nil)
  h.eq(V.recentRate(nil, 2100, 7000), nil)
  -- a lower total (an item ignored since) never gives a negative rate
  h.eq(V.recentRate(samples, 2100, 0), 0)
end)

h.test("Compact.recentText and goalFraction", function()
  local C = ns.UI.Compact
  local f = ns.Money.format
  h.eq(C.recentText({}, f), nil)
  h.eq(C.recentText({ recent = 12000.4 }, f), "15 min: " .. f(ns.Money.roundRate(12000.4)) .. "/h")
  h.eq(C.goalFraction({}), nil)
  h.eq(C.goalFraction({ goal = { value = 2500, goal = 10000 } }), 0.25)
  h.eq(C.goalFraction({ goal = { value = 20000, goal = 10000 } }), 1)
  local text = ns.Tooltip.text(C.hint({ total = 7000, perHour = 9000, recent = 12000, elapsed = 2100 }))
  h.eq(text:find("Last 15 minutes: ", 1, true) ~= nil, true)
end)

h.test("Compact.totalText and hint: the total against the goal, the breakdown", function()
  local C = ns.UI.Compact
  local f = ns.Money.format
  h.eq(C.totalText({ total = 5000 }, f), "Session " .. f(5000))
  h.eq(C.totalText({ total = 5000, goal = { value = 5000, goal = 10000 } }, f), "Session " .. f(5000) .. " / " .. f(10000))
  h.eq(C.totalText({ total = 1 }, f, "|cff000000"), "|cff000000Session|r " .. f(1))
  local tip = ns.Tooltip.text(C.hint({ total = 6000, items = 5000, gold = 1000, elapsed = 120, perHour = 180000,
    top = { name = "Ore", quantity = 3, value = 4000 }, goal = { value = 6000, goal = 10000 } }))
  for _, part in ipairs({ "2m", "Items: ", "Raw gold: ", "Total: ", "Gold per hour: ", "Best find: Ore x3", "60%" }) do
    h.eq(tip:find(part, 1, true) ~= nil, true)
  end
  local young = ns.Tooltip.text(C.hint({ total = 0, items = 0, gold = 0, elapsed = 10 }))
  h.eq(young:find("after the first minute", 1, true) ~= nil, true)
  h.eq(young:find("Raw gold", 1, true), nil)
end)
