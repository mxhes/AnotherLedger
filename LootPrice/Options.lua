local ADDON, ns = ...

-- Options registry. Every option is one table passed to Options.define; the
-- options panel (UI/OptionsPanel.lua) builds its widgets from the list, so a
-- new option never touches the panel:
--
--   Options.define({
--     key     = "alpha",              -- db.settings[key] (default in DB.defaults.settings)
--     type    = "slider",             -- slider | dropdown | checkbox (see OptionsPanel.WIDGETS)
--     label   = "Window opacity",
--     min = 0.1, max = 1, step = 0.05, -- slider
--     choices = { { value = "a", label = "A" }, ... }, -- dropdown
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

local function num(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Vertical size (px) of one option block in the panel, by type.
Options.HEIGHTS = { slider = 46, dropdown = 48, checkbox = 28 }
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

function Options.spec(key)
  return Options.byKey[key]
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
  elseif spec.type == "dropdown" then
    for _, c in ipairs(spec.choices or {}) do
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
    Options.set(db, spec.key, Options.get(db, spec.key))
  end
end

-- Text of a value for the panel: the spec's formatter, the choice label or the
-- plain value.
function Options.valueText(spec, value)
  if spec.format then return spec.format(value) end
  if spec.type == "dropdown" then
    for _, c in ipairs(spec.choices or {}) do
      if c.value == value then return c.label end
    end
  end
  return tostring(value)
end

-- Panel layout: top offset of each option block and the total height.
-- Returns { tops = { [key] = y }, height = total }.
function Options.layout(specs)
  local tops, y = {}, 0
  for _, spec in ipairs(specs) do
    tops[spec.key] = y
    y = y + Options.HEIGHTS[spec.type] + Options.GAP
  end
  return { tops = tops, height = math.max(0, y - Options.GAP) }
end

-- ---------------------------------------------------------------------------
-- Price source choices; Core.sourceAllowed uses the same values.

Options.PRICE_SOURCES = {
  { value = "auto", label = "Auto (TSM, then Auctionator)" },
  { value = "tsm", label = "TSM" },
  { value = "auctionator", label = "Auctionator" },
}

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
  key = "alpha", type = "slider", label = "Window opacity",
  min = 0, max = 1, step = 0.05, format = percent, apply = applyWindowLook,
})

-- 100 % is the theme color; above that the dark panel gets lighter.
Options.define({
  key = "brightness", type = "slider", label = "Window brightness",
  min = 0, max = 2, step = 0.05, format = percent, apply = applyWindowLook,
})

Options.define({
  key = "priceSource",
  type = "dropdown",
  label = "AH price source",
  choices = Options.PRICE_SOURCES,
  apply = refreshUI,
})

Options.define({
  key = "combatHide",
  type = "checkbox",
  label = "Hide in combat, show again afterwards",
  apply = function(v)
    if not v and ns.UI and ns.UI.Window and ns.UI.Window.combatShow then ns.UI.Window.combatShow() end
  end,
})

ns.Options = Options
