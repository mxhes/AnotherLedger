local ADDON, ns = ...

local L = ns.L

ns.UI = ns.UI or {}

-- Header row 1 (right of the title): elapsed timer and the Start / Stop /
-- Reset / Hide buttons. Client-only widgets; every WoW global is touched
-- inside functions only. formatElapsed and buttonStates are pure.
local Header = {}
ns.UI.Header = Header

local L_START = L["Start"]
local L_STOP = L["Stop"]
local L_RESET = L["Reset"]
local L_OPTIONS = L["Options"]
local L_TO_COMPACT = L["Compact window (or double-click the title)"]
local L_TO_FULL = L["Full window (or double-click the title)"]
local L_PAUSED = L["Paused"]
local L_RESTING = L["Resting"]
local L_TRAVELING = L["Traveling"]
local L_CLOCK_HINT = L["Click: start / stop the session"]
local L_RESET_CONFIRM = L["Reset the session? It is saved to History, then the loot and the clock start again from zero."]

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

-- The one Start / Stop button: its label and the handler a click calls.
function Header.toggleState(running)
  if running then return { label = L_STOP, action = "stop" } end
  return { label = L_START, action = "start" }
end

-- ---------------------------------------------------------------------------
-- Reset request (shared by the Reset button and /al reset)

-- With the option "Reset: ask for a note" the saved session's note box opens
-- (not for the automatic splits, which reset through Core directly).
local function doReset()
  local handlers = Header.handlers
  local entry
  if handlers and handlers.reset then
    entry = handlers.reset()
  elseif ns.Core and ns.Core.resetSession then
    entry = ns.Core.resetSession()
  end
  if type(entry) == "table" and ns.Util.setting("resetNote", false) == true
    and ns.UI.Ledger and ns.UI.Ledger.editNote then
    ns.UI.Ledger.editNote(entry)
  end
end

function Header.requestReset()
  if not ns.session then return end
  local value = ns.Core and ns.Core.sessionValue and ns.Core.sessionValue(ns.session) or 0
  if ns.Session.needsResetConfirm(ns.session, value) then
    ns.UI.Widgets.confirm(L_RESET_CONFIRM, L_RESET, doReset)
  else
    doReset()
  end
end

-- ---------------------------------------------------------------------------
-- Widgets

-- Attaches to header row 1; `handlers` = { start, stop, reset, hide, options }.
-- Pure. Width header row 1 needs (px): the title (`titleW`, the widest tab
-- title), room for the clock, Start / Stop (`toggleW`), Reset (`resetW`) and
-- the three icon buttons, with the gaps Header.attach puts between them.
function Header.rowNeed(titleW, toggleW, resetW)
  local T = ns.Theme
  local gap, w = T.sizes.buttonGap, widths()
  return (titleW or 0) + gap * 3 + T.sizes.timerWidth + gap * 3 + (toggleW or w.toggle) + gap
    + (resetW or w.reset) + gap + w.mode + gap + w.options + gap + w.hide
end

function Header.attach(row, handlers)
  if Header.instance then return Header.instance end
  local T = ns.Theme
  local W = ns.UI.Widgets
  local makeButton = W.button
  Header.handlers = handlers
  local gap = T.sizes.buttonGap

  local header = { row = row, mode = "full", sessionShown = true, running = nil }

  -- Buttons are laid out right to left: Close, Options, Reset, Start / Stop.
  local hide = W.iconButton(row, "close", widths().hide, function()
    -- Window.hide persists the hidden flag; never frame:Hide() directly.
    if handlers.hide then handlers.hide() end
  end)
  hide:SetPoint("RIGHT", row, "RIGHT", 0, 0)

  -- Options (gear icon), left of the Hide button; opens the options panel.
  local options = W.iconButton(row, "gear", widths().options, function()
    if handlers.options then handlers.options() end
  end)
  options:SetPoint("RIGHT", hide, "LEFT", -gap, 0)
  options.onEnter = function(self) W.showTextTooltip(self, L_OPTIONS, "ANCHOR_BOTTOMRIGHT") end
  options.onLeave = W.hideTooltip

  -- Mode button, left of the gear: switches compact / full in both layouts.
  local modeButton = W.iconButton(row, "compact", widths().mode, function()
    if ns.UI.Ledger and ns.UI.Ledger.toggleMode then ns.UI.Ledger.toggleMode() end
  end)
  modeButton:SetPoint("RIGHT", options, "LEFT", -gap, 0)
  modeButton.onEnter = function(self)
    W.showTextTooltip(self, header.mode == "compact" and L_TO_FULL or L_TO_COMPACT, "ANCHOR_BOTTOMRIGHT")
  end
  modeButton.onLeave = W.hideTooltip

  local reset = makeButton(row, L_RESET, widths().reset, { warn = true })
  W.fitButton(reset, { L_RESET }, widths().reset)
  reset:SetPoint("RIGHT", modeButton, "LEFT", -gap, 0)
  reset:SetScript("OnClick", function() Header.requestReset() end)

  -- One button: Start while stopped, Stop while running.
  local toggle = makeButton(row, L_START, widths().toggle)
  W.fitButton(toggle, { L_START, L_STOP }, widths().toggle)
  toggle:SetPoint("RIGHT", reset, "LEFT", -gap, 0)
  toggle:SetScript("OnClick", function()
    local fn = handlers[Header.toggleState(header.running).action]
    if fn then fn() end
  end)

  local timer = W.text(row, T.fonts.number, T.colors.ink, "RIGHT")
  timer:SetWidth(T.sizes.timerWidth)
  timer:SetPoint("RIGHT", toggle, "LEFT", -gap * 3, 0)
  timer:SetText(Header.formatElapsed(0))

  header.timer, header.toggle = timer, toggle
  header.reset, header.hide, header.options = reset, hide, options
  header.modeButton = modeButton

  -- Compact mode: the clock itself starts / stops the session (Reset stays in
  -- full mode); a red Paused marker and a dimmed clock while it is stopped.
  local paused = W.text(row, T.fonts.small, T.colors.stale, "RIGHT")
  paused:SetPoint("RIGHT", timer, "LEFT", -gap, 0)
  paused:SetText(L_PAUSED)
  paused:Hide()
  local clockButton = CreateFrame("Button", nil, row)
  clockButton:SetAllPoints(timer)
  -- Above the title's double-click button, and still a drag handle.
  clockButton:SetFrameLevel(row:GetFrameLevel() + 5)
  clockButton:RegisterForClicks("LeftButtonUp")
  clockButton:RegisterForDrag("LeftButton")
  clockButton:SetScript("OnDragStart", function() ns.UI.Window.beginDrag() end)
  clockButton:SetScript("OnDragStop", function() ns.UI.Window.endDrag() end)
  clockButton:SetScript("OnClick", function()
    if header.mode ~= "compact" then return end
    local fn = handlers[Header.toggleState(header.running).action]
    if fn then fn() end
  end)
  clockButton:SetScript("OnEnter", function(self)
    if header.mode == "compact" then W.showTextTooltip(self, L_CLOCK_HINT, "ANCHOR_BOTTOMRIGHT") end
  end)
  clockButton:SetScript("OnLeave", W.hideTooltip)
  header.pausedText, header.clockButton = paused, clockButton

  -- Tabs without the session controls (Bags, Bank, History) use the room for
  -- a short fact about their list (view.headerInfo: item or session count).
  local info = W.text(row, T.fonts.small, T.colors.hint, "RIGHT")
  info:SetPoint("RIGHT", modeButton, "LEFT", -gap * 3, 0)
  info:Hide()
  header.info = info

  -- Shows the controls for the mode, the tab and the running state.
  header.timerAnchor = "toggle"
  function header:Apply()
    local compact = self.mode == "compact"
    -- Compact hides Start / Stop and Reset: the clock moves next to the gear
    -- so it never covers the title.
    local anchor = compact and "mode" or "toggle"
    if anchor ~= self.timerAnchor then
      self.timer:ClearAllPoints()
      if compact then
        self.timer:SetPoint("RIGHT", modeButton, "LEFT", -gap * 2, 0)
      else
        self.timer:SetPoint("RIGHT", toggle, "LEFT", -gap * 3, 0)
      end
      self.timerAnchor = anchor
    end
    self.modeButton:SetGlyph(compact and "full" or "compact")
    if compact and self.goalBar then self.goalBar:Hide() end
    self.timer:SetShown(compact or self.sessionShown)
    self.info:SetShown(not compact and not self.sessionShown and (self.infoText or "") ~= "")
    self.toggle:SetShown(not compact and self.sessionShown)
    self.reset:SetShown(not compact and self.sessionShown)
    -- Stopped: compact shows the red Paused marker next to a dimmed clock; the
    -- full header has no room for the word, so the clock itself turns red.
    -- Resting (Pause in cities / while traveling): the same marker, saying
    -- Resting or Traveling.
    local stopped = self.running == false
    local resting = not stopped and (self.resting == "city" or self.resting == "travel")
    local restText = self.resting == "travel" and L_TRAVELING or L_RESTING
    self.pausedText:SetText(resting and restText or L_PAUSED)
    self.pausedText:SetShown(compact and (stopped or resting))
    local color = T.colors.ink
    if stopped or resting then color = compact and T.colors.buttonTextDisabled or T.colors.stale end
    W.setTextColor(self.timer, color)
  end

  -- The clock and the Start / Stop / Reset buttons belong to the session tab;
  -- the close button stays on every tab.
  function header:SetSessionControls(shown)
    self.sessionShown = shown and true or false
    self:Apply()
  end

  function header:SetMode(mode)
    self.mode = mode == "compact" and "compact" or "full"
    self:Apply()
  end

  function header:SetElapsed(seconds)
    self.timer:SetText(Header.formatElapsed(seconds))
  end

  -- The button only changes when the running state does.
  function header:SetRunning(running, resting)
    running = running and true or false
    resting = resting == "travel" and "travel" or (resting and "city" or false)
    if running == self.running and resting == self.resting then return end
    self.running, self.resting = running, resting
    self.toggle:SetText(Header.toggleState(running).label)
    self:Apply()
  end

  function header:SetInfo(text)
    self.infoText = text
    self.info:SetText(text or "")
    self:Apply()
  end

  -- Session goal bar (options "Session goal (gold / minutes)"): a thin gold
  -- line along the bottom of the title row, full layout and Session tab only
  -- (compact has its own, UI/Compact.lua).
  local goalBar = W.line(row, T.colors.gold, "OVERLAY")
  goalBar:SetHeight(T.sizes.compactGoalBarHeight)
  goalBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, -2)
  goalBar:Hide()
  header.goalBar = goalBar

  -- `fraction` 0 to 1, or nil (no goal, or not the full Session tab): hidden.
  function header:SetGoal(fraction)
    local width = self.row:GetWidth() or 0
    if self.mode ~= "compact" and fraction and fraction > 0 and width > 0 then
      self.goalBar:SetWidth(math.max(1, math.floor(width * fraction + 0.5)))
      self.goalBar:Show()
    else
      self.goalBar:Hide()
    end
  end

  -- Ledger part: the clock (and the minutes goal) is the same work on a full
  -- refresh and on a tick; the info text only changes with a full refresh.
  local part = {}
  local goalView
  function part:Tick(_, session, now)
    local elapsed = ns.Session.elapsed(session, now)
    header:SetElapsed(elapsed)
    header:SetRunning(session.running, session.resting)
    local goal = nil
    if goalView then
      local minutes = ns.Util.setting("goalMinutes", 0)
      goal = ns.View.goalFraction(goalView.goal, elapsed, ns.Util.isPositive(minutes) and minutes * 60 or nil)
    end
    header:SetGoal(goal)
  end
  function part:Update(view, session, now)
    goalView = type(view) == "table" and view.kind == "session" and view or nil
    self:Tick(view, session, now)
    header:SetInfo(type(view) == "table" and view.headerInfo or nil)
  end
  -- Font outline: the clock box grows with the glyphs (Fonts.applySizes).
  function part:Relayout() header.timer:SetWidth(T.sizes.timerWidth) end
  if ns.UI.Ledger then ns.UI.Ledger.register(part) end

  Header.instance = header
  return header
end
