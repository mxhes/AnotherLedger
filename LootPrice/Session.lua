local ADDON, ns = ...

local num, posInt = ns.Util.isNumber, ns.Util.isPositiveInt

-- The loot session: a clock that can be stopped plus the looted items and raw
-- gold. Pure: the caller passes the time in. Shape:
--   { startedAt, running, runningSince, elapsedBase, gold,
--     items = { [key] = { id, key, link, qty, lastSeen, price } },
--     currencies = { [currencyID] = { id, link, qty, lastSeen } },
--     places = { [place label] = loot events there } }
-- `key` is LootParse.itemKey: the item ID for a plain item, a string with the
-- bonus IDs for item variants. `price` = { vendor, ah, de } is the unit price
-- seen at loot time (a fallback for History when no live price is known).

local Session = {
  LARGE_SESSION_ITEMS = 25,
}

function Session.new(now)
  return {
    startedAt = now,
    running = true,
    runningSince = now,
    elapsedBase = 0,
    items = {},
    currencies = {},
    places = {},
    gold = 0,
  }
end

function Session.elapsed(session, now)
  local total = session.elapsedBase
  if session.running and session.runningSince then
    total = total + math.max(0, now - session.runningSince)
  end
  return total
end

-- `key` defaults to the item ID. Returns true and the stored item, or false
-- when the loot was not recorded (clock stopped, bad input).
function Session.add(session, itemID, link, qty, now, key)
  if not session.running then return false end
  if not num(itemID) or not posInt(qty) then return false end
  if key == nil then key = itemID end
  if not (num(key) or type(key) == "string") then return false end
  local item = session.items[key]
  if not item then
    item = { id = itemID, key = key, link = link, qty = 0, lastSeen = now }
    session.items[key] = item
  end
  item.qty = item.qty + qty
  item.lastSeen = now
  if link ~= nil then item.link = link end
  return true, item
end

-- Remembers the unit prices seen at loot time ({ vendor, ah, de }, each optional).
function Session.setPrice(item, info)
  if type(item) ~= "table" or type(info) ~= "table" then return end
  local p = {}
  for _, k in ipairs({ "vendor", "ah", "de" }) do
    if num(info[k]) and info[k] >= 0 then p[k] = info[k] end
  end
  if next(p) then item.price = p end
end

-- Whether any stored item (any variant) has the item ID.
function Session.hasItemID(items, itemID)
  if type(items) ~= "table" then return false end
  if items[itemID] ~= nil then return true end
  for _, it in pairs(items) do
    if type(it) == "table" and it.id == itemID then return true end
  end
  return false
end

-- Currency income (CHAT_MSG_CURRENCY). Returns whether it was recorded.
function Session.addCurrency(session, currencyID, link, qty, now)
  if not session.running then return false end
  if not num(currencyID) or not posInt(qty) then return false end
  if type(session.currencies) ~= "table" then session.currencies = {} end
  local c = session.currencies[currencyID]
  if not c then
    c = { id = currencyID, qty = 0 }
    session.currencies[currencyID] = c
  end
  c.qty = c.qty + qty
  c.lastSeen = now
  if type(link) == "string" then c.link = link end
  return true
end

-- Counts one loot event at `place` (zone, or instance and difficulty).
function Session.notePlace(session, place)
  if type(place) ~= "string" or place == "" then return end
  if type(session.places) ~= "table" then session.places = {} end
  session.places[place] = (num(session.places[place]) and session.places[place] or 0) + 1
end

-- The places of a session, most loot events first: { label, ... }.
function Session.placeList(places)
  local list = {}
  if type(places) ~= "table" then return list end
  for label, n in pairs(places) do
    if type(label) == "string" and num(n) then list[#list + 1] = { label = label, n = n } end
  end
  table.sort(list, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return a.label < b.label
  end)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.label end
  return out
end

-- Raw gold income in copper (looted and quest money, one total).
function Session.addGold(session, copper, now)
  if not session.running then return false end
  if not posInt(copper) then return false end
  session.gold = (num(session.gold) and session.gold or 0) + copper
  return true
end

function Session.goldTotal(session)
  return num(session.gold) and session.gold or 0
end

function Session.start(session, now)
  if session.running then return end
  session.running = true
  session.runningSince = now
end

function Session.stop(session, now)
  if not session.running then return end
  session.elapsedBase = Session.elapsed(session, now)
  session.running = false
  session.runningSince = nil
end

function Session.reset(session, now)
  session.items = {}
  session.currencies = {}
  session.places = {}
  session.gold = 0
  session.startedAt = now
  session.elapsedBase = 0
  session.runningSince = session.running and now or nil
end

-- Logout: fold running time into elapsedBase, keep the running flag.
function Session.suspend(session, now)
  if session.running then
    session.elapsedBase = Session.elapsed(session, now)
    session.runningSince = nil
  end
end

-- Login: restart the clock at the login time; offline time never counts.
function Session.resume(session, now)
  if session.running then
    session.runningSince = now
  end
end

local function validItem(it)
  return type(it) == "table" and num(it.id) and posInt(it.qty) and num(it.lastSeen)
    and (it.link == nil or type(it.link) == "string")
end

local function validSession(s)
  if type(s) ~= "table" then return false end
  if not num(s.startedAt) or type(s.running) ~= "boolean" then return false end
  if not num(s.elapsedBase) or s.elapsedBase < 0 then return false end
  if s.runningSince ~= nil and not num(s.runningSince) then return false end
  if type(s.items) ~= "table" then return false end
  for key, it in pairs(s.items) do
    if not validItem(it) then return false end
    if num(key) then
      if it.id ~= key then return false end
    elseif type(key) ~= "string" or it.key ~= key then
      return false
    end
  end
  return true
end

-- Missing gold (old records) -> 0. The old { looted, quest } table -> the sum of
-- its valid parts. Anything else malformed -> 0.
local function normalizeGold(s)
  local g = s.gold
  if type(g) == "table" then
    s.gold = ns.Util.nonNegative(g.looted) + ns.Util.nonNegative(g.quest)
  elseif not (num(g) and g >= 0) then
    s.gold = 0
  end
end

function Session.login(saved, keep, now)
  if keep and validSession(saved) then
    normalizeGold(saved)
    -- Older sessions have no currencies / places; malformed ones are dropped.
    if type(saved.currencies) ~= "table" then saved.currencies = {} end
    if type(saved.places) ~= "table" then saved.places = {} end
    Session.resume(saved, now)
    return saved
  end
  return Session.new(now)
end

function Session.itemCount(session)
  local n = 0
  for _ in pairs(session.items) do n = n + 1 end
  return n
end

function Session.needsResetConfirm(session)
  return Session.itemCount(session) >= Session.LARGE_SESSION_ITEMS
end

ns.Session = Session
