local ADDON, ns = ...

local L = ns.L
local L_NAME = L["AnotherLedger scan"]
local L_READING = L["Reading %d%%"]

ns.UI = ns.UI or {}

-- The AnotherLedger scan button on the auction house window: made on the first
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
  -- AuctionHouseFrame is the retail auction house window (load on demand: Blizzard_AuctionHouseUI). The button hangs
  -- just below its bottom right corner, where nothing of the game's sits
  -- (its tabs hang below the bottom left), and is drawn above its panels.
  local parent = _G.AuctionHouseFrame
  if type(parent) ~= "table" then return false end
  local T = ns.Theme
  local b = ns.UI.Widgets.button(parent, L_NAME, T.sizes.scanButtonWidth)
  ns.UI.Widgets.fitButton(b, { L_NAME, string.format(L_READING, 100) }, T.sizes.scanButtonWidth)
  b:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", T.sizes.scanButtonX, T.sizes.scanButtonY)
  b:SetFrameLevel(parent:GetFrameLevel() + T.sizes.scanButtonLevel)
  b:SetScript("OnClick", function()
    ns.Core.scanCommand()
    ScanButton.update()
  end)
  return b
end

local retrying = false

function ScanButton.show()
  if not ns.Core.scanAvailable(_G) then
    ScanButton.hide()
    return
  end
  if not ScanButton.frame then
    ScanButton.frame = make()
    if not ScanButton.frame then
      -- The game's auction house window may not exist yet when its open
      -- event comes: try again on the next frame (and Core calls show again
      -- when Blizzard_AuctionHouseUI loads).
      if not retrying and C_Timer and type(C_Timer.After) == "function" then
        retrying = true
        C_Timer.After(0, function()
          retrying = false
          if ns.Core.auctionHouseOpen() then ScanButton.show() end
        end)
      end
      return
    end
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
