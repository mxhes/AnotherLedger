local ADDON, ns = ...

ns.Sources = ns.Sources or {}

-- Vendor sell price: always available, not an auction house source (so it is
-- not registered with Sources.register).
local Vendor = {}

-- env is the global environment (_G in the client). Returns the vendor sell
-- price in copper (11th GetItemInfo return) or nil. With a link, the price of
-- that variant (the sell price grows with the item level).
function Vendor.get(env, itemID, link)
  if type(env) ~= "table" then return nil end
  local C_Item = env.C_Item
  if type(C_Item) ~= "table" or type(C_Item.GetItemInfo) ~= "function" then return nil end
  -- sellPrice is GetItemInfo's 11th return.
  local ok, price = pcall(function() return select(11, C_Item.GetItemInfo(type(link) == "string" and link or itemID)) end)
  if ok and type(price) == "number" then return price end
  return nil
end

ns.Sources.Vendor = Vendor
