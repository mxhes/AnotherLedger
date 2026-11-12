local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Top finds block (topBox) and totals bar (footer). Client-only widgets;
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
  return s.topHeaderHeight + count * s.topRowHeight + s.padding / 2
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

-- Footer layout at the 296 px content minimum: a stacked pair per half
-- (total above, rate below), so long money strings keep ~140 px per line.
function Summary.attach(topBox, footer)
  if Summary.instance then return Summary.instance end
  local T = ns.Theme
  local S = T.sizes
  local ink, gold, stale = T.colors.ink, T.colors.gold, T.colors.stale
  local line = T.colors.goldLine

  local summary = { topBox = topBox, footer = footer, rows = {}, height = nil }

  -- Top finds
  local header = makeText(topBox, T.fonts.small, gold)
  header:SetPoint("TOPLEFT", topBox, "TOPLEFT", 0, 0)
  header:SetText(L_TOP)
  summary.header = header

  for i = 1, MAX_TOP do
    local row = CreateFrame("Frame", nil, topBox)
    row:SetHeight(S.topRowHeight)
    row:SetPoint("TOPLEFT", topBox, "TOPLEFT", 0, -(S.topHeaderHeight + (i - 1) * S.topRowHeight))
    row:SetPoint("TOPRIGHT", topBox, "TOPRIGHT", 0, -(S.topHeaderHeight + (i - 1) * S.topRowHeight))
    local edge = row:CreateTexture(nil, "ARTWORK")
    edge:SetTexture(T.textures.rowHighlight)
    edge:SetVertexColor(line[1], line[2], line[3], 0.9)
    edge:SetWidth(2)
    edge:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)
    local value = makeText(row, T.fonts.small, ink, "RIGHT")
    value:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    local qty = makeText(row, T.fonts.small, ink, "RIGHT")
    qty:SetPoint("RIGHT", value, "LEFT", -6, 0)
    local name = makeText(row, T.fonts.small, ink, "LEFT")
    name:SetPoint("LEFT", row, "LEFT", 6, 0)
    name:SetPoint("RIGHT", qty, "LEFT", -6, 0)
    row:Hide()
    summary.rows[i] = { frame = row, name = name, qty = qty, value = value }
  end

  -- Totals bar
  local vendor = makeText(footer, T.fonts.small, ink, "LEFT")
  vendor:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, -1)
  vendor:SetPoint("TOPRIGHT", footer, "TOP", -4, -1)
  local vendorRate = makeText(footer, T.fonts.small, ink, "LEFT")
  vendorRate:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", 0, 1)
  local filtered = makeText(footer, T.fonts.small, stale, "LEFT")
  filtered:SetPoint("LEFT", vendorRate, "RIGHT", 6, 0)
  filtered:SetText(L_FILTERED)
  filtered:Hide()
  local ah = makeText(footer, T.fonts.small, ink, "RIGHT")
  ah:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, -1)
  ah:SetPoint("TOPLEFT", footer, "TOP", 4, -1)
  local ahRate = makeText(footer, T.fonts.small, ink, "RIGHT")
  ahRate:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", 0, 1)
  local unpriced = makeText(footer, T.fonts.small, stale, "RIGHT")
  unpriced:SetPoint("RIGHT", ahRate, "LEFT", -6, 0)
  unpriced:Hide()
  summary.vendor, summary.vendorRate, summary.filtered = vendor, vendorRate, filtered
  summary.ah, summary.ahRate, summary.unpriced = ah, ahRate, unpriced

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
  end

  -- Ledger part: refreshed with every tick / loot event.
  local part = {}
  function part:Update(v) summary:Set(v) end
  if ns.UI.Ledger then ns.UI.Ledger.register(part) end

  Summary.instance = summary
  return summary
end
