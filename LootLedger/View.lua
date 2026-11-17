local ADDON, ns = ...

local L = ns.L

local num = ns.Util.isNumber
local lower = string.lower

-- Pure ledger view: turns a session plus injected lookups into filtered,
-- sorted rows, top finds and totals. No WoW globals.
--
-- opts = {
--   now      = timestamp,
--   filter   = { qualities = { [0..7] = bool }, minValue = copper, search = text },
--   sort     = key of SORTS,
--   lookup   = function(itemID, link) -> Prices lookup result or nil,
--   itemInfo = function(itemID, link) -> { name, quality, bound } or nil,
--   currencyInfo = function(currencyID) -> { name, icon, quality } or nil,
--   showCurrencies = bool (default true),
--   includeGold = bool (default true),
--   formatDate = function(timestamp) -> text (History tab: tooltips),
--   shortDate = function(timestamp) -> text (History tab: the session rows;
--     formatDate without it),
--   isQuest  = function(itemID) -> bool (History Zones: the quest items group),
--   market = { rateGood, rateOk, soldHigh, soldMedium } or nil (no sale info),
--   ignored = { [itemID] = name or true } (the ignore list: these items are
--     left out of every list and total),
--   goal = copper or nil (the session goal: Session tab and compact progress),
--   kept = { [itemID] = name or true } (the keep list: Bags and Bank mark
--     these rows and split their total into kept and sellable),
-- }
--
-- A row's value is the best of its vendor, AH and disenchant totals; the sort
-- "AH value", Top finds, the minimum value filter and the alerts use it.
local View = {
  TOP_COUNT = 3,
  MIN_RATE_SECONDS = 60,
  STRONG_FLASH_VALUE = 100000,
  CURRENCY_KEY_PREFIX = "c:",
  -- The footer tooltip lists at most this many unpriced items by name.
  UNPRICED_NAMES = 10,
}

local MIN_QUALITY, MAX_QUALITY = 0, 7
local NO_LOOKUP = {}
local DETAIL_SEP = " \194\183 " -- middle dot between the parts of a row's second line

local L_CLICK_OPEN = L["Click to show the items"]
local L_CLICK_CLOSE = L["Click to collapse"]
local L_RIGHT_MENU = L["Right-click: note, merge or delete"]
local L_PER_HOUR = L["/h"]
local L_NO_MATCH = L["Nothing matches the filters. The x next to Sort clears them."]
local L_STOPPED = L["The clock is stopped: loot is not counted. Press Start."]
local L_NO_LOOT = L["No loot yet."]
local L_NO_HISTORY = L["No saved sessions yet. A session is saved when you reset it."]

-- A tooltip (ns.Tooltip) with its click hint added at the bottom.
local function withHint(tip, text)
  ns.Tooltip.hint(tip, text)
  return tip
end

-- `target` emptied and filled with the fields of `opts` (a reused table: no
-- garbage per redraw); the caller then changes what differs.
local function copyOpts(target, opts)
  for k in pairs(target) do target[k] = nil end
  for k, v in pairs(opts) do target[k] = v end
  return target
end

-- The second line of a History or Zones row: its parts joined by a dot.
local function detailText(parts)
  return table.concat(parts, DETAIL_SEP)
end

-- What an empty list says (view.empty): a filter hides everything, else
-- `fallback` (the tab's own reason).
function View.emptyText(rows, filter, fallback)
  if #rows > 0 then return nil end
  if View.isFiltered(filter) then return L_NO_MATCH end
  return fallback
end

local function allQualities(set)
  for q = MIN_QUALITY, MAX_QUALITY do
    if not set[q] then return false end
  end
  return true
end

function View.isFiltered(filter)
  if type(filter) ~= "table" then return false end
  if num(filter.minValue) and filter.minValue > 0 then return true end
  if type(filter.search) == "string" and filter.search ~= "" then return true end
  if type(filter.qualities) == "table" and not allQualities(filter.qualities) then return true end
  return false
end

-- The best of the three totals and which one it is ("vendor", "ah", "de").
-- Ties prefer vendor, then AH (the surest money).
-- `minGain`: the option Auction from (Prices.best).
function View.best(vendorTotal, ahTotal, deTotal, minGain)
  return ns.Prices.best(vendorTotal, ahTotal, deTotal, minGain)
end

-- How well an item sells, from TSM region data. `t` = { rateGood, rateOk,
-- soldHigh, soldMedium } (a negative cutoff is never reached). Returns the
-- sale rate level ("good" / "ok" / "bad") and the volume level ("high" /
-- "medium" / "low"); each is nil when its value is unknown or `t` is missing.
-- The options keep the middle cutoff at or below the top one (Options.lua).
local function level(v, top, mid, names)
  if not num(v) then return nil end
  if num(top) and top >= 0 and v >= top then return names[1] end
  if num(mid) and mid >= 0 and v >= mid then return names[2] end
  return names[3]
end
local RATE_LEVELS, VOLUME_LEVELS = { "good", "ok", "bad" }, { "high", "medium", "low" }

function View.marketLevels(saleRate, soldPerDay, t)
  if type(t) ~= "table" then return nil, nil end
  return level(saleRate, t.rateGood, t.rateOk, RATE_LEVELS),
    level(soldPerDay, t.soldHigh, t.soldMedium, VOLUME_LEVELS)
end

-- ---------------------------------------------------------------------------
-- Rows

-- One ledger row for an item ({ id, key, link, qty, lastSeen, price }).
-- `item.price` (unit prices seen at loot time) fills in what the live lookup
-- does not know; an AH price from there shows its age like a cached one.
local function makeRow(item, opts)
  local lookup = opts.lookup and opts.lookup(item.id, item.link)
  if type(lookup) ~= "table" then lookup = NO_LOOKUP end
  local info = opts.itemInfo and opts.itemInfo(item.id, item.link)
  if type(info) ~= "table" then info = nil end
  local saved = type(item.price) == "table" and item.price or NO_LOOKUP

  local name = info and type(info.name) == "string" and info.name or nil
  if not name then name = type(item.link) == "string" and item.link:match("%[(.-)%]") or "" end
  local quality = info and num(info.quality) and info.quality or 1

  local qty = item.qty
  local vendorEach, ahEach, deEach, ahFromCache, ahAge
  -- Whether ahEach is after the 5% fee (option "ahCut"): a live lookup says so
  -- with ahGross, a saved History price by its entry (opts.savedAhCut).
  local ahCut = false
  if opts.savedPrices then
    -- An opened History session: the prices it was saved with (its row's
    -- totals), live ones only for what it has none of. No age tag.
    vendorEach = num(saved.vendor) and saved.vendor or (num(lookup.vendor) and lookup.vendor or nil)
    deEach = num(saved.de) and saved.de or (num(lookup.de) and lookup.de or nil)
    if num(saved.ah) then
      ahEach, ahFromCache = saved.ah, false
      ahCut = opts.savedAhCut == true
    elseif num(lookup.ah) then
      ahEach, ahFromCache = lookup.ah, lookup.ahSource == "cache"
      ahAge = num(lookup.ahAge) and lookup.ahAge or nil
      ahCut = num(lookup.ahGross)
    end
  else
    vendorEach = num(lookup.vendor) and lookup.vendor or (num(saved.vendor) and saved.vendor or nil)
    ahEach = num(lookup.ah) and lookup.ah or nil
    ahCut = ahEach ~= nil and num(lookup.ahGross)
    ahFromCache = lookup.ahSource == "cache"
    ahAge = num(lookup.ahAge) and lookup.ahAge or nil
    if not ahEach and num(saved.ah) then
      ahEach, ahFromCache = saved.ah, true
      ahAge = num(item.lastSeen) and num(opts.now) and math.max(0, opts.now - item.lastSeen) or nil
    end
    -- The destroy rule (lookup.deBlocked) also drops the loot-time value.
    deEach = num(lookup.de) and lookup.de or (not lookup.deBlocked and num(saved.de) and saved.de or nil)
  end
  local vendorTotal = vendorEach and vendorEach * qty or nil
  local ahTotal = ahEach and ahEach * qty or nil
  local deTotal = deEach and deEach * qty or nil
  local bestTotal, bestKind = View.best(vendorTotal, ahTotal, deTotal, opts.ahMinGain)
  local rateLevel, volumeLevel = View.marketLevels(lookup.saleRate, lookup.soldPerDay, opts.market)

  return {
    rateLevel = rateLevel, volumeLevel = volumeLevel,
    id = item.id, key = item.key or item.id, link = item.link, name = name, quality = quality, quantity = qty,
    sortName = lower(name), -- lowercased once, for the search and the name sort
    vendorEach = vendorEach, vendorTotal = vendorTotal,
    ahEach = ahEach, ahTotal = ahTotal,
    deEach = deEach, deTotal = deTotal,
    bestTotal = bestTotal, bestKind = bestKind,
    -- Bound items can never be sold on the AH: no "unpriced" count for them.
    bound = info and info.bound and true or false,
    ahFromCache = ahFromCache, ahAge = ahAge,
    ahCut = ahCut and true or false,
    stale = ahFromCache and ahAge ~= nil and ns.Prices.isStale(ahAge) or false,
    value = bestTotal or 0,
    lastSeen = item.lastSeen,
  }
end

-- `needle` is the lowercased search text, or nil.
local function visible(row, filter, needle)
  if type(filter) ~= "table" then return true end
  if type(filter.qualities) == "table" and not filter.qualities[row.quality] then return false end
  if num(filter.minValue) and row.value < filter.minValue then return false end
  if needle and not string.find(row.sortName, needle, 1, true) then return false end
  return true
end

local function searchNeedle(filter)
  if type(filter) == "table" and type(filter.search) == "string" and filter.search ~= "" then
    return lower(filter.search)
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Sorting: every order is total (ties by name, then key), so it is stable
-- across refreshes.

local function byName(a, b)
  local an, bn = a.sortName, b.sortName
  if an ~= bn then return an < bn end
  return tostring(a.key or a.id) < tostring(b.key or b.id)
end

-- Descending by row[field] (missing = 0), ties by name then key.
local function descending(field)
  return function(a, b)
    local ka, kb = a[field] or 0, b[field] or 0
    if ka ~= kb then return ka > kb end
    return byName(a, b)
  end
end

-- A new sort order is one entry here plus its label in UI/FilterBar.lua.
-- "ah" keeps its saved key but sorts by the best value.
-- "perHour" (History Zones only): places by gold per hour, places without
-- recorded time last; item rows sort by value under it.
local SORTS = {
  ah = descending("value"),
  vendor = descending("vendorTotal"),
  recent = descending("lastSeen"),
  name = byName,
  perHour = function(a, b)
    local ka, kb = a.perHour, b.perHour
    if ka ~= kb then
      if ka == nil then return false end
      if kb == nil then return true end
      return ka > kb
    end
    return byName(a, b)
  end,
}

local byValue = descending("value")

-- The `count` most valuable rows (value > 0), best first. One pass with a tiny
-- insertion list instead of sorting a copy of every row.
local function topRows(rows, count)
  local top = {}
  for _, row in ipairs(rows) do
    if row.value > 0 and not row.isCurrency then
      local pos = #top + 1
      while pos > 1 and byValue(row, top[pos - 1]) do pos = pos - 1 end
      if pos <= count then
        table.insert(top, pos, row)
        top[count + 1] = nil
      end
    end
  end
  return top
end

-- Filtered, sorted rows and their vendor / AH / best totals for an items map
-- ({ [key] = { id, key, link, qty, lastSeen } }); shared by the session and the
-- inventory tabs.
local function ignoredSet(opts)
  return type(opts.ignored) == "table" and opts.ignored or NO_LOOKUP
end

local function collect(items, opts)
  local filter = opts.filter
  local needle = searchNeedle(filter)
  local ignored = ignoredSet(opts)

  local rows, n = {}, 0
  local vendor, ah, best, unpriced = 0, 0, 0, 0
  local unpricedNames = {}
  if type(items) ~= "table" then items = {} end
  for _, item in pairs(items) do
    if type(item) == "table" and num(item.id) and num(item.qty) and item.qty > 0 and not ignored[item.id] then
      local row = makeRow(item, opts)
      if visible(row, filter, needle) then
        n = n + 1
        rows[n] = row
        vendor = vendor + (row.vendorTotal or 0)
        ah = ah + (row.ahTotal or 0)
        best = best + (row.bestTotal or 0)
        if row.ahEach == nil and not row.bound then
          unpriced = unpriced + 1
          if #unpricedNames < View.UNPRICED_NAMES then
            unpricedNames[#unpricedNames + 1] = row.name .. " x" .. row.quantity
          end
        end
      end
    end
  end
  table.sort(rows, opts.sort ~= "perHour" and SORTS[opts.sort] or SORTS.ah)

  return rows, { vendor = vendor, ah = ah, best = best, unpriced = unpriced,
    unpricedNames = unpriced > 0 and unpricedNames or nil, filtered = View.isFiltered(filter) }
end

-- Currency rows ({ [currencyID] = { id, link, qty } }): quantity only, no
-- value, listed after the items by name. The search and quality filters apply;
-- a minimum value hides them (they are worth nothing in gold).
function View.currencyRows(currencies, opts)
  local rows = {}
  if type(currencies) ~= "table" or opts.showCurrencies == false then return rows end
  local filter = opts.filter
  local needle = searchNeedle(filter)
  for _, c in pairs(currencies) do
    if type(c) == "table" and num(c.id) and num(c.qty) and c.qty > 0 then
      local info = opts.currencyInfo and opts.currencyInfo(c.id)
      if type(info) ~= "table" then info = {} end
      local name = type(info.name) == "string" and info.name
        or (type(c.link) == "string" and c.link:match("%[(.-)%]")) or (L["Currency "] .. c.id)
      local row = {
        id = c.id, key = View.CURRENCY_KEY_PREFIX .. c.id, link = c.link, isCurrency = true,
        name = name, sortName = lower(name), quality = num(info.quality) and info.quality or 1,
        quantity = c.qty, icon = info.icon, value = 0, lastSeen = c.lastSeen,
      }
      if visible(row, filter, needle) then rows[#rows + 1] = row end
    end
  end
  table.sort(rows, byName)
  return rows
end

local function append(rows, more)
  for _, r in ipairs(more) do rows[#rows + 1] = r end
  return rows
end

-- ---------------------------------------------------------------------------
-- Views

-- Inventory tabs (bags, bank): rows and totals only, no clock, rates, raw gold
-- or top finds. Items on the keep list (opts.kept) are marked (row.kept);
-- totals.kept is their best value and totals.sellable the rest, both only
-- while a listed row is kept.
function View.buildInventory(items, opts)
  local rows, totals = collect(items, opts)
  local kept = type(opts.kept) == "table" and opts.kept or NO_LOOKUP
  local keptValue, any = 0, false
  -- What selling everything not kept brings, by the way each row is valued.
  local split = { vendor = 0, ah = 0, de = 0 }
  for _, row in ipairs(rows) do
    if kept[row.id] then
      row.kept, any = true, true
      keptValue = keptValue + (row.bestTotal or 0)
    elseif split[row.bestKind] and num(row.bestTotal) then
      split[row.bestKind] = split[row.bestKind] + row.bestTotal
    end
  end
  if any then totals.kept, totals.sellable = keptValue, totals.best - keptValue end
  totals.sellSplit = split
  return { rows = rows, top = {}, totals = totals, kind = "inventory", empty = View.emptyText(rows, opts.filter),
    -- The header's info text (right of the title): how many items are listed.
    headerInfo = #rows > 0 and ns.History.itemCount(#rows) or nil }
end

-- Bags: the character's gold (`money`, copper) and the net worth (the bag
-- items' best value plus that gold).
function View.addWorth(view, money)
  if not num(money) then return view end
  view.totals.money = money
  view.totals.worth = (view.totals.best or 0) + money
  return view
end

local function perHour(amount, elapsed)
  return amount * 3600 / elapsed
end

-- Sets (or clears, while the session is younger than MIN_RATE_SECONDS) the
-- per-hour rates of a session view in place. Cheap: the clock tick calls it
-- every second without rebuilding the rows.
function View.applyRates(view, elapsed)
  local totals, gold, combined = view.totals, view.gold, view.combined
  if num(elapsed) and elapsed >= View.MIN_RATE_SECONDS then
    totals.vendorPerHour = perHour(totals.vendor, elapsed)
    totals.ahPerHour = perHour(totals.ah, elapsed)
    totals.bestPerHour = perHour(totals.best or 0, elapsed)
    gold.perHour = perHour(gold.total, elapsed)
    combined.vendorPerHour = perHour(combined.vendor, elapsed)
    combined.ahPerHour = perHour(combined.ah, elapsed)
    combined.bestPerHour = perHour(combined.best or 0, elapsed)
  else
    totals.vendorPerHour, totals.ahPerHour, totals.bestPerHour = nil, nil, nil
    gold.perHour = nil
    combined.vendorPerHour, combined.ahPerHour, combined.bestPerHour = nil, nil, nil
  end
  return view
end

-- Gold and the combined (items + gold) totals of a view. Option "includeGold"
-- off: the combined totals are only the items, and the footer leaves the block
-- out.
local function addGold(view, goldTotal, includeGold)
  local totals = view.totals
  view.gold = { total = goldTotal }
  if includeGold == false then
    view.combined = { vendor = totals.vendor, ah = totals.ah, best = totals.best }
    view.noCombined = true
  else
    view.combined = { vendor = totals.vendor + goldTotal, ah = totals.ah + goldTotal,
      best = totals.best + goldTotal }
  end
  return view
end

local savedOpts = {} -- opts of an opened History session (reused)
local savedFilter = {} -- its filter: the qualities only (reused)

-- The sorts of the session list (UI/Tabs.lua offers these); any other sort
-- works as "ah".
local SESSION_SORT = { ah = SORTS.ah, recent = SORTS.recent, perHour = SORTS.perHour }

-- One History session row. Line 1: the start and the note ("+ Today 20:21 ·
-- Wingrest herbs"); line 2 (`detail`): length, item count and main place. Its
-- amount is the best value of the items (without ignored ones) plus, with
-- includeGold, the raw gold. The tooltip is built on hover (a function,
-- ns.Tooltip.resolve). `totals` = { vendor, ah, best } of History.totals.
local function sessionRow(e, i, open, opts, totals)
  local History = ns.History
  local dateFn = opts.shortDate or opts.formatDate
  local when = dateFn and dateFn(e.startedAt) or tostring(e.startedAt)
  local value = totals.best + (opts.includeGold ~= false and e.gold or 0)
  -- The place last: a narrow window cuts the line at its end, and a long
  -- place name may lose its tail, the item count never.
  local parts = { History.duration(e.elapsed), History.itemCount(totals.count) }
  local place = History.place(e)
  if place then parts[#parts + 1] = place end
  local note = History.note(e)
  local label = note and (when .. DETAIL_SEP .. note) or when
  local detail = detailText(parts)
  local formatDate, ignored = opts.formatDate, opts.ignored
  return {
    id = -i, key = -i, historyIndex = i, entry = e,
    name = (open and "- " or "+ ") .. label, detail = detail, sortName = lower(label .. " " .. detail),
    quality = 1,
    vendorTotal = totals.vendor, ahTotal = totals.ah, bestLineTotal = value,
    perHour = History.perHour(value, e.elapsed),
    icon = "Interface\\Icons\\INV_Misc_Note_01",
    hint = function()
      local tip = History.details(e, formatDate, ignored)
      return withHint(withHint(tip, open and L_CLICK_CLOSE or L_CLICK_OPEN), L_RIGHT_MENU)
    end,
    value = value, lastSeen = e.startedAt,
  }
end

local L_SESSIONS_FOLD = L["Click to fold or unfold these sessions"]
local CALENDAR_ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"

-- Sorted by Recent: a heading per day (this week) or ISO week (older) over its
-- sessions, with their count, length and value. A folded period
-- (`opts.folded[periodKey]`) keeps its heading and hides its sessions. The
-- opened session sits above every heading and counts in none.
local function appendPeriods(rows, sessionRows, opened, opts)
  local History = ns.History
  local folded = type(opts.folded) == "table" and opts.folded or NO_LOOKUP
  local heading, members
  local function close()
    if not heading then return end
    heading.detail = History.sessionCount(heading.count) .. DETAIL_SEP .. History.duration(heading.elapsed)
    heading.perHour = History.perHour(heading.value, heading.elapsed)
    heading.bestLineTotal = heading.value
    rows[#rows + 1] = heading
    if not folded[heading.periodKey] then append(rows, members) end
  end
  for _, r in ipairs(sessionRows) do
    if r ~= opened then
      local key, label = History.period(r.entry.startedAt, opts.now, opts.dateFn)
      if not heading or heading.periodKey ~= key then
        close()
        heading = { id = 0, key = "p:" .. key, periodKey = key, isHeading = true, name = label,
          sortName = lower(label), quality = 1, count = 0, elapsed = 0, value = 0,
          icon = CALENDAR_ICON, hint = L_SESSIONS_FOLD }
        members = {}
      end
      heading.count = heading.count + 1
      heading.elapsed = heading.elapsed + r.entry.elapsed
      heading.value = heading.value + (r.value or 0)
      members[#members + 1] = r
    end
  end
  close()
end

-- History tab: one row per archived session (newest first, or in the order
-- of a session sort). The search and the minimum value pick sessions (the
-- search looks at the start, length and place). The session at `openIndex`
-- (if any) always shows, moves to the top and lists its items (and
-- currencies) under it, filtered by quality and sorted by the item sort.
-- The totals add up the listed sessions, with rates over their summed length;
-- the header says how many sessions that is (view.headerInfo).
function View.buildHistory(list, opts, openIndex)
  opts = opts or {}
  if type(list) ~= "table" then list = {} end
  local History = ns.History
  local filter = opts.filter
  local needle = searchNeedle(filter)
  local minValue = type(filter) == "table" and num(filter.minValue) and filter.minValue or 0
  local sessionRows, opened = {}, nil
  local totals = { vendor = 0, ah = 0, best = 0, unpriced = 0, filtered = View.isFiltered(filter) }
  local gold, elapsed = 0, 0
  local t = {}
  for i, e in ipairs(list) do
    if History.valid(e) then
      local open = i == openIndex
      t.vendor, t.ah, t.best, t.count = History.totals(e, opts.ignored)
      local row = sessionRow(e, i, open, opts, t)
      local shown = open or (row.value >= minValue
        and (not needle or string.find(row.sortName, needle, 1, true) ~= nil))
      if shown then
        sessionRows[#sessionRows + 1] = row
        if open then opened = row end
        totals.vendor = totals.vendor + t.vendor
        totals.ah = totals.ah + t.ah
        totals.best = totals.best + t.best
        gold = gold + e.gold
        elapsed = elapsed + e.elapsed
      end
    end
  end
  if opts.sort then table.sort(sessionRows, SESSION_SORT[opts.sort] or SESSION_SORT.ah) end

  local rows = {}
  if opened then
    rows[1] = opened
    local entry = list[openIndex]
    local o = copyOpts(savedOpts, opts)
    o.savedPrices = true
    -- Its items at the rules it was saved with, so they add up to its row.
    o.ahMinGain = History.gainOf(entry)
    o.savedAhCut = entry.ahCut == true
    savedFilter.qualities = type(filter) == "table" and filter.qualities or nil
    o.filter = savedFilter
    append(rows, (collect(entry.items, o)))
    append(rows, View.currencyRows(entry.currencies, o))
  end
  if opts.sort == "recent" and type(opts.dateFn) == "function" and num(opts.now) then
    appendPeriods(rows, sessionRows, opened, opts)
  else
    for _, r in ipairs(sessionRows) do
      if r ~= opened then rows[#rows + 1] = r end
    end
  end
  local view = { rows = rows, top = {}, totals = totals, kind = "history", history = true,
    empty = View.emptyText(rows, filter, L_NO_HISTORY),
    headerInfo = #sessionRows > 0 and History.sessionCount(#sessionRows) or nil }
  addGold(view, gold, opts.includeGold)
  return View.applyRates(view, elapsed)
end

-- ---------------------------------------------------------------------------
-- History Zones: the loot of all saved sessions (plus the running one) per
-- zone -> subzone -> items, with time, value and gold per hour per place.

View.QUEST_ZONE = "\1quest"     -- quest items, outside every place and total
View.NO_TIME_SUB = "\1notime"   -- old loot without recorded time
View.UNKNOWN_ZONE = "?"         -- = Session.UNKNOWN_PLACE

local L_QUEST_ITEMS = L["Quest items"]
local L_NO_TIME = L["No time recorded"]
local L_UNKNOWN_PLACE = L["Unknown place"]
local L_CLICK_SUBZONES = L["Click to show the subzones"]
local L_TIME = L["Time: "]
local L_VALUE = L["Value: "]
local L_RAW_GOLD = L["Raw gold: "]
local L_GOLD_PER_HOUR = L["Gold per hour: "]
local MAP_ICON = "Interface\\Icons\\INV_Misc_Map_01"

local function placeLabel(key)
  if key == View.QUEST_ZONE then return L_QUEST_ITEMS end
  if key == View.NO_TIME_SUB then return L_NO_TIME end
  if key == View.UNKNOWN_ZONE then return L_UNKNOWN_PLACE end
  return key
end

local function placePerHour(value, seconds) return ns.History.perHour(value, seconds) end

local function newSlot() return { time = 0, gold = 0, items = {}, pos = {} } end

-- Adds the valid position sums of `src` ({ [mapID] = { x, y, n } }) to `dst`.
local function addPos(dst, src)
  local copy = ns.Session and ns.Session.copyPos and ns.Session.copyPos(src)
  if not copy then return end
  for mapID, p in pairs(copy) do
    local d = dst[mapID]
    if not d then d = { x = 0, y = 0, n = 0 }; dst[mapID] = d end
    d.x, d.y, d.n = d.x + p.x, d.y + p.y, d.n + p.n
  end
end

-- The averaged spot on the map with the most loot events (ties: lower map ID),
-- { mapID, x, y }, or nil.
local function spotOf(pos)
  local bestID, best
  for mapID, p in pairs(pos or {}) do
    if p.n > 0 and (not best or p.n > best.n or (p.n == best.n and mapID < bestID)) then
      bestID, best = mapID, p
    end
  end
  if not best then return nil end
  -- Corrupt saved sums must not put the waypoint off the map.
  local function clamp(v) return math.max(0, math.min(1, v)) end
  return { mapID = bestID, x = clamp(best.x / best.n), y = clamp(best.y / best.n) }
end

-- Adds `qty` of the entry item `src` under `key` to an items map.
local function addZoneItem(map, src, key, qty)
  local it = map[key]
  if not it then
    it = { id = src.id, key = key, link = src.link, price = src.price, qty = 0, lastSeen = src.lastSeen }
    map[key] = it
  elseif num(src.lastSeen) and (not num(it.lastSeen) or src.lastSeen > it.lastSeen) then
    it.lastSeen = src.lastSeen
    if type(src.link) == "string" then it.link = src.link end
    if src.price then it.price = src.price end
  end
  it.qty = it.qty + qty
end

-- Where the loot of an entry without per-place data goes: its only place,
-- else Unknown place; never with time.
-- History entries store places as a list (most loot first); the running
-- session as a map { [label] = loot events }.
local function fallbackZone(e)
  local places = e.places
  if type(places) ~= "table" then return View.UNKNOWN_ZONE end
  local list = places
  if places[1] == nil and ns.Session and ns.Session.placeList then list = ns.Session.placeList(places) end
  if #list == 1 and type(list[1]) == "string" then return list[1] end
  return View.UNKNOWN_ZONE
end

-- { [zone] = { [sub] = slot } } and the quest items map of all entries.
local function aggregateZones(entries, isQuest)
  local zones, quest = {}, {}
  local function slot(zone, sub)
    local z = zones[zone]
    if not z then z = {}; zones[zone] = z end
    local s = z[sub]
    if not s then s = newSlot(); z[sub] = s end
    return s
  end
  local function put(s, src, key, qty)
    if isQuest and isQuest(src.id) then
      addZoneItem(quest, src, key, qty)
    else
      addZoneItem(s.items, src, key, qty)
    end
  end
  for _, e in ipairs(entries) do
    if type(e) == "table" and (e.live or ns.History.valid(e)) and type(e.items) == "table" then
      local placed, placedGold = {}, 0
      if type(e.zones) == "table" then
        for zone, z in pairs(e.zones) do
          if type(z) == "table" and type(z.subs) == "table" then
            for sub, src in pairs(z.subs) do
              if type(src) == "table" then
                local s = slot(zone, sub)
                if num(src.time) and src.time > 0 then s.time = s.time + src.time end
                addPos(s.pos, src.pos)
                if num(src.gold) and src.gold > 0 then
                  s.gold = s.gold + src.gold
                  placedGold = placedGold + src.gold
                end
                if type(src.items) == "table" then
                  for key, qty in pairs(src.items) do
                    local it = e.items[key]
                    if type(it) == "table" and num(it.id) and num(qty) and qty > 0 then
                      put(s, it, key, qty)
                      placed[key] = (placed[key] or 0) + qty
                    end
                  end
                end
              end
            end
          end
        end
      end
      -- Loot without a place (old sessions, or looted before places were kept).
      local rest
      for key, it in pairs(e.items) do
        if type(it) == "table" and num(it.id) and num(it.qty) then
          local qty = it.qty - (placed[key] or 0)
          if qty > 0 then
            rest = rest or slot(fallbackZone(e), View.NO_TIME_SUB)
            put(rest, it, key, qty)
          end
        end
      end
      local gold = (num(e.gold) and e.gold or 0) - placedGold
      if gold > 0 then
        rest = rest or slot(fallbackZone(e), View.NO_TIME_SUB)
        rest.gold = rest.gold + gold
      end
    end
  end
  return zones, quest
end

-- Short forms of the instance difficulties (English and German names; the
-- game's texts). Anything else keeps its first letter.
local DIFFICULTY_SHORT = {
  normal = "N", heroic = "H", heroisch = "H", mythic = "M", mythisch = "M",
}

-- A place label for a row: "Instance (Difficulty)" with the difficulty
-- shortened ("Razorfen Downs (N)"), so a narrow row cuts the name, not the
-- difficulty. The tooltip keeps the full label.
function View.shortPlace(label)
  if type(label) ~= "string" then return label end
  local name, difficulty = label:match("^(.-) %(([^()]+)%)$")
  if not name then return label end
  local d = lower(difficulty)
  local short
  if d:find("keystone", 1, true) or d:find("schl\195\188sselstein", 1, true) or d:find("+", 1, true) then
    short = "M+"
  else
    -- The first character (UTF-8 safe).
    short = DIFFICULTY_SHORT[d] or difficulty:match("^[\1-\127\194-\244][\128-\191]*")
  end
  return name .. " (" .. short .. ")"
end

-- A place row's tooltip (ns.Tooltip): its name, time, value, raw gold, gold
-- per hour and the click.
local function placeHint(p, label, open, clickText)
  local Tip = ns.Tooltip
  local tip = Tip.new(label)
  if p.time > 0 then Tip.pair(tip, L_TIME, ns.History.duration(p.time)) end
  Tip.money(tip, L_VALUE, p.value)
  if p.gold > 0 then Tip.money(tip, L_RAW_GOLD, p.gold) end
  if p.perHour then
    Tip.rate(tip, L_GOLD_PER_HOUR, p.perHour)
  elseif p.time == 0 and p.zoneKey ~= View.QUEST_ZONE then
    Tip.note(tip, L_NO_TIME)
  end
  Tip.hint(tip, open and L_CLICK_CLOSE or clickText)
  return tip
end

-- One place row (zone, subzone or the quest group) from its summed figures.
-- Line 1: the name; line 2 (`detail`): time, gold per hour and item count.
-- The tooltip is built on hover. `last`: the row sorts after the others
-- (Unknown place, No time recorded).
local function placeRow(p, label, open, indent, clickText, last)
  local parts = {}
  if p.time > 0 then parts[#parts + 1] = ns.History.duration(p.time) end
  if p.perHour then parts[#parts + 1] = ns.Money.format(ns.Money.roundRate(p.perHour)) .. L_PER_HOUR end
  parts[#parts + 1] = ns.History.itemCount(p.count)
  return {
    id = 0, key = p.key, zoneKey = p.zoneKey, subKey = p.subKey,
    name = indent .. (open and "- " or "+ ") .. View.shortPlace(label), detail = indent .. detailText(parts),
    sortName = lower(label), quality = 1, sortsLast = last or false,
    vendorTotal = p.vendor, ahTotal = p.ah, bestLineTotal = p.value,
    value = p.value, perHour = p.perHour, placeTime = p.time, lastSeen = p.lastSeen,
    icon = MAP_ICON, hint = function() return placeHint(p, label, open, clickText) end,
  }
end

-- The place sorts: rows marked sortsLast after the others, then the chosen
-- order. Built once per sort key.
local placeSorts = {}
local function placeSort(key)
  key = SORTS[key] and key or "ah"
  local s = placeSorts[key]
  if not s then
    local inner = SORTS[key]
    s = function(a, b)
      if a.sortsLast ~= b.sortsLast then return b.sortsLast end
      return inner(a, b)
    end
    placeSorts[key] = s
  end
  return s
end

local function maxSeen(rows)
  local seen
  for _, r in ipairs(rows) do
    if num(r.lastSeen) and (not seen or r.lastSeen > seen) then seen = r.lastSeen end
  end
  return seen
end

-- `entries` = History entries plus, optionally, the running session as
-- { live = true, items, zones = Session.zoneSnapshot(...), places, gold }.
-- `open` = { zone, sub }: the opened zone lists its subzones, the opened subzone
-- its items. opts.isQuest(itemID) -> bool moves an item to the quest group.
-- Time spent counts whether or not the filter hides a place's loot: a zone's
-- time (and the footer's rates) include its subzones without listed loot.
function View.buildZones(entries, opts, open)
  opts = opts or {}
  open = open or {}
  if type(entries) ~= "table" then entries = {} end
  local withGold = opts.includeGold ~= false
  local sort = placeSort(opts.sort)
  local pick = type(opts.dailyPick) == "table" and opts.dailyPick or NO_LOOKUP
  local unpricedNames = {}
  local zones, quest = aggregateZones(entries, opts.isQuest)
  local totals = { vendor = 0, ah = 0, best = 0, unpriced = 0, filtered = View.isFiltered(opts.filter) }
  local goldSum, timeSum = 0, 0

  local zoneRows, opened = {}, nil
  for zone, subs in pairs(zones) do
    local zp = { key = "z:" .. zone, zoneKey = zone, time = 0, gold = 0, value = 0, vendor = 0, ah = 0,
      count = 0, timedValue = 0 }
    local subRows, subItems = {}, {}
    for sub, s in pairs(subs) do
      local items, t = collect(s.items, opts)
      local gold = withGold and s.gold or 0
      zp.time, timeSum = zp.time + s.time, timeSum + s.time
      -- The opened subzone stays listed when the filter hides all its items
      -- (the Daily farm click opens it).
      local isOpen = open.zone == zone and open.sub == sub
      if #items > 0 or gold > 0 or isOpen then
        local sp = { key = "s:" .. zone .. "\1" .. sub, zoneKey = zone, subKey = sub, time = s.time,
          gold = s.gold, value = t.best + gold, vendor = t.vendor, ah = t.ah, count = #items,
          lastSeen = maxSeen(items) }
        if sp.time > 0 then sp.perHour = placePerHour(sp.value, sp.time) end
        subRows[#subRows + 1] = placeRow(sp, placeLabel(sub), isOpen, "    ", L_CLICK_OPEN,
          sub == View.NO_TIME_SUB)
        if pick.zone == zone and pick.sub == sub then subRows[#subRows].daily = true end
        if isOpen then subItems[subRows[#subRows]] = items end
        zp.gold, zp.value = zp.gold + s.gold, zp.value + sp.value
        zp.vendor, zp.ah, zp.count = zp.vendor + t.vendor, zp.ah + t.ah, zp.count + #items
        if sp.time > 0 then zp.timedValue = zp.timedValue + sp.value end
        if sp.lastSeen and (not zp.lastSeen or sp.lastSeen > zp.lastSeen) then zp.lastSeen = sp.lastSeen end
        totals.vendor, totals.ah, totals.best = totals.vendor + t.vendor, totals.ah + t.ah, totals.best + t.best
        totals.unpriced = totals.unpriced + t.unpriced
        for _, name in ipairs(t.unpricedNames or NO_LOOKUP) do
          if #unpricedNames >= View.UNPRICED_NAMES then break end
          unpricedNames[#unpricedNames + 1] = name
        end
        goldSum = goldSum + s.gold
      end
    end
    if #subRows > 0 then
      if zp.time > 0 then zp.perHour = placePerHour(zp.timedValue, zp.time) end
      local isOpen = open.zone == zone
      local row = placeRow(zp, placeLabel(zone), isOpen, "", L_CLICK_SUBZONES, zone == View.UNKNOWN_ZONE)
      if pick.zone == zone then row.daily = true end
      table.sort(subRows, sort)
      row.children, row.childItems = subRows, subItems
      zoneRows[#zoneRows + 1] = row
      if isOpen then opened = row end
    end
  end
  table.sort(zoneRows, sort)

  local rows = {}
  for _, zr in ipairs(zoneRows) do
    rows[#rows + 1] = zr
    if zr == opened then
      for _, sr in ipairs(zr.children) do
        rows[#rows + 1] = sr
        if zr.childItems[sr] then append(rows, zr.childItems[sr]) end
      end
    end
    zr.children, zr.childItems = nil, nil
  end

  local questItems, qt = collect(quest, opts)
  if #questItems > 0 then
    local isOpen = open.zone == View.QUEST_ZONE
    local qp = { key = "z:" .. View.QUEST_ZONE, zoneKey = View.QUEST_ZONE, time = 0, gold = 0,
      value = qt.best, vendor = qt.vendor, ah = qt.ah, count = #questItems, lastSeen = maxSeen(questItems) }
    rows[#rows + 1] = placeRow(qp, L_QUEST_ITEMS, isOpen, "", L_CLICK_OPEN)
    if isOpen then append(rows, questItems) end
  end

  local view = { rows = rows, top = {}, totals = totals, kind = "zones", history = true,
    empty = View.emptyText(rows, opts.filter, L_NO_HISTORY),
    headerInfo = #zoneRows > 0 and ns.History.placeCount(#zoneRows) or nil }
  if totals.unpriced > 0 then totals.unpricedNames = unpricedNames end
  addGold(view, goldSum, opts.includeGold)
  return View.applyRates(view, timeSum)
end

-- ---------------------------------------------------------------------------
-- History Mobs: every mob (by NPC ID) and node (by object ID) of the saved
-- sessions plus the running one: what it dropped (valued like Zones: saved
-- prices first), its gold, kills and looted count, and the value per kill
-- (per time looted for nodes and mobs without kills). The search and the
-- minimum value pick mobs; the qualities filter their items. The mob at
-- `openKey` lists its items under it.

local L_N_KILLS, L_ONE_KILL = L[" kills"], L["1 kill"]
local L_N_LOOTED = L[" looted"]
local L_EACH = L[" each"]
local mobOpts, mobFilter = {}, {}

local function perKill(a, b)
  local ka, kb = a.perKill, b.perKill
  if ka ~= kb then
    if ka == nil then return false end
    if kb == nil then return true end
    return ka > kb
  end
  return byName(a, b)
end

local MOB_SORTS = { ah = SORTS.ah, name = SORTS.name, kills = descending("kills"), perKill = perKill }

-- Under the value sorts a mob that dropped nothing goes last; by kills or
-- name the order is plain.
local function mobSort(key)
  local inner = MOB_SORTS[key] or MOB_SORTS.ah
  if key == "kills" or key == "name" then return inner end
  return function(a, b)
    if a.sortsLast ~= b.sortsLast then return b.sortsLast end
    return inner(a, b)
  end
end

-- The source item of `key` for a mob's loot: the entry's own item (its saved
-- price), else a bare one priced live.
local function mobItemSource(e, key)
  local src = type(e.items) == "table" and e.items[key]
  if type(src) == "table" and num(src.id) then return src end
  local id = tonumber(key) or tonumber(tostring(key):match("^(%d+)"))
  if not id then return nil end
  return { id = id, key = key }
end

local function mainPlace(places)
  local best, bestN
  for p, n in pairs(places) do
    if not bestN or n > bestN or (n == bestN and p < best) then best, bestN = p, n end
  end
  return best
end

function View.buildMobs(entries, opts, openKey)
  opts = opts or {}
  if type(entries) ~= "table" then entries = {} end
  local filter = opts.filter
  local needle = searchNeedle(filter)
  local minValue = type(filter) == "table" and num(filter.minValue) and filter.minValue or 0
  local withGold = opts.includeGold ~= false
  copyOpts(mobOpts, opts)
  mobFilter.qualities = type(filter) == "table" and filter.qualities or nil
  mobOpts.filter = mobFilter

  -- Mobs added up over the entries; their items as Zones items.
  local all = {}
  for _, e in ipairs(entries) do
    if type(e) == "table" and type(e.mobs) == "table" then
      for key, m in pairs(e.mobs) do
        if type(key) == "string" and type(m) == "table" and num(m.kills) and num(m.looted) and num(m.gold) then
          local a = all[key]
          if not a then
            a = { kind = m.kind == "node" and "node" or "npc", kills = 0, looted = 0, gold = 0, items = {}, places = {} }
            all[key] = a
          end
          if type(m.name) == "string" and m.name ~= "" then a.name = m.name end
          a.kills, a.looted, a.gold = a.kills + m.kills, a.looted + m.looted, a.gold + m.gold
          for itemKey, qty in pairs(type(m.items) == "table" and m.items or NO_LOOKUP) do
            local src = num(qty) and qty > 0 and mobItemSource(e, itemKey)
            if src then addZoneItem(a.items, src, itemKey, qty) end
          end
          for p, n in pairs(type(m.places) == "table" and m.places or NO_LOOKUP) do
            if type(p) == "string" and num(n) then a.places[p] = (a.places[p] or 0) + n end
          end
        end
      end
    end
  end

  local totals = { vendor = 0, ah = 0, best = 0, unpriced = 0, filtered = View.isFiltered(filter) }
  local goldSum = 0
  local mobRows, opened, openedItems = {}, nil, nil
  for key, a in pairs(all) do
    local items, t = collect(a.items, mobOpts)
    local gold = withGold and a.gold or 0
    local value = t.best + gold
    local per = a.kills > 0 and a.kills or a.looted
    local label = a.name or key
    local isOpen = key == openKey
    local parts = {}
    if a.kills > 0 then
      parts[#parts + 1] = a.kills == 1 and L_ONE_KILL or (a.kills .. L_N_KILLS)
    else
      parts[#parts + 1] = a.looted .. L_N_LOOTED
    end
    local perValue = per > 0 and value / per or nil
    if perValue then parts[#parts + 1] = ns.Money.format(math.floor(perValue + 0.5)) .. L_EACH end
    local place = mainPlace(a.places)
    if place then parts[#parts + 1] = View.shortPlace(place) end
    local row = {
      id = 0, key = "m:" .. key, mobKey = key, kills = a.kills, looted = a.looted, perKill = perValue,
      name = (isOpen and "- " or "+ ") .. label, detail = detailText(parts), sortName = lower(label),
      quality = 1, sortsLast = value <= 0,
      vendorTotal = t.vendor, ahTotal = t.ah, bestLineTotal = value, value = value,
      icon = a.kind == "node" and ns.Theme.textures.node or ns.Theme.textures.mob,
      hint = isOpen and L_CLICK_CLOSE or L_CLICK_OPEN,
    }
    local shown = isOpen or (value >= minValue
      and (not needle or string.find(row.sortName, needle, 1, true) ~= nil
        or (place and string.find(lower(place), needle, 1, true) ~= nil)))
    if shown then
      mobRows[#mobRows + 1] = row
      if isOpen then opened, openedItems = row, items end
      totals.vendor, totals.ah, totals.best = totals.vendor + t.vendor, totals.ah + t.ah, totals.best + t.best
      totals.unpriced = totals.unpriced + t.unpriced
      goldSum = goldSum + a.gold
    end
  end
  table.sort(mobRows, mobSort(opts.sort))

  local rows = {}
  if opened then
    rows[1] = opened
    append(rows, openedItems)
  end
  for _, r in ipairs(mobRows) do
    if r ~= opened then rows[#rows + 1] = r end
  end
  local view = { rows = rows, top = {}, totals = totals, kind = "mobs", history = true,
    empty = View.emptyText(rows, filter, L_NO_HISTORY),
    headerInfo = #mobRows > 0 and ns.History.mobCount(#mobRows) or nil }
  addGold(view, goldSum, opts.includeGold)
  return View.applyRates(view, 0)
end

-- ---------------------------------------------------------------------------
-- Daily farm: the subzone of the saved History with the best gold per hour at
-- the current prices (valued like History Zones). The filter bar is ignored;
-- only subzones with at least `minSeconds` recorded time count.
--   { best = place, runnersUp = { place, ... (2 at most) }, slow = { names } or nil }
--   place = { zone, sub, time, value, perHour, pos = { mapID, x, y } or nil }
--   (pos: the averaged loot spot on the map looted most; none in instances
--   or in History saved before positions were recorded)
-- slow: more than half of the best place's AH value comes from items whose
-- sale rate is in the bad level (needs opts.market, i.e. TSM sale info).

View.FARM_RUNNERS_UP = 2
View.FARM_SLOW_NAMES = 5

local farmOpts = {}

local function farmSort(a, b)
  if a.perHour ~= b.perHour then return a.perHour > b.perHour end
  if a.time ~= b.time then return a.time > b.time end
  if a.zone ~= b.zone then return a.zone < b.zone end
  return a.sub < b.sub
end

local function slowItems(rows)
  local slowAh, allAh, bad = 0, 0, {}
  for _, r in ipairs(rows) do
    local ah = r.ahTotal or 0
    allAh = allAh + ah
    if r.rateLevel == "bad" and ah > 0 then
      slowAh = slowAh + ah
      bad[#bad + 1] = r
    end
  end
  if allAh <= 0 or slowAh * 2 <= allAh then return nil end
  table.sort(bad, function(a, b)
    if a.ahTotal ~= b.ahTotal then return a.ahTotal > b.ahTotal end
    return (a.sortName or "") < (b.sortName or "")
  end)
  local names = {}
  for i = 1, math.min(#bad, View.FARM_SLOW_NAMES) do names[i] = bad[i].name end
  return { names = names }
end

function View.dailyFarm(entries, opts, minSeconds)
  if type(entries) ~= "table" then return nil end
  opts = opts or {}
  if not num(minSeconds) then minSeconds = 0 end
  copyOpts(farmOpts, opts)
  farmOpts.filter, farmOpts.sort = nil, nil
  local withGold = opts.includeGold ~= false
  local levelFits = type(opts.levelFits) == "function" and opts.levelFits or nil

  local places, rowsOf = {}, {}
  local zones = aggregateZones(entries, opts.isQuest)
  for zone, subs in pairs(zones) do
    if zone ~= View.UNKNOWN_ZONE then
      for sub, s in pairs(subs) do
        if sub ~= View.NO_TIME_SUB and s.time > 0 and s.time >= minSeconds then
          local rows, t = collect(s.items, farmOpts)
          local value = t.best + (withGold and s.gold or 0)
          local perHour = placePerHour(value, s.time)
          -- A place that earned nothing is never worth going to (and its row
          -- would not exist in Zones to open).
          local pos = spotOf(s.pos)
          -- Option "Daily farm: my level": a place whose map is for another
          -- level is left out (no position or an unknown range: kept).
          local fits = not (levelFits and pos) or levelFits(pos.mapID) ~= false
          if perHour and value > 0 and fits then
            local p = { zone = zone, sub = sub, time = s.time, value = value, perHour = perHour, pos = pos }
            places[#places + 1] = p
            rowsOf[p] = rows
          end
        end
      end
    end
  end
  if #places == 0 then return nil end
  table.sort(places, farmSort)

  local runnersUp = {}
  for i = 2, math.min(#places, View.FARM_RUNNERS_UP + 1) do runnersUp[#runnersUp + 1] = places[i] end
  local best = places[1]
  return { best = best, runnersUp = runnersUp, slow = opts.market and slowItems(rowsOf[best]) or nil }
end

-- ---------------------------------------------------------------------------
-- Compact mode: the glance between pulls. Never filtered (the filter bar is
-- not shown there): total = every item's best value + raw gold (with
-- opts.includeGold), its rate over the session clock (nil under a minute), the
-- running state and the last drops, each row worth that drop's own quantity.
-- The rest is for the hover breakdown: the items' value, the raw gold, the
-- clock, the best find and the session goal (opts.goal).
--   { total, perHour, running, drops = { row, ... }, items, gold, elapsed,
--     top = row or nil, goal = { value, goal } or nil }

View.COMPACT_DROPS = 4

local compactOpts = {}

-- The session goal's progress, { value, goal } (copper), or nil without a goal.
function View.goalProgress(value, goal)
  if not (num(goal) and goal > 0 and num(value)) then return nil end
  return { value = value, goal = goal }
end

-- Whole percent of a goal progress, at most 100.
function View.goalPercent(progress)
  if type(progress) ~= "table" or not num(progress.goal) or progress.goal <= 0 then return 0 end
  return math.min(100, math.floor(progress.value * 100 / progress.goal))
end

-- The gold per hour graph from session.samples (Session.addSample): the rate
-- of each stretch between two samples (copper per hour, never below 0 when
-- prices fell). Returns the rates and the seconds one stretch covers, or nil
-- with fewer than View.GRAPH_MIN_BARS stretches.
View.GRAPH_MIN_BARS = 3

function View.rateGraph(samples)
  if type(samples) ~= "table" then return nil end
  local bars, prevT, prevV = {}, 0, 0
  for _, s in ipairs(samples) do
    if type(s) == "table" and num(s.t) and num(s.v) and s.t > prevT then
      bars[#bars + 1] = math.max(0, s.v - prevV) * 3600 / (s.t - prevT)
      prevT, prevV = s.t, s.v
    end
  end
  if #bars < View.GRAPH_MIN_BARS then return nil end
  return { bars = bars, step = prevT / #bars }
end

-- Adds the graph to a tooltip (ns.Tooltip): a heading, the bars, the best
-- stretch and how long one bar is.
function View.addRateGraph(tip, graph)
  if not graph then return end
  local Tip = ns.Tooltip
  local top = 0
  for _, v in ipairs(graph.bars) do if v > top then top = v end end
  Tip.section(tip, L["Gold per hour over time"])
  Tip.bars(tip, graph.bars)
  Tip.rate(tip, L["Best stretch: "], top)
  Tip.note(tip, string.format(L["One bar: %s of clock time."], ns.History.duration(graph.step)))
end

function View.buildCompact(session, opts)
  opts = opts or {}
  copyOpts(compactOpts, opts)
  compactOpts.filter = nil
  local items = type(session.items) == "table" and session.items or {}
  local ignored = ignoredSet(opts)
  local rows, t = collect(items, compactOpts)
  local gold = 0
  if opts.includeGold ~= false and ns.Session and ns.Session.goldTotal then
    gold = math.max(0, ns.Session.goldTotal(session))
  end
  local total = t.best + gold
  local elapsed = ns.Session.elapsed(session, opts.now or 0)
  local limit = num(opts.compactDrops) and opts.compactDrops or View.COMPACT_DROPS
  local drops = {}
  if type(session.recent) == "table" then
    for _, ev in ipairs(session.recent) do
      if #drops >= limit then break end
      local it = type(ev) == "table" and items[ev.key]
      if type(it) == "table" and num(it.id) and num(ev.qty) and ev.qty > 0 and not ignored[it.id] then
        drops[#drops + 1] = makeRow({ id = it.id, key = it.key or ev.key, link = it.link, price = it.price,
          qty = ev.qty, lastSeen = ev.at }, compactOpts)
      end
    end
  end
  return { total = total, perHour = ns.History.perHour(total, elapsed), running = session.running and true or false,
    drops = drops, items = t.best, gold = gold, elapsed = elapsed, top = topRows(rows, 1)[1],
    goal = View.goalProgress(total, opts.goal), graph = View.rateGraph(session.samples) }
end

-- Session tab: rows, totals, raw gold, combined totals, rates and top finds.
-- Currencies follow the item rows (they have no value). With a session goal
-- (opts.goal), view.goal is its progress: the unfiltered total, like compact.
local goalOpts = {}

function View.build(session, opts)
  local rows, totals = collect(session.items, opts)
  local top = topRows(rows, View.TOP_COUNT)
  append(rows, View.currencyRows(session.currencies, opts))

  -- Raw gold is income of its own: never filtered, counted equally on every
  -- side of the combined totals.
  local view = { rows = rows, top = top, totals = totals, kind = "session",
    empty = View.emptyText(rows, opts.filter, session.running and L_NO_LOOT or L_STOPPED) }
  local gold = math.max(0, ns.Session.goldTotal(session))
  addGold(view, gold, opts.includeGold)
  if num(opts.goal) and opts.goal > 0 then
    local best = totals.best
    if totals.filtered then
      copyOpts(goalOpts, opts)
      goalOpts.filter = nil
      best = select(2, collect(session.items, goalOpts)).best
    end
    view.goal = View.goalProgress(best + (opts.includeGold ~= false and gold or 0), opts.goal)
  end
  view.graph = View.rateGraph(session.samples)
  return View.applyRates(view, ns.Session.elapsed(session, opts.now))
end

-- ---------------------------------------------------------------------------
-- CSV export of the running session and of History Zones (/ll export).

View.ITEMS_CSV_HEADER = "name,quantity,vendor_g,ah_g,destroy_g,counted_g,counted_as"
View.ZONES_CSV_HEADER = "zone,subzone,minutes,value_g,raw_gold_g,gold_per_hour_g,items"

local tableOpts = {}

-- Every subzone of the History Zones data (all of them, no filter), by zone
-- and subzone name: { zone, sub (display names), time, value, gold, perHour,
-- count }. The quest items group is left out.
function View.zoneTable(entries, opts)
  opts = opts or {}
  copyOpts(tableOpts, opts)
  tableOpts.filter, tableOpts.sort = nil, nil
  local withGold = opts.includeGold ~= false
  local out = {}
  for zone, subs in pairs(aggregateZones(type(entries) == "table" and entries or {}, opts.isQuest)) do
    for sub, s in pairs(subs) do
      local rows, t = collect(s.items, tableOpts)
      local gold = withGold and s.gold or 0
      if #rows > 0 or gold > 0 or s.time > 0 then
        local value = t.best + gold
        out[#out + 1] = { zone = placeLabel(zone), sub = placeLabel(sub), time = s.time, value = value,
          gold = s.gold, perHour = placePerHour(value, s.time), count = #rows }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.zone ~= b.zone then return a.zone < b.zone end
    return a.sub < b.sub
  end)
  return out
end

function View.zonesCsv(entries, opts)
  local History = ns.History
  local field, gold = History.csvField, History.goldNumber
  local out = { View.ZONES_CSV_HEADER }
  for _, p in ipairs(View.zoneTable(entries, opts)) do
    out[#out + 1] = table.concat({
      field(p.zone), field(p.sub), string.format("%.1f", p.time / 60), gold(p.value), gold(p.gold),
      p.perHour and gold(p.perHour) or "", tostring(p.count),
    }, ",")
  end
  return table.concat(out, "\n")
end

-- The rows of a view (View.build) as CSV: items with their totals and what
-- they count as (vendor / ah / de), currencies with their quantity only.
function View.itemsCsv(rows)
  local History = ns.History
  local field, gold = History.csvField, History.goldNumber
  local function amount(v) return num(v) and gold(v) or "" end
  local out = { View.ITEMS_CSV_HEADER }
  for _, r in ipairs(type(rows) == "table" and rows or {}) do
    if r.quantity then
      out[#out + 1] = table.concat({
        field(r.name), tostring(r.quantity), amount(r.vendorTotal), amount(r.ahTotal), amount(r.deTotal),
        amount(r.bestTotal), r.bestKind or "",
      }, ",")
    end
  end
  return table.concat(out, "\n")
end

-- Position of the row with `key` (a LootParse.itemKey, or an item ID).
function View.indexOf(rows, key)
  for i, r in ipairs(rows) do
    if r.key == key or (r.key == nil and r.id == key) then return i end
  end
  return nil
end

function View.flashLevel(unitValue, addedQty)
  if num(unitValue) and num(addedQty) and unitValue * addedQty >= View.STRONG_FLASH_VALUE then
    return "strong"
  end
  return "normal"
end

ns.View = View
