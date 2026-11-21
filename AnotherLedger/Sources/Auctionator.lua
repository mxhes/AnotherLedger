local ADDON, ns = ...

ns.Sources = ns.Sources or {}

local Auctionator = {}

local CALLER = "AnotherLedger"
local DAY = 86400

local function api(env)
  if type(env) ~= "table" then return nil end
  local a = env.Auctionator
  local a_api = type(a) == "table" and a.API or nil
  local v1 = type(a_api) == "table" and a_api.v1 or nil
  return type(v1) == "table" and v1 or nil
end

-- Calls v1[name](CALLER, arg); the number it returns, else nil.
local function ask(v1, name, arg)
  if type(v1[name]) ~= "function" then return nil end
  local ok, value = pcall(v1[name], CALLER, arg)
  if ok and type(value) == "number" and value == value then return value end
  return nil
end

-- Age in seconds of Auctionator's price: GetAuctionAge* answer whole days
-- since that price was last scanned (0 = today, nil = unknown).
-- Client API: Auctionator.API.v1.GetAuctionAgeByItemLink /
-- GetAuctionAgeByItemID (callerID, link / itemID) -> days or nil.
local function ageOf(v1, name, arg)
  local days = ask(v1, name, arg)
  if days and days > 0 then return days * DAY end
  return 0
end

-- env is the global environment (_G in the client). get returns the price and
-- its age in seconds (Prices tags an aged price like a scan price).
function Auctionator.new(env)
  local function get(itemID, link)
    local v1 = api(env)
    if not v1 then return nil end
    -- The exact variant (bonus IDs) when a link is known.
    if type(link) == "string" then
      local byLink = ask(v1, "GetAuctionPriceByItemLink", link)
      if byLink then return byLink, ageOf(v1, "GetAuctionAgeByItemLink", link) end
    end
    local value = ask(v1, "GetAuctionPriceByItemID", itemID)
    if value then return value, ageOf(v1, "GetAuctionAgeByItemID", itemID) end
    return nil
  end
  return { name = "Auctionator", get = get }
end

-- Disenchant value of an item from Auctionator (nil when it cannot be
-- disenchanted or nothing is known). It needs a link: without one, the item's
-- own link from C_Item.GetItemInfo.
-- Client API: Auctionator.API.v1.GetDisenchantPriceByItemLink
-- (callerID, link) -> copper or nil.
function Auctionator.disenchant(env)
  local function get(itemID, link)
    local v1 = api(env)
    if not v1 then return nil end
    if type(link) ~= "string" then
      local C_Item = env.C_Item
      if type(C_Item) ~= "table" or type(C_Item.GetItemInfo) ~= "function" then return nil end
      local ok, _, itemLink = pcall(C_Item.GetItemInfo, itemID)
      if not (ok and type(itemLink) == "string") then return nil end
      link = itemLink
    end
    local value = ask(v1, "GetDisenchantPriceByItemLink", link)
    if value and value > 0 then return value end
    return nil
  end
  return { name = "Auctionator", get = get }
end

ns.Sources.Auctionator = Auctionator

ns.Sources.register({
  key = "auctionator",
  label = "Auctionator",
  create = function(env) return Auctionator.new(env) end,
  -- Asked after TSM's "Destroy" price (Core.buildPrices).
  createDisenchant = function(env) return Auctionator.disenchant(env) end,
  present = function(env)
    local a = type(env) == "table" and env.Auctionator
    return type(a) == "table" and type(a.API) == "table"
  end,
})
