local h = ...
local ns = h.load({ "Util.lua", "LootParse.lua", "Trade.lua" })

-- ---------------------------------------------------------------------------
-- Task 1: store, entries and trade kinds

h.test("Trade.classify: only items out for gold in is a sale", function()
  local T, item = ns.Trade, { { key = 1, id = 1, name = "A", n = 1 } }
  h.eq(T.classify(item, {}, 0, 500), "tsale")
  h.eq(T.classify({}, item, 500, 0), "tbuy")
  h.eq(T.classify(item, item, 0, 500), "trade")  -- items both ways
  h.eq(T.classify(item, {}, 100, 500), "trade")  -- gold both ways
  h.eq(T.classify(item, {}, 0, 0), "trade")      -- a gift
  h.eq(T.classify({}, {}, 0, 0), "trade")
end)

h.test("Trade.add: totals per item, earned after the cut, compared sales only with a market", function()
  local b = ns.Trade.bucket({}, "eu-Realm", true)
  ns.Trade.add(b, { t = 1, kind = "post", key = 5, id = 5, n = 10, gold = 1000 })
  ns.Trade.add(b, { t = 2, kind = "sale", key = 5, id = 5, n = 4, gold = 400, cut = 20, market = 110 })
  ns.Trade.add(b, { t = 3, kind = "tsale", key = 5, id = 5, n = 2, gold = 300, split = true, market = 110 })
  ns.Trade.add(b, { t = 4, kind = "expire", key = 5, id = 5, n = 6 })
  h.eq(b.totals[5], { posted = 10, sold = 6, soldAH = 4, expired = 6, cancelled = 0,
    gold = 680, cmpN = 4, cmpSale = 400, cmpMarket = 440 })
  h.eq(#b.log, 4)
end)

h.test("Trade.prune: old log entries go, totals stay", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  T.add(b, { t = 0, kind = "sale", key = 1, id = 1, n = 1, gold = 10, cut = 0 })
  T.add(b, { t = 100 * T.DAY, kind = "sale", key = 1, id = 1, n = 1, gold = 10, cut = 0 })
  T.prune(b, 100 * T.DAY, 90)
  h.eq(#b.log, 1); h.eq(b.totals[1].sold, 2)
end)

h.test("Trade.bucket: nil without create or realm key", function()
  h.eq(ns.Trade.bucket({}, "r"), nil); h.eq(ns.Trade.bucket({}, nil, true), nil)
end)

-- ---------------------------------------------------------------------------
-- Task 2: posts, sold marks and mail recording

local function saleMail(over)
  local m = { kind = "sale", subject = "Auction successful: Bolt", sender = "AH", money = 0,
    expires = 30 * 86400 + 12, name = "Bolt", who = "Buyer", gold = 400, cut = 20, n = 4, char = "Me" }
  for k, v in pairs(over or {}) do m[k] = v end
  return m
end

h.test("Trade.recordMail: a sale is recorded once, also from a second character", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  h.eq(T.recordMail(b, saleMail(), 100, function() return 110 end).kind, "sale")
  h.eq(T.recordMail(b, saleMail(), 200, function() return 110 end), nil)
  h.eq(T.recordMail(b, saleMail({ char = "Alt" }), 300, function() return 110 end), nil)
  h.eq(#b.log, 1)
end)

h.test("Trade.recordMail: temporary and final invoice are one sale", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  T.recordMail(b, saleMail({ subject = "Sale pending: Bolt" }), 100, function() end)
  h.eq(T.recordMail(b, saleMail({ money = 380, expires = 30 * 86400 + 3700 }), 3700, function() end), nil)
  h.eq(T.recordMail(b, saleMail({ money = 380, expires = 40 * 86400 }), 100 + T.JOIN_WINDOW + 1, function() end).kind, "sale")
end)

h.test("Trade.recordMail: the item comes from the open post, parts of a stack shrink it", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  T.addPost(b, { t = 1, key = 7, id = 7, name = "Bolt", n = 10, unit = 100 })
  local e = T.recordMail(b, saleMail(), 10, function() return 100 end)
  h.eq(e.key, 7); h.eq(b.posts[1].n, 6)
  T.recordMail(b, saleMail({ who = "Other", expires = 30 * 86400 + 99 }), 20, function() return 100 end)
  h.eq(b.posts[1].n, 2); h.eq(b.totals[7].sold, 8)
end)

h.test("Trade.recordMail: the market from the chat mark wins over the mailbox day", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  T.markSold(b, "Bolt", 5, 90)
  h.eq(T.recordMail(b, saleMail(), 900, function() return 200 end).market, 90)
  h.eq(#b.pending, 0)
end)

h.test("Trade.recordMail: a sale without a post or ID counts by name only", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  local e = T.recordMail(b, saleMail(), 10, function() return nil end)
  h.eq(e.key, nil); h.eq(e.name, "Bolt"); h.eq(e.market, nil)
end)

h.test("Trade.recordMail: a cancel mail is not counted again", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  h.eq(T.recordMail(b, { kind = "cancel", subject = "Auction cancelled: Bolt", sender = "AH", money = 0,
    expires = 99, key = 7, id = 7, name = "Bolt", n = 3 }, 10, function() end), nil)
  h.eq(#b.log, 0)
end)

h.test("Trade.cancel and expire mails take the amount off the open post", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  T.addPost(b, { t = 1, key = 7, id = 7, name = "Bolt", n = 10, unit = 100 })
  T.cancel(b, { t = 2, key = 7, id = 7, name = "Bolt", n = 3 })
  h.eq(b.posts[1].n, 7); h.eq(b.totals[7].cancelled, 3)
  T.recordMail(b, { kind = "expire", subject = "Auction expired: Bolt", sender = "AH", money = 0,
    expires = 500, key = 7, id = 7, name = "Bolt", n = 7 }, 10, function() end)
  h.eq(#b.posts, 0); h.eq(b.totals[7].expired, 7); h.eq(b.totals[7].posted, 10)
end)
