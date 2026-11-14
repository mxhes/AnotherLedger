local ADDON, ns = ...

local L = ns.L

ns.UI = ns.UI or {}

-- Tab registry and the tab buttons of header row 3. The ledger never names a
-- tab: it asks the selected tab's spec for its view. A new tab is one
-- Tabs.define call:
--
--   Tabs.define({
--     key   = "bags",                -- saved in db.tab
--     label = L["Bags"],                -- button text
--     title = L["Bag Ledger"],          -- window title while selected
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
  key = "session", label = L["Session"], title = L["Session Ledger"],
  sessionControls = true,
  ticks = true,
  build = function(ctx) return ns.View.build(ctx.session, ctx.opts) end,
  hasItem = function(itemID, ctx) return ns.Session.hasItemID(ctx.session.items, itemID) end,
})

-- Bags: live bag contents, scanned again only after the bags changed.
local bagItems
Tabs.define({
  key = "bags", label = L["Bags"], title = L["Bag Ledger"],
  watches = "bags",
  invalidate = function() bagItems = nil end,
  build = function(ctx)
    if not bagItems then bagItems = ns.Inventory.scanBags(ctx.env, ctx.now) end
    return ns.View.buildInventory(bagItems, ctx.opts)
  end,
  hasItem = function(itemID) return bagItems ~= nil and ns.Session.hasItemID(bagItems, itemID) end,
})

-- Bank: the last saved scan (Core scans while the bank window is open).
local function savedBank(ctx)
  local bank = ctx.chardb and ctx.chardb.bank
  return type(bank) == "table" and bank or nil
end

Tabs.define({
  key = "bank", label = L["Bank"], title = L["Bank Ledger"],
  watches = "bank",
  build = function(ctx)
    local bank = savedBank(ctx)
    local view = ns.View.buildInventory(bank and bank.items or {}, ctx.opts)
    local hours = ns.Options and ns.db and ns.Options.get(ns.db, "staleHours")
    view.note, view.noteStale = ns.Inventory.scanNote(ctx.now, bank and bank.scannedAt, hours and hours * 3600)
    return view
  end,
  hasItem = function(itemID, ctx)
    local bank = savedBank(ctx)
    return bank ~= nil and ns.Session.hasItemID(bank.items, itemID)
  end,
})

-- History: archived sessions; the opened one (ledger.historyIndex) lists its items.
local function savedHistory(ctx)
  local history = ctx.chardb and ctx.chardb.history
  return type(history) == "table" and history or {}
end

Tabs.define({
  key = "history", label = L["History"], title = L["Session History"],
  build = function(ctx)
    local history, ledger = savedHistory(ctx), ctx.ledger
    if ledger.historyIndex and not history[ledger.historyIndex] then ledger.historyIndex = nil end
    return ns.View.buildHistory(history, ctx.opts, ledger.historyIndex)
  end,
  hasItem = function(itemID, ctx)
    local entry = savedHistory(ctx)[ctx.ledger.historyIndex or 0]
    return type(entry) == "table" and ns.Session.hasItemID(entry.items, itemID)
  end,
})

-- ---------------------------------------------------------------------------
-- Buttons

-- `row` is the header row to put the buttons in; `onSelect(key)` is called when
-- another tab's button is clicked. Returns an object with SetSelected(key).
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
      if onSelect and key ~= tabs.selected then onSelect(key) end
    end)
    -- Gold bar under the selected tab.
    local mark = ns.UI.Widgets.line(b, T.colors.goldLine, "OVERLAY")
    mark:SetHeight(2)
    mark:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 3, -1)
    mark:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, -1)
    mark:Hide()
    b.mark = mark
    tabs.buttons[key] = b
    previous = b
  end

  -- The selected tab keeps its white text, gets the gold bar and a locked
  -- highlight; clicking it again does nothing.
  -- UNVERIFIED (check in client): Button:LockHighlight on UIPanelButtonTemplate.
  function tabs:SetSelected(key)
    self.selected = key
    for k, b in pairs(self.buttons) do
      local on = k == key
      b.mark:SetShown(on)
      if on then b:LockHighlight() else b:UnlockHighlight() end
    end
  end

  return tabs
end
