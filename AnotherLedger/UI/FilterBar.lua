local ADDON, ns = ...

local L = ns.L

ns.UI = ns.UI or {}

-- Header row 2: quality menu, minimum value (gold), search and sort. Edits
-- db.filter in place, the sort through FilterBar.getSort / setSort (the shown
-- view's sort, see Ledger.currentSort), and calls onChange() after every edit. Client-only
-- widgets; every WoW global is touched inside functions only. The helpers up
-- to "Menus" are pure.
local FilterBar = {}
ns.UI.FilterBar = FilterBar

local L_QUALITY = L["Quality"]
local L_MIN_HINT = L["Min g"]
local L_SEARCH_HINT = L["Search"]
local L_SORT_PREFIX = L["Sort: "]
local L_CLEAR = L["Clear the filters"]
local QUALITY_NAMES = {
  [0] = L["Poor"], L["Common"], L["Uncommon"], L["Rare"], L["Epic"], L["Legendary"],
  L["Artifact"], L["Heirloom"],
}
-- "ah" is the saved key of the best-value sort (best of vendor, AH, DE).
local SORT_LABELS = { ah = L["Value"], vendor = L["Vendor"], name = L["Name"], recent = L["Recent"],
  perHour = L["Gold/h"], perLoot = L["Per loot"],
  gold = L["Gold earned"], sold = L["Sold"], rate = L["Sell rate"], vsMarket = L["vs market"] }

FilterBar.SORTS = { "ah", "vendor", "name", "recent" }
-- Every sort a view may offer (a tab or sub-tab lists its own, see
-- Tabs.sorts); "perHour" only in History (Sessions and Zones). A saved sort the shown view
-- does not offer works (and is labeled) as "ah".
FilterBar.ALL_SORTS = { "ah", "vendor", "name", "recent", "perHour", "perLoot", "gold", "sold", "rate", "vsMarket" }

local MIN_QUALITY, MAX_QUALITY = 0, 7
local COPPER_PER_GOLD = 10000
local MAX_GOLD = 10000000

-- Widths live in Theme.widths.filter (width budget there).
local function widths() return ns.Theme.widths.filter end

-- ---------------------------------------------------------------------------
-- Pure helpers

function FilterBar.parseMinGold(text)
  if type(text) ~= "string" then return 0 end
  local trimmed = text:gsub("^%s+", ""):gsub("%s+$", "")
  -- Lua 5.1 reads "inf" / "nan" as numbers: only a finite one counts.
  local n = tonumber(trimmed)
  if not ns.Util.isNumber(n) or n <= 0 then return 0 end
  if n > MAX_GOLD then n = MAX_GOLD end
  return math.floor(n * COPPER_PER_GOLD + 0.5)
end

function FilterBar.formatMinGold(copper)
  if type(copper) ~= "number" or copper ~= copper or copper <= 0 then return "" end
  local s = string.format("%.4f", copper / COPPER_PER_GOLD)
  s = s:gsub("0+$", ""):gsub("%.$", "")
  return s
end

local function fullSet()
  local t = {}
  for q = MIN_QUALITY, MAX_QUALITY do t[q] = true end
  return t
end

function FilterBar.toggleQuality(filter, q)
  if type(filter) ~= "table" then return end
  if type(q) ~= "number" or q < MIN_QUALITY or q > MAX_QUALITY or q ~= math.floor(q) then return end
  if type(filter.qualities) ~= "table" then filter.qualities = fullSet() end
  filter.qualities[q] = not filter.qualities[q]
end

-- Quality button text: "Quality", or "Quality 5/8" while some are hidden.
function FilterBar.qualityLabel(filter)
  local set = type(filter) == "table" and filter.qualities
  if type(set) ~= "table" then return L_QUALITY end
  local on, all = 0, MAX_QUALITY - MIN_QUALITY + 1
  for q = MIN_QUALITY, MAX_QUALITY do
    if set[q] then on = on + 1 end
  end
  if on == all then return L_QUALITY end
  return L_QUALITY .. " " .. on .. "/" .. all
end

-- Quality preset: shows `min` and every better quality, hides the rest.
function FilterBar.setMinQuality(filter, min)
  if type(filter) ~= "table" or type(min) ~= "number" then return end
  local set = {}
  for q = MIN_QUALITY, MAX_QUALITY do set[q] = q >= min end
  filter.qualities = set
end

-- The presets at the top of the quality menu: { label, lowest quality shown }.
FilterBar.PRESETS = {
  { L["All qualities"], 0 },
  { L["Common and better"], 1 },
  { L["Uncommon and better"], 2 },
  { L["Rare and better"], 3 },
  { L["Epic and better"], 4 },
}

-- Clears every filter: all qualities, no minimum, no search.
function FilterBar.clear(filter)
  if type(filter) ~= "table" then return end
  filter.qualities = fullSet()
  filter.minValue = 0
  filter.search = ""
end

local function offers(sorts, key)
  for _, k in ipairs(sorts) do
    if k == key then return true end
  end
  return false
end

-- The sort after `current` within `sorts` (default FilterBar.SORTS).
function FilterBar.nextSort(current, sorts)
  sorts = sorts or FilterBar.SORTS
  -- A known sort this view does not offer shows as "ah": the next one follows "ah".
  if offers(FilterBar.ALL_SORTS, current) and not offers(sorts, current) then current = "ah" end
  for i, key in ipairs(sorts) do
    if key == current then return sorts[i % #sorts + 1] end
  end
  return sorts[1]
end

function FilterBar.sortLabel(key, sorts)
  if not offers(sorts or FilterBar.SORTS, key) then key = "ah" end
  return SORT_LABELS[key] or SORT_LABELS.ah
end

-- The sort of the shown view: the accessor given to attach, else db.sort.
function FilterBar.getSort()
  local access = FilterBar.sortAccess
  if access then return access.get() end
  return FilterBar.sortDb and FilterBar.sortDb.sort
end

function FilterBar.setSort(key)
  local access = FilterBar.sortAccess
  if access then
    access.set(key)
  elseif FilterBar.sortDb then
    FilterBar.sortDb.sort = key
  end
end

local function sortText()
  return L_SORT_PREFIX .. FilterBar.sortLabel(FilterBar.getSort(), FilterBar.activeSorts)
end

-- The sorts the shown view offers (nil = FilterBar.SORTS); relabels the button.
function FilterBar.setSorts(sorts)
  FilterBar.activeSorts = sorts
  local button = FilterBar.sortButton
  if button and FilterBar.sortDb then button:SetText(sortText()) end
end

function FilterBar.isActive(db)
  return ns.View.isFiltered(type(db) == "table" and db.filter or nil)
end

-- Repairs nil / wrong-typed saved state in place; returns db.
function FilterBar.repair(db)
  if type(db) ~= "table" then return db end
  if type(db.filter) ~= "table" then db.filter = {} end
  local f = db.filter
  if type(f.qualities) ~= "table" then f.qualities = fullSet() end
  if type(f.minValue) ~= "number" or f.minValue ~= f.minValue or f.minValue < 0 then f.minValue = 0 end
  if type(f.search) ~= "string" then f.search = "" end
  local okSort = false
  for _, key in ipairs(FilterBar.ALL_SORTS) do
    if key == db.sort then okSort = true end
  end
  if not okSort then db.sort = FilterBar.SORTS[1] end
  return db
end

-- ---------------------------------------------------------------------------
-- Menus (feature-detected at call time)

local function qualityLabel(q)
  local r, g, b = ns.Theme.qualityColor(q)
  return string.format("|cff%02x%02x%02x%s|r",
    math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5),
    QUALITY_NAMES[q])
end

local function isQualityOn(filter, q)
  return type(filter.qualities) ~= "table" or filter.qualities[q] == true
end

-- The presets (one click, the menu closes), then one checkbox per quality;
-- the menu stays open while qualities are toggled.
local function openQualityMenu(anchor, getFilter, changed)
  local entries = {}
  for _, p in ipairs(FilterBar.PRESETS) do
    entries[#entries + 1] = {
      text = p[1], kind = "button",
      onClick = function()
        FilterBar.setMinQuality(getFilter(), p[2])
        changed()
      end,
    }
  end
  for q = MIN_QUALITY, MAX_QUALITY do
    entries[#entries + 1] = {
      text = qualityLabel(q),
      isChecked = function() return isQualityOn(getFilter(), q) end,
      onClick = function()
        FilterBar.toggleQuality(getFilter(), q)
        changed()
      end,
    }
  end
  ns.UI.Widgets.openMenu(anchor, entries, "checkbox")
end

-- ---------------------------------------------------------------------------
-- Widgets

-- Edit box with a gray hint shown while empty and unfocused.
local function makeEdit(parent, hint, width)
  local T = ns.Theme
  local e = ns.UI.Widgets.input(parent, width)
  e:SetAutoFocus(false)
  e:SetFontObject(T.fonts.small)
  e:SetTextInsets(4, 4, 0, 0)
  e:SetMaxLetters(40)
  local label = ns.UI.Widgets.text(e, T.fonts.small, T.colors.hint)
  label:SetPoint("LEFT", e, "LEFT", 4, 0)
  label:SetText(hint)
  e.hint = label
  function e:RefreshHint()
    self.hint:SetShown(self:GetText() == "" and not self:HasFocus())
  end
  e:HookScript("OnEditFocusGained", e.RefreshHint)
  e:HookScript("OnEditFocusLost", e.RefreshHint)
  e:HookScript("OnTextChanged", e.RefreshHint)
  return e
end

-- Called by Ledger.init with (header.row2, ns.db, Ledger.refresh, sortAccess);
-- `sortAccess` = { get, set } of the shown view's sort (optional: db.sort).
function FilterBar.attach(row, db, onChange, sortAccess)
  if FilterBar.instance then return FilterBar.instance end
  FilterBar.sortDb, FilterBar.sortAccess = db, sortAccess
  local T = ns.Theme
  local makeButton = ns.UI.Widgets.button
  FilterBar.repair(db)
  local gap = T.sizes.buttonGap
  local bar = { row = row }

  local function changed()
    if onChange then onChange() end
  end
  -- Re-fetched each time so a replaced db.filter table is never stale.
  local function getFilter()
    FilterBar.repair(db)
    return db.filter
  end

  -- Gold underline while any filter is active.
  local underline = ns.UI.Widgets.line(row, T.colors.goldLine, "ARTWORK", 1)
  underline:SetHeight(2)
  underline:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  underline:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  underline:Hide()

  local quality = makeButton(row, L_QUALITY, widths().quality)
  quality:SetPoint("LEFT", row, "LEFT", 0, 0)
  quality:SetScript("OnClick", function(self)
    openQualityMenu(self, getFilter, changed)
  end)

  local minBox = makeEdit(row, L_MIN_HINT, widths().min)
  minBox:SetPoint("LEFT", quality, "RIGHT", gap + 4, 0)

  local sort = makeButton(row, sortText(), widths().sort)
  sort:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  sort:SetScript("OnClick", function()
    FilterBar.setSort(FilterBar.nextSort(FilterBar.getSort(), FilterBar.activeSorts))
    sort:SetText(sortText())
    changed()
  end)
  FilterBar.sortButton = sort

  -- Clear button left of the sort, only while a filter is active; the search
  -- box stretches up to it (or to the sort while it is hidden).
  local search = makeEdit(row, L_SEARCH_HINT, 100)
  local clear = ns.UI.Widgets.iconButton(row, "close", widths().clear, function()
    FilterBar.clear(getFilter())
    search:SetText("")
    minBox:SetText("")
    changed()
  end)
  clear:SetPoint("RIGHT", sort, "LEFT", -gap, 0)
  clear.onEnter = function(self) ns.UI.Widgets.showTextTooltip(self, L_CLEAR, "ANCHOR_BOTTOMRIGHT") end
  clear.onLeave = ns.UI.Widgets.hideTooltip
  clear:Hide()
  local searchTo
  local function placeSearch(active)
    local to = active and clear or sort
    if to == searchTo then return end
    searchTo = to
    search:ClearAllPoints()
    search:SetPoint("LEFT", minBox, "RIGHT", gap + 2, 0)
    search:SetPoint("RIGHT", to, "LEFT", -gap - 2, 0)
  end
  placeSearch(false)

  -- Minimum value: applied on Enter / focus lost (Enter clears focus).
  minBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  minBox:SetScript("OnEscapePressed", function(self)
    self:SetText(FilterBar.formatMinGold(getFilter().minValue)) -- discard the edit
    self:ClearFocus()
  end)
  minBox:SetScript("OnEditFocusLost", function(self)
    local f = getFilter()
    local copper = FilterBar.parseMinGold(self:GetText())
    local was = f.minValue
    f.minValue = copper
    self:SetText(FilterBar.formatMinGold(copper)) -- normalize what the user typed
    self:RefreshHint() -- SetScript replaced the hint hook above
    if copper ~= was then changed() end
  end)

  -- Search: applied as the user types; SetText from Update has userInput=false.
  search:SetScript("OnTextChanged", function(self, userInput)
    self:RefreshHint() -- SetScript replaced the hint hook above
    if not userInput then return end
    getFilter().search = self:GetText()
    changed()
  end)
  search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  bar.quality, bar.minBox, bar.search, bar.sort, bar.underline = quality, minBox, search, sort, underline
  bar.clear = clear

  -- Ledger part: re-sync the widgets from db (never calls onChange).
  local part = {}
  function part:Update()
    local f = getFilter()
    if not minBox:HasFocus() then
      local text = FilterBar.formatMinGold(f.minValue)
      if minBox:GetText() ~= text then minBox:SetText(text) end
    end
    if not search:HasFocus() and search:GetText() ~= f.search then
      search:SetText(f.search)
    end
    minBox:RefreshHint()
    search:RefreshHint()
    sort:SetText(sortText())
    local active = FilterBar.isActive(db)
    underline:SetShown(active)
    clear:SetShown(active)
    placeSearch(active)
    quality:SetText(FilterBar.qualityLabel(f))
  end
  if ns.UI.Ledger then ns.UI.Ledger.register(part) end

  FilterBar.instance = bar
  return bar
end
