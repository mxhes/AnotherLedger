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
local L_UNPRICED = L[" without AH price"]
local L_MARKED = L[" (marked ?)"]
local L_MARKED_FIRST = L[" (marked ?, listed first)"]
local L_CLICK_FIRST = L["Click: list the items without an AH price first."]
local L_CLICK_BACK = L["Click: back to the chosen sort."]
local L_FILTERED = L["filtered"]
local L_LABEL_ITEMS = L["Items"]
local L_LABEL_GOLD = L["Raw gold"]
local L_TOTAL = L["Total"]
local L_KEPT = L["Kept"]
local L_SELLABLE = L["Sellable"]
local L_VALUE = L["Value"]
local L_BEST = L["Best: "]
local L_GOAL = L["Goal "]
local L_GOAL_REACHED = L["Goal reached"]
local L_UNPRICED_TITLE = L["Without AH price"]
local L_WHY_NO_SOURCE = L["No TSM or Auctionator and no scan yet: open the auction house and type /al scan."]
local L_WHY_NO_PRICE = L["Your price sources have no auction price for these items (yet)."]
local L_AND_MORE = L["and %d more"]
local L_MONEY = L["Gold on hand"]
local L_WORTH = L["Net worth"]
local L_ALL_WORTH = L["All characters"]
local L_WORTH_BAGS = L["Bags: "]
local L_WORTH_BANK = L["Bank: "]
local L_WORTH_GOLD = L["Gold: "]
local L_WORTH_NO_BANK = L["not scanned"]
local L_WORTH_SAVED = L["Saved at logout and while Bags is shown; /al worth lists them."]
local L_SELL_SPLIT = L["Sell split"]
local L_DESTROY = L["Destroy: "]
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

Summary.ROWS = { "items", "gold", "total", "kept", "sellable", "money", "worth", "allWorth" }
local ROW_LABELS = { items = L_LABEL_ITEMS, gold = L_LABEL_GOLD, total = L_TOTAL, kept = L_KEPT,
  sellable = L_SELLABLE, money = L_MONEY, worth = L_WORTH, allWorth = L_ALL_WORTH }
local SEP = " \194\183 " -- middle dot

-- One line of notes under the table: the filtered / unpriced markers and the
-- view's note (bank scan age). Returns text, orange; nil without any part.
-- `unpricedFirst`: the unpriced items are listed first (Ledger.unpricedFirst).
function Summary.notesText(view, unpricedFirst)
  view = view or NONE
  local totals = view.totals or NONE
  local parts, orange = {}, false
  if totals.filtered then
    parts[#parts + 1] = L_FILTERED
    orange = true
  end
  local unpriced = tonumber(totals.unpriced) or 0
  if unpriced > 0 then
    -- Item rows mark unpriced items "?" (Zones and Mobs in their opened places
    -- and mobs). Clicking the line lists them first (Summary.attach).
    parts[#parts + 1] = unpriced .. L_UNPRICED .. (unpricedFirst and L_MARKED_FIRST or L_MARKED)
    orange = true
  end
  if view.note then
    parts[#parts + 1] = view.note
    if view.noteStale then orange = true end
  end
  -- The session goal (option "goalGold"): how far, in percent.
  if view.goal then
    local pct = ns.View.goalPercent(view.goal)
    parts[#parts + 1] = pct >= 100 and L_GOAL_REACHED or (L_GOAL .. pct .. "%")
  end
  if #parts == 0 then return nil end
  return table.concat(parts, SEP), orange
end

-- Which rows, columns and lines the table shows for `view`, and its height.
-- History and Zones show the same table as the Session tab: the listed
-- sessions (or places) added up, with rates over their recorded time.
function Summary.tableLayout(view)
  view = view or NONE
  local s = ns.Theme.sizes
  local inventory = view.kind == "inventory"
  -- Mobs has no clock to divide by: no per hour column.
  local layout = { rates = not inventory and view.kind ~= "mobs", titles = not inventory }
  -- Option "rawGold": its own Raw gold row or not (Total follows the counting).
  local _, goldRow = ns.Util.rawGold()
  if inventory then
    -- With kept items in the list: what is kept and what is left to sell.
    local totals = view.totals or NONE
    layout.rows = totals.kept and { "items", "kept", "sellable" } or { "items" }
    -- Bags: the character's gold and the net worth (bags + bank + gold), and
    -- with more than one character saved, all of theirs (Worth.lua).
    if totals.money ~= nil then
      layout.rows[#layout.rows + 1] = "money"
      layout.rows[#layout.rows + 1] = "worth"
      if totals.allWorth ~= nil then layout.rows[#layout.rows + 1] = "allWorth" end
    end
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

-- Value (best) and rate text of every row, and both as numbers for the coin
-- columns (`valueCopper`; `rateCopper` nil while there is no rate: the text
-- is then the em dash).
function Summary.rowTexts(view, formatMoney)
  view = view or NONE
  local totals, gold, combined = view.totals or NONE, view.gold or NONE, view.combined or NONE
  local function row(amount, perHour)
    return { value = amountText(amount, formatMoney), rate = Summary.rateText(perHour, formatMoney),
      valueCopper = tonumber(amount) or 0, rateCopper = perHour }
  end
  -- An unscanned bank has no total yet: a dash, not "0c".
  local items = row(totals.best, totals.bestPerHour)
  if view.unscanned then items.value = DASH end
  return {
    items = items,
    gold = row(gold.total, gold.perHour),
    total = row(combined.best, combined.bestPerHour),
    kept = row(totals.kept, nil),
    sellable = row(totals.sellable, nil),
    money = row(totals.money, nil),
    worth = row(totals.worth, nil),
    allWorth = row(totals.allWorth, nil),
  }
end

-- Hover tooltip: vendor / AH / best of the items and of items + gold, each
-- followed by its rate where the view has rates. Returns { {left, right[, source]}, ... };
-- `source` ("vendor" / "ah") colors the label (Theme.sourceColor).
function Summary.tooltipLines(view, formatMoney)
  view = view or NONE
  local layout = Summary.tableLayout(view)
  local lines = {}
  local function section(title, t)
    t = t or NONE
    lines[#lines + 1] = { title, "" }
    local function line(label, amount, perHour, source)
      local right = amountText(amount, formatMoney)
      if layout.rates then
        right = right .. "  " .. Summary.rateText(perHour, formatMoney) .. (perHour ~= nil and L_PER_HOUR or "")
      end
      lines[#lines + 1] = { label, right, source }
    end
    line(L_VENDOR, t.vendor, t.vendorPerHour, "vendor")
    line(L_AH, t.ah, t.ahPerHour, "ah")
    line(L_BEST, t.best, t.bestPerHour)
  end
  section(L_LABEL_ITEMS, view.totals)
  if layout.rates and not view.noCombined then section(L_TOTAL, view.combined) end
  -- Inventory: what the items not kept would bring, by how each is valued.
  local split = (view.totals or NONE).sellSplit
  if view.kind == "inventory" and type(split) == "table" then
    lines[#lines + 1] = { L_SELL_SPLIT, "" }
    lines[#lines + 1] = { L_VENDOR, amountText(split.vendor, formatMoney), "vendor" }
    lines[#lines + 1] = { L_AH, amountText(split.ah, formatMoney), "ah" }
    lines[#lines + 1] = { L_DESTROY, amountText(split.de, formatMoney), "de" }
  end
  -- Bags: what the net worth adds up, and every saved character's.
  local totals = view.totals or NONE
  if view.kind == "inventory" and totals.worth ~= nil then
    lines[#lines + 1] = { L_WORTH, "" }
    lines[#lines + 1] = { L_WORTH_BAGS, amountText(totals.bagsWorth, formatMoney) }
    lines[#lines + 1] = { L_WORTH_BANK, totals.bank ~= nil and amountText(totals.bank, formatMoney) or L_WORTH_NO_BANK }
    lines[#lines + 1] = { L_WORTH_GOLD, amountText(totals.money, formatMoney) }
    if type(view.worthList) == "table" and totals.allWorth ~= nil then
      lines[#lines + 1] = { L_ALL_WORTH, "" }
      for _, c in ipairs(view.worthList) do
        local label = c.key
        if not c.own and type(view.now) == "number" and type(c.at) == "number" and c.at > 0 then
          label = label .. " (" .. ns.Util.shortAge(math.max(0, view.now - c.at)) .. ")"
        end
        lines[#lines + 1] = { label, amountText(c.total, formatMoney) }
      end
      lines[#lines + 1] = { L_WORTH_SAVED, "", wrap = true }
    end
  end
  -- The unpriced items by name (the notes line only counts them).
  local names = type(totals.unpricedNames) == "table" and totals.unpricedNames or NONE
  if #names > 0 then
    lines[#lines + 1] = { L_UNPRICED_TITLE, "" }
    for _, name in ipairs(names) do lines[#lines + 1] = { name, "" } end
    local more = (tonumber(totals.unpriced) or 0) - #names
    if more > 0 then lines[#lines + 1] = { string.format(L_AND_MORE, more), "" } end
    -- Why: nothing gives auction prices yet (view.noAuctionPrices, set by the
    -- Ledger), or the sources there are know nothing of these items.
    lines[#lines + 1] = { view.noAuctionPrices and L_WHY_NO_SOURCE or L_WHY_NO_PRICE, "", wrap = true }
  end
  -- History: which sessions the table adds up (the tabs differ, see view.scope).
  if type(view.scope) == "string" then
    lines[#lines + 1] = { " ", "" }
    lines[#lines + 1] = { view.scope, "", wrap = true }
  end
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
  local s = ns.Theme.sizes
  return (11 + 15 + 14 + 2 * iconExtra()) * s.summaryCharPx + 6 + 8 + 2 * s.textOverhang
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
      copper = r.value,
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
    local value = ns.UI.Coins.new(row, T.fonts.topRow, ink)
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
  -- Both keep S.textOverhang free on their right: an outlined text draws past
  -- its measured end (Fonts.applySizes).
  local function placeValue(fs, f, rates)
    fs:ClearAllPoints()
    fs:SetPoint("RIGHT", f, "RIGHT", -(S.textOverhang + (rates and (rateW + 8 + S.textOverhang) or 0)), 0)
  end
  local function placeRate(fs, f)
    fs:ClearAllPoints()
    fs:SetPoint("RIGHT", f, "RIGHT", -S.textOverhang, 0)
  end

  local titles = { frame = makeLine() }
  titles.value = makeText(titles.frame, T.fonts.summaryMarker, T.colors.columnTitle, "RIGHT")
  titles.value:SetText(L_VALUE)
  placeValue(titles.value, titles.frame, true)
  titles.rate = makeText(titles.frame, T.fonts.summaryMarker, T.colors.columnTitle, "RIGHT")
  placeRate(titles.rate, titles.frame)
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
    -- Value and rate in coin columns (UI/Coins.lua), lined up down the table.
    c.value = ns.UI.Coins.new(f, T.fonts.summary, color)
    placeValue(c.value, f, true)
    c.rate = ns.UI.Coins.new(f, T.fonts.summary, color)
    placeRate(c.rate, f)
    cells[key] = c
  end
  summary.cells = cells

  local notesFrame = makeLine()
  notesFrame:SetHeight(S.footerNoteHeight)
  local notes = makeText(notesFrame, T.fonts.summaryMarker, ink, "LEFT")
  notes:SetPoint("LEFT", notesFrame, "LEFT", 0, 0)
  notes:SetPoint("RIGHT", notesFrame, "RIGHT", 0, 0)
  summary.notes, summary.notesFrame = notes, notesFrame
  -- With unpriced items, a click lists them first (and back again).
  local function hasUnpriced()
    local totals = summary.view and summary.view.totals
    return type(totals) == "table" and (tonumber(totals.unpriced) or 0) > 0
  end
  -- Takes the mouse only then (SetNotes), else the table's hover covers it.
  notesFrame:SetScript("OnMouseUp", function()
    if hasUnpriced() and ns.UI.Ledger then ns.UI.Ledger.toggleUnpricedFirst() end
  end)
  notesFrame:SetScript("OnEnter", function(self)
    if not (hasUnpriced() and GameTooltip and ns.UI.Ledger) then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local C = T.colors
    GameTooltip:AddLine(ns.UI.Ledger.unpricedFirst and L_CLICK_BACK or L_CLICK_FIRST, C.hint[1], C.hint[2], C.hint[3])
    GameTooltip:Show()
  end)
  notesFrame:SetScript("OnLeave", W.hideTooltip)

  -- Hover: vendor / AH / best of the last view.
  tbl:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local C = T.colors
    for _, l in ipairs(Summary.tooltipLines(summary.view)) do
      if l.wrap then
        GameTooltip:AddLine(l[1], C.tipLabel[1], C.tipLabel[2], C.tipLabel[3], true)
      else
        local lc = (l[3] and T.sourceColor(l[3])) or C.tipValue
        GameTooltip:AddDoubleLine(l[1], l[2], lc[1], lc[2], lc[3], C.tipValue[1], C.tipValue[2], C.tipValue[3])
      end
    end
    -- Session tab: the gold per hour graph under the values.
    local graph = summary.view and summary.view.graph
    if graph then
      local tip = ns.Tooltip.new()
      ns.View.addRateGraph(tip, graph)
      GameTooltip:AddLine(" ")
      W.addTooltipLines(tip)
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
    tbl:SetShown(layout.height > 0)
    titles.frame:SetShown(layout.titles)
    titles.value:SetShown(layout.titles)
    titles.rate:SetShown(layout.titles and layout.rates)
    placeValue(titles.value, titles.frame, layout.rates)
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
    -- Measure the amounts again in the new font (an outline, a size).
    for _, key in ipairs(Summary.ROWS) do
      ns.UI.Coins.clear(cells[key].value)
      ns.UI.Coins.clear(cells[key].rate)
    end
    for i = 1, MAX_TOP do ns.UI.Coins.clear(self.rows[i].value) end
    titles.frame:SetHeight(S.footerRowHeight)
    for _, key in ipairs(Summary.ROWS) do cells[key].frame:SetHeight(S.footerRowHeight) end
    notesFrame:SetHeight(S.footerNoteHeight)
    for i = 1, MAX_TOP do placeTopRow(self.rows[i].frame, i) end
    placeValue(titles.value, titles.frame, true)
    placeRate(titles.rate, titles.frame)
    for _, key in ipairs(Summary.ROWS) do placeRate(cells[key].rate, cells[key].frame) end
    self.footerHeight, self.height = nil, nil
    self:Set(self.view)
  end

  function summary:SetNotes(view)
    local text, orange = Summary.notesText(view, ns.UI.Ledger and ns.UI.Ledger.unpricedFirst)
    local totals = type(view) == "table" and view.totals
    notesFrame:EnableMouse(type(totals) == "table" and (tonumber(totals.unpriced) or 0) > 0)
    if not text then return end
    W.setTextColor(notes, orange and stale or ink)
    notes:SetText(text)
  end

  -- Top finds: up to MAX_TOP lines; the box collapses without any.
  function summary:SetTop(top)
    local lines = Summary.topLines(top)
    local values = {}
    for i = 1, MAX_TOP do
      local w, l = self.rows[i], lines[i]
      if l then
        local r, g, b = T.qualityColor(l.quality)
        W.setTextRGB(w.name, r, g, b, 1)
        w.name:SetText(l.name)
        w.qty:SetText(l.qty)
        ns.UI.Coins.set(w.value, l.copper, l.value)
        values[#values + 1] = w.value
        w.tooltipLink, w.link = l.tooltipLink, l.link
        w.frame:Show()
      else
        w.frame:Hide()
      end
    end
    ns.UI.Coins.align(values)
    -- Option "showTopFinds" off: the block stays collapsed.
    local shown = ns.Util.setting("showTopFinds", true)
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
    local values, rates = {}, {}
    for _, key in ipairs(Summary.ROWS) do
      local t, c = texts[key], cells[key]
      ns.UI.Coins.set(c.value, t.valueCopper, t.value)
      ns.UI.Coins.set(c.rate, t.rateCopper, t.rate)
      values[#values + 1], rates[#rates + 1] = c.value, c.rate
    end
    -- Each column in shared coin columns (the cells of hidden rows are hidden).
    ns.UI.Coins.align(values)
    ns.UI.Coins.align(rates)
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
