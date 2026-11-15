local ADDON, ns = ...

local num, posInt = ns.Util.isNumber, ns.Util.isPositiveInt

-- The loot session: a clock that can be stopped plus the looted items and raw
-- gold. Pure: the caller passes the time in. Shape:
--   { startedAt, running, runningSince, elapsedBase, gold,
--     items = { [key] = { id, key, link, qty, lastSeen, price } },
--     currencies = { [currencyID] = { id, link, qty, lastSeen } },
--     places = { [place label] = loot events there },
--     zones = per place loot / gold / time, at = current place (see below) }
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
    zones = {},
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

-- ---------------------------------------------------------------------------
-- Per place (History Zones): loot, raw gold and time per zone and subzone.
--   session.zones = { [zone] = { subs = { [sub] = { time, gold, items = { [key] = qty } } } } }
--   session.at = { zone, sub, since } -- the current place; `since` only while
--   the clock runs. Loot before any place is known goes to UNKNOWN_PLACE.

Session.UNKNOWN_PLACE = "?"

local function placeSlot(session, zone, sub)
  if type(session.zones) ~= "table" then session.zones = {} end
  local z = session.zones[zone]
  if type(z) ~= "table" then
    z = { subs = {} }
    session.zones[zone] = z
  end
  local s = z.subs[sub]
  if type(s) ~= "table" then
    s = { time = 0, gold = 0, items = {} }
    z.subs[sub] = s
  end
  return s
end

local function currentSlot(session)
  local at = session.at
  if type(at) == "table" then return placeSlot(session, at.zone, at.sub) end
  return placeSlot(session, Session.UNKNOWN_PLACE, Session.UNKNOWN_PLACE)
end

-- Seconds of the open stretch at the current place.
local function openStretch(session, now)
  local at = session.at
  if type(at) ~= "table" or not num(at.since) or not num(now) then return 0 end
  return math.max(0, now - at.since)
end

-- Adds the open stretch to the current place and restarts it at `now`.
local function closeStretch(session, now)
  local at = session.at
  if type(at) ~= "table" or not num(at.since) then return end
  local slot = placeSlot(session, at.zone, at.sub)
  slot.time = slot.time + openStretch(session, now)
  at.since = now
end

-- The player is now at `zone` / `sub` (sub nil or "" = the zone itself);
-- zone nil = unknown. The time so far goes to the place that was left.
function Session.enterPlace(session, zone, sub, now)
  if type(zone) ~= "string" or zone == "" then zone = nil end
  if type(sub) ~= "string" or sub == "" then sub = zone end
  local at = session.at
  if type(at) == "table" and at.zone == zone and at.sub == sub then return end
  closeStretch(session, now)
  if not zone then
    session.at = nil
    return
  end
  session.at = { zone = zone, sub = sub, since = session.running and now or nil }
end

function Session.notePlaceLoot(session, key, qty)
  if not (num(key) or type(key) == "string") or not posInt(qty) then return end
  local items = currentSlot(session).items
  items[key] = (items[key] or 0) + qty
end

function Session.notePlaceGold(session, copper)
  if not posInt(copper) then return end
  local slot = currentSlot(session)
  slot.gold = slot.gold + copper
end

-- Where the loot of the current place was picked up: per map, the summed
-- x / y (0..1) and the number of loot / gold events. Averaged by View.
--   slot.pos = { [mapID] = { x = sumX, y = sumY, n = count } }
function Session.notePlacePos(session, mapID, x, y)
  if not (num(mapID) and num(x) and num(y)) then return end
  local slot = currentSlot(session)
  if type(slot.pos) ~= "table" then slot.pos = {} end
  local p = slot.pos[mapID]
  if type(p) ~= "table" or not (num(p.x) and num(p.y) and num(p.n)) then
    p = { x = 0, y = 0, n = 0 }
    slot.pos[mapID] = p
  end
  p.x, p.y, p.n = p.x + x, p.y + y, p.n + 1
end

-- Valid position sums only (number x, y and n > 0), copied.
local function copyPos(pos)
  if type(pos) ~= "table" then return nil end
  local out, any = {}, false
  for mapID, p in pairs(pos) do
    if num(mapID) and type(p) == "table" and num(p.x) and num(p.y) and num(p.n) and p.n > 0 then
      out[mapID] = { x = p.x, y = p.y, n = p.n }
      any = true
    end
  end
  return any and out or nil
end
Session.copyPos = copyPos

-- A copy of session.zones with the open stretch counted up to `now`; the
-- session itself is not changed.
function Session.zoneSnapshot(session, now)
  local out = {}
  if type(session) ~= "table" or type(session.zones) ~= "table" then return out end
  for zone, z in pairs(session.zones) do
    if type(z) == "table" and type(z.subs) == "table" then
      local subs = {}
      for sub, s in pairs(z.subs) do
        if type(s) == "table" then
          local items = {}
          if type(s.items) == "table" then
            for key, qty in pairs(s.items) do
              if num(qty) and qty > 0 then items[key] = qty end
            end
          end
          subs[sub] = { time = num(s.time) and s.time or 0, gold = num(s.gold) and s.gold or 0, items = items,
            pos = copyPos(s.pos) }
        end
      end
      out[zone] = { subs = subs }
    end
  end
  local at = session.at
  local extra = openStretch(session, now)
  if extra > 0 then
    local z = out[at.zone] or { subs = {} }
    out[at.zone] = z
    local s = z.subs[at.sub] or { time = 0, gold = 0, items = {} }
    z.subs[at.sub] = s
    s.time = s.time + extra
  end
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
  if type(session.at) == "table" then session.at.since = now end
end

function Session.stop(session, now)
  if not session.running then return end
  session.elapsedBase = Session.elapsed(session, now)
  closeStretch(session, now)
  if type(session.at) == "table" then session.at.since = nil end
  session.running = false
  session.runningSince = nil
end

function Session.reset(session, now)
  session.items = {}
  session.currencies = {}
  session.places = {}
  session.zones = {}
  if type(session.at) == "table" then session.at.since = session.running and now or nil end
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
    closeStretch(session, now)
    if type(session.at) == "table" then session.at.since = nil end
  end
end

-- Login: restart the clock at the login time; offline time never counts.
function Session.resume(session, now)
  if session.running then
    session.runningSince = now
    if type(session.at) == "table" then session.at.since = now end
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
    if type(saved.zones) ~= "table" then saved.zones = {} end
    local at = saved.at
    if type(at) ~= "table" or type(at.zone) ~= "string" or type(at.sub) ~= "string" then saved.at = nil end
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
