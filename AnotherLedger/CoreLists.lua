local ADDON, ns = ...

-- Core's item lists (loads after Core.lua): the ignore list, the keep list
-- and the watch list with its loot alert.

local L = ns.L
local Core = ns.Core
local say = ns.Util.say
local function refreshUI() Core.refreshUI() end

-- Item lists (account-wide, { [itemID] = name or true } in AnotherLedgerDB):
--   ignored: left out of every list, total, alert and goal. They are still
--            recorded, so taking one off the list brings it back everywhere.
--   kept:    items you keep (tools, gear sets): Bags and Bank split their
--            total into kept and sellable.
-- Each list has get / add / remove / sorted functions, made by itemList.

local NO_ITEMS = {}

local function itemList(field)
  local function items()
    local db = ns.db
    if not db then return NO_ITEMS end
    if type(db[field]) ~= "table" then db[field] = {} end
    return db[field]
  end
  local function add(itemID, name)
    if not ns.Util.isNumber(itemID) or itemID <= 0 or not ns.db then return false end
    items()[itemID] = type(name) == "string" and name ~= "" and name or true
    refreshUI()
    return true
  end
  local function remove(itemID)
    local list = items()
    if list[itemID] == nil then return false end
    list[itemID] = nil
    refreshUI()
    return true
  end
  -- For the options menu: { { id, name }, ... } by name.
  local function sorted()
    local out = {}
    for id, name in pairs(items()) do
      out[#out + 1] = { id = id, name = type(name) == "string" and name or (L["Item "] .. tostring(id)) }
    end
    table.sort(out, function(a, b)
      if a.name ~= b.name then return a.name < b.name end
      return a.id < b.id
    end)
    return out
  end
  return items, add, remove, sorted
end

Core.ignoredItems, Core.ignoreItem, Core.unignoreItem, Core.ignoredList = itemList("ignored")
Core.keptItems, Core.keepItem, Core.unkeepItem, Core.keptList = itemList("kept")
-- The watch list: an item on it says so in chat, with a sound and a line in
-- the middle of the screen, whenever you loot it (Core.watchAlert). By item ID
-- (db.watched, like the ignore list) or by a text its name contains
-- (db.watchedNames = { [lower case text] = text as typed }: "Pattern:").
Core.watchedItems, Core.watchItem, Core.unwatchItem, Core.watchedList = itemList("watched")

Core.WATCH_TEXT_MIN = 3 -- shorter texts would match nearly everything

local function watchedNames()
  local db = ns.db
  if not db then return NO_ITEMS end
  if type(db.watchedNames) ~= "table" then db.watchedNames = {} end
  return db.watchedNames
end
Core.watchedNames = watchedNames

-- Watches every item whose name contains `text` (case ignored). Returns
-- whether it was added (false: too short, or no saved data yet).
function Core.watchName(text)
  if type(text) ~= "string" or not ns.db then return false end
  text = text:match("^%s*(.-)%s*$")
  if #text < Core.WATCH_TEXT_MIN then return false end
  watchedNames()[text:lower()] = text
  refreshUI()
  return true
end

function Core.unwatchName(text)
  if type(text) ~= "string" then return false end
  local key = text:match("^%s*(.-)%s*$"):lower()
  local names = watchedNames()
  if names[key] == nil then return false end
  names[key] = nil
  refreshUI()
  return true
end

-- Pure. Whether an item is watched: its ID is in `ids`, or its name contains
-- one of the texts of `names` (keys in lower case).
function Core.watchMatch(itemID, name, ids, names)
  if type(ids) == "table" and itemID ~= nil and ids[itemID] ~= nil then return true end
  if type(names) == "table" and type(name) == "string" and name ~= "" then
    local lower = name:lower()
    for text in pairs(names) do
      if type(text) == "string" and text ~= "" and lower:find(text, 1, true) then return true end
    end
  end
  return false
end

local L_WATCHED = L["watched item looted: %s%s"]

local function watchNotice(text)
  if type(PlaySound) == "function" and type(SOUNDKIT) == "table" then
    local kit = SOUNDKIT.RAID_WARNING or SOUNDKIT.UI_EPICLOOT_TOAST
    if kit then pcall(PlaySound, kit) end
  end
  -- UNVERIFIED (check in client): SOUNDKIT.RAID_WARNING plays the raid warning
  -- sound; UIErrorsFrame:AddMessage(text, r, g, b) shows the line in the
  -- middle of the screen for a few seconds.
  local frame = _G.UIErrorsFrame
  if type(frame) == "table" and type(frame.AddMessage) == "function" then
    local c = ns.Theme and ns.Theme.colors.gold or { 1, 0.82, 0 }
    pcall(frame.AddMessage, frame, text, c[1], c[2], c[3])
  end
end

-- A watched item was looted (also while the clock is stopped): chat line,
-- sound and screen line. Returns whether it alerted.
function Core.watchAlert(link, qty, itemID)
  local db = ns.db
  if not db or type(link) ~= "string" then return false end
  local name = link:match("%[(.-)%]")
  if not Core.watchMatch(itemID, name, db.watched, db.watchedNames) then return false end
  local text = string.format(L_WATCHED, link, (qty or 1) > 1 and (" x" .. qty) or "")
  say(text)
  watchNotice(text)
  return true
end
