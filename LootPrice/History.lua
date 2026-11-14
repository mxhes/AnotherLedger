local ADDON, ns = ...

-- Archive of finished sessions (per character, newest first). Pure: no WoW
-- globals. An entry is a snapshot taken when a session is thrown away (Reset,
-- or a fresh login without "keep session"):
--   { startedAt, elapsed, gold, nItems, vendor, ah, unpriced,
--     items = { [itemID] = { id, link, qty, lastSeen } } }
-- The vendor / AH totals are the prices at archive time.
local History = {
  DEFAULT_LIMIT = 50,
  UNLIMITED = -1,
}

local function num(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function nonNeg(v)
  return num(v) and v >= 0 and v or 0
end

-- Snapshot of `session`, or nil when it holds nothing worth keeping (no items
-- and no gold). `lookup(itemID)` returns { vendor, ah } or nil; `now` ends a
-- still running clock.
function History.snapshot(session, lookup, now)
  if type(session) ~= "table" or type(session.items) ~= "table" then return nil end
  local items, count, vendor, ah, unpriced = {}, 0, 0, 0, 0
  for _, it in pairs(session.items) do
    if type(it) == "table" and num(it.id) and num(it.qty) and it.qty > 0 then
      items[it.id] = {
        id = it.id,
        link = type(it.link) == "string" and it.link or nil,
        qty = it.qty,
        lastSeen = nonNeg(it.lastSeen),
      }
      count = count + 1
      local p = lookup and lookup(it.id)
      if type(p) ~= "table" then p = {} end
      if num(p.vendor) then vendor = vendor + p.vendor * it.qty end
      if num(p.ah) then ah = ah + p.ah * it.qty else unpriced = unpriced + 1 end
    end
  end
  local gold = nonNeg(session.gold)
  if count == 0 and gold <= 0 then return nil end
  local elapsed = nonNeg(session.elapsedBase)
  if session.running and num(session.runningSince) and num(now) and ns.Session and ns.Session.elapsed then
    local ok, v = pcall(ns.Session.elapsed, session, now)
    if ok and num(v) then elapsed = nonNeg(v) end
  end
  return {
    startedAt = nonNeg(session.startedAt), elapsed = elapsed, gold = gold,
    nItems = count, vendor = vendor, ah = ah, unpriced = unpriced, items = items,
  }
end

-- Drops the oldest entries beyond `limit` (negative = unlimited).
function History.prune(list, limit)
  if type(list) ~= "table" or not num(limit) or limit < 0 then return end
  while #list > limit do table.remove(list) end
end

-- Adds `entry` as the newest one, then prunes. limit 0 keeps nothing.
function History.add(list, entry, limit)
  if type(list) ~= "table" or type(entry) ~= "table" then return false end
  if not num(limit) then limit = History.DEFAULT_LIMIT end
  if limit == 0 then return false end
  table.insert(list, 1, entry)
  History.prune(list, limit)
  return true
end

-- Whether a saved entry is usable (the list lives in saved variables).
function History.valid(e)
  return type(e) == "table" and num(e.startedAt) and num(e.elapsed) and num(e.gold)
    and num(e.nItems) and num(e.vendor) and num(e.ah) and type(e.items) == "table"
end

-- "1h 12m", "12m", "45s".
function History.duration(seconds)
  if not num(seconds) or seconds < 0 then seconds = 0 end
  seconds = math.floor(seconds)
  if seconds >= 3600 then
    return math.floor(seconds / 3600) .. "h " .. math.floor((seconds % 3600) / 60) .. "m"
  end
  if seconds >= 60 then return math.floor(seconds / 60) .. "m" end
  return seconds .. "s"
end

ns.History = History
