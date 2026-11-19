local h = ...
local ns = h.load({ "Util.lua", "Money.lua", "Theme.lua", "Tooltip.lua", "DB.lua", "Sources/Sources.lua", "Sources/TSM.lua", "Sources/Auctionator.lua", "Sources/Scan.lua", "Options.lua" })
local O = ns.Options

local function db(settings)
  return { settings = settings or {} }
end

h.test("Options: the built-in options are registered in panel order", function()
  local keys = {}
  for _, s in ipairs(O.list()) do keys[#keys + 1] = s.key end
  h.eq(keys, { "alpha", "brightness", "windowScale", "lockWindow", "snapToGrid", "showOnLoot", "showInInstance", "hideInCities", "startHidden", "combatHide",
    "keepSession", "countCrafted", "priceSource", "tsmSource", "scanPrice", "scanReminder", "showMarket", "saleRateGood", "saleRateOk",
    "soldHigh", "soldMedium", "refreshSeconds", "staleHours", "ahCut", "ahMinGain", "destroyMode", "defaultSort",
    "goldDisplay", "coinIcons", "rawGold",
    "sessionChat", "resetNote", "afkPause", "cityPause", "instanceSession", "zoneSession", "zoneSessionMinutes", "minSessionMinutes",
    "alertGold", "alertSound", "goalGold", "goalMinutes",
    "showCurrencies", "hideWorthless", "itemTooltipDrops", "dailyFarm", "dailyFarmMinutes", "dailyFarmLevel", "accountZones", "showTopFinds", "compactDrops",
    "showIcons", "unitPrice", "ignoredItems", "keptItems", "followLoot", "fontFace", "fontOutline", "fontShadow", "fontSizeRows", "fontSizeTotals",
    "fontSizeTitles", "minimapButton", "minimapReset",
    "exportHistory", "clearHistory", "historyLimit", "tradeLogDays",
    "colorPreset", "colorText", "colorTitles", "colorHints", "colorVendor", "colorAuction", "colorDestroy", "colorTipLabels",
    "colorBackground", "colorBorder", "colorButtons", "resetColors", "deleteColorPreset" })
  -- every option but a button has its default in DB.defaults.settings
  for _, s in ipairs(O.list()) do
    if s.type ~= "button" and not s.get then h.eq(ns.DB.defaults.settings[s.key] ~= nil, true, s.key) end
    h.eq(O.HEIGHTS[s.type] ~= nil, true, s.key)
  end
end)

h.test("Options.normalize: scan price is market or lowest", function()
  local spec = O.spec("scanPrice")
  h.eq(O.normalize(spec, "lowest"), "lowest")
  h.eq(O.normalize(spec, "bogus"), "market")
  h.eq(ns.DB.defaults.settings.scanPrice, "market")
  h.eq(ns.DB.defaults.settings.scanReminder, true)
end)

h.test("Options.normalize: Trade log kept is 30, 90, 180 or 365 days, account-wide", function()
  local spec = O.spec("tradeLogDays")
  h.eq(spec.account, true)
  h.eq(O.normalize(spec, 180), 180)
  h.eq(O.normalize(spec, 7), 90)
  h.eq(ns.DB.defaults.settings.tradeLogDays, 90)
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

h.test("Options: TSM price is a dropdown that keeps any typed price", function()
  local t = O.spec("tsmSource")
  h.eq(t.type, "dropdown")
  h.eq(O.normalize(t, "  DBRecent "), "DBRecent")
  h.eq(O.normalize(t, "first(DBMinBuyout, DBMarket)"), "first(DBMinBuyout, DBMarket)")
  h.eq(O.normalize(t, ""), "DBMarket")
  h.eq(O.normalize(t, 5), "DBMarket")
  local saved = ns.db
  ns.db = db({ tsmSource = "DBMarket" })
  local values = {}
  for _, c in ipairs(O.choices(t)) do values[#values + 1] = c.value end
  h.eq(values, { "DBMarket", "DBMinBuyout", "DBRegionMarketAvg", "DBRecent", "DBHistorical", O.CUSTOM })
  ns.db = db({ tsmSource = "max(DBMarket, 100g)" })
  values = {}
  for _, c in ipairs(O.choices(t)) do values[#values + 1] = c.value end
  h.eq(values, { "DBMarket", "DBMinBuyout", "DBRegionMarketAvg", "DBRecent", "DBHistorical", "max(DBMarket, 100g)", O.CUSTOM })
  h.eq(O.valueText(t, "max(DBMarket, 100g)"), "max(DBMarket, 100g)")
  ns.db = saved
end)

h.test("Options.pick: Custom... asks for a TSM price and leaves the value until then", function()
  local saved, savedUI = ns.db, ns.UI
  local d = db({ tsmSource = "DBRecent" })
  ns.db = d
  local asked
  ns.UI = { Widgets = { prompt = function(text, accept, initial, fn) asked = { initial = initial, fn = fn } end } }
  h.eq(O.pick(d, "tsmSource", O.CUSTOM), "DBRecent")
  h.eq(d.settings.tsmSource, "DBRecent")
  h.eq(asked.initial, "DBRecent")
  asked.fn("  min(DBMarket, DBRecent) ")
  h.eq(d.settings.tsmSource, "min(DBMarket, DBRecent)")
  ns.db, ns.UI = saved, savedUI
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
  h.eq(O.valueText(O.spec("priceSource"), "tsm"), "TSM (not loaded)")
  _G.TSM_API = {}
  h.eq(O.valueText(O.spec("priceSource"), "tsm"), "TSM")
  _G.TSM_API = nil
  h.eq(O.valueText({ type = "checkbox" }, true), "On")
  h.eq(O.valueText({ type = "checkbox" }, false), "Off")
end)

h.test("Options.buttonText: a choice's short text, else valueText", function()
  local spec = { type = "dropdown", choices = {
    { value = "auto", label = "Auto (A, then B, then C)", short = "Auto" },
    { value = "a", label = "A" },
  } }
  h.eq(O.buttonText(spec, "auto"), "Auto")
  h.eq(O.buttonText(spec, "a"), "A")
  h.eq(O.buttonText(O.spec("priceSource"), "auto"), "Auto")
  h.eq(O.buttonText(O.spec("alpha"), 0.35), "35%")
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
  h.eq(ids, { "window", "prices", "display", "session", "history", "look" }) -- no empty Other
  for _, s in ipairs(O.list()) do h.eq(seen[s.key], true, s.key) end
end)

h.test("Options.sections: an option without a known category goes to Other", function()
  local spec = O.define({ key = "zzTest", type = "checkbox", label = "T" })
  local sections = O.sections()
  h.eq(sections[#sections].label, "Other")
  h.eq(sections[#sections].specs, { spec })
  for i, s in ipairs(O.specs) do if s == spec then table.remove(O.specs, i) end end
  O.byKey.zzTest = nil
end)

h.test("Options.layout: a header or a withPrevious option never starts a column", function()
  local specs = {
    { key = "a", type = "slider" }, { key = "b", type = "slider" },
    { key = "h", type = "header" }, { key = "c", type = "slider" },
    { key = "d", type = "slider" }, { key = "e", type = "slider", withPrevious = true },
  }
  local L = O.layout(specs, 2)
  h.eq(L.cols.c, L.cols.h)
  h.eq(L.tops.c, L.tops.h + O.HEIGHTS.header + O.GAP)
  h.eq(L.cols.e, L.cols.d)
  -- the Prices tab: Medium volume from stays under High volume from
  local prices
  for _, s in ipairs(O.sections()) do if s.id == "prices" then prices = s.specs end end
  local P = O.layout(prices, 2)
  h.eq(P.cols.soldMedium, P.cols.soldHigh)
end)

h.test("Options: Top finds and the Raw gold footer row show by default", function()
  h.eq(O.get(db(), "showTopFinds"), true)
  h.eq(O.get(db(), "rawGold"), "row")
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
  h.eq(text(O.tooltip(O.spec("defaultSort"))):match("[^\n]+$"), "Default: Value")
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

h.test("Options: color defaults match the theme colors they set", function()
  for _, o in ipairs(O.COLOR_OPTIONS) do
    local default = O.defaultFor(o[1])
    for _, key in ipairs(o[4]) do
      h.eq(ns.Theme.colorToHex(ns.Theme.colors[key]), default, o[1] .. " -> " .. key)
    end
  end
end)

h.test("Options: default colors are white text, cream vendor, blue AH, grey destroy", function()
  local d = function(k) return O.defaultFor(k) end
  h.eq(d("colorText"), "ffffff")
  h.eq(d("colorVendor"), "eddeb8")
  h.eq(d("colorAuction"), "80d1ff")
  h.eq(d("colorDestroy"), "b3b3b3")
  h.eq(ns.Theme.colors.tipValue, { 1, 1, 1, 1 })
end)

h.test("Options.normalize: a color takes rrggbb (any case, # allowed), else the default", function()
  local spec = O.spec("colorVendor")
  h.eq(O.normalize(spec, "FF8000"), "ff8000")
  h.eq(O.normalize(spec, " #00aaFF "), "00aaff")
  for _, bad in ipairs({ "fff", "zzzzzz", "ff80001", 5, false }) do
    h.eq(O.normalize(spec, bad), "eddeb8", tostring(bad))
  end
  h.eq(O.valueText(spec, "ff8000"), "#FF8000")
end)

h.test("Options.set on a color changes the theme color in place, alpha kept", function()
  local db = { settings = {} }
  local panel = ns.Theme.colors.panelTint
  local alpha = panel[4]
  O.set(db, "colorBackground", "ff0000")
  h.eq(ns.Theme.colors.panelTint == panel, true)
  h.eq({ panel[1], panel[2], panel[3], panel[4] }, { 1, 0, 0, alpha })
  O.set(db, "colorText", "000000")
  h.eq(ns.Theme.colors.ink[1], 0)
  h.eq(ns.Theme.colors.buttonText[1], 0)
  local saved = ns.db
  ns.db = db
  O.spec("resetColors").action()
  ns.db = saved
  h.eq(db.settings.colorBackground, "261a0f")
  h.eq(ns.Theme.colorToHex(ns.Theme.colors.ink), "ffffff")
end)

-- Color presets ---------------------------------------------------------------

local function hex(key) return ns.Theme.colorToHex(ns.Theme.colors[key]) end
local function presetHex(id, key) return ns.Theme.preset(id).colors[key] end

h.test("colorPreset is the first color option of Look: four presets and Save as preset", function()
  local first
  for _, s in ipairs(O.list()) do
    if s.category == "look" and s.key:match("^color") then first = s; break end
  end
  h.eq(first.key, "colorPreset")
  h.eq(first.type, "dropdown")
  local values = {}
  for _, c in ipairs(O.choices(first)) do values[#values + 1] = c.value end
  h.eq(values, { "anotherledger", "blizzard", "midnight", "tsm", O.CUSTOM })
  h.eq(#first.label <= 24, true)
  h.eq(O.defaultFor("colorPreset"), "anotherledger")
  -- The save entry is never a stored value; the removed Parchment neither.
  h.eq(O.normalize(first, O.CUSTOM), "anotherledger")
  h.eq(O.normalize(first, "parchment"), "anotherledger")
end)

h.test("picking a preset writes the 11 colors", function()
  local d = db()
  ns.db = d
  O.pick(d, "colorPreset", "midnight")
  for _, o in ipairs(O.COLOR_OPTIONS) do
    h.eq(d.settings[o[1]], presetHex("midnight", o[4][1]), o[1])
  end
  h.eq(hex("panelTint"), presetHex("midnight", "panelTint"))
  h.eq(hex("divider"), presetHex("midnight", "divider"))
  O.pick(d, "colorPreset", "anotherledger")
  ns.db = nil
end)

h.test("own color preset: saved from the current colors, listed, picked back", function()
  local d = db()
  ns.db = d
  O.pick(d, "colorPreset", "midnight")
  O.pick(d, "colorText", "123456")
  h.eq(O.saveColorPreset(d, "  Mine  "), "user:Mine")
  h.eq(d.settings.colorPreset, "user:Mine")
  h.eq(d.colorPresets[1].base, "midnight")
  h.eq(d.colorPresets[1].colors.colorText, "123456")
  h.eq(O.presetEdited(d.settings), false)
  h.eq(O.valueText(O.spec("colorPreset"), "user:Mine"), "Mine")
  h.eq(hex("ink"), "123456")
  -- listed after the built-in ones, before the save entry
  local values = {}
  for _, c in ipairs(O.choices(O.spec("colorPreset"))) do values[#values + 1] = c.value end
  h.eq(values, { "anotherledger", "blizzard", "midnight", "tsm", "user:Mine", O.CUSTOM })
  -- another preset, then back: the own colors on the base's other colors
  O.pick(d, "colorPreset", "tsm")
  h.eq(d.settings.colorText, presetHex("tsm", "ink"))
  O.pick(d, "colorPreset", "user:Mine")
  h.eq(d.settings.colorText, "123456")
  h.eq(d.settings.colorBackground, presetHex("midnight", "panelTint"))
  h.eq(hex("divider"), presetHex("midnight", "divider"))
  h.eq(hex("ink"), "123456")
  O.pick(d, "colorPreset", "anotherledger")
  ns.db = nil
end)

h.test("own color preset: names are checked, a taken one needs replace", function()
  local d = db()
  ns.db = d
  h.eq(select(2, O.saveColorPreset(d, "   ")), "Enter a name.")
  h.eq(select(2, O.saveColorPreset(d, string.rep("x", 33))), "The name is too long.")
  h.eq(select(2, O.saveColorPreset(d, "midnight")), "A built-in color preset has this name.")
  h.eq(select(2, O.saveColorPreset(d, "TSM-style")), "A built-in color preset has this name.")
  h.eq(O.saveColorPreset(d, "Mine"), "user:Mine")
  O.pick(d, "colorText", "abcdef")
  local id, err, taken = O.saveColorPreset(d, "MINE")
  h.eq(id, nil)
  h.eq(err, "exists")
  h.eq(taken, "Mine")
  h.eq(O.saveColorPreset(d, "MINE", true), "user:Mine")
  h.eq(#d.colorPresets, 1)
  h.eq(d.colorPresets[1].colors.colorText, "abcdef")
  O.pick(d, "colorPreset", "anotherledger")
  ns.db = nil
end)

h.test("own color preset: delete keeps every profile's colors", function()
  local d = db()
  d.profiles = { Default = d.settings, Other = { colorPreset = "user:Mine" } }
  ns.db = d
  O.pick(d, "colorPreset", "blizzard")
  O.pick(d, "colorBorder", "112233")
  O.saveColorPreset(d, "Mine")
  h.eq(select(2, O.deleteColorPreset("blizzard")), "Pick one of your own color presets first.")
  h.eq(O.deleteColorPreset("user:Mine"), true)
  h.eq(#d.colorPresets, 0)
  h.eq(d.settings.colorPreset, "blizzard")
  h.eq(d.settings.colorBorder, "112233")
  h.eq(d.profiles.Other.colorPreset, "blizzard")
  h.eq(d.profiles.Other.colorBorder, "112233")
  h.eq(d.profiles.Other.colorText, presetHex("blizzard", "ink"))
  h.eq(O.presetEdited(d.settings), true)
  O.pick(d, "colorPreset", "anotherledger")
  ns.db = nil
end)

h.test("Save as preset opens a name prompt and stores nothing itself", function()
  local d = db()
  ns.db = d
  local asked, savedUI = nil, ns.UI
  ns.UI = { Widgets = { prompt = function(text, accept, initial, fn) asked = fn end } }
  h.eq(O.pick(d, "colorPreset", O.CUSTOM), "anotherledger")
  h.eq(d.settings.colorPreset, nil)
  asked("Night")
  h.eq(d.settings.colorPreset, "user:Night")
  ns.UI = savedUI
  O.pick(d, "colorPreset", "anotherledger")
  ns.db = nil
end)

h.test("applyAll keeps tweaks over preset", function()
  local d = db({ colorPreset = "tsm", colorText = "ff0000" })
  ns.db = d
  O.applyAll(d)
  h.eq(hex("ink"), "ff0000")
  h.eq(hex("panelTint"), presetHex("tsm", "panelTint"))
  h.eq(hex("divider"), presetHex("tsm", "divider"))
  h.eq(d.settings.colorText, "ff0000")
  O.pick(d, "colorPreset", "anotherledger")
  ns.db = nil
end)

h.test("edited marker after a color tweak", function()
  local d = db()
  ns.db = d
  local spec = O.spec("colorPreset")
  O.pick(d, "colorPreset", "midnight")
  h.eq(O.valueText(spec, "midnight"), "Midnight")
  O.set(d, "colorText", "ff0000")
  h.eq(O.valueText(spec, "midnight"), "Midnight (edited)")
  O.pick(d, "colorPreset", "anotherledger")
  ns.db = nil
end)

h.test("color default is the active preset's color", function()
  local d = db()
  ns.db = d
  O.pick(d, "colorPreset", "midnight")
  h.eq(O.defaultFor("colorBackground"), presetHex("midnight", "panelTint"))
  h.eq(O.defaultFor("colorBackground", { colorPreset = "tsm" }), presetHex("tsm", "panelTint"))
  O.pick(d, "colorPreset", "anotherledger")
  ns.db = nil
end)

h.test("Reset colors goes back to the chosen preset's colors", function()
  local d = db()
  ns.db = d
  O.pick(d, "colorPreset", "midnight")
  O.pick(d, "colorText", "123456")
  h.eq(O.presetEdited(d.settings), true)
  O.spec("resetColors").action()
  h.eq(d.settings.colorPreset, "midnight")
  h.eq(d.settings.colorText, presetHex("midnight", "ink"))
  h.eq(O.presetEdited(d.settings), false)
  h.eq(hex("panelTint"), presetHex("midnight", "panelTint"))
  O.pick(d, "colorPreset", "anotherledger")
  ns.db = nil
end)

h.test("raw gold is one dropdown: counted in Total and its own row, each on or off", function()
  h.eq(O.spec("rawGold").type, "dropdown")
  h.eq(O.spec("includeGold"), nil)
  h.eq(O.spec("showFooterGold"), nil)
  local values = {}
  for _, c in ipairs(O.choices(O.spec("rawGold"))) do values[#values + 1] = c.value end
  h.eq(values, { "row", "total", "apart", "off" })
end)

h.test("Session tab: drop alert and both goals stand together in one column", function()
  local specs = {}
  for _, s in ipairs(O.list()) do if s.category == "session" then specs[#specs + 1] = s end end
  local L = O.layout(specs, 2)
  local order, col = {}, L.cols.alertGold
  for _, s in ipairs(specs) do if L.cols[s.key] == col then order[#order + 1] = s.key end end
  local at
  for i, k in ipairs(order) do if k == "alertGold" then at = i end end
  h.eq({ order[at], order[at + 1], order[at + 2], order[at + 3] },
    { "alertGold", "alertSound", "goalGold", "goalMinutes" })
end)

h.test("tooltip titles and notes are not tied to the panel colors", function()
  for _, o in ipairs(O.COLOR_OPTIONS) do
    for _, key in ipairs(o[4]) do
      if o[1] ~= "colorTipLabels" then h.eq(key:sub(1, 3) ~= "tip", true, o[1] .. " -> " .. key) end
    end
  end
end)

h.test("account options read and write db.account", function()
  local d = db()
  for _, key in ipairs({ "historyLimit", "accountZones", "minimapButton" }) do
    h.eq(O.spec(key).account, true, key)
  end
  O.set(d, "historyLimit", -1)
  h.eq(d.account.historyLimit, -1)
  h.eq(d.settings.historyLimit, nil)
  h.eq(O.get(d, "historyLimit"), -1)
  h.eq(O.get(db(), "accountZones"), true) -- default without db.account
end)

h.test("Options.inactive: price options without their addon say why", function()
  h.eq(type(O.inactive(O.spec("tsmSource"))), "string")
  h.eq(type(O.inactive(O.spec("showMarket"))), "string")
  h.eq(type(O.inactive(O.spec("destroyMode"))), "string")
  h.eq(O.inactive(O.spec("scanReminder")), nil)
  h.eq(O.inactive(O.spec("priceSource")), nil)
  _G.Auctionator = { API = {} }
  h.eq(O.inactive(O.spec("destroyMode")), nil)
  h.eq(type(O.inactive(O.spec("scanReminder"))), "string")
  h.eq(type(O.inactive(O.spec("saleRateGood"))), "string")
  _G.Auctionator = nil
  h.eq(O.inactive({ inactive = function() error("x") end }), nil)
  h.eq(O.inactive({ inactive = function() return "" end }), nil)
  local warned = false
  for _, line in ipairs(O.tooltip(O.spec("tsmSource")).lines) do
    if line.kind == "warn" then warned = true end
  end
  h.eq(warned, true)
end)
