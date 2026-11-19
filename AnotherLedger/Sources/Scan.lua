local ADDON, ns = ...

-- AnotherLedger scan as an auction price source: the prices of the addon's own
-- auction house scans (Scan.lua), asked after TSM and Auctionator. It answers
-- with the price and its age, so rows show how old the scan is. No `present`
-- check: it is AnotherLedger itself, not a price addon.
local L = ns.L
local L_NAME = L["AnotherLedger scan"]

ns.Sources.register({
  key = "scan",
  label = L_NAME,
  create = function(env, setting)
    local function now()
      local clock = type(env) == "table" and env.time or nil
      return type(clock) == "function" and clock() or os.time()
    end
    local function get(itemID, link)
      local Scan = ns.Scan
      local bucket = Scan and Scan.bucket(ns.db, Scan.currentRealmKey())
      if not bucket then return nil end
      local kind = setting("scanPrice") == "lowest" and "lowest" or "market"
      return Scan.lookup(bucket.items, itemID, link, kind, now())
    end
    return { name = L_NAME, get = get }
  end,
})
