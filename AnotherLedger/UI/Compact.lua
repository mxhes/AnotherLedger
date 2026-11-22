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
local L_RECENT = L["Last 15 min: "]
local L_RECENT_TIP = L["Last 15 minutes: "]
local DASH = "\226\128\148" -- em dash (UTF-8)
local MAX_DROPS = 4

-- Pure. Texts of one drop line: name, quantity, amount, source (nil without).
-- An unpriced drop shows "?" like its list row.
function Compact.dropText(row, formatMoney)
  local t = ns.UI.Rows.rowText(row, formatMoney)
  return { name = t.name, qty = t.qty, amount = t.amount, copper = t.copper, source = t.source,
    sourceText = t.sourceText, hideTag = t.hideTag }
end

-- Pure. The name with its quantity ("x47") in the quiet color `hint` (a
-- color code), so the names stand out.
function Compact.nameText(t, hint)
  if t.qty == nil or t.qty == "" then return t.name end
  if not hint then return t.name .. " " .. t.qty end
  return t.name .. " " .. hint .. t.qty .. "|r"
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

-- Pure. The big number: gold per hour, or an em dash under a minute and
-- while nothing has earned money yet (a bare "0/h" reads like a broken count).
function Compact.rateText(perHour, formatMoney)
  if perHour == nil or perHour <= 0 then return DASH .. L_PER_HOUR end
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

-- Pure. The title over the drops: "Last drops", else why the list is empty;
-- nil (no title) while the clock runs and the option "Compact: last drops" is 0.
function Compact.titleText(c)
  if type(c.drops) == "table" and #c.drops > 0 then return L_LAST_DROPS end
  if not c.running then return L_PAUSED end
  if c.dropLimit == 0 then return nil end
  return L_NO_DROPS
end

-- Pure. The text right of the drops title: the gold per hour of the last 15
-- minutes ("Last 15 min: 120g/h"), nil before the session is that old.
function Compact.recentText(c, formatMoney)
  if not c.recent then return nil end
  return L_RECENT .. (formatMoney or ns.Money.format)(ns.Money.roundRate(c.recent)) .. L_PER_HOUR
end

-- Pure. How much of the session goal is reached (0 to 1): the gold goal,
-- else the minutes goal; nil without a goal.
function Compact.goalFraction(c)
  return ns.View.goalFraction(c.goal, c.elapsed, c.goalSeconds)
end

-- Pure. The hover breakdown of the rate and total (ns.Tooltip): the clock,
-- the items, the raw gold, the total, its rate and the last 15 minutes' rate,
-- the best find and the goal.
function Compact.hint(c)
  local Tip = ns.Tooltip
  local tip = Tip.new(L_SESSION)
  Tip.pair(tip, L_TIME, ns.History.duration(c.elapsed or 0))
  Tip.money(tip, L_ITEMS, c.items or 0)
  if (c.gold or 0) > 0 then Tip.money(tip, L_RAW_GOLD, c.gold) end
  Tip.money(tip, L_TOTAL, c.total or 0)
  if c.perHour then
    Tip.rate(tip, L_GOLD_PER_HOUR, c.perHour)
    if c.recent then Tip.rate(tip, L_RECENT_TIP, c.recent) end
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
  local S = T.sizes
  Compact.perHour:SetText(Compact.rateText(c.perHour))
  Compact.total:SetText(Compact.totalText(c, nil, ns.Money.colorCode(T.colors.hint)))
  Compact.view = c
  -- A shown breakdown follows the numbers.
  local W = ns.UI.Widgets
  if Compact.hover and W.tooltipOwnedBy(Compact.hover) then W.showTextTooltip(Compact.hover, Compact.hint(c)) end

  local drops = c.drops or {}
  local title = Compact.titleText(c)
  Compact.dropsTitle:SetText(title or "")
  Compact.dropsTitle:SetShown(title ~= nil)
  Compact.recent:SetText(Compact.recentText(c) or "")
  -- The goal bar: its share of the area's width (a resize catches up on the
  -- next redraw, at the latest the next clock tick).
  local frac = Compact.goalFraction(c)
  local width = Compact.area:GetWidth() or 0
  if frac and frac > 0 and width > 0 then
    Compact.goalBar:SetWidth(math.max(1, math.floor(width * frac + 0.5)))
    Compact.goalBar:Show()
  else
    Compact.goalBar:Hide()
  end
  local cells = {}
  local hint = ns.Money.colorCode(T.colors.hint)
  local icons = ns.Util.setting("compactIcons", false) == true
  for i = 1, MAX_DROPS do
    local w = Compact.drops[i]
    local row = drops[i]
    if row then
      local t = Compact.dropText(row)
      local r, g, b = T.qualityColor(row.quality)
      w.name:SetText(Compact.nameText(t, hint))
      ns.UI.Widgets.setTextRGB(w.name, r, g, b, 1)
      -- Option "compactIcons": the item icon before the name.
      if icons then w.icon:SetTexture(ns.UI.Rows.iconOf(row)) end
      w.icon:SetShown(icons)
      w.name:ClearAllPoints()
      w.name:SetPoint("LEFT", icons and w.icon or w.frame, icons and "RIGHT" or "LEFT", icons and S.rowIconGap or 0, 0)
      w.name:SetPoint("RIGHT", w.amount, "LEFT", -S.rowNameGap, 0)
      ns.UI.Coins.set(w.amount, t.copper, t.amount)
      cells[#cells + 1] = w.amount
      -- The same framed tag as the list rows, lined up with the widest one.
      ns.UI.Rows.setSourceTag(w.tag, t.source, ns.UI.Rows.widestSource)
      w.tag:SetAlpha(t.hideTag and 0 or 1)
      -- On whole screen pixels, so its frame is equally thin on every side.
      ns.UI.Widgets.snapPoint(w.tag, "RIGHT", w.frame, "RIGHT", 0, 0)
      -- Hover: the item tooltip and its values, as on the full window's rows.
      local f = w.frame
      f.row = row
      f.tooltipLink = ns.UI.Rows.tooltipLink(row)
      f.tooltipLines = ns.UI.Rows.tooltipLines(row)
      if ns.UI.Widgets.tooltipOwnedBy(f) then ns.UI.Rows.showTooltip(f) end
      f:Show()
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

  local line = W.rule(area, T.colors.divider)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -28)
  line:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -28)

  -- Session goal progress over the divider, from the left.
  local goalBar = W.line(area, T.colors.gold, "OVERLAY")
  goalBar:SetHeight(S.compactGoalBarHeight)
  goalBar:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", 0, 0)
  goalBar:Hide()
  Compact.goalBar = goalBar

  local title = W.text(area, T.fonts.small, T.colors.hint, "LEFT")
  title:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -32)
  title:SetText(L_LAST_DROPS)
  Compact.dropsTitle = title

  -- The last 15 minutes' rate, right of the title.
  local recent = W.text(area, T.fonts.small, T.colors.hint, "RIGHT")
  recent:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -32)
  if recent.SetWordWrap then recent:SetWordWrap(false) end
  Compact.recent = recent
  -- A long title (Paused: ...) ends before the rate instead of under it.
  title:SetPoint("RIGHT", recent, "LEFT", -S.rowNameGap, 0)
  if title.SetWordWrap then title:SetWordWrap(false) end

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
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(S.compactRowHeight - 2, S.compactRowHeight - 2)
    icon:SetPoint("LEFT", f, "LEFT", 0, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:Hide()
    local name = W.text(f, T.fonts.rowSmall, T.colors.ink, "LEFT")
    name:SetPoint("LEFT", f, "LEFT", 0, 0)
    name:SetPoint("RIGHT", amount, "LEFT", -S.rowNameGap, 0)
    if name.SetWordWrap then name:SetWordWrap(false) end
    -- Hover: the item tooltip (Update sets its link and values); Shift /
    -- Ctrl-click as on the list rows; still a drag handle.
    f.row, f.tooltipLink, f.tooltipLines, f.tooltipText = false, false, false, false
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() ns.UI.Window.beginDrag() end)
    f:SetScript("OnDragStop", function() ns.UI.Window.endDrag() end)
    f:SetScript("OnEnter", function(self) if self.tooltipLink then ns.UI.Rows.showTooltip(self) end end)
    f:SetScript("OnLeave", W.hideTooltip)
    f:SetScript("OnMouseUp", function(self)
      if self.row then ns.UI.Rows.modifiedClick(self.row.link) end
    end)
    f:Hide()
    Compact.drops[i] = { frame = f, name = name, amount = amount, tag = tag, icon = icon }
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
