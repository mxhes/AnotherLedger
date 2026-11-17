local ADDON, ns = ...

local isNumber, isPositive = ns.Util.isNumber, ns.Util.isPositive

-- Price lookup: live AH sources first, then the saved cache of the last live
-- price (per region / game mode, with the name of the source that gave it),
-- plus vendor and destroy (disenchant) values. Pure: every client call is
-- injected through Prices.new.
local Prices = {
  -- A cached price older than this is tagged stale (option "staleHours").
  STALE_AFTER = ((ns.DB and ns.DB.defaults.settings.staleHours) or 12) * 3600,
  WRITE_INTERVAL = 60,             -- an unchanged price is re-stamped at most this often
  CACHE_MAX_AGE = 30 * 86400,      -- cached prices older than 30 days are dropped at login
  AH_CUT = 0.05,                   -- the auction house fee (option "ahCut")
}

-- ---------------------------------------------------------------------------
-- Value rules (options ahCut, ahMinGain, destroyMode)

-- The best of the vendor, AH and destroy values and which one it is
-- ("vendor" / "ah" / "de"). The AH value only counts when it beats the vendor
-- price by `minGainPct` percent (option "Auction from"; nil or 0 = any gain);
-- an item without a vendor price counts its AH value whenever it has one.
function Prices.best(vendor, ah, de, minGainPct)
  local best, kind = nil, nil
  if isNumber(vendor) then best, kind = vendor, "vendor" end
  if isNumber(ah) and (best == nil or ah > best) then
    local gain = isNumber(minGainPct) and minGainPct > 0 and minGainPct or 0
    if not (isNumber(vendor) and vendor > 0) or ah >= vendor * (1 + gain / 100) then best, kind = ah, "ah" end
  end
  if isNumber(de) and (best == nil or de > best) then best, kind = de, "de" end
  return best, kind
end

-- The profession a destroy of an item needs, from its class and subclass
-- (GetItemInfoInstant): weapons and armor are disenchanted, herbs milled, ore
-- prospected. nil for anything else.
local WEAPON, ARMOR, TRADE_GOODS = 2, 4, 7
local TRADE_HERB, TRADE_METAL_STONE = 9, 7
function Prices.destroyKind(classID, subclassID)
  if classID == WEAPON or classID == ARMOR then return "enchanting" end
  if classID == TRADE_GOODS then
    if subclassID == TRADE_HERB then return "inscription" end
    if subclassID == TRADE_METAL_STONE then return "jewelcrafting" end
  end
  return nil
end

-- Profession skill lines (GetProfessionInfo's 7th return) that destroy items.
local DESTROY_SKILLS = { [333] = "enchanting", [773] = "inscription", [755] = "jewelcrafting" }

-- { enchanting = true, ... } of a list of skill line IDs.
function Prices.professionSet(skillLines)
  local set = {}
  for _, id in ipairs(type(skillLines) == "table" and skillLines or {}) do
    local kind = DESTROY_SKILLS[id]
    if kind then set[kind] = true end
  end
  return set
end

local function anyOf(set)
  return type(set) == "table" and next(set) ~= nil
end

-- Option "destroyMode": does an item's destroy value count? `mode` is
-- "always" / "any" (one of my characters) / "self" (this character) / "never";
-- `own` and `all` are profession sets of this character and of all of them.
-- An item whose kind is unknown counts when the set has any destroy profession.
function Prices.destroyAllowed(mode, kind, own, all)
  if mode == "never" then return false end
  if mode ~= "any" and mode ~= "self" then return true end
  local set = mode == "self" and own or all
  if type(set) ~= "table" then return false end
  if kind == nil then return anyOf(set) end
  return set[kind] == true
end

local function validEntry(e)
  return type(e) == "table" and isNumber(e.seenAt)
end

local function isKeyPart(v)
  return type(v) == "string" or type(v) == "number"
end

function Prices.cacheKey(region, modeID)
  if not isKeyPart(region) or not isKeyPart(modeID) then return nil end
  return region .. "-" .. modeID
end

Prices.formatAge = ns.Util.shortAge

-- Old from STALE_AFTER on (the Bank tab's scan note uses the same rule).
function Prices.isStale(seconds)
  return seconds >= Prices.STALE_AFTER
end

-- Drops cached prices last seen more than `maxAge` seconds ago, unusable
-- entries and the buckets left empty. `cache` = { [key] = { [itemID] = entry } }.
-- Returns the number of removed entries.
function Prices.prune(cache, now, maxAge)
  if type(cache) ~= "table" or not isNumber(now) or not isNumber(maxAge) then return 0 end
  local removed = 0
  for key, bucket in pairs(cache) do
    if type(bucket) == "table" then
      for itemID, entry in pairs(bucket) do
        if not validEntry(entry) or now - entry.seenAt > maxAge then
          bucket[itemID] = nil
          removed = removed + 1
        end
      end
      if next(bucket) == nil then cache[key] = nil end
    end
  end
  return removed
end

local Instance = {}
Instance.__index = Instance

-- opts = {
--   sources    = { { name, get(itemID, link) -> copper or nil }, ... } asked in order,
--   vendor     = function(itemID, link) -> copper or nil,
--   disenchant = function(itemID, link) -> copper or nil (optional),
--   market     = function(itemID, link) -> { saleRate, soldPerDay } or nil (optional),
--   cache      = saved table { [key] = { [itemKey] = { price, seenAt, source } } },
--   cacheAllowed = function(sourceName) -> bool (optional): whether a cached
--                price of that source may be used (the price source option);
--                entries saved without a source always may,
-- `link` (optional) lets a source price the exact variant (bonus IDs); the
-- cache stores prices under LootParse.itemKey (the item ID for plain items).
--   key        = function() -> cache key or nil,
--   now        = function() -> timestamp,
-- }
function Prices.new(opts)
  return setmetatable({
    sources = opts.sources or {},
    vendor = opts.vendor,
    disenchant = opts.disenchant,
    market = opts.market,
    cache = opts.cache,
    cacheAllowed = opts.cacheAllowed,
    rules = opts.rules,
    key = opts.key,
    now = opts.now,
  }, Instance)
end

-- First valid live price and the name of the source that gave it.
function Instance:_live(itemID, link)
  for _, source in ipairs(self.sources) do
    local ok, value = pcall(source.get, itemID, link)
    if ok and isPositive(value) then return value, source.name end
  end
  return nil
end

-- Remembers a live price; an unchanged, recently stamped entry is left alone
-- so the saved table is not rewritten on every lookup.
function Instance:_remember(key, bucket, itemID, price, now, source)
  if not bucket then
    bucket = {}
    self.cache[key] = bucket
  end
  local entry = bucket[itemID]
  if validEntry(entry) and entry.price == price then
    entry.source = source
    local age = now - entry.seenAt
    if age >= 0 and age < Prices.WRITE_INTERVAL then return end
    entry.seenAt = now
    return
  end
  bucket[itemID] = { price = price, seenAt = now, source = source }
end

-- A cached entry from a source the price source option leaves out is not used.
function Instance:_cacheUsable(entry)
  if type(entry.source) ~= "string" or not self.cacheAllowed then return true end
  local ok, allowed = pcall(self.cacheAllowed, entry.source)
  return not ok or allowed and true or false
end

-- The value rules of the moment (opts.rules), or nil.
function Instance:_rules()
  if not self.rules then return nil end
  local ok, r = pcall(self.rules)
  return ok and type(r) == "table" and r or nil
end

-- Applies the value rules to a lookup result: the AH cut (ah after the fee,
-- ahGross the raw price) and the destroy rule (de dropped). The cache keeps
-- the raw price, so the cut is applied exactly once.
function Instance:_applyRules(result, itemID, link)
  local rules = self:_rules()
  if not rules then return result end
  if rules.ahCut and isNumber(result.ah) then
    result.ahGross = result.ah
    result.ah = math.floor(result.ah * (1 - Prices.AH_CUT))
  end
  if result.de and rules.destroyAllowed then
    local ok, allowed = pcall(rules.destroyAllowed, itemID, link)
    if ok and allowed == false then result.de = nil end
  end
  return result
end

-- Returns { vendor, de, ah, ahGross, ahSource, ahAge, saleRate, soldPerDay };
-- every field may be missing (saleRate / soldPerDay are live only, never
-- cached). ahSource is the live source's name or "cache"; ahAge is 0 for a
-- live price. With the AH cut (opts.rules) `ah` is after the fee and ahGross
-- the raw price.
function Instance:lookup(itemID, link)
  local result = {}
  local itemKey = itemID
  if type(link) == "string" and ns.LootParse then itemKey = ns.LootParse.itemKey(link) or itemID end
  if self.vendor then
    local ok, v = pcall(self.vendor, itemID, link)
    if ok and type(v) == "number" and v == v then result.vendor = v end
  end

  -- Disenchant value (live only, nil when the item cannot be disenchanted).
  if self.disenchant then
    local ok, v = pcall(self.disenchant, itemID, link)
    if ok and isPositive(v) then result.de = v end
  end

  -- Region market data (sale rate, sold per day).
  if self.market then
    local ok, m = pcall(self.market, itemID, link)
    if ok and type(m) == "table" then
      if isNumber(m.saleRate) and m.saleRate >= 0 then result.saleRate = m.saleRate end
      if isNumber(m.soldPerDay) and m.soldPerDay >= 0 then result.soldPerDay = m.soldPerDay end
    end
  end

  local now = self.now()
  local okKey, key = pcall(self.key)
  if not okKey then key = nil end
  local bucket = key and self.cache and self.cache[key] or nil
  if type(bucket) ~= "table" then bucket = nil end

  local price, name = self:_live(itemID, link)
  if price then
    result.ah, result.ahSource, result.ahAge = price, name, 0
    if key and self.cache then self:_remember(key, bucket, itemKey, price, now, name) end
    return self:_applyRules(result, itemID, link)
  end

  local entry = bucket and bucket[itemKey]
  if validEntry(entry) and isPositive(entry.price) and self:_cacheUsable(entry) then
    result.ah, result.ahSource, result.ahAge = entry.price, "cache", math.max(0, now - entry.seenAt)
  end
  return self:_applyRules(result, itemID, link)
end

ns.Prices = Prices
