local h = ...
local function load()
  return h.load({ "Util.lua", "Money.lua", "Theme.lua", "DB.lua", "Sources/Sources.lua", "Options.lua",
    "UI/Summary.lua", "UI/Fonts.lua" })
end

h.test("Fonts.scaledSizes: rounds the scaled pixel sizes", function()
  local ns = load()
  h.eq(ns.UI.Fonts.scaledSizes({ rowHeight = 40, topRowHeight = 20 }, { "rowHeight", "topRowHeight" }, 1.25),
    { rowHeight = 50, topRowHeight = 25 })
  h.eq(ns.UI.Fonts.scaledSizes({ rowHeight = 40 }, { "rowHeight" }, 0.8), { rowHeight = 32 })
end)

h.test("Fonts.install: the default sizes change nothing", function()
  local ns = load()
  local before = ns.Theme.sizes.rowHeight
  ns.UI.Fonts.install({ settings = {} })
  h.eq(ns.Theme.sizes.rowHeight, before)
  h.eq(ns.Theme.fonts.body, "GameFontHighlight")
end)

h.test("Fonts.install: a scaled group gets its own font objects and taller rows", function()
  local ns = load()
  local created = {}
  local function fakeFont(name)
    local f = { name = name }
    function f:CopyFontObject(base) self.base = base end
    function f:GetFont() return "file.ttf", 12, "" end
    function f:SetFont(file, size, flags) self.file, self.size, self.flags = file, size, flags end
    created[name] = f
    return f
  end
  _G.CreateFont = fakeFont
  _G.GameFontHighlight = fakeFont("GameFontHighlight")
  _G.GameFontHighlightSmall = fakeFont("GameFontHighlightSmall")
  local ok, err = pcall(function()
    ns.UI.Fonts.install({ settings = { fontSizeRows = 18 } })
  end)
  _G.CreateFont, _G.GameFontHighlight, _G.GameFontHighlightSmall = nil, nil, nil
  assert(ok, err)
  h.eq(ns.Theme.sizes.rowHeight, 45) -- 30 * 18 / 12
  h.eq(ns.Theme.sizes.iconSize, 30) -- the icon scales with the list text
  h.eq(ns.Theme.fonts.body, "LootPriceBody")
  h.eq(ns.Theme.fonts.rowSmall, "LootPriceRowSmall")
  h.near(created.LootPriceBody.size, 18)
  h.eq(created.LootPriceBody.base.name, "GameFontHighlight")
  -- the totals keep their size but are copies too, so the typeface can change live
  h.eq(ns.Theme.fonts.summary, "LootPriceSummary")
  h.eq(created.LootPriceSummary.size, 12)
  h.eq(ns.Theme.fonts.title, "GameFontNormal") -- no such game font in this fake client
  h.eq(ns.Theme.sizes.footerHeight, 4 * ns.Theme.sizes.footerRowHeight)
  h.eq(ns.Theme.sizes.minHeight, ns.UI.Summary.requiredWindowHeight())
end)

h.test("Fonts.install: a larger totals size grows the footer table and the minimum height", function()
  local ns = load()
  _G.CreateFont = function(name)
    local f = {}
    function f:CopyFontObject() end
    function f:GetFont() return "file.ttf", 12, "" end
    function f:SetFont() end
    return f
  end
  local ok, err = pcall(function()
    ns.UI.Fonts.install({ settings = { fontSizeTotals = 15 } })
  end)
  _G.CreateFont = nil
  assert(ok, err)
  local s = ns.Theme.sizes
  h.eq(s.footerRowHeight, 23) -- 18 * 15 / 12, rounded
  h.eq(s.footerNoteHeight, 20)
  h.eq(s.footerHeight, 4 * 23)
  h.eq(s.minHeight, ns.UI.Summary.requiredWindowHeight())
end)

h.test("Fonts.install: the largest totals size widens the table columns and the minimum width", function()
  local ns = load()
  _G.CreateFont = function()
    local f = {}
    function f:CopyFontObject() end
    function f:GetFont() return "file.ttf", 12, "" end
    function f:SetFont() end
    return f
  end
  local ok, err = pcall(function()
    ns.UI.Fonts.install({ settings = { fontSizeTotals = 18 } })
  end)
  _G.CreateFont = nil
  assert(ok, err)
  local s = ns.Theme.sizes
  -- the glyph estimate follows the font, so the /h column (14 glyphs) fits "999g 59s 59c/h"
  h.eq(s.summaryCharPx >= 6.6 * 18 / 12 - 0.5, true)
  -- and the window is never narrower than the widest table line
  h.eq(s.minWidth >= ns.UI.Summary.tableWorstWidth() + 2 * (s.padding + 4), true)
end)

local function fakeClient(files)
  local created = {}
  local function newFont(name)
    local f = { name = name }
    function f:CopyFontObject(base) self.base = base end
    function f:GetFont() return self.file or "Fonts\\FRIZQT__.TTF", self.size or 12, "" end
    function f:SetFont(file, size, flags)
      if files and not files[file] then return false end
      self.file, self.size, self.flags = file, size, flags
      return true
    end
    created[name] = f
    return f
  end
  return created, newFont
end

h.test("Fonts: choices offer the default and the fonts the client loads", function()
  local ns = load()
  local created, newFont = fakeClient({ ["Fonts\\FRIZQT__.TTF"] = true, ["Fonts\\ARIALN.TTF"] = true })
  _G.CreateFont = newFont
  local ok, err = pcall(function()
    local c = ns.UI.Fonts.choices()
    h.eq(c[1], { value = "default", label = "WoW default" })
    h.eq(#c, 3)
    h.eq(c[2].label, "Arial Narrow") -- sorted by name
    -- the option accepts a listed font and falls back to the default for others
    ns.UI.Fonts.choices() -- cached
    h.eq(ns.Options.normalize(ns.Options.spec("fontFace"), "Fonts\\ARIALN.TTF"), "Fonts\\ARIALN.TTF")
    h.eq(ns.Options.normalize(ns.Options.spec("fontFace"), "Fonts\\nope.ttf"), "default")
  end)
  _G.CreateFont = nil
  assert(ok, err)
end)

h.test("Fonts.applyFace: switches every own font object live, default restores the game font", function()
  local ns = load()
  local created, newFont = fakeClient({ ["Fonts\\FRIZQT__.TTF"] = true, ["Fonts\\ARIALN.TTF"] = true })
  _G.CreateFont = newFont
  _G.GameFontHighlight = newFont("GameFontHighlight")
  local ok, err = pcall(function()
    ns.UI.Fonts.install({ settings = { fontFace = "Fonts\\ARIALN.TTF" } })
    h.eq(created.LootPriceBody.file, "Fonts\\ARIALN.TTF")
    ns.Options.set({ settings = {} }, "fontFace", "default") -- apply -> restores
    h.eq(created.LootPriceBody.file, "Fonts\\FRIZQT__.TTF")
    ns.UI.Fonts.applyFace("Fonts\\ARIALN.TTF")
    h.eq(created.LootPriceBody.file, "Fonts\\ARIALN.TTF")
    h.eq(created.LootPriceBody.size, 12) -- size untouched
    ns.UI.Fonts.applyFace("Fonts\\missing.ttf") -- refused: keeps the game font
    h.eq(created.LootPriceBody.file, "Fonts\\FRIZQT__.TTF")
  end)
  _G.CreateFont, _G.GameFontHighlight = nil, nil
  assert(ok, err)
end)

h.test("Fonts.applySizes: a changed size resizes the own font objects live, from the theme's values", function()
  local ns = load()
  local created, newFont = fakeClient()
  _G.CreateFont = newFont
  _G.GameFontHighlight = newFont("GameFontHighlight")
  local ok, err = pcall(function()
    local db = { settings = {} }
    h.eq(ns.UI.Fonts.applySizes(db), false) -- before install: nothing
    ns.UI.Fonts.install(db)
    h.eq(ns.UI.Fonts.applySizes(db), false) -- nothing changed
    db.settings.fontSizeRows = 15
    h.eq(ns.UI.Fonts.applySizes(db), true)
    h.near(created.LootPriceBody.size, 15)
    h.eq(ns.Theme.sizes.rowHeight, 38) -- 30 * 15 / 12, rounded
    db.settings.fontSizeRows = 9
    h.eq(ns.UI.Fonts.applySizes(db), true)
    h.eq(ns.Theme.sizes.rowHeight, 23) -- 30 * 9 / 12 (rounded), not 38 * 9 / 12
    h.near(created.LootPriceBody.size, 9)
    h.eq(created.LootPriceSummary.size, 12) -- other groups untouched
  end)
  _G.CreateFont, _G.GameFontHighlight = nil, nil
  assert(ok, err)
end)

h.test("Fonts.install: the source tag font is pinned to Arial Narrow, whatever the typeface", function()
  local ns = load()
  local created, newFont = fakeClient({ ["Fonts\\FRIZQT__.TTF"] = true, ["Fonts\\ARIALN.TTF"] = true, ["Fonts\\skurri.ttf"] = true })
  _G.CreateFont = newFont
  _G.GameFontHighlightSmall = newFont("GameFontHighlightSmall")
  local ok, err = pcall(function()
    ns.UI.Fonts.install({ settings = {} })
    h.eq(created.LootPriceSourceTag.file, "Fonts\\ARIALN.TTF")
    ns.UI.Fonts.applyFace("Fonts\\skurri.ttf")
    h.eq(created.LootPriceSourceTag.file, "Fonts\\ARIALN.TTF")
    h.eq(created.LootPriceSmall.file, "Fonts\\skurri.ttf")
  end)
  _G.CreateFont, _G.GameFontHighlightSmall = nil, nil
  assert(ok, err)
end)

h.test("Fonts.install: without Arial Narrow the source tag keeps the game font", function()
  local ns = load()
  local created, newFont = fakeClient({ ["Fonts\\FRIZQT__.TTF"] = true })
  _G.CreateFont = newFont
  _G.GameFontHighlightSmall = newFont("GameFontHighlightSmall")
  local ok, err = pcall(function()
    ns.UI.Fonts.install({ settings = {} })
    h.eq(created.LootPriceSourceTag.file, "Fonts\\FRIZQT__.TTF")
  end)
  _G.CreateFont, _G.GameFontHighlightSmall = nil, nil
  assert(ok, err)
end)

h.test("Fonts.flags / shadowOf: outline flags and the shadow on or off", function()
  local F = load().UI.Fonts
  h.eq(F.flags("", "none"), "")
  h.eq(F.flags("MONOCHROME", "none"), "MONOCHROME") -- the game font's own flags
  h.eq(F.flags("", "OUTLINE"), "OUTLINE")
  h.eq(F.flags("", "THICKOUTLINE"), "THICKOUTLINE")
  h.eq(F.flags("", "bogus"), "")
  h.eq(F.shadowOf({ x = 1, y = -1, r = 0, g = 0, b = 0, a = 0.8 }, true), { 1, -1, 0, 0, 0, 0.8 })
  h.eq(F.shadowOf({ x = 0, y = 0, a = 0 }, true), { 1, -1, 0, 0, 0, 1 }) -- a font without one gets one
  h.eq(F.shadowOf(nil, true), { 1, -1, 0, 0, 0, 1 })
  h.eq(F.shadowOf({ x = 2, y = -2, a = 1 }, false), { 0, 0, 0, 0, 0, 0 })
end)

h.test("Fonts.applyStyle: outline and shadow on every own font object, live", function()
  local ns = load()
  local created, newFont = fakeClient()
  _G.CreateFont = function(name)
    local f = newFont(name)
    function f:SetShadowOffset(x, y) self.shadow = { x, y } end
    function f:SetShadowColor(r, g, b, a) self.shadowColor = { r, g, b, a } end
    return f
  end
  local base = newFont("GameFontHighlight")
  function base:GetShadowOffset() return 1, -1 end
  function base:GetShadowColor() return 0, 0, 0, 1 end
  _G.GameFontHighlight = base
  local ok, err = pcall(function()
    ns.UI.Fonts.install({ settings = { fontOutline = "OUTLINE", fontShadow = false } })
    local body = created.LootPriceBody
    h.eq(body.flags, "OUTLINE"); h.eq(body.shadow, { 0, 0 })
    h.eq(ns.UI.Fonts.applyStyle("OUTLINE", false), false) -- nothing changed
    h.eq(ns.UI.Fonts.applyStyle("THICKOUTLINE", true), true)
    h.eq(body.flags, "THICKOUTLINE"); h.eq(body.shadow, { 1, -1 }); h.eq(body.shadowColor, { 0, 0, 0, 1 })
    h.eq(body.size, 12) -- size untouched
    ns.UI.Fonts.applyStyle("none", true)
    h.eq(body.flags, "")
    -- a later size change keeps the outline
    ns.UI.Fonts.applyStyle("OUTLINE", true)
    ns.UI.Fonts.applySizes({ settings = { fontSizeRows = 15 } })
    h.eq(body.flags, "OUTLINE"); h.near(body.size, 15)
  end)
  _G.CreateFont, _G.GameFontHighlight = nil, nil
  assert(ok, err)
end)

h.test("Fonts.choices: SetFont returning nothing counts as loaded (retail)", function()
  local ns = load()
  local created = {}
  _G.CreateFont = function(name)
    local f = { name = name }
    function f:SetFont() end -- retail: no return value
    created[name] = f
    return f
  end
  local ok, err = pcall(function()
    local c = ns.UI.Fonts.choices()
    local labels = {}
    for _, e in ipairs(c) do labels[#labels + 1] = e.label end
    h.eq(labels[1], "WoW default")
    h.eq(#c >= 5, true) -- the four built-in fonts are offered
  end)
  _G.CreateFont = nil
  assert(ok, err)
end)

h.test("Fonts.choices: the game's own fonts are offered, named, deduplicated and sorted", function()
  local ns = load()
  local created, newFont = fakeClient({ ["Fonts\\FRIZQT__.TTF"] = true, ["Fonts\\ARIALN.TTF"] = true,
    ["Fonts\\skurri.ttf"] = true, ["Fonts\\MORPHEUS.ttf"] = true,
    ["Fonts\\K_Damage.TTF"] = true, ["Fonts\\Special.ttf"] = true })
  _G.CreateFont = newFont
  local objs = {
    GameFontNormal = "Fonts\\FRIZQT__.TTF",
    CombatTextFont = "Fonts\\K_Damage.TTF",
    QuestFont = "Fonts\\Special.ttf",
  }
  for name, file in pairs(objs) do _G[name] = { GetFont = function() return file, 12, "" end } end
  local ok, err = pcall(function()
    local c = ns.UI.Fonts.choices()
    local labels, seen = {}, {}
    for i, e in ipairs(c) do
      labels[i] = e.label
      h.eq(seen[e.value:lower()], nil, "duplicate " .. e.value)
      seen[e.value:lower()] = true
    end
    h.eq(labels, { "WoW default", "Arial Narrow", "Damage", "Friz Quadrata", "Morpheus", "Skurri", "Special" })
  end)
  for name in pairs(objs) do _G[name] = nil end
  _G.CreateFont = nil
  assert(ok, err)
end)
