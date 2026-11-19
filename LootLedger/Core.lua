local ADDON, ns = ...

local L = ns.L

-- The addon's event core: creates the session and the price lookup at login,
-- records loot and gold, scans the bank, and tells the UI when to redraw.
-- Slash commands live in Slash.lua, the /ll demo data in Demo.lua.
local Core = {}
ns.Core = Core
-- Counts the loot windows read (mob data changed); UI/ItemTooltip.lua
-- rebuilds its drop index when it moves.
Core.mobsVersion = 0

local say = ns.Util.say
local num = ns.Util.isNumber

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
local restingSeen = false -- the resting state Core.checkRest saw last (option "hideInCities")
-- Mobs (Mobs.lua): the open loot window's slots, mob names seen this login
-- ({ [mob key] = name }) and the corpses looted. Never saved.
local lootSlots
local mobNames = {}
local mobState = {}
-- The player's last cast target ({ name, at }; UNIT_SPELLCAST_SENT): a
-- gathering cast names the node of the loot window that follows.
local castTarget
local NODE_CAST_SECONDS = 30
local zoneState = {} -- the session's zone and a pending new one (Core.zoneSwitch)
-- The open loot window: { money = GetMoney() at opening, chat = copper the
-- money messages counted since }, or nil (see "Raw gold backstop").
local lootWindow
local LOOT_SETTLE_SECONDS = 1 -- late PLAYER_MONEY / chat after the window closed
local HEARTBEAT_SECONDS = 5 -- Core.heartbeat: time goal, zone delay, rate graph

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
  if type(env.GetCurrentRegionName) == "function" then
    local ok, v = pcall(env.GetCurrentRegionName)
    if ok then region = v end
  end
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
  -- db.settings is nil after logout (Profiles.beforeLogout).
  local function setting(key) return db.settings and db.settings[key] end
  local function selected() return setting("priceSource") end

  local sources, disenchant, market = {}, nil, nil
  local keyOfName = {} -- source name (stored with a cached price) -> option key
  for _, spec in ipairs(Sources.list()) do
    local source = spec.create(env, setting)
    keyOfName[source.name] = spec.key
    sources[#sources + 1] = Sources.gate(source, spec.key, selected)
    -- Sale rate / sold per day: from the first source that offers them, not
    -- gated by the price source option (TSM data also helps next to Auctionator).
    if not market and spec.createMarket then market = spec.createMarket(env, setting) end
    -- Disenchant value: from the first source that offers one. Not gated
    -- either: only TSM has destroy values, and AH source = Auctionator must
    -- not quietly turn them off (the option Destroy values decides).
    if not disenchant and spec.createDisenchant then
      disenchant = spec.createDisenchant(env, setting).get
    end
  end

  -- Value rules, read at every lookup (options ahCut and destroyMode); the
  -- same table until one of the options changes.
  local cached
  local function rules()
    local cut, mode = setting("ahCut") ~= false, setting("destroyMode")
    if not (cached and cached.ahCut == cut and cached.mode == mode) then
      cached = {
        ahCut = cut, mode = mode,
        destroyAllowed = function(itemID, link) return Core.destroyAllowed(env, db, mode, itemID, link) end,
      }
    end
    return cached
  end

  return ns.Prices.new({
    sources = sources,
    rules = rules,
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

-- One chat line, once per account, when no auction price addon is loaded
-- (Sources `present`): without one every item counts at its vendor price.
-- `db.priceHintShown` is cleared again once an addon is found, so removing it
-- later brings the hint back once. Returns whether it printed.
local L_NO_PRICE_ADDON = L["No auction price addon found: items count at their vendor price. Scan the auction house with /ll scan, or install TSM or Auctionator."]

function Core.priceAddonHint(env, db, say)
  if type(db) ~= "table" then return false end
  if ns.Sources.anyPresent(env) then
    db.priceHintShown = nil
    return false
  end
  if db.priceHintShown then return false end
  -- Prices from LootLedger's own scan for this realm: no hint needed.
  local bucket = ns.Scan and ns.Scan.bucket(db, ns.Scan.currentRealmKey())
  if bucket and next(bucket.items) ~= nil then return false end
  db.priceHintShown = true
  say(L_NO_PRICE_ADDON)
  return true
end

-- Destroy professions (Enchanting, Inscription, Jewelcrafting) of the
-- logged-in character: { enchanting = true, ... }. GetProfessions returns the
-- profession indices; GetProfessionInfo's 7th return is the skill line.
function Core.professions(env)
  local lines = {}
  if type(env.GetProfessions) ~= "function" or type(env.GetProfessionInfo) ~= "function" then
    return ns.Prices.professionSet(lines)
  end
  local ok, a, b, c, d, e = pcall(env.GetProfessions)
  if not ok then return ns.Prices.professionSet(lines) end
  for _, index in ipairs({ a or false, b or false, c or false, d or false, e or false }) do
    if index then
      local got, _, _, _, _, _, _, skillLine = pcall(env.GetProfessionInfo, index)
      if got and type(skillLine) == "number" then lines[#lines + 1] = skillLine end
    end
  end
  return ns.Prices.professionSet(lines)
end

-- The profession sets Core.destroyAllowed adds up, kept until they change:
-- { db, set = db.professions, key, all, own }.
local professionCache

-- Saves this character's destroy professions (login, SKILL_LINES_CHANGED).
-- At login (`atLogin`) the client may not know them yet: an empty read then
-- keeps the saved set; SKILL_LINES_CHANGED is the game's own word.
function Core.noteProfessions(atLogin)
  local key = Core.character or Core.characterKey(_G)
  if not (key and ns.db) then return end
  if type(ns.db.professions) ~= "table" then ns.db.professions = {} end
  local set, old = Core.professions(_G), ns.db.professions[key]
  if atLogin and next(set) == nil and type(old) == "table" and next(old) ~= nil then return end
  ns.db.professions[key] = set
  professionCache = nil
end

-- All characters' destroy professions and this character's (cached).
local function professionSets(db, key)
  local saved = type(db.professions) == "table" and db.professions or nil
  local c = professionCache
  if c and c.db == db and c.set == saved and c.key == key then return c.all, c.own end
  local all, own = {}, nil
  for character, set in pairs(saved or {}) do
    if type(set) == "table" then
      for k, v in pairs(set) do if v then all[k] = true end end
      if character == key then own = set end
    end
  end
  professionCache = { db = db, set = saved, key = key, all = all, own = own or {} }
  return all, professionCache.own
end

-- Option "destroyMode": whether an item's destroy value counts. The kind of
-- destroy follows the item's class (C_Item.GetItemInfoInstant: 6th and 7th
-- returns).
function Core.destroyAllowed(env, db, mode, itemID, link)
  if mode ~= "any" and mode ~= "self" then return mode ~= "never" end
  local kind
  local C = env.C_Item
  local info = type(C) == "table" and C.GetItemInfoInstant or env.GetItemInfoInstant
  if type(info) == "function" then
    local ok, _, _, _, _, _, classID, subclassID = pcall(info, link or itemID)
    if ok then kind = ns.Prices.destroyKind(classID, subclassID) end
  end
  local all, own = professionSets(db, Core.character or Core.characterKey(env))
  return ns.Prices.destroyAllowed(mode, kind, own, all)
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
  return (ns.Prices.best(info.vendor, info.ah, info.de, ns.Util.setting("ahMinGain", 0)))
end

-- What a session is worth now: every item valued like its list row (live
-- prices, else the ones seen at loot time) plus the raw gold (copper;
-- `withoutGold`: the items only). Ignored items do not count. Reset asks
-- first above Session.LARGE_SESSION_VALUE.
function Core.sessionValue(session, withoutGold)
  if type(session) ~= "table" then return 0 end
  local total = withoutGold and 0 or ns.Session.goldTotal(session)
  local ignored = Core.ignoredItems()
  local gain = ns.Util.setting("ahMinGain", 0)
  for _, it in pairs(session.items or {}) do
    if type(it) == "table" and ns.Util.isNumber(it.id) and ns.Util.isNumber(it.qty) and not ignored[it.id] then
      total = total + ns.View.itemValue(it, Core.lookupPrice, gain)
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
-- GetDifficultyInfo(id) returns the name first.
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
    say(L["the clock is stopped: loot is not counted (History > Mobs still counts it). /ll start or the Start button starts it."])
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
  -- Option "showOnLoot": the session's first item opens the window.
  if ns.Session.itemCount(ns.session) == 1 and item.qty == qty then Core.autoWindow("show", "loot", "showOnLoot") end
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
  Core.alertIfValuable(link, qty, unitValue, itemID)
  Core.checkGoals(true)
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

-- Option "alertSound": the sound of the drop alert and the session goals.
local function alertSound()
  if ns.Util.setting("alertSound", false) and type(PlaySound) == "function" then
    local kit = type(SOUNDKIT) == "table" and SOUNDKIT.UI_EPICLOOT_TOAST or nil
    if kit then PlaySound(kit) end
  end
end

-- Option "alertGold" / "alertSound": a chat line (and a sound) for a valuable
-- drop. Ignored items never alert.
function Core.alertIfValuable(link, qty, unitValue, itemID)
  if itemID and Core.ignoredItems()[itemID] then return end
  if not Core.alertWorthy(unitValue, qty, ns.Util.setting("alertGold", 0)) then return end
  say(string.format(L["valuable drop: %s%s worth %s"], link, (qty or 1) > 1 and (" x" .. qty) or "",
    ns.Money.format(unitValue * qty)))
  alertSound()
end

-- ---------------------------------------------------------------------------
-- Session goals (options "goalGold", "goalMinutes"): a chat line (and the
-- alert sound) once the session is worth that much gold or the clock reaches
-- that many minutes. Each goal is announced once per session and value
-- (session.goalsNoted = { gold = goal, time = goal }); a new goal counts anew.

-- Pure. The goals newly reached: { gold = bool, time = bool }. `value` is
-- copper (nil: not checked), `elapsed` seconds; goals of 0 or less are off.
function Core.goalsReached(value, elapsed, goalGold, goalMinutes, noted)
  noted = type(noted) == "table" and noted or {}
  local out = { gold = false, time = false }
  if num(goalGold) and goalGold > 0 and num(value) and value >= goalGold * 10000 and noted.gold ~= goalGold then
    out.gold = true
  end
  if num(goalMinutes) and goalMinutes > 0 and num(elapsed) and elapsed >= goalMinutes * 60
    and noted.time ~= goalMinutes then
    out.time = true
  end
  return out
end

-- The goal in copper for the views (View opts.goal), or nil while it is off.
function Core.goalCopper()
  local gold = ns.Util.setting("goalGold", 0)
  if ns.Util.isNumber(gold) and gold > 0 then return gold * 10000 end
  return nil
end

-- `withValue`: also check the gold goal (after loot; the clock ticker checks
-- the time only, the session value costs a price lookup per item).
function Core.checkGoals(withValue)
  local session = ns.session
  if type(session) ~= "table" or session.demo then return end
  local setting = ns.Util.setting
  local goalGold, goalMinutes = setting("goalGold", 0), setting("goalMinutes", 0)
  local noted = type(session.goalsNoted) == "table" and session.goalsNoted or {}
  local elapsed = ns.Session.elapsed(session, time())
  local value
  if withValue and ns.Util.isNumber(goalGold) and goalGold > 0 and noted.gold ~= goalGold then
    value = Core.sessionValue(session, not ns.Util.goldCounted())
  end
  local reached = Core.goalsReached(value, elapsed, goalGold, goalMinutes, noted)
  if not (reached.gold or reached.time) then return end
  if reached.gold then
    noted.gold = goalGold
    say(string.format(L["session goal reached: %s in %s."], ns.Money.format(value), ns.History.duration(elapsed)))
  end
  if reached.time then
    noted.time = goalMinutes
    say(string.format(L["%d minutes farmed: the session is worth %s."], goalMinutes,
      ns.Money.format(Core.sessionValue(session, not ns.Util.goldCounted()))))
  end
  session.goalsNoted = noted
  alertSound()
end

-- Gold per hour graph: a sample of the session's worth (like the compact
-- total) once a sample step of running clock has passed (Session.addSample).
function Core.sampleRate()
  local session = ns.session
  if type(session) ~= "table" or session.demo or not session.running then return end
  local elapsed = ns.Session.elapsed(session, time())
  if not ns.Session.sampleDue(session, elapsed) then return end
  ns.Session.addSample(session, elapsed, Core.sessionValue(session, not ns.Util.goldCounted()))
end

-- Every HEARTBEAT_SECONDS (a ticker set up at login).
function Core.heartbeat()
  Core.checkGoals(false)
  Core.checkZone()
  Core.sampleRate()
end

-- ---------------------------------------------------------------------------
-- Item lists (account-wide, { [itemID] = name or true } in LootLedgerDB):
--   ignored: left out of every list, total, alert and goal. They are still
--            recorded, so taking one off the list brings it back everywhere.
--   kept:    items you keep (tools, gear sets): Bags and Bank split their
--            total into kept and sellable.
-- Each list has get / add / remove / sorted functions, made by itemList.

local NO_ITEMS = {}

local function itemList(field)
  local function items()
    local db = ns.db
    if not db then return NO_ITEMS end
    if type(db[field]) ~= "table" then db[field] = {} end
    return db[field]
  end
  local function add(itemID, name)
    if not ns.Util.isNumber(itemID) or itemID <= 0 or not ns.db then return false end
    items()[itemID] = type(name) == "string" and name ~= "" and name or true
    refreshUI()
    return true
  end
  local function remove(itemID)
    local list = items()
    if list[itemID] == nil then return false end
    list[itemID] = nil
    refreshUI()
    return true
  end
  -- For the options menu: { { id, name }, ... } by name.
  local function sorted()
    local out = {}
    for id, name in pairs(items()) do
      out[#out + 1] = { id = id, name = type(name) == "string" and name or (L["Item "] .. tostring(id)) }
    end
    table.sort(out, function(a, b)
      if a.name ~= b.name then return a.name < b.name end
      return a.id < b.id
    end)
    return out
  end
  return items, add, remove, sorted
end

Core.ignoredItems, Core.ignoreItem, Core.unignoreItem, Core.ignoredList = itemList("ignored")
Core.keptItems, Core.keepItem, Core.unkeepItem, Core.keptList = itemList("kept")

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
  Core.checkGoals(true)
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
  -- Mobs: the coin slots taken, scaled to the copper actually received (a
  -- group splits it); nothing received known: the whole coin.
  local pending = window.mobMoney
  if type(pending) ~= "table" then return end
  local listed = 0
  for _, p in ipairs(pending) do listed = listed + p.slot.qty end
  local received = window.chat + missing
  local factor = (received > 0 and listed > 0) and math.min(1, received / listed) or 1
  for _, p in ipairs(pending) do
    ns.Mobs.credit(p.mobs, ns.Mobs.scaleMoney(p.slot, factor), p.place, p.names, mobState)
  end
end

-- ---------------------------------------------------------------------------
-- Session actions (shared by the slash commands and the header buttons)

function Core.startSession()
  if not ns.session then return end
  ns.session.afkPaused = nil
  pausedNoted = false
  Core.updatePlace()
  ns.Session.start(ns.session, time())
  Core.checkRest()
  say(L["session started."])
  refreshUI()
end

-- Option "cityPause": rests the clock while the player is resting (city, inn)
-- and wakes it when they leave or the option is turned off. A stopped clock
-- (by hand or AFK) is never started here.
function Core.checkRest()
  local session = ns.session
  if not (session and ns.db) then return end
  local resting = type(IsResting) == "function" and IsResting() and true or false
  -- Option "hideInCities": hide on entering a resting area, show on leaving.
  if resting ~= restingSeen then
    restingSeen = resting
    if resting then Core.autoWindow("hide", "city", "hideInCities") else Core.autoWindow("undo", "city") end
  end
  local want = resting and ns.Options.get(ns.db, "cityPause") and session.running and not session.afkPaused
  if want and not session.resting then
    ns.Session.rest(session, time())
    refreshUI()
  elseif not want and session.resting then
    ns.Session.wake(session, time())
    refreshUI()
  end
end

function Core.stopSession()
  if not ns.session then return end
  ns.session.afkPaused = nil
  ns.Session.stop(ns.session, time())
  say(L["session stopped."])
  refreshUI()
end

-- Pure. The chat line of a finished session (option "sessionChat"): its
-- length, main place, worth (best value, plus the raw gold with
-- `includeGold`) and gold per hour.
function Core.sessionSummary(entry, includeGold)
  local History = ns.History
  local value = History.bestOf(entry) + (includeGold ~= false and entry.gold or 0)
  local text = string.format(L["session saved: %s"], History.duration(entry.elapsed))
  local place = History.place(entry)
  if place then text = text .. L[" in "] .. place end
  text = text .. ", " .. ns.Money.format(value)
  local rate = History.perHour(value, entry.elapsed)
  if rate then text = text .. " (" .. ns.Money.format(ns.Money.roundRate(rate)) .. L["/h"] .. ")" end
  return text .. "."
end

-- Saves a finished session to the History tab (per character). Empty sessions
-- and sessions with demo loot (fake, `session.demo`) are skipped; the History
-- option decides how many are kept. With the option "sessionChat" a chat
-- line sums the session up. Returns the saved entry, or nil.
function Core.archiveSession(session)
  local History = ns.History
  if not ns.chardb or not History or type(session) ~= "table" or session.demo then return end
  local limit = ns.Util.setting("historyLimit", History.DEFAULT_LIMIT)
  if limit == 0 then return end
  local entry = History.snapshot(session, Core.lookupPrice, time())
  if not entry then return end
  if type(ns.chardb.history) ~= "table" then ns.chardb.history = {} end
  History.add(ns.chardb.history, entry, limit)
  if ns.Util.setting("sessionChat", false) then
    say(Core.sessionSummary(entry, ns.Util.goldCounted()))
  end
  return entry
end

-- ---------------------------------------------------------------------------
-- History lists. Every character's History lives in LootLedgerDB.histories
-- ({ ["Name-Realm"] = list }), so History Zones and the Daily farm can use
-- them all; ns.chardb.history is this character's list there while logged in
-- (Core.linkHistory at login, unlinked at logout so it is not saved twice).

-- "Name-Realm" of the logged-in character, or nil while the client does not
-- know it (then History stays per character, as before).
function Core.characterKey(env)
  local name = type(env.UnitName) == "function" and env.UnitName("player") or nil
  if type(name) ~= "string" or name == "" then return nil end
  local realm = type(env.GetRealmName) == "function" and env.GetRealmName() or nil
  if type(realm) ~= "string" or realm == "" then return name end
  return name .. "-" .. realm
end

function Core.linkHistory()
  local key = Core.characterKey(_G)
  if not (key and ns.db and ns.chardb) then return end
  if type(ns.db.histories) ~= "table" then ns.db.histories = {} end
  ns.chardb.history = ns.History.adopt(ns.db.histories, key, ns.chardb.history)
  Core.character = key
  -- The options panel lists which characters use a profile.
  if ns.Profiles then ns.Profiles.noteUser(ns.db, key, ns.Profiles.active(ns.chardb)) end
end

local function historyList()
  local chardb = ns.chardb
  if not chardb then return nil end
  if type(chardb.history) ~= "table" then chardb.history = {} end
  return chardb.history
end

-- The History that Zones and the Daily farm read, and a key that changes with
-- it: every character's (option "accountZones"), else this character's.
function Core.zoneHistory()
  local own = historyList() or {}
  local all = ns.db and ns.db.histories
  if Core.character and type(all) == "table" and ns.Util.setting("accountZones", true) then
    return ns.History.combine(all)
  end
  return ns.History.combine({ own = own })
end

-- History changes of this login that /ll undo takes back, the last one last:
-- { restore = { entry, ... } (put back), drop = entry or nil (taken out
-- again: a merged session) }. Not saved, a reload or logout forgets them.
local undoStack = {}

-- Deletes the session at `index` of this character's History.
function Core.deleteHistory(index)
  local list = historyList()
  local entry = list and list[index]
  if not ns.History.remove(list, index) then return false end
  undoStack[#undoStack + 1] = { restore = { entry } }
  say(L["session deleted from History. /ll undo brings it back."])
  return true
end

-- Deletes every session of this character's History (the options' button asks first).
function Core.clearHistory()
  local list = historyList()
  if not list or #list == 0 then return false end
  local copy = {}
  for i, e in ipairs(list) do copy[i] = e end
  ns.History.clear(list)
  undoStack[#undoStack + 1] = { restore = copy }
  say(L["History cleared. /ll undo brings it back."])
  refreshUI()
  return true
end

-- Whether the session at `index` has an older one to merge with.
function Core.canMergeHistory(index)
  local list = historyList()
  local History = ns.History
  return list ~= nil and History.valid(list[index]) and History.valid(list[index + 1]) or false
end

-- Merges the session at `index` with the next older one (History is newest
-- first) into one session in their place. Returns the merged entry or nil.
function Core.mergeHistory(index)
  if not Core.canMergeHistory(index) then return nil end
  local list = historyList()
  local newer, older = list[index], list[index + 1]
  local merged = ns.History.merge(newer, older)
  if not merged then return nil end
  list[index] = merged
  table.remove(list, index + 1)
  undoStack[#undoStack + 1] = { restore = { newer, older }, drop = merged }
  say(L["sessions merged. /ll undo splits them again."])
  return merged
end

-- Takes back the last delete, clear or merge. Returns how many sessions came back.
function Core.undoDelete()
  local last = table.remove(undoStack)
  local list = historyList()
  if not (last and list) then
    say(L["nothing to undo."])
    return 0
  end
  if last.drop then
    for i = #list, 1, -1 do
      if list[i] == last.drop then table.remove(list, i) end
    end
  end
  local n = ns.History.restore(list, last.restore)
  local ledger = ns.UI and ns.UI.Ledger
  if ledger then ledger.historyIndex = nil end
  if last.drop then
    say(L["the merged session is split again."])
  else
    say(string.format(L["%d session(s) back in History."], n))
  end
  refreshUI()
  return n
end

-- `message` (optional) replaces the chat line. Returns the History entry the
-- session became, or nil (empty, demo or History off).
function Core.resetSession(message)
  if ns.Demo then ns.Demo.restoreCache(ns.db) end
  if not ns.session then return nil end
  local entry = Core.archiveSession(ns.session)
  ns.Session.reset(ns.session, time())
  say(message or L["session reset."])
  refreshUI()
  return entry
end

-- Option "instanceSession": a loading screen that enters or leaves an
-- instance (or changes to another one) archives the session and starts a new
-- one. Pure decision: returns whether the instance key changed.
function Core.instanceChanged(previous, current)
  return previous ~= current
end

-- The window's automatic show / hide (UI.Window.autoShow / autoHide /
-- autoUndo). `option` (for show and hide) must be on; undo always runs, so
-- turning the option off never leaves the window hidden.
function Core.autoWindow(action, reason, option)
  local W = ns.UI and ns.UI.Window
  if not W or not ns.db then return end
  if option and not ns.Options.get(ns.db, option) then return end
  if action == "show" then W.autoShow(reason)
  elseif action == "hide" then W.autoHide(reason)
  else W.autoUndo(reason) end
end

-- Mobs are recorded whether the clock runs or not (History > Mobs is about
-- what a mob drops, not about the session's worth); never in demo mode.
function Core.mobsCounting()
  local session = ns.session
  return session ~= nil and not session.demo and type(session.mobs) == "table" or false
end

-- Reads every slot of the loot window that just opened (Mobs.readSlot).
function Core.snapshotLoot()
  lootSlots = nil
  if not Core.mobsCounting() or type(GetNumLootItems) ~= "function" then return end
  local ok, n = pcall(GetNumLootItems)
  if not (ok and num(n)) then return end
  local slots = {}
  local cast = castTarget and time() - castTarget.at <= NODE_CAST_SECONDS and castTarget.name or nil
  for slot = 1, n do
    local okSlot, s = pcall(ns.Mobs.readSlot, _G, slot)
    if okSlot and s and #s.sources > 0 then
      slots[slot] = s
      for _, src in ipairs(s.sources) do
        local key, kind = ns.Mobs.idOf(src.guid)
        if cast and kind == "node" and not mobNames[key] then
          mobNames[key] = cast
          castTarget = nil
        end
      end
    end
  end
  lootSlots = slots
  -- Drop chances: what each corpse held, taken or not.
  ns.Mobs.noteWindow(ns.session.mobs, slots, mobState)
  Core.mobsVersion = Core.mobsVersion + 1 -- the item tooltips' index is stale
end


-- The name of the mob behind `guid`: the unit tooltip's first line (cached
-- for the login), else nil (History > Mobs then shows "NPC 12345").
function Core.mobName(env, guid, key)
  local C = env.C_TooltipInfo
  -- Unit tooltips only: a node is named by its gathering cast (snapshotLoot).
  if key:sub(1, 4) ~= "obj:" and type(C) == "table" and type(C.GetHyperlink) == "function" then
    local ok, data = pcall(C.GetHyperlink, "unit:" .. guid)
    local line = ok and type(data) == "table" and type(data.lines) == "table" and data.lines[1]
    local text = type(line) == "table" and line.leftText
    if type(text) == "string" and text ~= "" then
      mobNames[key] = text
      return text
    end
  end
  return nil
end

-- Option "dailyFarmLevel": whether the player's `level` is inside the level
-- range of map `mapID`; nil when unknown (no API, no range).
function Core.levelFits(env, mapID, level)
  local C = env.C_Map
  if not (type(C) == "table" and type(C.GetMapLevels) == "function" and num(mapID) and num(level)) then return nil end
  local ok, low, high = pcall(C.GetMapLevels, mapID)
  if not (ok and num(low) and num(high) and high > 0) then return nil end
  return level >= low and level <= high
end

-- Option "minSessionMinutes": a session shorter than this continues instead
-- of being saved on a split or at login (a manual Reset still saves it).
-- Without `now` (a saved session at login) only its elapsedBase counts, so
-- offline time never does.
function Core.isShort(session, now, minMinutes)
  if not (num(minMinutes) and minMinutes > 0 and type(session) == "table") then return false end
  local elapsed
  if num(now) then elapsed = ns.Session.elapsed(session, now) else elapsed = session.elapsedBase end
  return num(elapsed) and elapsed < minMinutes * 60 or false
end

local function shortNow(session)
  return Core.isShort(session, time(), ns.Options.get(ns.db, "minSessionMinutes"))
end

-- Whether a session has anything recorded (items, currencies or raw gold).
local function hasLoot(session)
  return next(session.items or {}) ~= nil or next(session.currencies or {}) ~= nil
    or ns.Session.goldTotal(session) > 0
end

local function checkInstance()
  local place, key = Core.placeOf(_G, difficulties)
  local changed = Core.instanceChanged(lastInstance, key)
  lastInstance = key
  if not changed then return end
  -- Option "showInInstance": open inside, close again on leaving.
  if key ~= nil then Core.autoWindow("show", "instance", "showInInstance") else Core.autoWindow("undo", "instance") end
  if not (ns.session and ns.db and ns.Options.get(ns.db, "instanceSession")) then return end
  zoneState.zone, zoneState.pending = place, nil -- no second split for the same move
  if hasLoot(ns.session) and shortNow(ns.session) then return end -- continues
  Core.resetSession(L["new session"] .. (place and (": " .. place) or "") .. ".")
end

-- Option "zoneSession". Pure decision over `state` = { zone, pending, since }
-- (the session's zone, a new zone the player is in and since when): returns
-- true once the player stayed `grace` seconds in another zone; then that zone
-- is the session's. A flight or a rest in a city or inn (`away`) never
-- counts, nor does a zone left again before the grace time is over: selling
-- in Orgrimmar does not end the Badlands session.
function Core.zoneSwitch(state, place, now, away, grace)
  if away then
    state.pending, state.since = nil, nil
    return false
  end
  if type(place) ~= "string" then return false end
  if state.zone == nil then state.zone = place end
  if place == state.zone then
    state.pending, state.since = nil, nil
    return false
  end
  if place ~= state.pending then
    state.pending, state.since = place, now
    return false
  end
  if now - state.since < grace then return false end
  state.zone, state.pending, state.since = place, nil, nil
  return true
end

-- Called on zone changes and by the ticker. While the clock is stopped
-- nothing splits. An empty session just starts over (the time getting here
-- does not count), without a chat line.
function Core.checkZone()
  local session = ns.session
  if not (session and ns.db) then return end
  local place = Core.placeOf(_G, difficulties)
  local onTaxi = type(UnitOnTaxi) == "function" and UnitOnTaxi("player") and true or false
  local resting = type(IsResting) == "function" and IsResting() and true or false
  local grace = ns.Options.get(ns.db, "zoneSessionMinutes") * 60
  if not Core.zoneSwitch(zoneState, place, time(), onTaxi or resting, grace) then return end
  if not (ns.Options.get(ns.db, "zoneSession") and session.running) then return end
  if hasLoot(session) then
    if shortNow(session) then return end -- continues in the new zone
    Core.resetSession(L["new session"] .. ": " .. place .. ".")
  else
    ns.Session.reset(session, time())
    refreshUI()
  end
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
    Core.checkRest()
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
  -- The game's auction house UI loads on demand, possibly after the window's
  -- open event: the scan button waits for it.
  if name == "Blizzard_AuctionHouseUI" then
    if tradeWindows.AUCTION_HOUSE and ns.UI and ns.UI.ScanButton then ns.UI.ScanButton.show() end
    return
  end
  if name ~= ADDON then return end
  -- The addon was called LootPrice. A player who renames the old saved files
  -- (SavedVariables/LootPrice.lua -> LootLedger.lua, account and character)
  -- brings LootPriceDB / LootPriceCharDB in: take them over once.
  -- The client runs the whole renamed file, so the old global names are set
  -- when ADDON_LOADED fires.
  if LootLedgerDB == nil and type(LootPriceDB) == "table" then
    LootLedgerDB, LootPriceDB = LootPriceDB, nil
  end
  if LootLedgerCharDB == nil and type(LootPriceCharDB) == "table" then
    LootLedgerCharDB, LootPriceCharDB = LootPriceCharDB, nil
  end
  LootLedgerDB = ns.DB.applyDefaults(LootLedgerDB, ns.DB.defaults)
  LootLedgerCharDB = ns.DB.applyDefaults(LootLedgerCharDB, ns.DB.charDefaults)
  ns.DB.migrateAccount(LootLedgerDB)
  -- After migrateAccount: this drops the old settings table.
  ns.Profiles.init(LootLedgerDB, LootLedgerCharDB)
  ns.db = LootLedgerDB
  ns.chardb = LootLedgerCharDB
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
    Core.checkZone()
    return
  end
  if not ns.db then return end
  setupDone = true
  lastInstance = select(2, Core.placeOf(_G, difficulties))
  zoneState.zone = (Core.placeOf(_G, difficulties))

  -- Old cached prices are of no use and only grow the saved file.
  ns.Prices.prune(ns.db.cache, now, ns.Prices.CACHE_MAX_AGE)
  Core.pruneScan(ns.db, now)

  Core.linkHistory()
  Core.noteProfessions(true)
  local previous = ns.chardb.session
  local keep = ns.Options.get(ns.db, "keepSession") or isReloadingUi
  -- A short session with loot continues (Min. session length) as if it were
  -- new: running, dated from this login. Empty and demo sessions never do.
  local short = not keep and type(previous) == "table" and not previous.demo
    and Core.isShort(previous, nil, ns.Options.get(ns.db, "minSessionMinutes"))
  if short then
    local ok, has = pcall(hasLoot, previous)
    short = ok and has
  end
  ns.session = ns.Session.login(previous, keep or short, now)
  ns.chardb.session = ns.session
  if short and ns.session == previous then
    ns.session.afkPaused = nil
    ns.session.startedAt = now
    ns.Session.start(ns.session, now)
  end
  ns.prices = Core.buildPrices(_G, ns.db, time, Core.cacheKey)
  Core.priceAddonHint(_G, ns.db, ns.Util.say)
  -- A session that was not kept goes to History (prices are available now).
  if previous ~= ns.session then Core.archiveSession(previous) end
  Core.updatePlace()
  if ns.UI and ns.UI.Ledger then ns.UI.Ledger.init() end
  -- Before the options: LibDBIcon (if loaded) takes over the minimap button.
  if ns.UI and ns.UI.Broker then ns.UI.Broker.init() end
  if ns.UI and ns.UI.ItemTooltip then ns.UI.ItemTooltip.init() end
  ns.Options.applyAll(ns.db)
  Core.checkRest()
  if ns.UI and ns.UI.OptionsPanel then ns.UI.OptionsPanel.registerPage() end
  -- Every few seconds, window shown or not: the time goal, the zone delay of
  -- "Session per zone" and the gold per hour graph.
  if C_Timer and type(C_Timer.NewTicker) == "function" then
    C_Timer.NewTicker(HEARTBEAT_SECONDS, Core.heartbeat)
  end
  refreshUI()
end

-- History Zones: the player moved to another zone or subzone (no redraw).
-- They fire for subzone changes too.
for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
  events[event] = function()
    Core.updatePlace()
    Core.checkZone()
  end
end

-- Combat auto hide / show (option "combatHide"): hides the window when combat
-- starts and shows it again when combat ends, but only if it was shown before.
function events.PLAYER_REGEN_DISABLED()
  local window = ns.UI and ns.UI.Window
  if window and ns.db and ns.Options.get(ns.db, "combatHide") then window.combatHide() end
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
for _, base in ipairs({ "MERCHANT", "MAIL", "TRADE", "AUCTION_HOUSE" }) do
  events[base .. "_SHOW"] = function() tradeWindows[base] = true end
  events[base .. "_CLOSED"] = function() tradeWindows[base] = nil end
end

-- ---------------------------------------------------------------------------
-- LootLedger scan (Scan.lua): a full auction house read on request and the
-- search results the player opens, only without TSM and Auctionator.

local L_SCAN_DONE = L["Scan done: %s items priced (%.1f s)."]
local L_SCAN_STOPPED = L["Scan stopped: the auction house was closed. %s items priced."]
local L_SCAN_WAIT = L["The game allows the next full scan in %s."]
local L_SCAN_REFUSED = L["The game did not answer the scan. Try again later."]
local L_SCAN_CLOSED = L["Open the auction house to scan."]
local L_SCAN_OFF = L["Scanning is off while TSM or Auctionator is loaded."]
local L_SCAN_NO_REALM = L["The realm is not known yet. Try again in a moment."]
local L_SCAN_REMIND = L["Your last auction house scan is more than a day old: /ll scan or the LootLedger scan button."]
local SCAN_ANSWER_SECONDS = 60 -- no full read within this: the game refused it
local SCAN_REMIND_AFTER = 86400

-- reader: the running Scan.newReader or false; pending: ReplicateItems sent,
-- its event not come yet; token: the pending request (its 60 s check).
local scan = { reader = false, pending = false, token = 0, fraction = 0, reminded = false }
Core.onScanChange = false -- set by UI/ScanButton.lua: called on every change

local function scanChanged()
  if Core.onScanChange then pcall(Core.onScanChange) end
end

-- The realm key of the scan buckets (Scan.realmKey): price cache key + realm.
local function currentRealmKey()
  local realm
  if type(GetRealmName) == "function" then
    local ok, name = pcall(GetRealmName)
    if ok then realm = name end
  end
  return ns.Scan.realmKey(Core.cacheKey(), realm)
end
if ns.Scan then ns.Scan.currentRealmKey = currentRealmKey end

local function scanBucket(create)
  return ns.Scan.bucket(ns.db, ns.Scan.currentRealmKey(), create)
end

local function clock()
  return type(GetTime) == "function" and GetTime() or time()
end

function Core.auctionHouseOpen()
  return tradeWindows.AUCTION_HOUSE == true
end

-- Scanning is offered without TSM and Auctionator, when the client has the
-- auction house API.
function Core.scanAvailable(env)
  env = env or _G
  local ah = env.C_AuctionHouse
  return not ns.Sources.anyPresent(env) and type(ah) == "table" and type(ah.ReplicateItems) == "function"
end

-- For the scan button: { running, fraction (0..1), waitLeft (seconds) }.
function Core.scanState()
  return {
    running = scan.reader ~= false or scan.pending,
    fraction = scan.fraction,
    waitLeft = ns.Scan.waitLeft(ns.chardb and ns.chardb.scanAt, time()),
  }
end

local function finishScan(stats)
  scan.reader = false
  local bucket = scanBucket(true)
  local priced = bucket and ns.Scan.commit(bucket, stats.sets, time()) or 0
  if stats.stopped then
    say(L_SCAN_STOPPED:format(priced))
  else
    if bucket then bucket.lastFull = time() end
    say(L_SCAN_DONE:format(priced, math.max(0, clock() - (scan.startedAt or clock()))))
  end
  requestRefresh()
  scanChanged()
end

-- Starts a full read. Returns true, or false and why: "closed" (no auction
-- house), "unavailable" (TSM / Auctionator or no API), "realm" (the realm
-- key is not known yet: the read would have nowhere to go), "running",
-- "wait" (plus the seconds left) or "refused" (the call failed).
function Core.startScan()
  if not tradeWindows.AUCTION_HOUSE then return false, "closed" end
  if not Core.scanAvailable(_G) then return false, "unavailable" end
  if scan.reader or scan.pending then return false, "running" end
  if ns.Scan.currentRealmKey() == nil then return false, "realm" end
  local now = time()
  local left = ns.Scan.waitLeft(ns.chardb.scanAt, now)
  if left > 0 then return false, "wait", left end
  -- UNVERIFIED (check in client): C_AuctionHouse.ReplicateItems, answered by
  -- REPLICATE_ITEM_LIST_UPDATE; the game allows one call per 15 minutes.
  if not pcall(C_AuctionHouse.ReplicateItems) then return false, "refused" end
  local previous = ns.chardb.scanAt
  ns.chardb.scanAt = now
  scan.pending, scan.fraction, scan.startedAt = true, 0, clock()
  scan.token = scan.token + 1
  local token = scan.token
  if C_Timer and C_Timer.After then
    C_Timer.After(SCAN_ANSWER_SECONDS, function()
      if not (scan.pending and scan.token == token) then return end
      scan.pending = false
      ns.chardb.scanAt = previous
      say(L_SCAN_REFUSED)
      scanChanged()
    end)
  end
  scanChanged()
  return true
end

-- /ll scan and the button: starts a scan and says why when it cannot.
function Core.scanCommand()
  local ok, why, left = Core.startScan()
  if ok or why == "running" then return ok end
  if why == "closed" then say(L_SCAN_CLOSED)
  elseif why == "unavailable" then say(L_SCAN_OFF)
  elseif why == "realm" then say(L_SCAN_NO_REALM)
  elseif why == "wait" then say(L_SCAN_WAIT:format(ns.Util.shortAge(left)))
  else say(L_SCAN_REFUSED) end
  return false
end

-- UNVERIFIED (check in client): GetNumReplicateItems, GetReplicateItemInfo
-- (0-based index; count 3rd, buyout 10th, itemID 17th return) and
-- GetReplicateItemLink (may be nil for items the client has not loaded: the
-- reader then keys the entry by its item ID).
function events.REPLICATE_ITEM_LIST_UPDATE()
  if not scan.pending then return end
  scan.pending = false
  local api = C_AuctionHouse
  scan.reader = ns.Scan.newReader({
    count = api.GetNumReplicateItems,
    info = function(i)
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = api.GetReplicateItemInfo(i)
      return count, buyout, itemID, api.GetReplicateItemLink(i)
    end,
    after = C_Timer.After,
    onProgress = function(f)
      scan.fraction = f
      scanChanged()
    end,
    onDone = finishScan,
  })
  scan.reader:start()
end

-- Passive recording: a full set of search results the player opened.
local function recordSets(sets)
  if not next(sets) then return end
  local bucket = scanBucket(true)
  if bucket and ns.Scan.commit(bucket, sets, time()) > 0 then requestRefresh() end
end

local function passiveOn()
  return tradeWindows.AUCTION_HOUSE and Core.scanAvailable(_G)
end

-- UNVERIFIED (check in client): HasFullCommoditySearchResults,
-- GetNumCommoditySearchResults, GetCommoditySearchResultInfo (1-based;
-- unitPrice, quantity).
function events.COMMODITY_SEARCH_RESULTS_UPDATED(itemID)
  if not passiveOn() or type(itemID) ~= "number" then return end
  local api = C_AuctionHouse
  local ok, full = pcall(api.HasFullCommoditySearchResults, itemID)
  if not (ok and full) then return end
  local list = {}
  local okN, n = pcall(api.GetNumCommoditySearchResults, itemID)
  for i = 1, okN and type(n) == "number" and n or 0 do
    local got, r = pcall(api.GetCommoditySearchResultInfo, itemID, i)
    if got and type(r) == "table" and num(r.unitPrice) and r.unitPrice > 0 and num(r.quantity) and r.quantity >= 1 then
      list[#list + 1] = { unit = r.unitPrice, qty = r.quantity }
    end
  end
  recordSets(#list > 0 and { [itemID] = list } or {})
end

-- UNVERIFIED (check in client): HasFullItemSearchResults,
-- GetNumItemSearchResults, GetItemSearchResultInfo (1-based; buyoutAmount,
-- quantity, itemLink). Grouped by variant (LootParse.itemKey of the link).
function events.ITEM_SEARCH_RESULTS_UPDATED(itemKey)
  if not passiveOn() or type(itemKey) ~= "table" then return end
  -- Battle pets all share the cage item ID: never priced.
  if itemKey.itemID == ns.Scan.PET_CAGE then return end
  if num(itemKey.battlePetSpeciesID) and itemKey.battlePetSpeciesID > 0 then return end
  local api = C_AuctionHouse
  local ok, full = pcall(api.HasFullItemSearchResults, itemKey)
  if not (ok and full) then return end
  local sets = {}
  local okN, n = pcall(api.GetNumItemSearchResults, itemKey)
  for i = 1, okN and type(n) == "number" and n or 0 do
    local got, r = pcall(api.GetItemSearchResultInfo, itemKey, i)
    if got and type(r) == "table" and num(r.buyoutAmount) and r.buyoutAmount > 0 then
      local qty = num(r.quantity) and r.quantity >= 1 and r.quantity or 1
      local key = ns.LootParse.itemKey(r.itemLink) or itemKey.itemID
      if key ~= nil then
        sets[key] = sets[key] or {}
        local set = sets[key]
        set[#set + 1] = { unit = math.floor(r.buyoutAmount / qty), qty = qty }
      end
    end
  end
  recordSets(sets)
end

-- The reminder: once per login, when the last full scan is old or missing.
local function scanReminder()
  if scan.reminded or not Core.scanAvailable(_G) then return end
  if not ns.db or ns.Options.get(ns.db, "scanReminder") == false then return end
  local bucket = scanBucket(false)
  local last = bucket and bucket.lastFull
  if num(last) and time() - last <= SCAN_REMIND_AFTER then return end
  scan.reminded = true
  say(L_SCAN_REMIND)
end

-- Old scan prices only grow the saved file (login).
function Core.pruneScan(db, now)
  if type(db) ~= "table" or type(db.scan) ~= "table" then return end
  for key, bucket in pairs(db.scan) do
    if type(bucket) ~= "table" or type(bucket.items) ~= "table" then
      db.scan[key] = nil
    else
      ns.Scan.prune(bucket.items, now)
      if next(bucket.items) == nil then db.scan[key] = nil end
    end
  end
end

events.AUCTION_HOUSE_SHOW = function()
  tradeWindows.AUCTION_HOUSE = true
  scanReminder()
  if ns.UI and ns.UI.ScanButton then ns.UI.ScanButton.show() end
end

events.AUCTION_HOUSE_CLOSED = function()
  tradeWindows.AUCTION_HOUSE = nil
  scan.pending = false
  if scan.reader then scan.reader:stop() end
  if ns.UI and ns.UI.ScanButton then ns.UI.ScanButton.hide() end
end

-- Loot window (raw gold backstop). A window that opens before the last one
-- settled settles that one first.
-- Looted money arrives before LOOT_CLOSED + 1 s.
local function openLootWindow()
  if lootWindow then settleLoot(lootWindow) end
  local money = currentMoney()
  if money and ns.session then lootWindow = { money = money, chat = 0 } end
  Core.snapshotLoot()
end

-- LOOT_READY comes before LOOT_OPENED. Fast loot addons (Leatrix Plus and
-- the like) take every slot on LOOT_READY, so by LOOT_OPENED the slots are
-- empty and their LOOT_SLOT_CLEARED may already have fired: the window is
-- read here, and LOOT_OPENED reads it only when LOOT_READY did not.
local readByReady = false

function events.LOOT_READY()
  readByReady = true
  openLootWindow()
end

function events.LOOT_OPENED()
  if readByReady then
    readByReady = false
    return
  end
  openLootWindow()
end

-- A slot taken from the loot window: its loot goes to the mob or node it
-- came from (Mobs.credit).
function events.LOOT_SLOT_CLEARED(slot)
  local slots = lootSlots
  local entry = slots and slots[slot]
  if not entry then return end
  slots[slot] = nil
  if not Core.mobsCounting() then return end
  local mobs = ns.session.mobs
  local names = {}
  for _, s in ipairs(entry.sources) do
    local key = ns.Mobs.idOf(s.guid)
    if key then names[key] = mobNames[key] or Core.mobName(_G, s.guid, key) end
  end
  local place = (Core.placeOf(_G, difficulties))
  -- Coin waits for the window's end: in a group you get a share of it
  -- (settleLoot scales it to what you received).
  if entry.kind == "money" and lootWindow then
    if type(lootWindow.mobMoney) ~= "table" then lootWindow.mobMoney = {} end
    table.insert(lootWindow.mobMoney, { mobs = mobs, slot = entry, place = place, names = names })
    return
  end
  ns.Mobs.credit(mobs, entry, place, names, mobState)
end

-- No combat log: registering COMBAT_LOG_EVENT_UNFILTERED is forbidden for
-- addons on this client (ADDON_ACTION_FORBIDDEN, even inside pcall), so
-- kills are not counted.

-- The player's cast target: the node's name for a gathering cast.
function events.UNIT_SPELLCAST_SENT(unit, target)
  if unit == "player" and type(target) == "string" and target ~= "" then
    castTarget = { name = target, at = time() }
  end
end

-- Names of mobs the player sees (name plates, target, mouseover).
local function noteUnitName(unit)
  if type(UnitGUID) ~= "function" or type(UnitName) ~= "function" then return end
  local ok, guid = pcall(UnitGUID, unit)
  local key = ok and ns.Mobs.idOf(guid)
  if not key then return end
  local okName, name = pcall(UnitName, unit)
  if okName and type(name) == "string" and name ~= "" then mobNames[key] = name end
end

function events.NAME_PLATE_UNIT_ADDED(unit) noteUnitName(unit) end
function events.PLAYER_TARGET_CHANGED() noteUnitName("target") end
function events.UPDATE_MOUSEOVER_UNIT() noteUnitName("mouseover") end

function events.LOOT_CLOSED()
  lootSlots = nil
  readByReady = false
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

-- Bags: gold on hand and net worth follow the character's money.
function events.PLAYER_MONEY()
  dataChanged("bags")
end

function events.PLAYER_UPDATE_RESTING()
  Core.checkRest()
end

function events.SKILL_LINES_CHANGED()
  Core.noteProfessions()
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
  -- The History is saved once, in LootLedgerDB.histories (Core.linkHistory).
  if Core.character and ns.chardb then ns.chardb.history = nil end
  -- The active profile is saved once, in LootLedgerDB.profiles.
  if ns.Profiles then ns.Profiles.beforeLogout(ns.db) end
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
