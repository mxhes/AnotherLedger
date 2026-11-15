local ADDON, ns = ...

ns.UI = ns.UI or {}

-- LibDataBroker data source ("LootPrice": the session's best value plus raw
-- gold and its rate, for Titan Panel, ElvUI, ChocolateBar, ...) and, with
-- LibDBIcon, the minimap button through LibDBIcon (works with minimap button
-- collectors). Without the libraries (not packaged, no other addon loads them)
-- nothing happens here and UI/Minimap.lua shows its own button.
-- Client-only; every WoW global is touched inside functions only.
local Broker = {}
ns.UI.Broker = Broker

local NAME = "LootPrice"
local ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local UPDATE_SECONDS = 15

local L = ns.L
local L_LEFT = L["Left click: show / hide the window"]
local L_RIGHT = L["Right click: options"]
local L_DRAG = L["Drag: move the button"]
local L_SESSION = L["Session"]
local L_BEST = L["Items (best value)"]
local L_GOLD = L["Raw gold"]
local L_TOTAL = L["Total"]
local L_PER_HOUR = L["/h"]

-- Pure. Session numbers for the broker text and tooltip: { best, gold, total,
-- perHour (total per hour or nil), elapsed }. `lookup(itemID, link)` prices an
-- item. `includeGold` false (option "Raw gold in Total" off): the total is the
-- items only.
function Broker.summary(session, lookup, now, includeGold)
  local out = { best = 0, gold = 0, total = 0, perHour = nil, elapsed = 0 }
  if type(session) ~= "table" then return out end
  local ignored = ns.Core and ns.Core.ignoredItems and ns.Core.ignoredItems() or nil
  local view = ns.View.build(session, { now = now, lookup = lookup, showCurrencies = false, ignored = ignored })
  out.best = view.totals.best or 0
  out.gold = view.gold.total or 0
  out.total = out.best + (includeGold == false and 0 or out.gold)
  out.elapsed = ns.Session.elapsed(session, now)
  if out.elapsed >= ns.View.MIN_RATE_SECONDS then out.perHour = out.total * 3600 / out.elapsed end
  return out
end

-- Pure. The broker text: "12g 3s (4g/h)".
function Broker.text(summary, formatMoney)
  formatMoney = formatMoney or ns.Money.format
  local text = formatMoney(summary.total)
  if summary.perHour then text = text .. " (" .. formatMoney(summary.perHour) .. L_PER_HOUR .. ")" end
  return text
end

local function libStub(name)
  local stub = _G.LibStub
  if stub == nil then return nil end
  local ok, lib = pcall(stub, name, true)
  return ok and lib or nil
end

local function current()
  local includeGold = ns.Util.setting("includeGold", true)
  return Broker.summary(ns.session, ns.Core.lookupPrice, time(), includeGold)
end

function Broker.update()
  local object = Broker.object
  if not object or not ns.session then return end
  local ok, s = pcall(current)
  if ok then object.text = Broker.text(s, ns.Money.formatColored) end
end

local function onClick(_, button)
  if button == "RightButton" then
    if ns.UI.OptionsPanel then ns.UI.OptionsPanel.toggle() end
  elseif ns.UI.Window then
    ns.UI.Window.toggle()
  end
end

local function onTooltipShow(tooltip)
  local fm = ns.Money.formatColored
  tooltip:AddLine(NAME)
  local ok, s = pcall(current)
  if ok then
    tooltip:AddDoubleLine(L_SESSION, ns.UI.Header and ns.UI.Header.formatElapsed(s.elapsed) or "", 1, 1, 1, 1, 1, 1)
    tooltip:AddDoubleLine(L_BEST, fm(s.best), 1, 1, 1, 1, 1, 1)
    tooltip:AddDoubleLine(L_GOLD, fm(s.gold), 1, 1, 1, 1, 1, 1)
    tooltip:AddDoubleLine(L_TOTAL, Broker.text(s, fm), 1, 1, 1, 1, 1, 1)
  end
  tooltip:AddLine(" ")
  tooltip:AddLine(L_LEFT, 0.7, 0.7, 0.7)
  tooltip:AddLine(L_RIGHT, 0.7, 0.7, 0.7)
  if Broker.icon then tooltip:AddLine(L_DRAG, 0.7, 0.7, 0.7) end
end

-- Creates the data object and the LibDBIcon button (once, at login, before the
-- options are applied). Returns whether LibDBIcon now owns the minimap button.
function Broker.init()
  if Broker.object or not ns.db then return Broker.icon ~= nil end
  local ldb = libStub("LibDataBroker-1.1")
  if not ldb then return false end
  Broker.object = ldb:NewDataObject(NAME, {
    type = "data source", label = NAME, text = NAME, icon = ICON,
    OnClick = onClick, OnTooltipShow = onTooltipShow,
  })
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(UPDATE_SECONDS, Broker.update) end

  local icon = libStub("LibDBIcon-1.0")
  if icon and Broker.object then
    local s = ns.db.settings
    local saved = ns.db.minimapIcon
    saved.hide = not s.minimapButton
    if not ns.Util.isNumber(saved.minimapPos) then saved.minimapPos = s.minimapAngle end
    icon:Register(NAME, Broker.object, saved)
    Broker.icon = icon
  end
  Broker.update()
  return Broker.icon ~= nil
end

-- Minimap button through LibDBIcon (UI/Minimap.lua asks first).
function Broker.setIconShown(shown)
  if not Broker.icon then return false end
  ns.db.minimapIcon.hide = not shown
  if shown then Broker.icon:Show(NAME) else Broker.icon:Hide(NAME) end
  return true
end

function Broker.resetIcon()
  if not Broker.icon then return false end
  ns.db.minimapIcon.minimapPos = ns.DB.defaults.settings.minimapAngle
  Broker.icon:Refresh(NAME, ns.db.minimapIcon)
  return true
end
