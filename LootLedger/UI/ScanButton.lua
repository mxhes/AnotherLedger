local ADDON, ns = ...

local L = ns.L
local L_NAME = L["LootLedger scan"]
local L_READING = L["Reading %d%%"]

ns.UI = ns.UI or {}

-- The LootLedger scan button on the auction house window: made on the first
-- AUCTION_HOUSE_SHOW while scanning is available (Core.scanAvailable), shows
-- the progress of a running scan or the game's wait, and starts a scan on a
-- click (Core.scanCommand). Core calls show / hide with the auction house.
local ScanButton = { frame = false }
ns.UI.ScanButton = ScanButton

local ticker = false

-- Pure: the button text of a Core.scanState().
function ScanButton.text(state)
  if state.running then return L_READING:format(math.floor((state.fraction or 0) * 100)) end
  local left = state.waitLeft or 0
  if left > 0 then
    local s = math.ceil(left)
    return L_NAME .. " " .. math.floor(s / 60) .. ":" .. string.format("%02d", s % 60)
  end
  return L_NAME
end

function ScanButton.update()
  local b = ScanButton.frame
  if not b then return end
  b:SetText(ScanButton.text(ns.Core.scanState()))
end

local function stopTicker()
  if ticker and ticker.Cancel then ticker:Cancel() end
  ticker = false
end

local function make()
  -- UNVERIFIED (check in client): AuctionHouseFrame is the retail auction
  -- house window, and the bottom right corner has room for the button.
  local parent = _G.AuctionHouseFrame
  if type(parent) ~= "table" then return false end
  local T = ns.Theme
  local b = ns.UI.Widgets.button(parent, L_NAME, T.sizes.scanButtonWidth)
  b:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", T.sizes.scanButtonX, T.sizes.scanButtonY)
  b:SetScript("OnClick", function()
    ns.Core.scanCommand()
    ScanButton.update()
  end)
  return b
end

function ScanButton.show()
  if not ns.Core.scanAvailable(_G) then
    ScanButton.hide()
    return
  end
  if not ScanButton.frame then
    ScanButton.frame = make()
    if not ScanButton.frame then return end
    ns.Core.onScanChange = ScanButton.update
  end
  ScanButton.frame:Show()
  ScanButton.update()
  -- The wait counts down once a second while the auction house is open.
  if not ticker and C_Timer and type(C_Timer.NewTicker) == "function" then
    ticker = C_Timer.NewTicker(1, ScanButton.update)
  end
end

function ScanButton.hide()
  stopTicker()
  if ScanButton.frame then ScanButton.frame:Hide() end
end
