local ADDON, ns = ...

-- Core's AnotherLedger scan section (loads after Core.lua, before Boot.lua):
-- the scan command, the full read and the passive search results.

local L = ns.L
local Core = ns.Core
local events = Core.events
local say = ns.Util.say
local num = ns.Util.isNumber
local tradeWindows = Core.tradeWindows
local function requestRefresh(delay) Core.requestRefresh(delay) end

-- AnotherLedger scan (Scan.lua): a full auction house read on request and the
-- search results the player opens, also next to TSM and Auctionator (Auto asks
-- them first; the scan answers for items they have no price for).

local L_SCAN_DONE = L["Scan done: %s items priced (%.1f s)."]
local L_SCAN_STOPPED = L["Scan stopped: the auction house was closed. %s items priced."]
local L_SCAN_WAIT = L["The game allows the next full scan in %s."]
local L_SCAN_REFUSED = L["The game did not answer the scan. Try again later."]
local L_SCAN_CLOSED = L["Open the auction house to scan."]
local L_SCAN_OFF = L["The game offers no auction house scan."]
local L_SCAN_NO_REALM = L["The realm is not known yet. Try again in a moment."]
local L_SCAN_REMIND = L["Your last auction house scan is more than a day old: /al scan or the AnotherLedger scan button."]
local SCAN_ANSWER_SECONDS = 60 -- no full read within this: the game refused it
local SCAN_REMIND_AFTER = 86400

-- reader: the running Scan.newReader or false; pending: ReplicateItems sent,
-- its event not come yet; token: the pending request (its 60 s check).
local scan = { reader = false, pending = false, token = 0, fraction = 0, reminded = false }
Core.onScanChange = false -- set by UI/ScanButton.lua: called on every change

local function scanChanged()
  if Core.onScanChange then pcall(Core.onScanChange) end
end

-- The realm key of the scan buckets (Scan.realmKey): price cache key + realm.
local function currentRealmKey()
  local realm
  if type(GetRealmName) == "function" then
    local ok, name = pcall(GetRealmName)
    if ok then realm = name end
  end
  return ns.Scan.realmKey(Core.cacheKey(), realm)
end
if ns.Scan then ns.Scan.currentRealmKey = currentRealmKey end

local function scanBucket(create)
  return ns.Scan.bucket(ns.db, ns.Scan.currentRealmKey(), create)
end

local function clock()
  return type(GetTime) == "function" and GetTime() or time()
end

function Core.auctionHouseOpen()
  return tradeWindows.AUCTION_HOUSE == true
end

-- Scanning is offered whenever the client has the auction house API, also
-- next to TSM and Auctionator.
function Core.scanAvailable(env)
  env = env or _G
  local ah = env.C_AuctionHouse
  return type(ah) == "table" and type(ah.ReplicateItems) == "function"
end

-- For the scan button: { running, fraction (0..1), waitLeft (seconds) }.
function Core.scanState()
  return {
    running = scan.reader ~= false or scan.pending,
    fraction = scan.fraction,
    waitLeft = ns.Scan.waitLeft(ns.chardb and ns.chardb.scanAt, time()),
  }
end

local function finishScan(stats)
  scan.reader = false
  local bucket = scanBucket(true)
  local priced = bucket and ns.Scan.commit(bucket, stats.sets, time()) or 0
  if stats.stopped then
    say(L_SCAN_STOPPED:format(priced))
  else
    if bucket then bucket.lastFull = time() end
    say(L_SCAN_DONE:format(priced, math.max(0, clock() - (scan.startedAt or clock()))))
  end
  requestRefresh()
  scanChanged()
end

-- Starts a full read. Returns true, or false and why: "closed" (no auction
-- house), "unavailable" (no API), "realm" (the realm
-- key is not known yet: the read would have nowhere to go), "running",
-- "wait" (plus the seconds left) or "refused" (the call failed).
function Core.startScan()
  if not tradeWindows.AUCTION_HOUSE then return false, "closed" end
  if not Core.scanAvailable(_G) then return false, "unavailable" end
  if scan.reader or scan.pending then return false, "running" end
  if ns.Scan.currentRealmKey() == nil then return false, "realm" end
  local now = time()
  local left = ns.Scan.waitLeft(ns.chardb.scanAt, now)
  if left > 0 then return false, "wait", left end
  -- Client API: C_AuctionHouse.ReplicateItems, answered by
  -- REPLICATE_ITEM_LIST_UPDATE; the game allows one call per 15 minutes.
  if not pcall(C_AuctionHouse.ReplicateItems) then return false, "refused" end
  local previous = ns.chardb.scanAt
  ns.chardb.scanAt = now
  scan.pending, scan.fraction, scan.startedAt = true, 0, clock()
  scan.token = scan.token + 1
  local token = scan.token
  if C_Timer and C_Timer.After then
    C_Timer.After(SCAN_ANSWER_SECONDS, function()
      if not (scan.pending and scan.token == token) then return end
      scan.pending = false
      ns.chardb.scanAt = previous
      say(L_SCAN_REFUSED)
      scanChanged()
    end)
  end
  scanChanged()
  return true
end

-- /al scan and the button: starts a scan and says why when it cannot.
function Core.scanCommand()
  local ok, why, left = Core.startScan()
  if ok or why == "running" then return ok end
  if why == "closed" then say(L_SCAN_CLOSED)
  elseif why == "unavailable" then say(L_SCAN_OFF)
  elseif why == "realm" then say(L_SCAN_NO_REALM)
  elseif why == "wait" then say(L_SCAN_WAIT:format(ns.Util.shortAge(left)))
  else say(L_SCAN_REFUSED) end
  return false
end

-- Client API: GetNumReplicateItems, GetReplicateItemInfo
-- (0-based index; count 3rd, buyout 10th, itemID 17th return) and
-- GetReplicateItemLink (may be nil for items the client has not loaded: the
-- reader then keys the entry by its item ID).
function events.REPLICATE_ITEM_LIST_UPDATE()
  if not scan.pending then return end
  scan.pending = false
  local api = C_AuctionHouse
  scan.reader = ns.Scan.newReader({
    count = api.GetNumReplicateItems,
    info = function(i)
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = api.GetReplicateItemInfo(i)
      return count, buyout, itemID, api.GetReplicateItemLink(i)
    end,
    after = C_Timer.After,
    onProgress = function(f)
      scan.fraction = f
      scanChanged()
    end,
    onDone = finishScan,
  })
  scan.reader:start()
end

-- Passive recording: a full set of search results the player opened.
local function recordSets(sets)
  if not next(sets) then return end
  local bucket = scanBucket(true)
  if bucket and ns.Scan.commit(bucket, sets, time()) > 0 then requestRefresh() end
end

local function passiveOn()
  return tradeWindows.AUCTION_HOUSE and Core.scanAvailable(_G)
end

-- Client API: HasFullCommoditySearchResults,
-- GetNumCommoditySearchResults, GetCommoditySearchResultInfo (1-based;
-- unitPrice, quantity).
function events.COMMODITY_SEARCH_RESULTS_UPDATED(itemID)
  if not passiveOn() or type(itemID) ~= "number" then return end
  local api = C_AuctionHouse
  local ok, full = pcall(api.HasFullCommoditySearchResults, itemID)
  if not (ok and full) then return end
  local list = {}
  local okN, n = pcall(api.GetNumCommoditySearchResults, itemID)
  for i = 1, okN and type(n) == "number" and n or 0 do
    local got, r = pcall(api.GetCommoditySearchResultInfo, itemID, i)
    if got and type(r) == "table" and num(r.unitPrice) and r.unitPrice > 0 and num(r.quantity) and r.quantity >= 1 then
      list[#list + 1] = { unit = r.unitPrice, qty = r.quantity }
    end
  end
  recordSets(#list > 0 and { [itemID] = list } or {})
end

-- Client API: HasFullItemSearchResults,
-- GetNumItemSearchResults, GetItemSearchResultInfo (1-based; buyoutAmount,
-- quantity, itemLink). Grouped by variant (LootParse.itemKey of the link).
function events.ITEM_SEARCH_RESULTS_UPDATED(itemKey)
  if not passiveOn() or type(itemKey) ~= "table" then return end
  -- Battle pets all share the cage item ID: never priced.
  if itemKey.itemID == ns.Scan.PET_CAGE then return end
  if num(itemKey.battlePetSpeciesID) and itemKey.battlePetSpeciesID > 0 then return end
  local api = C_AuctionHouse
  local ok, full = pcall(api.HasFullItemSearchResults, itemKey)
  if not (ok and full) then return end
  local sets = {}
  local okN, n = pcall(api.GetNumItemSearchResults, itemKey)
  for i = 1, okN and type(n) == "number" and n or 0 do
    local got, r = pcall(api.GetItemSearchResultInfo, itemKey, i)
    if got and type(r) == "table" and num(r.buyoutAmount) and r.buyoutAmount > 0 then
      local qty = num(r.quantity) and r.quantity >= 1 and r.quantity or 1
      local key = ns.LootParse.itemKey(r.itemLink) or itemKey.itemID
      if key ~= nil then
        sets[key] = sets[key] or {}
        local set = sets[key]
        set[#set + 1] = { unit = math.floor(r.buyoutAmount / qty), qty = qty }
      end
    end
  end
  recordSets(sets)
end

-- The reminder: once per login, when the last full scan is old or missing.
-- Not while TSM or Auctionator is loaded: they bring their own prices.
local function scanReminder()
  if scan.reminded or not Core.scanAvailable(_G) or ns.Sources.anyPresent(_G) then return end
  if not ns.db or ns.Options.get(ns.db, "scanReminder") == false then return end
  local bucket = scanBucket(false)
  local last = bucket and bucket.lastFull
  if num(last) and time() - last <= SCAN_REMIND_AFTER then return end
  scan.reminded = true
  say(L_SCAN_REMIND)
end

-- Old scan prices only grow the saved file (login).
function Core.pruneScan(db, now)
  if type(db) ~= "table" or type(db.scan) ~= "table" then return end
  for key, bucket in pairs(db.scan) do
    if type(bucket) ~= "table" or type(bucket.items) ~= "table" then
      db.scan[key] = nil
    else
      ns.Scan.prune(bucket.items, now)
      if next(bucket.items) == nil then db.scan[key] = nil end
    end
  end
end

events.AUCTION_HOUSE_SHOW = function()
  tradeWindows.AUCTION_HOUSE = true
  scanReminder()
  if ns.UI and ns.UI.ScanButton then ns.UI.ScanButton.show() end
end

events.AUCTION_HOUSE_CLOSED = function()
  tradeWindows.AUCTION_HOUSE = nil
  scan.pending = false
  if scan.reader then scan.reader:stop() end
  if ns.UI and ns.UI.ScanButton then ns.UI.ScanButton.hide() end
end
