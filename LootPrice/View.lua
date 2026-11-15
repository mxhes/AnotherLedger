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
--   formatDate = function(timestamp) -> text (History tab),
--   market = { rateGood, rateOk, soldHigh, soldMedium } or nil (no sale info),
-- }
--
-- A row's value is the best of its vendor, AH and disenchant totals; the sort
-- "AH value", Top finds, the minimum value filter and the alerts use it.
local View = {
  TOP_COUNT = 3,
  MIN_RATE_SECONDS = 60,
  STRONG_FLASH_VALUE = 100000,
  CURRENCY_KEY_PREFIX = "c:",
}

local MIN_QUALITY, MAX_QUALITY = 0, 7
local NO_LOOKUP = {}

local L_CLICK_OPEN = L["Click to show the items"]
local L_CLICK_CLOSE = L["Click to collapse"]

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
function View.best(vendorTotal, ahTotal, deTotal)
  local best, kind = nil, nil
  if num(vendorTotal) then best, kind = vendorTotal, "vendor" end
  if num(ahTotal) and (best == nil or ahTotal > best) then best, kind = ahTotal, "ah" end
  if num(deTotal) and (best == nil or deTotal > best) then best, kind = deTotal, "de" end
  return best, kind
end

-- How well an item sells, from TSM region data. `t` = { rateGood, rateOk,
-- soldHigh, soldMedium } (a negative cutoff is never reached). Returns the
-- sale rate level ("good" / "ok" / "bad") and the volume level ("high" /
-- "medium" / "low"); each is nil when its value is unknown or `t` is missing.
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
  local vendorEach = num(lookup.vendor) and lookup.vendor or (num(saved.vendor) and saved.vendor or nil)
  local ahEach = num(lookup.ah) and lookup.ah or nil
  local ahFromCache = lookup.ahSource == "cache"
  local ahAge = num(lookup.ahAge) and lookup.ahAge or nil
  if not ahEach and num(saved.ah) then
    ahEach, ahFromCache = saved.ah, true
    ahAge = num(item.lastSeen) and num(opts.now) and math.max(0, opts.now - item.lastSeen) or nil
  end
  local deEach = num(lookup.de) and lookup.de or (num(saved.de) and saved.de or nil)
  local vendorTotal = vendorEach and vendorEach * qty or nil
  local ahTotal = ahEach and ahEach * qty or nil
  local deTotal = deEach and deEach * qty or nil
  local bestTotal, bestKind = View.best(vendorTotal, ahTotal, deTotal)
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
local SORTS = {
  ah = descending("value"),
  vendor = descending("vendorTotal"),
  recent = descending("lastSeen"),
  name = byName,
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
local function collect(items, opts)
  local filter = opts.filter
  local needle = searchNeedle(filter)

  local rows, n = {}, 0
  local vendor, ah, best, unpriced = 0, 0, 0, 0
  if type(items) ~= "table" then items = {} end
  for _, item in pairs(items) do
    if type(item) == "table" and num(item.id) and num(item.qty) and item.qty > 0 then
      local row = makeRow(item, opts)
      if visible(row, filter, needle) then
        n = n + 1
        rows[n] = row
        vendor = vendor + (row.vendorTotal or 0)
        ah = ah + (row.ahTotal or 0)
        best = best + (row.bestTotal or 0)
        if row.ahEach == nil and not row.bound then unpriced = unpriced + 1 end
      end
    end
  end
  table.sort(rows, SORTS[opts.sort] or SORTS.ah)

  return rows, { vendor = vendor, ah = ah, best = best, unpriced = unpriced, filtered = View.isFiltered(filter) }
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
-- or top finds.
function View.buildInventory(items, opts)
  local rows, totals = collect(items, opts)
  return { rows = rows, top = {}, totals = totals, kind = "inventory" }
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

-- History tab: one row per archived session (newest first), shown through the
-- normal row layout; the DE line carries the session's raw gold. The session
-- at `openIndex` (if any) moves to the top and its items (and currencies) are
-- listed right under it (filter and sort apply to them), then the other
-- sessions follow. The footer adds up every saved session, with rates over
-- their summed length. opts.formatDate(timestamp) -> text.
function View.buildHistory(list, opts, openIndex)
  opts = opts or {}
  if type(list) ~= "table" then list = {} end
  local History = ns.History
  local sessionRows, opened = {}, nil
  local totals = { vendor = 0, ah = 0, best = 0, unpriced = 0, filtered = false }
  local gold, elapsed = 0, 0
  for i, e in ipairs(list) do
    if History.valid(e) then
      local when = opts.formatDate and opts.formatDate(e.startedAt) or tostring(e.startedAt)
      local open = i == openIndex
      local best = History.bestOf(e)
      local place = History.place(e)
      local name = (open and "- " or "+ ") .. when .. "  " .. History.duration(e.elapsed)
      if place then name = name .. "  " .. place end
      local row = {
        id = -i, key = -i, historyIndex = i,
        name = name, sortName = lower(name),
        quality = 1, quantity = e.nItems,
        -- Line 2 of the row shows the session's best value (raw gold is in the hint).
        vendorTotal = e.vendor, ahTotal = e.ah, bestLineTotal = best,
        icon = "Interface\\Icons\\INV_Misc_Note_01",
        hint = History.details(e, opts.formatDate) .. "\n" .. (open and L_CLICK_CLOSE or L_CLICK_OPEN),
        value = best, lastSeen = e.startedAt,
      }
      sessionRows[#sessionRows + 1] = row
      if open then opened = row end
      totals.vendor = totals.vendor + e.vendor
      totals.ah = totals.ah + e.ah
      totals.best = totals.best + best
      gold = gold + e.gold
      elapsed = elapsed + e.elapsed
    end
  end

  local rows = {}
  if opened then
    rows[1] = opened
    local entry = list[openIndex]
    append(rows, (collect(entry.items, opts)))
    append(rows, View.currencyRows(entry.currencies, opts))
  end
  for _, r in ipairs(sessionRows) do
    if r ~= opened then rows[#rows + 1] = r end
  end
  local view = { rows = rows, top = {}, totals = totals, kind = "history", history = true }
  addGold(view, gold, opts.includeGold)
  return View.applyRates(view, elapsed)
end

-- Session tab: rows, totals, raw gold, combined totals, rates and top finds.
-- Currencies follow the item rows (they have no value).
function View.build(session, opts)
  local rows, totals = collect(session.items, opts)
  local top = topRows(rows, View.TOP_COUNT)
  append(rows, View.currencyRows(session.currencies, opts))

  -- Raw gold is income of its own: never filtered, counted equally on every
  -- side of the combined totals.
  local view = { rows = rows, top = top, totals = totals, kind = "session" }
  addGold(view, math.max(0, ns.Session.goldTotal(session)), opts.includeGold)
  return View.applyRates(view, ns.Session.elapsed(session, opts.now))
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
