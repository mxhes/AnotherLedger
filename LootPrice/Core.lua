local ADDON, ns = ...

-- The addon's event core: creates the session and the price lookup at login,
-- records loot and gold, scans the bank, and tells the UI when to redraw.
-- Slash commands live in Slash.lua, the /lp demo data in Demo.lua.
local Core = {}
ns.Core = Core

local say = ns.Util.say

local REFRESH_THROTTLE = 0.2 -- seconds: bursts of item info / bag events share one redraw
local KEY_RETRY_SECONDS = 10

local keyState = { key = nil } -- { key, tried }: the price cache key, see keyFromState
local setupDone = false -- session/prices/UI are created once per Lua session
local lootPatterns -- LootParse patterns, built once from the real globals
local moneyPatterns -- LootParse money patterns, built lazily likewise
local refreshPending = false
local bankOpen = false

-- ---------------------------------------------------------------------------
-- UI notifications

local function refreshUI()
  if ns.UI and ns.UI.refresh then ns.UI.refresh() end
end

-- One redraw after `delay` seconds for any number of requests in between.
local function requestRefresh(delay)
  if refreshPending then return end
  if not (C_Timer and C_Timer.After) then
    refreshUI()
    return
  end
  refreshPending = true
  C_Timer.After(delay or REFRESH_THROTTLE, function()
    refreshPending = false
    refreshUI()
  end)
end

-- Data of kind `what` ("bags", "bank") changed: redraw if the shown tab lists it.
local function dataChanged(what)
  local ledger = ns.UI and ns.UI.Ledger
  if ledger and ledger.dataChanged(what) then requestRefresh() end
end

-- ---------------------------------------------------------------------------
-- Price cache key and price lookup (take the global environment as a
-- parameter, testable)

-- Region/game-mode cache key, or nil while either part is unavailable.
-- Both engine calls may be missing on the Forever client, hence pcall.
function Core.evalKey(env)
  local region, modeID
  -- UNVERIFIED (check in client): GetCurrentRegionName exists and returns a region string.
  if type(env.GetCurrentRegionName) == "function" then
    local ok, v = pcall(env.GetCurrentRegionName)
    if ok then region = v end
  end
  -- UNVERIFIED (check in client): C_GameRules.GetCurrentGameModeRecordID exists on Forever.
  local rules = env.C_GameRules
  if type(rules) == "table" and type(rules.GetCurrentGameModeRecordID) == "function" then
    local ok, v = pcall(rules.GetCurrentGameModeRecordID)
    if ok then modeID = v end
  end
  return ns.Prices.cacheKey(region, modeID)
end

-- Lazily re-evaluates a nil key (the game mode may be unknown right after
-- login), at most once per KEY_RETRY_SECONDS. `state` = { key, tried }.
function Core.keyFromState(state, env, now)
  if state.key == nil and (state.tried == nil or now - state.tried >= KEY_RETRY_SECONDS) then
    state.tried = now
    state.key = Core.evalKey(env)
  end
  return state.key
end

-- The current price cache key (nil while region / game mode are unknown).
function Core.cacheKey()
  return Core.keyFromState(keyState, _G, time())
end

-- Builds the Prices object over `env` (_G in the client) from the registered
-- price sources (Sources/Sources.lua). `getKey` returns the current cache key;
-- the settings (price source option, TSM price string) are read live from
-- db.settings, so changing them needs no rebuild.
function Core.buildPrices(env, db, now, getKey)
  local Sources = ns.Sources
  local function setting(key) return db.settings[key] end
  local function selected() return db.settings.priceSource end

  local sources, disenchant = {}, nil
  for _, spec in ipairs(Sources.list()) do
    sources[#sources + 1] = Sources.gate(spec.create(env, setting), spec.key, selected)
    -- Disenchant value: from the first source that offers one.
    if not disenchant and spec.createDisenchant then
      disenchant = Sources.gate(spec.createDisenchant(env, setting), spec.key, selected).get
    end
  end

  return ns.Prices.new({
    sources = sources,
    vendor = function(itemID) return Sources.Vendor.get(env, itemID) end,
    disenchant = disenchant,
    cache = db.cache,
    key = getKey,
    now = now,
  })
end

-- Price lookup that never errors: nil before login is done or when a source fails.
function Core.lookupPrice(itemID)
  local prices = ns.prices
  if not prices then return nil end
  local ok, info = pcall(prices.lookup, prices, itemID)
  return ok and info or nil
end

-- ---------------------------------------------------------------------------
-- Loot capture

function Core.recordLoot(link, qty)
  local itemID = ns.LootParse.itemID(link)
  if not itemID or not ns.session then return end
  if not ns.Session.add(ns.session, itemID, link, qty, time()) then return end
  if ns.UI and ns.UI.flash then
    -- flash refreshes the ledger itself (once per frame, however much dropped)
    local info = Core.lookupPrice(itemID)
    local unitValue = info and (info.ah or info.vendor)
    ns.UI.flash(itemID, ns.View.flashLevel(unitValue, qty))
  else
    refreshUI()
  end
end

-- Raw gold (looted or quest money), copper > 0. Redraws on success; gold that
-- drops together with items shares their redraw.
function Core.recordGold(copper)
  if not ns.session then return end
  if not ns.Session.addGold(ns.session, copper, time()) then return end
  requestRefresh(0)
end

local function onLootMessage(text)
  if not lootPatterns then lootPatterns = ns.LootParse.compile(_G) end
  local link, qty = ns.LootParse.parse(lootPatterns, text)
  if link then Core.recordLoot(link, qty) end
end

local function onMoneyMessage(text)
  if not moneyPatterns then moneyPatterns = ns.LootParse.compileMoney(_G) end
  local copper = ns.LootParse.parseMoney(moneyPatterns, text)
  if copper then Core.recordGold(copper) end
end

-- ---------------------------------------------------------------------------
-- Session actions (shared by the slash commands and the header buttons)

function Core.startSession()
  if not ns.session then return end
  ns.Session.start(ns.session, time())
  say("session started.")
  refreshUI()
end

function Core.stopSession()
  if not ns.session then return end
  ns.Session.stop(ns.session, time())
  say("session stopped.")
  refreshUI()
end

-- Saves a finished session to the History tab (per character). Empty sessions
-- are skipped; the History option decides how many are kept.
function Core.archiveSession(session)
  local History = ns.History
  if not ns.chardb or not History or type(session) ~= "table" then return end
  local limit = ns.Options and ns.db and ns.Options.get(ns.db, "historyLimit") or History.DEFAULT_LIMIT
  if limit == 0 then return end
  local entry = History.snapshot(session, Core.lookupPrice, time())
  if not entry then return end
  if type(ns.chardb.history) ~= "table" then ns.chardb.history = {} end
  History.add(ns.chardb.history, entry, limit)
end

function Core.resetSession()
  -- Demo loot is fake: it is not worth keeping in History.
  local Demo = ns.Demo
  local wasDemo = Demo ~= nil and Demo.active()
  if Demo then Demo.restoreCache(ns.db) end
  if not ns.session then return end
  if not wasDemo then Core.archiveSession(ns.session) end
  ns.Session.reset(ns.session, time())
  say("session reset.")
  refreshUI()
end

-- ---------------------------------------------------------------------------
-- Bank scan

-- Bank contents can only be read while the bank window is open: scan while it
-- is, keep the last scan (per character) for the Bank tab. A first scan that
-- comes back empty right at opening is ignored when a scan is saved already
-- (the slots may not be loaded yet); later scans of the same visit are trusted.
function Core.scanBank(trustEmpty)
  local chardb = ns.chardb
  if not chardb then return end
  local now = time()
  local items = ns.Inventory.scanBank(_G, now)
  local saved = chardb.bank
  if next(items) == nil and not trustEmpty and saved and next(saved.items) ~= nil then return end
  chardb.bank = { scannedAt = now, items = items }
  dataChanged("bank")
end

-- ---------------------------------------------------------------------------
-- Events: one function per event, registered automatically by Core.init.

local events = {}

function events.ADDON_LOADED(name)
  if name ~= ADDON then return end
  LootPriceDB = ns.DB.applyDefaults(LootPriceDB, ns.DB.defaults)
  LootPriceCharDB = ns.DB.applyDefaults(LootPriceCharDB, ns.DB.charDefaults)
  ns.db = LootPriceDB
  ns.chardb = LootPriceCharDB
end

-- The session is created on the first PLAYER_ENTERING_WORLD of the Lua
-- session: a real login starts fresh (unless "keep" is on), a /reload
-- (isReloadingUi) always keeps it. Later firings (zone changes, instances)
-- only re-evaluate the cache key.
function events.PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
  local now = time()
  keyState.key = Core.evalKey(_G)
  keyState.tried = now
  if setupDone or not ns.db then return end
  setupDone = true

  -- Old cached prices are of no use and only grow the saved file.
  ns.Prices.prune(ns.db.cache, now, ns.Prices.CACHE_MAX_AGE)

  local keep = ns.db.settings.keepSession or isReloadingUi
  local previous = ns.chardb.session
  ns.session = ns.Session.login(previous, keep, now)
  ns.chardb.session = ns.session
  ns.prices = Core.buildPrices(_G, ns.db, time, Core.cacheKey)
  -- A session that was not kept goes to History (prices are available now).
  if previous ~= ns.session then Core.archiveSession(previous) end
  if ns.UI and ns.UI.Ledger then ns.UI.Ledger.init() end
  ns.Options.applyAll(ns.db)
  refreshUI()
end

-- Combat auto hide / show (option "combatHide"): hides the window when combat
-- starts and shows it again when combat ends, but only if it was shown before.
function events.PLAYER_REGEN_DISABLED()
  local window = ns.UI and ns.UI.Window
  if window and ns.db and ns.db.settings.combatHide then window.combatHide() end
end

function events.PLAYER_REGEN_ENABLED()
  local window = ns.UI and ns.UI.Window
  if window then window.combatShow() end
end

function events.CHAT_MSG_LOOT(text)
  if ns.session then onLootMessage(text) end
end

function events.CHAT_MSG_MONEY(text)
  if ns.session then onMoneyMessage(text) end
end

-- moneyReward is copper; 0, nil and non-numbers are ignored by Session.addGold.
function events.QUEST_TURNED_IN(questID, xpReward, moneyReward)
  if ns.session then Core.recordGold(moneyReward) end
end

-- Only items on the shown tab matter; the event fires for every item query
-- of every addon.
function events.GET_ITEM_INFO_RECEIVED(itemID)
  local ledger = ns.UI and ns.UI.Ledger
  local wanted
  if ledger and ledger.wantsItemInfo then
    wanted = ledger.wantsItemInfo(itemID)
  else
    wanted = ns.session ~= nil and ns.session.items[itemID] ~= nil
  end
  if wanted then requestRefresh() end
end

function events.BANKFRAME_OPENED()
  bankOpen = true
  Core.scanBank(false)
end

function events.BANKFRAME_CLOSED()
  bankOpen = false
end

function events.BAG_UPDATE_DELAYED()
  if bankOpen then Core.scanBank(true) end
  dataChanged("bags")
end

function events.PLAYER_LOGOUT()
  if ns.Demo then ns.Demo.restoreCache(ns.db) end
  if ns.session then
    ns.Session.suspend(ns.session, time())
    ns.chardb.session = ns.session
  end
end

Core.events = events

function Core.init()
  local frame = CreateFrame("Frame")
  for event in pairs(events) do frame:RegisterEvent(event) end
  frame:SetScript("OnEvent", function(_, event, ...)
    local handler = events[event]
    if handler then handler(...) end
  end)
  Core.frame = frame
  if ns.Slash then ns.Slash.register() end
end

if type(_G.CreateFrame) == "function" then Core.init() end
