local ADDON, ns = ...

local Prices = {
  STALE_AFTER = 43200,
  WRITE_INTERVAL = 60,
}

local function valid(v)
  return type(v) == "number" and v == v and v > 0 and v ~= math.huge
end

local function validEntry(e)
  return type(e) == "table" and type(e.seenAt) == "number" and e.seenAt == e.seenAt
    and e.seenAt ~= math.huge and e.seenAt ~= -math.huge
end

function Prices.cacheKey(region, modeID)
  local function ok(v) return type(v) == "string" or type(v) == "number" end
  if not ok(region) or not ok(modeID) then return nil end
  return region .. "-" .. modeID
end

function Prices.formatAge(seconds)
  if seconds >= 86400 then return math.floor(seconds / 86400) .. "d" end
  if seconds >= 3600 then return math.floor(seconds / 3600) .. "h" end
  return math.max(1, math.floor(seconds / 60)) .. "m"
end

function Prices.isStale(seconds)
  return seconds > Prices.STALE_AFTER
end

local Instance = {}
Instance.__index = Instance

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

function Instance:_live(itemID)
  for _, source in ipairs(self.sources) do
    local ok, value = pcall(source.get, itemID)
    if ok and valid(value) then return value, source.name end
  end
  return nil
end

function Instance:lookup(itemID)
  local result = {}
  if self.vendor then
    local ok, v = pcall(self.vendor, itemID)
    if ok and type(v) == "number" and v == v then result.vendor = v end
  end

  -- Disenchant value (live only, nil when the item cannot be disenchanted).
  if self.disenchant then
    local ok, v = pcall(self.disenchant, itemID)
    if ok and valid(v) then result.de = v end
  end

  local now = self.now()
  local okKey, key = pcall(self.key)
  if not okKey then key = nil end
  local bucket = key and self.cache and self.cache[key] or nil
  if type(bucket) ~= "table" then bucket = nil end

  local price, name = self:_live(itemID)
  if price then
    result.ah, result.ahSource, result.ahAge = price, name, 0
    if key and self.cache then
      if not bucket then
        bucket = {}
        self.cache[key] = bucket
      end
      local entry = bucket[itemID]
      local fresh = false
      if validEntry(entry) and entry.price == price then
        local diff = now - entry.seenAt
        fresh = diff >= 0 and diff < Prices.WRITE_INTERVAL
      end
      if not fresh then
        bucket[itemID] = { price = price, seenAt = now }
      end
    end
    return result
  end

  local entry = bucket and bucket[itemID]
  if validEntry(entry) and valid(entry.price) then
    result.ah, result.ahSource, result.ahAge = entry.price, "cache", math.max(0, now - entry.seenAt)
  end
  return result
end

ns.Prices = Prices
