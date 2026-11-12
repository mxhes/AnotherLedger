local ADDON, ns = ...

ns.Sources = ns.Sources or {}

local Vendor = {}

-- env is the global environment (_G in the client). Returns the vendor sell
-- price in copper (11th GetItemInfo return) or nil.
function Vendor.get(env, itemID)
  if type(env) ~= "table" then return nil end
  local C_Item = env.C_Item
  if type(C_Item) ~= "table" or type(C_Item.GetItemInfo) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g, i, j, k, price = pcall(C_Item.GetItemInfo, itemID)
  if ok and type(price) == "number" then return price end
  return nil
end

ns.Sources.Vendor = Vendor
