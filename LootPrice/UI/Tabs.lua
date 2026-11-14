local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Tab registry and the tab buttons of header row 3. The ledger never names a
-- tab: it asks the selected tab's spec for its view. A new tab is one
-- Tabs.define call:
--
--   Tabs.define({
--     key   = "bags",                -- saved in db.tab
--     label = "Bags",                -- button text
--     title = "Bag Ledger",          -- window title while selected
--     build = function(ctx) return view end, -- see View.lua for the view shape
--     sessionControls = false,       -- show the clock and Start / Stop / Reset
--     ticks   = false,               -- per-hour rates change with the clock
--     watches = "bags",              -- data kind whose change redraws the tab
--     invalidate = function() end,   -- optional: drop cached data of `watches`
--     hasItem = function(itemID, ctx) return bool end, -- is the item listed?
--   })
--
-- ctx = { now, env, session, chardb, opts (View options), ledger }.
-- valid, label and title are pure; attach is client-only.
local Tabs = {}
ns.UI.Tabs = Tabs

Tabs.KEYS = {} -- tab keys in display order
Tabs.DEFAULT = "session"

local specs = {}

function Tabs.define(spec)
  assert(type(spec) == "table" and type(spec.key) == "string", "tab needs a key")
  assert(type(spec.build) == "function", "tab needs a build function")
  if not specs[spec.key] then Tabs.KEYS[#Tabs.KEYS + 1] = spec.key end
  specs[spec.key] = spec
  return spec
end

-- The spec of a tab; an unknown key gives the default tab.
function Tabs.get(key)
  return specs[key] or specs[Tabs.DEFAULT]
end

function Tabs.valid(key)
  return specs[key] ~= nil
end

function Tabs.label(key)
  return Tabs.get(key).label
end

function Tabs.title(key)
  return Tabs.get(key).title
end

-- Drops the cached data of every tab watching `what` ("bags", "bank", ...).
function Tabs.invalidate(what)
  for _, key in ipairs(Tabs.KEYS) do
    local spec = specs[key]
    if spec.watches == what and spec.invalidate then spec.invalidate() end
  end
end

-- ---------------------------------------------------------------------------
-- Built-in tabs

-- Session: the loot of the running session.
Tabs.define({
  key = "session", label = "Session", title = "Session Ledger",
  sessionControls = true,
  ticks = true,
  build = function(ctx) return ns.View.build(ctx.session, ctx.opts) end,
  hasItem = function(itemID, ctx) return ctx.session.items[itemID] ~= nil end,
})

-- Bags: live bag contents, scanned again only after the bags changed.
local bagItems
Tabs.define({
  key = "bags", label = "Bags", title = "Bag Ledger",
  watches = "bags",
  invalidate = function() bagItems = nil end,
  build = function(ctx)
    if not bagItems then bagItems = ns.Inventory.scanBags(ctx.env, ctx.now) end
    return ns.View.buildInventory(bagItems, ctx.opts)
  end,
  hasItem = function(itemID) return bagItems ~= nil and bagItems[itemID] ~= nil end,
})

-- Bank: the last saved scan (Core scans while the bank window is open).
local function savedBank(ctx)
  local bank = ctx.chardb and ctx.chardb.bank
  return type(bank) == "table" and bank or nil
end

Tabs.define({
  key = "bank", label = "Bank", title = "Bank Ledger",
  watches = "bank",
  build = function(ctx)
    local bank = savedBank(ctx)
    local view = ns.View.buildInventory(bank and bank.items or {}, ctx.opts)
    view.note, view.noteStale = ns.Inventory.scanNote(ctx.now, bank and bank.scannedAt)
    return view
  end,
  hasItem = function(itemID, ctx)
    local bank = savedBank(ctx)
    return bank ~= nil and type(bank.items) == "table" and bank.items[itemID] ~= nil
  end,
})

-- History: archived sessions; the opened one (ledger.historyIndex) lists its items.
local function savedHistory(ctx)
  local history = ctx.chardb and ctx.chardb.history
  return type(history) == "table" and history or {}
end

Tabs.define({
  key = "history", label = "History", title = "Session History",
  build = function(ctx)
    local history, ledger = savedHistory(ctx), ctx.ledger
    if ledger.historyIndex and not history[ledger.historyIndex] then ledger.historyIndex = nil end
    return ns.View.buildHistory(history, ctx.opts, ledger.historyIndex)
  end,
  hasItem = function(itemID, ctx)
    local entry = savedHistory(ctx)[ctx.ledger.historyIndex or 0]
    return type(entry) == "table" and type(entry.items) == "table" and entry.items[itemID] ~= nil
  end,
})

-- ---------------------------------------------------------------------------
-- Buttons

-- `row` is the header row to put the buttons in; `onSelect(key)` is called when
-- a tab button is clicked. Returns an object with SetSelected(key): the
-- selected tab's button is disabled (disabled font).
function Tabs.attach(row, onSelect)
  local T = ns.Theme
  local tabs = { buttons = {} }
  local previous
  for _, key in ipairs(Tabs.KEYS) do
    local b = ns.UI.Widgets.button(row, Tabs.label(key), T.widths.tab)
    if previous then
      b:SetPoint("LEFT", previous, "RIGHT", T.sizes.buttonGap, 0)
    else
      b:SetPoint("LEFT", row, "LEFT", 0, 0)
    end
    b:SetScript("OnClick", function()
      if onSelect then onSelect(key) end
    end)
    tabs.buttons[key] = b
    previous = b
  end

  function tabs:SetSelected(key)
    for k, b in pairs(self.buttons) do b:SetEnabled(k ~= key) end
  end

  return tabs
end
