local ADDON, ns = ...

local L = ns.L

ns.UI = ns.UI or {}

-- Compact mode body (the glance between pulls): gold per hour in large type
-- with the session total next to it, the last drops (name, value and source
-- tag, Task "one counted value" style) and the Daily farm line. Draws
-- view.compact (View.buildCompact); only while the window is in compact mode.
-- Client-only; every WoW global is touched inside functions only. dropText is
-- pure.
local Compact = {}
ns.UI.Compact = Compact

local L_PER_HOUR = L["/h"]
local L_LAST_DROPS = L["Last drops"]
local DASH = "\226\128\148" -- em dash (UTF-8)
local MAX_DROPS = 4

-- Pure. Texts of one drop line: name, quantity, amount, source (nil without).
function Compact.dropText(row, formatMoney)
  local t = ns.UI.Rows.rowText(row, formatMoney)
  return { name = t.name, qty = t.qty, amount = t.amount, source = t.source, sourceText = t.sourceText }
end

-- Pure. Window height the compact body needs: chrome, the title row, the top
-- block, four drop rows and the Daily farm line (Theme.sizes.compactMinHeight
-- must not be smaller).
function Compact.requiredHeight()
  local S = ns.Theme.sizes
  local inset = S.padding + 4
  return 2 * inset + S.headerRowHeight + S.padding / 2
    + S.compactDropsTop + (MAX_DROPS + 1) * S.compactRowHeight + S.compactGap
end

-- Pure. The big number: gold per hour, or an em dash under a minute.
function Compact.rateText(perHour, formatMoney)
  if perHour == nil then return DASH end
  return (formatMoney or ns.Money.formatColored)(math.floor(perHour + 0.5)) .. L_PER_HOUR
end

-- ---------------------------------------------------------------------------
-- Widgets

local function setColor(fs, c) ns.UI.Widgets.setTextColor(fs, c) end

local part = {}

function part:Update(view)
  if not (ns.UI.Ledger and ns.UI.Ledger.mode == "compact") then return end
  local c = view and view.compact
  if not c then return end
  local T = ns.Theme
  Compact.perHour:SetText(Compact.rateText(c.perHour))
  Compact.total:SetText(ns.Money.formatColored(c.total or 0))

  local drops = c.drops or {}
  Compact.dropsTitle:SetShown(#drops > 0)
  for i = 1, MAX_DROPS do
    local w = Compact.drops[i]
    local row = drops[i]
    if row then
      local t = Compact.dropText(row)
      local r, g, b = T.qualityColor(row.quality)
      w.name:SetText(t.name .. " " .. t.qty)
      ns.UI.Widgets.setTextRGB(w.name, r, g, b, 1)
      w.amount:SetText(t.amount)
      if t.source then
        local col = T.colors[ns.UI.Rows.SOURCE_COLOR[t.source]] or T.colors.ink
        w.tag:SetText(t.sourceText)
        setColor(w.tag, col)
        w.tag:Show()
      else
        w.tag:Hide()
      end
      w.frame:Show()
    else
      w.frame:Hide()
    end
  end

  local farm = view.dailyFarm
  if farm and ns.UI.DailyFarm then
    Compact.farmText:SetText(ns.UI.DailyFarm.label(farm))
    Compact.farm:Show()
  else
    Compact.farm:Hide()
  end
end

-- The rate and total change with the clock (Ledger.tick rebuilds view.compact).
part.Tick = part.Update

-- Attaches to the window's compact area (Window.frame.compact).
function Compact.attach(area)
  if Compact.area then return Compact end
  local T = ns.Theme
  local W = ns.UI.Widgets
  local S = T.sizes
  Compact.area = area

  -- The rate never shrinks; the total takes what is left right of it.
  local perHour = W.text(area, T.fonts.compactBig, T.colors.gold, "LEFT")
  perHour:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
  if perHour.SetWordWrap then perHour:SetWordWrap(false) end
  local total = W.text(area, T.fonts.compactMid, T.colors.ink, "RIGHT")
  total:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -3)
  total:SetPoint("LEFT", perHour, "RIGHT", S.rowNameGap, 0)
  if total.SetWordWrap then total:SetWordWrap(false) end
  Compact.perHour, Compact.total = perHour, total

  local line = W.line(area, T.colors.divider)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -28)
  line:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -28)

  local title = W.text(area, T.fonts.small, T.colors.hint, "LEFT")
  title:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -32)
  title:SetText(L_LAST_DROPS)
  Compact.dropsTitle = title

  Compact.drops = {}
  for i = 1, MAX_DROPS do
    local f = CreateFrame("Frame", nil, area)
    f:SetHeight(S.compactRowHeight)
    local y = -S.compactDropsTop - (i - 1) * S.compactRowHeight
    f:SetPoint("TOPLEFT", area, "TOPLEFT", 0, y)
    f:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, y)
    local tag = W.text(f, T.fonts.sourceTag, T.colors.ink, "RIGHT")
    tag:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    local amount = W.text(f, T.fonts.rowSmall, T.colors.ink, "RIGHT")
    amount:SetPoint("RIGHT", tag, "LEFT", -S.rowLabelGap - S.rowTagPad, 0)
    local name = W.text(f, T.fonts.rowSmall, T.colors.ink, "LEFT")
    name:SetPoint("LEFT", f, "LEFT", 0, 0)
    name:SetPoint("RIGHT", amount, "LEFT", -S.rowNameGap, 0)
    if name.SetWordWrap then name:SetWordWrap(false) end
    f:Hide()
    Compact.drops[i] = { frame = f, name = name, amount = amount, tag = tag }
  end

  -- Daily farm line at the bottom: same text and clicks as the strip.
  local farm = CreateFrame("Button", nil, area)
  farm:SetHeight(S.compactRowHeight)
  farm:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", 0, 0)
  farm:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, 0)
  farm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  farm:SetScript("OnClick", function(_, which)
    local DF = ns.UI.DailyFarm
    if DF then DF.click(which, type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and true or false) end
  end)
  farm:SetScript("OnEnter", function(self)
    local DF = ns.UI.DailyFarm
    if DF and DF.farm then W.showTextTooltip(self, DF.hint(DF.farm), "ANCHOR_BOTTOMLEFT") end
  end)
  farm:SetScript("OnLeave", W.hideTooltip)
  local farmText = W.text(farm, T.fonts.small, T.colors.dailyFarm, "LEFT")
  farmText:SetPoint("LEFT", farm, "LEFT", 0, 0)
  farmText:SetPoint("RIGHT", farm, "RIGHT", 0, 0)
  if farmText.SetWordWrap then farmText:SetWordWrap(false) end
  farm:Hide()
  Compact.farm, Compact.farmText = farm, farmText

  if ns.UI.Ledger then ns.UI.Ledger.register(part) end
  return Compact
end
