local ADDON, ns = ...

local L = ns.L

-- Options registry. Every option is one table passed to Options.define; the
-- options panel (UI/OptionsPanel.lua) builds its widgets from the list, so a
-- new option never touches the panel:
--
--   Options.define({
--     key     = "alpha",              -- db.settings[key] (default in DB.defaults.settings)
--     type    = "slider",             -- slider | dropdown | checkbox | number | text | color | button (see OptionsPanel.WIDGETS)
--     category = "window",            -- section of the panel (Options.CATEGORIES)
--     label   = "Opacity",            -- short; the details go in tooltip
--     tooltip = "Fades the window...", -- shown on hover with the default (Options.tooltip)
--     zeroText = "Off",               -- number: text of 0 (optional)
--     tooltipExtra = function() -> text or nil, -- a live line for the tooltip (optional)
--     min = 0.1, max = 1, step = 0.05, -- slider
--     choices = { { value = "a", label = L["A"] }, ... }, -- dropdown (or a function returning that list)
--     (labels go through ns.L, Locale.lua: L["Opacity"])
--     (number: whole number >= 0, or -1 = unlimited; typed into a text box)
--     (text: any non-empty text; button: has no value, `action` runs on click)
--     (color: "rrggbb"; `colors` = the Theme.colors keys it sets)
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

-- Vertical size (px) of one option block in the panel, by type (the controls
-- in it: Theme.options).
Options.HEIGHTS = { slider = 38, dropdown = 40, checkbox = 22, number = 38, text = 38, color = 22, button = 22, header = 22 }
Options.GAP = 6

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
  { id = "display", label = L["List"] },
  { id = "session", label = L["Session"] },
  { id = "history", label = L["History"] },
  { id = "look", label = L["Look"] },
  { id = "profiles", label = L["Profiles"] },
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

-- The value of a "Custom..." dropdown entry; never stored.
Options.CUSTOM = "\1custom"

-- The choices of a dropdown option; a function is asked each time, so a list
-- that grows later (price sources) is always current.
function Options.choices(spec)
  local choices = spec.choices
  if type(choices) == "function" then choices = choices() end
  return type(choices) == "table" and choices or {}
end

-- The default of an option. A color option's default is the color of the
-- preset `settings.colorPreset` (default: the active settings, ns.db), so
-- right-click "default" and the export compare against the chosen preset.
function Options.defaultFor(key, settings)
  local colors = Options.colorTargets and Options.colorTargets[key]
  if colors then
    if type(settings) ~= "table" then settings = ns.db and ns.db.settings end
    local id = type(settings) == "table" and settings.colorPreset or nil
    local p = ns.Theme and ns.Theme.preset(id)
    if p and p.colors[colors[1]] then return p.colors[colors[1]] end
  end
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
  elseif spec.type == "text" or (spec.type == "dropdown" and spec.free) then
    -- A `free` dropdown also keeps any typed text (TSM price strings).
    if type(value) ~= "string" or value == Options.CUSTOM then return default end
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
  elseif spec.type == "color" then
    if type(value) ~= "string" then return default end
    local hex = value:match("^%s*#?(%x%x%x%x%x%x)%s*$")
    if not hex then return default end
    return hex:lower()
  end
  return default
end

-- Where an option's value is stored: db.account for `account = true`
-- options (shared by every profile), else db.settings (the active profile).
local function store(db, spec)
  if type(db) ~= "table" then return nil end
  if spec.account then return db.account end
  return db.settings
end

-- An option with `get` / `store` functions keeps its value elsewhere (the
-- profile choice: LootLedgerCharDB); Options.applyAll skips it.
function Options.get(db, key)
  local spec = Options.byKey[key]
  if not spec then return nil end
  if spec.get then return spec.get() end
  local t = store(db, spec)
  local value
  if type(t) == "table" then value = t[key] end -- may be false
  return Options.normalize(spec, value)
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
  local v = Options.normalize(spec, value)
  if spec.store then
    spec.store(v)
    return v
  end
  local field = spec.account and "account" or "settings"
  if type(db[field]) ~= "table" then db[field] = {} end
  db[field][key] = v
  if spec.apply then spec.apply(v) end
  return v
end

-- A player's choice in the options panel: Options.set, then the option's
-- `picked(db, value)` (things only a fresh choice does, e.g. a color preset
-- writing the single colors; never run by Options.applyAll). An option's
-- `intercept(db, value)` runs first; when it returns true nothing is set
-- (the "Custom..." entry opening a text box).
function Options.pick(db, key, value)
  local spec = Options.byKey[key]
  if spec and spec.intercept and spec.intercept(db, value) then return Options.get(db, key) end
  local v = Options.set(db, key, value)
  if spec and spec.picked and type(db) == "table" then spec.picked(db, v) end
  return v
end

-- Applies every stored value (login): repairs invalid saved values as it goes.
function Options.applyAll(db)
  for _, spec in ipairs(Options.specs) do
    if spec.type ~= "button" and not spec.store then Options.set(db, spec.key, Options.get(db, spec.key)) end
  end
end

-- Text of a value for the panel: the spec's formatter, the choice label or the
-- plain value.
function Options.valueText(spec, value)
  if spec.format then return spec.format(value) end
  if spec.type == "checkbox" then return value and L["On"] or L["Off"] end
  if spec.type == "number" and num(value) and value < 0 then return L["Unlimited"] end
  if spec.type == "number" and value == 0 and spec.zeroText then return spec.zeroText end
  if spec.type == "color" and type(value) == "string" then return "#" .. value:upper() end
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
  -- Live facts (the profile's characters), worked out on hover.
  local extra = spec.tooltipExtra and spec.tooltipExtra()
  if type(extra) == "string" and extra ~= "" then Tip.note(tip, extra) end
  if spec.type ~= "button" then
    Tip.note(tip, L["Default: "] .. Options.valueText(spec, Options.normalize(spec, nil)))
  end
  if spec.type == "color" then Tip.hint(tip, L["Click: pick a color. Right-click: default."]) end
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
  tooltip = L["Fades the background and border of the window and the options window. Text and rows stay fully visible."],
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
  tooltip = L["The window can't be moved or resized."],
  apply = function()
    if ns.UI and ns.UI.Window and ns.UI.Window.applyLock then ns.UI.Window.applyLock() end
  end,
})

Options.define({ key = "snapToGrid", category = "window", type = "checkbox", label = L["Snap to grid"],
  tooltip = L["When you let go of the window near a line of the Edit Mode grid, its edge or center snaps onto that line. Uses the grid spacing set in Edit Mode."] })

Options.define({ key = "startHidden", category = "window", type = "checkbox", label = L["Start hidden"],
  tooltip = L["The window stays closed at login. Open it with the minimap button or /ll."] })

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
  tooltip = L["The session and its clock carry over to your next login instead of starting fresh. Same as /ll keep."] })

-- Off: "You create" messages and items received while a merchant, mailbox,
-- trade or auction house window is open are not loot.
Options.define({
  key = "countCrafted", category = "session", type = "checkbox", label = L["Crafted and bought"],
  tooltip = L["Counts items you craft, and items you get at a vendor, mailbox, trade or the auction house, as loot."],
})

Options.define({
  key = "priceSource", category = "prices",
  type = "dropdown",
  label = L["AH price source"],
  tooltip = L["Where auction prices come from. Auto asks TSM first, then Auctionator."],
  -- "Auto" plus every registered price source (Sources/Sources.lua).
  choices = function() return ns.Sources.choices() end,
  apply = refreshUI,
})

-- The TSM price string, read live by Sources/TSM.lua (same as /ll tsm): the
-- common TSM prices, a typed one as its own entry, and "Custom..." to type one.
local TSM_PRICES = { "DBMarket", "DBMinBuyout", "DBRegionMarketAvg", "DBRecent", "DBHistorical" }
Options.define({
  key = "tsmSource", category = "prices", type = "dropdown", free = true, label = L["TSM price"],
  tooltip = L["The TSM price used for AH values, e.g. DBMarket or DBMinBuyout. Same as /ll tsm."],
  choices = function()
    local list, known = {}, {}
    for _, p in ipairs(TSM_PRICES) do
      list[#list + 1] = { value = p, label = p }
      known[p] = true
    end
    local t = ns.db and ns.db.settings
    local current = type(t) == "table" and t.tsmSource or nil
    if type(current) == "string" and current ~= "" and not known[current] and current ~= Options.CUSTOM then
      list[#list + 1] = { value = current, label = current }
    end
    list[#list + 1] = { value = Options.CUSTOM, label = L["Custom..."] }
    return list
  end,
  intercept = function(db, value)
    if value ~= Options.CUSTOM then return false end
    local W = ns.UI and ns.UI.Widgets
    if W and W.prompt then
      W.prompt(L["TSM price:"], L["OK"], Options.get(db, "tsmSource"), function(text)
        Options.pick(db, "tsmSource", text)
        local Panel = ns.UI.OptionsPanel
        if Panel and Panel.refreshAll then Panel.refreshAll() end
      end)
    end
    return true
  end,
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
  tooltip = L["How often prices and age tags are looked up again while the window is open. The Daily farm is worked out again at the same pace."],
  min = 10, max = 120, step = 5, format = function(v) return v .. " s" end,
})

-- After this long a cached AH price shows its age tag in orange.
Options.define({
  key = "staleHours", category = "prices", type = "slider", label = L["Old price after"],
  tooltip = L["A cached AH price older than this shows its age tag in orange. The Bank tab's scan note turns orange after the same time."],
  min = 1, max = 72, step = 1, format = function(v) return v .. " h" end,
  apply = function(v)
    if ns.Prices then ns.Prices.STALE_AFTER = v * 3600 end
    refreshUI()
  end,
})

-- Value rules (Prices lookup rules and Prices.best): read at lookup time, so
-- a change only needs a redraw.
Options.define({
  key = "ahCut", category = "prices", type = "checkbox", label = L["AH cut (5%)"],
  tooltip = L["Counts Auction values after the auction house's 5% fee, so they show what you would actually get. Sessions already in History keep the prices they were saved with."],
  apply = refreshUI,
})

Options.define({
  key = "ahMinGain", category = "prices", type = "slider", label = L["Auction from"],
  tooltip = L["An item counts at its Auction value only when that beats its vendor price by this much; else it counts as Vendor. Off counts the Auction value whenever it is higher. The tooltip always shows both."],
  min = 0, max = 100, step = 5,
  format = function(v) return v == 0 and L["Off"] or string.format(L["+%d%% over vendor"], v) end,
  apply = refreshUI,
})

Options.define({
  key = "destroyMode", category = "prices", type = "dropdown", label = L["Destroy values"],
  tooltip = L["When an item counts its disenchant, mill or prospect value: always, only if one of your characters has the profession (Enchanting for gear, Inscription for herbs, Jewelcrafting for ore), only if this character has it, or never."],
  choices = {
    { value = "always", label = L["Always"] },
    { value = "any", label = L["If one of my characters can"] },
    { value = "self", label = L["If this character can"] },
    { value = "never", label = L["Never"] },
  },
  apply = refreshUI,
})

-- Applied at login and whenever changed; the sort button of the filter bar
-- still changes the order for the rest of the session.
Options.define({
  key = "defaultSort", category = "display",
  type = "dropdown",
  label = L["Sort at login"],
  tooltip = L["The list's order at every login. The sort button still changes it for the rest of the session."],
  choices = {
    { value = "ah", label = L["Value"] },
    { value = "vendor", label = L["Vendor"] },
    { value = "name", label = L["Name"] },
    { value = "recent", label = L["Recent"] },
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
  key = "includeGold", category = "display", type = "checkbox", label = L["Count raw gold"],
  tooltip = L["Counts the gold you looted in the totals: the footer's Total row, the compact window, the minimap button text, the History sessions, the place values of Zones and the Daily farm. Off leaves the Total row out."],
  apply = refreshUI,
})

Options.define({ key = "sessionChat", category = "session", type = "checkbox", label = L["Session summary in chat"],
  tooltip = L["When a session is saved to History (Reset, a new session per zone or instance, a fresh login), a chat line sums it up: length, place, worth and gold per hour."] })

Options.define({ key = "afkPause", category = "session", type = "checkbox", label = L["Pause when AFK"],
  tooltip = L["Stops the clock while you are AFK and starts it again when you are back."] })

-- Core.checkRest: the clock stands still in cities and inns; loot still counts.
Options.define({ key = "cityPause", category = "session", type = "checkbox", label = L["Pause in cities"],
  tooltip = L["Stops the clock while you are in a city or inn (resting), so time spent selling and mailing does not lower your gold per hour. Loot and gold still count."],
  apply = function() if ns.Core and ns.Core.checkRest then ns.Core.checkRest() end end })

Options.define({
  key = "instanceSession", category = "session", type = "checkbox",
  label = L["Session per instance"],
  tooltip = L["Saves the session to History and starts a new one whenever you enter or leave a dungeon or raid."],
})

-- Core.zoneSwitch: a new zone only counts once you stayed there this long
-- (a flight path or a short detour does not split the session).
Options.define({
  key = "zoneSession", category = "session", type = "checkbox", label = L["Session per zone"],
  tooltip = L["Saves the session to History and starts a new one when you change zones and stay in the new one (see Zone change delay). Flights don't count."],
})

Options.define({
  key = "zoneSessionMinutes", category = "session", type = "slider", label = L["Zone change delay"],
  tooltip = L["How long you must stay in a new zone before Session per zone starts a new session. Loot from that time still counts for the old session."],
  min = 1, max = 15, step = 1, format = function(v) return v .. " min" end,
})

-- Core.isShort: a short session folds into the next one (manual Reset still
-- saves it).
Options.define({
  key = "minSessionMinutes", category = "session", type = "slider", label = L["Min. session length"],
  tooltip = L["A session shorter than this is not saved to History when a new zone or instance or a fresh login would start a new one; it just continues. Reset always saves it. Off saves every session."],
  min = 0, max = 15, step = 1, format = function(v) return v == 0 and L["Off"] or (v .. " min") end,
})

-- Chat line when one drop is worth at least this much (gold). Empty / 0 = off.
Options.define({
  key = "alertGold", category = "session", type = "number", label = L["Drop alert (gold)"],
  tooltip = L["A chat line when one drop is worth at least this much gold. 0 or empty turns it off."],
  zeroText = L["Off"],
})

Options.define({ key = "alertSound", category = "session", type = "checkbox", label = L["Alert sound"],
  tooltip = L["Plays a sound with the drop alert and when a session goal is reached."] })

-- Session goals (Core.checkGoals): a chat line once reached; the gold goal's
-- progress shows in the compact window and the Session footer.
Options.define({
  key = "goalGold", category = "session", type = "number", label = L["Session goal (gold)"],
  tooltip = L["A target for the session's worth: the compact window shows the total against it, the Session footer how far you are, and a chat line says when it is reached. Counts like the compact total. 0 or empty turns it off."],
  zeroText = L["Off"], apply = refreshUI,
})

Options.define({
  key = "goalMinutes", category = "session", type = "number", label = L["Session goal (minutes)"],
  tooltip = L["A chat line when the session clock reaches this many minutes, with what the session is worth. 0 or empty turns it off."],
  zeroText = L["Off"],
})

Options.define({
  key = "showCurrencies", category = "display", type = "checkbox", label = L["Currencies"],
  tooltip = L["Lists looted currencies after the items."],
  apply = refreshUI,
})

-- Daily farm strip at the top of the window (View.dailyFarm): the saved place
-- with the best gold per hour; only places with this much recorded time count.
Options.define({
  key = "dailyFarm", category = "history", type = "checkbox", label = L["Daily farm"],
  tooltip = L["Shows the Daily strip: the place in your History with the best gold per hour at today's prices."],
  apply = refreshUI,
})

Options.define({
  key = "dailyFarmMinutes", category = "history", type = "slider", label = L["Daily farm: min. time"],
  tooltip = L["How long you must have farmed a place before the Daily strip can pick it."],
  min = 5, max = 120, step = 5, format = function(v) return v .. " min" end, apply = refreshUI,
})

-- History Zones and the Daily farm across characters (Core.zoneHistory).
Options.define({
  key = "accountZones", account = true, category = "history", type = "checkbox", label = L["Zones: all characters"],
  tooltip = L["History Zones and the Daily strip use the History of all your characters. Off: only this character's. The Sessions list always shows this character's."],
  apply = refreshUI,
})

-- Off: the Top finds block under the footer stays collapsed.
Options.define({
  key = "showTopFinds", category = "display", type = "checkbox", label = L["Top finds"],
  tooltip = L["Shows the session's three most valuable finds under the footer."],
  apply = refreshUI,
})

-- Off: the footer table has no Raw gold row (Total still follows includeGold).
Options.define({
  key = "showFooterGold", category = "display", type = "checkbox", label = L["Show raw gold row"],
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

-- The value of one item instead of the stack (Rows.rowText).
Options.define({
  key = "unitPrice", category = "display", type = "checkbox", label = L["Price per unit"],
  tooltip = L["List rows show the value of one item instead of the whole stack. Totals and tooltips stay the same."],
  apply = refreshUI,
})

-- An item list of Core (ignored, kept) as a menu: a click takes an item off
-- the list (or back on while the menu is open). `empty`: the chat line
-- without any items.
local function itemListMenu(button, which, empty)
  local Core, W = ns.Core, ns.UI and ns.UI.Widgets
  if not (Core and W) then return end
  local items, add, remove = Core[which .. "Items"], Core[which == "ignored" and "ignoreItem" or "keepItem"],
    Core[which == "ignored" and "unignoreItem" or "unkeepItem"]
  local list = Core[which .. "List"]()
  if #list == 0 then
    ns.Util.say(empty)
    return
  end
  local entries = {}
  for _, item in ipairs(list) do
    entries[#entries + 1] = {
      text = item.name,
      isChecked = function() return items()[item.id] ~= nil end,
      onClick = function()
        if items()[item.id] ~= nil then remove(item.id) else add(item.id, item.name) end
      end,
    }
  end
  W.openMenu(button, entries, "checkbox")
end

-- The ignore list (Core.ignoredItems).
Options.define({
  key = "ignoredItems", category = "display", type = "button", label = L["Ignored items"],
  tooltip = L["Items you ignored (right-click a row in the list) don't count anywhere. Opens the list: click an item to count it again."],
  action = function(button)
    itemListMenu(button, "ignored", L["no ignored items. Right-click an item in the list to ignore it."])
  end,
})

-- The keep list (Core.keptItems).
Options.define({
  key = "keptItems", category = "display", type = "button", label = L["Kept items"],
  tooltip = L["Items you keep (right-click a row in Bags or Bank) are counted apart: the footer shows what is kept and what you can sell. Opens the list: click an item to sell it again."],
  action = function(button)
    itemListMenu(button, "kept", L["no kept items. Right-click an item in Bags or Bank to keep it."])
  end,
})

-- Off: new loot only flashes its row when it is in view; the list stays put.
Options.define({
  key = "followLoot", category = "display", type = "checkbox", label = L["Scroll to new loot"],
  tooltip = L["New loot scrolls the Session list to its row. Off keeps the list where it is; a row in view still flashes."],
})

-- Typeface of all addon text; changes live. "WoW default" keeps the game's own font.
Options.define({
  key = "fontFace", category = "look",
  type = "dropdown",
  label = L["Font"],
  tooltip = L["Typeface of all LootLedger text. WoW default uses the game font of your client's language. Other addons are not affected."],
  choices = function()
    if ns.UI and ns.UI.Fonts then return ns.UI.Fonts.choices() end
    return { { value = "default", label = L["WoW default"] } }
  end,
  apply = function(v)
    if ns.UI and ns.UI.Fonts then ns.UI.Fonts.applyFace(v) end
  end,
})

-- Outline and shadow of all addon text (UI/Fonts.lua); applied live. An
-- outline makes the text wider: the glyph estimates and the clock grow
-- (Fonts.applySizes) and the window re-lays itself out, now and once more on
-- the next frame, when the client has drawn the text in the new font.
local function applyFontStyle()
  local UI, db = ns.UI, ns.db
  if not (UI and UI.Fonts and UI.Fonts.applyStyle and db) then return end
  if not UI.Fonts.applyStyle(Options.get(db, "fontOutline"), Options.get(db, "fontShadow")) then return end
  if UI.Fonts.applySizes then UI.Fonts.applySizes(db) end
  local Ledger = UI.Ledger
  if not (Ledger and Ledger.relayout) then return end
  Ledger.relayout()
  local timer = _G.C_Timer
  if type(timer) == "table" and type(timer.After) == "function" then timer.After(0, Ledger.relayout) end
end
Options.define({
  key = "fontOutline", category = "look", type = "dropdown", label = L["Font outline"],
  tooltip = L["A dark outline around all LootLedger text, easier to read over a bright background. Thick is bolder."],
  choices = {
    { value = "none", label = L["None"] },
    { value = "OUTLINE", label = L["Thin"] },
    { value = "THICKOUTLINE", label = L["Thick"] },
  },
  apply = applyFontStyle,
})
Options.define({
  key = "fontShadow", category = "look", type = "checkbox", label = L["Font shadow"],
  tooltip = L["A soft dark shadow under all LootLedger text, as the game draws it. Off gives flat text; with an outline it often looks cleaner."],
  apply = applyFontStyle,
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
Options.define({ key = "fontSizeRows", category = "look", type = "dropdown", label = L["List text"],
  tooltip = L["Size of the list text. The rows grow and shrink with it."],
  choices = sizeChoices(8, 18), apply = applySizes })
Options.define({ key = "fontSizeTotals", category = "look", type = "dropdown", label = L["Totals text"],
  tooltip = L["Size of the footer table and Top finds."],
  choices = sizeChoices(8, 18), apply = applySizes })
Options.define({ key = "fontSizeTitles", category = "look", type = "dropdown", label = L["Section titles"],
  tooltip = L["Size of section titles such as Top finds."],
  choices = sizeChoices(10, 24), apply = applySizes })

-- Round button on the minimap (UI/Minimap.lua).
Options.define({
  key = "minimapButton", account = true, category = "window",
  type = "checkbox",
  label = L["Minimap button"],
  tooltip = L["Shows the LootLedger button on the minimap. Left-click shows or hides the window, right-click opens these options."],
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
  key = "exportHistory", category = "history", type = "button", label = L["Export History"],
  tooltip = L["Opens a copy box with your History as CSV, for a spreadsheet. Same as /ll export."],
  action = function()
    if ns.UI and ns.UI.Export then ns.UI.Export.history() end
  end,
})

Options.define({
  key = "clearHistory", category = "history", type = "button", label = L["Clear History"],
  tooltip = L["Deletes every session of this character's History, after asking. /ll undo brings them back until you log out or reload."],
  action = function()
    local history = ns.chardb and ns.chardb.history
    if type(history) ~= "table" or #history == 0 or not (ns.UI and ns.UI.Widgets) then return end
    ns.UI.Widgets.confirm(string.format(L["Delete all %d sessions of your History? /ll undo brings them back until you log out."], #history),
      L["Delete"], function() ns.Core.clearHistory() end)
  end,
})

-- Every History list the limit applies to: each character's in
-- LootLedgerDB.histories plus this character's own (the same table once
-- Core.linkHistory ran), each once.
local function historyLists()
  local lists, seen = {}, {}
  local function add(list)
    if type(list) == "table" and not seen[list] then
      seen[list] = true
      lists[#lists + 1] = list
    end
  end
  if ns.db and type(ns.db.histories) == "table" then
    for _, list in pairs(ns.db.histories) do add(list) end
  end
  add(ns.chardb and ns.chardb.history)
  return lists
end
Options.historyLists = historyLists

-- How many finished sessions History keeps per character (an account-wide
-- option: every character's list). Lowering it asks first (in the panel),
-- then prunes at once.
Options.define({
  key = "historyLimit", account = true, category = "history",
  type = "number",
  label = L["History kept"],
  tooltip = L["How many sessions each character's History keeps. 0 keeps none, empty keeps all. Lowering it asks first, then deletes the oldest."],
  -- The panel asks before a lower limit deletes saved sessions.
  confirm = function(v)
    if not num(v) or v < 0 then return nil end
    local extra = 0
    for _, list in ipairs(historyLists()) do extra = extra + math.max(0, #list - v) end
    if extra == 0 then return nil end
    return string.format(L["Delete the %d oldest sessions of your History? This can't be undone."], extra)
  end,
  apply = function(v)
    if ns.History then
      for _, list in ipairs(historyLists()) do ns.History.prune(list, v) end
    end
    refreshUI()
  end,
})

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
  { "colorTipLabels", L["Tooltip labels"], L["Color of the labels on the left of LootLedger tooltips."], { "tipLabel" } },
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

local function refreshPanel()
  local panel = ns.UI and ns.UI.OptionsPanel
  if panel and panel.refreshAll then panel.refreshAll() end
end

-- Preset names shown in the panel (Theme.presets keep the English ones).
local PRESET_LABELS = { midnight = L["Midnight"], tsm = L["TSM-style"], parchment = L["Parchment"] }

-- Color preset: first in Colors so Options.applyAll sets the whole palette
-- before the single colors are applied on top of it.
Options.define({
  key = "colorPreset", category = "look", type = "dropdown", label = L["Color preset"],
  tooltip = L["Sets the whole look of the window, the buttons and the tooltips at once. You can change single colors afterwards."],
  choices = function()
    local out = {}
    for _, p in ipairs(ns.Theme.presets) do out[#out + 1] = { value = p.id, label = PRESET_LABELS[p.id] or p.label } end
    return out
  end,
  format = function(v)
    local p = ns.Theme.preset(v)
    local text = p and (PRESET_LABELS[p.id] or p.label) or tostring(v)
    if ns.db and Options.presetEdited(ns.db.settings) then text = text .. L[" (edited)"] end
    return text
  end,
  apply = function(v)
    local changed = ns.Theme.applyPreset(v)
    local UI = ns.UI
    if UI and UI.Widgets and UI.Widgets.recolor then UI.Widgets.recolor(changed) end
    applyWindowLook()
    refreshUI()
  end,
  picked = function(db, v)
    local p = ns.Theme.preset(v)
    if not p then return end
    for _, o in ipairs(COLOR_OPTIONS) do Options.set(db, o[1], p.colors[o[4][1]]) end
    if p.outline then Options.set(db, "fontOutline", p.outline) end
    refreshPanel()
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

ns.Options = Options
