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
--     present = function(env) -> bool, -- optional: the addon is loaded
--   })
--
-- `env` is the global environment (_G in the client) and `setting(key)` reads
-- db.settings[key] live. Sources are asked in registration (.toc) order; the
-- options dropdown and the price lookup are built from this list, so a new
-- source touches no other file.
ns.Sources = ns.Sources or {}
local Sources = ns.Sources
local L = ns.L

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

-- Whether any source with a `present` check finds its addon loaded (no AH
-- prices at all otherwise: Core.priceAddonHint).
function Sources.anyPresent(env)
  for _, spec in ipairs(specs) do
    if type(spec.present) == "function" and spec.present(env) then return true end
  end
  return false
end

-- Whether the addon of a source is loaded: its `present` check, or true for
-- a source without one (AnotherLedger scan, own sales).
function Sources.isPresent(spec, env)
  if type(spec) ~= "table" then return false end
  if type(spec.present) ~= "function" then return true end
  local ok, present = pcall(spec.present, env)
  return ok and present and true or false
end

-- Whether a loaded source offers `field` ("createDisenchant", "createMarket"):
-- destroy values or sale info exist at all (options shown dimmed otherwise).
function Sources.offers(field, env)
  for _, spec in ipairs(specs) do
    if type(spec[field]) == "function" and type(spec.present) == "function" and Sources.isPresent(spec, env) then
      return true
    end
  end
  return false
end

-- The option value that counts: a selected source whose addon is not loaded
-- acts as "auto" (the choice is kept for when the addon is back).
function Sources.effective(selected, env)
  local spec = byKey[selected]
  if spec and not Sources.isPresent(spec, env) then return Sources.AUTO end
  return selected
end

-- Whether the source `key` may answer under the selected option value. Only a
-- registered key narrows the choice; "auto" and unknown values ask everyone.
-- With `env`, a selected source that is not loaded counts as "auto".
function Sources.allowed(selected, key, env)
  if env ~= nil then selected = Sources.effective(selected, env) end
  return selected == key or byKey[selected] == nil
end

-- Wraps a source so it only answers while the option allows it. The selection
-- is read live, so changing the option needs no rebuild.
function Sources.gate(source, key, getSelected, env)
  return {
    name = source.name,
    get = function(itemID, link)
      local ok, selected = pcall(getSelected)
      if not ok or not Sources.allowed(selected, key, env) then return nil end
      return source.get(itemID, link)
    end,
  }
end

-- Dropdown choices: "Auto (A, then B)" followed by one entry per source. The
-- Auto entry's `short` text ("Auto") is what the closed dropdown button shows.
-- With `env`, a source whose addon is not loaded says so (it acts as Auto).
local L_NOT_LOADED = L["%s (not loaded)"]
function Sources.choices(env)
  local labels = {}
  for i, spec in ipairs(specs) do labels[i] = spec.label or spec.key end
  local auto = L["Auto"]
  if #labels > 0 then auto = auto .. " (" .. table.concat(labels, L[", then "]) .. ")" end
  local choices = { { value = Sources.AUTO, label = auto, short = L["Auto"] } }
  for i, spec in ipairs(specs) do
    local label = labels[i]
    if env ~= nil and not Sources.isPresent(spec, env) then label = L_NOT_LOADED:format(label) end
    choices[#choices + 1] = { value = spec.key, label = label }
  end
  return choices
end
