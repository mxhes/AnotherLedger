local ADDON, ns = ...

local L = ns.L

ns.UI = ns.UI or {}

-- Daily farm strip: one header row between the filters and the tabs naming
-- the saved place with the best gold per hour (view.dailyFarm, View.dailyFarm).
-- Hidden without a pick. Click: waypoint to the farm spot (DailyFarm.click).
-- label and hint are pure; attach and Update touch the client.
local DailyFarm = {}
ns.UI.DailyFarm = DailyFarm

local L_DAILY_FARM = L["Daily: "]
local L_PER_HOUR = L["/h"]
local L_SLOW = L["slow selling"]
local L_TIME = L["Time: "]
local L_VALUE = L["Value: "]
local L_GOLD_PER_HOUR = L["Gold per hour: "]
local L_ALSO_GOOD = L["Also good:"]
local L_SELLS_SLOWLY = L["Sells slowly: "]
local L_CLICK = L["Click to open it in Zones"]
local L_CLICK_WAYPOINT = L["Click: waypoint"]
local L_SHIFT_CLICK = L["Shift-click: open it in Zones"]
local L_RIGHT_CLICK = L["Right-click: copy the /way line"]
local L_WAYPOINT_SET = L["Waypoint set: "]
local L_NO_WAYPOINT = L["No waypoint could be set."]
local L_WAY_TITLE = L["Waypoint (/way)"]

DailyFarm.shown = false

-- "Subzone (Zone)", or the zone alone when the place is the zone itself.
function DailyFarm.placeName(p) return ns.Waypoint.name(p) end

local function rate(p)
  -- Whole gold keeps the strip short in a narrow window; no "~" (it sits
  -- raised in the game font). The hover text has the exact rate.
  return ns.Money.format(ns.Money.roundRate(p.perHour)) .. L_PER_HOUR
end

function DailyFarm.label(farm)
  local best = farm.best
  -- Rate first: a narrow window cuts the place name, never the gold per hour.
  local text = L_DAILY_FARM .. rate(best) .. "  " .. DailyFarm.placeName(best)
  if farm.slow then
    text = text .. "  " .. ns.Money.colorCode(ns.Theme.colors.marketBad) .. L_SLOW .. "|r"
  end
  return text
end

-- The strip's tooltip (ns.Tooltip): the place as title, its time, value and
-- exact gold per hour, the runner-ups, the slow sellers and the clicks.
function DailyFarm.hint(farm)
  local Tip = ns.Tooltip
  local best = farm.best
  local tip = Tip.new(DailyFarm.placeName(best))
  Tip.pair(tip, L_TIME, ns.History.duration(best.time))
  Tip.money(tip, L_VALUE, best.value)
  Tip.rate(tip, L_GOLD_PER_HOUR, best.perHour)
  if type(farm.runnersUp) == "table" and #farm.runnersUp > 0 then
    Tip.section(tip, L_ALSO_GOOD)
    for _, p in ipairs(farm.runnersUp) do
      Tip.rate(tip, "  " .. DailyFarm.placeName(p), p.perHour, true)
    end
  end
  if farm.slow and type(farm.slow.names) == "table" then
    Tip.warn(tip, L_SELLS_SLOWLY .. table.concat(farm.slow.names, ", "))
  end
  if best.pos then
    Tip.hint(tip, L_CLICK_WAYPOINT)
    Tip.hint(tip, L_SHIFT_CLICK)
    Tip.hint(tip, L_RIGHT_CLICK)
  else
    Tip.hint(tip, L_CLICK)
  end
  return tip
end

-- Click on the strip: left sets a waypoint to the farm spot (Zones when the
-- place has none), shift-left opens Zones, right shows the /way line in the
-- copy box (addons cannot write the clipboard).
function DailyFarm.click(which, shift)
  local farm = DailyFarm.farm
  if not farm then return end
  local best = farm.best
  if which == "RightButton" then
    local text = ns.Waypoint.text(best)
    if text and ns.UI.Export then ns.UI.Export.show(text, L_WAY_TITLE) end
    return
  end
  if shift or not best.pos then
    ns.UI.Ledger.showFarm(best.zone, best.sub)
    return
  end
  if ns.Waypoint.set(_G, best) then
    ns.Util.say(L_WAYPOINT_SET .. DailyFarm.placeName(best))
  else
    ns.Util.say(L_NO_WAYPOINT)
  end
end

-- ---------------------------------------------------------------------------
-- Widgets

local part = {}

function part:Update(view)
  local farm = view and view.dailyFarm
  local shown = farm ~= nil
  DailyFarm.shown = shown
  DailyFarm.farm = farm
  local window = ns.UI.Window
  if window and window.setFarmRow then window.setFarmRow(shown) end
  if shown then DailyFarm.text:SetText(DailyFarm.label(farm)) end
end

-- Attaches to the header's Daily farm row: a full-width button with the map icon
-- and the label; hover shows the hint and a highlight, clicks go to
-- DailyFarm.click, dragging moves the window like the rest of the header. The text
-- uses the header font (not the list font, which follows List text size).
function DailyFarm.attach(row)
  local T, W = ns.Theme, ns.UI.Widgets
  local button = CreateFrame("Button", nil, row)
  button:SetAllPoints(row)
  button:SetHighlightTexture(T.textures.buttonHighlight, "ADD")
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(T.sizes.dailyFarmIcon, T.sizes.dailyFarmIcon)
  icon:SetPoint("LEFT", button, "LEFT", 0, 0)
  icon:SetTexture(T.textures.dailyFarm)
  local fc = T.colors.dailyFarm
  icon:SetVertexColor(fc[1], fc[2], fc[3], fc[4] or 1)
  local text = W.text(button, T.fonts.title, T.colors.dailyFarm, "LEFT")
  text:SetPoint("LEFT", icon, "RIGHT", 4, 0)
  text:SetPoint("RIGHT", button, "RIGHT", 0, 0)
  DailyFarm.button, DailyFarm.text = button, text
  DailyFarm.wire(button)

  ns.UI.Ledger.register(part)
  return button
end

-- The clicks, hover text and window drag of a Daily farm button (the strip
-- and the compact line behave the same).
function DailyFarm.wire(button)
  local W = ns.UI.Widgets
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetScript("OnDragStart", function() ns.UI.Window.beginDrag() end)
  button:SetScript("OnDragStop", function() ns.UI.Window.endDrag() end)
  button:SetScript("OnClick", function(_, which)
    DailyFarm.click(which, type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and true or false)
  end)
  button:SetScript("OnEnter", function(self)
    if DailyFarm.farm then W.showTextTooltip(self, DailyFarm.hint(DailyFarm.farm), "ANCHOR_BOTTOMLEFT") end
  end)
  button:SetScript("OnLeave", W.hideTooltip)
end
