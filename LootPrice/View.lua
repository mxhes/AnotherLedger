local ADDON, ns = ...

local num = ns.Util.isNumber
local lower = string.lower

-- Pure ledger view: turns a session plus injected lookups into filtered,
-- sorted rows, top finds and totals. No WoW globals.
--
-- opts = {
--   now      = timestamp,
--   filter   = { qualities = { [0..7] = bool }, minValue = copper, search = text },
--   sort     = key of SORTS,
--   lookup   = function(itemID) -> Prices lookup result or nil,
--   itemInfo = function(itemID) -> { name, quality } or nil,
--   formatDate = function(timestamp) -> text (History tab),
-- }
local View = {
  TOP_COUNT = 3,
  MIN_RATE_SECONDS = 60,
  STRONG_FLASH_VALUE = 100000,
}

local MIN_QUALITY, MAX_QUALITY = 0, 7
local NO_LOOKUP = {}

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

-- ---------------------------------------------------------------------------
-- Rows

-- One ledger row for an item ({ id, link, qty, lastSeen }).
local function makeRow(item, opts)
  local lookup = opts.lookup and opts.lookup(item.id)
  if type(lookup) ~= "table" then lookup = NO_LOOKUP end
  local info = opts.itemInfo and opts.itemInfo(item.id)
  if type(info) ~= "table" then info = nil end

  local name = info and type(info.name) == "string" and info.name or nil
  if not name then name = type(item.link) == "string" and item.link:match("%[(.-)%]") or "" end
  local quality = info and num(info.quality) and info.quality or 1

  local qty = item.qty
  local vendorEach = num(lookup.vendor) and lookup.vendor or nil
  local ahEach = num(lookup.ah) and lookup.ah or nil
  local deEach = num(lookup.de) and lookup.de or nil
  local ahFromCache = lookup.ahSource == "cache"
  local ahAge = num(lookup.ahAge) and lookup.ahAge or nil
  local vendorTotal = vendorEach and vendorEach * qty or nil
  local ahTotal = ahEach and ahEach * qty or nil

  return {
    id = item.id, link = item.link, name = name, quality = quality, quantity = qty,
    sortName = lower(name), -- lowercased once, for the search and the name sort
    vendorEach = vendorEach, vendorTotal = vendorTotal,
    ahEach = ahEach, ahTotal = ahTotal,
    deEach = deEach, deTotal = deEach and deEach * qty or nil,
    ahFromCache = ahFromCache, ahAge = ahAge,
    stale = ahFromCache and ahAge ~= nil and ns.Prices.isStale(ahAge) or false,
    value = ahTotal or vendorTotal or 0,
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

-- ---------------------------------------------------------------------------
-- Sorting: every order is total (ties by name, then id), so it is stable
-- across refreshes.

local function byName(a, b)
  local an, bn = a.sortName, b.sortName
  if an ~= bn then return an < bn end
  return a.id < b.id
end

-- Descending by row[field] (missing = 0), ties by name then id.
local function descending(field)
  return function(a, b)
    local ka, kb = a[field] or 0, b[field] or 0
    if ka ~= kb then return ka > kb end
    return byName(a, b)
  end
end

-- A new sort order is one entry here plus its label in UI/FilterBar.lua.
local SORTS = {
  ah = descending("ahTotal"),
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
    if row.value > 0 then
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

-- Filtered, sorted rows and their vendor / AH totals for an items map
-- ({ [itemID] = { id, link, qty, lastSeen } }); shared by the session and the
-- inventory tabs.
local function collect(items, opts)
  local filter = opts.filter
  local needle
  if type(filter) == "table" and type(filter.search) == "string" and filter.search ~= "" then
    needle = lower(filter.search)
  end

  local rows, n = {}, 0
  local vendor, ah, unpriced = 0, 0, 0
  for _, item in pairs(items) do
    if type(item) == "table" and num(item.id) and num(item.qty) and item.qty > 0 then
      local row = makeRow(item, opts)
      if visible(row, filter, needle) then
        n = n + 1
        rows[n] = row
        vendor = vendor + (row.vendorTotal or 0)
        ah = ah + (row.ahTotal or 0)
        if row.ahEach == nil then unpriced = unpriced + 1 end
      end
    end
  end
  table.sort(rows, SORTS[opts.sort] or SORTS.ah)

  return rows, { vendor = vendor, ah = ah, unpriced = unpriced, filtered = View.isFiltered(filter) }
end

-- ---------------------------------------------------------------------------
-- Views

-- Inventory tabs (bags, bank): rows and totals only, no clock, rates, raw gold
-- or top finds.
function View.buildInventory(items, opts)
  local rows, totals = collect(items, opts)
  return { rows = rows, top = {}, totals = totals, kind = "inventory" }
end

-- History tab: one row per archived session (newest first), shown through the
-- normal row layout; the DE line carries the session's raw gold. The session
-- at `openIndex` (if any) moves to the top and its items are listed right
-- under it (filter and sort apply to them), then the other sessions follow.
-- opts.formatDate(timestamp) -> text.
function View.buildHistory(list, opts, openIndex)
  opts = opts or {}
  if type(list) ~= "table" then list = {} end
  local sessionRows, opened = {}, nil
  local totals = { vendor = 0, ah = 0, unpriced = 0, filtered = false }
  for i, e in ipairs(list) do
    if ns.History.valid(e) then
      local when = opts.formatDate and opts.formatDate(e.startedAt) or tostring(e.startedAt)
      local open = i == openIndex
      local row = {
        id = -i, historyIndex = i,
        name = (open and "- " or "+ ") .. when .. "  " .. ns.History.duration(e.elapsed),
        quality = 1, quantity = e.nItems,
        vendorTotal = e.vendor, ahTotal = e.ah, deTotal = e.gold, deLabel = "Gold: ",
        icon = "Interface\\Icons\\INV_Misc_Note_01",
        hint = open and "Click to collapse" or "Click to show the items",
        value = e.ah, lastSeen = e.startedAt,
      }
      sessionRows[#sessionRows + 1] = row
      if open then opened = row end
      totals.vendor = totals.vendor + e.vendor
      totals.ah = totals.ah + e.ah
    end
  end

  local rows = {}
  if opened then
    rows[1] = opened
    local items = collect(list[openIndex].items, opts)
    for _, r in ipairs(items) do rows[#rows + 1] = r end
  end
  for _, r in ipairs(sessionRows) do
    if r ~= opened then rows[#rows + 1] = r end
  end
  return { rows = rows, top = {}, totals = totals, kind = "inventory", history = true }
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
    gold.perHour = perHour(gold.total, elapsed)
    combined.vendorPerHour = perHour(combined.vendor, elapsed)
    combined.ahPerHour = perHour(combined.ah, elapsed)
  else
    totals.vendorPerHour, totals.ahPerHour = nil, nil
    gold.perHour = nil
    combined.vendorPerHour, combined.ahPerHour = nil, nil
  end
  return view
end

-- Session tab: rows, totals, raw gold, combined totals, rates and top finds.
function View.build(session, opts)
  local rows, totals = collect(session.items, opts)

  -- Raw gold is income of its own: never filtered, counted equally on both
  -- sides of the combined totals.
  local goldTotal = math.max(0, ns.Session.goldTotal(session))
  local view = {
    rows = rows,
    top = topRows(rows, View.TOP_COUNT),
    totals = totals,
    gold = { total = goldTotal },
    combined = { vendor = totals.vendor + goldTotal, ah = totals.ah + goldTotal },
  }
  return View.applyRates(view, ns.Session.elapsed(session, opts.now))
end

function View.indexOf(rows, itemID)
  for i, r in ipairs(rows) do
    if r.id == itemID then return i end
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
