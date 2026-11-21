local ADDON, ns = ...

local L = ns.L

-- How much each part of the saved data takes (/al stats). Pure: the tables
-- are handed in. Sizes are estimates of the text the game writes into
-- WTF/.../SavedVariables (keys, values, indentation, the "-- [n]" notes of
-- list entries), close enough to see which part grows.
local Stats = {}
ns.Stats = Stats

local num = ns.Util.isNumber
local floor = math.floor

local function numberSize(v)
  if v == floor(v) and v > -1e15 and v < 1e15 then return #string.format("%.0f", v) end
  return 18
end

local function stringSize(s)
  local _, escapes = s:gsub("[\"\\\n]", "")
  return #s + 2 + escapes
end

local function keySize(k)
  if type(k) == "string" then return stringSize(k) + 2 end -- ["key"]
  if type(k) == "number" then return numberSize(k) + 2 end -- [12]
  return 8
end

-- Estimated bytes of `v` written at `depth` (tabs). A table met twice (an
-- alias, like the active profile under `settings`) counts once: `seen`.
function Stats.size(v, depth, seen)
  local t = type(v)
  if t == "string" then return stringSize(v) end
  if t == "number" then return num(v) and numberSize(v) or 5 end
  if t == "boolean" then return v and 4 or 5 end
  if t ~= "table" then return 3 end
  seen = seen or {}
  if seen[v] then return 0 end
  seen[v] = true
  depth = depth or 0
  local total = 2 + depth + 1 -- "{\n" ... "}"
  local n = #v
  for k, x in pairs(v) do
    local entry = Stats.size(x, depth + 1, seen) + depth + 1 + 2 -- indent, ",\n"
    if type(k) == "number" and k >= 1 and k <= n and k == floor(k) then
      entry = entry + 7 + numberSize(k) -- " -- [n]"
    else
      entry = entry + keySize(k) + 3 -- " = "
    end
    total = total + entry
  end
  return total
end

local function count(t)
  local n = 0
  if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
  return n
end

-- The parts of the account data (AnotherLedgerDB) and of the character's
-- (AnotherLedgerCharDB): { total, parts = { { key, size, n, m }, ... } }, the
-- largest part first, "other" (options, lists, window) last.
--   history: n sessions on m characters (mobs: the size of their mob data)
--   scan: n items on m realms; trade: n log entries; cache: n prices;
--   character: this character's session and bank scan.
function Stats.collect(db, chardb)
  db = type(db) == "table" and db or {}
  local seen = {}
  local parts = {}

  -- Every character's list, plus the character's own when it is not one of
  -- them (no character name yet: History stays in the character file).
  local lists = {}
  for _, list in pairs(type(db.histories) == "table" and db.histories or {}) do
    if type(list) == "table" then lists[#lists + 1] = list end
  end
  local own = type(chardb) == "table" and type(chardb.history) == "table" and chardb.history or nil
  for _, list in ipairs(lists) do
    if list == own then own = nil end
  end
  if own then lists[#lists + 1] = own end
  local sessions, mobsSize, historySize = 0, 0, 0
  for _, list in ipairs(lists) do
    historySize = historySize + Stats.size(list, 1, seen)
    for _, e in ipairs(list) do
      sessions = sessions + 1
      if type(e) == "table" and type(e.mobs) == "table" then
        mobsSize = mobsSize + Stats.size(e.mobs, 4)
      end
    end
  end
  parts[#parts + 1] = { key = "history", size = historySize, n = sessions, m = #lists, mobs = mobsSize }

  local scanItems, realms = 0, 0
  for _, bucket in pairs(type(db.scan) == "table" and db.scan or {}) do
    realms = realms + 1
    if type(bucket) == "table" then scanItems = scanItems + count(bucket.items) end
  end
  parts[#parts + 1] = { key = "scan", size = Stats.size(db.scan or {}, 1, seen), n = scanItems, m = realms }

  local entries = 0
  for _, bucket in pairs(type(db.trade) == "table" and db.trade or {}) do
    if type(bucket) == "table" and type(bucket.log) == "table" then entries = entries + #bucket.log end
  end
  parts[#parts + 1] = { key = "trade", size = Stats.size(db.trade or {}, 1, seen), n = entries }

  local prices = 0
  for _, bucket in pairs(type(db.cache) == "table" and db.cache or {}) do prices = prices + count(bucket) end
  parts[#parts + 1] = { key = "cache", size = Stats.size(db.cache or {}, 1, seen), n = prices }

  -- Both files; what the character file shares with the account file (the
  -- History alias, the session) counts once.
  local fileSeen = {}
  local total = Stats.size(db, 0, fileSeen)
  if type(chardb) == "table" then total = total + Stats.size(chardb, 0, fileSeen) end
  -- The character file without its History (counted above).
  local charSize = type(chardb) == "table" and Stats.size(chardb, 0, seen) or 0
  parts[#parts + 1] = { key = "character", size = charSize }

  local counted = 0
  for _, p in ipairs(parts) do counted = counted + p.size end
  table.sort(parts, function(a, b) return a.size > b.size end)
  parts[#parts + 1] = { key = "other", size = math.max(0, total - counted) }
  return { total = total, parts = parts }
end

-- "312 B", "4.2 KB", "1.8 MB".
function Stats.bytes(n)
  if not num(n) or n < 1024 then return string.format("%d B", num(n) and n or 0) end
  if n < 1024 * 1024 then return string.format("%.1f KB", n / 1024) end
  return string.format("%.1f MB", n / (1024 * 1024))
end

local L_TOTAL = L["Saved data: about %s."]
local L_HISTORY = L["History: %s (sessions: %d, characters: %d, mob data: %s). Options: History kept, Mob data kept."]
local L_SCAN = L["Auction house scan: %s (items: %d, realms: %d). Prices older than 14 days are dropped."]
local L_TRADE = L["Trade log: %s (entries: %d). Option: Trade log kept."]
local L_CACHE = L["Price cache: %s (prices: %d). Prices older than 30 days are dropped."]
local L_CHARACTER = L["This character (session, bank): %s."]
local L_OTHER = L["Options, lists and window: %s."]

-- The chat lines of /al stats for Stats.collect's result.
function Stats.lines(stats)
  local out = { string.format(L_TOTAL, Stats.bytes(stats.total)) }
  for _, p in ipairs(stats.parts) do
    local size = Stats.bytes(p.size)
    local line
    if p.key == "history" then
      line = string.format(L_HISTORY, size, p.n, p.m, Stats.bytes(p.mobs))
    elseif p.key == "scan" then
      line = string.format(L_SCAN, size, p.n, p.m)
    elseif p.key == "trade" then
      line = string.format(L_TRADE, size, p.n)
    elseif p.key == "cache" then
      line = string.format(L_CACHE, size, p.n)
    elseif p.key == "character" then
      line = string.format(L_CHARACTER, size)
    else
      line = string.format(L_OTHER, size)
    end
    out[#out + 1] = "  " .. line
  end
  return out
end
