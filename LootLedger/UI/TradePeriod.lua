local ADDON, ns = ...

ns.UI = ns.UI or {}

-- The period switch of the Trade tab's Items: a button at the right end of
-- the sub-tab row (7 days, 30 days, All), shown only while Items is shown.
-- The choice is saved in db.tradePeriod (account-wide, like the Trade data).
local TradePeriod = {}
ns.UI.TradePeriod = TradePeriod

local L = ns.L
local LABELS = { ["7"] = L["7 days"], ["30"] = L["30 days"], all = L["All"] }
TradePeriod.DEFAULT = "30"

-- Pure. The saved period, a known one or the default.
function TradePeriod.current(db)
  local p = type(db) == "table" and db.tradePeriod or nil
  return LABELS[p] and p or TradePeriod.DEFAULT
end

-- Pure. The button text of a period.
function TradePeriod.label(period)
  return LABELS[period] or LABELS[TradePeriod.DEFAULT]
end

function TradePeriod.set(period)
  if not (LABELS[period] and type(ns.db) == "table") then return end
  ns.db.tradePeriod = period
  if ns.UI.Ledger and ns.UI.Ledger.refresh then ns.UI.Ledger.refresh() end
end

local function openMenu(button)
  local entries = {}
  for _, p in ipairs(ns.View.TRADE_PERIODS) do
    entries[#entries + 1] = { text = LABELS[p], onClick = function() TradePeriod.set(p) end }
  end
  ns.UI.Widgets.openMenu(button, entries)
end

local part = {}
function part:Update(view)
  local b = TradePeriod.button
  if not b then return end
  local shown = type(view) == "table" and view.kind == "tradeItems"
  b:SetShown(shown)
  if shown then b:SetText(TradePeriod.label(TradePeriod.current(ns.db))) end
end

-- Builds the button on `row` (the window's sub-tab row) and registers it.
function TradePeriod.attach(row)
  if TradePeriod.button or not row then return end
  local T = ns.Theme
  local b = ns.UI.Widgets.button(row, TradePeriod.label(TradePeriod.current(ns.db)), T.sizes.tradePeriodWidth)
  b:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  b:SetScript("OnClick", function(self) openMenu(self) end)
  b:Hide()
  TradePeriod.button = b
  ns.UI.Ledger.register(part)
end
