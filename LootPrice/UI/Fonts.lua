local ADDON, ns = ...

local L = ns.L

ns.UI = ns.UI or {}

-- Font options. The typeface (option "fontFace") changes live. Three groups of
-- the ledger also have a size in px (list text, totals text, section titles):
-- the px of the group's main font, its smaller fonts keep their proportion, and
-- its row heights in Theme.sizes grow or shrink with it. Everything is decided once, before the
-- window is built (Fonts.install, called by Ledger.init), so a changed size
-- takes effect after /reload.
local Fonts = {}
ns.UI.Fonts = Fonts

-- option = Options key (the size in px), nominal = the game's size of the main
-- font in px (the default of the option), fonts = Theme.fonts keys, sizes = Theme.sizes
-- keys (pixel heights) that scale with it.
Fonts.GROUPS = {
  { option = "fontSizeRows", nominal = 12, fonts = { "body", "rowSmall" }, sizes = { "rowHeight" } },
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

-- Well-known game fonts; only the ones the client really loads are offered.
local BUILT_IN = {
  { "Friz Quadrata", "Fonts\\FRIZQT__.TTF" },
  { "Arial Narrow", "Fonts\\ARIALN.TTF" },
  { "Skurri", "Fonts\\skurri.ttf" },
  { "Morpheus", "Fonts\\MORPHEUS.ttf" },
}

local faceChoices

-- Can the client use this font file? SetFont returns false when it cannot.
local function loads(path)
  local create = _G.CreateFont
  if type(create) ~= "function" then return false end
  Fonts.probe = Fonts.probe or create("LootPriceFontProbe")
  return Fonts.probe:SetFont(path, 12, "") and true or false
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
  faceChoices = list
  return list
end

-- ---------------------------------------------------------------------------
-- Font objects

local objects = {} -- [key] = { font, file, size, flags } for the objects made here

-- Sets the file of a font object, falling back to the game's own when the
-- client refuses the chosen one.
local function setFace(entry, face)
  local file = (face and face ~= Fonts.DEFAULT_FACE) and face or entry.file
  if entry.font:SetFont(file, entry.size, entry.flags) == false then
    entry.font:SetFont(entry.file, entry.size, entry.flags)
  end
end

-- Creates "LootPrice<Key>" as a copy of the game font object `baseName` at
-- `factor` times its size, in typeface `face`. Returns the new object's name,
-- or nil without the client API.
local function ownFont(key, baseName, factor, face)
  local create, base = _G.CreateFont, _G[baseName]
  if type(create) ~= "function" or type(base) ~= "table" then return nil end
  local name = "LootPrice" .. key:sub(1, 1):upper() .. key:sub(2)
  local font = create(name)
  font:CopyFontObject(base)
  local file, size, flags = base:GetFont()
  if not (file and size) then return nil end
  local entry = { font = font, file = file, size = size * factor, flags = flags }
  objects[key] = entry
  setFace(entry, face)
  return name
end

-- Option "fontFace": the new typeface for every font object made by install.
function Fonts.applyFace(face)
  for _, entry in pairs(objects) do setFace(entry, face) end
end

local installed = false

-- Gives the ledger its own copy of every game font (so the typeface can change
-- without touching other addons) and applies the saved sizes to ns.Theme.
-- Runs once, before the window is built.
function Fonts.install(db)
  if installed or type(db) ~= "table" or not ns.Options then return end
  installed = true
  local T = ns.Theme
  local face = ns.Options.get(db, "fontFace")
  local factors, scaledAny = {}, false
  for _, group in ipairs(Fonts.GROUPS) do
    local factor = (ns.Options.get(db, group.option) or group.nominal) / group.nominal
    if factor ~= 1 then
      scaledAny = true
      for key, value in pairs(Fonts.scaledSizes(T.sizes, group.sizes, factor)) do T.sizes[key] = value end
    end
    for _, key in ipairs(group.fonts) do factors[key] = factor end
  end
  local keys = {}
  for key, value in pairs(T.fonts) do
    if key ~= "file" and type(value) == "string" then keys[#keys + 1] = key end
  end
  for _, key in ipairs(keys) do
    local name = ownFont(key, T.fonts[key], factors[key] or 1, face)
    if name then T.fonts[key] = name end
  end
  if not scaledAny then return end
  local s = T.sizes
  s.footerHeight = 4 * s.footerRowHeight
  -- The footer table's columns are budgeted with the glyph estimate of the
  -- totals font (unrounded: it is a fraction of a px); the window is never
  -- narrower than the widest table line.
  local totals = factors.summary or 1
  s.summaryCharPx = s.summaryCharPx * totals
  s.markerCharPx = s.markerCharPx * totals
  if ns.UI.Summary and ns.UI.Summary.tableWorstWidth then
    s.minWidth = math.max(s.minWidth, math.ceil(ns.UI.Summary.tableWorstWidth() + 2 * (s.padding + 4)))
  end
  if ns.UI.Summary and ns.UI.Summary.requiredWindowHeight then
    s.minHeight = ns.UI.Summary.requiredWindowHeight()
  end
end
