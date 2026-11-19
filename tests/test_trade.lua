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
