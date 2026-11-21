local ADDON, ns = ...

-- Core's Trade section (loads after Core.lua, before Boot.lua): auction
-- posts and cancels, the sold chat line, auction mails and player trades.

local L = ns.L
local Core = ns.Core
local events = Core.events
local function dataChanged(what) Core.dataChanged(what) end

-- Trade section: auction posts and cancels (hooked calls), the "buyer found"
-- chat line, auction mails and finished player trades, recorded per realm
-- in Trade.lua. Nothing is recorded while the realm key is unknown.

local trade = { hooked = false, snap = false }

-- The Trade bucket of the current realm (made when `create`), or nil.
function Core.tradeBucket(create)
  if not (ns.Trade and ns.Scan) then return nil end
  return ns.Trade.bucket(ns.db, ns.Scan.currentRealmKey(), create)
end

-- The market per unit of an item now, without the player's own sales.
function Core.marketAt(itemID, link)
  if not (ns.prices and ns.prices.marketPrice) or itemID == nil then return nil end
  return ns.prices:marketPrice(itemID, link, L["Own sales"])
end

local function marketOf(key, id) return Core.marketAt(id) end

-- A client format string ("... of %s.") as a pattern capturing the %s part.
function Core.formatPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local escaped = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  return "^" .. escaped:gsub("%%%%s", "(.+)") .. "$"
end

local function playerName()
  if type(UnitName) ~= "function" then return nil end
  local ok, name = pcall(UnitName, "player")
  return ok and name or nil
end

-- { key, id, name } of an item link.
local function itemOfLink(link)
  if type(link) ~= "string" then return nil end
  local id = ns.LootParse.itemID(link)
  if not id then return nil end
  -- A crafting reagent's name carries its quality icon (|A...|a) in the
  -- link; mails name the item without it.
  local name = link:match("%[(.-)%]")
  if name then name = name:gsub("|A.-|a", ""):gsub("^%s+", ""):gsub("%s+$", "") end
  return { key = ns.LootParse.itemKey(link) or id, id = id, name = name }
end

-- The item ID the client knows for an item name (cached items only).
local function idOfName(name)
  local api = C_Item
  if type(name) ~= "string" or type(api) ~= "table" or type(api.GetItemInfoInstant) ~= "function" then return nil end
  local ok, id = pcall(api.GetItemInfoInstant, name)
  return ok and type(id) == "number" and id or nil
end

local function recorded()
  dataChanged("trade")
end

local function addPost(link, quantity, unit)
  local bucket, item = Core.tradeBucket(true), itemOfLink(link)
  if not (bucket and item) or type(quantity) ~= "number" or quantity <= 0 then return end
  ns.Trade.addPost(bucket, { t = time(), key = item.key, id = item.id, name = item.name, n = quantity,
    unit = type(unit) == "number" and unit or 0, char = playerName() })
  recorded()
end

-- Client API: C_AuctionHouse.PostItem(itemLocation,
-- duration, quantity, bid, buyout), PostCommodity(itemLocation, duration,
-- quantity, unitPrice) and CancelAuction(auctionID) are what the auction
-- house UI calls; C_Item.GetItemLink(itemLocation) gives the link; the owned
-- auction of an ID (GetNumOwnedAuctions / GetOwnedAuctionInfo) still exists
-- when CancelAuction is called.
local function linkOfLocation(loc)
  local api = C_Item
  if type(api) ~= "table" or type(api.GetItemLink) ~= "function" then return nil end
  local ok, link = pcall(api.GetItemLink, loc)
  return ok and link or nil
end

local function ownedAuction(auctionID)
  local api = C_AuctionHouse
  if type(api.GetNumOwnedAuctions) ~= "function" or type(api.GetOwnedAuctionInfo) ~= "function" then return nil end
  for i = 1, api.GetNumOwnedAuctions() or 0 do
    local info = api.GetOwnedAuctionInfo(i)
    if type(info) == "table" and info.auctionID == auctionID then return info end
  end
  return nil
end

function Core.hookAuctionCalls()
  if trade.hooked then return end
  local api = C_AuctionHouse
  if type(hooksecurefunc) ~= "function" or type(api) ~= "table" then return end
  trade.hooked = true
  if type(api.PostItem) == "function" then
    hooksecurefunc(api, "PostItem", function(loc, duration, quantity, bid, buyout)
      local total = (type(buyout) == "number" and buyout > 0) and buyout or bid
      if type(quantity) == "number" and quantity > 0 and type(total) == "number" then
        addPost(linkOfLocation(loc), quantity, math.floor(total / quantity))
      end
    end)
  end
  if type(api.PostCommodity) == "function" then
    hooksecurefunc(api, "PostCommodity", function(loc, duration, quantity, unitPrice)
      addPost(linkOfLocation(loc), quantity, unitPrice)
    end)
  end
  if type(api.CancelAuction) == "function" then
    hooksecurefunc(api, "CancelAuction", function(auctionID)
      local ok, info = pcall(ownedAuction, auctionID)
      local item = ok and info and itemOfLink(info.itemLink)
      local bucket = item and Core.tradeBucket(true)
      if not bucket then return end
      ns.Trade.cancel(bucket, { t = time(), key = item.key, id = item.id, name = item.name,
        n = info.quantity or 1, char = playerName() })
      recorded()
    end)
  end
end

-- Client API: CHAT_MSG_SYSTEM carries ERR_AUCTION_SOLD_S
-- ("A buyer has been found for your auction of %s.") with the item name.
events.CHAT_MSG_SYSTEM = function(text)
  local pattern = Core.formatPattern(ERR_AUCTION_SOLD_S)
  local name = pattern and type(text) == "string" and text:match(pattern)
  if not name then return end
  local bucket = Core.tradeBucket(true)
  if not bucket then return end
  ns.Trade.markSold(bucket, name, time(), Core.marketAt(idOfName(name)))
end

-- Client API: GetInboxHeaderInfo(i) gives sender 3rd,
-- subject 4th, money 5th, daysLeft 7th; GetInboxInvoiceInfo(i) gives
-- invoiceType ("seller" / "seller_temp_invoice" / "buyer"), itemName, playerName, bid,
-- buyout, deposit, consignment, ..., count 11th; expired and cancelled mails
-- have the subjects AUCTION_EXPIRED_MAIL_SUBJECT / AUCTION_REMOVED_MAIL_SUBJECT
-- and the item as attachment 1 (GetInboxItemLink, count 4th of GetInboxItem).
local function readMail(i, now)
  local _, _, sender, subject, money, _, daysLeft = GetInboxHeaderInfo(i)
  if type(daysLeft) ~= "number" then return nil end
  local m = { sender = sender, subject = subject, money = money, expires = now + daysLeft * ns.Trade.DAY,
    char = playerName() }
  if type(GetInboxInvoiceInfo) == "function" then
    local kind, name, who, bid, _, _, cut, _, _, _, count = GetInboxInvoiceInfo(i)
    if kind == "seller" or kind == "seller_temp_invoice" then
      m.kind, m.name, m.who, m.gold, m.cut, m.n = "sale", name, who, bid or 0, cut or 0, count or 1
      m.temp = kind == "seller_temp_invoice" or nil
      m.id = idOfName(name) -- the post of that name gives the key (Trade.recordMail)
      return m
    end
    -- UNVERIFIED (check in client): an auction won (also a commodity
    -- purchase) has invoiceType "buyer", the seller as playerName and the
    -- price paid as bid; the item is attachment 1.
    if kind == "buyer" then
      local item = itemOfLink(type(GetInboxItemLink) == "function" and GetInboxItemLink(i, 1) or nil)
      m.kind, m.name, m.who, m.gold, m.n = "buy", name or (item and item.name), who, bid or 0, count or 1
      if item then m.key, m.id = item.key, item.id else m.id = idOfName(name) end
      return m
    end
  end
  for kind, fmt in pairs({ expire = AUCTION_EXPIRED_MAIL_SUBJECT, cancel = AUCTION_REMOVED_MAIL_SUBJECT }) do
    local pattern = Core.formatPattern(fmt)
    if pattern and type(subject) == "string" and subject:match(pattern) then
      local item = itemOfLink(type(GetInboxItemLink) == "function" and GetInboxItemLink(i, 1) or nil)
      if not item then return nil end
      local count = type(GetInboxItem) == "function" and select(4, GetInboxItem(i, 1)) or 1
      m.kind, m.key, m.id, m.name, m.n = kind, item.key, item.id, item.name, count or 1
      return m
    end
  end
  return nil
end

events.MAIL_INBOX_UPDATE = function()
  if type(GetInboxNumItems) ~= "function" or type(GetInboxHeaderInfo) ~= "function" then return end
  local bucket = Core.tradeBucket(true)
  if not bucket then return end
  local now, mails = time(), {}
  for i = 1, GetInboxNumItems() or 0 do
    local ok, m = pcall(readMail, i, now)
    if ok and m then mails[#mails + 1] = m end
  end
  if #ns.Trade.recordInbox(bucket, mails, now, marketOf) > 0 then recorded() end
end

-- Client API: TRADE_ACCEPT_UPDATE fires when either side
-- accepts; slots 1-6 are traded (GetTradePlayerItemLink / Info, count 3rd,
-- and the Target versions); GetPlayerTradeMoney / GetTargetTradeMoney;
-- UnitName("NPC") is the partner; UI_INFO_MESSAGE(type, ERR_TRADE_COMPLETE)
-- comes once the trade went through.
local function tradeSide(linkFn, infoFn)
  local items = {}
  if type(linkFn) ~= "function" or type(infoFn) ~= "function" then return items end
  for i = 1, 6 do
    local item = itemOfLink(linkFn(i))
    if item then
      item.n = select(3, infoFn(i)) or 1
      items[#items + 1] = item
    end
  end
  return items
end

events.TRADE_ACCEPT_UPDATE = function()
  local ok, snap = pcall(function()
    local partner = type(UnitName) == "function" and UnitName("NPC") or nil
    return {
      out = tradeSide(GetTradePlayerItemLink, GetTradePlayerItemInfo),
      ["in"] = tradeSide(GetTradeTargetItemLink, GetTradeTargetItemInfo),
      goldOut = type(GetPlayerTradeMoney) == "function" and GetPlayerTradeMoney() or 0,
      goldIn = type(GetTargetTradeMoney) == "function" and GetTargetTradeMoney() or 0,
      who = partner, char = playerName(),
    }
  end)
  trade.snap = ok and snap or false
end

events.UI_INFO_MESSAGE = function(_, message)
  if not trade.snap or message ~= ERR_TRADE_COMPLETE then return end
  local snap = trade.snap
  trade.snap = false
  local bucket = Core.tradeBucket(true)
  if not bucket then return end
  ns.Trade.addTrade(bucket, snap, time(), marketOf)
  recorded()
end

-- A trade that closes without the "complete" message saved nothing; the
-- message can come just after TRADE_CLOSED, so the snapshot is dropped at
-- the next TRADE_SHOW (and by a later unrelated message only if a trade
-- went through).
do
  local show, closed = events.TRADE_SHOW, events.TRADE_CLOSED
  events.TRADE_SHOW = function(...)
    trade.snap = false
    if show then return show(...) end
  end
  events.TRADE_CLOSED = function(...)
    if closed then closed(...) end
    if trade.snap and C_Timer and type(C_Timer.After) == "function" then
      local snap = trade.snap
      C_Timer.After(1, function() if trade.snap == snap then trade.snap = false end end)
    end
  end
end

-- Old Trade log entries go at login (option Trade log kept); totals stay.
function Core.pruneTrade(db, now)
  if type(db) ~= "table" or type(db.trade) ~= "table" or not ns.Trade then return end
  local days = ns.Options.get(db, "tradeLogDays")
  for key, bucket in pairs(db.trade) do
    if type(bucket) ~= "table" then
      db.trade[key] = nil
    else
      ns.Trade.prune(ns.Trade.bucket(db, key, true), now, days)
    end
  end
end
