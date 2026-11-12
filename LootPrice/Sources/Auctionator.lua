local ADDON, ns = ...

ns.Sources = ns.Sources or {}

local Auctionator = {}

-- env is the global environment (_G in the client).
function Auctionator.new(env)
  local function get(itemID)
    if type(env) ~= "table" then return nil end
    local a = env.Auctionator
    local api = type(a) == "table" and a.API or nil
    local v1 = type(api) == "table" and api.v1 or nil
    if type(v1) ~= "table" or type(v1.GetAuctionPriceByItemID) ~= "function" then return nil end
    local ok, value = pcall(v1.GetAuctionPriceByItemID, "LootPrice", itemID)
    if ok and type(value) == "number" then return value end
    return nil
  end
  return { name = "Auctionator", get = get }
end

ns.Sources.Auctionator = Auctionator
