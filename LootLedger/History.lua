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
local L_NOTE = L["Note: "]

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

-- The totals of an entry without the items on the ignore list (`ignored` =
-- { [itemID] = name or true }, see Core.ignoredItems), at the unit prices it
-- was saved with: vendor, ah, best, item count. Taking an item off the list
-- brings its value back.
function History.totals(e, ignored)
  local vendor, ah, best, count = e.vendor, e.ah, History.bestOf(e), e.nItems
  if type(ignored) ~= "table" or next(ignored) == nil or type(e.items) ~= "table" then
    return vendor, ah, best, count
  end
  for _, it in pairs(e.items) do
    if type(it) == "table" and ignored[it.id] and num(it.qty) then
      local p = type(it.price) == "table" and it.price or {}
      local v = num(p.vendor) and p.vendor or nil
      local a = num(p.ah) and p.ah or nil
      local d = num(p.de) and p.de or nil
      if v then vendor = vendor - v * it.qty end
      if a then ah = ah - a * it.qty end
      best = best - math.max(v or 0, a or 0, d or 0) * it.qty
      count = count - 1
    end
  end
  return math.max(0, vendor), math.max(0, ah), math.max(0, best), math.max(0, count)
end

-- ---------------------------------------------------------------------------
-- Notes: a short text of the player's own on a session ("Wingrest herbs").

History.NOTE_MAX = 60 -- characters

-- The note of an entry, or nil.
function History.note(e)
  local note = type(e) == "table" and e.note
  if type(note) == "string" and note ~= "" then return note end
  return nil
end

-- Sets (trimmed, at most NOTE_MAX characters) or, with an empty text, removes
-- the note of `e`. Returns the stored note or nil.
function History.setNote(e, text)
  if type(e) ~= "table" then return nil end
  local t = type(text) == "string" and text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]+", " ") or ""
  -- Cut by characters, never inside a UTF-8 sequence.
  local out, n = {}, 0
  for ch in t:gmatch("[\1-\127\194-\244][\128-\191]*") do
    n = n + 1
    if n > History.NOTE_MAX then break end
    out[n] = ch
  end
  t = table.concat(out)
  e.note = t ~= "" and t or nil
  return e.note
end

-- ---------------------------------------------------------------------------
-- Lists

-- Newest session first (the order History is kept in).
local function newerFirst(a, b)
  local x = type(a) == "table" and num(a.startedAt) and a.startedAt or 0
  local y = type(b) == "table" and num(b.startedAt) and b.startedAt or 0
  return x > y
end

-- Puts deleted `entries` back into `list` (undo), in start order.
function History.restore(list, entries)
  if type(list) ~= "table" or type(entries) ~= "table" then return 0 end
  for _, e in ipairs(entries) do list[#list + 1] = e end
  table.sort(list, newerFirst)
  return #entries
end

-- ---------------------------------------------------------------------------
-- Merging: two saved sessions become one (a dungeon run split by leaving and
-- entering again, a break that started a new session). Pure; neither input
-- is changed.

-- Unit prices of an item found in both sessions: per source, the average
-- weighted by quantity where both have one, else the one that exists.
local function mergePrice(pa, qa, pb, qb)
  pa = type(pa) == "table" and pa or {}
  pb = type(pb) == "table" and pb or {}
  local out = {}
  for _, k in ipairs({ "vendor", "ah", "de" }) do
    local a, b = num(pa[k]) and pa[k] or nil, num(pb[k]) and pb[k] or nil
    if a and b then
      out[k] = math.floor((a * qa + b * qb) / (qa + qb) + 0.5)
    else
      out[k] = a or b
    end
  end
  return next(out) and out or nil
end

local function mergeItems(a, b)
  local out = {}
  for _, src in ipairs({ a, b }) do
    for key, it in pairs(type(src) == "table" and src or {}) do
      if type(it) == "table" and num(it.id) and num(it.qty) and it.qty > 0 then
        local have = out[key]
        if not have then
          out[key] = { id = it.id, key = it.key or key, link = it.link, qty = it.qty, lastSeen = it.lastSeen,
            price = copyPrice(it.price) }
        else
          have.price = mergePrice(have.price, have.qty, it.price, it.qty)
          have.qty = have.qty + it.qty
          if num(it.lastSeen) and (not num(have.lastSeen) or it.lastSeen > have.lastSeen) then
            have.lastSeen = it.lastSeen
            if type(it.link) == "string" then have.link = it.link end
          end
        end
      end
    end
  end
  return out
end

local function mergeCurrencies(a, b)
  local out = {}
  for _, src in ipairs({ a, b }) do
    for id, c in pairs(type(src) == "table" and src or {}) do
      if type(c) == "table" and num(c.qty) and c.qty > 0 then
        local have = out[id]
        if have then
          have.qty = have.qty + c.qty
        else
          out[id] = { id = c.id or id, qty = c.qty, link = c.link }
        end
      end
    end
  end
  return out
end

-- Session.zoneSnapshot shapes: time, gold, loot and map positions per subzone add up.
local function mergeZones(a, b)
  local out = {}
  for _, src in ipairs({ a, b }) do
    for zone, z in pairs(type(src) == "table" and src or {}) do
      if type(z) == "table" and type(z.subs) == "table" then
        local oz = out[zone] or { subs = {} }
        out[zone] = oz
        for sub, s in pairs(z.subs) do
          if type(s) == "table" then
            local os = oz.subs[sub] or { time = 0, gold = 0, items = {}, pos = {} }
            oz.subs[sub] = os
            if num(s.time) then os.time = os.time + s.time end
            if num(s.gold) then os.gold = os.gold + s.gold end
            for key, qty in pairs(type(s.items) == "table" and s.items or {}) do
              if num(qty) and qty > 0 then os.items[key] = (os.items[key] or 0) + qty end
            end
            for mapID, p in pairs(type(s.pos) == "table" and s.pos or {}) do
              if type(p) == "table" and num(p.x) and num(p.y) and num(p.n) then
                local d = os.pos[mapID] or { x = 0, y = 0, n = 0 }
                os.pos[mapID] = d
                d.x, d.y, d.n = d.x + p.x, d.y + p.y, d.n + p.n
              end
            end
          end
        end
      end
    end
  end
  return out
end

-- Places of the more valuable session first, then the other's, at most MAX_PLACES.
local function mergePlaces(first, second)
  local out, seen = {}, {}
  for _, list in ipairs({ first, second }) do
    for _, label in ipairs(type(list) == "table" and list or {}) do
      if type(label) == "string" and not seen[label] and #out < History.MAX_PLACES then
        seen[label] = true
        out[#out + 1] = label
      end
    end
  end
  return out
end

-- One entry of two valid ones: it starts with the earlier one and lasts as
-- long as both clocks together (the time between them never counts). Values,
-- gold, items, currencies and places add up; both notes are kept.
function History.merge(a, b)
  if not (History.valid(a) and History.valid(b)) then return nil end
  local items = mergeItems(a.items, b.items)
  local count = 0
  for _ in pairs(items) do count = count + 1 end
  local first, second = a, b
  if History.bestOf(b) + b.gold > History.bestOf(a) + a.gold then first, second = b, a end
  local merged = {
    startedAt = math.min(a.startedAt, b.startedAt), elapsed = a.elapsed + b.elapsed, gold = a.gold + b.gold,
    nItems = count, vendor = a.vendor + b.vendor, ah = a.ah + b.ah, best = History.bestOf(a) + History.bestOf(b),
    places = mergePlaces(first.places, second.places), items = items,
    currencies = mergeCurrencies(a.currencies, b.currencies), zones = mergeZones(a.zones, b.zones),
  }
  local older, newer = a, b
  if b.startedAt < a.startedAt then older, newer = b, a end
  local notes = {}
  for _, e in ipairs({ older, newer }) do
    local note = History.note(e)
    if note and note ~= notes[1] then notes[#notes + 1] = note end
  end
  if #notes > 0 then History.setNote(merged, table.concat(notes, " / ")) end
  return merged
end

-- The account-wide History table (`histories` = { [character] = list }) takes
-- over the character's own list `own` (LootLedgerCharDB.history) at login:
-- entries not yet in histories[name] (same start) are added. Returns the
-- character's list in `histories`.
function History.adopt(histories, name, own)
  local list = histories[name]
  if type(list) ~= "table" then
    list = {}
    histories[name] = list
  end
  if type(own) == "table" and own ~= list and #own > 0 then
    local seen = {}
    for _, e in ipairs(list) do
      if type(e) == "table" then seen[tostring(e.startedAt)] = true end
    end
    for _, e in ipairs(own) do
      if type(e) == "table" and not seen[tostring(e.startedAt)] then list[#list + 1] = e end
    end
    table.sort(list, newerFirst)
  end
  return list
end

-- Every list of `histories` ({ [character] = list }) in one list, by character
-- name, plus a key that changes when any list does (its table, length or
-- newest session): History Zones and the Daily farm across characters.
function History.combine(histories)
  local names = {}
  for name, list in pairs(histories) do
    if type(list) == "table" then names[#names + 1] = tostring(name) end
  end
  table.sort(names)
  local out, key = {}, {}
  for _, name in ipairs(names) do
    local list = histories[name]
    for _, e in ipairs(list) do out[#out + 1] = e end
    local first = list[1]
    key[#key + 1] = name .. "=" .. tostring(list) .. "#" .. #list .. "@"
      .. tostring(type(first) == "table" and first.startedAt)
  end
  return out, table.concat(key, ";")
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
-- `ignored`: the ignore list (History.totals).
function History.details(e, formatDate, ignored)
  local Tip = ns.Tooltip
  local when = formatDate and formatDate(e.startedAt) or tostring(e.startedAt)
  local tip = Tip.new(when)
  local vendor, ah, best, count = History.totals(e, ignored)
  Tip.note(tip, History.duration(e.elapsed) .. ", " .. History.itemCount(count))
  local note = History.note(e)
  if note then Tip.labelled(tip, L_NOTE, note) end
  if type(e.places) == "table" and #e.places > 0 then
    Tip.labelled(tip, L_PLACES, table.concat(e.places, ", "))
  end
  local currencies = History.currencyText(e)
  if currencies then Tip.labelled(tip, L_CURRENCIES, currencies) end
  local function money(label, amount, source)
    Tip.money(tip, label, amount, History.perHour(amount, e.elapsed), source)
  end
  money(L_VENDOR, vendor, "vendor")
  money(L_AH, ah, "ah")
  money(L_BEST, best)
  money(L_GOLD, e.gold)
  return tip
end

-- ---------------------------------------------------------------------------
-- CSV export

History.CSV_HEADER = "start,duration_min,place,items,vendor_g,ah_g,best_g,raw_gold_g,best_plus_gold_per_hour_g,currencies,note"

-- One CSV field: quoted when it holds a comma, quote or line break.
function History.csvField(text)
  text = tostring(text or "")
  if text:find('[,"\n]') then text = '"' .. text:gsub('"', '""') .. '"' end
  return text
end
local csvField = History.csvField

-- Copper as gold with four decimals, so a spreadsheet can sum it.
function History.goldNumber(copper)
  return string.format("%.4f", (copper or 0) / 10000)
end
local goldNumber = History.goldNumber

-- The History list as CSV text (header first, newest session first). Amounts
-- are in gold with four decimals so a spreadsheet can sum them; items on the
-- ignore list (`ignored`) are left out like in the window.
function History.csv(list, formatDate, ignored)
  local out = { History.CSV_HEADER }
  if type(list) ~= "table" then list = {} end
  for _, e in ipairs(list) do
    if History.valid(e) then
      local vendor, ah, best, count = History.totals(e, ignored)
      local rate = History.perHour(best + e.gold, e.elapsed)
      out[#out + 1] = table.concat({
        csvField(formatDate and formatDate(e.startedAt) or e.startedAt),
        string.format("%.1f", e.elapsed / 60),
        csvField(type(e.places) == "table" and table.concat(e.places, "; ") or ""),
        tostring(count),
        goldNumber(vendor), goldNumber(ah), goldNumber(best), goldNumber(e.gold),
        rate and goldNumber(rate) or "",
        csvField(History.currencyText(e, "; ") or ""),
        csvField(History.note(e) or ""),
      }, ",")
    end
  end
  return table.concat(out, "\n")
end

ns.History = History
