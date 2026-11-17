local ADDON, ns = ...

local L = ns.L
local L_NO_NAME = L["Enter a name."]
local L_TOO_LONG = L["The name is too long."]
local L_EXISTS = L["A profile with this name exists."]
local L_KEEP_DEFAULT = L["The Default profile can't be renamed or deleted."]
local L_UNKNOWN = L["There is no profile with this name."]

-- Settings profiles. Every option (Options.lua) except the account-wide ones
-- lives in a profile: LootLedgerDB.profiles = { [name] = settings }. Each
-- character picks one (LootLedgerCharDB.profile, "Default" when missing). While
-- logged in, LootLedgerDB.settings is the active profile's table, so every
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
  local wanted = type(chardb) == "table" and chardb.profile or nil
  local name = find(db, wanted)
  -- A profile another character renamed: follow its new name.
  if not name and type(db.renamed) == "table" then name = find(db, db.renamed[wanted]) end
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
  -- Other characters still name the old one: LootLedgerDB.renamed = { [old] = new }.
  if type(db.renamed) ~= "table" then db.renamed = {} end
  for old, new in pairs(db.renamed) do
    if new == key then db.renamed[old] = valid end
  end
  db.renamed[key] = valid
  db.renamed[valid] = nil
  if type(chardb) == "table" and chardb.profile == key then chardb.profile = valid end
  for character, used in pairs(type(db.profileUsers) == "table" and db.profileUsers or {}) do
    if used == key then db.profileUsers[character] = valid end
  end
  return true
end

function Profiles.delete(db, chardb, name)
  local key = find(db, name)
  if not key then return false, L_UNKNOWN end
  if key == Profiles.DEFAULT then return false, L_KEEP_DEFAULT end
  local wasActive = db.settings == db.profiles[key]
  db.profiles[key] = nil
  if type(db.renamed) == "table" then
    for old, new in pairs(db.renamed) do
      if new == key then db.renamed[old] = nil end
    end
  end
  if type(chardb) == "table" and chardb.profile == key then chardb.profile = Profiles.DEFAULT end
  for character, used in pairs(type(db.profileUsers) == "table" and db.profileUsers or {}) do
    if used == key then db.profileUsers[character] = Profiles.DEFAULT end
  end
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

-- Which character uses which profile, for the panel ("Used by: ..."):
-- LootLedgerDB.profileUsers = { ["Name-Realm"] = profile name }. Each
-- character notes itself at login and when it switches; rename and delete
-- keep the map current.
function Profiles.noteUser(db, character, name)
  if type(db) ~= "table" or type(character) ~= "string" or type(name) ~= "string" then return end
  if type(db.profileUsers) ~= "table" then db.profileUsers = {} end
  db.profileUsers[character] = name
end

-- The characters that use profile `name`, sorted.
function Profiles.users(db, name)
  local out = {}
  for character, used in pairs(type(db) == "table" and type(db.profileUsers) == "table" and db.profileUsers or {}) do
    if used == name then out[#out + 1] = character end
  end
  table.sort(out)
  return out
end

-- ---------------------------------------------------------------------------
-- Export / import: one line "LP1:key=value;key=value", only the options that
-- differ from their default (colors: from the profile's own preset). Values:
-- booleans t / f, numbers in full, text with % ; = percent-encoded.

Profiles.PREFIX = "LP1:"
local L_NOT_PROFILE = L["This is not a LootLedger profile."]
local L_NOTHING = L["Nothing to import."]

-- The options a profile string carries: stored in the profile, not buttons.
local function portable(spec)
  return spec.type ~= "button" and not spec.account and not spec.get and not spec.store
end

local function escape(s)
  return (s:gsub("[%%;=]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function unescape(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function numberText(v)
  if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format("%d", v) end
  local short = string.format("%.15g", v)
  if tonumber(short) == v then return short end
  return string.format("%.17g", v)
end

local function valueText(v)
  if type(v) == "boolean" then return v and "t" or "f" end
  if type(v) == "number" then return numberText(v) end
  return escape(tostring(v))
end

function Profiles.encode(settings)
  local O = ns.Options
  settings = type(settings) == "table" and settings or {}
  local pairsOut = {}
  for _, spec in ipairs(O.list()) do
    if portable(spec) and settings[spec.key] ~= nil then -- missing = the default
      local v = O.normalize(spec, settings[spec.key])
      if v ~= O.defaultFor(spec.key, settings) then
        pairsOut[#pairsOut + 1] = spec.key .. "=" .. valueText(v)
      end
    end
  end
  table.sort(pairsOut)
  return Profiles.PREFIX .. table.concat(pairsOut, ";")
end

-- The value `raw` (unescaped text) stands for, by the option's type, or nil.
local function parse(spec, raw)
  if spec.type == "checkbox" then
    if raw == "t" then return true elseif raw == "f" then return false end
    return nil
  elseif spec.type == "slider" or spec.type == "number" then
    return tonumber(raw)
  elseif spec.type == "dropdown" then
    for _, c in ipairs(ns.Options.choices(spec)) do
      if tostring(c.value) == raw then return c.value end
    end
    return nil
  end
  return raw
end

-- Text -> settings, taken, skipped; or nil and the reason. A value is taken
-- only when the option knows it as it is (nothing clamped or replaced).
function Profiles.decode(text)
  if type(text) ~= "string" then return nil, L_NOT_PROFILE end
  local body = text:gsub("^%s+", ""):gsub("%s+$", "")
  if body:sub(1, #Profiles.PREFIX) ~= Profiles.PREFIX then return nil, L_NOT_PROFILE end
  body = body:sub(#Profiles.PREFIX + 1)
  local O = ns.Options
  local out, taken, skipped = {}, 0, 0
  for pair in body:gmatch("[^;]+") do
    local key, raw = pair:match("^([%w_]+)=(.*)$")
    local spec = key and O.spec(key)
    local value -- may be false
    if spec and portable(spec) then value = parse(spec, unescape(raw)) end
    if value ~= nil and O.normalize(spec, value) == value then
      out[key] = value
      taken = taken + 1
    else
      skipped = skipped + 1
    end
  end
  if taken == 0 then return nil, L_NOTHING end
  return out, taken, skipped
end

ns.Profiles = Profiles

-- ---------------------------------------------------------------------------
-- The Profiles section of the options. The actions look the UI up when they
-- run (Widgets popups, the Export window), so this file stays loadable in tests.

local L_NEW_NAME = L["Name of the new profile:"]
local L_RENAME_TO = L["New name of the profile:"]
local L_IMPORT_NAME = L["Name of the imported profile:"]
local L_CREATE = L["Create"]
local L_RENAME = L["Rename"]
local L_DELETE = L["Delete"]
local L_IMPORT = L["Import"]
local L_OVERWRITE = L["Overwrite"]
local L_DELETE_Q = L["Delete the profile %s?"]
local L_OVERWRITE_Q = L["Overwrite the profile %s?"]
local L_IMPORTED = L["Imported %d settings, skipped %d."]
local L_EXPORT_TITLE = L["Profile export"]
local L_IMPORT_TITLE = L["Profile import"]

local function say(msg)
  if ns.Util and ns.Util.say then ns.Util.say(msg) end
end

local function widgets() return ns.UI and ns.UI.Widgets end

local function refreshPanel()
  local panel = ns.UI and ns.UI.OptionsPanel
  if panel and panel.refreshAll then panel.refreshAll() end
end

local function current() return Profiles.active(ns.chardb) end

-- Asks for a name, then `fn(name)`; errors go to chat.
local function askName(question, accept, initial, fn)
  local W = widgets()
  if W and W.prompt then W.prompt(question, accept, initial or "", fn) end
end

local function done(ok, err)
  if not ok and err then say(err) end
  refreshPanel()
  return ok
end

local function define(spec)
  spec.category = "profiles"
  return ns.Options.define(spec)
end

define({
  key = "profile", type = "dropdown", label = L["Profile"],
  tooltip = L["The settings this character uses. Every character can use its own profile or share one."],
  choices = function()
    local out = {}
    for _, name in ipairs(ns.db and Profiles.names(ns.db) or { Profiles.DEFAULT }) do
      out[#out + 1] = { value = name, label = name }
    end
    return out
  end,
  get = current,
  store = function(v)
    if not ns.db then return end
    Profiles.activate(ns.db, ns.chardb, v)
    Profiles.noteUser(ns.db, ns.Core and ns.Core.character, current())
  end,
  -- The tooltip lists the characters that use the chosen profile.
  tooltipExtra = function()
    local users = ns.db and Profiles.users(ns.db, current()) or {}
    if #users == 0 then return nil end
    return L["Used by: "] .. table.concat(users, ", ")
  end,
  picked = refreshPanel,
})

define({
  key = "profileNew", type = "button", label = L["New profile"],
  tooltip = L["Creates a profile with the default settings and switches to it."],
  action = function()
    askName(L_NEW_NAME, L_CREATE, "", function(name)
      local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "")
      local ok, err = Profiles.create(ns.db, trimmed)
      if ok then Profiles.activate(ns.db, ns.chardb, trimmed) end
      done(ok, err)
    end)
  end,
})

define({
  key = "profileCopy", type = "button", label = L["Copy profile"],
  tooltip = L["Creates a profile with the settings of this one and switches to it."],
  action = function()
    askName(L_NEW_NAME, L_CREATE, "", function(name)
      local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "")
      local ok, err = Profiles.create(ns.db, trimmed, ns.db.settings)
      if ok then Profiles.activate(ns.db, ns.chardb, trimmed) end
      done(ok, err)
    end)
  end,
})

define({
  key = "profileRename", type = "button", label = L["Rename profile"],
  tooltip = L["Gives this profile a new name. Default can't be renamed."],
  action = function()
    askName(L_RENAME_TO, L_RENAME, current(), function(name)
      done(Profiles.rename(ns.db, ns.chardb, current(), name))
    end)
  end,
})

define({
  key = "profileDelete", type = "button", label = L["Delete profile"],
  tooltip = L["Deletes this profile and switches to Default. Characters that used it use Default from now on."],
  action = function()
    local name = current()
    if name == Profiles.DEFAULT then return done(Profiles.delete(ns.db, ns.chardb, name)) end
    local W = widgets()
    if W and W.confirm then
      W.confirm(string.format(L_DELETE_Q, name), L_DELETE, function() done(Profiles.delete(ns.db, ns.chardb, name)) end)
    end
  end,
})

define({
  key = "profileExport", type = "button", label = L["Export profile"],
  tooltip = L["Shows this profile as one line of text to copy and share."],
  action = function()
    local Export = ns.UI and ns.UI.Export
    if Export then Export.show(Profiles.encode(ns.db.settings), L_EXPORT_TITLE) end
  end,
})

-- Import: paste box -> decode -> name -> (overwrite?) -> create and switch.
local function importAs(settings, taken, skipped, name)
  local trimmed = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
  local function finish(replace)
    local ok, err = Profiles.create(ns.db, trimmed, settings, replace)
    if not ok then return done(ok, err) end
    local Export = ns.UI and ns.UI.Export
    if Export and Export.hide then Export.hide() end
    Profiles.activate(ns.db, ns.chardb, trimmed)
    say(string.format(L_IMPORTED, taken, skipped))
    done(true)
  end
  if find(ns.db, trimmed) then
    local W = widgets()
    if W and W.confirm then W.confirm(string.format(L_OVERWRITE_Q, trimmed), L_OVERWRITE, function() finish(true) end) end
    return
  end
  finish(false)
end

define({
  key = "profileImport", type = "button", label = L["Import profile"],
  tooltip = L["Paste a profile line from an export. It becomes a new profile under a name you choose."],
  action = function()
    local Export = ns.UI and ns.UI.Export
    if not Export then return end
    Export.edit(L_IMPORT_TITLE, function(text)
      local settings, taken, skipped = Profiles.decode(text)
      if not settings then return say(taken) end
      askName(L_IMPORT_NAME, L_IMPORT, "", function(name) importAs(settings, taken, skipped, name) end)
    end)
  end,
})
