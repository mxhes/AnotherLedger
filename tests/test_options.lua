local h = ...
local ns = h.load({ "Util.lua", "Money.lua", "Theme.lua", "Tooltip.lua", "DB.lua", "Sources/Sources.lua", "Sources/TSM.lua", "Sources/Auctionator.lua", "Options.lua" })
local O = ns.Options

local function db(settings)
  return { settings = settings or {} }
end

h.test("Options: the built-in options are registered in panel order", function()
  local keys = {}
  for _, s in ipairs(O.list()) do keys[#keys + 1] = s.key end
  h.eq(keys, { "alpha", "brightness", "windowScale", "lockWindow", "startHidden", "combatHide",
    "keepSession", "priceSource", "tsmSource", "showMarket", "saleRateGood", "saleRateOk",
    "soldHigh", "soldMedium", "refreshSeconds", "staleHours", "defaultSort",
    "goldDisplay", "coinIcons", "includeGold", "alertGold", "alertSound", "countCrafted", "afkPause", "instanceSession",
    "showCurrencies", "dailyFarm", "dailyFarmMinutes", "showTopFinds", "showFooterGold", "compactDrops", "showIcons", "fontFace", "fontSizeRows", "fontSizeTotals",
    "fontSizeTitles", "minimapButton", "minimapReset",
    "exportHistory", "historyLimit" })
  -- every option but a button has its default in DB.defaults.settings
  for _, s in ipairs(O.list()) do
    if s.type ~= "button" then h.eq(ns.DB.defaults.settings[s.key] ~= nil, true, s.key) end
    h.eq(O.HEIGHTS[s.type] ~= nil, true, s.key)
  end
end)

h.test("Options.normalize: slider clamps and snaps, falls back to the default", function()
  local a = O.spec("alpha")
  h.eq(O.normalize(a, 0.5), 0.5)
  h.eq(O.normalize(a, 5), 1)
  h.eq(O.normalize(a, -1), 0)
  h.eq(O.normalize(a, 0.52), 0.5)
  h.eq(O.normalize(a, 0.3), 0.3)
  h.eq(O.normalize(a, "x"), 1)
  h.eq(O.normalize(a, 0 / 0), 1)
end)

h.test("Options.normalize: dropdown only takes a listed choice, checkbox a boolean", function()
  local p, c = O.spec("priceSource"), O.spec("combatHide")
  h.eq(O.normalize(p, "tsm"), "tsm")
  h.eq(O.normalize(p, "auctionator"), "auctionator")
  h.eq(O.normalize(p, "nope"), "auto")
  h.eq(O.normalize(p, nil), "auto")
  h.eq(O.normalize(c, true), true)
  h.eq(O.normalize(c, "yes"), false)
end)

h.test("Options.get / set store in db.settings and call apply", function()
  local applied
  local spec = O.spec("alpha")
  local old = spec.apply
  spec.apply = function(v) applied = v end
  local d = db({ alpha = 0.7 })
  h.eq(O.get(d, "alpha"), 0.7)
  h.eq(O.get(db(), "alpha"), 1) -- missing -> default
  h.eq(O.set(d, "alpha", 0.42), 0.4)
  h.eq(d.settings.alpha, 0.4)
  h.eq(applied, 0.4)
  h.eq(O.set(d, "nope", 1), nil)
  spec.apply = old
end)

h.test("Options.applyAll repairs invalid saved values", function()
  local d = db({ alpha = "bad", priceSource = "x", combatHide = 3 })
  O.applyAll(d)
  h.eq(d.settings.alpha, 1)
  h.eq(d.settings.priceSource, "auto")
  h.eq(d.settings.combatHide, false)
end)

h.test("Options.define: a new option is picked up and listed, redefining replaces", function()
  local n = #O.list()
  O.define({ key = "demoFlag", type = "checkbox", label = "Demo" })
  h.eq(#O.list(), n + 1)
  h.eq(O.spec("demoFlag").label, "Demo")
  O.define({ key = "demoFlag", type = "checkbox", label = "Demo 2" })
  h.eq(#O.list(), n + 1)
  h.eq(O.spec("demoFlag").label, "Demo 2")
  -- unknown types are rejected
  h.eq(pcall(O.define, { key = "bad", type = "knob", label = "x" }), false)
  -- remove the demo again
  table.remove(O.specs, #O.specs)
  O.byKey.demoFlag = nil
end)

h.test("Options.layout stacks the blocks with a gap", function()
  local specs = O.list()
  local L = O.layout(specs)
  local y = 0
  for _, spec in ipairs(specs) do
    h.eq(L.tops[spec.key], y, spec.key)
    y = y + O.HEIGHTS[spec.type] + O.GAP
  end
  h.eq(L.height, y - O.GAP)
  h.eq(O.layout({}).height, 0)
end)

h.test("Options.layout: columns split the blocks, each column stacks from the top", function()
  local specs = O.list()
  local L = O.layout(specs, 2)
  local seen, last = { 0, 0 }, 1
  for _, spec in ipairs(specs) do
    local col = L.cols[spec.key]
    h.eq(col >= last, true, spec.key) -- columns fill in order
    last = col
    if seen[col] == 0 then h.eq(L.tops[spec.key], 0, spec.key) end
    seen[col] = seen[col] + 1
  end
  h.eq(seen[1] > 0 and seen[2] > 0, true)
  h.eq(L.height < O.layout(specs, 1).height, true)
end)

h.test("Options.normalize: text is trimmed and falls back when empty, tsmSource and the new ranges", function()
  local t = O.spec("tsmSource")
  h.eq(O.normalize(t, "  DBMinBuyout "), "DBMinBuyout")
  h.eq(O.normalize(t, "   "), "DBMarket")
  h.eq(O.normalize(t, 5), "DBMarket")
  h.eq(O.normalize(O.spec("windowScale"), 3), 1.5)
  h.eq(O.normalize(O.spec("refreshSeconds"), 7), 10)
  h.eq(O.normalize(O.spec("staleHours"), 100), 72)
  h.eq(O.normalize(O.spec("defaultSort"), "zzz"), "ah")
  h.eq(O.normalize(O.spec("goldDisplay"), "gold"), "gold")
  h.eq(O.normalize(O.spec("alertGold"), -1), -1)
end)

h.test("Options: daily farm is on by default with a 20 minute minimum (5..120)", function()
  h.eq(O.get(db(), "dailyFarm"), true)
  h.eq(O.get(db(), "dailyFarmMinutes"), 20)
  h.eq(O.normalize(O.spec("dailyFarmMinutes"), 500), 120)
  h.eq(O.normalize(O.spec("dailyFarmMinutes"), 1), 5)
  h.eq(O.normalize(O.spec("dailyFarmMinutes"), 23), 25)
end)

h.test("Options.applyAll skips buttons", function()
  local d = db({})
  O.applyAll(d)
  h.eq(d.settings.minimapReset, nil)
end)

h.test("Options: the window sliders cover 0..100 % (brightness 0..200 %)", function()
  local function range(key)
    local s = O.spec(key)
    return { s.min, s.max, s.type }
  end
  h.eq(range("alpha"), { 0, 1, "slider" })
  h.eq(range("brightness"), { 0, 2, "slider" })
  h.eq(O.normalize(O.spec("brightness"), 1.5), 1.5)
  h.eq(O.normalize(O.spec("alpha"), 0), 0)
  h.eq(O.valueText(O.spec("brightness"), 1.5), "150%")
end)

h.test("Options.valueText: formatter, choice label, plain value", function()
  h.eq(O.valueText(O.spec("alpha"), 0.35), "35%")
  h.eq(O.valueText(O.spec("priceSource"), "tsm"), "TSM")
  h.eq(O.valueText({ type = "checkbox" }, true), "On")
  h.eq(O.valueText({ type = "checkbox" }, false), "Off")
end)

h.test("Options: number option normalizes to a whole number, negatives mean unlimited", function()
  local s = O.spec("historyLimit")
  h.eq(s.type, "number")
  h.eq(O.normalize(s, 20), 20)
  h.eq(O.normalize(s, 0), 0)
  h.eq(O.normalize(s, 7.9), 7)
  h.eq(O.normalize(s, -5), -1)
  h.eq(O.normalize(s, "x"), 50)
  h.eq(O.normalize(s, 0 / 0), 50)
  h.eq(O.valueText(s, -1), "Unlimited")
  h.eq(O.valueText(s, 12), "12")
end)

h.test("Options.parseNumber: digits, empty / unlimited words, garbage", function()
  h.eq(O.parseNumber("25"), 25)
  h.eq(O.parseNumber("  0 "), 0)
  h.eq(O.parseNumber(""), -1)
  h.eq(O.parseNumber("Unlimited"), -1)
  h.eq(O.parseNumber("inf"), -1)
  h.eq(O.parseNumber("-1"), -1)
  h.eq(O.parseNumber("\226\136\158"), -1)
  h.eq(O.parseNumber("12x"), nil)
  h.eq(O.parseNumber("-4"), nil)
  h.eq(O.parseNumber(nil), nil)
end)

h.test("Options: historyLimit apply prunes the saved history", function()
  ns.History = { prune = function(list, v) list.pruned = v end }
  ns.chardb = { history = {} }
  O.set(db(), "historyLimit", 3)
  h.eq(ns.chardb.history.pruned, 3)
  ns.History, ns.chardb = nil, nil
end)

h.test("Options.entries: a header per section, every option exactly once, in section order", function()
  local entries = O.entries()
  local headers, seen, section = {}, {}, nil
  for _, e in ipairs(entries) do
    if e.type == "header" then
      headers[#headers + 1] = e.label
      section = e.key:match("^header:(.+)$")
    else
      h.eq(seen[e.key], nil, e.key)
      seen[e.key] = true
      h.eq(e.category, section, e.key) -- listed under its own section
    end
  end
  h.eq(headers, { "Window", "Prices", "Display", "Session and alerts" })
  for _, s in ipairs(O.list()) do h.eq(seen[s.key], true, s.key) end
end)

h.test("Options.sections: one per category in order, every option once, in its own section", function()
  local ids, seen = {}, {}
  for _, s in ipairs(O.sections()) do
    ids[#ids + 1] = s.id
    h.eq(#s.specs > 0, true, s.id)
    for _, spec in ipairs(s.specs) do
      h.eq(seen[spec.key], nil, spec.key)
      seen[spec.key] = true
      h.eq(spec.category, s.id, spec.key)
    end
  end
  h.eq(ids, { "window", "prices", "display", "session" }) -- no empty Other
  for _, s in ipairs(O.list()) do h.eq(seen[s.key], true, s.key) end
end)

h.test("Options.entries: an option without a known category goes to Other", function()
  local spec = O.define({ key = "zzTest", type = "checkbox", label = "T" })
  local entries = O.entries()
  h.eq(entries[#entries - 1].label, "Other")
  h.eq(entries[#entries].key, "zzTest")
  for i, s in ipairs(O.specs) do if s == spec then table.remove(O.specs, i) end end
  O.byKey.zzTest = nil
end)

h.test("Options.layout: a header always sits right above its first option, also across columns", function()
  local entries = O.entries()
  local L = O.layout(entries, 2)
  for i, e in ipairs(entries) do
    if e.type == "header" then
      local nextEntry = entries[i + 1]
      h.eq(L.cols[nextEntry.key], L.cols[e.key], e.key)
      h.eq(L.tops[nextEntry.key], L.tops[e.key] + O.HEIGHTS.header + O.GAP, e.key)
    end
  end
end)

h.test("Options: Top finds and the Raw gold footer row show by default", function()
  h.eq(O.get(db(), "showTopFinds"), true)
  h.eq(O.get(db(), "showFooterGold"), true)
end)

h.test("Options: compact mode shows 4 last drops by default (0..4)", function()
  h.eq(O.get(db(), "compactDrops"), 4)
  h.eq(O.normalize(O.spec("compactDrops"), 9), 4)
  h.eq(O.normalize(O.spec("compactDrops"), -1), 0)
end)

h.test("Options: the text sizes are dropdowns of px sizes", function()
  for key, range in pairs({ fontSizeRows = { 8, 18 }, fontSizeTotals = { 8, 18 }, fontSizeTitles = { 10, 24 } }) do
    local s = O.spec(key)
    h.eq(s.type, "dropdown")
    local c = O.choices(s)
    h.eq(#c, range[2] - range[1] + 1)
    h.eq(c[1], { value = range[1], label = range[1] .. " px" })
    h.eq(c[#c].value, range[2])
  end
  local rows = O.spec("fontSizeRows")
  h.eq(O.normalize(rows, 15), 15) -- a size saved by the old slider stays
  h.eq(O.normalize(rows, 30), 12) -- outside the list: the default
  h.eq(O.valueText(rows, 12), "12 px")
end)

h.test("Options: every option has a short label and a tooltip", function()
  for _, s in ipairs(O.list()) do
    h.eq(type(s.tooltip) == "string" and s.tooltip ~= "", true, s.key .. " tooltip")
    h.eq(#s.label <= 24, true, s.key .. " label is short: " .. s.label)
  end
end)

h.test("Options.tooltip: title, what it does, the default", function()
  local text = ns.Tooltip.text
  local lock = O.tooltip(O.spec("lockWindow"))
  h.eq(lock.title, "Lock window")
  h.eq(text(lock), "Lock window\nThe window can't be moved or resized.\nDefault: Off")
  h.eq(text(O.tooltip(O.spec("alpha"))):match("[^\n]+$"), "Default: 100%")
  h.eq(text(O.tooltip(O.spec("defaultSort"))):match("[^\n]+$"), "Default: Best value")
  h.eq(text(O.tooltip(O.spec("fontSizeTitles"))):match("[^\n]+$"), "Default: 16 px")
  h.eq(text(O.tooltip(O.spec("alertGold"))):match("[^\n]+$"), "Default: Off")
  h.eq(text(O.tooltip(O.spec("historyLimit"))):match("[^\n]+$"), "Default: 50")
  -- a button has no default
  h.eq(text(O.tooltip(O.spec("exportHistory"))):find("Default", 1, true), nil)
  -- the description wraps, the default is a quiet note
  local ops = ns.Tooltip.render(lock)
  h.eq(ops[2].wrap, true)
  h.eq(ops[3].color, ns.Theme.colors.tipNote)
end)

h.test("Options: the sale rate and volume cutoffs stay in order", function()
  local d = db({ saleRateGood = 0.5, saleRateOk = 0.1, soldHigh = 100, soldMedium = 10 })
  ns.db = d
  O.set(d, "saleRateOk", 0.8) -- above "sells well": that one follows
  h.eq(d.settings.saleRateGood, 0.8)
  O.set(d, "saleRateGood", 0.3) -- below "sells okay": that one follows
  h.eq(d.settings.saleRateOk, 0.3)
  O.set(d, "soldMedium", 200)
  h.eq(d.settings.soldHigh, 200)
  O.set(d, "soldHigh", -1) -- empty = never High volume: Medium stays free
  h.eq(d.settings.soldMedium, 200)
  ns.db = nil
end)
