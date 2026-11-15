local ADDON, ns = ...

-- Registry of auction house price sources. A source is one file that ends with
--
--   ns.Sources.register({
--     key    = "tsm",                -- value of the "AH price source" option
--     label  = "TSM",                -- shown in the options dropdown
--     create = function(env, setting) return { name = "TSM", get = function(itemID, link) ... end } end,
--     createDisenchant = function(env, setting) ... end, -- optional, same shape
--     createMarket = function(env, setting) -- optional: returns
--       function(itemID, link) -> { saleRate, soldPerDay } or nil (region data)
--   })
--
-- `env` is the global environment (_G in the client) and `setting(key)` reads
-- db.settings[key] live. Sources are asked in registration (.toc) order; the
-- options dropdown and the price lookup are built from this list, so a new
-- source touches no other file.
ns.Sources = ns.Sources or {}
local Sources = ns.Sources

Sources.AUTO = "auto" -- option value: ask every source, in order

local specs, byKey = {}, {}

function Sources.register(spec)
  assert(type(spec) == "table" and type(spec.key) == "string", "source needs a key")
  assert(type(spec.create) == "function", "source needs a create function")
  if not byKey[spec.key] then specs[#specs + 1] = spec end
  byKey[spec.key] = spec
  return spec
end

function Sources.list()
  return specs
end

-- Whether the source `key` may answer under the selected option value. Only a
-- registered key narrows the choice; "auto" and unknown values ask everyone.
function Sources.allowed(selected, key)
  return selected == key or byKey[selected] == nil
end

-- Wraps a source so it only answers while the option allows it. The selection
-- is read live, so changing the option needs no rebuild.
function Sources.gate(source, key, getSelected)
  return {
    name = source.name,
    get = function(itemID, link)
      local ok, selected = pcall(getSelected)
      if not ok or not Sources.allowed(selected, key) then return nil end
      return source.get(itemID, link)
    end,
  }
end

-- Dropdown choices: "Auto (A, then B)" followed by one entry per source.
function Sources.choices()
  local labels = {}
  for i, spec in ipairs(specs) do labels[i] = spec.label or spec.key end
  local auto = "Auto"
  if #labels > 0 then auto = auto .. " (" .. table.concat(labels, ", then ") .. ")" end
  local choices = { { value = Sources.AUTO, label = auto } }
  for i, spec in ipairs(specs) do
    choices[#choices + 1] = { value = spec.key, label = labels[i] }
  end
  return choices
end
