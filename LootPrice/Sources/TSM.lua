local ADDON, ns = ...

ns.Sources = ns.Sources or {}

local TSM = {}

-- TSM's item string for a link (bonus IDs included), else "i:<itemID>".
-- UNVERIFIED (check in client): TSM_API.ToItemString(link) exists and returns
-- the variant's item string.
function TSM.itemString(api, itemID, link)
  if type(link) == "string" and type(api.ToItemString) == "function" then
    local ok, s = pcall(api.ToItemString, link)
    if ok and type(s) == "string" and s ~= "" then return s end
  end
  return "i:" .. tostring(itemID)
end

-- env is the global environment (_G in the client); getSource returns the TSM
-- price source string (e.g. "DBMarket").
function TSM.new(env, getSource)
  local function get(itemID, link)
    if type(env) ~= "table" then return nil end
    local api = env.TSM_API
    if type(api) ~= "table" or type(api.GetCustomPriceValue) ~= "function" then return nil end
    local okS, source = pcall(getSource)
    if not okS or source == nil then return nil end
    -- UNVERIFIED (check in client): GetCustomPriceValue(source, "i:<itemID>") signature.
    local ok, value = pcall(api.GetCustomPriceValue, source, TSM.itemString(api, itemID, link))
    if ok and type(value) == "number" then return value end
    return nil
  end
  return { name = "TSM", get = get }
end

-- Region market data of an item: { saleRate = 0..1, soldPerDay = n }, either
-- field may be missing; nil without TSM or without any data. TSM rounds custom
-- price values to whole numbers (copper), so the value is asked scaled up and
-- divided again.
-- UNVERIFIED (check in client): GetCustomPriceValue accepts "DBRegionSaleRate * 1000"
-- and "DBRegionSoldPerDay * 100", and DBRegionSaleRate is a plain 0..1 rate.
TSM.RATE_SCALE, TSM.SOLD_SCALE = 1000, 100

function TSM.market(env, itemID, link)
  if type(env) ~= "table" then return nil end
  local api = env.TSM_API
  if type(api) ~= "table" or type(api.GetCustomPriceValue) ~= "function" then return nil end
  local item = TSM.itemString(api, itemID, link)
  local function value(expr, scale)
    local ok, v = pcall(api.GetCustomPriceValue, expr .. " * " .. scale, item)
    if ok and ns.Util.isNumber(v) and v >= 0 then return v / scale end
    return nil
  end
  local rate = value("DBRegionSaleRate", TSM.RATE_SCALE)
  -- A rate can never be above 1: TSM had it scaled by 1000 already.
  if rate and rate > 1 then rate = rate / 1000 end
  local sold = value("DBRegionSoldPerDay", TSM.SOLD_SCALE)
  if rate == nil and sold == nil then return nil end
  return { saleRate = rate, soldPerDay = sold }
end

ns.Sources.TSM = TSM

ns.Sources.register({
  key = "tsm",
  label = "TSM",
  -- The TSM price string (e.g. "DBMarket") is the tsmSource setting, read live.
  create = function(env, setting)
    return TSM.new(env, function() return setting("tsmSource") end)
  end,
  -- Disenchant value: TSM's "Destroy" price (nil for items that cannot be
  -- disenchanted).
  createDisenchant = function(env)
    return TSM.new(env, function() return "Destroy" end)
  end,
  -- Region sale rate and sold per day (shown under the item name).
  createMarket = function(env)
    return function(itemID, link) return TSM.market(env, itemID, link) end
  end,
})
