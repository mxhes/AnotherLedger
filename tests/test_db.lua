local h = ...
local ns = h.load({ "DB.lua" })
local DB = ns.DB

h.test("DB.defaults shape", function()
  local d = DB.defaults
  h.eq(d.version, 1)
  h.eq(d.cache, {})
  h.eq(d.settings, { keepSession = false, tsmSource = "DBMarket" })
  h.eq(d.window, { point = "CENTER", x = 0, y = 0, width = 420, height = 420, hidden = false })
  h.eq(d.filter.minValue, 0)
  h.eq(d.filter.search, "")
  h.eq(d.sort, "ah")
  for q = 0, 7 do h.eq(d.filter.qualities[q], true) end
end)

h.test("applyDefaults(nil) is an equal, independent copy", function()
  local D = DB.defaults
  local r = DB.applyDefaults(nil, D)
  h.eq(r, D)
  r.settings.keepSession = true
  r.filter.qualities[3] = false
  r.cache.x = 1
  h.eq(D.settings.keepSession, false)
  h.eq(D.filter.qualities[3], true)
  h.eq(D.cache, {})
end)

h.test("applyDefaults handles non-table saved", function()
  h.eq(DB.applyDefaults("oops", DB.defaults), DB.defaults)
  h.eq(DB.applyDefaults(5, DB.defaults), DB.defaults)
end)

h.test("applyDefaults keeps saved values and fills the rest", function()
  local r = DB.applyDefaults({ settings = { keepSession = true } }, DB.defaults)
  h.eq(r.settings.keepSession, true)
  h.eq(r.settings.tsmSource, "DBMarket")
  h.eq(r.window.width, 420)
end)

h.test("applyDefaults replaces wrong-typed values", function()
  local r = DB.applyDefaults({ settings = "oops", window = { width = "x" }, sort = 5 }, DB.defaults)
  h.eq(r.settings, { keepSession = false, tsmSource = "DBMarket" })
  h.eq(r.window.width, 420)
  h.eq(r.sort, "ah")
end)

h.test("applyDefaults preserves unknown keys such as cache entries", function()
  local saved = { cache = { ["EU-1"] = { [2589] = { price = 5, seenAt = 9 } } }, extra = 7 }
  local r = DB.applyDefaults(saved, DB.defaults)
  h.eq(r.cache["EU-1"][2589].price, 5)
  h.eq(r.extra, 7)
  h.eq(r, saved)
end)

h.test("applyDefaults never mutates defaults and shares no tables", function()
  local D = DB.defaults
  local a = DB.applyDefaults({}, D)
  local b = DB.applyDefaults({}, D)
  h.eq(a.filter.qualities == b.filter.qualities, false)
  h.eq(a.filter.qualities == D.filter.qualities, false)
  a.filter.qualities[0] = false
  h.eq(b.filter.qualities[0], true)
  h.eq(D.filter.qualities[0], true)
  local r = DB.applyDefaults({ filter = { qualities = { [1] = false } } }, D)
  h.eq(r.filter.qualities[1], false)
  h.eq(r.filter.qualities[2], true)
  h.eq(D.filter.qualities[1], true)
end)
