local ADDON, ns = ...

local L = ns.L

ns.UI = ns.UI or {}

-- Daily farm strip: one header row between the filters and the tabs naming
-- the saved place with the best gold per hour (view.dailyFarm, View.dailyFarm).
-- Hidden without a pick. Click: History -> Zones at that place.
-- label and hint are pure; attach and Update touch the client.
local DailyFarm = {}
ns.UI.DailyFarm = DailyFarm

local L_DAILY_FARM = L["Daily farm: "]
local L_PER_HOUR = L["/h"]
local L_SLOW = L["slow selling"]
local L_ZONE = L["Zone: "]
local L_SUBZONE = L["Subzone: "]
local L_TIME = L["Time: "]
local L_VALUE = L["Value: "]
local L_GOLD_PER_HOUR = L["Gold per hour: "]
local L_ALSO_GOOD = L["Also good:"]
local L_SELLS_SLOWLY = L["Sells slowly: "]
local L_CLICK = L["Click to open it in Zones"]

DailyFarm.shown = false

-- Rates of 1 gold and more are rounded to whole gold so the strip stays short
-- in a narrow window (the hover text has the full amounts).
local GOLD = 10000
local function rounded(copper)
  if copper >= GOLD then return math.floor(copper / GOLD + 0.5) * GOLD end
  return copper
end

-- "Subzone (Zone)", or the zone alone when the place is the zone itself.
function DailyFarm.placeName(p)
  if p.sub == nil or p.sub == p.zone then return p.zone end
  return p.sub .. " (" .. p.zone .. ")"
end

local function rate(p)
  return "~" .. ns.Money.format(rounded(p.perHour)) .. L_PER_HOUR
end

function DailyFarm.label(farm)
  local best = farm.best
  local text = L_DAILY_FARM .. DailyFarm.placeName(best) .. "  " .. rate(best)
  if farm.slow then
    text = text .. "  " .. ns.Money.colorCode(ns.Theme.colors.marketBad) .. L_SLOW .. "|r"
  end
  return text
end

function DailyFarm.hint(farm)
  local best = farm.best
  local lines = { L_ZONE .. best.zone }
  if best.sub and best.sub ~= best.zone then lines[#lines + 1] = L_SUBZONE .. best.sub end
  lines[#lines + 1] = L_TIME .. ns.History.duration(best.time)
  lines[#lines + 1] = L_VALUE .. ns.Money.format(best.value)
  lines[#lines + 1] = L_GOLD_PER_HOUR .. ns.Money.format(math.floor(best.perHour + 0.5))
  if type(farm.runnersUp) == "table" and #farm.runnersUp > 0 then
    lines[#lines + 1] = L_ALSO_GOOD
    for _, p in ipairs(farm.runnersUp) do
      lines[#lines + 1] = "  " .. DailyFarm.placeName(p) .. "  " .. rate(p)
    end
  end
  if farm.slow and type(farm.slow.names) == "table" then
    lines[#lines + 1] = L_SELLS_SLOWLY .. table.concat(farm.slow.names, ", ")
  end
  lines[#lines + 1] = L_CLICK
  return table.concat(lines, "\n")
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
-- and the label; hover shows the hint and a highlight, click opens the place
-- in Zones, dragging moves the window like the rest of the header. The text
-- uses the header font (not the list font, which follows List text size).
function DailyFarm.attach(row)
  local T, W = ns.Theme, ns.UI.Widgets
  local button = CreateFrame("Button", nil, row)
  button:SetAllPoints(row)
  button:SetHighlightTexture(T.textures.buttonHighlight, "ADD")
  button:RegisterForDrag("LeftButton")
  button:SetScript("OnDragStart", function() ns.UI.Window.beginDrag() end)
  button:SetScript("OnDragStop", function() ns.UI.Window.endDrag() end)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(T.sizes.dailyFarmIcon, T.sizes.dailyFarmIcon)
  icon:SetPoint("LEFT", button, "LEFT", 0, 0)
  icon:SetTexture(T.textures.dailyFarm)
  local text = W.text(button, T.fonts.title, T.colors.dailyFarm, "LEFT")
  text:SetPoint("LEFT", icon, "RIGHT", 4, 0)
  text:SetPoint("RIGHT", button, "RIGHT", 0, 0)
  DailyFarm.button, DailyFarm.text = button, text

  button:SetScript("OnClick", function()
    local farm = DailyFarm.farm
    if farm then ns.UI.Ledger.showFarm(farm.best.zone, farm.best.sub) end
  end)
  button:SetScript("OnEnter", function(self)
    if DailyFarm.farm then W.showTextTooltip(self, DailyFarm.hint(DailyFarm.farm), "ANCHOR_BOTTOMLEFT") end
  end)
  button:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)

  ns.UI.Ledger.register(part)
  return button
end
