local ADDON, ns = ...

-- Own sales as an auction price source: the average price per unit the
-- player got for an item (auction house and trade sales, Trade.lua), asked
-- after the AnotherLedger scan. It answers with the price and the age of the
-- newest sale, so rows show it as aged like scan prices. No `present` check.
local L = ns.L
local L_NAME = L["Own sales"]

ns.Sources.register({
  key = "sales",
  label = L_NAME,
  create = function(env, setting)
    local function now()
      local clock = type(env) == "table" and env.time or nil
      return type(clock) == "function" and clock() or os.time()
    end
    local function get(itemID, link)
      local Trade, Scan = ns.Trade, ns.Scan
      if not (Trade and Scan) then return nil end
      local bucket = Trade.bucket(ns.db, Scan.currentRealmKey())
      if not bucket then return nil end
      return Trade.salePrice(bucket, itemID, link, now())
    end
    return { name = L_NAME, get = get }
  end,
})
