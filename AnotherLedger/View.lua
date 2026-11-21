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
--   unpricedFirst = bool (the footer's unpriced note was clicked: item rows
--     without an AH price, row.unpriced, sort first),
--   hideWorthless = bool (option "Hide worthless": rows nothing pays for,
--     row.worthless, are left out of the lists and the compact drops),
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

ns.View = View

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
local L_NO_MOBS = L["No mob loot recorded yet. What you loot from mobs and nodes while the clock runs shows here."]

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

-- Whether a lookup's AH price shows its age: a cached one, or a live source's
-- with an age of its own (AnotherLedger scan).
local function aged(lookup)
  return lookup.ahSource == "cache" or lookup.ahAged == true
end

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
  -- with ahGross, a saved price with its own `cut`.
  local ahCut = false
  if opts.savedPrices then
    -- An opened History session: the prices it was saved with (its row's
    -- totals), live ones only for what it has none of. No age tag.
    vendorEach = num(saved.vendor) and saved.vendor or (num(lookup.vendor) and lookup.vendor or nil)
    deEach = num(saved.de) and saved.de or (num(lookup.de) and lookup.de or nil)
    if num(saved.ah) then
      ahEach, ahFromCache = saved.ah, false
      ahCut = saved.cut == true
    elseif num(lookup.ah) then
      ahEach, ahFromCache = lookup.ah, aged(lookup)
      ahAge = num(lookup.ahAge) and lookup.ahAge or nil
      ahCut = num(lookup.ahGross)
    end
  else
    vendorEach = num(lookup.vendor) and lookup.vendor or (num(saved.vendor) and saved.vendor or nil)
    ahEach = num(lookup.ah) and lookup.ah or nil
    ahCut = ahEach ~= nil and num(lookup.ahGross)
    ahFromCache = aged(lookup)
    ahAge = num(lookup.ahAge) and lookup.ahAge or nil
    if not ahEach and num(saved.ah) then
      ahEach, ahFromCache = saved.ah, true
      ahCut = saved.cut == true
      ahAge = num(item.lastSeen) and num(opts.now) and math.max(0, opts.now - item.lastSeen) or nil
    end
    -- The destroy rule (lookup.deBlocked) also drops the loot-time value.
    deEach = num(lookup.de) and lookup.de or (not lookup.deBlocked and num(saved.de) and saved.de or nil)
  end
  local vendorTotal = vendorEach and vendorEach * qty or nil
  local ahTotal = ahEach and ahEach * qty or nil
  local deTotal = deEach and deEach * qty or nil
  -- The best of the three and which one it is (Prices.best: ties prefer
  -- vendor, then AH; opts.ahMinGain is the option Auction from).
  local bestTotal, bestKind = ns.Prices.best(vendorTotal, ahTotal, deTotal, opts.ahMinGain)
  local rateLevel, volumeLevel = View.marketLevels(lookup.saleRate, lookup.soldPerDay, opts.market)
  -- Bound items can never be sold on the AH: by bind type (info.bound) or
  -- because this stack is soulbound (item.bound, Bags and Bank).
  local bound = (info and info.bound or item.bound == true) and true or false
  -- Nothing to sell it for (quest items, keys): a vendor price of 0 and no
  -- AH or destroy value. The row shows a dash instead of "0 Vendor".
  local worthless = vendorEach == 0 and ahEach == nil and deEach == nil

  return {
    rateLevel = rateLevel, volumeLevel = volumeLevel,
    id = item.id, key = item.key or item.id, link = item.link, name = name, quality = quality, quantity = qty,
    sortName = lower(name), -- lowercased once, for the search and the name sort
    vendorEach = vendorEach, vendorTotal = vendorTotal,
    ahEach = ahEach, ahTotal = ahTotal,
    deEach = deEach, deTotal = deTotal,
    bestTotal = bestTotal, bestKind = bestKind,
    bound = bound,
    -- No AH price ("?" on the row, counted in the footer): never for bound
    -- or worthless items, which show no "?".
    unpriced = ahEach == nil and not bound and not worthless,
    ahFromCache = ahFromCache, ahAge = ahAge,
    ahCut = ahCut and true or false,
    stale = ahFromCache and ahAge ~= nil and ns.Prices.isStale(ahAge) or false,
    value = bestTotal or 0,
    worthless = worthless,
    lastSeen = item.lastSeen,
  }
end

-- The best value of a session item ({ id, link, qty, price }) exactly as its
-- list row counts it: `lookup(itemID, link)` first, the loot-time prices for
-- what it does not know. `ahMinGain`: the option "Auction from".
local valueOpts = {}
function View.itemValue(item, lookup, ahMinGain)
  valueOpts.lookup, valueOpts.ahMinGain = lookup, ahMinGain
  return makeRow(item, valueOpts).value
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

-- Descending by row[field]; rows without one last, ties by name then key.
local function descendingKnown(field)
  return function(a, b)
    local ka, kb = a[field], b[field]
    if ka ~= kb then
      if ka == nil then return false end
      if kb == nil then return true end
      return ka > kb
    end
    return byName(a, b)
  end
end

-- `inner` with the rows marked sortsLast after the others (Unknown place, a
-- mob that dropped nothing). Built once per inner order.
local lastSorts = {}
local function sortsLastAfter(inner)
  local s = lastSorts[inner]
  if not s then
    s = function(a, b)
      if a.sortsLast ~= b.sortsLast then return b.sortsLast end
      return inner(a, b)
    end
    lastSorts[inner] = s
  end
  return s
end

-- `inner` with the unpriced rows ("?", no AH price) first: a click on the
-- footer's unpriced note (opts.unpricedFirst, Ledger.toggleUnpricedFirst).
local unpricedSorts = {}
local function unpricedFirst(inner)
  local s = unpricedSorts[inner]
  if not s then
    s = function(a, b)
      local ua, ub = a.unpriced == true, b.unpriced == true
      if ua ~= ub then return ua end
      return inner(a, b)
    end
    unpricedSorts[inner] = s
  end
  return s
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
  perHour = descendingKnown("perHour"),
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
  local hideWorthless = opts.hideWorthless == true

  local rows, n = {}, 0
  local vendor, ah, best, unpriced = 0, 0, 0, 0
  local unpricedNames = {}
  if type(items) ~= "table" then items = {} end
  for _, item in pairs(items) do
    if type(item) == "table" and num(item.id) and num(item.qty) and item.qty > 0 and not ignored[item.id] then
      local row = makeRow(item, opts)
      if visible(row, filter, needle) and not (hideWorthless and row.worthless) then
        n = n + 1
        rows[n] = row
        vendor = vendor + (row.vendorTotal or 0)
        ah = ah + (row.ahTotal or 0)
        best = best + (row.bestTotal or 0)
        if row.unpriced then
          unpriced = unpriced + 1
          if #unpricedNames < View.UNPRICED_NAMES then
            unpricedNames[#unpricedNames + 1] = row.name .. " x" .. row.quantity
          end
        end
      end
    end
  end
  local order = opts.sort ~= "perHour" and SORTS[opts.sort] or SORTS.ah
  table.sort(rows, opts.unpricedFirst and unpricedFirst(order) or order)

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

-- Sets the rates of `view` from part of its totals only: `timed` = { vendor,
-- ah, best, gold } of the places with recorded time, over their `seconds`.
-- Loot without time (old sessions) counts in the amounts, not in the rates.
local function timedRates(view, timed, seconds, includeGold)
  local part = addGold({ totals = { vendor = timed.vendor, ah = timed.ah, best = timed.best } },
    timed.gold, includeGold)
  View.applyRates(part, seconds)
  local t, pt = view.totals, part.totals
  t.vendorPerHour, t.ahPerHour, t.bestPerHour = pt.vendorPerHour, pt.ahPerHour, pt.bestPerHour
  view.gold.perHour = part.gold.perHour
  local c, pc = view.combined, part.combined
  c.vendorPerHour, c.ahPerHour, c.bestPerHour = pc.vendorPerHour, pc.ahPerHour, pc.bestPerHour
  return view
end

local savedOpts = {} -- opts of an opened History session (reused)
local savedFilter = {} -- its filter: the qualities only (reused)

-- The sorts of the session list (UI/Tabs.lua offers these); any other sort
-- works as "ah".
local SESSION_SORT = { ah = SORTS.ah, recent = SORTS.recent, perHour = SORTS.perHour }

-- One History session row. Line 1: the start and the note ("+ Today 20:21 ·
-- Wingrest herbs"); line 2 (`detail`): length, gold per hour, item count and
-- main place. Its
-- amount is the best value of the items (without ignored ones) plus, with
-- includeGold, the raw gold. The tooltip is built on hover (a function,
-- ns.Tooltip.resolve). `totals` = { vendor, ah, best } of History.totals.
local function sessionRow(e, i, open, opts, totals)
  local History = ns.History
  local dateFn = opts.shortDate or opts.formatDate
  local when = dateFn and dateFn(e.startedAt) or tostring(e.startedAt)
  local value = totals.best + (opts.includeGold ~= false and e.gold or 0)
  local perHour = History.perHour(value, e.elapsed)
  -- The place last: a narrow window cuts the line at its end, and a long
  -- place name may lose its tail, the item count never.
  local parts = { History.duration(e.elapsed) }
  if perHour then parts[#parts + 1] = ns.Money.format(ns.Money.roundRate(perHour)) .. L_PER_HOUR end
  parts[#parts + 1] = History.itemCount(totals.count)
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
    perHour = perHour,
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
  local context = History.periodContext(opts.now, opts.dateFn)
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
      local key, label = History.period(r.entry.startedAt, opts.now, opts.dateFn, context)
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
-- Compact mode: the glance between pulls. Never filtered (the filter bar is
-- not shown there): total = every item's best value + raw gold (with
-- opts.includeGold), its rate over the session clock (nil under a minute), the
-- running state and the last drops, each row worth that drop's own quantity.
-- The rest is for the hover breakdown: the items' value, the raw gold, the
-- clock, the best find and the session goal (opts.goal).
--   { total, perHour, running, drops = { row, ... }, dropLimit, items, gold, elapsed,
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

-- Gold per hour of the last `window` seconds of clock: from the newest sample
-- at least that old to `total` now (the samples hold the same worth as the
-- compact total). nil while the session is younger than `window`. With long
-- sessions the samples are sparser (Session.addSample), so the stretch may
-- run up to one sample step longer.
View.RECENT_SECONDS = 15 * 60

function View.recentRate(samples, elapsed, total, window)
  if type(samples) ~= "table" or not (num(elapsed) and num(total)) then return nil end
  window = window or View.RECENT_SECONDS
  for i = #samples, 1, -1 do
    local s = samples[i]
    if type(s) == "table" and num(s.t) and num(s.v) and elapsed - s.t >= window then
      return math.max(0, total - s.v) * 3600 / (elapsed - s.t)
    end
  end
  return nil
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
        local row = makeRow({ id = it.id, key = it.key or ev.key, link = it.link, price = it.price,
          qty = ev.qty, lastSeen = ev.at }, compactOpts)
        if not (opts.hideWorthless == true and row.worthless) then drops[#drops + 1] = row end
      end
    end
  end
  return { total = total, perHour = ns.History.perHour(total, elapsed), running = session.running and true or false,
    recent = View.recentRate(session.samples, elapsed, total),
    drops = drops, dropLimit = limit, items = t.best, gold = gold, elapsed = elapsed, top = topRows(rows, 1)[1],
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


-- Shared with ViewZones.lua and ViewTrade.lua (not for other files).
View.internal = {
  NO_LOOKUP = NO_LOOKUP,
  SORTS = SORTS,
  addGold = addGold,
  append = append,
  byName = byName,
  collect = collect,
  copyOpts = copyOpts,
  descending = descending,
  descendingKnown = descendingKnown,
  detailText = detailText,
  searchNeedle = searchNeedle,
  sortsLastAfter = sortsLastAfter,
  timedRates = timedRates,
  topRows = topRows,
  visible = visible,
}

-- ---------------------------------------------------------------------------
-- CSV export of the running session (/al export session).

View.ITEMS_CSV_HEADER = "name,quantity,vendor_g,ah_g,destroy_g,counted_g,counted_as"

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
