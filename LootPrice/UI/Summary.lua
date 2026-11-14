local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Top finds block (topBox, at the bottom of the window under the summaries) and
-- the summaries (footer). Client-only widgets;
-- every WoW global is touched inside functions only. totalsText, topLines and
-- topBoxHeight are pure.
local Summary = {}
ns.UI.Summary = Summary

local L_TOP = "Top finds"
local L_VENDOR = "Vendor: "
local L_AH = "AH: "
local L_PER_HOUR = "/h"
local L_UNPRICED = " unpriced"
local L_FILTERED = "filtered"
local L_GOLD = "Gold "
local L_LABEL_ITEMS = "Items"
local L_LABEL_GOLD = "Raw gold"
local L_LABEL_TOTAL = "Items + gold"
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

-- "12g 5s/h", or an em dash while there is no rate yet.
function Summary.rateText(perHour, formatMoney)
  if perHour == nil then return DASH end
  return (formatMoney or ns.Money.formatColored)(perHour) .. L_PER_HOUR
end

-- Items block: `totals` = View totals {vendor, ah, vendorPerHour, ahPerHour,
-- unpriced, filtered}.
function Summary.totalsText(totals, formatMoney)
  totals = totals or NONE
  local unpriced = tonumber(totals.unpriced) or 0
  return {
    vendor = L_VENDOR .. amountText(totals.vendor, formatMoney),
    vendorRate = Summary.rateText(totals.vendorPerHour, formatMoney),
    ah = L_AH .. amountText(totals.ah, formatMoney),
    ahRate = Summary.rateText(totals.ahPerHour, formatMoney),
    unpriced = unpriced > 0 and (unpriced .. L_UNPRICED) or nil,
    filtered = totals.filtered and true or false,
  }
end

-- Raw gold block: `gold` = View gold {total, perHour}; one line, total left and
-- rate right (an em dash while the rate is nil).
function Summary.goldText(gold, formatMoney)
  gold = gold or NONE
  return {
    total = L_GOLD .. amountText(gold.total, formatMoney),
    rate = Summary.rateText(gold.perHour, formatMoney),
  }
end

-- Combined items + gold block: `combined` = View combined {vendor, ah,
-- vendorPerHour, ahPerHour}. Same texts as the item totals, without the
-- unpriced / filtered markers (those belong to the item block only).
function Summary.combinedText(combined, formatMoney)
  combined = combined or NONE
  return {
    vendor = L_VENDOR .. amountText(combined.vendor, formatMoney),
    vendorRate = Summary.rateText(combined.vendorPerHour, formatMoney),
    ah = L_AH .. amountText(combined.ah, formatMoney),
    ahRate = Summary.rateText(combined.ahPerHour, formatMoney),
  }
end

-- Vertical layout of the footer blocks from the top: label row then content.
-- Returns { items = {top, labelTop, contentTop, height}, gold = ..., total = ...,
-- height = total footer height }.
function Summary.footerLayout()
  local s = ns.Theme.sizes
  local y = 0
  local function block(contentHeight)
    local b = { top = y, labelHeight = s.footerLabelHeight, contentTop = y + s.footerLabelHeight,
      contentHeight = contentHeight, height = s.footerLabelHeight + contentHeight }
    y = y + b.height
    return b
  end
  local layout = {
    items = block(s.footerItemsHeight),
    gold = block(s.footerGoldHeight),
    total = block(s.footerTotalHeight),
  }
  layout.height = y
  return layout
end

-- Footer height per view kind: the session shows all three blocks; the
-- inventory tabs only the items block, plus a note line when the view has one.
function Summary.footerHeightFor(view)
  local s = ns.Theme.sizes
  local layout = Summary.footerLayout()
  if type(view) == "table" and view.kind == "inventory" then
    return layout.items.height + (view.note and s.footerNoteHeight or 0)
  end
  if type(view) == "table" and view.noCombined then
    return layout.height - layout.total.height
  end
  return layout.height
end

-- Window height the list needs: chrome around the content, header, a full Top
-- finds block, `minListRows` rows and the footer.
function Summary.requiredWindowHeight()
  local s = ns.Theme.sizes
  return 2 * (s.padding + 4) + s.headerHeight + Summary.topBoxHeight(MAX_TOP)
    + s.minListRows * s.rowHeight + Summary.footerLayout().height
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

-- Width of one footer half at a window `width`: the content width minus the
-- 4 px gap either side of the center line, split in two.
function Summary.footerHalfWidth(width)
  local s = ns.Theme.sizes
  return (width - 2 * (s.padding + 4) - 8) / 2
end

-- Estimated width of the worst second line of a half: a rate with 14
-- characters ("999g 59s 59c/h") in the summary font, a 6 px gap and a marker
-- with 11 characters ("99 unpriced") in the marker font.
function Summary.footerWorstWidth()
  local s = ns.Theme.sizes
  return 14 * s.summaryCharPx + 6 + 11 * s.markerCharPx
end

-- ---------------------------------------------------------------------------
-- Widgets

-- Footer layout at the 326 px content minimum (350 px window): three blocks,
-- each under a label row. Items and Total: a stacked pair per half (total
-- above, rate below), ~159 px per line (Summary.footerHalfWidth). Gold: one
-- line, total left / rate right.
function Summary.attach(topBox, footer)
  if Summary.instance then return Summary.instance end
  local T = ns.Theme
  local W = ns.UI.Widgets
  local makeText = W.text
  local S = T.sizes
  local ink, stale = T.colors.ink, T.colors.stale
  local titleColor = T.colors.sectionTitle
  local line = T.colors.goldLine

  local summary = { topBox = topBox, footer = footer, rows = {}, height = nil }

  -- Top finds (bottom of the window, under the summaries). The divider is the
  -- top edge of the topBox; the content starts below it.
  local off = S.dividerHeight + S.padding / 2
  local header = makeText(topBox, T.fonts.topHeader, titleColor)
  header:SetPoint("TOPLEFT", topBox, "TOPLEFT", 0, -off)
  header:SetText(L_TOP)
  summary.header = header

  for i = 1, MAX_TOP do
    local row = CreateFrame("Frame", nil, topBox)
    row:SetHeight(S.topRowHeight)
    row:SetPoint("TOPLEFT", topBox, "TOPLEFT", 0, -(off + S.topHeaderHeight + (i - 1) * S.topRowHeight))
    row:SetPoint("TOPRIGHT", topBox, "TOPRIGHT", 0, -(off + S.topHeaderHeight + (i - 1) * S.topRowHeight))
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
    summary.rows[i] = entry
  end

  -- Divider between the summaries and the Top finds block: the top edge of the
  -- topBox, so it disappears together with a collapsed topBox.
  local divider = W.line(topBox, T.colors.divider)
  divider:SetHeight(S.dividerHeight)
  divider:SetPoint("TOPLEFT", topBox, "TOPLEFT", 0, 0)
  divider:SetPoint("TOPRIGHT", topBox, "TOPRIGHT", 0, 0)
  summary.divider = divider

  -- Footer: three stacked blocks (items, raw gold, items + gold). Each starts
  -- with a title row (gold title, thin separator line to its right).
  local layout = Summary.footerLayout()
  local sep = T.colors.rowSeparator

  local function block(b, labelText)
    local frame = CreateFrame("Frame", nil, footer)
    frame:SetHeight(b.contentHeight)
    frame:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, -b.contentTop)
    frame:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, -b.contentTop)
    local label = makeText(footer, T.fonts.blockLabel, titleColor, "LEFT")
    label:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, -b.top)
    label:SetHeight(b.labelHeight)
    label:SetText(labelText)
    local rule = W.line(footer, sep)
    rule:SetHeight(S.rowSeparator)
    rule:SetPoint("LEFT", label, "RIGHT", S.footerLabelGap, 0)
    rule:SetPoint("RIGHT", footer, "RIGHT", 0, 0)
    -- Label and rule live on the footer, so they are shown / hidden with the box.
    function frame:SetBlockShown(shown)
      self:SetShown(shown)
      label:SetShown(shown)
      rule:SetShown(shown)
    end
    return frame
  end

  -- A stacked vendor/AH pair: totals line over rate line, left and right half.
  local function pair(parent)
    local p = {}
    p.vendor = makeText(parent, T.fonts.summary, ink, "LEFT")
    p.vendor:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -1)
    p.vendor:SetPoint("TOPRIGHT", parent, "TOP", -4, -1)
    p.vendorRate = makeText(parent, T.fonts.summary, ink, "LEFT")
    p.vendorRate:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 1)
    p.ah = makeText(parent, T.fonts.summary, ink, "RIGHT")
    p.ah:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -1)
    p.ah:SetPoint("TOPLEFT", parent, "TOP", 4, -1)
    p.ahRate = makeText(parent, T.fonts.summary, ink, "RIGHT")
    p.ahRate:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 1)
    return p
  end

  local itemsBox = block(layout.items, L_LABEL_ITEMS)
  local items = pair(itemsBox)
  local filtered = makeText(itemsBox, T.fonts.summaryMarker, stale, "LEFT")
  filtered:SetPoint("LEFT", items.vendorRate, "RIGHT", 6, 0)
  filtered:SetText(L_FILTERED)
  filtered:Hide()
  local unpriced = makeText(itemsBox, T.fonts.summaryMarker, stale, "RIGHT")
  unpriced:SetPoint("RIGHT", items.ahRate, "LEFT", -6, 0)
  unpriced:Hide()

  local goldBox = block(layout.gold, L_LABEL_GOLD)
  local goldTotal = makeText(goldBox, T.fonts.summary, ink, "LEFT")
  goldTotal:SetPoint("TOPLEFT", goldBox, "TOPLEFT", 0, -1)
  local goldRate = makeText(goldBox, T.fonts.summary, ink, "RIGHT")
  goldRate:SetPoint("TOPRIGHT", goldBox, "TOPRIGHT", 0, -1)
  goldTotal:SetPoint("TOPRIGHT", goldBox, "TOP", 0, -1)

  local totalBox = block(layout.total, L_LABEL_TOTAL)
  local total = pair(totalBox)

  -- Scan-age note of the bank tab, under the items block.
  local note = makeText(footer, T.fonts.summaryMarker, T.colors.ink, "LEFT")
  note:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, -(layout.items.height + 2))
  note:Hide()

  summary.items, summary.vendor, summary.vendorRate = items, items.vendor, items.vendorRate
  summary.ah, summary.ahRate = items.ah, items.ahRate
  summary.filtered, summary.unpriced = filtered, unpriced
  summary.goldTotal, summary.goldRate = goldTotal, goldRate
  summary.total = total
  summary.goldBox, summary.totalBox, summary.note = goldBox, totalBox, note

  -- Footer blocks and height for the view kind (session / inventory).
  function summary:SetKind(view)
    local inventory = view.kind == "inventory"
    local noCombined = view.noCombined and true or false
    if inventory ~= self.inventory then
      self.inventory = inventory
      self.goldBox:SetBlockShown(not inventory)
    end
    if inventory ~= self.inventoryTotal or noCombined ~= self.noCombined then
      self.inventoryTotal, self.noCombined = inventory, noCombined
      self.totalBox:SetBlockShown(not inventory and not noCombined)
    end
    local footerHeight = Summary.footerHeightFor(view)
    if footerHeight ~= self.footerHeight then
      self.footerHeight = footerHeight
      if ns.UI.Window and ns.UI.Window.setFooterHeight then
        ns.UI.Window.setFooterHeight(footerHeight)
      end
    end
  end

  -- Scan-age note under the items block (bank tab).
  function summary:SetNote(text, isStale)
    if not text then
      self.note:Hide()
      return
    end
    W.setTextColor(self.note, isStale and stale or ink)
    self.note:SetText(text)
    self.note:Show()
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
        w.tooltipLink = l.tooltipLink
        w.frame:Show()
      else
        w.frame:Hide()
      end
    end
    local height = Summary.topBoxHeight(#lines)
    if height ~= self.height then
      self.height = height
      if ns.UI.Window and ns.UI.Window.setTopBoxHeight then
        ns.UI.Window.setTopBoxHeight(height)
      end
    end
  end

  -- The amounts: item totals with the unpriced / filtered markers and, on the
  -- session tab, raw gold and the combined totals.
  function summary:SetTotals(view)
    local totals = view.totals or NONE
    self.vendor:SetText(L_VENDOR .. amountText(totals.vendor))
    self.ah:SetText(L_AH .. amountText(totals.ah))
    local unpricedCount = tonumber(totals.unpriced) or 0
    if unpricedCount > 0 then
      self.unpriced:SetText(unpricedCount .. L_UNPRICED)
      self.unpriced:Show()
    else
      self.unpriced:Hide()
    end
    self.filtered:SetShown(totals.filtered and true or false)
    if self.inventory then return end

    local gold, combined = view.gold or NONE, view.combined or NONE
    self.goldTotal:SetText(L_GOLD .. amountText(gold.total))
    self.total.vendor:SetText(L_VENDOR .. amountText(combined.vendor))
    self.total.ah:SetText(L_AH .. amountText(combined.ah))
  end

  -- The per-hour rates: the only footer texts that change with the clock.
  function summary:SetRates(view)
    local rateText = Summary.rateText
    local totals = view.totals or NONE
    self.vendorRate:SetText(rateText(totals.vendorPerHour))
    self.ahRate:SetText(rateText(totals.ahPerHour))
    if self.inventory then return end

    local gold, combined = view.gold or NONE, view.combined or NONE
    self.goldRate:SetText(rateText(gold.perHour))
    self.total.vendorRate:SetText(rateText(combined.vendorPerHour))
    self.total.ahRate:SetText(rateText(combined.ahPerHour))
  end

  function summary:Set(view)
    view = view or NONE
    self:SetKind(view)
    self:SetNote(view.note, view.noteStale)
    self:SetTop(view.top)
    self:SetTotals(view)
    self:SetRates(view)
  end

  -- Ledger part: everything on a full refresh, only the rates on a clock tick.
  local part = {}
  function part:Update(view) summary:Set(view) end
  function part:Tick(view) summary:SetRates(view) end
  if ns.UI.Ledger then ns.UI.Ledger.register(part) end

  Summary.instance = summary
  return summary
end
