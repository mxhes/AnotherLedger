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

-- ---------------------------------------------------------------------------
-- Auction house: posts, cancels, "buyer found" marks and mails

Trade.JOIN_WINDOW = 7200 -- a second invoice of the same sale within this many seconds is the same sale

-- Logs a posted auction and keeps it open, so a sale mail (which only names
-- the item) finds its item key. post = { t, key, id, name, n, unit }.
function Trade.addPost(bucket, post)
  local n, unit = post.n or 0, post.unit or 0
  Trade.add(bucket, { t = post.t, kind = "post", key = post.key, id = post.id, name = post.name,
    n = n, gold = unit * n, char = post.char })
  bucket.posts[#bucket.posts + 1] = { t = post.t, key = post.key, id = post.id, name = post.name, n = n, unit = unit }
end

-- Takes `n` off the newest open post that `match` accepts; returns that post
-- (nil without one). An emptied post is dropped.
local function takeFromPost(bucket, n, match)
  for i = #bucket.posts, 1, -1 do
    local p = bucket.posts[i]
    if match(p) then
      p.n = (p.n or 0) - (n or 0)
      if p.n <= 0 then table.remove(bucket.posts, i) end
      return p
    end
  end
  return nil
end

local function byKey(key)
  return function(p) return key ~= nil and p.key == key end
end

-- A cancelled auction (from the auction house): logged, and its amount off
-- the open post. c = { t, key, id, name, n, char }.
function Trade.cancel(bucket, c)
  Trade.add(bucket, { t = c.t, kind = "cancel", key = c.key, id = c.id, name = c.name, n = c.n, char = c.char })
  takeFromPost(bucket, c.n, byKey(c.key))
end

-- The "buyer found" chat line: remembers the market of that moment for the
-- sale mail that comes later (no sale yet).
function Trade.markSold(bucket, name, now, market)
  bucket.pending[#bucket.pending + 1] = { name = name, t = now, market = market }
end

local function part(v) return v == nil and "" or tostring(v) end

-- The key of a mail: what does not change while it sits in the inbox.
function Trade.mailKey(m)
  local expires = type(m.expires) == "number" and math.floor(m.expires / 60) or ""
  return table.concat({ part(m.kind), part(m.subject), part(m.sender), part(m.money), part(m.name),
    part(m.who), part(m.gold), part(m.n), part(expires) }, "|")
end

-- The key of a sale: the same for its temporary and its final invoice.
function Trade.saleKey(m)
  return table.concat({ part(m.name), part(m.who), part(m.gold), part(m.n) }, "|")
end

-- The market of the oldest "buyer found" mark of `name` (removed), or nil.
local function takeMark(bucket, name)
  for i, mark in ipairs(bucket.pending) do
    if mark.name == name then
      table.remove(bucket.pending, i)
      return true, mark.market
    end
  end
  return false
end

-- Records an auction mail once. m = { kind = "sale" / "expire" / "cancel",
-- subject, sender, money, expires, name, who, gold, cut, n, key, id, char }.
-- `marketAt(key, id)` gives the market per unit now, asked only when no
-- "buyer found" mark has it. Returns the new entry, or nil when the mail (or
-- the other invoice of the same sale) is already recorded, or for a cancel
-- mail (counted at the auction house already).
function Trade.recordMail(bucket, m, now, marketAt)
  local mailKey = Trade.mailKey(m)
  if bucket.mails[mailKey] then return nil end
  bucket.mails[mailKey] = type(m.expires) == "number" and m.expires or now + 31 * Trade.DAY
  if m.kind == "cancel" then return nil end

  if m.kind == "expire" then
    takeFromPost(bucket, m.n, byKey(m.key))
    return Trade.add(bucket, { t = now, kind = "expire", key = m.key, id = m.id, name = m.name, n = m.n, char = m.char })
  end
  if m.kind ~= "sale" then return nil end

  local saleKey = "s:" .. Trade.saleKey(m)
  local until_ = bucket.mails[saleKey]
  if type(until_) == "number" and until_ >= now then return nil end
  bucket.mails[saleKey] = now + Trade.JOIN_WINDOW

  local key, id = m.key, m.id
  local post = takeFromPost(bucket, m.n, function(p)
    if key ~= nil then return p.key == key end
    return p.name == m.name
  end)
  if key == nil and post then key, id = post.key, post.id end
  local _, market = takeMark(bucket, m.name)
  if market == nil and key ~= nil and type(marketAt) == "function" then market = marketAt(key, id) end
  return Trade.add(bucket, { t = now, kind = "sale", key = key, id = id, name = m.name, n = m.n,
    gold = m.gold, cut = m.cut, market = market, who = m.who, char = m.char })
end

ns.Trade = Trade
