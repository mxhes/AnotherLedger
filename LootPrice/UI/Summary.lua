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

local function money(v)
  return ns.Money.format(tonumber(v) or 0)
end

local function moneyColored(v)
  return ns.Money.formatColored(tonumber(v) or 0)
end

local function rate(v)
  if v == nil then return DASH end
  return ns.Money.format(v) .. L_PER_HOUR
end

local function rateColored(v)
  if v == nil then return DASH end
  return ns.Money.formatColored(v) .. L_PER_HOUR
end

function Summary.totalsText(totals)
  totals = totals or {}
  local unpriced = tonumber(totals.unpriced) or 0
  return {
    vendor = L_VENDOR .. money(totals.vendor),
    vendorRate = rate(totals.vendorPerHour),
    ah = L_AH .. money(totals.ah),
    ahRate = rate(totals.ahPerHour),
    -- Same texts with colored coin amounts (color escapes), used by the UI.
    vendorColored = L_VENDOR .. moneyColored(totals.vendor),
    vendorRateColored = rateColored(totals.vendorPerHour),
    ahColored = L_AH .. moneyColored(totals.ah),
    ahRateColored = rateColored(totals.ahPerHour),
    unpriced = unpriced > 0 and (unpriced .. L_UNPRICED) or nil,
    filtered = totals.filtered and true or false,
  }
end

-- Raw gold block: `gold` = View gold {total, perHour}; one line, total left and
-- rate right (an em dash while the rate is nil).
function Summary.goldText(gold)
  gold = gold or {}
  return {
    total = L_GOLD .. money(gold.total),
    rate = rate(gold.perHour),
    totalColored = L_GOLD .. moneyColored(gold.total),
    rateColored = rateColored(gold.perHour),
  }
end

-- Combined items + gold block: `combined` = View combined {vendor, ah,
-- vendorPerHour, ahPerHour}. Same texts as the item totals, without the
-- unpriced / filtered markers (those belong to the item block only).
function Summary.combinedText(combined)
  local t = Summary.totalsText(combined)
  return {
    vendor = t.vendor, vendorRate = t.vendorRate, ah = t.ah, ahRate = t.ahRate,
    vendorColored = t.vendorColored, vendorRateColored = t.vendorRateColored,
    ahColored = t.ahColored, ahRateColored = t.ahRateColored,
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

-- Window height the list needs: chrome around the content, header, a full Top
-- finds block, `minListRows` rows and the footer.
function Summary.requiredWindowHeight()
  local s = ns.Theme.sizes
  return 2 * (s.padding + 4) + s.headerHeight + Summary.topBoxHeight(MAX_TOP)
    + s.minListRows * s.rowHeight + Summary.footerLayout().height
end

function Summary.topLines(top)
  local out = {}
  if type(top) ~= "table" then return out end
  for i = 1, math.min(#top, MAX_TOP) do
    local r = top[i]
    out[#out + 1] = {
      name = r.name or "?",
      qty = "x" .. (tonumber(r.quantity) or 0),
      valueText = ns.Money.format(r.value),
      valueColored = ns.Money.formatColored(r.value),
      quality = r.quality,
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

local function makeText(parent, font, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  return fs
end

-- Footer layout at the 326 px content minimum (350 px window): three blocks,
-- each under a label row. Items and Total: a stacked pair per half (total
-- above, rate below), ~159 px per line (Summary.footerHalfWidth). Gold: one
-- line, total left / rate right.
function Summary.attach(topBox, footer)
  if Summary.instance then return Summary.instance end
  local T = ns.Theme
  local S = T.sizes
  local ink, gold, stale = T.colors.ink, T.colors.gold, T.colors.stale
  local line = T.colors.goldLine

  local summary = { topBox = topBox, footer = footer, rows = {}, height = nil }

  -- Top finds (bottom of the window, under the summaries). The divider is the
  -- top edge of the topBox; the content starts below it.
  local off = S.dividerHeight + S.padding / 2
  local header = makeText(topBox, T.fonts.topHeader, gold)
  header:SetPoint("TOPLEFT", topBox, "TOPLEFT", 0, -off)
  header:SetText(L_TOP)
  summary.header = header

  for i = 1, MAX_TOP do
    local row = CreateFrame("Frame", nil, topBox)
    row:SetHeight(S.topRowHeight)
    row:SetPoint("TOPLEFT", topBox, "TOPLEFT", 0, -(off + S.topHeaderHeight + (i - 1) * S.topRowHeight))
    row:SetPoint("TOPRIGHT", topBox, "TOPRIGHT", 0, -(off + S.topHeaderHeight + (i - 1) * S.topRowHeight))
    local edge = row:CreateTexture(nil, "ARTWORK")
    edge:SetTexture(T.textures.rowHighlight)
    edge:SetVertexColor(line[1], line[2], line[3], 0.9)
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
    summary.rows[i] = { frame = row, name = name, qty = qty, value = value }
  end

  -- Divider between the summaries and the Top finds block: the top edge of the
  -- topBox, so it disappears together with a collapsed topBox.
  local divider = topBox:CreateTexture(nil, "ARTWORK")
  divider:SetTexture(T.textures.rowHighlight)
  local dc = T.colors.divider
  divider:SetVertexColor(dc[1], dc[2], dc[3], dc[4])
  divider:SetHeight(S.dividerHeight)
  divider:SetPoint("TOPLEFT", topBox, "TOPLEFT", 0, 0)
  divider:SetPoint("TOPRIGHT", topBox, "TOPRIGHT", 0, 0)
  summary.divider = divider

  -- Footer: three stacked blocks (items, raw gold, items + gold). Each starts
  -- with a title row (gold title, thin separator line to its right).
  local layout = Summary.footerLayout()
  local titleColor = T.colors.gold
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
    local rule = footer:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(T.textures.rowHighlight)
    rule:SetVertexColor(sep[1], sep[2], sep[3], sep[4])
    rule:SetHeight(S.rowSeparator)
    rule:SetPoint("LEFT", label, "RIGHT", S.footerLabelGap, 0)
    rule:SetPoint("RIGHT", footer, "RIGHT", 0, 0)
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

  summary.items, summary.vendor, summary.vendorRate = items, items.vendor, items.vendorRate
  summary.ah, summary.ahRate = items.ah, items.ahRate
  summary.filtered, summary.unpriced = filtered, unpriced
  summary.goldTotal, summary.goldRate = goldTotal, goldRate
  summary.total = total

  function summary:Set(view)
    view = view or {}
    local lines = Summary.topLines(view.top)
    for i = 1, MAX_TOP do
      local w, l = self.rows[i], lines[i]
      if l then
        local r, g, b = T.qualityColor(l.quality, true)
        w.name:SetTextColor(r, g, b, 1)
        w.name:SetText(l.name)
        w.qty:SetText(l.qty)
        w.value:SetText(l.valueColored)
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

    local t = Summary.totalsText(view.totals)
    self.vendor:SetText(t.vendorColored)
    self.vendorRate:SetText(t.vendorRateColored)
    self.ah:SetText(t.ahColored)
    self.ahRate:SetText(t.ahRateColored)
    if t.unpriced then
      self.unpriced:SetText(t.unpriced)
      self.unpriced:Show()
    else
      self.unpriced:Hide()
    end
    self.filtered:SetShown(t.filtered)

    local g = Summary.goldText(view.gold)
    self.goldTotal:SetText(g.totalColored)
    self.goldRate:SetText(g.rateColored)

    local c = Summary.combinedText(view.combined)
    self.total.vendor:SetText(c.vendorColored)
    self.total.vendorRate:SetText(c.vendorRateColored)
    self.total.ah:SetText(c.ahColored)
    self.total.ahRate:SetText(c.ahRateColored)
  end

  -- Ledger part: refreshed with every tick / loot event.
  local part = {}
  function part:Update(v) summary:Set(v) end
  if ns.UI.Ledger then ns.UI.Ledger.register(part) end

  Summary.instance = summary
  return summary
end
