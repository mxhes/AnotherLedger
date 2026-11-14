local ADDON, ns = ...

local isNumber, isPositive = ns.Util.isNumber, ns.Util.isPositive

-- Price lookup: live AH sources first, then the saved cache of the last price
-- each source returned (per region / game mode), plus vendor and disenchant
-- values. Pure: every client call is injected through Prices.new.
local Prices = {
  STALE_AFTER = 43200,             -- a cached price older than 12 h is tagged stale
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

function Prices.isStale(seconds)
  return seconds > Prices.STALE_AFTER
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
--   sources    = { { name, get(itemID) -> copper or nil }, ... } asked in order,
--   vendor     = function(itemID) -> copper or nil,
--   disenchant = function(itemID) -> copper or nil (optional),
--   cache      = saved table { [key] = { [itemID] = { price, seenAt } } },
--   key        = function() -> cache key or nil,
--   now        = function() -> timestamp,
-- }
function Prices.new(opts)
  return setmetatable({
    sources = opts.sources or {},
    vendor = opts.vendor,
    disenchant = opts.disenchant,
    cache = opts.cache,
    key = opts.key,
    now = opts.now,
  }, Instance)
end

-- First valid live price and the name of the source that gave it.
function Instance:_live(itemID)
  for _, source in ipairs(self.sources) do
    local ok, value = pcall(source.get, itemID)
    if ok and isPositive(value) then return value, source.name end
  end
  return nil
end

-- Remembers a live price; an unchanged, recently stamped entry is left alone
-- so the saved table is not rewritten on every lookup.
function Instance:_remember(key, bucket, itemID, price, now)
  if not bucket then
    bucket = {}
    self.cache[key] = bucket
  end
  local entry = bucket[itemID]
  if validEntry(entry) and entry.price == price then
    local age = now - entry.seenAt
    if age >= 0 and age < Prices.WRITE_INTERVAL then return end
    entry.seenAt = now
    return
  end
  bucket[itemID] = { price = price, seenAt = now }
end

-- Returns { vendor, de, ah, ahSource, ahAge }; every field may be missing.
-- ahSource is the live source's name or "cache"; ahAge is 0 for a live price.
function Instance:lookup(itemID)
  local result = {}
  if self.vendor then
    local ok, v = pcall(self.vendor, itemID)
    if ok and type(v) == "number" and v == v then result.vendor = v end
  end

  -- Disenchant value (live only, nil when the item cannot be disenchanted).
  if self.disenchant then
    local ok, v = pcall(self.disenchant, itemID)
    if ok and isPositive(v) then result.de = v end
  end

  local now = self.now()
  local okKey, key = pcall(self.key)
  if not okKey then key = nil end
  local bucket = key and self.cache and self.cache[key] or nil
  if type(bucket) ~= "table" then bucket = nil end

  local price, name = self:_live(itemID)
  if price then
    result.ah, result.ahSource, result.ahAge = price, name, 0
    if key and self.cache then self:_remember(key, bucket, itemID, price, now) end
    return result
  end

  local entry = bucket and bucket[itemID]
  if validEntry(entry) and isPositive(entry.price) then
    result.ah, result.ahSource, result.ahAge = entry.price, "cache", math.max(0, now - entry.seenAt)
  end
  return result
end

ns.Prices = Prices
