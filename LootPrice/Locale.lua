local ADDON, ns = ...

-- Translations. The English text is the key: L["Vendor: "] gives the text of
-- the client language when a locale file (Locales/*.lua) has it, else the
-- English text itself. Locale files load right after this one, so every file
-- after them can translate its texts at load time.
--
-- A locale file is one call:
--   ns.Locale.register("deDE", { ["Vendor: "] = "Händler: ", ... })
local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

local Locale = {}
ns.Locale = Locale

-- The client language ("enUS", "deDE", ...); "enUS" outside the client.
function Locale.current()
  local get = _G.GetLocale
  if type(get) == "function" then
    local ok, v = pcall(get)
    if ok and type(v) == "string" then return v end
  end
  return "enUS"
end

-- Adds the strings of `locale` when it is the client language. `forLocale`
-- (optional, tests) replaces the client language. Returns whether they were used.
function Locale.register(locale, strings, forLocale)
  if locale ~= (forLocale or Locale.current()) or type(strings) ~= "table" then return false end
  for key, text in pairs(strings) do
    if type(key) == "string" and type(text) == "string" and text ~= "" then rawset(L, key, text) end
  end
  return true
end
