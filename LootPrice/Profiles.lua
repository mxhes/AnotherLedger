local ADDON, ns = ...

local L = ns.L
local L_NO_NAME = L["Enter a name."]
local L_TOO_LONG = L["The name is too long."]
local L_EXISTS = L["A profile with this name exists."]
local L_KEEP_DEFAULT = L["The Default profile can't be renamed or deleted."]
local L_UNKNOWN = L["There is no profile with this name."]

-- Settings profiles. Every option (Options.lua) except the account-wide ones
-- lives in a profile: LootPriceDB.profiles = { [name] = settings }. Each
-- character picks one (LootPriceCharDB.profile, "Default" when missing). While
-- logged in, LootPriceDB.settings is the active profile's table, so every
-- Options.get(ns.db, key) reads it; Profiles.beforeLogout clears that alias so
-- the profile is saved once. Pure: no WoW globals.
local Profiles = {}

Profiles.DEFAULT = "Default"
Profiles.MAX_NAME = 32

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

-- The defaults a profile is filled with (for the few direct db.settings
-- reads). Not the single colors: their default is the profile's preset
-- (Options.defaultFor), so a missing color must stay missing.
local function defaults()
  local all = ns.DB and ns.DB.defaults and ns.DB.defaults.settings or {}
  local targets = ns.Options and ns.Options.colorTargets or {}
  local out = {}
  for k, v in pairs(all) do
    if not targets[k] then out[k] = v end
  end
  return out
end

-- The name `name` is stored under (case-insensitive match), or nil.
local function find(db, name)
  if type(db.profiles) ~= "table" or type(name) ~= "string" then return nil end
  if db.profiles[name] then return name end
  local lower = name:lower()
  for key in pairs(db.profiles) do
    if key:lower() == lower then return key end
  end
  return nil
end

local function point(db, name)
  db.settings = ns.DB.applyDefaults(db.profiles[name], defaults())
  db.profiles[name] = db.settings
end

-- Login: the first time, a fresh "Default" (the old settings are not carried
-- over); then the character's profile becomes db.settings.
function Profiles.init(db, chardb)
  if db.profilesMigrated ~= true then
    db.profiles = { [Profiles.DEFAULT] = {} }
    db.profilesMigrated = true
  end
  if type(db.profiles) ~= "table" then db.profiles = {} end
  if type(db.profiles[Profiles.DEFAULT]) ~= "table" then db.profiles[Profiles.DEFAULT] = {} end
  local name = type(chardb) == "table" and find(db, chardb.profile) or nil
  if not name or type(db.profiles[name]) ~= "table" then name = Profiles.DEFAULT end
  if type(chardb) == "table" then chardb.profile = name end
  point(db, name)
end

-- Logout: the profile is saved under db.profiles only.
function Profiles.beforeLogout(db)
  if type(db) == "table" then db.settings = nil end
end

function Profiles.active(chardb)
  local name = type(chardb) == "table" and chardb.profile or nil
  if type(name) ~= "string" or name == "" then return Profiles.DEFAULT end
  return name
end

-- Every profile name: Default first, the rest sorted (case-insensitive).
function Profiles.names(db)
  local out = {}
  for name in pairs(type(db.profiles) == "table" and db.profiles or {}) do
    if name ~= Profiles.DEFAULT then out[#out + 1] = name end
  end
  table.sort(out, function(a, b) return a:lower() < b:lower() end)
  table.insert(out, 1, Profiles.DEFAULT)
  return out
end

-- A usable new name: trimmed, 1..MAX_NAME characters, not taken (another
-- profile than `except`). Returns the name, or nil and the reason.
function Profiles.validName(db, name, except)
  if type(name) ~= "string" then return nil, L_NO_NAME end
  local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "")
  if trimmed == "" then return nil, L_NO_NAME end
  if #trimmed > Profiles.MAX_NAME then return nil, L_TOO_LONG end
  local taken = find(db, trimmed)
  if taken and taken ~= except then return nil, L_EXISTS end
  return trimmed
end

-- A new profile `name` from a copy of `from` (a settings table), else empty
-- (the defaults). `replace`: an existing profile of that name is overwritten
-- in place. Returns true, or false and the reason.
function Profiles.create(db, name, from, replace)
  local existing = find(db, type(name) == "string" and (name:gsub("^%s+", ""):gsub("%s+$", "")) or nil)
  if replace and existing then
    local t = db.profiles[existing]
    for k in pairs(t) do t[k] = nil end
    for k, v in pairs(copy(from or {})) do t[k] = v end
    return true
  end
  local valid, err = Profiles.validName(db, name)
  if not valid then return false, err end
  db.profiles[valid] = copy(from or {})
  return true
end

function Profiles.rename(db, chardb, old, new)
  local key = find(db, old)
  if not key then return false, L_UNKNOWN end
  if key == Profiles.DEFAULT then return false, L_KEEP_DEFAULT end
  local valid, err = Profiles.validName(db, new, key)
  if not valid then return false, err end
  if valid == Profiles.DEFAULT then return false, L_EXISTS end
  local t = db.profiles[key]
  db.profiles[key] = nil
  db.profiles[valid] = t
  if type(chardb) == "table" and chardb.profile == key then chardb.profile = valid end
  return true
end

function Profiles.delete(db, chardb, name)
  local key = find(db, name)
  if not key then return false, L_UNKNOWN end
  if key == Profiles.DEFAULT then return false, L_KEEP_DEFAULT end
  local wasActive = db.settings == db.profiles[key]
  db.profiles[key] = nil
  if type(chardb) == "table" and chardb.profile == key then chardb.profile = Profiles.DEFAULT end
  if wasActive then Profiles.activate(db, chardb, Profiles.DEFAULT) end
  return true
end

-- Switches this character to `name` (unknown: Default) and applies every option.
function Profiles.activate(db, chardb, name)
  local key = find(db, name)
  if not key or type(db.profiles[key]) ~= "table" then key = Profiles.DEFAULT end
  if type(db.profiles[key]) ~= "table" then db.profiles[key] = {} end
  if type(chardb) == "table" then chardb.profile = key end
  point(db, key)
  if ns.Options and ns.Options.applyAll then ns.Options.applyAll(db) end
end

ns.Profiles = Profiles
