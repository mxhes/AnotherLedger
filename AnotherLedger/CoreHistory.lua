local ADDON, ns = ...

-- Core's History section (loads after Core.lua): every character's History
-- list, delete / clear / merge and /al undo.

local L = ns.L
local Core = ns.Core
local say = ns.Util.say
local function refreshUI() Core.refreshUI() end

-- History lists. Every character's History lives in AnotherLedgerDB.histories
-- ({ ["Name-Realm"] = list }), so History Zones and the Daily farm can use
-- them all; ns.chardb.history is this character's list there while logged in
-- (Core.linkHistory at login, unlinked at logout so it is not saved twice).

-- "Name-Realm" of the logged-in character, or nil while the client does not
-- know it (then History stays per character, as before).
function Core.characterKey(env)
  local name = type(env.UnitName) == "function" and env.UnitName("player") or nil
  if type(name) ~= "string" or name == "" then return nil end
  local realm = type(env.GetRealmName) == "function" and env.GetRealmName() or nil
  if type(realm) ~= "string" or realm == "" then return name end
  return name .. "-" .. realm
end

function Core.linkHistory()
  local key = Core.characterKey(_G)
  if not (key and ns.db and ns.chardb) then return end
  if type(ns.db.histories) ~= "table" then ns.db.histories = {} end
  ns.chardb.history = ns.History.adopt(ns.db.histories, key, ns.chardb.history)
  Core.character = key
  -- The options panel lists which characters use a profile.
  if ns.Profiles then ns.Profiles.noteUser(ns.db, key, ns.Profiles.active(ns.chardb)) end
end

local function historyList()
  local chardb = ns.chardb
  if not chardb then return nil end
  if type(chardb.history) ~= "table" then chardb.history = {} end
  return chardb.history
end

-- The History that Zones and the Daily farm read, and a key that changes with
-- it: every character's (option "accountZones"), else this character's.
function Core.zoneHistory()
  local own = historyList() or {}
  local all = ns.db and ns.db.histories
  if Core.character and type(all) == "table" and ns.Util.setting("accountZones", true) then
    return ns.History.combine(all)
  end
  return ns.History.combine({ own = own })
end

-- History changes of this login that /al undo takes back, the last one last:
-- { restore = { entry, ... } (put back), drop = entry or nil (taken out
-- again: a merged session) }. Not saved, a reload or logout forgets them.
local undoStack = {}

-- Deletes the session at `index` of this character's History.
function Core.deleteHistory(index)
  local list = historyList()
  local entry = list and list[index]
  if not ns.History.remove(list, index) then return false end
  undoStack[#undoStack + 1] = { restore = { entry } }
  say(L["session deleted from History. /al undo brings it back."])
  return true
end

-- Deletes every session of this character's History (the options' button asks first).
function Core.clearHistory()
  local list = historyList()
  if not list or #list == 0 then return false end
  local copy = {}
  for i, e in ipairs(list) do copy[i] = e end
  ns.History.clear(list)
  undoStack[#undoStack + 1] = { restore = copy }
  say(L["History cleared. /al undo brings it back."])
  refreshUI()
  return true
end

-- Whether the session at `index` has an older one to merge with.
function Core.canMergeHistory(index)
  local list = historyList()
  local History = ns.History
  return list ~= nil and History.valid(list[index]) and History.valid(list[index + 1]) or false
end

-- Merges the session at `index` with the next older one (History is newest
-- first) into one session in their place. Returns the merged entry or nil.
function Core.mergeHistory(index)
  if not Core.canMergeHistory(index) then return nil end
  local list = historyList()
  local newer, older = list[index], list[index + 1]
  local merged = ns.History.merge(newer, older)
  if not merged then return nil end
  list[index] = merged
  table.remove(list, index + 1)
  ns.History.changed()
  undoStack[#undoStack + 1] = { restore = { newer, older }, drop = merged }
  say(L["sessions merged. /al undo splits them again."])
  return merged
end

-- Takes back the last delete, clear or merge. Returns how many sessions came back.
function Core.undoDelete()
  local last = table.remove(undoStack)
  local list = historyList()
  if not (last and list) then
    say(L["nothing to undo."])
    return 0
  end
  if last.drop then
    for i = #list, 1, -1 do
      if list[i] == last.drop then table.remove(list, i) end
    end
  end
  local n = ns.History.restore(list, last.restore)
  local ledger = ns.UI and ns.UI.Ledger
  if ledger then ledger.historyIndex = nil end
  if last.drop then
    say(L["the merged session is split again."])
  else
    say(string.format(L["%d session(s) back in History."], n))
  end
  refreshUI()
  return n
end
