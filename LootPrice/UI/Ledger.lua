local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Controller: owns the window, builds the view from live data and feeds every
-- registered part (Rows, and later Header / Summary / FilterBar).
local Ledger = {}
ns.UI.Ledger = Ledger

local TICK_SECONDS = 1

local parts = {}
local list -- the Rows list, set by init

-- A part is a table with a method Update(view, session, now).
function Ledger.register(part)
  parts[#parts + 1] = part
end

local function guarded(fn, ...)
  local ok, a = pcall(fn, ...)
  if ok then return a end
  return nil
end

local function itemInfo(itemID)
  local name, quality
  if C_Item and C_Item.GetItemInfo then
    local n, _, q = C_Item.GetItemInfo(itemID)
    name, quality = n, q
  elseif type(GetItemInfo) == "function" then
    local n, _, q = GetItemInfo(itemID)
    name, quality = n, q
  end
  if name == nil then return nil end
  return { name = name, quality = quality }
end

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

-- Current tab: "session" (loot), "bags" (live bag contents) or "bank" (the
-- last saved bank scan).
Ledger.tab = "session"
local bagItems
local bagsDirty = true

function Ledger.markBagsDirty()
  bagsDirty = true
end

function Ledger.isInventoryTab()
  return Ledger.tab ~= "session"
end

local function viewOpts(now)
  local prices = ns.prices
  local db = ns.db or {}
  return {
    now = now,
    filter = db.filter,
    sort = db.sort,
    lookup = function(id)
      if not prices then return nil end
      return guarded(prices.lookup, prices, id)
    end,
    itemInfo = function(id) return guarded(itemInfo, id) end,
  }
end

function Ledger.buildView(now)
  local session = ns.session
  if not session then return nil end
  local tab = Ledger.tab
  if tab == "bags" then
    if bagsDirty or not bagItems then
      bagItems = ns.Inventory.scanBags(_G, now)
      bagsDirty = false
    end
    return ns.View.buildInventory(bagItems, viewOpts(now))
  elseif tab == "bank" then
    local bank = ns.chardb and ns.chardb.bank or {}
    local view = ns.View.buildInventory(bank.items or {}, viewOpts(now))
    view.note, view.noteStale = ns.Inventory.scanNote(now, bank.scannedAt)
    return view
  end
  return ns.View.build(session, viewOpts(now))
end

-- Switches the tab, remembers it and redraws the whole window for it.
function Ledger.setTab(key)
  if not ns.UI.Tabs.valid(key) then key = "session" end
  Ledger.tab = key
  if ns.db then ns.db.tab = key end
  if ns.UI.Window and ns.UI.Window.setTitle then ns.UI.Window.setTitle(ns.UI.Tabs.title(key)) end
  if ns.UI.Header and ns.UI.Header.instance then
    ns.UI.Header.instance:SetSessionControls(key == "session")
  end
  if Ledger.tabs then Ledger.tabs:SetSelected(key) end
  if list then list:SetOffset(0) end
  Ledger.refresh()
end

-- Item data arrived: only matters for rows of the current tab.
function Ledger.wantsItemInfo(itemID)
  if Ledger.tab == "session" then
    return ns.session ~= nil and ns.session.items[itemID] ~= nil
  end
  return true
end

function Ledger.refresh()
  if not list or not ns.session then return end
  local now = time()
  local ok, view = pcall(Ledger.buildView, now)
  if not ok then
    reportOnce(view)
    return
  end
  if not view then return end
  Ledger.view = view
  for _, part in ipairs(parts) do
    local ok, err = pcall(part.Update, part, view, ns.session, now)
    if not ok then reportError(err) end
  end
end

-- Refresh, bring the row into view, then flash it.
function Ledger.flash(itemID, level)
  if not list then return end
  Ledger.refresh()
  list:ScrollToItem(itemID)
  list:Flash(itemID, level)
end

local rowsPart = {}
function rowsPart:Update(view)
  list:SetData(view.rows)
end

function Ledger.init()
  if Ledger.frame then return Ledger.frame end
  local frame = ns.UI.Window.create(ns.db)
  if not frame then return nil end
  Ledger.frame = frame

  local Rows = ns.UI.Rows
  local function applyMinWidth(measured)
    ns.UI.Window.setMinWidth(Rows.requiredRowWidth(measured))
  end
  list = Rows.attach(frame.listArea, applyMinWidth)
  Ledger.list = list
  applyMinWidth(list.measured)
  table.insert(parts, 1, rowsPart)

  -- One failing part must not stop the others, the ticker or the first refresh.
  local function attach(part, fn)
    if not part then return end
    local ok, err = pcall(fn)
    if not ok then reportError(err) end
  end

  attach(ns.UI.Summary, function()
    ns.UI.Summary.attach(frame.topBox, frame.footer)
  end)

  attach(ns.UI.Header, function()
    local Core = ns.Core
    ns.UI.Header.attach(frame.header.row1, {
      start = Core.startSession,
      stop = Core.stopSession,
      reset = Core.resetSession,
      hide = ns.UI.Window.hide,
    })
  end)

  attach(ns.UI.FilterBar, function()
    ns.UI.FilterBar.attach(frame.header.row2, ns.db, Ledger.refresh)
  end)

  -- OnUpdate only runs while the frame is shown; the clock only ticks on the
  -- session tab.
  local acc = 0
  frame:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < TICK_SECONDS then return end
    acc = 0
    if Ledger.tab == "session" and ns.session and ns.session.running then Ledger.refresh() end
  end)

  -- Bags may have changed while the window was hidden.
  frame:HookScript("OnShow", function()
    if Ledger.isInventoryTab() then
      Ledger.markBagsDirty()
      Ledger.refresh()
    end
  end)

  attach(ns.UI.Tabs, function()
    Ledger.tabs = ns.UI.Tabs.attach(frame.header.row3, Ledger.setTab)
  end)
  local saved = ns.db and ns.db.tab
  if ns.UI.Tabs.valid(saved) then Ledger.tab = saved end
  if ns.UI.Window.setTitle then ns.UI.Window.setTitle(ns.UI.Tabs.title(Ledger.tab)) end
  if Ledger.tabs then Ledger.tabs:SetSelected(Ledger.tab) end
  if ns.UI.Header and ns.UI.Header.instance then
    ns.UI.Header.instance:SetSessionControls(Ledger.tab == "session")
  end

  Ledger.refresh()
  return frame
end

ns.UI.refresh = Ledger.refresh
ns.UI.flash = Ledger.flash
