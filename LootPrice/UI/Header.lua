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
local L_OPTIONS = "Options"
local L_RESET_CONFIRM = "Reset the session? All logged loot and the timer will be cleared."
local L_YES = "Reset"
local L_NO = "Cancel"

-- Compact button widths live in Theme.widths.header (width budget there).
local function widths() return ns.Theme.widths.header end

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

-- Attaches to header row 1; `handlers` = { start, stop, reset, hide, options }.
function Header.attach(row, handlers)
  if Header.instance then return Header.instance end
  local T = ns.Theme
  local W = ns.UI.Widgets
  local makeButton = W.button
  Header.handlers = handlers
  local gap = T.sizes.buttonGap

  local header = { row = row }

  -- Buttons are laid out right to left: Hide, Options, Reset, Stop, Start.
  local hide = makeButton(row, L_HIDE, widths().hide)
  hide:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  hide:SetScript("OnClick", function()
    -- Window.hide persists the hidden flag; never frame:Hide() directly.
    if handlers.hide then handlers.hide() end
  end)

  -- Options (gear icon), left of the Hide button; opens the options panel.
  local options = CreateFrame("Button", nil, row)
  options:SetSize(widths().options, T.sizes.buttonHeight)
  options:SetPoint("RIGHT", hide, "LEFT", -gap, 0)
  options:SetNormalTexture(T.textures.optionsIcon)
  local normal = options:GetNormalTexture()
  if normal and normal.SetTexCoord then normal:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  options:SetHighlightTexture(T.textures.buttonHighlight, "ADD")
  options:SetScript("OnClick", function()
    if handlers.options then handlers.options() end
  end)
  options:SetScript("OnEnter", function(self)
    W.showTextTooltip(self, L_OPTIONS, "ANCHOR_BOTTOMRIGHT")
  end)
  options:SetScript("OnLeave", W.hideTooltip)

  local reset = makeButton(row, L_RESET, widths().reset)
  reset:SetPoint("RIGHT", options, "LEFT", -gap, 0)
  reset:SetScript("OnClick", function() Header.requestReset() end)

  local stop = makeButton(row, L_STOP, widths().stop)
  stop:SetPoint("RIGHT", reset, "LEFT", -gap, 0)
  stop:SetScript("OnClick", function()
    if handlers.stop then handlers.stop() end
  end)

  local start = makeButton(row, L_START, widths().start)
  start:SetPoint("RIGHT", stop, "LEFT", -gap, 0)
  start:SetScript("OnClick", function()
    if handlers.start then handlers.start() end
  end)

  local timer = W.text(row, T.fonts.number, T.colors.ink, "RIGHT")
  timer:SetWidth(T.sizes.timerWidth)
  timer:SetPoint("RIGHT", start, "LEFT", -gap * 3, 0)
  timer:SetText(Header.formatElapsed(0))

  header.timer, header.start, header.stop = timer, start, stop
  header.reset, header.hide, header.options = reset, hide, options

  -- The clock and the Start / Stop / Reset buttons belong to the session tab;
  -- the Hide button stays on every tab.
  function header:SetSessionControls(shown)
    self.timer:SetShown(shown)
    self.start:SetShown(shown)
    self.stop:SetShown(shown)
    self.reset:SetShown(shown)
  end

  function header:SetElapsed(seconds)
    self.timer:SetText(Header.formatElapsed(seconds))
  end

  -- The buttons only change when the running state does.
  function header:SetRunning(running)
    running = running and true or false
    if running == self.running then return end
    self.running = running
    local st = Header.buttonStates(running)
    self.start:SetEnabled(st.start)
    self.stop:SetEnabled(st.stop)
  end

  -- Ledger part: the clock is the same work on a full refresh and on a tick.
  local part = {}
  function part:Update(_, session, now)
    header:SetElapsed(ns.Session.elapsed(session, now))
    header:SetRunning(session.running)
  end
  part.Tick = part.Update
  if ns.UI.Ledger then ns.UI.Ledger.register(part) end

  Header.instance = header
  return header
end
