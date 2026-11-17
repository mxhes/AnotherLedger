local ADDON, ns = ...

local L = ns.L

ns.UI = ns.UI or {}

-- Compact mode body (the glance between pulls): gold per hour in large type
-- with the session total next to it, the last drops (name, the counted value
-- and its source tag) and the Daily farm line. Draws view.compact
-- (View.buildCompact); only while the window is in compact mode.
-- Client-only; every WoW global is touched inside functions only. dropText is
-- pure.
local Compact = {}
ns.UI.Compact = Compact

local L_PER_HOUR = L["/h"]
local L_LAST_DROPS = L["Last drops"]
local L_SESSION = L["Session"]
local L_NO_DROPS = L["No drops yet."]
local L_PAUSED = L["Paused: click the clock to start."]
local L_TIME = L["Time: "]
local L_ITEMS = L["Items: "]
local L_RAW_GOLD = L["Raw gold: "]
local L_TOTAL = L["Total: "]
local L_GOLD_PER_HOUR = L["Gold per hour: "]
local L_NO_RATE = L["Gold per hour shows after the first minute."]
local L_BEST_FIND = L["Best find: "]
local L_GOAL = L["Goal: "]
local DASH = "\226\128\148" -- em dash (UTF-8)
local MAX_DROPS = 4

-- Pure. Texts of one drop line: name, quantity, amount, source (nil without).
function Compact.dropText(row, formatMoney)
  local t = ns.UI.Rows.rowText(row, formatMoney)
  return { name = t.name, qty = t.qty, amount = t.amount, copper = t.copper, source = t.source,
    sourceText = t.sourceText }
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
  if perHour == nil then return DASH .. L_PER_HOUR end
  return (formatMoney or ns.Money.formatColored)(math.floor(perHour + 0.5)) .. L_PER_HOUR
end

-- Pure. The text right of the rate: "Session 312g", or "Session 312g / 500g"
-- with a session goal. `hint` wraps the quiet parts (a color code, or none).
function Compact.totalText(c, formatMoney, hint)
  formatMoney = formatMoney or ns.Money.formatColored
  local open, close = hint or "", hint and "|r" or ""
  local text = open .. L_SESSION .. close .. " " .. formatMoney(c.total or 0)
  if c.goal then text = text .. open .. " / " .. close .. formatMoney(c.goal.goal) end
  return text
end

-- Pure. The hover breakdown of the rate and total (ns.Tooltip): the clock,
-- the items, the raw gold, the total and its rate, the best find and the goal.
function Compact.hint(c)
  local Tip = ns.Tooltip
  local tip = Tip.new(L_SESSION)
  Tip.pair(tip, L_TIME, ns.History.duration(c.elapsed or 0))
  Tip.money(tip, L_ITEMS, c.items or 0)
  if (c.gold or 0) > 0 then Tip.money(tip, L_RAW_GOLD, c.gold) end
  Tip.money(tip, L_TOTAL, c.total or 0)
  if c.perHour then
    Tip.rate(tip, L_GOLD_PER_HOUR, c.perHour)
  else
    Tip.note(tip, L_NO_RATE)
  end
  if c.top then
    local qty = (c.top.quantity or 1) > 1 and (" x" .. c.top.quantity) or ""
    Tip.money(tip, L_BEST_FIND .. c.top.name .. qty, c.top.value)
  end
  if c.goal then
    Tip.pair(tip, L_GOAL, ns.View.goalPercent(c.goal) .. "%")
  end
  ns.View.addRateGraph(tip, c.graph)
  return tip
end

-- ---------------------------------------------------------------------------
-- Widgets

local part = {}

function part:Update(view)
  if not (ns.UI.Ledger and ns.UI.Ledger.mode == "compact") then return end
  local c = view and view.compact
  if not c then return end
  local T = ns.Theme
  Compact.perHour:SetText(Compact.rateText(c.perHour))
  Compact.total:SetText(Compact.totalText(c, nil, ns.Money.colorCode(T.colors.hint)))
  Compact.view = c
  -- A shown breakdown follows the numbers.
  local W = ns.UI.Widgets
  if Compact.hover and W.tooltipOwnedBy(Compact.hover) then W.showTextTooltip(Compact.hover, Compact.hint(c)) end

  -- Without drops the title line says why the list is empty.
  local drops = c.drops or {}
  if #drops > 0 then
    Compact.dropsTitle:SetText(L_LAST_DROPS)
  else
    Compact.dropsTitle:SetText(c.running and L_NO_DROPS or L_PAUSED)
  end
  local cells = {}
  for i = 1, MAX_DROPS do
    local w = Compact.drops[i]
    local row = drops[i]
    if row then
      local t = Compact.dropText(row)
      local r, g, b = T.qualityColor(row.quality)
      w.name:SetText(t.name .. " " .. t.qty)
      ns.UI.Widgets.setTextRGB(w.name, r, g, b, 1)
      ns.UI.Coins.set(w.amount, t.copper, t.amount)
      cells[#cells + 1] = w.amount
      -- The same framed tag as the list rows, lined up with the widest one.
      ns.UI.Rows.setSourceTag(w.tag, t.source, ns.UI.Rows.widestSource)
      -- On whole screen pixels, so its frame is equally thin on every side.
      ns.UI.Widgets.snapPoint(w.tag, "RIGHT", w.frame, "RIGHT", 0, 0)
      w.frame:Show()
    else
      w.frame:Hide()
    end
  end
  -- The drops' values in shared coin columns.
  ns.UI.Coins.align(cells)

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

-- Anchors the texts that follow an amount, keeping the overhang of an
-- outlined text free (Theme.sizes.textOverhang): the total right of the rate,
-- each drop's amount left of its tag.
local function placeTexts()
  local S = ns.Theme.sizes
  local total, area = Compact.total, Compact.area
  total:ClearAllPoints()
  total:SetPoint("TOPRIGHT", area, "TOPRIGHT", -S.textOverhang, -3)
  total:SetPoint("LEFT", Compact.perHour, "RIGHT", S.rowNameGap + S.textOverhang, 0)
  for _, w in ipairs(Compact.drops or {}) do
    w.amount:ClearAllPoints()
    w.amount:SetPoint("RIGHT", w.tag, "LEFT", -ns.UI.Rows.labelGap(), 0)
  end
end

-- Font outline or sizes changed: new gaps, and the texts measured again in
-- the new font (a FontString given the same text may keep its old width).
function part:Relayout()
  placeTexts()
  Compact.perHour:SetText("")
  Compact.total:SetText("")
  for _, w in ipairs(Compact.drops) do
    w.name:SetText("")
    ns.UI.Coins.clear(w.amount)
  end
end

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
  if total.SetWordWrap then total:SetWordWrap(false) end
  Compact.perHour, Compact.total = perHour, total

  -- Hovering the rate and total shows the breakdown; it is still a drag handle.
  local hover = CreateFrame("Frame", nil, area)
  hover:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
  hover:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, 0)
  hover:SetHeight(26)
  hover:EnableMouse(true)
  hover:RegisterForDrag("LeftButton")
  hover:SetScript("OnDragStart", function() ns.UI.Window.beginDrag() end)
  hover:SetScript("OnDragStop", function() ns.UI.Window.endDrag() end)
  hover:SetScript("OnEnter", function(self)
    if Compact.view then W.showTextTooltip(self, Compact.hint(Compact.view), "ANCHOR_BOTTOM") end
  end)
  hover:SetScript("OnLeave", W.hideTooltip)
  Compact.hover = hover

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
    local tag = ns.UI.Rows.sourceTag(f)
    tag:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    tag:Hide()
    local amount = ns.UI.Coins.new(f, T.fonts.rowSmall, T.colors.ink)
    local name = W.text(f, T.fonts.rowSmall, T.colors.ink, "LEFT")
    name:SetPoint("LEFT", f, "LEFT", 0, 0)
    name:SetPoint("RIGHT", amount, "LEFT", -S.rowNameGap, 0)
    if name.SetWordWrap then name:SetWordWrap(false) end
    f:Hide()
    Compact.drops[i] = { frame = f, name = name, amount = amount, tag = tag }
  end
  placeTexts()

  -- Daily farm line at the bottom: same text and clicks as the strip.
  local farm = CreateFrame("Button", nil, area)
  farm:SetHeight(S.compactRowHeight)
  farm:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", 0, 0)
  farm:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, 0)
  if ns.UI.DailyFarm then ns.UI.DailyFarm.wire(farm) end
  local farmText = W.text(farm, T.fonts.small, T.colors.dailyFarm, "LEFT")
  farmText:SetPoint("LEFT", farm, "LEFT", 0, 0)
  farmText:SetPoint("RIGHT", farm, "RIGHT", 0, 0)
  if farmText.SetWordWrap then farmText:SetWordWrap(false) end
  farm:Hide()
  Compact.farm, Compact.farmText = farm, farmText

  if ns.UI.Ledger then ns.UI.Ledger.register(part) end
  return Compact
end
