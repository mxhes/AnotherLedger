local ADDON, ns = ...

ns.UI = ns.UI or {}

-- Controller: owns the window, builds the view of the selected tab from live
-- data and feeds every registered part (Rows, Header, Summary, FilterBar).
--
-- Two kinds of redraw keep the per-second cost low:
--   refresh  full rebuild: prices are looked up again, rows sorted, every part
--            gets Update(view, session, now). Runs when data changes and, on
--            every tab, every refreshSeconds while the window is shown
--            (prices, age tags), clock running or not.
--   tick     once a second while the clock runs: only the per-hour rates are
--            recomputed and parts that have a Tick(view, session, now) method
--            (clock, rate texts) are called.
-- Nothing is redrawn while the window is hidden; it catches up when shown.
local Ledger = {}
ns.UI.Ledger = Ledger

local TICK_SECONDS = 1
local FULL_REFRESH_SECONDS = ns.DB.defaults.settings.refreshSeconds -- option "refreshSeconds"

local function refreshSeconds()
  return ns.Util.setting("refreshSeconds", FULL_REFRESH_SECONDS)
end

local parts = {}
local list -- the Rows list, set by init
local lastRefresh = 0 -- time of the last full refresh
local stale = false -- a refresh was skipped while the window was hidden

-- Current tab key (see UI/Tabs.lua).
Ledger.tab = ns.UI.Tabs.DEFAULT
-- Current sub-tab key of that tab (nil: it has none), and the opened place of
-- History Zones ({ zone, sub }).
Ledger.subtab = nil
Ledger.zoneOpen = {}
-- Layout mode: "full" (the ledger) or "compact" (the glance); db.mode.
Ledger.mode = "full"

-- A part is a table with a method Update(view, session, now) and, optionally,
-- Tick(view, session, now) and Relayout() (Theme.sizes changed; Ledger.relayout).
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

-- Bind types (14th GetItemInfo return) of items that can never be sold on the
-- auction house: on pickup, quest, account, warband, warband until equipped.
local UNAUCTIONABLE = { [1] = true, [4] = true, [7] = true, [8] = true, [9] = true }

local function readItemInfo(itemID, link)
  local name, _, quality, bindType
  local query = type(link) == "string" and link or itemID
  local getInfo = (C_Item and C_Item.GetItemInfo) or (type(GetItemInfo) == "function" and GetItemInfo) or nil
  if getInfo then
    local r = { getInfo(query) }
    name, quality, bindType = r[1], r[3], r[14]
  end
  if name == nil then return nil end
  return { name = name, quality = quality, bound = UNAUCTIONABLE[bindType] or false }
end

local function itemInfo(itemID, link)
  local ok, info = pcall(readItemInfo, itemID, link)
  return ok and info or nil
end

-- C_CurrencyInfo.GetCurrencyInfo(id) returns { name, iconFileID, quality }.
local function readCurrencyInfo(currencyID)
  local api = C_CurrencyInfo
  if not (api and api.GetCurrencyInfo) then return nil end
  local info = api.GetCurrencyInfo(currencyID)
  if type(info) ~= "table" then return nil end
  return { name = info.name, icon = info.iconFileID, quality = info.quality }
end

local function currencyInfo(currencyID)
  local ok, info = pcall(readCurrencyInfo, currencyID)
  return ok and info or nil
end

-- History Zones: quest items (item class 12) go to their own group.
-- GetItemInfoInstant returns the class ID 6th; Enum.ItemClass.Questitem is 12.
local QUEST_CLASS = 12
local function readIsQuest(itemID)
  local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if type(fn) ~= "function" then return false end
  local classID = select(6, fn(itemID))
  return classID == QUEST_CLASS
end

-- An item's class never changes: asked once per item ID.
local questMemo = {}
local function isQuest(itemID)
  local hit = questMemo[itemID]
  if hit == nil then
    local ok, quest = pcall(readIsQuest, itemID)
    hit = ok and quest or false
    questMemo[itemID] = hit
  end
  return hit
end

-- Prices are looked up once per item variant and redraw: the same item can
-- show up more than once (History) and every lookup asks every source.
local priceMemo = {}
local function lookupPrice(itemID, link)
  local key = itemID
  if type(link) == "string" then key = ns.LootParse.itemKey(link) or itemID end
  local hit = priceMemo[key]
  if hit == nil then
    hit = ns.Core.lookupPrice(itemID, link) or false
    priceMemo[key] = hit
  end
  return hit or nil
end

local function formatDate(timestamp)
  return date("%Y-%m-%d %H:%M", timestamp)
end
Ledger.formatDate = formatDate

-- The cutoffs of the sale info levels (View.marketLevels), or nil with the
-- option "showMarket" off.
local marketCutoffs = {}
function Ledger.marketCutoffs(db)
  local O = ns.Options
  if not (O and db) or ns.Util.setting("showMarket", true) == false then return nil end
  marketCutoffs.rateGood, marketCutoffs.rateOk = O.get(db, "saleRateGood"), O.get(db, "saleRateOk")
  marketCutoffs.soldHigh, marketCutoffs.soldMedium = O.get(db, "soldHigh"), O.get(db, "soldMedium")
  return marketCutoffs
end

-- History rows: "Today 20:21", "Sat 14:55", "2026-11-02" (History.shortDate).
local function shortDate(timestamp)
  return ns.History.shortDate(timestamp, time(), date)
end

local viewOpts = { lookup = lookupPrice, itemInfo = itemInfo, currencyInfo = currencyInfo, formatDate = formatDate,
  shortDate = shortDate, isQuest = isQuest }

-- The History that Zones reads (every character's with "accountZones").
local function zoneHistory()
  local Core = ns.Core
  if Core and Core.zoneHistory then return (Core.zoneHistory()) end
  return ns.chardb and ns.chardb.history or {}
end

local context = { opts = viewOpts, ledger = Ledger, zoneHistory = zoneHistory }

-- The sort of the shown view: History Sessions and Zones keep their own
-- (db.sorts, Tabs.sortSlot), the item lists share db.sort.
function Ledger.currentSort()
  local db = ns.db
  if not db then return nil end
  local slot, default = ns.UI.Tabs.sortSlot(Ledger.tab, Ledger.subtab)
  if not slot then return db.sort end
  local saved = type(db.sorts) == "table" and db.sorts[slot] or nil
  for _, key in ipairs(ns.UI.Tabs.sorts(Ledger.tab, Ledger.subtab)) do
    if key == saved then return saved end
  end
  return default
end

function Ledger.setSort(key)
  local db = ns.db
  if not db then return end
  local slot = ns.UI.Tabs.sortSlot(Ledger.tab, Ledger.subtab)
  if not slot then
    db.sort = key
    return
  end
  if type(db.sorts) ~= "table" then db.sorts = {} end
  db.sorts[slot] = key
end

local function currentContext(now)
  local db = ns.db
  viewOpts.now = now
  viewOpts.filter = db and db.filter
  viewOpts.sort = Ledger.currentSort()
  local setting = ns.Util.setting
  viewOpts.includeGold = setting("includeGold", true)
  viewOpts.showCurrencies = setting("showCurrencies", true)
  viewOpts.market = Ledger.marketCutoffs(db)
  viewOpts.ahMinGain = setting("ahMinGain", 0)
  viewOpts.compactDrops = setting("compactDrops", nil)
  viewOpts.ignored = db and type(db.ignored) == "table" and db.ignored or nil
  viewOpts.kept = db and type(db.kept) == "table" and db.kept or nil
  viewOpts.goal = ns.Core and ns.Core.goalCopper and ns.Core.goalCopper() or nil
  context.now = now
  context.env = _G
  context.session = ns.session
  context.chardb = ns.chardb
  return context
end

-- The View options the window builds with now (the CSV export reuses them).
function Ledger.viewOptions()
  return currentContext(time()).opts
end

-- ---------------------------------------------------------------------------
-- Building and drawing

-- The Daily farm of the saved History (not the running session, so farming
-- does not move today's pick), or nil with the option off. It scans all of
-- History, so the result is kept until History or the options it reads
-- (value, gold, price source, sale info) change, or the price refresh interval
-- has passed (prices may have moved).
-- An error is reported once and leaves the rest of the window drawn.
local farmCache = { key = nil, at = 0, value = nil }

-- `listKey`: History.combine's key of the lists it reads.
local function farmKey(listKey, minutes)
  local m = viewOpts.market
  local setting = ns.Util.setting
  local ignored, idSum = 0, 0
  for id in pairs(viewOpts.ignored or {}) do ignored, idSum = ignored + 1, idSum + (tonumber(id) or 0) end
  return table.concat({
    listKey, tostring(minutes), tostring(viewOpts.includeGold), ignored .. ":" .. idSum,
    tostring(setting("priceSource", nil)), tostring(setting("tsmSource", nil)),
    tostring(setting("ahCut", nil)), tostring(setting("ahMinGain", nil)), tostring(setting("destroyMode", nil)),
    m and (tostring(m.rateGood) .. "/" .. tostring(m.rateOk)) or "-",
  }, "|")
end

local function dailyFarm(now)
  local setting = ns.Util.setting
  if not (ns.Options and ns.db and ns.Core) or setting("dailyFarm", true) == false then return nil end
  local history, listKey = ns.Core.zoneHistory()
  if type(history) ~= "table" then return nil end
  local minutes = setting("dailyFarmMinutes", 20)
  local key = farmKey(listKey, minutes)
  if key == farmCache.key and now - farmCache.at < refreshSeconds() then return farmCache.value end
  local ok, farm = pcall(ns.View.dailyFarm, history, viewOpts, minutes * 60)
  if not ok then
    reportOnce(farm)
    farm = nil
  end
  farmCache.key, farmCache.at, farmCache.value = key, now, farm
  return farm
end

function Ledger.buildView(now)
  if not ns.session then return nil end
  for k in pairs(priceMemo) do priceMemo[k] = nil end
  local ctx = currentContext(now)
  -- The Daily farm first: History Zones marks its place (opts.dailyPick).
  local farm = dailyFarm(now)
  local best = type(farm) == "table" and farm.best or nil
  viewOpts.dailyPick = best and { zone = best.zone, sub = best.sub } or nil
  local view = ns.UI.Tabs.build(Ledger.tab, Ledger.subtab, ctx)
  if type(view) == "table" then
    view.dailyFarm = farm
    -- Compact mode draws its own unfiltered numbers and last drops.
    if Ledger.mode == "compact" then view.compact = ns.View.buildCompact(ns.session, viewOpts) end
  end
  return view
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

-- Re-lays the window out after Theme.sizes changed (font size options, item
-- icons): the window bounds first, then every part with a Relayout method,
-- then a full redraw.
function Ledger.relayout()
  if not Ledger.frame then return end
  local window = ns.UI.Window
  if window and window.applySizes then
    local ok, err = pcall(window.applySizes)
    if not ok then reportError(err) end
  end
  for _, part in ipairs(parts) do
    if part.Relayout then
      local ok, err = pcall(part.Relayout, part)
      if not ok then reportError(err) end
    end
  end
  Ledger.refresh()
end

-- Font size options: new sizes for the theme and the font objects, and a
-- relayout when any of them changed (nothing happens before the window exists).
function Ledger.applySizes()
  local fonts = ns.UI.Fonts
  if not (fonts and ns.db and fonts.applySizes(ns.db)) then return end
  Ledger.relayout()
end

-- Every second: a full refresh when the prices are due (any tab, while the
-- window is shown); else, while the clock runs, the rates and the clock only.
function Ledger.tick()
  local session = ns.session
  if not (list and session and windowShown()) then return end
  local now = time()
  local view = Ledger.view
  if not view or stale or now - lastRefresh >= refreshSeconds() then
    Ledger.refresh()
    return
  end
  -- Compact mode always shows the session clock and rate, whatever the tab.
  local compact = Ledger.mode == "compact"
  local ticks = ns.UI.Tabs.get(Ledger.tab).ticks
  if not (session.running and (compact or ticks)) then return end
  if ticks then ns.View.applyRates(view, ns.Session.elapsed(session, now)) end
  if compact then
    viewOpts.now = now
    view.compact = ns.View.buildCompact(session, viewOpts)
  end
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

local pendingFlash = {} -- [item key] = level
local lastFlashed
local flashScheduled = false

-- Option "followLoot": only the Session list scrolls to new loot.
local function followLoot()
  if Ledger.tab ~= "session" or Ledger.mode ~= "full" then return false end
  return ns.Util.setting("followLoot", true)
end

local function flushFlashes()
  flashScheduled = false
  Ledger.refresh()
  if windowShown() then
    if lastFlashed and followLoot() then list:ScrollToItem(lastFlashed) end
    for key, level in pairs(pendingFlash) do list:Flash(key, level) end
  end
  for key in pairs(pendingFlash) do pendingFlash[key] = nil end
  lastFlashed = nil
end

-- `key` is the looted item's LootParse.itemKey.
function Ledger.flash(key, level)
  if not list then return end
  if pendingFlash[key] ~= "strong" then pendingFlash[key] = level end
  lastFlashed = key
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

-- The saved (or default) sub-tab of tab `key`, or nil when it has none.
local function savedSubtab(key)
  local saved = ns.db and type(ns.db.subtab) == "table" and ns.db.subtab[key] or nil
  local sub = ns.UI.Tabs.subtab(key, saved)
  return sub and sub.key or nil
end

local function applyTab(key)
  local Tabs = ns.UI.Tabs
  local spec = Tabs.get(key)
  if ns.UI.Window.setTitle then ns.UI.Window.setTitle(spec.title) end
  if Ledger.tabs then Ledger.tabs:SetSelected(key) end
  local strips = Ledger.subtabStrips or {}
  for k, strip in pairs(strips) do strip.frame:SetShown(k == key) end
  if strips[key] then strips[key]:SetSelected(Ledger.subtab) end
  if ns.UI.Window.setSubtabRow then ns.UI.Window.setSubtabRow(Tabs.subtabs(key) ~= nil) end
  if ns.UI.FilterBar and ns.UI.FilterBar.setSorts then ns.UI.FilterBar.setSorts(Tabs.sorts(key, Ledger.subtab)) end
  local header = ns.UI.Header and ns.UI.Header.instance
  if header then header:SetSessionControls(spec.sessionControls == true) end
end

-- Scroll position per tab and sub-tab for this login: coming back to a list
-- shows it where it was left (clamped when it got shorter).
local scrollOffsets = {}

local function viewKey()
  return Ledger.tab .. "/" .. tostring(Ledger.subtab)
end

local function rememberScroll()
  if list then scrollOffsets[viewKey()] = list.offset end
end

local function restoreScroll()
  if list then list.offset = scrollOffsets[viewKey()] or 0 end
end

-- Tab and sub-tab state without a redraw (setTab / setSubtab / showFarm redraw).
local function switchTab(key)
  if not ns.UI.Tabs.valid(key) then key = ns.UI.Tabs.DEFAULT end
  rememberScroll()
  Ledger.tab = key
  Ledger.subtab = savedSubtab(key)
  Ledger.historyIndex = nil
  Ledger.zoneOpen = {}
  if ns.db then ns.db.tab = key end
  applyTab(key)
  restoreScroll()
end

local function switchSubtab(subKey)
  local sub = ns.UI.Tabs.subtab(Ledger.tab, subKey)
  if not sub then return false end
  rememberScroll()
  Ledger.subtab = sub.key
  Ledger.historyIndex = nil
  Ledger.zoneOpen = {}
  if ns.db then
    if type(ns.db.subtab) ~= "table" then ns.db.subtab = {} end
    ns.db.subtab[Ledger.tab] = sub.key
  end
  applyTab(Ledger.tab)
  restoreScroll()
  return true
end

-- Switches the tab, remembers it and redraws the whole window for it.
function Ledger.setTab(key)
  switchTab(key)
  Ledger.refresh()
end

-- Switches the sub-tab of the shown tab and remembers it per tab.
function Ledger.setSubtab(subKey)
  if switchSubtab(subKey) then Ledger.refresh() end
end

-- Switches the layout mode ("full" / "compact"), remembers it and redraws.
function Ledger.setMode(mode)
  if mode ~= "compact" then mode = "full" end
  Ledger.mode = mode
  if ns.db then ns.db.mode = mode end
  if ns.UI.Window.applyMode then ns.UI.Window.applyMode(mode) end
  local header = ns.UI.Header and ns.UI.Header.instance
  if header and header.SetMode then header:SetMode(mode) end
  Ledger.applyModeTitle()
  Ledger.refresh()
end

-- Compact shows the session whatever the tab: its title; full: the tab's.
function Ledger.applyModeTitle()
  local W, Tabs = ns.UI.Window, ns.UI.Tabs
  if not W.setTitle then return end
  W.setTitle(Tabs.title(Ledger.mode == "compact" and "session" or Ledger.tab))
end

function Ledger.toggleMode()
  Ledger.setMode(Ledger.mode == "compact" and "full" or "compact")
end

-- History Zones: a zone row opens its subzones (and closes another zone), a
-- subzone row its items; clicking the opened one again collapses it.
function Ledger.toggleZone(zoneKey, subKey)
  local open = Ledger.zoneOpen
  if subKey == nil then
    if open.zone == zoneKey then
      Ledger.zoneOpen = {}
    else
      Ledger.zoneOpen = { zone = zoneKey }
    end
  elseif open.sub == subKey then
    Ledger.zoneOpen = { zone = zoneKey }
  else
    Ledger.zoneOpen = { zone = zoneKey, sub = subKey }
  end
  Ledger.refresh()
end

-- Daily farm click: History -> Zones with that zone and subzone opened.
-- One redraw; the opened subzone is scrolled to the top of the list (as far
-- as the list scrolls) so its items show under it.
function Ledger.showFarm(zone, sub)
  -- Zones lives in the full layout: compact switches to it first.
  if Ledger.mode == "compact" then Ledger.setMode("full") end
  if Ledger.tab ~= "history" then switchTab("history") end
  if Ledger.subtab ~= "zones" then switchSubtab("zones") end
  Ledger.zoneOpen = { zone = zone, sub = sub }
  Ledger.refresh()
  if not (list and Ledger.view) then return end
  local idx = ns.View.indexOf(Ledger.view.rows, "s:" .. zone .. "\1" .. sub)
  if not idx then return end
  local visible = ns.UI.Rows.visibleCount(list.area:GetHeight(), ns.Theme.sizes.rowHeight)
  list:SetOffset(ns.UI.Rows.clampOffset(idx - 1, #Ledger.view.rows, visible))
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

local L_DELETE = ns.L["Delete"]
local L_ADD_NOTE = ns.L["Add note"]
local L_EDIT_NOTE = ns.L["Edit note"]
local L_MERGE = ns.L["Merge with the older session"]
local L_NOTE_PROMPT = ns.L["Note for this session (empty removes it):"]
local L_SAVE = ns.L["Save"]
local L_IGNORE = ns.L["Ignore this item"]
local L_IGNORED = ns.L["%s is ignored: it no longer counts anywhere. Options, Display, Ignored items takes it back."]
local L_KEEP = ns.L["Keep (not for sale)"]
local L_UNKEEP = ns.L["Sell again (not kept)"]

-- Deletes the History session at `index` (/ll undo brings it back). The
-- opened session stays open (its index moves when a newer one goes).
function Ledger.deleteHistory(index)
  if not (ns.Core and ns.Core.deleteHistory(index)) then return end
  local open = Ledger.historyIndex
  if open == index then
    Ledger.historyIndex = nil
  elseif open and open > index then
    Ledger.historyIndex = open - 1
  end
  Ledger.refresh()
end

-- Merges the History session at `index` with the next older one. The merged
-- session is opened when one of the two was.
function Ledger.mergeHistory(index)
  if not (ns.Core and ns.Core.mergeHistory(index)) then return end
  local open = Ledger.historyIndex
  if open == index or open == index + 1 then
    Ledger.historyIndex = index
  elseif open and open > index + 1 then
    Ledger.historyIndex = open - 1
  end
  Ledger.refresh()
end

-- Asks for the note of a History session (`entry`, the saved table).
function Ledger.editNote(entry)
  ns.UI.Widgets.prompt(L_NOTE_PROMPT, L_SAVE, ns.History.note(entry) or "", function(text)
    ns.History.setNote(entry, text)
    Ledger.refresh()
  end)
end

function Ledger.ignoreItem(row)
  if not (ns.Core and ns.Core.ignoreItem(row.id, row.name)) then return end
  ns.Util.say(string.format(L_IGNORED, row.link or row.name or tostring(row.id)))
end

-- Right-click menu of a row: a History session (note, delete) or an item (ignore).
-- Returns the menu entries, or nil when the row has none.
function Ledger.rowMenu(row)
  if row.historyIndex then
    local entry, index = row.entry, row.historyIndex
    local entries = {
      { text = (tostring(row.name or ""):gsub("^[%+%-] ", "")), title = true },
      { text = ns.History.note(entry) and L_EDIT_NOTE or L_ADD_NOTE, onClick = function() Ledger.editNote(entry) end },
    }
    -- Merging always takes the next older session (by start), whatever the sort.
    if ns.Core and ns.Core.canMergeHistory(index) then
      entries[#entries + 1] = { text = L_MERGE, onClick = function() Ledger.mergeHistory(index) end }
    end
    entries[#entries + 1] = { text = L_DELETE, onClick = function() Ledger.deleteHistory(index) end }
    return entries
  end
  if type(row.id) == "number" and row.id > 0 and not row.isCurrency and not row.zoneKey then
    local entries = {
      { text = row.name, title = true },
      { text = L_IGNORE, onClick = function() Ledger.ignoreItem(row) end },
    }
    -- Bags and Bank: the keep list (kept items count apart in the footer).
    local Core = ns.Core
    if Ledger.view and Ledger.view.kind == "inventory" and Core then
      if Core.keptItems()[row.id] ~= nil then
        entries[#entries + 1] = { text = L_UNKEEP, onClick = function() Core.unkeepItem(row.id) end }
      else
        entries[#entries + 1] = { text = L_KEEP, onClick = function() Core.keepItem(row.id, row.name) end }
      end
    end
    return entries
  end
  return nil
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
  local hasItem = ns.UI.Tabs.hasItemFn(Ledger.tab, Ledger.subtab)
  if not hasItem then return true end
  return hasItem(itemID, currentContext(time())) and true or false
end

-- ---------------------------------------------------------------------------
-- Setup

local rowsPart = {}
function rowsPart:Update(view)
  list:SetData(view.rows, view.empty)
end
function rowsPart:Relayout()
  list:Relayout()
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
  if UI.Fonts then UI.Fonts.install(ns.db) end -- before any text is created
  local frame = UI.Window.create(ns.db)
  if not frame then return nil end
  Ledger.frame = frame

  local Rows = UI.Rows
  local function applyMinWidth(measured)
    UI.Window.setMinWidth(Rows.requiredRowWidth(measured))
  end
  list = Rows.attach(frame.listArea, applyMinWidth)
  Ledger.list = list
  -- Left-click opens History sessions and Zones places; right-click opens the
  -- row's menu (Ledger.rowMenu) at the row.
  list.onRowClick = function(row, button, frame)
    if button == "RightButton" then
      local entries = Ledger.rowMenu(row)
      if entries then UI.Widgets.openMenu(frame, entries, "button") end
    elseif row.historyIndex then
      Ledger.toggleHistory(row.historyIndex)
    elseif row.zoneKey then
      Ledger.toggleZone(row.zoneKey, row.subKey)
    end
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
    UI.FilterBar.attach(frame.header.row2, ns.db, Ledger.refresh,
      { get = Ledger.currentSort, set = Ledger.setSort })
  end)

  attach(UI.Tabs, function()
    Ledger.tabs = UI.Tabs.attach(frame.header.row3, Ledger.setTab)
  end)

  attach(UI.DailyFarm, function()
    UI.DailyFarm.attach(frame.header.rowFarm)
  end)

  -- One sub-tab strip per tab that has sub-tabs, on header row 4.
  attach(UI.Tabs, function()
    Ledger.subtabStrips = {}
    local row = frame.header.row4
    if not row then return end
    for _, key in ipairs(UI.Tabs.KEYS) do
      local subs = UI.Tabs.subtabs(key)
      if subs then
        local holder = CreateFrame("Frame", nil, row)
        holder:SetAllPoints(row)
        local items = {}
        for i, sub in ipairs(subs) do items[i] = { key = sub.key, label = sub.label } end
        local strip = UI.Tabs.strip(holder, items, Ledger.setSubtab)
        strip.frame = holder
        holder:Hide()
        Ledger.subtabStrips[key] = strip
      end
    end
  end)

  attach(UI.Compact, function()
    if frame.compact then UI.Compact.attach(frame.compact) end
  end)
  UI.Window.onTitleDoubleClick = Ledger.toggleMode

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
  Ledger.subtab = savedSubtab(Ledger.tab)
  applyTab(Ledger.tab)

  -- The saved layout mode (anything else starts full).
  local mode = ns.db and ns.db.mode == "compact" and "compact" or "full"
  if ns.db then ns.db.mode = mode end
  Ledger.mode = mode
  UI.Window.applyMode(mode)
  local header = UI.Header and UI.Header.instance
  if header and header.SetMode then header:SetMode(mode) end
  Ledger.applyModeTitle()

  Ledger.refresh()
  return frame
end

ns.UI.refresh = Ledger.refresh
ns.UI.flash = Ledger.flash
