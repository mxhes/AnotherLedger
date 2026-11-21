local ADDON, ns = ...

-- Net worth of every character: each character saves what its bags, its last
-- bank scan and its gold were worth (copper, valued when saved) in
-- AnotherLedgerDB.worth = { ["Name-Realm"] = { bags, bank, money, at } }, so
-- the Bags footer can add up all characters. Saved by the Bags tab while it is
-- shown and at logout (Ledger.noteWorth). Pure: no client calls.
local Worth = {}

local function num(v)
  return ns.Util.isNumber(v)
end

local function store(db)
  if type(db) ~= "table" then return nil end
  if type(db.worth) ~= "table" then db.worth = {} end
  return db.worth
end

-- Saves the snapshot of character `key`: `snap` = { bags, bank (nil: never
-- scanned), money, at }. Returns whether it saved.
function Worth.note(db, key, snap)
  local saved = store(db)
  if not (saved and type(key) == "string" and key ~= "" and type(snap) == "table") then return false end
  if not (num(snap.bags) and num(snap.money)) then return false end
  saved[key] = {
    bags = snap.bags,
    bank = num(snap.bank) and snap.bank or nil,
    money = snap.money,
    at = num(snap.at) and snap.at or 0,
  }
  return true
end

-- The total of one snapshot (bags + bank + gold).
function Worth.total(e)
  if type(e) ~= "table" then return 0 end
  return (num(e.bags) and e.bags or 0) + (num(e.bank) and e.bank or 0) + (num(e.money) and e.money or 0)
end

-- Every saved character, richest first: { { key, bags, bank, money, at,
-- total, own }, ... } (`own`: the logged-in character `current`), and the sum.
function Worth.list(db, current)
  local out, sum = {}, 0
  local saved = type(db) == "table" and type(db.worth) == "table" and db.worth or {}
  for key, e in pairs(saved) do
    if type(key) == "string" and type(e) == "table" then
      local total = Worth.total(e)
      out[#out + 1] = { key = key, bags = e.bags, bank = e.bank, money = e.money, at = e.at,
        total = total, own = key == current }
      sum = sum + total
    end
  end
  table.sort(out, function(a, b)
    if a.total ~= b.total then return a.total > b.total end
    return a.key < b.key
  end)
  return out, sum
end

-- The saved character whose key is `text` or starts with it (case ignored):
-- its key, or nil when none or several match.
function Worth.find(db, text)
  if type(text) ~= "string" then return nil end
  local needle = text:match("^%s*(.-)%s*$"):lower()
  if needle == "" then return nil end
  local found
  for key in pairs(type(db) == "table" and type(db.worth) == "table" and db.worth or {}) do
    local lower = key:lower()
    if lower == needle then return key end
    if lower:sub(1, #needle) == needle then
      if found then return nil end
      found = key
    end
  end
  return found
end

-- Drops character `key` (a deleted or renamed character). Returns whether it was saved.
function Worth.forget(db, key)
  local saved = type(db) == "table" and type(db.worth) == "table" and db.worth or nil
  if not (saved and key and saved[key]) then return false end
  saved[key] = nil
  return true
end

ns.Worth = Worth
