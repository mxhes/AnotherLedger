local ADDON, ns = ...

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
--     choices = { { value = "a", label = "A" }, ... }, -- dropdown (or a function returning that list)
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
  { id = "window", label = "Window" },
  { id = "prices", label = "Prices" },
  { id = "display", label = "Display" },
  { id = "session", label = "Session and alerts" },
}

-- What the panel shows, top to bottom: for every section a header entry
-- ({ key = "header:<id>", type = "header", label }) followed by its options in
-- the order they were defined. Empty sections are left out.
function Options.entries()
  local known, byCategory = {}, {}
  for _, c in ipairs(Options.CATEGORIES) do known[c.id], byCategory[c.id] = true, {} end
  local other = {}
  for _, spec in ipairs(Options.specs) do
    local list = known[spec.category] and byCategory[spec.category] or other
    list[#list + 1] = spec
  end
  local out = {}
  local function section(id, label, specs)
    if #specs == 0 then return end
    out[#out + 1] = { key = "header:" .. id, type = "header", label = label }
    for _, spec in ipairs(specs) do out[#out + 1] = spec end
  end
  for _, c in ipairs(Options.CATEGORIES) do section(c.id, c.label, byCategory[c.id]) end
  section("other", "Other", other)
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
  key = "alpha", category = "window", type = "slider", label = "Window opacity",
  min = 0, max = 1, step = 0.05, format = percent, apply = applyWindowLook,
})

-- 100 % is the theme color; above that the dark panel gets lighter.
Options.define({
  key = "brightness", category = "window", type = "slider", label = "Window brightness",
  min = 0, max = 2, step = 0.05, format = percent, apply = applyWindowLook,
})

Options.define({
  key = "windowScale", category = "window", type = "slider", label = "Window scale",
  min = 0.7, max = 1.5, step = 0.05, format = percent,
  apply = function()
    if ns.UI and ns.UI.Window and ns.UI.Window.applyScale then ns.UI.Window.applyScale() end
  end,
})

Options.define({ key = "lockWindow", category = "window", type = "checkbox", label = "Lock window (no moving or resizing)" })

Options.define({ key = "startHidden", category = "window", type = "checkbox", label = "Start hidden at login" })

Options.define({
  key = "combatHide", category = "window",
  type = "checkbox",
  label = "Hide in combat, show again afterwards",
  apply = function(v)
    if not v and ns.UI and ns.UI.Window and ns.UI.Window.combatShow then ns.UI.Window.combatShow() end
  end,
})

Options.define({ key = "keepSession", category = "session", type = "checkbox", label = "Keep the session across logins" })

Options.define({
  key = "priceSource", category = "prices",
  type = "dropdown",
  label = "AH price source",
  -- "Auto" plus every registered price source (Sources/Sources.lua).
  choices = function() return ns.Sources.choices() end,
  apply = refreshUI,
})

-- The TSM price string, read live by Sources/TSM.lua (same as /lp tsm).
Options.define({
  key = "tsmSource", category = "prices", type = "text", label = "TSM price source (e.g. DBMarket)", apply = refreshUI,
})

Options.define({
  key = "refreshSeconds", category = "prices", type = "slider", label = "Price refresh interval",
  min = 10, max = 120, step = 5, format = function(v) return v .. " s" end,
})

-- After this long a cached AH price shows its age tag in orange.
Options.define({
  key = "staleHours", category = "prices", type = "slider", label = "Mark cached prices as old after",
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
  label = "Sort order (at login)",
  choices = {
    { value = "ah", label = "AH value" },
    { value = "vendor", label = "Vendor value" },
    { value = "name", label = "Name" },
    { value = "recent", label = "Most recent" },
  },
  apply = function(v)
    if ns.db then ns.db.sort = v end
    refreshUI()
  end,
})

Options.define({
  key = "goldDisplay", category = "display",
  type = "dropdown",
  label = "Amounts of 1 gold and more",
  choices = {
    { value = "full", label = "Gold, silver and copper" },
    { value = "silver", label = "Gold and silver" },
    { value = "gold", label = "Gold only" },
  },
  apply = function(v)
    if ns.Money then ns.Money.setStyle(v) end
    refreshUI()
  end,
})

Options.define({
  key = "includeGold", category = "display", type = "checkbox", label = "Add raw gold to the combined total", apply = refreshUI,
})

-- Chat line when one drop is worth at least this much (gold). Empty / 0 = off.
Options.define({
  key = "alertGold", category = "session", type = "number", label = "Alert for drops worth (gold, 0 = off)",
})

Options.define({ key = "alertSound", category = "session", type = "checkbox", label = "Play a sound with the alert" })

-- Round button on the minimap (UI/Minimap.lua).
-- Font sizes (UI/Fonts.lua): decided before the window is built, so they take
-- effect after /reload.
-- Typeface of all addon text; changes live. "WoW default" keeps the game's own font.
Options.define({
  key = "fontFace", category = "display",
  type = "dropdown",
  label = "Font",
  choices = function()
    if ns.UI and ns.UI.Fonts then return ns.UI.Fonts.choices() end
    return { { value = "default", label = "WoW default" } }
  end,
  apply = function(v)
    if ns.UI and ns.UI.Fonts then ns.UI.Fonts.applyFace(v) end
  end,
})

local function px(v) return v .. " px" end
Options.define({ key = "fontSizeRows", category = "display", type = "slider", label = "List text size (after /reload)",
  min = 8, max = 18, step = 1, format = px })
Options.define({ key = "fontSizeTotals", category = "display", type = "slider", label = "Totals text size (after /reload)",
  min = 8, max = 18, step = 1, format = px })
Options.define({ key = "fontSizeTitles", category = "display", type = "slider", label = "Section title size (after /reload)",
  min = 10, max = 24, step = 1, format = px })
Options.define({
  key = "reloadUI", category = "display", type = "button", label = "Reload UI to apply font sizes",
  action = function()
    if type(ReloadUI) == "function" then ReloadUI() end
  end,
})

Options.define({
  key = "minimapButton", category = "window",
  type = "checkbox",
  label = "Show minimap button",
  apply = function(v)
    if ns.UI and ns.UI.Minimap then ns.UI.Minimap.setShown(v) end
  end,
})

Options.define({
  key = "minimapReset", category = "window", type = "button", label = "Reset minimap button position",
  action = function()
    if ns.UI and ns.UI.Minimap then ns.UI.Minimap.resetPosition() end
  end,
})

-- How many finished sessions the History tab keeps. Lowering it prunes at once.
Options.define({
  key = "historyLimit", category = "session",
  type = "number",
  label = "History sessions kept (empty = unlimited)",
  apply = function(v)
    if ns.History and ns.chardb and type(ns.chardb.history) == "table" then
      ns.History.prune(ns.chardb.history, v)
    end
    refreshUI()
  end,
})

ns.Options = Options
