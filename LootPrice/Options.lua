local ADDON, ns = ...

local L = ns.L

-- Options registry. Every option is one table passed to Options.define; the
-- options panel (UI/OptionsPanel.lua) builds its widgets from the list, so a
-- new option never touches the panel:
--
--   Options.define({
--     key     = "alpha",              -- db.settings[key] (default in DB.defaults.settings)
--     type    = "slider",             -- slider | dropdown | checkbox | number | text | button (see OptionsPanel.WIDGETS)
--     category = "window",            -- section of the panel (Options.CATEGORIES)
--     label   = "Window opacity",
--     min = 0.1, max = 1, step = 0.05, -- slider
--     choices = { { value = "a", label = L["A"] }, ... }, -- dropdown (or a function returning that list)
--     (labels go through ns.L, Locale.lua: L["Window opacity"])
--     (number: whole number >= 0, or -1 = unlimited; typed into a text box)
--     (text: any non-empty text; button: has no value, `action` runs on click)
--     format  = function(v) ... end,  -- optional display text of the value
--     apply   = function(value) ... end, -- optional: make the value take effect
--   })
--
-- Values are validated by type (clamped, snapped, checked against the choices)
-- and fall back to the default; pure, no WoW globals.
local Options = {
  specs = {},
  byKey = {},
}

local num = ns.Util.isNumber

-- Vertical size (px) of one option block in the panel, by type.
Options.HEIGHTS = { slider = 46, dropdown = 48, checkbox = 28, number = 46, text = 46, button = 28, header = 26 }
Options.GAP = 8

function Options.define(spec)
  assert(type(spec) == "table" and type(spec.key) == "string", "option needs a key")
  assert(Options.HEIGHTS[spec.type], "unknown option type: " .. tostring(spec.type))
  if Options.byKey[spec.key] then
    for i, s in ipairs(Options.specs) do
      if s.key == spec.key then Options.specs[i] = spec end
    end
  else
    Options.specs[#Options.specs + 1] = spec
  end
  Options.byKey[spec.key] = spec
  return spec
end

function Options.list()
  return Options.specs
end

-- The sections of the panel, in order. An option names its section with
-- `category`; one without (or with an unknown one) lands in a last "Other" section.
Options.CATEGORIES = {
  { id = "window", label = L["Window"] },
  { id = "prices", label = L["Prices"] },
  { id = "display", label = L["Display"] },
  { id = "session", label = L["Session and alerts"] },
}

-- What the panel shows, top to bottom: for every section a header entry
-- ({ key = "header:<id>", type = "header", label }) followed by its options in
-- the order they were defined. Empty sections are left out.
function Options.entries()
  local out = {}
  for _, section in ipairs(Options.sections()) do
    out[#out + 1] = { key = "header:" .. section.id, type = "header", label = section.label }
    for _, spec in ipairs(section.specs) do out[#out + 1] = spec end
  end
  return out
end

-- The sections in panel order, each { id, label, specs = { spec, ... } }: one
-- tab of the options panel each. Empty sections are left out; options without
-- a known category form a last "Other" section.
function Options.sections()
  local known, byCategory = {}, {}
  for _, c in ipairs(Options.CATEGORIES) do known[c.id], byCategory[c.id] = true, {} end
  local other = {}
  for _, spec in ipairs(Options.specs) do
    local list = known[spec.category] and byCategory[spec.category] or other
    list[#list + 1] = spec
  end
  local out = {}
  local function section(id, label, specs)
    if #specs > 0 then out[#out + 1] = { id = id, label = label, specs = specs } end
  end
  for _, c in ipairs(Options.CATEGORIES) do section(c.id, c.label, byCategory[c.id]) end
  section("other", L["Other"], other)
  return out
end

function Options.spec(key)
  return Options.byKey[key]
end

-- The choices of a dropdown option; a function is asked each time, so a list
-- that grows later (price sources) is always current.
function Options.choices(spec)
  local choices = spec.choices
  if type(choices) == "function" then choices = choices() end
  return type(choices) == "table" and choices or {}
end

function Options.defaultFor(key)
  local d = ns.DB and ns.DB.defaults and ns.DB.defaults.settings
  return d and d[key]
end

-- Returns a valid value for the option: the given one clamped / snapped, or the
-- default when it is of the wrong type or not an allowed choice.
function Options.normalize(spec, value)
  local default = Options.defaultFor(spec.key)
  if spec.type == "checkbox" then
    if type(value) == "boolean" then return value end
    return default
  elseif spec.type == "slider" then
    if not num(value) then return default end
    local v = math.min(spec.max, math.max(spec.min, value))
    if num(spec.step) and spec.step > 0 then
      v = spec.min + math.floor((v - spec.min) / spec.step + 0.5) * spec.step
      v = math.min(spec.max, math.max(spec.min, v))
      -- Trim floating point noise (0.30000000000000004 -> 0.3).
      v = tonumber(string.format("%.6g", v))
    end
    return v
  elseif spec.type == "text" then
    if type(value) ~= "string" then return default end
    local trimmed = value:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then return default end
    return trimmed
  elseif spec.type == "number" then
    if not num(value) then return default end
    if value < 0 then return -1 end
    return math.floor(value)
  elseif spec.type == "dropdown" then
    for _, c in ipairs(Options.choices(spec)) do
      if c.value == value then return value end
    end
    return default
  end
  return default
end

function Options.get(db, key)
  local spec = Options.byKey[key]
  if not spec then return nil end
  local settings = type(db) == "table" and db.settings or nil
  return Options.normalize(spec, settings and settings[key])
end

-- Text typed into a number option -> value, or nil when it is not understood.
-- Digits give that number; an empty box, "unlimited", "inf", "-1" give -1.
function Options.parseNumber(text)
  if type(text) ~= "string" then return nil end
  local t = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
  if t == "" or t == "-1" or t:match("^[ui]") or t:find("\226\136\158", 1, true) then return -1 end
  if t:match("^%d+$") then return tonumber(t) end
  return nil
end

-- Validates, stores and applies. Returns the stored value.
function Options.set(db, key, value)
  local spec = Options.byKey[key]
  if not spec or type(db) ~= "table" then return nil end
  db.settings = db.settings or {}
  local v = Options.normalize(spec, value)
  db.settings[key] = v
  if spec.apply then spec.apply(v) end
  return v
end

-- Applies every stored value (login): repairs invalid saved values as it goes.
function Options.applyAll(db)
  for _, spec in ipairs(Options.specs) do
    if spec.type ~= "button" then Options.set(db, spec.key, Options.get(db, spec.key)) end
  end
end

-- Text of a value for the panel: the spec's formatter, the choice label or the
-- plain value.
function Options.valueText(spec, value)
  if spec.format then return spec.format(value) end
  if spec.type == "number" and num(value) and value < 0 then return "Unlimited" end
  if spec.type == "dropdown" then
    for _, c in ipairs(Options.choices(spec)) do
      if c.value == value then return c.label end
    end
  end
  return tostring(value)
end

-- Panel layout: top offset of each option block and the total height. With
-- `columns` > 1 the blocks flow top to bottom through the columns, each about
-- equally tall. Returns { tops = { [key] = y }, cols = { [key] = column },
-- height = tallest column }.
function Options.layout(specs, columns)
  columns = math.max(1, math.floor(columns or 1))
  local total = 0
  for _, spec in ipairs(specs) do total = total + Options.HEIGHTS[spec.type] + Options.GAP end
  local per = total / columns
  local tops, cols, col, y, height = {}, {}, 1, 0, 0
  local previous
  for i, spec in ipairs(specs) do
    local h = Options.HEIGHTS[spec.type]
    -- A header counts together with the entry under it, and that entry never
    -- starts a column by itself.
    local need = h
    if spec.type == "header" and specs[i + 1] then need = h + Options.GAP + Options.HEIGHTS[specs[i + 1].type] end
    if col < columns and y > 0 and not (previous and previous.type == "header") and y + need / 2 > per then
      height = math.max(height, y - Options.GAP)
      col, y = col + 1, 0
    end
    tops[spec.key], cols[spec.key] = y, col
    y = y + h + Options.GAP
    previous = spec
  end
  return { tops = tops, cols = cols, height = math.max(height, y - Options.GAP, 0) }
end

-- ---------------------------------------------------------------------------
-- Built-in options. Apply callbacks look the UI up at call time, so they are
-- harmless before the window exists (and in the tests).

local function refreshUI()
  if ns.UI and ns.UI.refresh then ns.UI.refresh() end
end

local function percent(v) return math.floor(v * 100 + 0.5) .. "%" end

local function applyWindowLook()
  if ns.UI and ns.UI.Window and ns.UI.Window.applyLook then ns.UI.Window.applyLook() end
end

-- Window background and border.
Options.define({
  key = "alpha", category = "window", type = "slider", label = L["Window opacity"],
  min = 0, max = 1, step = 0.05, format = percent, apply = applyWindowLook,
})

-- 100 % is the theme color; above that the dark panel gets lighter.
Options.define({
  key = "brightness", category = "window", type = "slider", label = L["Window brightness"],
  min = 0, max = 2, step = 0.05, format = percent, apply = applyWindowLook,
})

Options.define({
  key = "windowScale", category = "window", type = "slider", label = L["Window scale"],
  min = 0.7, max = 1.5, step = 0.05, format = percent,
  apply = function()
    if ns.UI and ns.UI.Window and ns.UI.Window.applyScale then ns.UI.Window.applyScale() end
  end,
})

Options.define({ key = "lockWindow", category = "window", type = "checkbox", label = L["Lock window (no moving or resizing)"] })

Options.define({ key = "startHidden", category = "window", type = "checkbox", label = L["Start hidden at login"] })

Options.define({
  key = "combatHide", category = "window",
  type = "checkbox",
  label = L["Hide in combat, show again afterwards"],
  apply = function(v)
    if not v and ns.UI and ns.UI.Window and ns.UI.Window.combatShow then ns.UI.Window.combatShow() end
  end,
})

Options.define({ key = "keepSession", category = "session", type = "checkbox", label = L["Keep the session across logins"] })

Options.define({
  key = "priceSource", category = "prices",
  type = "dropdown",
  label = L["AH price source"],
  -- "Auto" plus every registered price source (Sources/Sources.lua).
  choices = function() return ns.Sources.choices() end,
  apply = refreshUI,
})

-- The TSM price string, read live by Sources/TSM.lua (same as /lp tsm).
Options.define({
  key = "tsmSource", category = "prices", type = "text", label = L["TSM price source (e.g. DBMarket)"], apply = refreshUI,
})

-- TSM region sale info under the item name (Sources/TSM.lua TSM.market) and
-- the cutoffs of its levels (View.marketLevels).
Options.define({
  key = "showMarket", category = "prices", type = "checkbox", label = L["Show TSM sale info under the name"], apply = refreshUI,
})

local function rate(v) return string.format("%.2f", v) end
Options.define({ key = "saleRateGood", category = "prices", type = "slider", label = L["Sale rate: sells well from"],
  min = 0, max = 1, step = 0.01, format = rate, apply = refreshUI })
Options.define({ key = "saleRateOk", category = "prices", type = "slider", label = L["Sale rate: sells okay from"],
  min = 0, max = 1, step = 0.01, format = rate, apply = refreshUI })
Options.define({ key = "soldHigh", category = "prices", type = "number", label = L["Sold per day: high volume from"],
  apply = refreshUI })
Options.define({ key = "soldMedium", category = "prices", type = "number", label = L["Sold per day: medium volume from"],
  apply = refreshUI })

Options.define({
  key = "refreshSeconds", category = "prices", type = "slider", label = L["Price refresh interval"],
  min = 10, max = 120, step = 5, format = function(v) return v .. " s" end,
})

-- After this long a cached AH price shows its age tag in orange.
Options.define({
  key = "staleHours", category = "prices", type = "slider", label = L["Mark cached prices as old after"],
  min = 1, max = 72, step = 1, format = function(v) return v .. " h" end,
  apply = function(v)
    if ns.Prices then ns.Prices.STALE_AFTER = v * 3600 end
    refreshUI()
  end,
})

-- Applied at login and whenever changed; the sort button of the filter bar
-- still changes the order for the rest of the session.
Options.define({
  key = "defaultSort", category = "display",
  type = "dropdown",
  label = L["Sort order (at login)"],
  choices = {
    { value = "ah", label = L["Best value"] },
    { value = "vendor", label = L["Vendor value"] },
    { value = "name", label = L["Name"] },
    { value = "recent", label = L["Most recent"] },
  },
  apply = function(v)
    if ns.db then ns.db.sort = v end
    refreshUI()
  end,
})

Options.define({
  key = "goldDisplay", category = "display",
  type = "dropdown",
  label = L["Amounts of 1 gold and more"],
  choices = {
    { value = "full", label = L["Gold, silver and copper"] },
    { value = "silver", label = L["Gold and silver"] },
    { value = "gold", label = L["Gold only"] },
  },
  apply = function(v)
    if ns.Money then ns.Money.setStyle(v) end
    refreshUI()
  end,
})

Options.define({
  key = "includeGold", category = "display", type = "checkbox", label = L["Add raw gold to the combined total"], apply = refreshUI,
})

-- Chat line when one drop is worth at least this much (gold). Empty / 0 = off.
Options.define({
  key = "alertGold", category = "session", type = "number", label = L["Alert for drops worth (gold, 0 = off)"],
})

Options.define({ key = "alertSound", category = "session", type = "checkbox", label = L["Play a sound with the alert"] })

-- Off: "You create" messages and items received while a merchant, mailbox,
-- trade or auction house window is open are not loot.
Options.define({
  key = "countCrafted", category = "session", type = "checkbox", label = L["Count crafted items and purchases"],
})

Options.define({ key = "afkPause", category = "session", type = "checkbox", label = L["Pause the clock while AFK"] })

Options.define({
  key = "instanceSession", category = "session", type = "checkbox",
  label = L["New session for each dungeon or raid"],
})

Options.define({
  key = "showCurrencies", category = "display", type = "checkbox", label = L["Show currencies in the list"], apply = refreshUI,
})

-- Daily farm strip at the top of the window (View.dailyFarm): the saved place
-- with the best gold per hour; only places with this much recorded time count.
Options.define({
  key = "dailyFarm", category = "display", type = "checkbox", label = L["Show the daily farm"], apply = refreshUI,
})

Options.define({
  key = "dailyFarmMinutes", category = "display", type = "slider", label = L["Daily farm: minimum time in a place"],
  min = 5, max = 120, step = 5, format = function(v) return v .. " min" end, apply = refreshUI,
})

-- Off: the Top finds block under the footer stays collapsed.
Options.define({
  key = "showTopFinds", category = "display", type = "checkbox", label = L["Show Top finds"], apply = refreshUI,
})

-- Off: the footer table has no Raw gold row (Total still follows includeGold).
Options.define({
  key = "showFooterGold", category = "display", type = "checkbox", label = L["Show the Raw gold row in the footer"],
  apply = refreshUI,
})

-- Off: the list rows have no icon and their text starts at the left edge.
Options.define({
  key = "showIcons", category = "display", type = "checkbox", label = L["Show item icons"],
  apply = function()
    if ns.UI and ns.UI.Ledger and ns.UI.Ledger.relayout then ns.UI.Ledger.relayout() end
  end,
})

-- Round button on the minimap (UI/Minimap.lua).
-- Font sizes (UI/Fonts.lua): applied live, the window re-lays itself out.
-- Typeface of all addon text; changes live. "WoW default" keeps the game's own font.
Options.define({
  key = "fontFace", category = "display",
  type = "dropdown",
  label = L["Font"],
  choices = function()
    if ns.UI and ns.UI.Fonts then return ns.UI.Fonts.choices() end
    return { { value = "default", label = L["WoW default"] } }
  end,
  apply = function(v)
    if ns.UI and ns.UI.Fonts then ns.UI.Fonts.applyFace(v) end
  end,
})

local function px(v) return v .. " px" end
-- Re-applies every size and re-lays the window out when one changed.
local function applySizes()
  if ns.UI and ns.UI.Ledger and ns.UI.Ledger.applySizes then ns.UI.Ledger.applySizes() end
end
Options.define({ key = "fontSizeRows", category = "display", type = "slider", label = L["List text size"],
  min = 8, max = 18, step = 1, format = px, apply = applySizes })
Options.define({ key = "fontSizeTotals", category = "display", type = "slider", label = L["Totals text size"],
  min = 8, max = 18, step = 1, format = px, apply = applySizes })
Options.define({ key = "fontSizeTitles", category = "display", type = "slider", label = L["Section title size"],
  min = 10, max = 24, step = 1, format = px, apply = applySizes })

Options.define({
  key = "minimapButton", category = "window",
  type = "checkbox",
  label = L["Show minimap button"],
  apply = function(v)
    if ns.UI and ns.UI.Minimap then ns.UI.Minimap.setShown(v) end
  end,
})

Options.define({
  key = "minimapReset", category = "window", type = "button", label = L["Reset minimap button position"],
  action = function()
    if ns.UI and ns.UI.Minimap then ns.UI.Minimap.resetPosition() end
  end,
})

Options.define({
  key = "exportHistory", category = "session", type = "button", label = L["Export History as CSV"],
  action = function()
    if ns.UI and ns.UI.Export then ns.UI.Export.history() end
  end,
})

-- How many finished sessions the History tab keeps. Lowering it prunes at once.
Options.define({
  key = "historyLimit", category = "session",
  type = "number",
  label = L["History sessions kept (empty = unlimited)"],
  apply = function(v)
    if ns.History and ns.chardb and type(ns.chardb.history) == "table" then
      ns.History.prune(ns.chardb.history, v)
    end
    refreshUI()
  end,
})

ns.Options = Options
