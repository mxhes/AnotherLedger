local ADDON, ns = ...

local Session = {
  LARGE_SESSION_ITEMS = 25,
}

local function num(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function posInt(v)
  return num(v) and v > 0 and v == math.floor(v)
end

function Session.new(now)
  return {
    startedAt = now,
    running = true,
    runningSince = now,
    elapsedBase = 0,
    items = {},
  }
end

function Session.elapsed(session, now)
  local total = session.elapsedBase
  if session.running and session.runningSince then
    total = total + math.max(0, now - session.runningSince)
  end
  return total
end

function Session.add(session, itemID, link, qty, now)
  if not session.running then return false end
  if not num(itemID) or not posInt(qty) then return false end
  local item = session.items[itemID]
  if not item then
    item = { id = itemID, link = link, qty = 0, lastSeen = now }
    session.items[itemID] = item
  end
  item.qty = item.qty + qty
  item.lastSeen = now
  if link ~= nil then item.link = link end
  return true
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
    if not num(key) or not validItem(it) or it.id ~= key then return false end
  end
  return true
end

function Session.login(saved, keep, now)
  if keep and validSession(saved) then
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
