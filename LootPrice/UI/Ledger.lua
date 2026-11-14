local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Controller: owns the window, builds the view of the selected tab from live
-- data and feeds every registered part (Rows, Header, Summary, FilterBar).
--
-- Two kinds of redraw keep the per-second cost low:
--   refresh  full rebuild: prices are looked up again, rows sorted, every part
--            gets Update(view, session, now). Runs when data changes and every
--            FULL_REFRESH_SECONDS while the clock runs (prices, age tags).
--   tick     once a second while the clock runs: only the per-hour rates are
--            recomputed and parts that have a Tick(view, session, now) method
--            (clock, rate texts) are called.
-- Nothing is redrawn while the window is hidden; it catches up when shown.
local Ledger = {}
ns.UI.Ledger = Ledger

local TICK_SECONDS = 1
local FULL_REFRESH_SECONDS = 30

local parts = {}
local list -- the Rows list, set by init
local lastRefresh = 0 -- time of the last full refresh
local stale = false -- a refresh was skipped while the window was hidden

-- Current tab key (see UI/Tabs.lua).
Ledger.tab = ns.UI.Tabs.DEFAULT

-- A part is a table with a method Update(view, session, now) and, optionally,
-- Tick(view, session, now).
function Ledger.register(part)
  parts[#parts + 1] = part
end

-- ---------------------------------------------------------------------------
-- Error reporting

local function reportError(err)
  local handler = type(geterrorhandler) == "function" and geterrorhandler()
  if handler then handler(err) end
end

-- Reports each distinct error message once, so a failure that repeats every
-- tick does not flood the error handler.
local reported = {}
local function reportOnce(err)
  local key = tostring(err)
  if reported[key] then return end
  reported[key] = true
  reportError(err)
end

-- ---------------------------------------------------------------------------
-- View inputs (one reused options / context table: no garbage per refresh)

local function readItemInfo(itemID)
  local name, _, quality
  if C_Item and C_Item.GetItemInfo then
    name, _, quality = C_Item.GetItemInfo(itemID)
  elseif type(GetItemInfo) == "function" then
    name, _, quality = GetItemInfo(itemID)
  end
  if name == nil then return nil end
  return { name = name, quality = quality }
end

local function itemInfo(itemID)
  local ok, info = pcall(readItemInfo, itemID)
  return ok and info or nil
end

local function lookupPrice(itemID)
  return ns.Core.lookupPrice(itemID)
end

local function formatDate(timestamp)
  return date("%d %b %H:%M", timestamp)
end

local viewOpts = { lookup = lookupPrice, itemInfo = itemInfo, formatDate = formatDate }
local context = { opts = viewOpts, ledger = Ledger }

local function currentContext(now)
  local db = ns.db
  viewOpts.now = now
  viewOpts.filter = db and db.filter
  viewOpts.sort = db and db.sort
  context.now = now
  context.env = _G
  context.session = ns.session
  context.chardb = ns.chardb
  return context
end

-- ---------------------------------------------------------------------------
-- Building and drawing

function Ledger.buildView(now)
  if not ns.session then return nil end
  return ns.UI.Tabs.get(Ledger.tab).build(currentContext(now))
end

local function windowShown()
  local window = ns.UI.Window
  return window ~= nil and window.isShown()
end

-- Full redraw. Skipped (and remembered) while the window is hidden.
function Ledger.refresh()
  if not list or not ns.session then return end
  if not windowShown() then
    stale = true
    return
  end
  stale = false
  local now = time()
  lastRefresh = now
  local ok, view = pcall(Ledger.buildView, now)
  if not ok then
    reportOnce(view)
    return
  end
  if not view then return end
  Ledger.view = view
  for _, part in ipairs(parts) do
    local okPart, err = pcall(part.Update, part, view, ns.session, now)
    if not okPart then reportError(err) end
  end
end

-- Clock tick: rates and clock only; a full refresh when the prices are due.
function Ledger.tick()
  local session = ns.session
  if not (list and session and session.running and ns.UI.Tabs.get(Ledger.tab).ticks) then return end
  local now = time()
  local view = Ledger.view
  if not view or stale or now - lastRefresh >= FULL_REFRESH_SECONDS then
    Ledger.refresh()
    return
  end
  ns.View.applyRates(view, ns.Session.elapsed(session, now))
  for _, part in ipairs(parts) do
    if part.Tick then
      local ok, err = pcall(part.Tick, part, view, session, now)
      if not ok then reportOnce(err) end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Loot flash: the looted row is brought into view and flashed. Several loot
-- messages of one frame (area loot) share a single refresh.

local pendingFlash = {} -- [itemID] = level
local lastFlashed
local flashScheduled = false

local function flushFlashes()
  flashScheduled = false
  Ledger.refresh()
  if windowShown() then
    if lastFlashed then list:ScrollToItem(lastFlashed) end
    for itemID, level in pairs(pendingFlash) do list:Flash(itemID, level) end
  end
  for itemID in pairs(pendingFlash) do pendingFlash[itemID] = nil end
  lastFlashed = nil
end

function Ledger.flash(itemID, level)
  if not list then return end
  if pendingFlash[itemID] ~= "strong" then pendingFlash[itemID] = level end
  lastFlashed = itemID
  if flashScheduled then return end
  flashScheduled = true
  if C_Timer and C_Timer.After then
    C_Timer.After(0, flushFlashes) -- next frame
  else
    flushFlashes()
  end
end

-- ---------------------------------------------------------------------------
-- Tabs and data changes

local function applyTab(key)
  local Tabs = ns.UI.Tabs
  local spec = Tabs.get(key)
  if ns.UI.Window.setTitle then ns.UI.Window.setTitle(spec.title) end
  if Ledger.tabs then Ledger.tabs:SetSelected(key) end
  local header = ns.UI.Header and ns.UI.Header.instance
  if header then header:SetSessionControls(spec.sessionControls == true) end
end

-- Switches the tab, remembers it and redraws the whole window for it.
function Ledger.setTab(key)
  if not ns.UI.Tabs.valid(key) then key = ns.UI.Tabs.DEFAULT end
  Ledger.tab = key
  Ledger.historyIndex = nil
  if ns.db then ns.db.tab = key end
  applyTab(key)
  if list then list.offset = 0 end
  Ledger.refresh()
end

-- History tab: clicking a session opens it (its items are listed under it at
-- the top of the list); clicking the opened session again collapses it.
function Ledger.toggleHistory(index)
  if Ledger.historyIndex == index then
    Ledger.historyIndex = nil
  else
    Ledger.historyIndex = index
  end
  if list then list.offset = 0 end
  Ledger.refresh()
end

-- Data of kind `what` ("bags", "bank") changed: tabs caching it forget their
-- copy. Returns whether the shown tab needs a refresh for it.
function Ledger.dataChanged(what)
  ns.UI.Tabs.invalidate(what)
  return ns.UI.Tabs.get(Ledger.tab).watches == what
end

-- Item data arrived: only matters for an item listed on the current tab.
function Ledger.wantsItemInfo(itemID)
  if not ns.session then return false end
  local spec = ns.UI.Tabs.get(Ledger.tab)
  if not spec.hasItem then return true end
  return spec.hasItem(itemID, currentContext(time())) and true or false
end

-- ---------------------------------------------------------------------------
-- Setup

local rowsPart = {}
function rowsPart:Update(view)
  list:SetData(view.rows)
end

-- One failing part must not stop the others, the ticker or the first refresh.
local function attach(part, fn)
  if not part then return end
  local ok, err = pcall(fn)
  if not ok then reportError(err) end
end

function Ledger.init()
  if Ledger.frame then return Ledger.frame end
  local UI = ns.UI
  local frame = UI.Window.create(ns.db)
  if not frame then return nil end
  Ledger.frame = frame

  local Rows = UI.Rows
  local function applyMinWidth(measured)
    UI.Window.setMinWidth(Rows.requiredRowWidth(measured))
  end
  list = Rows.attach(frame.listArea, applyMinWidth)
  Ledger.list = list
  list.onRowClick = function(row)
    if row.historyIndex then Ledger.toggleHistory(row.historyIndex) end
  end
  applyMinWidth(list.measured)
  table.insert(parts, 1, rowsPart)

  attach(UI.Summary, function()
    UI.Summary.attach(frame.topBox, frame.footer)
  end)

  attach(UI.Header, function()
    local Core = ns.Core
    UI.Header.attach(frame.header.row1, {
      start = Core.startSession,
      stop = Core.stopSession,
      reset = Core.resetSession,
      hide = UI.Window.hide,
      options = UI.OptionsPanel and UI.OptionsPanel.toggle,
    })
  end)

  attach(UI.FilterBar, function()
    UI.FilterBar.attach(frame.header.row2, ns.db, Ledger.refresh)
  end)

  attach(UI.Tabs, function()
    Ledger.tabs = UI.Tabs.attach(frame.header.row3, Ledger.setTab)
  end)

  -- OnUpdate only runs while the frame is shown.
  local acc = 0
  frame:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < TICK_SECONDS then return end
    acc = 0
    Ledger.tick()
  end)

  -- Catch up on everything that changed while the window was hidden.
  frame:HookScript("OnShow", Ledger.refresh)

  local saved = ns.db and ns.db.tab
  if UI.Tabs.valid(saved) then Ledger.tab = saved end
  applyTab(Ledger.tab)

  Ledger.refresh()
  return frame
end

ns.UI.refresh = Ledger.refresh
ns.UI.flash = Ledger.flash
