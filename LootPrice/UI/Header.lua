local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Header row 1 (right of the title): elapsed timer and the Start / Stop /
-- Reset / Hide buttons. Client-only widgets; every WoW global is touched
-- inside functions only. formatElapsed and buttonStates are pure.
local Header = {}
ns.UI.Header = Header

local L_START = "Start"
local L_STOP = "Stop"
local L_RESET = "Reset"
local L_HIDE = "X"
local L_RESET_CONFIRM = "Reset the session? All logged loot and the timer will be cleared."
local L_YES = "Reset"
local L_NO = "Cancel"

-- Compact button widths. Row 1 at the 320 px minimum is 296 px wide
-- (320 - 2 * (padding 8 + 4)): buttons 38 + 34 + 40 + 20 = 132 plus three
-- 2 px gaps = 138, timer 54, leaving ~104 px for the title (~95 px).
local WIDTHS = { start = 38, stop = 34, reset = 40, hide = 20 }

-- ---------------------------------------------------------------------------
-- Pure helpers

function Header.formatElapsed(seconds)
  if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 or seconds == math.huge then
    return "00:00:00"
  end
  local total = math.floor(seconds)
  local hours = math.floor(total / 3600)
  local minutes = math.floor((total % 3600) / 60)
  local secs = total % 60
  return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

function Header.buttonStates(running)
  local r = running and true or false
  return { start = not r, stop = r }
end

-- ---------------------------------------------------------------------------
-- Reset request (shared by the Reset button and /lp reset)

local function doReset()
  local handlers = Header.handlers
  if handlers and handlers.reset then
    handlers.reset()
  elseif ns.Core and ns.Core.resetSession then
    ns.Core.resetSession()
  end
end

function Header.requestReset()
  if not ns.session then return end
  if ns.Session.needsResetConfirm(ns.session) then
    if not StaticPopupDialogs["LOOTPRICE_RESET"] then
      StaticPopupDialogs["LOOTPRICE_RESET"] = {
        text = L_RESET_CONFIRM,
        button1 = L_YES,
        button2 = L_NO,
        OnAccept = doReset,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
      }
    end
    StaticPopup_Show("LOOTPRICE_RESET")
  else
    doReset()
  end
end

-- ---------------------------------------------------------------------------
-- Widgets

local function makeButton(parent, label, width)
  local T = ns.Theme
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, T.sizes.buttonHeight)
  b:SetText(label)
  local fs = b:GetFontString()
  if fs and fs.SetFontObject then fs:SetFontObject(T.fonts.button) end
  return b
end

-- Attaches to header row 1; `handlers` = { start, stop, reset, hide }.
function Header.attach(row, handlers)
  if Header.instance then return Header.instance end
  local T = ns.Theme
  Header.handlers = handlers
  local gap = T.sizes.buttonGap

  local header = { row = row }

  -- Buttons are laid out right to left: Hide, Reset, Stop, Start.
  local hide = makeButton(row, L_HIDE, WIDTHS.hide)
  hide:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  hide:SetScript("OnClick", function()
    -- Window.hide persists the hidden flag; never frame:Hide() directly.
    if handlers.hide then handlers.hide() end
  end)

  local reset = makeButton(row, L_RESET, WIDTHS.reset)
  reset:SetPoint("RIGHT", hide, "LEFT", -gap, 0)
  reset:SetScript("OnClick", function() Header.requestReset() end)

  local stop = makeButton(row, L_STOP, WIDTHS.stop)
  stop:SetPoint("RIGHT", reset, "LEFT", -gap, 0)
  stop:SetScript("OnClick", function()
    if handlers.stop then handlers.stop() end
  end)

  local start = makeButton(row, L_START, WIDTHS.start)
  start:SetPoint("RIGHT", stop, "LEFT", -gap, 0)
  start:SetScript("OnClick", function()
    if handlers.start then handlers.start() end
  end)

  local timer = row:CreateFontString(nil, "OVERLAY", T.fonts.number)
  timer:SetWidth(T.sizes.timerWidth)
  timer:SetJustifyH("RIGHT")
  timer:SetPoint("RIGHT", start, "LEFT", -gap * 3, 0)
  local ink = T.colors.ink
  timer:SetTextColor(ink[1], ink[2], ink[3], ink[4])
  timer:SetText(Header.formatElapsed(0))

  header.timer, header.start, header.stop = timer, start, stop
  header.reset, header.hide = reset, hide

  function header:SetElapsed(seconds)
    self.timer:SetText(Header.formatElapsed(seconds))
  end

  function header:SetRunning(running)
    local st = Header.buttonStates(running)
    self.start:SetEnabled(st.start)
    self.stop:SetEnabled(st.stop)
  end

  -- Ledger part: refreshed with every tick / loot event.
  local part = {}
  function part:Update(_, session, now)
    header:SetElapsed(ns.Session.elapsed(session, now))
    header:SetRunning(session.running)
  end
  if ns.UI.Ledger then ns.UI.Ledger.register(part) end

  Header.instance = header
  return header
end
