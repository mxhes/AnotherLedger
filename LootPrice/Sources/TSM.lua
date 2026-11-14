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
})
