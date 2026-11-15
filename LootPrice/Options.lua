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
--     label   = "Opacity",            -- short; the details go in tooltip
--     tooltip = "Fades the window...", -- shown on hover with the default (Options.tooltip)
--     zeroText = "Off",               -- number: text of 0 (optional)
--     min = 0.1, max = 1, step = 0.05, -- slider
--     choices = { { value = "a", label = L["A"] }, ... }, -- dropdown (or a function returning that list)
--     (labels go through ns.L, Locale.lua: L["Opacity"])
--     (number: whole number >= 0, or -1 = unlimited; typed into a text box)
--     (text: any non-empty text; button: has no value, `action` runs on click)
--     format  = function(v) ... end,  -- optional display text of the value
--     apply   = function(value) ... end, -- optional: make the value take effect
--     confirm = function(value) ... end, -- optional: a question (text) the panel
--                                        -- asks before storing value, or nil
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
  if spec.type == "checkbox" then return value and L["On"] or L["Off"] end
  if spec.type == "number" and num(value) and value < 0 then return L["Unlimited"] end
  if spec.type == "number" and value == 0 and spec.zeroText then return spec.zeroText end
  if spec.type == "dropdown" then
    for _, c in ipairs(Options.choices(spec)) do
      if c.value == value then return c.label end
    end
  end
  return tostring(value)
end

-- The hover tooltip of an option (ns.Tooltip): its label as title, what it
-- does, and its default value (not for a button).
function Options.tooltip(spec)
  local Tip = ns.Tooltip
  local tip = Tip.new(spec.label)
  if spec.tooltip then Tip.para(tip, spec.tooltip) end
  if spec.type ~= "button" then
    Tip.note(tip, L["Default: "] .. Options.valueText(spec, Options.normalize(spec, nil)))
  end
  return tip
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
-- harmless before the window exists (and in the tests). Labels are short; the
-- details are in `tooltip` (shown on hover in the panel, Options.tooltip).

local function refreshUI()
  if ns.UI and ns.UI.refresh then ns.UI.refresh() end
end

local function percent(v) return math.floor(v * 100 + 0.5) .. "%" end

local function applyWindowLook()
  if ns.UI and ns.UI.Window and ns.UI.Window.applyLook then ns.UI.Window.applyLook() end
end

-- Window background and border.
Options.define({
  key = "alpha", category = "window", type = "slider", label = L["Opacity"],
  tooltip = L["Fades the window's background and border. Text and rows stay fully visible."],
  min = 0, max = 1, step = 0.05, format = percent, apply = applyWindowLook,
})

-- 100 % is the theme color; above that the dark panel gets lighter.
Options.define({
  key = "brightness", category = "window", type = "slider", label = L["Brightness"],
  tooltip = L["Makes the dark background lighter or darker. 100% is the normal look, 0% is black."],
  min = 0, max = 2, step = 0.05, format = percent, apply = applyWindowLook,
})

Options.define({
  key = "windowScale", category = "window", type = "slider", label = L["Scale"],
  tooltip = L["Size of the whole window. It keeps its center on the screen."],
  min = 0.7, max = 1.5, step = 0.05, format = percent,
  apply = function()
    if ns.UI and ns.UI.Window and ns.UI.Window.applyScale then ns.UI.Window.applyScale() end
  end,
})

Options.define({ key = "lockWindow", category = "window", type = "checkbox", label = L["Lock window"],
  tooltip = L["The window can't be moved or resized."] })

Options.define({ key = "startHidden", category = "window", type = "checkbox", label = L["Start hidden"],
  tooltip = L["The window stays closed at login. Open it with the minimap button or /lp."] })

Options.define({
  key = "combatHide", category = "window",
  type = "checkbox",
  label = L["Hide in combat"],
  tooltip = L["Hides the window when combat starts and shows it again afterwards, but only if it was open. A window you closed yourself stays closed."],
  apply = function(v)
    if not v and ns.UI and ns.UI.Window and ns.UI.Window.combatShow then ns.UI.Window.combatShow() end
  end,
})

Options.define({ key = "keepSession", category = "session", type = "checkbox", label = L["Keep session"],
  tooltip = L["The session and its clock carry over to your next login instead of starting fresh. Same as /lp keep."] })

Options.define({
  key = "priceSource", category = "prices",
  type = "dropdown",
  label = L["AH price source"],
  tooltip = L["Where auction prices come from. Auto asks TSM first, then Auctionator."],
  -- "Auto" plus every registered price source (Sources/Sources.lua).
  choices = function() return ns.Sources.choices() end,
  apply = refreshUI,
})

-- The TSM price string, read live by Sources/TSM.lua (same as /lp tsm).
Options.define({
  key = "tsmSource", category = "prices", type = "text", label = L["TSM price"],
  tooltip = L["The TSM price used for AH values, e.g. DBMarket or DBMinBuyout. Same as /lp tsm."],
  apply = refreshUI,
})

-- TSM region sale info under the item name (Sources/TSM.lua TSM.market) and
-- the cutoffs of its levels (View.marketLevels).
Options.define({
  key = "showMarket", category = "prices", type = "checkbox", label = L["TSM sale info"],
  tooltip = L["With TSM loaded, shows under each item name how well it sells in your region (well / okay / poorly) and how many sell per day."],
  apply = refreshUI,
})

-- The two cutoffs of a level pair stay in order: moving one past the other
-- moves the other along (the middle level could never show otherwise). The
-- stored value is written directly (no apply loop); a negative top cutoff
-- (number option: empty = never) leaves the middle one free.
local function keepOrder(topKey, midKey, changed)
  local db = ns.db
  if not (db and db.settings) then return end
  local top, mid = Options.get(db, topKey), Options.get(db, midKey)
  if not (num(top) and num(mid)) or top < 0 or mid <= top then return end
  if changed == topKey then db.settings[midKey] = top else db.settings[topKey] = mid end
  local panel = ns.UI and ns.UI.OptionsPanel
  if panel and panel.refreshAll then panel.refreshAll() end
end
Options.keepOrder = keepOrder

local function ordered(topKey, midKey, changed)
  return function()
    keepOrder(topKey, midKey, changed)
    refreshUI()
  end
end

local function rate(v) return string.format("%.2f", v) end
Options.define({ key = "saleRateGood", category = "prices", type = "slider", label = L["Sells well from"],
  tooltip = L["Region sale rate (0 to 1) from which an item counts as selling well."],
  min = 0, max = 1, step = 0.01, format = rate, apply = ordered("saleRateGood", "saleRateOk", "saleRateGood") })
Options.define({ key = "saleRateOk", category = "prices", type = "slider", label = L["Sells okay from"],
  tooltip = L["Region sale rate from which an item counts as selling okay. Below it, it sells poorly."],
  min = 0, max = 1, step = 0.01, format = rate, apply = ordered("saleRateGood", "saleRateOk", "saleRateOk") })
Options.define({ key = "soldHigh", category = "prices", type = "number", label = L["High volume from"],
  tooltip = L["Average number sold per day in your region from which an item is High volume. Empty = never."],
  apply = ordered("soldHigh", "soldMedium", "soldHigh") })
Options.define({ key = "soldMedium", category = "prices", type = "number", label = L["Medium volume from"],
  tooltip = L["Average number sold per day from which an item is Medium volume. Below it, Low volume."],
  apply = ordered("soldHigh", "soldMedium", "soldMedium") })

Options.define({
  key = "refreshSeconds", category = "prices", type = "slider", label = L["Price refresh"],
  tooltip = L["How often prices and age tags are looked up again while the clock runs. The Daily farm is worked out again at the same pace."],
  min = 10, max = 120, step = 5, format = function(v) return v .. " s" end,
})

-- After this long a cached AH price shows its age tag in orange.
Options.define({
  key = "staleHours", category = "prices", type = "slider", label = L["Old price after"],
  tooltip = L["A cached AH price older than this shows its age tag in orange."],
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
  label = L["Sort at login"],
  tooltip = L["The list's order at every login. The sort button still changes it for the rest of the session."],
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
  label = L["Large amounts"],
  tooltip = L["How amounts of 1 gold and more are shown: all coins, gold and silver, or gold only. Smaller amounts always show in full."],
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

-- Coin icons in place of g / s / c; the window's minimum width follows (an
-- icon is wider than a letter), so the sizes are re-applied too.
Options.define({
  key = "coinIcons", category = "display", type = "checkbox",
  label = L["Coin icons"],
  tooltip = L["Shows the game's coin icons instead of the letters g, s and c, wherever amounts appear."],
  apply = function(v)
    if ns.Money then ns.Money.setIcons(v) end
    -- New minimum width, and the rows measure their amount column again.
    local UI = ns.UI
    if UI and UI.Fonts and UI.Fonts.applySizes and ns.db then UI.Fonts.applySizes(ns.db) end
    if UI and UI.Ledger and UI.Ledger.relayout then UI.Ledger.relayout() end
    refreshUI()
  end,
})

Options.define({
  key = "includeGold", category = "display", type = "checkbox", label = L["Raw gold in Total"],
  tooltip = L["Adds the gold you looted to the Total row of the footer. Off leaves the Total row out."],
  apply = refreshUI,
})

-- Chat line when one drop is worth at least this much (gold). Empty / 0 = off.
Options.define({
  key = "alertGold", category = "session", type = "number", label = L["Drop alert (gold)"],
  tooltip = L["A chat line when one drop is worth at least this much gold. 0 or empty turns it off."],
  zeroText = L["Off"],
})

Options.define({ key = "alertSound", category = "session", type = "checkbox", label = L["Alert sound"],
  tooltip = L["Plays a sound with the drop alert."] })

-- Off: "You create" messages and items received while a merchant, mailbox,
-- trade or auction house window is open are not loot.
Options.define({
  key = "countCrafted", category = "session", type = "checkbox", label = L["Crafted and bought"],
  tooltip = L["Counts items you craft, and items you get at a vendor, mailbox, trade or the auction house, as loot."],
})

Options.define({ key = "afkPause", category = "session", type = "checkbox", label = L["Pause when AFK"],
  tooltip = L["Stops the clock while you are AFK and starts it again when you are back."] })

Options.define({
  key = "instanceSession", category = "session", type = "checkbox",
  label = L["Session per instance"],
  tooltip = L["Saves the session to History and starts a new one whenever you enter or leave a dungeon or raid."],
})

Options.define({
  key = "showCurrencies", category = "display", type = "checkbox", label = L["Currencies"],
  tooltip = L["Lists looted currencies after the items."],
  apply = refreshUI,
})

-- Daily farm strip at the top of the window (View.dailyFarm): the saved place
-- with the best gold per hour; only places with this much recorded time count.
Options.define({
  key = "dailyFarm", category = "display", type = "checkbox", label = L["Daily farm"],
  tooltip = L["Shows the Daily strip: the place in your History with the best gold per hour at today's prices."],
  apply = refreshUI,
})

Options.define({
  key = "dailyFarmMinutes", category = "display", type = "slider", label = L["Daily farm: min. time"],
  tooltip = L["How long you must have farmed a place before the Daily strip can pick it."],
  min = 5, max = 120, step = 5, format = function(v) return v .. " min" end, apply = refreshUI,
})

-- Off: the Top finds block under the footer stays collapsed.
Options.define({
  key = "showTopFinds", category = "display", type = "checkbox", label = L["Top finds"],
  tooltip = L["Shows the session's three most valuable finds under the footer."],
  apply = refreshUI,
})

-- Off: the footer table has no Raw gold row (Total still follows includeGold).
Options.define({
  key = "showFooterGold", category = "display", type = "checkbox", label = L["Raw gold row"],
  tooltip = L["Shows the Raw gold row in the footer table."],
  apply = refreshUI,
})

-- Compact mode: how many of the last drops it lists (0 hides the block).
Options.define({
  key = "compactDrops", category = "display", type = "slider", label = L["Compact: last drops"],
  tooltip = L["How many of the last drops the compact window lists. 0 hides them."],
  min = 0, max = 4, step = 1, apply = refreshUI,
})

-- Off: the list rows have no icon and their text starts at the left edge.
Options.define({
  key = "showIcons", category = "display", type = "checkbox", label = L["Item icons"],
  tooltip = L["Shows the item icon at the start of each list row. Off starts the text at the left edge."],
  apply = function()
    if ns.UI and ns.UI.Ledger and ns.UI.Ledger.relayout then ns.UI.Ledger.relayout() end
  end,
})

-- Typeface of all addon text; changes live. "WoW default" keeps the game's own font.
Options.define({
  key = "fontFace", category = "display",
  type = "dropdown",
  label = L["Font"],
  tooltip = L["Typeface of all LootPrice text. WoW default uses the game font of your client's language. Other addons are not affected."],
  choices = function()
    if ns.UI and ns.UI.Fonts then return ns.UI.Fonts.choices() end
    return { { value = "default", label = L["WoW default"] } }
  end,
  apply = function(v)
    if ns.UI and ns.UI.Fonts then ns.UI.Fonts.applyFace(v) end
  end,
})

-- Font sizes (UI/Fonts.lua): a dropdown of whole px sizes; applied live, the
-- window re-lays itself out.
local function sizeChoices(min, max)
  local list = {}
  for v = min, max do list[#list + 1] = { value = v, label = v .. " px" } end
  return list
end
-- Re-applies every size and re-lays the window out when one changed.
local function applySizes()
  if ns.UI and ns.UI.Ledger and ns.UI.Ledger.applySizes then ns.UI.Ledger.applySizes() end
end
Options.define({ key = "fontSizeRows", category = "display", type = "dropdown", label = L["List text"],
  tooltip = L["Size of the list text. The rows grow and shrink with it."],
  choices = sizeChoices(8, 18), apply = applySizes })
Options.define({ key = "fontSizeTotals", category = "display", type = "dropdown", label = L["Totals text"],
  tooltip = L["Size of the footer table and Top finds."],
  choices = sizeChoices(8, 18), apply = applySizes })
Options.define({ key = "fontSizeTitles", category = "display", type = "dropdown", label = L["Section titles"],
  tooltip = L["Size of section titles such as Top finds."],
  choices = sizeChoices(10, 24), apply = applySizes })

-- Round button on the minimap (UI/Minimap.lua).
Options.define({
  key = "minimapButton", category = "window",
  type = "checkbox",
  label = L["Minimap button"],
  tooltip = L["Shows the LootPrice button on the minimap. Left-click shows or hides the window, right-click opens these options."],
  apply = function(v)
    if ns.UI and ns.UI.Minimap then ns.UI.Minimap.setShown(v) end
  end,
})

Options.define({
  key = "minimapReset", category = "window", type = "button", label = L["Reset minimap button"],
  tooltip = L["Moves the minimap button back to the bottom left of the minimap."],
  action = function()
    if ns.UI and ns.UI.Minimap then ns.UI.Minimap.resetPosition() end
  end,
})

Options.define({
  key = "exportHistory", category = "session", type = "button", label = L["Export History"],
  tooltip = L["Opens a copy box with your History as CSV, for a spreadsheet. Same as /lp export."],
  action = function()
    if ns.UI and ns.UI.Export then ns.UI.Export.history() end
  end,
})

-- How many finished sessions the History tab keeps. Lowering it prunes at once.
Options.define({
  key = "historyLimit", category = "session",
  type = "number",
  label = L["History kept"],
  tooltip = L["How many sessions History keeps. 0 keeps none, empty keeps all. Lowering it asks first, then deletes the oldest."],
  -- The panel asks before a lower limit deletes saved sessions.
  confirm = function(v)
    local history = ns.chardb and ns.chardb.history
    local n = type(history) == "table" and #history or 0
    if not num(v) or v < 0 or n <= v then return nil end
    return string.format(L["Delete the %d oldest sessions of your History? This can't be undone."], n - v)
  end,
  apply = function(v)
    if ns.History and ns.chardb and type(ns.chardb.history) == "table" then
      ns.History.prune(ns.chardb.history, v)
    end
    refreshUI()
  end,
})

ns.Options = Options
