local ADDON, ns = ...

-- Trade: what the player sells and trades, per realm (shared by all
-- characters, under the same realm key as the scan). Pure: Core reads the
-- client (mail, auction house, chat, trade window) and feeds the functions
-- here; Sources/Sales.lua answers prices and View.lua builds the Trade tab.
--
-- Saved: LootLedgerDB.trade[realmKey] = {
--   log     = { entry, ... } (oldest first, dropped after Trade log kept),
--   totals  = { [itemKey] = { posted, sold, soldAH, expired, cancelled, gold,
--               cmpN, cmpSale, cmpMarket } } (kept for good),
--   posts   = { open posts: { t, key, id, name, n, unit } },
--   pending = { "buyer found" marks: { name, t, market } },
--   mails   = { [mail key] = expires } (mails already recorded),
-- }
--
-- entry = { t, kind, key, id, name, n, gold, cut, market, who, char, split,
--   out, in, goldOut, goldIn }
--   kind: "post", "cancel", "expire", "sale" (auction), "tsale" (trade sale),
--     "tbuy" (trade purchase), "trade" (anything else).
--   gold: total before the cut (sale, tsale, tbuy; post: unit price x n);
--   cut: the auction house cut; market: the market price per unit that day;
--   split: the gold of a trade sale was split between item kinds (estimate);
--   out / in: { { key, id, name, n }, ... } of a trade.
local Trade = {
  DAY = 86400,
  LOG_DAYS = 90,
  POST_DAYS = 2,  -- open posts and "buyer found" marks are kept this long
}

local SALES = { sale = true, tsale = true }

-- ---------------------------------------------------------------------------
-- Store

-- The bucket of `realmKey` in db.trade, made when `create` is set; nil
-- otherwise (also while the realm key is unknown).
function Trade.bucket(db, realmKey, create)
  if type(db) ~= "table" or realmKey == nil then return nil end
  if type(db.trade) ~= "table" then
    if not create then return nil end
    db.trade = {}
  end
  local b = db.trade[realmKey]
  if type(b) ~= "table" or type(b.log) ~= "table" then
    if not create then return nil end
    b = {}
    db.trade[realmKey] = b
  end
  for _, field in ipairs({ "log", "totals", "posts", "pending", "mails" }) do
    if type(b[field]) ~= "table" then b[field] = {} end
  end
  return b
end

local function totalsOf(bucket, key)
  local t = bucket.totals[key]
  if not t then
    t = { posted = 0, sold = 0, soldAH = 0, expired = 0, cancelled = 0, gold = 0,
      cmpN = 0, cmpSale = 0, cmpMarket = 0 }
    bucket.totals[key] = t
  end
  return t
end

-- Appends `entry` to the log and counts it in the totals of its item key
-- (entries without a key, and plain trades and purchases, count in none).
function Trade.add(bucket, entry)
  bucket.log[#bucket.log + 1] = entry
  local key, kind, n = entry.key, entry.kind, entry.n or 0
  if key == nil then return entry end
  if kind == "post" then
    totalsOf(bucket, key).posted = totalsOf(bucket, key).posted + n
  elseif kind == "cancel" then
    totalsOf(bucket, key).cancelled = totalsOf(bucket, key).cancelled + n
  elseif kind == "expire" then
    totalsOf(bucket, key).expired = totalsOf(bucket, key).expired + n
  elseif SALES[kind] then
    local t = totalsOf(bucket, key)
    t.sold = t.sold + n
    if kind == "sale" then t.soldAH = t.soldAH + n end
    t.gold = t.gold + (entry.gold or 0) - (entry.cut or 0)
    if type(entry.market) == "number" and not entry.split then
      t.cmpN = t.cmpN + n
      t.cmpSale = t.cmpSale + (entry.gold or 0)
      t.cmpMarket = t.cmpMarket + entry.market * n
    end
  end
  return entry
end

-- What a finished trade was: "tsale" (only items out, only gold in), "tbuy"
-- (only gold out, only items in) or "trade" (gifts, alt transfers, swaps).
function Trade.classify(out, inItems, goldOut, goldIn)
  local gaveItems, gotItems = #(out or {}) > 0, #(inItems or {}) > 0
  local gaveGold, gotGold = (goldOut or 0) > 0, (goldIn or 0) > 0
  if gaveItems and not gotItems and gotGold and not gaveGold then return "tsale" end
  if gotItems and not gaveItems and gaveGold and not gotGold then return "tbuy" end
  return "trade"
end

local function keepNewer(list, oldest, field)
  local kept = {}
  for _, e in ipairs(list) do
    if type(e) == "table" and (e[field] or 0) >= oldest then kept[#kept + 1] = e end
  end
  return kept
end

-- Drops log entries older than `keepDays` days, open posts and marks older
-- than POST_DAYS and mail keys past their expiry. The totals stay.
function Trade.prune(bucket, now, keepDays)
  if type(bucket) ~= "table" then return end
  local days = type(keepDays) == "number" and keepDays or Trade.LOG_DAYS
  bucket.log = keepNewer(bucket.log, now - days * Trade.DAY, "t")
  bucket.posts = keepNewer(bucket.posts, now - Trade.POST_DAYS * Trade.DAY, "t")
  bucket.pending = keepNewer(bucket.pending, now - Trade.POST_DAYS * Trade.DAY, "t")
  for key, expires in pairs(bucket.mails) do
    if type(expires) ~= "number" or expires < now then bucket.mails[key] = nil end
  end
end

ns.Trade = Trade
