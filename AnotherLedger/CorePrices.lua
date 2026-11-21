local ADDON, ns = ...

-- Core's price section (loads after Core.lua): the price cache key, the
-- Prices object over the registered sources, the no-price-addon hint, destroy
-- professions, the price trend and what an item or a session is worth.

local L = ns.L
local Core = ns.Core

local KEY_RETRY_SECONDS = 10
local keyState = { key = nil } -- { key, tried }: the price cache key, see keyFromState

-- Price cache key and price lookup (take the global environment as a
-- parameter, testable)

-- Region/game-mode cache key, or nil while either part is not known yet (the
-- call fails or answers nothing; asked again later). A client without one of
-- the calls (both exist on Forever) uses
-- Core.NO_KEY_PART for it, so the price cache, the scan and the Trade log
-- still work there instead of waiting for good.
Core.NO_KEY_PART = "any"

local function keyPart(fn)
  if type(fn) ~= "function" then return Core.NO_KEY_PART end
  local ok, v = pcall(fn)
  return ok and v or nil
end

function Core.evalKey(env)
  local rules = env.C_GameRules
  local modeFn = type(rules) == "table" and rules.GetCurrentGameModeRecordID or nil
  return ns.Prices.cacheKey(keyPart(env.GetCurrentRegionName), keyPart(modeFn))
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

-- Asks for the cache key again now (every loading screen).
function Core.renewKey(now)
  keyState.key = Core.evalKey(_G)
  keyState.tried = now
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

  local sources, destroyers, market = {}, {}, nil
  local keyOfName = {} -- source name (stored with a cached price) -> option key
  for _, spec in ipairs(Sources.list()) do
    local source = spec.create(env, setting)
    keyOfName[source.name] = spec.key
    -- A selected source whose addon is not loaded acts as Auto.
    sources[#sources + 1] = Sources.gate(source, spec.key, selected, env)
    -- Sale rate / sold per day: from the first source that offers them, not
    -- gated by the price source option (TSM data also helps next to Auctionator).
    if not market and spec.createMarket then market = spec.createMarket(env, setting) end
    -- Disenchant value: the first source that answers (TSM, then
    -- Auctionator). Not gated either: AH source = Auctionator must not
    -- quietly turn TSM's destroy values off (the option Destroy values decides).
    if spec.createDisenchant then destroyers[#destroyers + 1] = spec.createDisenchant(env, setting).get end
  end
  local disenchant = nil
  if #destroyers > 0 then
    disenchant = function(itemID, link)
      for _, get in ipairs(destroyers) do
        local ok, v = pcall(get, itemID, link)
        if ok and ns.Util.isPositive(v) then return v end
      end
      return nil
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
      return key == nil or Sources.allowed(selected(), key, env)
    end,
    key = getKey,
    now = now,
  })
end

-- One chat line, once per account, when no auction price addon is loaded
-- (Sources `present`): without one every item counts at its vendor price.
-- `db.priceHintShown` is cleared again once an addon is found, so removing it
-- later brings the hint back once. Returns whether it printed.
local L_NO_PRICE_ADDON = L["No auction price addon found: items count at their vendor price. Scan the auction house with /al scan, or install TSM or Auctionator."]

-- Whether this realm has a scan price of AnotherLedger's own.
local function hasScanPrices(db)
  local bucket = ns.Scan and ns.Scan.currentRealmKey and ns.Scan.bucket(db, ns.Scan.currentRealmKey())
  return bucket ~= nil and next(bucket.items) ~= nil
end

-- Whether anything gives auction prices: TSM, Auctionator or a scan of this
-- realm (the footer tooltip says why items have no AH price).
function Core.hasAuctionPrices(env, db)
  return ns.Sources.anyPresent(env) or (type(db) == "table" and hasScanPrices(db))
end

function Core.priceAddonHint(env, db, say)
  if type(db) ~= "table" then return false end
  if ns.Sources.anyPresent(env) then
    db.priceHintShown = nil
    return false
  end
  if db.priceHintShown then return false end
  -- Prices from AnotherLedger's own scan for this realm: no hint needed.
  if hasScanPrices(db) then return false end
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

-- The price trend of an item (the item tooltips): TSM's market value against
-- its 60 day average when TSM answers, else the newest day of this realm's
-- AnotherLedger scan against the days before. Returns change (a fraction,
-- +0.12 = 12% up) and source ("tsm" / "scan"), or nil.
function Core.priceTrend(env, db, itemID, link, now)
  local TSM = ns.Sources and ns.Sources.TSM
  if TSM and TSM.trend then
    local ok, change = pcall(TSM.trend, env, itemID, link)
    if ok and change then return change, "tsm" end
  end
  local Scan = ns.Scan
  local bucket = Scan and Scan.currentRealmKey and Scan.bucket(db, Scan.currentRealmKey())
  if bucket then
    local kind = ns.Util.setting("scanPrice", "market") == "lowest" and "lowest" or "market"
    local change = Scan.trendOf(bucket.items, itemID, link, kind, now)
    if change then return change, "scan" end
  end
  return nil
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
