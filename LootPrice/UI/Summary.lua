local ADDON, ns = ...

local L = ns.L

ns.UI = ns.UI or {}

-- The footer value table (rows Items / Raw gold / Total, columns Value and per hour,
-- a notes line and a vendor / AH tooltip) and the Top finds block (topBox, at
-- the bottom of the window under the footer). Client-only widgets; every WoW
-- global is touched inside functions only. The helpers up to "Widgets" are pure.
local Summary = {}
ns.UI.Summary = Summary

local L_TOP = L["Top finds"]
local L_VENDOR = L["Vendor: "]
local L_AH = L["AH: "]
local L_PER_HOUR = L["/h"]
local L_PER_HOUR_TITLE = L["per hour"]
local L_UNPRICED = L[" unpriced"]
local L_MARKED = L[" (marked ?)"]
local L_FILTERED = L["filtered"]
local L_LABEL_ITEMS = L["Items"]
local L_LABEL_GOLD = L["Raw gold"]
local L_TOTAL = L["Total"]
local L_VALUE = L["Value"]
local L_BEST = L["Best: "]
local DASH = "\226\128\148" -- em dash (UTF-8)
local MAX_TOP = 3

-- ---------------------------------------------------------------------------
-- Pure helpers

-- Every text helper takes an optional `formatMoney`; it defaults to the colored
-- coin format (Money.formatColored), the tests pass Money.format for plain text.
local NONE = {}

local function amountText(v, formatMoney)
  return (formatMoney or ns.Money.formatColored)(tonumber(v) or 0)
end

-- "12g 5s" (the column title says per hour), or an em dash while there is no
-- rate yet.
function Summary.rateText(perHour, formatMoney)
  if perHour == nil then return DASH end
  return (formatMoney or ns.Money.formatColored)(perHour)
end

-- ---------------------------------------------------------------------------
-- Value table (rows Items / Raw gold / Total, columns Value and per hour)

Summary.ROWS = { "items", "gold", "total" }
local ROW_LABELS = { items = L_LABEL_ITEMS, gold = L_LABEL_GOLD, total = L_TOTAL }
local SEP = " \194\183 " -- middle dot

-- One line of notes under the table: the filtered / unpriced markers and the
-- view's note (bank scan age). Returns text, orange; nil without any part.
function Summary.notesText(view)
  view = view or NONE
  local totals = view.totals or NONE
  local parts, orange = {}, false
  if totals.filtered then
    parts[#parts + 1] = L_FILTERED
    orange = true
  end
  local unpriced = tonumber(totals.unpriced) or 0
  if unpriced > 0 then
    -- Item rows mark unpriced items "?"; History session lists have no marks.
    parts[#parts + 1] = unpriced .. L_UNPRICED .. (view.history and "" or L_MARKED)
    orange = true
  end
  if view.note then
    parts[#parts + 1] = view.note
    if view.noteStale then orange = true end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, SEP), orange
end

-- Which rows, columns and lines the table shows for `view`, and its height.
function Summary.tableLayout(view)
  view = view or NONE
  local s = ns.Theme.sizes
  local inventory = view.kind == "inventory"
  local layout = { rates = not inventory, titles = not inventory }
  -- Option "showFooterGold" off: no Raw gold row (Total still includes it).
  local O, db = ns.Options, ns.db
  local goldRow = not (O and db) or O.get(db, "showFooterGold") ~= false
  if inventory then
    layout.rows = { "items" }
  elseif view.noCombined then
    layout.rows = goldRow and { "items", "gold" } or { "items" }
  else
    layout.rows = goldRow and { "items", "gold", "total" } or { "items", "total" }
  end
  layout.notes = Summary.notesText(view) ~= nil
  layout.height = ((layout.titles and 1 or 0) + #layout.rows) * s.footerRowHeight
    + (layout.notes and s.footerNoteHeight or 0)
  return layout
end

-- Value (best) and rate text of every row.
function Summary.rowTexts(view, formatMoney)
  view = view or NONE
  local totals, gold, combined = view.totals or NONE, view.gold or NONE, view.combined or NONE
  local function row(amount, perHour)
    return { value = amountText(amount, formatMoney), rate = Summary.rateText(perHour, formatMoney) }
  end
  return {
    items = row(totals.best, totals.bestPerHour),
    gold = row(gold.total, gold.perHour),
    total = row(combined.best, combined.bestPerHour),
  }
end

-- Hover tooltip: vendor / AH / best of the items and of items + gold, each
-- followed by its rate where the view has rates. Returns { {left, right}, ... }.
function Summary.tooltipLines(view, formatMoney)
  view = view or NONE
  local layout = Summary.tableLayout(view)
  local lines = {}
  local function section(title, t)
    t = t or NONE
    lines[#lines + 1] = { title, "" }
    local function line(label, amount, perHour)
      local right = amountText(amount, formatMoney)
      if layout.rates then
        right = right .. "  " .. Summary.rateText(perHour, formatMoney) .. (perHour ~= nil and L_PER_HOUR or "")
      end
      lines[#lines + 1] = { label, right }
    end
    line(L_VENDOR, t.vendor, t.vendorPerHour)
    line(L_AH, t.ah, t.ahPerHour)
    line(L_BEST, t.best, t.bestPerHour)
  end
  section(L_LABEL_ITEMS, view.totals)
  if layout.rates and not view.noCombined then section(L_TOTAL, view.combined) end
  return lines
end

-- Estimated width of the widest table line: an 11-character label
-- ("Gegenstände"), a 15-character value ("123456g 78s 90c") and a 14-character
-- rate ("999g 59s 59c/h") in the summary font, with 6 and 8 px gaps.
-- With coin icons each of the three units is about two glyphs wide instead of
-- one letter: one more glyph per unit in the value and in the rate.
local function iconExtra()
  return (ns.Money.iconsOn and ns.Money.iconsOn()) and 3 or 0
end

function Summary.tableWorstWidth()
  return (11 + 15 + 14 + 2 * iconExtra()) * ns.Theme.sizes.summaryCharPx + 6 + 8
end

-- Width of the /h column: the 14-character worst-case rate.
local function rateColumnWidth()
  return (14 + iconExtra()) * ns.Theme.sizes.summaryCharPx
end

-- ---------------------------------------------------------------------------
-- Top finds

-- Window height the list needs: chrome around the content, header, a full Top
-- finds block, `minListRows` rows and the full session footer table.
function Summary.requiredWindowHeight()
  local s = ns.Theme.sizes
  return 2 * (s.padding + 4) + s.headerHeight + Summary.topBoxHeight(MAX_TOP)
    + s.minListRows * s.rowHeight + Summary.tableLayout(NONE).height
end

function Summary.topLines(top, formatMoney)
  local out = {}
  if type(top) ~= "table" then return out end
  formatMoney = formatMoney or ns.Money.formatColored
  for i = 1, math.min(#top, MAX_TOP) do
    local r = top[i]
    out[i] = {
      name = r.name or "?",
      qty = "x" .. (tonumber(r.quantity) or 0),
      value = formatMoney(r.value),
      quality = r.quality,
      link = r.link,
      tooltipLink = ns.UI.Rows and ns.UI.Rows.tooltipLink(r) or nil,
    }
  end
  return out
end

function Summary.topBoxHeight(count)
  count = math.min(tonumber(count) or 0, MAX_TOP)
  if count <= 0 then return 0 end
  local s = ns.Theme.sizes
  return s.topHeaderHeight + count * s.topRowHeight + s.padding / 2 + s.dividerHeight
end

-- ---------------------------------------------------------------------------
-- Widgets

function Summary.attach(topBox, footer)
  if Summary.instance then return Summary.instance end
  local T = ns.Theme
  local W = ns.UI.Widgets
  local makeText = W.text
  local S = T.sizes
  local ink, stale, gold = T.colors.ink, T.colors.stale, T.colors.gold
  local titleColor = T.colors.sectionTitle
  local line = T.colors.goldLine

  local summary = { topBox = topBox, footer = footer, rows = {}, height = nil }

  -- Top finds (bottom of the window, under the footer). The divider is the
  -- top edge of the topBox; the content starts below it.
  local off = S.dividerHeight + S.padding / 2
  -- Section title in the header font: below the window title, not above it.
  local header = makeText(topBox, T.fonts.title, titleColor)
  header:SetPoint("TOPLEFT", topBox, "TOPLEFT", 0, -off)
  header:SetText(L_TOP)
  summary.header = header

  -- Height and place of Top finds row `i` (again after a size change).
  local function placeTopRow(row, i)
    local y = -(off + S.topHeaderHeight + (i - 1) * S.topRowHeight)
    row:SetHeight(S.topRowHeight)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", topBox, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", topBox, "TOPRIGHT", 0, y)
  end

  for i = 1, MAX_TOP do
    local row = CreateFrame("Frame", nil, topBox)
    placeTopRow(row, i)
    local edge = W.line(row, line, "ARTWORK", 0.9)
    edge:SetWidth(2)
    edge:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)
    local value = makeText(row, T.fonts.topRow, ink, "RIGHT")
    -- Keep clear of the resize grip in the window's bottom-right corner.
    value:SetPoint("RIGHT", row, "RIGHT", -(2 + S.gripSize), 0)
    local qty = makeText(row, T.fonts.topRow, ink, "RIGHT")
    qty:SetPoint("RIGHT", value, "LEFT", -6, 0)
    local name = makeText(row, T.fonts.topRow, ink, "LEFT")
    name:SetPoint("LEFT", row, "LEFT", 6, 0)
    name:SetPoint("RIGHT", qty, "LEFT", -6, 0)
    row:Hide()
    local entry = { frame = row, name = name, qty = qty, value = value }
    -- Item tooltip while the mouse is over the find.
    row:EnableMouse(true)
    row:SetScript("OnEnter", function() W.showItemTooltip(row, entry.tooltipLink) end)
    row:SetScript("OnLeave", W.hideTooltip)
    -- Shift / Ctrl-click: link in chat / try on, like a list row.
    row:SetScript("OnMouseUp", function() ns.UI.Rows.modifiedClick(entry.link) end)
    summary.rows[i] = entry
  end

  -- Divider between the footer and the Top finds block: the top edge of the
  -- topBox, so it disappears together with a collapsed topBox.
  local divider = W.line(topBox, T.colors.divider)
  divider:SetHeight(S.dividerHeight)
  divider:SetPoint("TOPLEFT", topBox, "TOPLEFT", 0, 0)
  divider:SetPoint("TOPRIGHT", topBox, "TOPRIGHT", 0, 0)
  summary.divider = divider

  -- Footer: the value table. Every line is a frame of footerRowHeight stacked
  -- from the footer top in the order of Summary.tableLayout (re-anchored when
  -- the layout changes). The table frame covers the footer and owns the tooltip.
  local tbl = CreateFrame("Frame", nil, footer)
  tbl:SetAllPoints(footer)
  tbl:EnableMouse(true)
  summary.table = tbl

  local rateW = rateColumnWidth() -- recomputed by ApplySizes
  local function makeLine()
    local f = CreateFrame("Frame", nil, tbl)
    f:SetHeight(S.footerRowHeight)
    return f
  end
  -- Value right edge: left of the /h column, or flush right without rates.
  local function placeValue(fs, f, rates)
    fs:ClearAllPoints()
    fs:SetPoint("RIGHT", f, "RIGHT", rates and -(rateW + 8) or 0, 0)
  end

  local titles = { frame = makeLine() }
  titles.value = makeText(titles.frame, T.fonts.summaryMarker, T.colors.columnTitle, "RIGHT")
  titles.value:SetText(L_VALUE)
  placeValue(titles.value, titles.frame, true)
  titles.rate = makeText(titles.frame, T.fonts.summaryMarker, T.colors.columnTitle, "RIGHT")
  titles.rate:SetPoint("RIGHT", titles.frame, "RIGHT", 0, 0)
  titles.rate:SetText(L_PER_HOUR_TITLE)
  summary.titles = titles

  local cells = {}
  for _, key in ipairs(Summary.ROWS) do
    local color = key == "total" and gold or ink
    local f = makeLine()
    local c = { frame = f }
    c.label = makeText(f, T.fonts.summary, color, "LEFT")
    c.label:SetPoint("LEFT", f, "LEFT", 0, 0)
    c.label:SetText(ROW_LABELS[key])
    c.value = makeText(f, T.fonts.summary, color, "RIGHT")
    placeValue(c.value, f, true)
    c.rate = makeText(f, T.fonts.summary, color, "RIGHT")
    c.rate:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    cells[key] = c
  end
  summary.cells = cells

  local notesFrame = makeLine()
  notesFrame:SetHeight(S.footerNoteHeight)
  local notes = makeText(notesFrame, T.fonts.summaryMarker, ink, "LEFT")
  notes:SetPoint("LEFT", notesFrame, "LEFT", 0, 0)
  notes:SetPoint("RIGHT", notesFrame, "RIGHT", 0, 0)
  summary.notes, summary.notesFrame = notes, notesFrame

  -- Hover: vendor / AH / best of the last view.
  tbl:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    for _, l in ipairs(Summary.tooltipLines(summary.view)) do
      GameTooltip:AddDoubleLine(l[1], l[2], 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:Show()
  end)
  tbl:SetScript("OnLeave", W.hideTooltip)

  -- Shows the lines of `layout` stacked from the top and hides the rest.
  local function setShown(c, shown, rates)
    c.frame:SetShown(shown)
    c.label:SetShown(shown)
    c.value:SetShown(shown)
    c.rate:SetShown(shown and rates)
  end
  function summary:SetLayout(layout)
    local stack, y = {}, 0
    titles.frame:SetShown(layout.titles)
    titles.value:SetShown(layout.titles)
    titles.rate:SetShown(layout.titles)
    if layout.titles then stack[#stack + 1] = titles.frame end
    local shown = {}
    for _, key in ipairs(layout.rows) do
      shown[key] = true
      stack[#stack + 1] = cells[key].frame
    end
    for _, key in ipairs(Summary.ROWS) do
      local c = cells[key]
      setShown(c, shown[key] == true, layout.rates)
      placeValue(c.value, c.frame, layout.rates)
    end
    notesFrame:SetShown(layout.notes)
    notes:SetShown(layout.notes)
    if layout.notes then stack[#stack + 1] = notesFrame end
    for _, f in ipairs(stack) do
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, -y)
      f:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, -y)
      y = y + f:GetHeight()
    end
    if layout.height ~= self.footerHeight then
      self.footerHeight = layout.height
      if ns.UI.Window and ns.UI.Window.setFooterHeight then
        ns.UI.Window.setFooterHeight(layout.height)
      end
    end
  end

  -- Theme.sizes changed (font size options): new line heights, Top finds
  -- places and /h column width; the next Set re-stacks the table and resizes
  -- the footer and the Top finds box.
  function summary:ApplySizes()
    rateW = rateColumnWidth()
    titles.frame:SetHeight(S.footerRowHeight)
    for _, key in ipairs(Summary.ROWS) do cells[key].frame:SetHeight(S.footerRowHeight) end
    notesFrame:SetHeight(S.footerNoteHeight)
    for i = 1, MAX_TOP do placeTopRow(self.rows[i].frame, i) end
    placeValue(titles.value, titles.frame, true)
    self.footerHeight, self.height = nil, nil
    self:Set(self.view)
  end

  function summary:SetNotes(view)
    local text, orange = Summary.notesText(view)
    if not text then return end
    W.setTextColor(notes, orange and stale or ink)
    notes:SetText(text)
  end

  -- Top finds: up to MAX_TOP lines; the box collapses without any.
  function summary:SetTop(top)
    local lines = Summary.topLines(top)
    for i = 1, MAX_TOP do
      local w, l = self.rows[i], lines[i]
      if l then
        local r, g, b = T.qualityColor(l.quality)
        w.name:SetTextColor(r, g, b, 1)
        w.name:SetText(l.name)
        w.qty:SetText(l.qty)
        w.value:SetText(l.value)
        w.tooltipLink, w.link = l.tooltipLink, l.link
        w.frame:Show()
      else
        w.frame:Hide()
      end
    end
    -- Option "showTopFinds" off: the block stays collapsed.
    local O, db = ns.Options, ns.db
    local shown = not (O and db) or O.get(db, "showTopFinds") ~= false
    local height = shown and Summary.topBoxHeight(#lines) or 0
    if height ~= self.height then
      self.height = height
      if ns.UI.Window and ns.UI.Window.setTopBoxHeight then
        ns.UI.Window.setTopBoxHeight(height)
      end
    end
  end

  -- The amounts and rates of the table (the rates are the only texts that
  -- change with the clock; a tick redraws the values too, which is cheap).
  function summary:SetValues(view)
    local texts = Summary.rowTexts(view)
    for _, key in ipairs(Summary.ROWS) do
      cells[key].value:SetText(texts[key].value)
      cells[key].rate:SetText(texts[key].rate)
    end
  end

  function summary:Set(view)
    view = view or NONE
    self.view = view
    self:SetLayout(Summary.tableLayout(view))
    self:SetNotes(view)
    self:SetTop(view.top)
    self:SetValues(view)
  end

  -- Ledger part: everything on a full refresh, only the amounts on a clock tick.
  local part = {}
  function part:Update(view) summary:Set(view) end
  function part:Relayout() summary:ApplySizes() end
  function part:Tick(view)
    summary.view = view or NONE
    summary:SetValues(summary.view)
  end
  if ns.UI.Ledger then ns.UI.Ledger.register(part) end

  Summary.instance = summary
  return summary
end
