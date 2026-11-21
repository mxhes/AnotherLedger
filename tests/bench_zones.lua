-- Timing of the History views over a large History (not part of the test run):
--   lua tests/bench_zones.lua [sessions]
local h = dofile("tests/harness.lua")
local ns = h.load({ "Util.lua", "Money.lua", "Theme.lua", "Tooltip.lua", "Prices.lua", "Session.lua",
  "History.lua", "Mobs.lua", "View.lua", "ViewZones.lua", "ViewTrade.lua" })
local V = ns.View

local SESSIONS = tonumber(arg and arg[1]) or 500
local ZONES, SUBS, ITEMS_PER_SUB, MOBS = 20, 5, 15, 8

math.randomseed(1)
local function link(id) return "|cff1eff00|Hitem:" .. id .. "::::::::60:::::|h[Item " .. id .. "]|h|r" end

local entries = {}
for i = 1, SESSIONS do
  local e = { startedAt = 1000000 + i * 3600, elapsed = 3600, gold = 0, nItems = 0, vendor = 0, ah = 0,
    items = {}, zones = {}, places = {}, mobs = {} }
  local zone = "Zone" .. math.random(ZONES)
  local z = { subs = {} }
  e.zones[zone] = z
  e.places[1] = zone
  for s = 1, 2 do
    local sub = "Sub" .. math.random(SUBS)
    local src = { time = 1800, gold = 5000, items = {}, pos = {} }
    z.subs[sub] = src
    for _ = 1, ITEMS_PER_SUB do
      local id = math.random(2000)
      local qty = math.random(5)
      local it = e.items[id]
      if not it then
        it = { id = id, key = id, link = link(id), qty = 0, lastSeen = e.startedAt,
          price = { vendor = 100, ah = 500 } }
        e.items[id] = it
      end
      it.qty = it.qty + qty
      src.items[id] = (src.items[id] or 0) + qty
    end
    e.gold = e.gold + 5000
  end
  for m = 1, MOBS do
    local key = "npc:" .. math.random(300)
    local mob = { kind = "npc", id = m, looted = 3, gold = 200, items = {}, places = { [zone] = 3 } }
    for id in pairs(e.items) do
      if math.random() < 0.1 then mob.items[id] = 1 end
    end
    e.mobs[key] = mob
  end
  entries[i] = e
end

local lookup = function(id) return { vendor = 100, ah = 400 + id % 50 } end
local itemInfo = function(id) return { name = "Item " .. id, quality = 2 } end
local opts = { lookup = lookup, itemInfo = itemInfo, sort = "ah", now = 2000000 }

local function time(label, fn, runs)
  runs = runs or 10
  fn()
  local t0 = os.clock()
  for _ = 1, runs do fn() end
  print(string.format("%-28s %7.2f ms", label, (os.clock() - t0) * 1000 / runs))
end

print(SESSIONS .. " sessions")
time("buildZones", function() V.buildZones(entries, opts, {}) end)
time("buildMobs", function() V.buildMobs(entries, opts, nil) end)
time("dailyFarm", function() V.dailyFarm(entries, opts, 1200) end)
time("dropIndex", function() V.dropIndex(entries) end)
time("buildHistory", function() V.buildHistory(entries, opts, nil) end)

-- Cached (ViewZones.lua): the saved History plus a running session that
-- looted in one place, as a loot redraw sees it.
local live = { live = true, gold = 100, items = {}, places = { Zone1 = 3 },
  zones = { Zone1 = { subs = { Sub1 = { time = 60, gold = 100, items = {}, pos = {} } } } },
  mobs = { ["npc:1"] = { kind = "npc", looted = 1, gold = 100, items = {} } } }
for id = 1, 10 do
  live.items[id] = { id = id, key = id, link = link(id), qty = 1, lastSeen = 1 }
  live.zones.Zone1.subs.Sub1.items[id] = 1
  live.mobs["npc:1"].items[id] = 1
end
local withLive = {}
for i, e in ipairs(entries) do withLive[i] = e end
withLive[#withLive + 1] = live
local copts = {}
for k, v in pairs(opts) do copts[k] = v end
copts.historyKey, copts.valueKey = "bench", "v1"
time("buildZones cached", function() V.buildZones(withLive, copts, {}) end)
time("buildMobs cached", function() V.buildMobs(withLive, copts, nil) end)
time("dailyFarm cached", function() V.dailyFarm(entries, copts, 1200) end)

-- The cached views equal the uncached ones.
local function rowsOf(view)
  local out = {}
  for i, r in ipairs(view.rows) do out[i] = (r.key or "") .. "=" .. tostring(r.value) end
  return table.concat(out, ",")
end
assert(rowsOf(V.buildZones(withLive, copts, {})) == rowsOf(V.buildZones(withLive, opts, {})))
assert(rowsOf(V.buildMobs(withLive, copts, nil)) == rowsOf(V.buildMobs(withLive, opts, nil)))
print("cached views match")
