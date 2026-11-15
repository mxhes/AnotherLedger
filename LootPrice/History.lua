local ADDON, ns = ...

local L = ns.L

-- Archive of finished sessions (per character, newest first). Pure: no WoW
-- globals. An entry is a snapshot taken when a session is thrown away (Reset,
-- a fresh login without "keep session", or the new-session-per-instance option):
--   { startedAt, elapsed, gold, nItems, vendor, ah, best,
--     places = { "label", ... } (most loot first),
--     items = { [key] = { id, key, link, qty, lastSeen, price } },
--     currencies = { [currencyID] = { id, link, qty } },
--     zones = Session.zoneSnapshot (loot, gold and time per zone / subzone) }
-- The vendor / AH / best totals are the prices at archive time; an item the
-- live lookup cannot price falls back to the price seen when it was looted.
local History = {
  DEFAULT_LIMIT = 50,
  UNLIMITED = -1,
  MAX_PLACES = 5,
}

local num, nonNeg = ns.Util.isNumber, ns.Util.nonNegative

local L_PLACES = L["Places: "]
local L_ITEMS = L[" items"]
local L_ONE_ITEM = L["1 item"]
local L_VENDOR = L["Vendor: "]
local L_AH = L["AH: "]
local L_BEST = L["Best: "]
local L_GOLD = L["Raw gold: "]
local L_CURRENCIES = L["Currencies: "]
local L_CURRENCY = L["Currency "]

local function copyPrice(p)
  if type(p) ~= "table" then return nil end
  local out = {}
  for _, k in ipairs({ "vendor", "ah", "de" }) do
    if num(p[k]) then out[k] = p[k] end
  end
  return next(out) and out or nil
end

-- Snapshot of `session`, or nil when it holds nothing worth keeping (no items,
-- currencies or gold). `lookup(itemID, link)` returns { vendor, ah, de } or
-- nil; `now` ends a still running clock.
function History.snapshot(session, lookup, now)
  if type(session) ~= "table" or type(session.items) ~= "table" then return nil end
  local items, count, vendor, ah, best = {}, 0, 0, 0, 0
  for key, it in pairs(session.items) do
    if type(it) == "table" and num(it.id) and num(it.qty) and it.qty > 0 then
      local itemKey = it.key or key
      local saved = copyPrice(it.price) or {}
      local p = lookup and lookup(it.id, it.link)
      if type(p) ~= "table" then p = {} end
      local v = num(p.vendor) and p.vendor or saved.vendor
      local a = num(p.ah) and p.ah or saved.ah
      local d = num(p.de) and p.de or saved.de
      -- The unit prices the totals are made of: an opened session lists its
      -- items at these, so they add up to the session row.
      items[itemKey] = {
        id = it.id,
        key = itemKey,
        link = type(it.link) == "string" and it.link or nil,
        qty = it.qty,
        lastSeen = nonNeg(it.lastSeen),
        price = copyPrice({ vendor = v, ah = a, de = d }),
      }
      count = count + 1
      if v then vendor = vendor + v * it.qty end
      if a then ah = ah + a * it.qty end
      best = best + math.max(v or 0, a or 0, d or 0) * it.qty
    end
  end
  local currencies, nCurrencies = {}, 0
  if type(session.currencies) == "table" then
    for id, c in pairs(session.currencies) do
      if type(c) == "table" and num(id) and num(c.qty) and c.qty > 0 then
        currencies[id] = { id = id, qty = c.qty, link = type(c.link) == "string" and c.link or nil }
        nCurrencies = nCurrencies + 1
      end
    end
  end
  local gold = nonNeg(session.gold)
  if count == 0 and nCurrencies == 0 and gold <= 0 then return nil end
  local elapsed = nonNeg(session.elapsedBase)
  if session.running and num(session.runningSince) and num(now) and ns.Session and ns.Session.elapsed then
    local ok, v = pcall(ns.Session.elapsed, session, now)
    if ok and num(v) then elapsed = nonNeg(v) end
  end
  local places = {}
  if ns.Session and ns.Session.placeList then
    for i, label in ipairs(ns.Session.placeList(session.places)) do
      if i > History.MAX_PLACES then break end
      places[i] = label
    end
  end
  local zones
  if ns.Session and ns.Session.zoneSnapshot then zones = ns.Session.zoneSnapshot(session, now) end
  return {
    startedAt = nonNeg(session.startedAt), elapsed = elapsed, gold = gold,
    nItems = count, vendor = vendor, ah = ah, best = best,
    places = places, items = items, currencies = currencies, zones = zones,
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

-- Removes the entry at `index` (1 = newest). Returns whether one was removed.
function History.remove(list, index)
  if type(list) ~= "table" or not num(index) or not list[index] then return false end
  table.remove(list, index)
  return true
end

-- Empties the list in place (the saved table stays the same table).
function History.clear(list)
  if type(list) ~= "table" then return end
  for i = #list, 1, -1 do list[i] = nil end
end

-- Whether a saved entry is usable (the list lives in saved variables).
function History.valid(e)
  return type(e) == "table" and num(e.startedAt) and num(e.elapsed) and num(e.gold)
    and num(e.nItems) and num(e.vendor) and num(e.ah) and type(e.items) == "table"
end

-- Best value of an entry; entries saved before it existed use their AH total.
function History.bestOf(e)
  if num(e.best) then return e.best end
  return math.max(e.ah or 0, e.vendor or 0)
end

-- Where most of the loot of an entry came from, or nil.
function History.place(e)
  local places = type(e) == "table" and e.places
  if type(places) == "table" and type(places[1]) == "string" then return places[1] end
  return nil
end

-- The currencies of an entry as "Name x3, Other x1" (by name), or nil. The
-- name comes from the saved link; `sep` joins the parts (default ", ").
function History.currencyText(e, sep)
  local list = {}
  if type(e) ~= "table" or type(e.currencies) ~= "table" then return nil end
  for id, c in pairs(e.currencies) do
    if type(c) == "table" and num(c.qty) and c.qty > 0 then
      local name = type(c.link) == "string" and c.link:match("%[(.-)%]") or (L_CURRENCY .. tostring(id))
      list[#list + 1] = { name = name, qty = c.qty }
    end
  end
  if #list == 0 then return nil end
  table.sort(list, function(a, b) return a.name < b.name end)
  for i, c in ipairs(list) do list[i] = c.name .. " x" .. c.qty end
  return table.concat(list, sep or ", ")
end

-- "1 item", "12 items".
function History.itemCount(n)
  if n == 1 then return L_ONE_ITEM end
  return tostring(n) .. L_ITEMS
end

local L_TODAY, L_YESTERDAY = L["Today"], L["Yesterday"]
local WEEKDAYS = { L["Sun"], L["Mon"], L["Tue"], L["Wed"], L["Thu"], L["Fri"], L["Sat"] }
-- The date of an older session (the German client writes 15.11.2026).
local L_DATE_FORMAT = L["%Y-%m-%d"]

-- The short start of a session for its row: "Today 20:21", "Yesterday 9:05",
-- a weekday within the last six days ("Sat 14:55"), else the date alone.
-- `dateFn` is the client's date (os.date): dateFn(format, timestamp).
function History.shortDate(ts, now, dateFn)
  if not (num(ts) and num(now)) or type(dateFn) ~= "function" then return tostring(ts) end
  local function day(t) return dateFn("%Y-%m-%d", t) end
  local clock = dateFn("%H:%M", ts)
  if day(ts) == day(now) then return L_TODAY .. " " .. clock end
  if day(ts) == day(now - 86400) then return L_YESTERDAY .. " " .. clock end
  if ts < now and now - ts < 6 * 86400 then
    local weekday = WEEKDAYS[(tonumber(dateFn("%w", ts)) or 0) + 1]
    return weekday .. " " .. clock
  end
  return dateFn(L_DATE_FORMAT, ts)
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

-- Copper per hour over `elapsed` seconds, or nil under a minute.
function History.perHour(amount, elapsed)
  if not num(amount) or not num(elapsed) or elapsed < 60 then return nil end
  return amount * 3600 / elapsed
end

-- Multi-line tooltip text of an entry: when, how long, where, the totals and
-- their rates. `formatDate(timestamp)` -> text; `formatMoney` defaults to Money.format.
-- The session's tooltip (ns.Tooltip): the start as title, its length and item
-- count, the places, then each value with its gold per hour.
function History.details(e, formatDate)
  local Tip = ns.Tooltip
  local when = formatDate and formatDate(e.startedAt) or tostring(e.startedAt)
  local tip = Tip.new(when)
  Tip.note(tip, History.duration(e.elapsed) .. ", " .. History.itemCount(e.nItems))
  if type(e.places) == "table" and #e.places > 0 then
    Tip.labelled(tip, L_PLACES, table.concat(e.places, ", "))
  end
  local currencies = History.currencyText(e)
  if currencies then Tip.labelled(tip, L_CURRENCIES, currencies) end
  local function money(label, amount, source)
    Tip.money(tip, label, amount, History.perHour(amount, e.elapsed), source)
  end
  money(L_VENDOR, e.vendor, "vendor")
  money(L_AH, e.ah, "ah")
  money(L_BEST, History.bestOf(e))
  money(L_GOLD, e.gold)
  return tip
end

-- ---------------------------------------------------------------------------
-- CSV export

History.CSV_HEADER = "start,duration_min,place,items,vendor_g,ah_g,best_g,raw_gold_g,best_plus_gold_per_hour_g,currencies"

local function csvField(text)
  text = tostring(text or "")
  if text:find('[,"\n]') then text = '"' .. text:gsub('"', '""') .. '"' end
  return text
end

local function goldNumber(copper)
  return string.format("%.4f", (copper or 0) / 10000)
end

-- The History list as CSV text (header first, newest session first). Amounts
-- are in gold with four decimals so a spreadsheet can sum them.
function History.csv(list, formatDate)
  local out = { History.CSV_HEADER }
  if type(list) ~= "table" then list = {} end
  for _, e in ipairs(list) do
    if History.valid(e) then
      local best = History.bestOf(e)
      local rate = History.perHour(best + e.gold, e.elapsed)
      out[#out + 1] = table.concat({
        csvField(formatDate and formatDate(e.startedAt) or e.startedAt),
        string.format("%.1f", e.elapsed / 60),
        csvField(type(e.places) == "table" and table.concat(e.places, "; ") or ""),
        tostring(e.nItems),
        goldNumber(e.vendor), goldNumber(e.ah), goldNumber(best), goldNumber(e.gold),
        rate and goldNumber(rate) or "",
        csvField(History.currencyText(e, "; ") or ""),
      }, ",")
    end
  end
  return table.concat(out, "\n")
end

ns.History = History
