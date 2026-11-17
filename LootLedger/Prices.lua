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
}

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

-- Returns { vendor, de, ah, ahSource, ahAge, saleRate, soldPerDay }; every
-- field may be missing (saleRate / soldPerDay are live only, never cached).
-- ahSource is the live source's name or "cache"; ahAge is 0 for a live price.
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
    return result
  end

  local entry = bucket and bucket[itemKey]
  if validEntry(entry) and isPositive(entry.price) and self:_cacheUsable(entry) then
    result.ah, result.ahSource, result.ahAge = entry.price, "cache", math.max(0, now - entry.seenAt)
  end
  return result
end

ns.Prices = Prices
