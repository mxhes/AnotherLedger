local ADDON, ns = ...

-- The Appearance options that set the look: the single colors, the color
-- presets (built-in and saved ones) and the skin with its parts. Defined
-- after Options.lua's own options, so the panel lists them after the fonts.

local L = ns.L
local Options = ns.Options
local refreshUI = Options.refreshUI
local applyWindowLook = Options.applyWindowLook

-- ---------------------------------------------------------------------------
-- Colors (category "look", after the fonts): each option sets one or more Theme.colors in
-- place (Theme.setColor), then the UI recolors live: the texts, lines and
-- backdrops made by UI/Widgets.lua (Widgets.recolor), the window look and a
-- refresh for the rest. Tooltips read the colors when they are shown.

local function applyColors(targets)
  return function(v)
    local changed = {}
    for _, key in ipairs(targets) do
      local c = ns.Theme and ns.Theme.setColor(key, v)
      if c then changed[c] = true end
    end
    local UI = ns.UI
    if UI and UI.Widgets and UI.Widgets.recolor then UI.Widgets.recolor(changed) end
    applyWindowLook()
    refreshUI()
  end
end

-- key, label, tooltip, Theme.colors keys (the first one's default is the
-- option's default, DB.defaults.settings). Panel colors never also set a
-- tooltip color: tooltips stay on the dark game tooltip on every preset.
local COLOR_OPTIONS = {
  { "colorText", L["Text"], L["Color of the normal text: amounts, quantities, the clock and the buttons."],
    { "ink", "buttonText" } },
  { "colorTitles", L["Titles and totals"], L["Color of the Total row, the compact window's gold per hour and the window titles."],
    { "gold" } },
  { "colorHints", L["Hints"], L["Color of quiet texts: column titles and hints."],
    { "hint", "columnTitle" } },
  { "colorVendor", L["Vendor"], L["Color of the Vendor tag and of vendor values in tooltips."], { "tagVendor" } },
  { "colorAuction", L["Auction"], L["Color of the Auction tag and of auction house values in tooltips."], { "tagAh" } },
  { "colorDestroy", L["Destroy"], L["Color of the Destroy tag (disenchant, mill, prospect) and of its values in tooltips."],
    { "tagDe" } },
  { "colorTipLabels", L["Tooltip labels"], L["Color of the labels on the left of AnotherLedger tooltips."], { "tipLabel" } },
  { "colorBackground", L["Window background"], L["Background of the window and the options. Opacity and Brightness still apply to the window."],
    { "panelTint" } },
  { "colorBorder", L["Window border"], L["Edge of the window and the options."], { "panelBorder" } },
  { "colorButtons", L["Button background"], L["Fill of the buttons."], { "buttonFill" } },
}
Options.COLOR_OPTIONS = COLOR_OPTIONS
Options.colorTargets = {}
for _, o in ipairs(COLOR_OPTIONS) do Options.colorTargets[o[1]] = o[4] end

-- Any single color differs from the preset `settings.colorPreset`.
function Options.presetEdited(settings)
  if type(settings) ~= "table" then return false end
  for _, o in ipairs(COLOR_OPTIONS) do
    local spec = Options.byKey[o[1]]
    if spec and Options.normalize(spec, settings[o[1]]) ~= Options.defaultFor(o[1], settings) then return true end
  end
  return false
end

local refreshPanel = Options.refreshPanel
local say = ns.Util.say

-- Preset names shown in the panel (Theme.presets keep the English ones).
local PRESET_LABELS = { midnight = L["Midnight"], tsm = L["TSM-style"] }

-- The player's own color presets: AnotherLedgerDB.colorPresets (every
-- profile sees them), a list of { name, base = a Theme.presets id, colors =
-- { [color option key] = "rrggbb" } }. The option value of one is
-- Options.USER_PRESET .. name. A Theme color no option sets comes from `base`.
Options.USER_PRESET = "user:"
Options.MAX_PRESET_NAME = 32

local function validOwn(p)
  return type(p) == "table" and type(p.name) == "string" and p.name ~= "" and type(p.colors) == "table"
end

local function ownList()
  local db = ns.db
  if type(db) ~= "table" then return {} end
  if type(db.colorPresets) ~= "table" then db.colorPresets = {} end
  return db.colorPresets
end

-- The own preset whose option value is `id`, and its index; or nil.
function Options.userPreset(id)
  local prefix = Options.USER_PRESET
  if type(id) ~= "string" or id:sub(1, #prefix) ~= prefix then return nil end
  local name = id:sub(#prefix + 1)
  for i, p in ipairs(ownList()) do
    if validOwn(p) and p.name == name then return p, i end
  end
  return nil
end

-- The Theme.presets id a preset stands on: itself, or an own preset's base
-- (unknown: the first preset, the AnotherLedger look).
function Options.basePreset(id)
  local own = Options.userPreset(id)
  if own then id = own.base end
  local p = ns.Theme and ns.Theme.preset(id)
  if p then return p.id end
  return ns.Theme and ns.Theme.presets[1].id or nil
end

-- The "rrggbb" of color option `key` in preset `id` (built-in or own), or nil.
function Options.presetColor(id, key)
  local targets = Options.colorTargets and Options.colorTargets[key]
  if not targets then return nil end
  local own = Options.userPreset(id)
  if own then
    local hex = own.colors[key]
    if type(hex) == "string" and hex:match("^%x%x%x%x%x%x$") then return hex:lower() end
    id = own.base
  end
  local p = ns.Theme and ns.Theme.preset(id)
  return p and p.colors[targets[1]] or nil
end

-- Saves the current single colors of `db.settings` as own preset `name`
-- and makes it the chosen preset. A name an own preset already has
-- (any case) needs `replace`. Returns the option value; or nil, the reason,
-- and for a taken name "exists" as the reason plus the stored name.
function Options.saveColorPreset(db, name, replace)
  if type(db) ~= "table" or type(ns.db) ~= "table" then return nil, L["Enter a name."] end
  local trimmed = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if trimmed == "" then return nil, L["Enter a name."] end
  if #trimmed > Options.MAX_PRESET_NAME then return nil, L["The name is too long."] end
  local lower = trimmed:lower()
  for _, p in ipairs(ns.Theme.presets) do
    if p.id == lower or p.label:lower() == lower or (PRESET_LABELS[p.id] or ""):lower() == lower then
      return nil, L["A built-in color preset has this name."]
    end
  end
  local list = ownList()
  local index
  for i, p in ipairs(list) do
    if validOwn(p) and p.name:lower() == lower then index = i end
  end
  if index and not replace then return nil, "exists", list[index].name end
  local colors = {}
  for _, o in ipairs(COLOR_OPTIONS) do colors[o[1]] = Options.get(db, o[1]) end
  local entry = { name = index and list[index].name or trimmed,
    base = Options.basePreset(Options.get(db, "colorPreset")), colors = colors }
  if index then list[index] = entry else list[#list + 1] = entry end
  return Options.set(db, "colorPreset", Options.USER_PRESET .. entry.name)
end

-- Deletes the own preset `id`. Every profile that used it keeps its colors:
-- it moves to the own preset's base with the own colors filled in.
-- Returns true, or false and the reason.
function Options.deleteColorPreset(id)
  local own, index = Options.userPreset(id)
  if not own then return false, L["Pick one of your own color presets first."] end
  local base = Options.basePreset(id)
  local profiles = type(ns.db.profiles) == "table" and ns.db.profiles or {}
  local touched = { ns.db.settings }
  for _, s in pairs(profiles) do touched[#touched + 1] = s end
  for _, s in ipairs(touched) do
    if type(s) == "table" and s.colorPreset == id then
      for _, o in ipairs(COLOR_OPTIONS) do
        if s[o[1]] == nil then s[o[1]] = Options.presetColor(id, o[1]) end
      end
      s.colorPreset = base
    end
  end
  table.remove(ns.db.colorPresets, index)
  return true
end

-- ---------------------------------------------------------------------------
-- Skins (category "look", before the colors): the shape of the border,
-- buttons and lines (Theme.skins). A skin writes its four parts
-- when picked; each part sets Theme.style and redraws (Widgets.applySkin).
-- Skins never change colors.

-- option key, Theme.style part
Options.SKIN_PARTS = {
  { "skinBorder", "border" }, { "skinButtons", "buttons" },
  { "skinLines", "lines" }, { "skinListBox", "listBox" }, { "skinTabs", "tabs" },
}
Options.skinTargets = {}
for _, p in ipairs(Options.SKIN_PARTS) do Options.skinTargets[p[1]] = p[2] end

local SKIN_LABELS = { modern = L["Modern"], classic = L["Classic"], forge = L["Forge"], slate = L["Slate"],
  gilded = L["Gilded"] }
local STYLE_LABELS = {
  rounded = L["Rounded"], round = L["Round"], bevel = L["Bevel"], thin = L["Thin"], gilded = L["Gilded"],
  zebra = L["Zebra"], pills = L["Pills"], folder = L["Folder"],
  flat = L["Flat"], bronze = L["Bronze"], raised = L["Raised"],
  gold = L["Gold"], groove = L["Groove"], plain = L["Plain"], dotted = L["Dotted"],
}

-- Any part differs from the skin `settings.skin`.
function Options.skinEdited(settings)
  if type(settings) ~= "table" then return false end
  for _, p in ipairs(Options.SKIN_PARTS) do
    local spec = Options.byKey[p[1]]
    if spec and Options.normalize(spec, settings[p[1]]) ~= Options.defaultFor(p[1], settings) then return true end
  end
  return false
end

local function applySkin()
  local W = ns.UI and ns.UI.Widgets
  if W and W.applySkin then W.applySkin() end
end

Options.define({
  key = "skin", category = "look", type = "dropdown", label = L["Skin"],
  tooltip = L["Sets the border, buttons, lines, tabs and list box at once. Modern also sets its font (Inter) and colors (Polaris); the others keep yours. You can change single parts afterwards."],
  choices = function()
    local out = {}
    for _, s in ipairs(ns.Theme.skins) do out[#out + 1] = { value = s.id, label = SKIN_LABELS[s.id] or s.label } end
    return out
  end,
  format = function(v)
    local s = ns.Theme.skin(v)
    local text = s and (SKIN_LABELS[s.id] or s.label) or tostring(v)
    if ns.db and Options.skinEdited(ns.db.settings) then text = text .. L[" (edited)"] end
    return text
  end,
  -- Modern also brings its font and color preset (as if picked by hand, so
  -- the single colors follow the preset).
  picked = function(db, v)
    local s = ns.Theme.skin(v)
    if s then
      for _, p in ipairs(Options.SKIN_PARTS) do Options.set(db, p[1], s[p[2]]) end
      if s.font then Options.set(db, "fontFace", s.font) end
      if s.preset then Options.pick(db, "colorPreset", s.preset) end
    end
    refreshPanel()
  end,
})

local SKIN_TOOLTIPS = {
  border = L["Frame of the window and the options. Round has rounded corners and tabs; the others are square."],
  buttons = L["Shape of every button: Bronze is shaded, Raised has a light top and a dark bottom edge, Flat is one color with a thin edge."],
  lines = L["Lines between the rows, under the tabs and above Top finds. Zebra shades every other row instead of lines between them."],
  tabs = L["Shape of the tabs: Pills are flat with a line under the chosen tab, Folder tabs have an edge like the border."],
}
local SKIN_PART_LABELS = { border = L["Border"], buttons = L["Buttons"], lines = L["Lines"], tabs = L["Tabs"] }

for _, p in ipairs(Options.SKIN_PARTS) do
  local key, part = p[1], p[2]
  local spec = { key = key, category = "look",
    apply = function(v)
      ns.Theme.setStyle(part, v)
      applySkin()
    end,
    -- The skin dropdown shows "(edited)" from now on.
    picked = function() refreshPanel() end }
  if part == "listBox" then
    spec.type, spec.label = "checkbox", L["Sunken list"]
    spec.tooltip = L["Draws a darker sunken box behind the list rows."]
  else
    spec.type, spec.label, spec.tooltip = "dropdown", SKIN_PART_LABELS[part], SKIN_TOOLTIPS[part]
    spec.choices = function()
      local out = {}
      for _, v in ipairs(ns.Theme.skinParts[part]) do out[#out + 1] = { value = v, label = STYLE_LABELS[v] or v } end
      return out
    end
  end
  Options.define(spec)
end

-- Color preset: first in Colors so Options.applyAll sets the whole palette
-- before the single colors are applied on top of it. The last entry saves
-- the current colors as an own preset.
Options.define({
  key = "colorPreset", category = "look", type = "dropdown", label = L["Color preset"],
  tooltip = L["Sets the whole look of the window, the buttons and the tooltips at once. You can change single colors afterwards and save them as your own preset with the last entry."],
  choices = function()
    local out = {}
    for _, p in ipairs(ns.Theme.presets) do out[#out + 1] = { value = p.id, label = PRESET_LABELS[p.id] or p.label } end
    local names = {}
    for _, p in ipairs(ownList()) do
      if validOwn(p) then names[#names + 1] = p.name end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    for _, name in ipairs(names) do out[#out + 1] = { value = Options.USER_PRESET .. name, label = name } end
    out[#out + 1] = { value = Options.CUSTOM, label = L["Save as preset..."] }
    return out
  end,
  format = function(v)
    local own = Options.userPreset(v)
    local p = ns.Theme.preset(v)
    local text = own and own.name or p and (PRESET_LABELS[p.id] or p.label) or tostring(v)
    if ns.db and Options.presetEdited(ns.db.settings) then text = text .. L[" (edited)"] end
    return text
  end,
  apply = function(v)
    local changed = ns.Theme.applyPreset(Options.basePreset(v))
    -- The stored single colors stay on top of the preset.
    if ns.db then
      for _, o in ipairs(COLOR_OPTIONS) do
        local hex = Options.get(ns.db, o[1])
        for _, key in ipairs(o[4]) do
          local c = ns.Theme.setColor(key, hex)
          if c then changed[c] = true end
        end
      end
    end
    local UI = ns.UI
    if UI and UI.Widgets and UI.Widgets.recolor then UI.Widgets.recolor(changed) end
    applyWindowLook()
    refreshUI()
  end,
  picked = function(db, v)
    for _, o in ipairs(COLOR_OPTIONS) do
      local hex = Options.presetColor(v, o[1])
      if hex then Options.set(db, o[1], hex) end
    end
    refreshPanel()
  end,
  -- "Save as preset...": asks for a name (an own preset's name overwrites it
  -- after a question).
  intercept = function(db, value)
    if value ~= Options.CUSTOM then return false end
    local W = ns.UI and ns.UI.Widgets
    if not (W and W.prompt) then return true end
    local own = Options.userPreset(Options.get(db, "colorPreset"))
    W.prompt(L["Name of the color preset:"], L["Save"], own and own.name or "", function(text)
      local id, err, taken = Options.saveColorPreset(db, text)
      if not id and err == "exists" then
        if W.confirm then
          W.confirm(string.format(L["Overwrite the color preset %s?"], taken), L["Overwrite"], function()
            Options.saveColorPreset(db, text, true)
            refreshPanel()
          end)
        end
        return
      end
      if not id then say(err) end
      refreshPanel()
    end)
    return true
  end,
})

for _, o in ipairs(COLOR_OPTIONS) do
  Options.define({ key = o[1], category = "look", type = "color", label = o[2], tooltip = o[3],
    colors = o[4], apply = applyColors(o[4]),
    -- The preset dropdown shows "(edited)" from now on.
    picked = function() refreshPanel() end })
end

Options.define({
  key = "resetColors", category = "look", type = "button", label = L["Reset colors"],
  tooltip = L["Sets every color back to the chosen color preset."],
  action = function()
    if not ns.db then return end
    -- Back to the chosen preset (its colors, no "(edited)").
    Options.pick(ns.db, "colorPreset", Options.get(ns.db, "colorPreset"))
    refreshPanel()
  end,
})

Options.define({
  key = "deleteColorPreset", category = "look", type = "button", label = L["Delete color preset"],
  tooltip = L["Deletes the chosen color preset if it is one of your own. The colors stay as they are."],
  action = function()
    if not ns.db then return end
    local id = Options.get(ns.db, "colorPreset")
    local own = Options.userPreset(id)
    if not own then return say(L["Pick one of your own color presets first."]) end
    local W = ns.UI and ns.UI.Widgets
    if W and W.confirm then
      W.confirm(string.format(L["Delete the color preset %s?"], own.name), L["Delete"], function()
        local ok, err = Options.deleteColorPreset(id)
        if not ok then say(err) end
        refreshPanel()
      end)
    end
  end,
})
