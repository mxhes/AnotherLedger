local ADDON, ns = ...

ns.Sources = ns.Sources or {}

local Auctionator = {}

-- env is the global environment (_G in the client).
function Auctionator.new(env)
  local function get(itemID, link)
    if type(env) ~= "table" then return nil end
    local a = env.Auctionator
    local api = type(a) == "table" and a.API or nil
    local v1 = type(api) == "table" and api.v1 or nil
    if type(v1) ~= "table" then return nil end
    -- The exact variant (bonus IDs) when a link is known.
    -- UNVERIFIED (check in client): Auctionator.API.v1.GetAuctionPriceByItemLink(callerID, link).
    if type(link) == "string" and type(v1.GetAuctionPriceByItemLink) == "function" then
      local okLink, byLink = pcall(v1.GetAuctionPriceByItemLink, "LootPrice", link)
      if okLink and type(byLink) == "number" then return byLink end
    end
    if type(v1.GetAuctionPriceByItemID) ~= "function" then return nil end
    -- UNVERIFIED (check in client): Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID).
    local ok, value = pcall(v1.GetAuctionPriceByItemID, "LootPrice", itemID)
    if ok and type(value) == "number" then return value end
    return nil
  end
  return { name = "Auctionator", get = get }
end

ns.Sources.Auctionator = Auctionator

ns.Sources.register({
  key = "auctionator",
  label = "Auctionator",
  create = function(env) return Auctionator.new(env) end,
})
