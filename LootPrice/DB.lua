local ADDON, ns = ...

local DB = {}

DB.defaults = {
  version = 1,
  cache = {},
  settings = { keepSession = false, tsmSource = "DBMarket" },
  window = { point = "CENTER", x = 0, y = 0, width = 420, height = 440, hidden = false },
  filter = {
    qualities = { [0] = true, true, true, true, true, true, true, true },
    minValue = 0,
    search = "",
  },
  sort = "ah",
}

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

-- Fills missing keys of `saved` from `defaults` (recursively), replaces values
-- whose type differs from the default's, keeps unknown keys. Returns the table
-- to use; never mutates `defaults` and shares no tables with it.
function DB.applyDefaults(saved, defaults)
  if type(saved) ~= "table" then return copy(defaults) end
  for k, d in pairs(defaults) do
    local v = saved[k]
    if type(d) == "table" then
      if type(v) ~= "table" then
        saved[k] = copy(d)
      else
        DB.applyDefaults(v, d)
      end
    elseif type(v) ~= type(d) then
      saved[k] = d
    end
  end
  return saved
end

ns.DB = DB
