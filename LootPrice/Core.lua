local ADDON, ns = ...

local L = ns.L

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
local currencyPatterns -- LootParse currency patterns, built lazily likewise
local refreshPending = false
local bankOpen = false
-- Windows that put bought / traded / mailed items into the bags while open
-- (their "You receive item" messages are not loot). [event base] = open.
local tradeWindows = {}
local lastInstance -- instance key of the last loading screen (option "instanceSession")
-- The open loot window: { money = GetMoney() at opening, chat = copper the
-- money messages counted since }, or nil (see "Raw gold backstop").
local lootWindow
local LOOT_SETTLE_SECONDS = 1 -- late PLAYER_MONEY / chat after the window closed

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

  local sources, disenchant, market = {}, nil, nil
  local keyOfName = {} -- source name (stored with a cached price) -> option key
  for _, spec in ipairs(Sources.list()) do
    local source = spec.create(env, setting)
    keyOfName[source.name] = spec.key
    sources[#sources + 1] = Sources.gate(source, spec.key, selected)
    -- Sale rate / sold per day: from the first source that offers them, not
    -- gated by the price source option (TSM data also helps next to Auctionator).
    if not market and spec.createMarket then market = spec.createMarket(env, setting) end
    -- Disenchant value: from the first source that offers one.
    if not disenchant and spec.createDisenchant then
      disenchant = Sources.gate(spec.createDisenchant(env, setting), spec.key, selected).get
    end
  end

  return ns.Prices.new({
    sources = sources,
    vendor = function(itemID, link) return Sources.Vendor.get(env, itemID, link) end,
    disenchant = disenchant,
    market = market,
    cache = db.cache,
    -- A cached price only counts while its source may answer (AH price source).
    cacheAllowed = function(name)
      local key = keyOfName[name]
      return key == nil or Sources.allowed(selected(), key)
    end,
    key = getKey,
    now = now,
  })
end

-- Price lookup that never errors: nil before login is done or when a source
-- fails. `link` (optional) prices the exact item variant.
function Core.lookupPrice(itemID, link)
  local prices = ns.prices
  if not prices then return nil end
  local ok, info = pcall(prices.lookup, prices, itemID, link)
  return ok and info or nil
end

-- Unit value of a price lookup: the best of vendor, AH and disenchant.
function Core.unitValue(info)
  if type(info) ~= "table" then return nil end
  return (ns.View.best(info.vendor, info.ah, info.de))
end

-- What a session is worth now: every item at its best unit value plus the raw
-- gold (copper). Reset asks first above Session.LARGE_SESSION_VALUE.
function Core.sessionValue(session)
  if type(session) ~= "table" then return 0 end
  local total = ns.Session.goldTotal(session)
  for _, it in pairs(session.items or {}) do
    if type(it) == "table" and ns.Util.isNumber(it.qty) then
      local unit = Core.unitValue(Core.lookupPrice(it.id, it.link))
      if unit then total = total + unit * it.qty end
    end
  end
  return total
end

-- ---------------------------------------------------------------------------
-- Where the player is (History: zone or instance per session)

-- The difficulty name of an instance: GetInstanceInfo's, else
-- GetDifficultyInfo(difficultyID), else the last one seen in that instance
-- (`remembered`, by instance name). While loading, the client may report no
-- difficulty; without the fallbacks one dungeon would show up as two places.
-- UNVERIFIED (check in client): GetDifficultyInfo(id) returns the name first.
local function difficultyOf(env, name, difficultyID, difficultyName, remembered)
  local text = type(difficultyName) == "string" and difficultyName ~= "" and difficultyName or nil
  if not text and type(env.GetDifficultyInfo) == "function" and difficultyID then
    local ok, v = pcall(env.GetDifficultyInfo, difficultyID)
    if ok and type(v) == "string" and v ~= "" then text = v end
  end
  if remembered then
    if text then remembered[name] = text else text = remembered[name] end
  end
  return text
end

local difficulties = {} -- instance name -> last difficulty name seen

-- Pure over `env` (and `remembered`, a table the caller keeps; optional).
-- Returns the place label ("Zone", or "Instance (Difficulty)") and an instance
-- key (the instance name; nil outside instances).
-- GetInstanceInfo gives name, instanceType, difficultyID, difficultyName.
function Core.placeOf(env, remembered)
  if type(env.GetInstanceInfo) == "function" then
    local ok, name, instanceType, difficultyID, difficultyName = pcall(env.GetInstanceInfo)
    if ok and type(name) == "string" and name ~= "" and instanceType ~= nil and instanceType ~= "none" then
      local difficulty = difficultyOf(env, name, difficultyID, difficultyName, remembered)
      if difficulty then return name .. " (" .. difficulty .. ")", name end
      return name, name
    end
  end
  local zone
  for _, fn in ipairs({ "GetRealZoneText", "GetZoneText" }) do
    if not zone and type(env[fn]) == "function" then
      local ok, v = pcall(env[fn])
      if ok and type(v) == "string" and v ~= "" then zone = v end
    end
  end
  return zone, nil
end

-- Pure over `env`: the subzone label, or `zone` when there is none.
-- GetSubZoneText is "" in places without a subzone.
function Core.subzoneOf(env, zone)
  if type(env.GetSubZoneText) == "function" then
    local ok, v = pcall(env.GetSubZoneText)
    if ok and type(v) == "string" and v ~= "" then return v end
  end
  return zone
end

-- Pure over `env`: the player's map position as mapID, x, y (0..1), or nil
-- (inside instances, or when the client has none: 0,0 means unknown).
-- C_Map.GetBestMapForUnit("player") and
-- C_Map.GetPlayerMapPosition(mapID, "player"):GetXY() (0..1).
local function readPosition(env)
  local api = env.C_Map
  if type(api) ~= "table" or type(api.GetBestMapForUnit) ~= "function"
    or type(api.GetPlayerMapPosition) ~= "function" then return nil end
  local mapID = api.GetBestMapForUnit("player")
  if type(mapID) ~= "number" then return nil end
  local pos = api.GetPlayerMapPosition(mapID, "player")
  if type(pos) ~= "table" or type(pos.GetXY) ~= "function" then return nil end
  local x, y = pos:GetXY()
  return mapID, x, y
end

local function inUnit(v) return type(v) == "number" and v == v and v >= 0 and v <= 1 end

-- Inside any instance (dungeon, raid, scenario, delve) there is no farm spot to
-- go back to from outside: no position. Same instance test as Core.placeOf.
local function inInstance(env)
  if type(env.GetInstanceInfo) ~= "function" then return false end
  local ok, _, instanceType = pcall(env.GetInstanceInfo)
  return ok and instanceType ~= nil and instanceType ~= "none"
end

function Core.positionOf(env)
  if type(env) ~= "table" or inInstance(env) then return nil end
  local ok, mapID, x, y = pcall(readPosition, env)
  if not ok or not mapID or not inUnit(x) or not inUnit(y) or (x == 0 and y == 0) then return nil end
  return mapID, x, y
end

local function notePosition()
  if ns.session then ns.Session.notePlacePos(ns.session, Core.positionOf(_G)) end
end

-- History Zones: tells the session where the player is now (zone and
-- subzone). Returns the place label (Core.placeOf), or nil.
function Core.updatePlace()
  if not ns.session then return nil end
  local zone = Core.placeOf(_G, difficulties)
  ns.Session.enterPlace(ns.session, zone, Core.subzoneOf(_G, zone), time())
  return zone
end

-- One loot or gold event: the place is current, counted for History and,
-- unless `noSpot`, the spot on the map remembered.
local function notePlace(noSpot)
  local place = Core.updatePlace()
  if not ns.session then return end
  ns.Session.notePlace(ns.session, place)
  if not noSpot then notePosition() end
end

-- ---------------------------------------------------------------------------
-- Loot capture

-- Pure. Whether an item message of `kind` ("loot", "pushed", "created" or
-- nil) counts as loot. Crafted items and items received while a merchant,
-- mailbox, trade or auction house window is open only count with the option
-- "countCrafted". `windowOpen` says whether such a window is open.
function Core.countsAsLoot(kind, countCrafted, windowOpen)
  if countCrafted then return true end
  if kind == "created" then return false end
  if kind == "pushed" and windowOpen then return false end
  return true
end

local function tradeWindowOpen()
  return next(tradeWindows) ~= nil
end

-- Loot, gold and currencies are not counted while the clock is stopped: one
-- chat line per stop says so (cleared when the clock runs again).
local pausedNoted = false
local function notCounted()
  if not ns.session or ns.session.running then return false end
  if not pausedNoted then
    pausedNoted = true
    say(L["the clock is stopped: loot is not counted. /lp start or the Start button starts it."])
  end
  return true
end

function Core.recordLoot(link, qty, kind)
  if not ns.session then return end
  local countCrafted = ns.Util.setting("countCrafted", false)
  if not Core.countsAsLoot(kind, countCrafted, tradeWindowOpen()) then return end
  local key, itemID = ns.LootParse.itemKey(link)
  if not key or notCounted() then return end
  local added, item = ns.Session.add(ns.session, itemID, link, qty, time(), key)
  if not added then return end
  notePlace()
  ns.Session.notePlaceLoot(ns.session, key, qty)
  ns.Session.noteRecent(ns.session, key, qty, time())
  local info = Core.lookupPrice(itemID, link)
  ns.Session.setPrice(item, info)
  local unitValue = Core.unitValue(info)
  if ns.UI and ns.UI.flash then
    -- flash refreshes the ledger itself (once per frame, however much dropped)
    ns.UI.flash(key, ns.View.flashLevel(unitValue, qty))
  else
    refreshUI()
  end
  Core.alertIfValuable(link, qty, unitValue)
end

-- Currency income (CHAT_MSG_CURRENCY).
function Core.recordCurrency(currencyID, link, qty)
  if not ns.session or notCounted() then return end
  if not ns.Session.addCurrency(ns.session, currencyID, link, qty, time()) then return end
  requestRefresh(0)
end

-- Pure. Is a drop of `unitValue` x `qty` copper worth an alert at `gold` (the
-- option "alertGold"; 0 or less = off)?
function Core.alertWorthy(unitValue, qty, gold)
  if not (ns.Util.isNumber(unitValue) and ns.Util.isNumber(qty) and ns.Util.isNumber(gold)) then return false end
  if gold <= 0 then return false end
  return unitValue * qty >= gold * 10000
end

-- Option "alertGold" / "alertSound": a chat line (and a sound) for a valuable drop.
function Core.alertIfValuable(link, qty, unitValue)
  if not Core.alertWorthy(unitValue, qty, ns.Util.setting("alertGold", 0)) then return end
  say(string.format(L["valuable drop: %s%s worth %s"], link, (qty or 1) > 1 and (" x" .. qty) or "",
    ns.Money.format(unitValue * qty)))
  if ns.Util.setting("alertSound", false) and type(PlaySound) == "function" then
    local kit = type(SOUNDKIT) == "table" and SOUNDKIT.UI_EPICLOOT_TOAST or nil
    if kit then PlaySound(kit) end
  end
end

-- Raw gold (looted or quest money), copper > 0. Redraws on success; gold that
-- drops together with items shares their redraw.
-- `noSpot`: the money was not picked up here (quest turn-in at the quest
-- giver), so it does not move the place's farm spot.
function Core.recordGold(copper, noSpot)
  if not ns.session or not ns.Util.isPositiveInt(copper) or notCounted() then return end
  if not ns.Session.addGold(ns.session, copper) then return end
  notePlace(noSpot)
  ns.Session.notePlaceGold(ns.session, copper)
  requestRefresh(0)
end

local function onLootMessage(text)
  if not lootPatterns then lootPatterns = ns.LootParse.compile(_G) end
  local link, qty, kind = ns.LootParse.parse(lootPatterns, text)
  if link then Core.recordLoot(link, qty, kind) end
end

local function onCurrencyMessage(text)
  if not currencyPatterns then currencyPatterns = ns.LootParse.compileCurrency(_G) end
  local id, link, qty = ns.LootParse.parseCurrency(currencyPatterns, text)
  if id then Core.recordCurrency(id, link, qty) end
end

local function onMoneyMessage(text)
  if not moneyPatterns then moneyPatterns = ns.LootParse.compileMoney(_G) end
  local copper = ns.LootParse.parseMoney(moneyPatterns, text)
  if not copper then return end
  if lootWindow then lootWindow.chat = lootWindow.chat + copper end
  Core.recordGold(copper)
end

-- ---------------------------------------------------------------------------
-- Raw gold backstop: money looted while a loot window was open that no money
-- message accounted for (a message form LootParse does not know, another
-- client language) is counted from the change of the player's money.

-- Pure. Copper gained during a loot window beyond what the messages counted;
-- 0 when nothing is missing or the amounts are unusable.
function Core.missingGold(startMoney, endMoney, chatCopper)
  local num = ns.Util.isNumber
  if not (num(startMoney) and num(endMoney)) then return 0 end
  local missing = (endMoney - startMoney) - (num(chatCopper) and chatCopper or 0)
  return missing > 0 and math.floor(missing) or 0
end

local function currentMoney()
  if type(GetMoney) ~= "function" then return nil end
  local ok, v = pcall(GetMoney)
  return ok and v or nil
end

-- Closes the bookkeeping of `window` and records what the messages missed.
local function settleLoot(window)
  if lootWindow == window then lootWindow = nil end
  local missing = Core.missingGold(window.money, currentMoney(), window.chat)
  if missing > 0 then Core.recordGold(missing) end
end

-- ---------------------------------------------------------------------------
-- Session actions (shared by the slash commands and the header buttons)

function Core.startSession()
  if not ns.session then return end
  ns.session.afkPaused = nil
  pausedNoted = false
  Core.updatePlace()
  ns.Session.start(ns.session, time())
  say(L["session started."])
  refreshUI()
end

function Core.stopSession()
  if not ns.session then return end
  ns.session.afkPaused = nil
  ns.Session.stop(ns.session, time())
  say(L["session stopped."])
  refreshUI()
end

-- Saves a finished session to the History tab (per character). Empty sessions
-- and sessions with demo loot (fake, `session.demo`) are skipped; the History
-- option decides how many are kept.
function Core.archiveSession(session)
  local History = ns.History
  if not ns.chardb or not History or type(session) ~= "table" or session.demo then return end
  local limit = ns.Util.setting("historyLimit", History.DEFAULT_LIMIT)
  if limit == 0 then return end
  local entry = History.snapshot(session, Core.lookupPrice, time())
  if not entry then return end
  if type(ns.chardb.history) ~= "table" then ns.chardb.history = {} end
  History.add(ns.chardb.history, entry, limit)
end

-- `message` (optional) replaces the chat line.
function Core.resetSession(message)
  if ns.Demo then ns.Demo.restoreCache(ns.db) end
  if not ns.session then return end
  Core.archiveSession(ns.session)
  ns.Session.reset(ns.session, time())
  say(message or L["session reset."])
  refreshUI()
end

-- Option "instanceSession": a loading screen that enters or leaves an
-- instance (or changes to another one) archives the session and starts a new
-- one. Pure decision: returns whether the instance key changed.
function Core.instanceChanged(previous, current)
  return previous ~= current
end

local function checkInstance()
  local place, key = Core.placeOf(_G, difficulties)
  local previous = lastInstance
  lastInstance = key
  if not (ns.session and ns.db and ns.Options.get(ns.db, "instanceSession")) then return end
  if not Core.instanceChanged(previous, key) then return end
  Core.resetSession(L["new session"] .. (place and (": " .. place) or "") .. ".")
end

-- Option "afkPause": stops the clock while the player is AFK and starts it
-- again when they are back (only if it was running before).
local function checkAfk()
  local session = ns.session
  if not session or type(UnitIsAFK) ~= "function" then return end
  local afk = UnitIsAFK("player") and true or false
  if afk and session.running and ns.Options.get(ns.db, "afkPause") then
    ns.Session.stop(session, time())
    session.afkPaused = true
    say(L["clock paused while you are away."])
    refreshUI()
  elseif not afk and session.afkPaused then
    session.afkPaused = nil
    pausedNoted = false
    ns.Session.start(session, time())
    say(L["clock running again."])
    refreshUI()
  end
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
  if setupDone then
    Core.updatePlace()
    checkInstance()
    return
  end
  if not ns.db then return end
  setupDone = true
  lastInstance = select(2, Core.placeOf(_G, difficulties))

  -- Old cached prices are of no use and only grow the saved file.
  ns.Prices.prune(ns.db.cache, now, ns.Prices.CACHE_MAX_AGE)

  local keep = ns.db.settings.keepSession or isReloadingUi
  local previous = ns.chardb.session
  ns.session = ns.Session.login(previous, keep, now)
  ns.chardb.session = ns.session
  ns.prices = Core.buildPrices(_G, ns.db, time, Core.cacheKey)
  -- A session that was not kept goes to History (prices are available now).
  if previous ~= ns.session then Core.archiveSession(previous) end
  Core.updatePlace()
  if ns.UI and ns.UI.Ledger then ns.UI.Ledger.init() end
  -- Before the options: LibDBIcon (if loaded) takes over the minimap button.
  if ns.UI and ns.UI.Broker then ns.UI.Broker.init() end
  ns.Options.applyAll(ns.db)
  if ns.UI and ns.UI.OptionsPanel then ns.UI.OptionsPanel.registerPage() end
  refreshUI()
end

-- History Zones: the player moved to another zone or subzone (no redraw).
-- They fire for subzone changes too.
for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
  events[event] = function() Core.updatePlace() end
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

function events.CHAT_MSG_CURRENCY(text)
  if ns.session then onCurrencyMessage(text) end
end

function events.PLAYER_FLAGS_CHANGED(unit)
  if unit == "player" then checkAfk() end
end

-- Merchant, mailbox, trade and auction house windows (see tradeWindows).
-- UNVERIFIED (check in client): these event names exist on Forever.
for _, base in ipairs({ "MERCHANT", "MAIL", "TRADE", "AUCTION_HOUSE" }) do
  events[base .. "_SHOW"] = function() tradeWindows[base] = true end
  events[base .. "_CLOSED"] = function() tradeWindows[base] = nil end
end

-- Loot window (raw gold backstop). A window that opens before the last one
-- settled settles that one first.
-- UNVERIFIED (check in client): LOOT_OPENED / LOOT_CLOSED and GetMoney on
-- Forever, and that looted money arrives before LOOT_CLOSED + 1 s.
function events.LOOT_OPENED()
  if lootWindow then settleLoot(lootWindow) end
  local money = currentMoney()
  if money and ns.session then lootWindow = { money = money, chat = 0 } end
end

function events.LOOT_CLOSED()
  local window = lootWindow
  if not window then return end
  if C_Timer and C_Timer.After then
    C_Timer.After(LOOT_SETTLE_SECONDS, function()
      if lootWindow == window then settleLoot(window) end
    end)
  else
    settleLoot(window)
  end
end

-- moneyReward is copper; 0, nil and non-numbers are ignored by Session.addGold.
function events.QUEST_TURNED_IN(questID, xpReward, moneyReward)
  if ns.session then Core.recordGold(moneyReward, true) end
end

-- Only items on the shown tab matter; the event fires for every item query
-- of every addon.
function events.GET_ITEM_INFO_RECEIVED(itemID)
  local ledger = ns.UI and ns.UI.Ledger
  local wanted
  if ledger and ledger.wantsItemInfo then
    wanted = ledger.wantsItemInfo(itemID)
  else
    wanted = ns.session ~= nil and ns.Session.hasItemID(ns.session.items, itemID)
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

-- The bank's own slots and the reagent bank (older clients) fire these
-- instead of BAG_UPDATE_DELAYED.
function events.PLAYERBANKSLOTS_CHANGED()
  if bankOpen then Core.scanBank(true) end
end

function events.PLAYERREAGENTBANKSLOTS_CHANGED()
  if bankOpen then Core.scanBank(true) end
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
  -- An event this client does not know raises an error: skip it.
  for event in pairs(events) do pcall(frame.RegisterEvent, frame, event) end
  frame:SetScript("OnEvent", function(_, event, ...)
    local handler = events[event]
    if handler then handler(...) end
  end)
  Core.frame = frame
  if ns.Slash then ns.Slash.register() end
end

if type(_G.CreateFrame) == "function" then Core.init() end
