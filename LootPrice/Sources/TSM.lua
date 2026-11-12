local ADDON, ns = ...

ns.Sources = ns.Sources or {}

local TSM = {}

-- env is the global environment (_G in the client); getSource returns the TSM
-- price source string (e.g. "DBMarket").
function TSM.new(env, getSource)
  local function get(itemID)
    if type(env) ~= "table" then return nil end
    local api = env.TSM_API
    if type(api) ~= "table" or type(api.GetCustomPriceValue) ~= "function" then return nil end
    local okS, source = pcall(getSource)
    if not okS or source == nil then return nil end
    local ok, value = pcall(api.GetCustomPriceValue, source, "i:" .. tostring(itemID))
    if ok and type(value) == "number" then return value end
    return nil
  end
  return { name = "TSM", get = get }
end

ns.Sources.TSM = TSM
