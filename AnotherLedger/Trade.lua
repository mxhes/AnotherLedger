local ADDON, ns = ...

-- Trade: what the player sells and trades, per realm (shared by all
-- characters, under the same realm key as the scan). Pure: Core reads the
-- client (mail, auction house, chat, trade window) and feeds the functions
-- here; Sources/Sales.lua answers prices and View.lua builds the Trade tab.
--
-- Saved: AnotherLedgerDB.trade[realmKey] = {
--   log     = { entry, ... } (oldest first, dropped after Trade log kept),
--   totals  = { [itemKey] = { posted, sold, soldAH, expired, cancelled, gold,
--               cmpN, cmpSale, cmpMarket, bought, spent } } (kept for good),
--   posts   = { open posts: { t, key, id, name, n, unit } },
--   pending = { "buyer found" marks: { name, t, market } },
--   mails   = { [mail key] = { expires, ... } } (mails already recorded:
--               the expiry of each copy, per character),
-- }
--
-- entry = { t, kind, key, id, name, n, gold, cut, market, who, char, split,
--   out, in, goldOut, goldIn }
--   kind: "post", "cancel", "expire", "sale" (auction), "buy" (auction
--     purchase), "tsale" (trade sale), "tbuy" (trade purchase), "trade"
--     (anything else).
--   gold: total before the cut (sale, tsale, tbuy; post: unit price x n;
--     buy: what was paid);
--   cut: the auction house cut; market: the market price per unit that day;
--   split: the gold of a trade sale was split between item kinds (estimate);
--   out / in: { { key, id, name, n }, ... } of a trade.
local Trade = {
  DAY = 86400,
  LOG_DAYS = 90,
  POST_DAYS = 2,  -- open posts and "buyer found" marks are kept this long
}

local SALES = { sale = true, tsale = true }
-- Entries counted in the totals of their item key.
local COUNTED = { post = true, cancel = true, expire = true, sale = true, tsale = true, buy = true }

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
      cmpN = 0, cmpSale = 0, cmpMarket = 0, bought = 0, spent = 0 }
    bucket.totals[key] = t
  end
  return t
end

-- Counts `entry` into the totals table `t` of its item.
local function countInto(t, entry)
  local kind, n = entry.kind, entry.n or 0
  if kind == "post" then
    t.posted = t.posted + n
  elseif kind == "cancel" then
    t.cancelled = t.cancelled + n
  elseif kind == "expire" then
    t.expired = t.expired + n
  elseif kind == "buy" then
    -- Totals saved before purchases were recorded have no such fields.
    t.bought = (t.bought or 0) + n
    t.spent = (t.spent or 0) + (entry.gold or 0)
  elseif SALES[kind] then
    t.sold = t.sold + n
    if kind == "sale" then t.soldAH = t.soldAH + n end
    t.gold = t.gold + (entry.gold or 0) - (entry.cut or 0)
    if type(entry.market) == "number" and not entry.split then
      t.cmpN = t.cmpN + n
      t.cmpSale = t.cmpSale + (entry.gold or 0)
      t.cmpMarket = t.cmpMarket + entry.market * n
    end
  end
end

-- Appends `entry` to the log and counts it in the totals of its item key
-- (entries without a key, and plain trades and trade purchases, count in
-- none).
local indexes = setmetatable({}, { __mode = "k" }) -- bucket -> sale price index (not saved)

function Trade.add(bucket, entry)
  indexes[bucket] = nil
  bucket.log[#bucket.log + 1] = entry
  if entry.key ~= nil and COUNTED[entry.kind] then
    countInto(totalsOf(bucket, entry.key), entry)
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
  indexes[bucket] = nil
  for key, list in pairs(bucket.mails) do
    local kept = {}
    if type(list) == "table" then
      for _, expires in ipairs(list) do
        if type(expires) == "number" and expires >= now then kept[#kept + 1] = expires end
      end
    end
    bucket.mails[key] = #kept > 0 and kept or nil
  end
end

-- ---------------------------------------------------------------------------
-- Auction house: posts, cancels, "buyer found" marks and mails

Trade.MAIL_DRIFT = 300 -- seconds a mail's computed expiry may move between two reads

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

-- The key of a mail: what does not change while it sits in the inbox, and
-- whose inbox it is (each mail lives in one character's inbox). Copies with
-- the same key are told apart by their expiry (Trade.recordMail).
function Trade.mailKey(m)
  return table.concat({ part(m.char), part(m.kind), part(m.subject), part(m.sender), part(m.money),
    part(m.name), part(m.who), part(m.gold), part(m.n) }, "|")
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

-- Whether this copy of a mail was recorded before: one remembered expiry
-- (within MAIL_DRIFT) per copy. `used` = { [list] = { [index] = true } }
-- keeps one inbox read from matching the same copy twice. A new copy's
-- expiry is remembered (marked used).
local function seenBefore(bucket, key, expires, used)
  local list = bucket.mails[key]
  if type(list) ~= "table" then
    list = {}
    bucket.mails[key] = list
  end
  used[list] = used[list] or {}
  for i, e in ipairs(list) do
    if not used[list][i] and math.abs(e - expires) <= Trade.MAIL_DRIFT then
      used[list][i] = true
      return true
    end
  end
  list[#list + 1] = expires
  used[list][#list] = true
  return false
end

-- The newest sale still waiting for its final invoice (temporary invoice
-- recorded, `temp` = its sale key), or nil.
local function waitingSale(bucket, saleKey)
  for i = #bucket.log, 1, -1 do
    local e = bucket.log[i]
    if e.temp == saleKey then return e end
  end
  return nil
end

-- Records an auction mail once. m = { kind = "sale" / "buy" / "expire" / "cancel",
-- subject, sender, money, expires, name, who, gold, cut, n, key, id, char,
-- temp } (temp: a temporary invoice, sent before the money). `marketAt(key,
-- id)` gives the market per unit now, asked only when no "buyer found" mark
-- has it. `used`: see seenBefore (one per inbox read; Trade.recordInbox).
-- Returns the new entry, or nil when this copy is already recorded, for the
-- final invoice of a sale whose temporary one was recorded, or for a cancel
-- mail (counted at the auction house already).
function Trade.recordMail(bucket, m, now, marketAt, used)
  local expires = type(m.expires) == "number" and m.expires or now + 31 * Trade.DAY
  if seenBefore(bucket, Trade.mailKey(m), expires, used or {}) then return nil end
  if m.kind == "cancel" then return nil end

  if m.kind == "expire" then
    takeFromPost(bucket, m.n, byKey(m.key))
    return Trade.add(bucket, { t = now, kind = "expire", key = m.key, id = m.id, name = m.name, n = m.n, char = m.char })
  end
  if m.kind == "buy" then
    -- An auction won: the item (attached) is known by link or by name.
    local key = m.key ~= nil and m.key or m.id
    return Trade.add(bucket, { t = now, kind = "buy", key = key, id = m.id, name = m.name, n = m.n,
      gold = m.gold, who = m.who, char = m.char })
  end
  if m.kind ~= "sale" then return nil end

  local saleKey = Trade.saleKey(m)
  if not m.temp then
    local waiting = waitingSale(bucket, saleKey)
    if waiting then
      waiting.temp = nil
      return nil
    end
  end

  local key, id = m.key, m.id
  local post = takeFromPost(bucket, m.n, function(p)
    if key ~= nil then return p.key == key end
    return p.name == m.name
  end)
  if key == nil then
    -- The newest open post of that name gives the item key (a variant
    -- too); else the item ID the client found for the name, if any.
    if post then key, id = post.key, post.id else key = id end
  end
  local _, market = takeMark(bucket, m.name)
  if market == nil and key ~= nil and type(marketAt) == "function" then market = marketAt(key, id) end
  return Trade.add(bucket, { t = now, kind = "sale", key = key, id = id, name = m.name, n = m.n,
    gold = m.gold, cut = m.cut, market = market, who = m.who, char = m.char, temp = m.temp and saleKey or nil })
end

-- Records the mails of one inbox read (Core: MAIL_INBOX_UPDATE). Temporary
-- invoices go first, so a final invoice read together with its temporary
-- one settles it. Returns the new entries.
function Trade.recordInbox(bucket, mails, now, marketAt)
  local ordered = {}
  for _, m in ipairs(mails) do if m.temp then ordered[#ordered + 1] = m end end
  for _, m in ipairs(mails) do if not m.temp then ordered[#ordered + 1] = m end end
  local used, added = {}, {}
  for _, m in ipairs(ordered) do
    local e = Trade.recordMail(bucket, m, now, marketAt, used)
    if e then added[#added + 1] = e end
  end
  return added
end

-- ---------------------------------------------------------------------------
-- Player trades

-- Splits `gold` between `items` ({ { key, id, n }, ... }) by each item's
-- market value x amount; equally per unit when any item has no market.
-- `marketOf(key, id)` gives the market per unit. The parts add up to `gold`
-- (the rest of the rounding goes to the last item).
function Trade.splitGold(items, gold, marketOf)
  local weights, sum, priced = {}, 0, true
  for i, item in ipairs(items) do
    local m = type(marketOf) == "function" and marketOf(item.key, item.id) or nil
    if type(m) ~= "number" or m <= 0 then priced = false end
    weights[i] = m
  end
  for i, item in ipairs(items) do
    weights[i] = (priced and weights[i] or 1) * (item.n or 0)
    sum = sum + weights[i]
  end
  local parts, given = {}, 0
  for i = 1, #items do
    if i == #items then
      parts[i] = gold - given
    else
      parts[i] = sum > 0 and math.floor(gold * weights[i] / sum) or 0
      given = given + parts[i]
    end
  end
  return parts
end

-- Records a finished trade. snap = { out, in, goldOut, goldIn, who, char }
-- (out / in = { { key, id, name, n }, ... }). A trade sale logs one "tsale"
-- per item kind (several kinds: the gold split, marked `split`); a purchase
-- or any other trade logs one entry with both sides (no totals).
function Trade.addTrade(bucket, snap, now, marketOf)
  local out, inItems = snap.out or {}, snap["in"] or {}
  local kind = Trade.classify(out, inItems, snap.goldOut, snap.goldIn)
  if kind ~= "tsale" then
    local gold = kind == "tbuy" and snap.goldOut or snap.goldIn
    return Trade.add(bucket, { t = now, kind = kind, out = out, ["in"] = inItems,
      goldOut = snap.goldOut or 0, goldIn = snap.goldIn or 0, gold = gold or 0,
      who = snap.who, char = snap.char })
  end
  local parts = Trade.splitGold(out, snap.goldIn, marketOf)
  local split = #out > 1 or nil
  for i, item in ipairs(out) do
    local market = type(marketOf) == "function" and marketOf(item.key, item.id) or nil
    Trade.add(bucket, { t = now, kind = "tsale", key = item.key, id = item.id, name = item.name, n = item.n,
      gold = parts[i], market = market, split = split, who = snap.who, char = snap.char })
  end
end

-- ---------------------------------------------------------------------------
-- Statistics and the own sale price

local function groupOf(e)
  if e.key ~= nil then return e.key end
  if type(e.name) == "string" then return "name:" .. e.name end
  return nil
end

local function emptyStat(key, e)
  return { key = key, id = e.id, name = e.name, posted = 0, sold = 0, soldAH = 0, expired = 0, cancelled = 0,
    gold = 0, cmpN = 0, cmpSale = 0, cmpMarket = 0, bought = 0, spent = 0, sales = {}, buys = {} }
end

-- Per item: { key, id, name, sold, soldAH, gold, expired, cancelled, bought,
-- spent, rate, vsMarket, sales, buys } from the log entries since `since` (a
-- time), or from the totals when `since` is nil (sales and purchases always
-- from the log, newest first).
-- rate = sold at the auction house / (that + expired + cancelled), nil
-- without auction events; vsMarket = sale / market - 1 over the compared
-- sales, nil without one. Items not yet sold, returned or bought are left
-- out.
function Trade.itemStats(bucket, since, now)
  local groups, order = {}, {}
  local function stat(group, e)
    local s = groups[group]
    if not s then
      s = emptyStat(group ~= nil and e.key or nil, e)
      groups[group] = s
      order[#order + 1] = group
    end
    if s.name == nil then s.name = e.name end
    if s.id == nil then s.id = e.id end
    return s
  end
  -- The log: counts (with `since`, and always for name-only sales), names
  -- and the sales lists.
  for i = #bucket.log, 1, -1 do
    local e = bucket.log[i]
    local group = groupOf(e)
    if group ~= nil and (since == nil or (e.t or 0) >= since) then
      local s = stat(group, e)
      if SALES[e.kind] then s.sales[#s.sales + 1] = e end
      if e.kind == "buy" then s.buys[#s.buys + 1] = e end
      if since ~= nil or e.key == nil then countInto(s, e) end
    end
  end
  -- All time: the totals of keyed items.
  if since == nil then
    for key, t in pairs(bucket.totals) do
      local s = groups[key]
      if not s then
        s = emptyStat(key, { id = type(key) == "number" and key or nil })
        groups[key] = s
        order[#order + 1] = key
      end
      for _, f in ipairs({ "posted", "sold", "soldAH", "expired", "cancelled", "gold", "cmpN", "cmpSale", "cmpMarket",
        "bought", "spent" }) do
        s[f] = t[f] or 0
      end
    end
  end
  local list = {}
  for _, group in ipairs(order) do
    local s = groups[group]
    if s.sold > 0 or s.expired + s.cancelled > 0 or s.bought > 0 then
      local ah = s.soldAH + s.expired + s.cancelled
      -- Name-only sales have no posts or returns to weigh against: no rate.
      s.rate = (s.key ~= nil and ah > 0) and s.soldAH / ah or nil
      s.vsMarket = s.cmpMarket > 0 and s.cmpSale / s.cmpMarket - 1 or nil
      list[#list + 1] = s
    end
  end
  return list
end

-- The sale price index of a bucket, built in one pass over the log and kept
-- until the log changes (Trade.add, Trade.prune): per item key { gold, n,
-- newest } of its sales without a split, and the item IDs in the log.
local function indexOf(bucket)
  local idx = indexes[bucket]
  if idx then return idx end
  idx = { keys = {}, ids = {} }
  for _, e in ipairs(bucket.log) do
    if e.id ~= nil then idx.ids[e.id] = true end
    if SALES[e.kind] and e.key ~= nil and not e.split and (e.n or 0) > 0 then
      local k = idx.keys[e.key]
      if not k then
        k = { gold = 0, n = 0, newest = e.t }
        idx.keys[e.key] = k
      end
      k.gold, k.n = k.gold + (e.gold or 0), k.n + e.n
      if e.t > k.newest then k.newest = e.t end
    end
  end
  indexes[bucket] = idx
  return idx
end

-- The own sale price of an item: the amount-weighted average gold per unit
-- (before the cut) of its sales in the log, trade sales with a split left
-- out; and the age of the newest of them. nil without such a sale.
function Trade.salePrice(bucket, itemID, link, now)
  if type(bucket) ~= "table" then return nil end
  local key = itemID
  if type(link) == "string" and ns.LootParse then key = ns.LootParse.itemKey(link) or itemID end
  if key == nil then return nil end
  local k = indexOf(bucket).keys[key]
  if not k or k.n <= 0 then return nil end
  return math.floor(k.gold / k.n + 0.5), math.max(0, now - k.newest)
end

-- Whether an item ID appears anywhere in the bucket's log (Trade tab: redraw
-- when its item info arrives).
function Trade.hasItemID(bucket, itemID)
  return type(bucket) == "table" and itemID ~= nil and indexOf(bucket).ids[itemID] == true
end

ns.Trade = Trade
