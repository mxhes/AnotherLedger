local ADDON, ns = ...

local L = ns.L

ns.UI = ns.UI or {}

-- Font options. The typeface (option "fontFace"), the outline ("fontOutline"),
-- the shadow ("fontShadow") and the sizes change live.
-- Three groups of the ledger have a size in px (list text, totals text, section
-- titles): the px of the group's main font, its smaller fonts keep their
-- proportion, and its row heights in Theme.sizes grow or shrink with it.
-- Fonts.install (called by Ledger.init, before the window is built) makes the
-- font objects; Fonts.applySizes recomputes the sizes from the theme's own
-- values whenever a size option changes, and the ledger then re-lays itself
-- out (Ledger.relayout).
local Fonts = {}
ns.UI.Fonts = Fonts

-- option = Options key (the size in px), nominal = the game's size of the main
-- font in px (the default of the option), fonts = Theme.fonts keys, sizes = Theme.sizes
-- keys (pixel heights) that scale with it.
Fonts.GROUPS = {
  { option = "fontSizeRows", nominal = 12, fonts = { "body", "rowSmall", "sourceTag" }, sizes = { "rowHeight", "iconSize" } },
  { option = "fontSizeTotals", nominal = 12, fonts = { "summary", "summaryMarker", "topRow" },
    sizes = { "footerRowHeight", "footerNoteHeight", "topRowHeight" } },
  { option = "fontSizeTitles", nominal = 16, fonts = { "topHeader" }, sizes = { "topHeaderHeight" } },
}

local function round(v) return math.floor(v + 0.5) end

-- Pure. The pixel sizes `keys` of `base` multiplied by `factor`.
function Fonts.scaledSizes(base, keys, factor)
  local out = {}
  for _, key in ipairs(keys) do out[key] = round(base[key] * factor) end
  return out
end

-- ---------------------------------------------------------------------------
-- Typeface (option "fontFace"): "default" keeps the WoW font of each game font
-- object (right for the client's language); any other value is a font file path.

Fonts.DEFAULT_FACE = "default"

-- Well-known game fonts, in every client since the first one; only the ones
-- the client really loads are offered.
local BUILT_IN = {
  { "Friz Quadrata", "Fonts\\FRIZQT__.TTF" },
  { "Arial Narrow", "Fonts\\ARIALN.TTF" },
  { "Skurri", "Fonts\\skurri.ttf" },
  { "Morpheus", "Fonts\\MORPHEUS.ttf" },
}

-- Game font objects whose files are offered too: the game draws with them,
-- so the files exist (also the ones of other languages and newer clients).
-- Missing ones are skipped.
local GAME_FONT_OBJECTS = {
  "GameFontNormal", "ChatFontNormal", "NumberFontNormal", "QuestFont", "SystemFont_Med1",
  "GameFontNormalHuge", "CombatTextFont", "ZoneTextFont", "SubZoneTextFont", "DestinyFontLarge",
  "MailFont_Large", "InvoiceFont_Med", "SpellFont_Small", "Fancy16Font", "FriendsFont_Normal",
}

-- Names of known font files (lower-case base name, no extension).
local FILE_NAMES = {
  frizqt__ = "Friz Quadrata", frizqt___cyr = "Friz Quadrata (Cyrillic)", arialn = "Arial Narrow",
  skurri = "Skurri", skurri_cyr = "Skurri (Cyrillic)", morpheus = "Morpheus",
  morpheus_cyr = "Morpheus (Cyrillic)", nim_____ = "Nimrod", k_damage = "Damage",
  k_pagetext = "Page text", ["2002"] = "2002", ["2002b"] = "2002 Bold",
}

-- Pure. A display name for a font file path: a known name, else its base name.
function Fonts.fileLabel(path)
  local base = tostring(path):match("([^\\/]+)$") or tostring(path)
  base = base:gsub("%.[^.]+$", "")
  return FILE_NAMES[base:lower()] or base
end

local faceChoices

-- Can the client use this font file? SetFont returns false when it cannot; on
-- retail it returns nothing at all, which counts as loaded.
local function loads(path)
  local create = _G.CreateFont
  if type(create) ~= "function" then return false end
  Fonts.probe = Fonts.probe or create("AnotherLedgerFontProbe")
  return Fonts.probe:SetFont(path, 12, "") ~= false
end

-- { { value, label }, ... } for the dropdown: the WoW default, the built-in
-- fonts the client has and every font registered with LibSharedMedia (when
-- another addon provides it). Built once, on first use.
function Fonts.choices()
  if faceChoices then return faceChoices end
  local list, seen = { { value = Fonts.DEFAULT_FACE, label = L["WoW default"] } }, {}
  local function add(label, path)
    if seen[path:lower()] then return end
    seen[path:lower()] = true
    list[#list + 1] = { value = path, label = label }
  end
  for _, font in ipairs(BUILT_IN) do
    if loads(font[2]) then add(font[1], font[2]) end
  end
  for _, name in ipairs(GAME_FONT_OBJECTS) do
    local obj = _G[name]
    if type(obj) == "table" and type(obj.GetFont) == "function" then
      local ok, file = pcall(obj.GetFont, obj)
      if ok and type(file) == "string" and file ~= "" then add(Fonts.fileLabel(file), file) end
    end
  end
  local libStub = _G.LibStub
  local lsm
  if libStub then
    local ok, lib = pcall(libStub, "LibSharedMedia-3.0", true)
    if ok then lsm = lib end
  end
  if lsm and lsm.HashTable then
    local names = {}
    for name in pairs(lsm:HashTable("font")) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
      local path = lsm:HashTable("font")[name]
      if type(path) == "string" and loads(path) then add(name, path) end
    end
  end
  -- WoW default first, the fonts by name.
  local first = table.remove(list, 1)
  table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
  table.insert(list, 1, first)
  faceChoices = list
  return list
end

-- ---------------------------------------------------------------------------
-- Font objects

local objects = {} -- [key] = { font, file, size, gameSize, flags, shadow } for the objects made here
local face = nil      -- current typeface (option "fontFace")
local outline = "none" -- option "fontOutline"
local shadow = true    -- option "fontShadow"

-- Option "fontOutline": the values the game's SetFont takes as flags.
Fonts.OUTLINES = { none = true, OUTLINE = true, THICKOUTLINE = true }

-- Pure. The flags a font object gets: the outline, or the game font's own
-- flags with none.
function Fonts.flags(gameFlags, chosen)
  if chosen and chosen ~= "none" and Fonts.OUTLINES[chosen] then return chosen end
  return gameFlags or ""
end

-- Pure. The shadow of a font object: { x, y, r, g, b, a }. On: the game
-- font's own shadow, or 1 px down right in black when it has none. Off: none.
function Fonts.shadowOf(game, on)
  if not on then return { 0, 0, 0, 0, 0, 0 } end
  game = game or {}
  local x, y = game.x or 0, game.y or 0
  if x == 0 and y == 0 then x, y = 1, -1 end
  local a = game.a or 0
  if a <= 0 then return { x, y, 0, 0, 0, 1 } end
  return { x, y, game.r or 0, game.g or 0, game.b or 0, a }
end

-- Sets the file, size and outline of a font object, falling back to the game's
-- own file when the client refuses the chosen one.
local function setFace(entry, chosen)
  if entry.pinned then chosen = entry.pinned end
  local file = (chosen and chosen ~= Fonts.DEFAULT_FACE) and chosen or entry.file
  local flags = Fonts.flags(entry.flags, outline)
  if entry.font:SetFont(file, entry.size, flags) == false then
    entry.font:SetFont(entry.file, entry.size, flags)
  end
end

local function setShadow(entry)
  local f = entry.font
  if type(f.SetShadowOffset) ~= "function" or type(f.SetShadowColor) ~= "function" then return end
  local s = Fonts.shadowOf(entry.shadow, shadow)
  f:SetShadowOffset(s[1], s[2])
  f:SetShadowColor(s[3], s[4], s[5], s[6])
end

-- The game font's own shadow, to restore it when the option is on again.
local function gameShadow(base)
  local s = {}
  if type(base.GetShadowOffset) == "function" then s.x, s.y = base:GetShadowOffset() end
  if type(base.GetShadowColor) == "function" then s.r, s.g, s.b, s.a = base:GetShadowColor() end
  for k, v in pairs(s) do if type(v) ~= "number" then s[k] = nil end end
  return s
end

-- Creates "AnotherLedger<Key>" as a copy of the game font object `baseName` in
-- typeface `face` (its size is set by applySizes). Returns the new object's
-- name, or nil without the client API.
local function ownFont(key, baseName)
  local create, base = _G.CreateFont, _G[baseName]
  if type(create) ~= "function" or type(base) ~= "table" then return nil end
  local name = "AnotherLedger" .. key:sub(1, 1):upper() .. key:sub(2)
  local font = create(name)
  font:CopyFontObject(base)
  local file, size, flags = base:GetFont()
  if not (file and size) then return nil end
  local pinned = ns.Theme.fontFiles and ns.Theme.fontFiles[key] or nil
  objects[key] = { font = font, file = file, size = size, gameSize = size, flags = flags, pinned = pinned,
    shadow = gameShadow(base) }
  return name
end

-- Option "fontFace": the new typeface for every font object made by install.
function Fonts.applyFace(chosen)
  face = chosen
  for _, entry in pairs(objects) do setFace(entry, chosen) end
end

-- The current outline's entry of a Theme.sizes table keyed by outline (0
-- without an outline).
function Fonts.outlineValue(key)
  local t = ns.Theme.sizes[key]
  return type(t) == "table" and t[outline] or 0
end

-- Extra width per glyph of the current outline (Theme.sizes.outlineGlyphPx).
function Fonts.outlineGlyphPx() return Fonts.outlineValue("outlineGlyphPx") end

-- Options "fontOutline" / "fontShadow": every font object made by install
-- (the source tags too). Returns whether anything changed; the caller re-lays
-- the window out, as an outline makes the text wider.
function Fonts.applyStyle(newOutline, newShadow)
  newOutline = Fonts.OUTLINES[newOutline] and newOutline or "none"
  newShadow = newShadow and true or false
  if newOutline == outline and newShadow == shadow then return false end
  outline, shadow = newOutline, newShadow
  for _, entry in pairs(objects) do
    setFace(entry, face)
    setShadow(entry)
  end
  return true
end

-- The theme's own values of every size applySizes derives, taken once before
-- the first change, so a size is always computed from them (never compounded).
local DERIVED = { "footerHeight", "summaryCharPx", "markerCharPx", "timerWidth", "minWidth", "minHeight" }
local base

local function snapshot(sizes)
  if base then return end
  base = {}
  for _, group in ipairs(Fonts.GROUPS) do
    for _, key in ipairs(group.sizes) do base[key] = sizes[key] end
  end
  for _, key in ipairs(DERIVED) do base[key] = sizes[key] end
end

local installed = false

-- FontStrings created from an own font object follow a later SetFont of that
-- object (new size without re-creating them).
-- Applies the saved sizes to ns.Theme.sizes and to the font objects. Returns
-- whether any size changed (nothing to re-lay out otherwise). Does nothing
-- before install.
function Fonts.applySizes(db)
  if not installed or type(db) ~= "table" or not ns.Options then return false end
  local T = ns.Theme
  local s = T.sizes
  snapshot(s)
  local factors, changed = {}, false
  local function set(key, value)
    if s[key] ~= value then s[key], changed = value, true end
  end
  for _, group in ipairs(Fonts.GROUPS) do
    local factor = (ns.Options.get(db, group.option) or group.nominal) / group.nominal
    for key, value in pairs(Fonts.scaledSizes(base, group.sizes, factor)) do set(key, value) end
    for _, key in ipairs(group.fonts) do factors[key] = factor end
  end
  for key, entry in pairs(objects) do
    local size = entry.gameSize * (factors[key] or 1)
    if entry.size ~= size then
      entry.size, changed = size, true
      setFace(entry, face)
    end
  end
  set("footerHeight", 4 * s.footerRowHeight)
  -- The footer table's columns are budgeted with the glyph estimate of the
  -- totals font (unrounded: it is a fraction of a px); the window is never
  -- narrower than the widest table line.
  -- An outline widens every glyph: the estimates and the clock grow with it.
  local totals = factors.summary or 1
  local extra = Fonts.outlineGlyphPx()
  set("summaryCharPx", base.summaryCharPx * totals + extra)
  set("markerCharPx", base.markerCharPx * totals + extra)
  set("timerWidth", base.timerWidth + s.timerGlyphs * extra)
  set("textOverhang", Fonts.outlineValue("outlineOverhangPx"))
  set("tagTextShift", Fonts.outlineValue("outlineTagShiftPx"))
  set("tagPadExtra", Fonts.outlineValue("outlineTagPadPx"))
  local minWidth = base.minWidth
  if ns.UI.Summary and ns.UI.Summary.tableWorstWidth then
    minWidth = math.max(minWidth, math.ceil(ns.UI.Summary.tableWorstWidth() + 2 * (s.padding + 4)))
  end
  set("minWidth", minWidth)
  if ns.UI.Summary and ns.UI.Summary.requiredWindowHeight then
    set("minHeight", ns.UI.Summary.requiredWindowHeight())
  end
  return changed
end

-- Gives the ledger its own copy of every game font (so the typeface and sizes
-- can change without touching other addons) and applies the saved face and
-- sizes. Runs once, before the window is built.
function Fonts.install(db)
  if installed or type(db) ~= "table" or not ns.Options then return end
  installed = true
  local T = ns.Theme
  face = ns.Options.get(db, "fontFace")
  outline = ns.Options.get(db, "fontOutline")
  if not Fonts.OUTLINES[outline] then outline = "none" end
  shadow = ns.Options.get(db, "fontShadow") and true or false
  local keys = {}
  for key, value in pairs(T.fonts) do
    if key ~= "file" and type(value) == "string" then keys[#keys + 1] = key end
  end
  for _, key in ipairs(keys) do
    local name = ownFont(key, T.fonts[key])
    if name then T.fonts[key] = name end
  end
  for _, entry in pairs(objects) do
    setFace(entry, face)
    setShadow(entry)
  end
  Fonts.applySizes(db)
end
