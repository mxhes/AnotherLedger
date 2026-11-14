local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Header row 2: quality menu, minimum value (gold), search and sort. Edits
-- db.filter / db.sort in place and calls onChange() after every edit. Client-only
-- widgets; every WoW global is touched inside functions only. The helpers up
-- to "Menus" are pure.
local FilterBar = {}
ns.UI.FilterBar = FilterBar

local L_QUALITY = "Quality"
local L_MIN_HINT = "Min g"
local L_SEARCH_HINT = "Search"
local L_SORT_PREFIX = "Sort: "
local QUALITY_NAMES = {
  [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact", "Heirloom",
}
local SORT_LABELS = { ah = "AH", vendor = "Vendor", name = "Name", recent = "Recent" }

FilterBar.SORTS = { "ah", "vendor", "name", "recent" }

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
  local n = tonumber(trimmed)
  if type(n) ~= "number" or n ~= n or n <= 0 then return 0 end
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

function FilterBar.nextSort(current)
  for i, key in ipairs(FilterBar.SORTS) do
    if key == current then return FilterBar.SORTS[i % #FilterBar.SORTS + 1] end
  end
  return FilterBar.SORTS[1]
end

function FilterBar.sortLabel(key)
  return SORT_LABELS[key] or SORT_LABELS.ah
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
  for _, key in ipairs(FilterBar.SORTS) do
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

-- One checkbox per quality; the menu stays open while qualities are toggled.
local function openQualityMenu(anchor, getFilter, changed)
  local entries = {}
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
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width, T.sizes.buttonHeight)
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

-- Called by Ledger.init with (header.row2, ns.db, Ledger.refresh).
function FilterBar.attach(row, db, onChange)
  if FilterBar.instance then return FilterBar.instance end
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

  local sort = makeButton(row, L_SORT_PREFIX .. FilterBar.sortLabel(db.sort), widths().sort)
  sort:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  sort:SetScript("OnClick", function()
    db.sort = FilterBar.nextSort(db.sort)
    sort:SetText(L_SORT_PREFIX .. FilterBar.sortLabel(db.sort))
    changed()
  end)

  local search = makeEdit(row, L_SEARCH_HINT, 100)
  search:SetPoint("LEFT", minBox, "RIGHT", gap + 2, 0)
  search:SetPoint("RIGHT", sort, "LEFT", -gap - 2, 0)

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
    sort:SetText(L_SORT_PREFIX .. FilterBar.sortLabel(db.sort))
    underline:SetShown(FilterBar.isActive(db))
  end
  if ns.UI.Ledger then ns.UI.Ledger.register(part) end

  FilterBar.instance = bar
  return bar
end
