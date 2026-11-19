local ADDON, ns = ...

-- LootLedger scan: the addon's own auction house prices, for players without
-- TSM or Auctionator. Pure: the client calls of a scan are injected (see
-- Scan.newReader); Core wires the events and Sources/Scan.lua answers the
-- price lookups.
local Scan = {
  MARKET_SHARE = 0.15, -- the market value averages the cheapest 15% of the listed units
}

-- ---------------------------------------------------------------------------
-- Listing math

-- Market value and lowest unit price of one item's listings
-- ({ { unit = copper, qty = n }, ... }, any order). The cheapest share is
-- counted in units (at least one), so one big cheap stack weighs by its size.
-- Nothing for an empty list.
function Scan.listingValues(listings)
  if type(listings) ~= "table" or #listings == 0 then return end
  local sorted, total = {}, 0
  for i, l in ipairs(listings) do
    sorted[i] = l
    total = total + l.qty
  end
  table.sort(sorted, function(a, b) return a.unit < b.unit end)
  local want = math.max(1, math.floor(total * Scan.MARKET_SHARE + 0.5))
  local taken, sum = 0, 0
  for _, l in ipairs(sorted) do
    local n = math.min(l.qty, want - taken)
    sum = sum + l.unit * n
    taken = taken + n
    if taken >= want then break end
  end
  return math.floor(sum / taken), sorted[1].unit
end

-- ---------------------------------------------------------------------------
-- Daily average and packed storage
--
-- One entry per item key: today's market value and lowest price (m, l) with
-- the time they were seen (t), and the running average of the days before
-- (am, al) up to day ad. A later day folds the old day into the average with
-- a weight that halves every HALF_LIFE_DAYS; a same-day value replaces m / l.
-- Kept this way (not a list of days) so a full scan stays small when saved.

Scan.DAY = 86400
Scan.HALF_LIFE_DAYS = 5
Scan.MAX_AGE = 14 * 86400 -- newer values only: older ones are not used and pruned

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function enc(n)
  n = math.floor(n)
  if n <= 0 then return "0" end
  local s = ""
  while n > 0 do
    local d = n % 36
    s = DIGITS:sub(d + 1, d + 1) .. s
    n = (n - d) / 36
  end
  return s
end

local function day(t) return math.floor(t / Scan.DAY) end

local function weight(fromDay, toDay)
  return 0.5 ^ ((toDay - fromDay) / Scan.HALF_LIFE_DAYS)
end

-- Packed text of an entry: t, m, l and, with an average, am, al, ad, as
-- base-36 integers joined by ",". Only pack / unpack know this format.
function Scan.pack(e)
  local parts = { enc(e.t), enc(e.m), enc(e.l) }
  if e.am then
    parts[4], parts[5], parts[6] = enc(e.am), enc(e.al), enc(e.ad)
  end
  return table.concat(parts, ",")
end

function Scan.unpack(s)
  if type(s) ~= "string" then return nil end
  local n = {}
  for part in (s .. ","):gmatch("([^,]*),") do
    local v = part:match("^[0-9a-z]+$") and tonumber(part, 36)
    if not v then return nil end
    n[#n + 1] = v
  end
  if #n == 3 then return { t = n[1], m = n[2], l = n[3] } end
  if #n == 6 then return { t = n[1], m = n[2], l = n[3], am = n[4], al = n[5], ad = n[6] } end
  return nil
end

-- Records one day's market value and lowest price of `key` at time `now`.
function Scan.record(items, key, market, lowest, now)
  local e = Scan.unpack(items[key])
  market, lowest = math.floor(market), math.floor(lowest)
  if e and day(now) > day(e.t) then
    local d = day(e.t)
    if e.am then
      local w = weight(e.ad, d)
      e.am = e.am * w + e.m * (1 - w)
      e.al = e.al * w + e.l * (1 - w)
    else
      e.am, e.al = e.m, e.l
    end
    e.ad = d
  elseif e and day(now) < day(e.t) then
    return -- an older value than the one saved: keep the newer
  end
  e = e or {}
  e.t, e.m, e.l = now, market, lowest
  items[key] = Scan.pack(e)
end

-- The price of `key` ("market" or "lowest") and its age in seconds, or nil
-- when it is missing, unreadable or older than MAX_AGE.
function Scan.price(items, key, kind, now)
  if type(items) ~= "table" then return nil end
  local e = Scan.unpack(items[key])
  if not e or now - e.t > Scan.MAX_AGE then return nil end
  local today = kind == "lowest" and e.l or e.m
  local value = today
  if e.am then
    local w = weight(e.ad, day(e.t))
    value = (kind == "lowest" and e.al or e.am) * w + today * (1 - w)
  end
  return math.floor(value), math.max(0, now - e.t)
end

-- Drops unreadable and too old entries; returns how many.
function Scan.prune(items, now)
  if type(items) ~= "table" then return 0 end
  local removed = 0
  for key, s in pairs(items) do
    local e = Scan.unpack(s)
    if not e or now - e.t > Scan.MAX_AGE then
      items[key] = nil
      removed = removed + 1
    end
  end
  return removed
end

-- The price of an item: its exact variant (LootParse.itemKey of the link),
-- else the plain item's entry.
function Scan.lookup(items, itemID, link, kind, now)
  if type(items) ~= "table" then return nil end
  local key = ns.LootParse and type(link) == "string" and ns.LootParse.itemKey(link) or nil
  if key ~= nil then
    local v, age = Scan.price(items, key, kind, now)
    if v then return v, age end
  end
  return Scan.price(items, itemID, kind, now)
end

-- ---------------------------------------------------------------------------
-- Chunked reader of a full auction house read

Scan.CHUNK = 2000      -- entries read per frame
Scan.PET_CAGE = 82800  -- every battle pet shares this item ID: not priced
Scan.WAIT = 900        -- the game allows one full read every 15 minutes

-- Reads `o.count()` entries through `o.info(i)` (i from 0; returns qty,
-- buyout, itemID, link) CHUNK per `o.after(0, fn)` call and groups their unit
-- prices per item key (the link's LootParse.itemKey, else the item ID);
-- listings with the same unit price add up. Entries without buyout, without
-- quantity and battle pets are skipped. Ends once, through `o.onDone({ sets,
-- read, total, stopped })`, when everything is read or on reader:stop().
-- `o.onProgress(fraction)` follows each chunk.
function Scan.newReader(o)
  local r = { sets = {}, read = 0, total = 0, finished = false }
  local index = {} -- key -> unit -> position in sets[key]

  local function add(key, unit, qty)
    local set = r.sets[key]
    if not set then
      set = {}
      r.sets[key], index[key] = set, {}
    end
    local at = index[key][unit]
    if at then
      set[at].qty = set[at].qty + qty
    else
      set[#set + 1] = { unit = unit, qty = qty }
      index[key][unit] = #set
    end
  end

  local function finish(stopped)
    if r.finished then return end
    r.finished = true
    o.onDone({ sets = r.sets, read = r.read, total = r.total, stopped = stopped })
  end

  local function chunk()
    if r.finished then return end
    local last = math.min(r.total, r.read + Scan.CHUNK)
    for i = r.read, last - 1 do
      local ok, qty, buyout, itemID, link = pcall(o.info, i)
      if ok and type(qty) == "number" and qty >= 1 and type(buyout) == "number" and buyout > 0
        and type(itemID) == "number" and itemID ~= Scan.PET_CAGE then
        local key = ns.LootParse and type(link) == "string" and ns.LootParse.itemKey(link) or itemID
        add(key, math.floor(buyout / qty), qty)
      end
    end
    r.read = last
    if o.onProgress then o.onProgress(r.total > 0 and r.read / r.total or 1) end
    if r.read >= r.total then finish(false) else o.after(0, chunk) end
  end

  function r:start()
    local ok, n = pcall(o.count)
    r.total = ok and type(n) == "number" and n > 0 and math.floor(n) or 0
    o.after(0, chunk)
  end

  function r:stop() finish(true) end

  return r
end

-- Records the market value and lowest price of every listing set; returns
-- how many keys were priced.
function Scan.commit(bucket, sets, now)
  local priced = 0
  for key, listings in pairs(sets) do
    local market, lowest = Scan.listingValues(listings)
    if market then
      Scan.record(bucket.items, key, market, lowest, now)
      priced = priced + 1
    end
  end
  return priced
end

-- Seconds until the game allows the next full read (0 = ready).
function Scan.waitLeft(scanAt, now)
  if type(scanAt) ~= "number" then return 0 end
  return math.max(0, scanAt + Scan.WAIT - now)
end

-- ---------------------------------------------------------------------------
-- Saved buckets: LootLedgerDB.scan[realmKey] = { lastFull, items }

-- The price cache key (region and game mode) plus the realm: non-commodity
-- listings are per realm. nil while either is unknown.
function Scan.realmKey(cacheKey, realm)
  if cacheKey == nil or type(realm) ~= "string" or realm == "" then return nil end
  return cacheKey .. "-" .. realm
end

-- The bucket of `realmKey` in db.scan, made when `create` is set; nil otherwise.
function Scan.bucket(db, realmKey, create)
  if type(db) ~= "table" or realmKey == nil then return nil end
  if type(db.scan) ~= "table" then
    if not create then return nil end
    db.scan = {}
  end
  local b = db.scan[realmKey]
  if type(b) ~= "table" or type(b.items) ~= "table" then
    if not create then return nil end
    b = { items = {} }
    db.scan[realmKey] = b
  end
  return b
end

-- The current realm key; Core sets the real one at load.
function Scan.currentRealmKey() return nil end

ns.Scan = Scan
