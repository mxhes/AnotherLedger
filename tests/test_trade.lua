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
    gold = 680, cmpN = 4, cmpSale = 400, cmpMarket = 440, bought = 0, spent = 0 })
  h.eq(#b.log, 4)
end)

h.test("Trade.recordMail: an auction won is a purchase, once, counted as bought and spent", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  local m = { kind = "buy", subject = "Auction won: Bolt", sender = "AH", money = 0, expires = 1000,
    name = "Bolt", who = "Seller", gold = 900, n = 3, id = 5, key = "5:1", char = "Me" }
  local e = T.recordMail(b, m, 10)
  h.eq(e.kind, "buy"); h.eq(e.key, "5:1"); h.eq(e.gold, 900); h.eq(e.who, "Seller")
  h.eq(T.recordMail(b, m, 20), nil) -- the same mail read again
  h.eq(b.totals["5:1"].bought, 3)
  h.eq(b.totals["5:1"].spent, 900)
  h.eq(b.totals["5:1"].gold, 0) -- spending is not earning
  -- Without a link: the item ID is the key.
  local byName = T.recordMail(b, { kind = "buy", name = "Ore", gold = 50, n = 1, id = 7, expires = 2000 }, 30)
  h.eq(byName.key, 7)
  -- Totals saved before purchases were recorded have no bought / spent yet.
  b.totals[9] = { posted = 0, sold = 0, soldAH = 0, expired = 0, cancelled = 0, gold = 0, cmpN = 0, cmpSale = 0, cmpMarket = 0 }
  T.add(b, { t = 40, kind = "buy", key = 9, id = 9, n = 2, gold = 20 })
  h.eq(b.totals[9].bought, 2); h.eq(b.totals[9].spent, 20)
end)

h.test("Trade.itemStats: purchases count per item, in the period and all time", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  T.add(b, { t = 100, kind = "buy", key = 5, id = 5, name = "Bolt", n = 4, gold = 400 })
  T.add(b, { t = 200, kind = "sale", key = 5, id = 5, name = "Bolt", n = 2, gold = 500, cut = 25 })
  T.add(b, { t = 300, kind = "buy", key = 6, id = 6, name = "Ore", n = 1, gold = 30 })
  local all = T.itemStats(b, nil, 400)
  h.eq(#all, 2)
  local bolt, ore
  for _, s in ipairs(all) do if s.key == 5 then bolt = s else ore = s end end
  h.eq(bolt.bought, 4); h.eq(bolt.spent, 400); h.eq(bolt.gold, 475); h.eq(#bolt.buys, 1)
  h.eq(ore.bought, 1); h.eq(ore.sold, 0) -- only bought: still listed
  local recent = T.itemStats(b, 150, 400)
  for _, s in ipairs(recent) do
    if s.key == 5 then h.eq(s.bought, 0); h.eq(s.sold, 2) end
  end
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

h.test("Trade.recordMail: a sale is recorded once; another character's mail is its own", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  h.eq(T.recordMail(b, saleMail(), 100, function() return 110 end).kind, "sale")
  h.eq(T.recordMail(b, saleMail(), 200, function() return 110 end), nil)
  h.eq(T.recordMail(b, saleMail({ char = "Alt" }), 300, function() return 110 end).kind, "sale")
  h.eq(#b.log, 2)
end)

h.test("Trade.recordMail: temporary and final invoice are one sale", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  T.recordMail(b, saleMail({ subject = "Sale pending: Bolt", temp = true }), 100, function() end)
  h.eq(T.recordMail(b, saleMail({ money = 380, expires = 30 * 86400 + 3700 }), 3700, function() end), nil)
  h.eq(T.recordMail(b, saleMail({ money = 380, expires = 40 * 86400 }), 9000, function() end).kind, "sale")
end)

h.test("Trade.recordMail: the final invoice read hours after the temporary one is still one sale", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  T.recordMail(b, saleMail({ subject = "Sale pending: Bolt", temp = true }), 100, function() end)
  h.eq(T.recordMail(b, saleMail({ money = 380, expires = 30 * 86400 + 3700 }), 100 + 5 * 3600, function() end), nil)
  h.eq(#b.log, 1); h.eq(b.log[1].temp, nil)
end)

h.test("Trade.recordInbox: two identical sale mails are two sales, also when read again", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  local inbox = { saleMail(), saleMail({ expires = 30 * 86400 + 30 }) }
  h.eq(#T.recordInbox(b, inbox, 100, function() end), 2)
  h.eq(#T.recordInbox(b, inbox, 200, function() end), 0)
  h.eq(#b.log, 2)
end)

h.test("Trade.recordInbox: a mail whose expiry drifts by a few seconds is not counted again", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  local m = { kind = "expire", subject = "Auction expired: Bolt", sender = "AH", money = 0,
    expires = 59 * 60 + 59.6, key = 7, id = 7, name = "Bolt", n = 3, char = "Me" }
  T.recordInbox(b, { m }, 10, function() end)
  local later = {}
  for k, v in pairs(m) do later[k] = v end
  later.expires = 60 * 60 + 0.4 -- across the minute
  h.eq(#T.recordInbox(b, { later }, 3 * 86400, function() end), 0)
  h.eq(b.totals[7].expired, 3)
end)

h.test("Trade.salePrice: stays quick on a big log and follows new sales and pruning", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  for i = 1, 20000 do T.add(b, { t = i, kind = "post", key = i % 50, id = i % 50, n = 1, gold = 10 }) end
  T.add(b, { t = 20001, kind = "sale", key = 5, id = 5, n = 1, gold = 100, cut = 5 })
  local start = os.clock()
  for _ = 1, 2000 do T.salePrice(b, 999, nil, 30000) end
  h.eq(os.clock() - start < 0.5, true)
  h.eq(T.salePrice(b, 5, nil, 30000), 100)
  T.add(b, { t = 20002, kind = "sale", key = 5, id = 5, n = 1, gold = 300, cut = 5 })
  h.eq(T.salePrice(b, 5, nil, 30000), 200)
  T.prune(b, 20001.5 + 90 * T.DAY, 90)
  h.eq(T.salePrice(b, 5, nil, 30000), 300)
  h.eq(T.hasItemID(b, 5), true); h.eq(T.hasItemID(b, 999), false)
end)

h.test("Trade.recordMail: the item comes from the open post, parts of a stack shrink it", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  T.addPost(b, { t = 1, key = 7, id = 7, name = "Bolt", n = 10, unit = 100 })
  local e = T.recordMail(b, saleMail(), 10, function() return 100 end)
  h.eq(e.key, 7); h.eq(b.posts[1].n, 6)
  T.recordMail(b, saleMail({ who = "Other", expires = 30 * 86400 + 99, money = 390 }), 20, function() return 100 end)
  h.eq(b.posts[1].n, 2); h.eq(b.totals[7].sold, 8)
end)

h.test("Trade.recordInbox: a mail gone from a whole inbox read is forgotten, an equal later one counts", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  local first, second = saleMail(), saleMail({ expires = 30 * 86400 + 99 }) -- 87 s apart, same subject and money
  h.eq(#T.recordInbox(b, { first }, 10, function() end, "Me"), 1)
  h.eq(#T.recordInbox(b, {}, 20, function() end, "Me"), 0) -- taken
  h.eq(#T.recordInbox(b, { second }, 110, function() end, "Me"), 1)
  h.eq(#T.recordInbox(b, { second }, 120, function() end, "Me"), 0)
  h.eq(#b.log, 2)
end)

h.test("Trade.recordInbox: a partial read or another character's read forgets nothing", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  T.recordInbox(b, { saleMail() }, 10, function() end, "Me")
  T.recordInbox(b, {}, 20, function() end) -- not every mail could be read
  T.recordInbox(b, {}, 30, function() end, "Alt")
  h.eq(#T.recordInbox(b, { saleMail() }, 40, function() end, "Me"), 0)
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

-- ---------------------------------------------------------------------------
-- Task 3: statistics, gold split and the sale price

h.test("Trade.splitGold: by market value, equal per unit without one, adds up", function()
  local T = ns.Trade
  local items = { { key = 1, n = 1 }, { key = 2, n = 3 } }
  h.eq(T.splitGold(items, 1000, function(k) return 100 end), { 250, 750 })
  h.eq(T.splitGold(items, 1001, function(k) return k == 1 and 100 or nil end), { 250, 751 })
end)

h.test("Trade.addTrade: several item kinds are split and kept out of the price", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  T.addTrade(b, { out = { { key = 1, id = 1, name = "A", n = 1 }, { key = 2, id = 2, name = "B", n = 1 } },
    ["in"] = {}, goldOut = 0, goldIn = 1000, who = "P", char = "Me" }, 10, function() return 100 end)
  h.eq(#b.log, 2); h.eq(b.log[1].split, true); h.eq(b.totals[1].gold, 500)
  h.eq(T.salePrice(b, 1, nil, 20), nil)
end)

h.test("Trade.addTrade: one item kind for gold is a trade sale with its market", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  T.addTrade(b, { out = { { key = 1, id = 1, name = "A", n = 2 } }, ["in"] = {}, goldOut = 0, goldIn = 300,
    who = "P", char = "Me" }, 10, function() return 140 end)
  h.eq(b.log[1].kind, "tsale"); h.eq(b.log[1].gold, 300); h.eq(b.log[1].market, 140)
  h.eq(b.log[1].who, "P"); h.eq(T.salePrice(b, 1, nil, 20), 150)
end)

h.test("Trade.addTrade: a gift is logged without totals", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  T.addTrade(b, { out = { { key = 1, id = 1, name = "A", n = 2 } }, ["in"] = {}, goldOut = 0, goldIn = 0,
    who = "Alt", char = "Me" }, 10, function() end)
  h.eq(b.log[1].kind, "trade"); h.eq(b.totals[1], nil)
end)

h.test("Trade.itemStats: sell rate in units and price against the market", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  T.add(b, { t = 10, kind = "sale", key = 5, id = 5, name = "Bolt", n = 6, gold = 660, cut = 33, market = 100 })
  T.add(b, { t = 10, kind = "expire", key = 5, id = 5, name = "Bolt", n = 2 })
  T.add(b, { t = 10, kind = "tsale", key = 5, id = 5, name = "Bolt", n = 2, gold = 200 })
  local s = T.itemStats(b, nil, 20)[1]
  h.eq(s.sold, 8); h.eq(s.gold, 827); h.near(s.rate, 0.75, 1e-9); h.near(s.vsMarket, 0.1, 1e-9)
  h.eq(#s.sales, 2)
  h.eq(#T.itemStats(b, 15, 20), 0)
  local recent = T.itemStats(b, 5, 20)[1]
  h.eq(recent.sold, 8); h.eq(recent.gold, 827); h.near(recent.rate, 0.75, 1e-9)
end)

h.test("Trade.itemStats: name-only sales are grouped by name", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  T.add(b, { t = 10, kind = "sale", name = "Old thing", n = 1, gold = 50, cut = 0 })
  T.add(b, { t = 11, kind = "sale", name = "Old thing", n = 2, gold = 90, cut = 0 })
  local all = T.itemStats(b, nil, 20)
  h.eq(#all, 1); h.eq(all[1].sold, 3); h.eq(all[1].key, nil); h.eq(all[1].rate, nil)
end)

h.test("Trade.salePrice: weighted average per unit and the age of the newest sale", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  T.add(b, { t = 10, kind = "sale", key = 5, id = 5, n = 1, gold = 100, cut = 5 })
  T.add(b, { t = 40, kind = "tsale", key = 5, id = 5, n = 3, gold = 600 })
  local p, age = T.salePrice(b, 5, nil, 100)
  h.eq(p, 175); h.eq(age, 60)
  h.eq(T.salePrice(b, 6, nil, 100), nil)
end)

h.test("Trade.recordMail: a sale with only an item ID still takes the variant's post by name", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  T.addPost(b, { t = 1, key = "9:100", id = 9, name = "Bracers", n = 1, unit = 5000 })
  local e = T.recordMail(b, saleMail({ name = "Bracers", n = 1, gold = 5000, id = 9 }), 10, function() end)
  h.eq(e.key, "9:100"); h.eq(#b.posts, 0)
  local e2 = T.recordMail(b, saleMail({ name = "Bracers", who = "X", n = 1, gold = 4000, id = 9, money = 3800 }), 20,
    function() end)
  h.eq(e2.key, 9)
end)

-- A sale mail not opened yet has no invoice: only its subject and money.
local function unreadSale(over)
  local m = { kind = "sale", subject = "Auction successful: Bolt (4)", sender = "AH", money = 380,
    expires = 30 * 86400 + 12, name = "Bolt", n = 4, char = "Me", estimate = true }
  for k, v in pairs(over or {}) do m[k] = v end
  return m
end

h.test("Trade.recordMail: an unread sale mail prices the sale from its post, less the cut", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  T.addPost(b, { t = 1, key = 7, id = 7, name = "Bolt", n = 10, unit = 100 })
  local e = T.recordMail(b, unreadSale(), 10, function() return 90 end)
  h.eq(e.kind, "sale"); h.eq(e.key, 7); h.eq(e.n, 4); h.eq(e.gold, 400); h.eq(e.cut, 20)
  h.eq(b.totals[7].sold, 4); h.eq(b.posts[1].n, 6)
end)

h.test("Trade.recordMail: an unread sale mail without a post counts the money received", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  local e = T.recordMail(b, unreadSale(), 10, function() end)
  h.eq(e.gold, 380); h.eq(e.cut, 0)
end)

h.test("Trade.recordMail: a sale mail counts once, read before and after it was opened", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  h.eq(T.recordMail(b, unreadSale(), 10, function() end).kind, "sale")
  -- Opened: the invoice now.
  h.eq(T.recordMail(b, saleMail({ money = 380, subject = "Auction successful: Bolt (4)" }), 20, function() end), nil)
  h.eq(#b.log, 1)
end)

h.test("Trade.recordMail: a sale mail recorded under the old mail key is not counted again", function()
  local T, b = ns.Trade, ns.Trade.bucket({}, "r", true)
  local m = saleMail({ money = 380 })
  b.mails[T.legacyMailKey(m)] = { m.expires }
  h.eq(T.recordMail(b, m, 20, function() end), nil)
  h.eq(#b.log, 0)
end)
