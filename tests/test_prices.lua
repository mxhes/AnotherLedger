local h = ...
local ns = h.load({ "Util.lua", "Prices.lua" })
local P = ns.Prices

local function make(sources, vendor, cache, key, clock)
  return P.new({
    sources = sources, vendor = vendor, cache = cache,
    key = key or function() return "EU-1" end,
    now = function() return clock.t end,
  })
end
local function src(name, v) return { name = name, get = function() return v end } end

h.test("Prices live price is cached", function()
  local cache, clock = {}, { t = 1000 }
  local p = make({ src("TSM", 4500) }, function() return nil end, cache, nil, clock)
  local r = p:lookup(5)
  h.eq(r.ah, 4500); h.eq(r.ahSource, "TSM"); h.eq(r.ahAge, 0)
  h.eq(cache["EU-1"][5].price, 4500); h.eq(cache["EU-1"][5].seenAt, 1000)
end)

h.test("Prices falls through to second source", function()
  local p = make({ src("A", nil), src("B", 300) }, function() end, {}, nil, { t = 1 })
  local r = p:lookup(5)
  h.eq(r.ah, 300); h.eq(r.ahSource, "B")
end)

h.test("Prices cache fallback with age", function()
  local cache = { ["EU-1"] = { [5] = { price = 4500, seenAt = 1000 } } }
  local p = make({ src("A", nil) }, function() end, cache, nil, { t = 1000 + 14 * 3600 })
  local r = p:lookup(5)
  h.eq(r.ah, 4500); h.eq(r.ahSource, "cache"); h.eq(r.ahAge, 50400)
  h.eq(P.isStale(50400), true)
end)

h.test("Prices nothing anywhere", function()
  local p = make({ src("A", nil) }, function() end, {}, nil, { t = 1 })
  local r = p:lookup(5)
  h.eq(r.ah, nil); h.eq(r.ahAge, nil); h.eq(r.ahSource, nil)
end)

h.test("Prices nil key never touches cache", function()
  local cache = {}
  local p = make({ src("A", 100) }, function() end, cache, function() return nil end, { t = 1 })
  local r = p:lookup(5)
  h.eq(r.ah, 100)
  h.eq(next(cache), nil)
end)

h.test("Prices write throttle", function()
  local cache, clock = {}, { t = 1000 }
  local price = 100
  local p = make({ { name = "A", get = function() return price end } }, function() end, cache, nil, clock)
  p:lookup(5)
  clock.t = 1010; p:lookup(5)
  h.eq(cache["EU-1"][5].seenAt, 1000)
  clock.t = 1061; p:lookup(5)
  h.eq(cache["EU-1"][5].seenAt, 1061)
  clock.t = 1070; price = 200; p:lookup(5)
  h.eq(cache["EU-1"][5].price, 200); h.eq(cache["EU-1"][5].seenAt, 1070)
end)

h.test("Prices bad values are nil", function()
  local bad = { 0, -1, 0 / 0, "abc", true, math.huge }
  for _, v in ipairs(bad) do
    local p = make({ src("A", v), src("B", 50) }, function() end, {}, nil, { t = 1 })
    h.eq(p:lookup(5).ahSource, "B")
  end
  local thrower = { name = "T", get = function() error("boom") end }
  local cache = { ["EU-1"] = { [5] = { price = 9, seenAt = 1 } } }
  local r = make({ thrower }, function() end, cache, nil, { t = 11 }):lookup(5)
  h.eq(r.ahSource, "cache"); h.eq(r.ah, 9); h.eq(r.ahAge, 10)
  r = make({ thrower, src("B", 7) }, function() end, {}, nil, { t = 1 }):lookup(5)
  h.eq(r.ahSource, "B")
end)

h.test("Prices vendor", function()
  local function v(x) return make({}, function() return x end, {}, nil, { t = 1 }):lookup(5).vendor end
  h.eq(v(1200), 1200); h.eq(v(nil), nil); h.eq(v(0), 0)
end)

h.test("Prices cacheKey", function()
  h.eq(P.cacheKey("EU", 7), "EU-7")
  h.eq(P.cacheKey("EU", nil), nil)
  h.eq(P.cacheKey(nil, 7), nil)
  h.eq(P.cacheKey({}, 7), nil)
  h.eq(P.cacheKey("EU", {}), nil)
  h.eq(P.cacheKey("EU", true), nil)
  h.eq(P.cacheKey("EU", print), nil)
end)

h.test("Prices formatAge/isStale", function()
  h.eq(P.formatAge(30), "1m"); h.eq(P.formatAge(120), "2m")
  h.eq(P.formatAge(14 * 3600), "14h"); h.eq(P.formatAge(3 * 86400), "3d")
  h.eq(P.isStale(43200), false); h.eq(P.isStale(43201), true)
end)

local function one(cache, price, t, key)
  local clock = { t = t }
  local p = make({ src("A", price) }, function() end, cache, key, clock)
  return p:lookup(5)
end

h.test("Prices malformed entries are overwritten", function()
  for _, bad in ipairs({ 5, true, { price = 100 }, { price = 100, seenAt = "x" }, { price = 100, seenAt = 0 / 0 } }) do
    local cache = { ["EU-1"] = { [5] = bad } }
    local r = one(cache, 100, 1000)
    h.eq(r.ah, 100)
    h.eq(cache["EU-1"][5].seenAt, 1000)
  end
end)

h.test("Prices malformed entries ignored on fallback", function()
  for _, bad in ipairs({ 5, true, { price = 100 }, { price = 100, seenAt = "x" }, { price = 100, seenAt = 0 / 0 } }) do
    local r = one({ ["EU-1"] = { [5] = bad } }, nil, 1000)
    h.eq(r.ah, nil); h.eq(r.ahAge, nil)
  end
end)

h.test("Prices non-table bucket", function()
  for _, bad in ipairs({ 7, "str", true }) do
    local cache = { ["EU-1"] = bad }
    local r = one(cache, 100, 1000)
    h.eq(r.ah, 100)
    h.eq(cache["EU-1"][5].price, 100)
    h.eq(one({ ["EU-1"] = bad }, nil, 1000).ah, nil)
  end
end)

h.test("Prices throttle boundary and backwards clock", function()
  local cache = { ["EU-1"] = { [5] = { price = 100, seenAt = 1000 } } }
  one(cache, 100, 1059); h.eq(cache["EU-1"][5].seenAt, 1000)
  one(cache, 100, 1060); h.eq(cache["EU-1"][5].seenAt, 1060)
  one(cache, 100, 900); h.eq(cache["EU-1"][5].seenAt, 900)
  local c2 = { ["EU-1"] = { [5] = { price = 100, seenAt = 2000 } } }
  local r = one(c2, nil, 1000)
  h.eq(r.ahAge, 0)
end)

h.test("Prices throwing key keeps live price", function()
  local cache = {}
  local r = one(cache, 100, 1, function() error("x") end)
  h.eq(r.ah, 100); h.eq(next(cache), nil)
end)

h.test("Prices formatAge boundaries", function()
  h.eq(P.formatAge(59), "1m"); h.eq(P.formatAge(60), "1m"); h.eq(P.formatAge(3599), "59m")
  h.eq(P.formatAge(3600), "1h"); h.eq(P.formatAge(86399), "23h"); h.eq(P.formatAge(86400), "1d")
end)

h.test("Prices disenchant value is live and optional", function()
  local function de(fn)
    return P.new({ sources = {}, disenchant = fn, cache = {}, key = function() return "EU-1" end,
      now = function() return 1 end }):lookup(5).de
  end
  h.eq(de(function() return 750 end), 750)
  h.eq(de(function() return nil end), nil)
  h.eq(de(function() return 0 end), nil)
  h.eq(de(function() error("boom") end), nil)
  h.eq(de(nil), nil)
end)

h.test("Prices.prune drops old and unusable entries and empty buckets", function()
  local day = 86400
  local now = 100 * day
  local cache = {
    ["EU-1"] = {
      [1] = { price = 5, seenAt = now - 10 * day },  -- kept
      [2] = { price = 5, seenAt = now - 31 * day },  -- too old
      [3] = { price = 5, seenAt = now + 50 },        -- clock went back: kept
      [4] = "garbage",
      [5] = { price = 5 },                           -- no timestamp
    },
    ["EU-2"] = { [9] = { price = 1, seenAt = 0 } },  -- bucket ends up empty
    junk = 7,                                        -- not a bucket: left alone
  }
  h.eq(ns.Prices.prune(cache, now, 30 * day), 4)
  h.eq(cache["EU-1"], { [1] = { price = 5, seenAt = now - 10 * day }, [3] = { price = 5, seenAt = now + 50 } })
  h.eq(cache["EU-2"], nil)
  h.eq(cache.junk, 7)
  h.eq(ns.Prices.prune(cache, now, 30 * day), 0)
  h.eq(ns.Prices.prune(nil, now, day), 0)
  h.eq(ns.Prices.prune(cache, nil, day), 0)
  h.eq(ns.Prices.CACHE_MAX_AGE, 30 * day)
end)

h.test("an unchanged live price re-stamps the cache entry in place", function()
  local entry = { price = 100, seenAt = 1000 }
  local cache = { ["EU-1"] = { [5] = entry } }
  local p = ns.Prices.new({
    sources = { { name = "S", get = function() return 100 end } },
    cache = cache, key = function() return "EU-1" end, now = function() return 2000 end,
  })
  p:lookup(5)
  h.eq(cache["EU-1"][5] == entry, true) -- no new table
  h.eq(entry.seenAt, 2000)
end)

h.test("lookup adds live sale rate and sold per day from the market function", function()
  local p = P.new({ sources = {}, now = function() return 1 end, key = function() return nil end,
    market = function() return { saleRate = 0.2, soldPerDay = 3 } end })
  local r = p:lookup(5)
  h.eq(r.saleRate, 0.2)
  h.eq(r.soldPerDay, 3)
  p = P.new({ sources = {}, now = function() return 1 end, key = function() return nil end,
    market = function() error("boom") end })
  h.eq(p:lookup(5).saleRate, nil)
  p = P.new({ sources = {}, now = function() return 1 end, key = function() return nil end,
    market = function() return { saleRate = -1, soldPerDay = "x" } end })
  r = p:lookup(5)
  h.eq(r.saleRate, nil)
  h.eq(r.soldPerDay, nil)
end)
