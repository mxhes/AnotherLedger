local ADDON, ns = ...

-- Pure ledger view: turns a session plus injected lookups into filtered,
-- sorted rows, top finds and totals. No WoW globals.
local View = {
  TOP_COUNT = 3,
  MIN_RATE_SECONDS = 60,
  STRONG_FLASH_VALUE = 100000,
}

local function num(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function allQualities(set)
  for q = 0, 7 do
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

local function makeRow(item, opts)
  local lookup = opts.lookup and opts.lookup(item.id)
  if type(lookup) ~= "table" then lookup = {} end
  local info = opts.itemInfo and opts.itemInfo(item.id)
  if type(info) ~= "table" then info = nil end

  local name = info and type(info.name) == "string" and info.name or nil
  if not name then name = type(item.link) == "string" and item.link:match("%[(.-)%]") or "" end
  local quality = info and num(info.quality) and info.quality or 1

  local qty = item.qty
  local vendorEach = num(lookup.vendor) and lookup.vendor or nil
  local ahEach = num(lookup.ah) and lookup.ah or nil
  local ahFromCache = lookup.ahSource == "cache"
  local ahAge = num(lookup.ahAge) and lookup.ahAge or nil
  local vendorTotal = vendorEach and vendorEach * qty or nil
  local ahTotal = ahEach and ahEach * qty or nil
  local deEach = num(lookup.de) and lookup.de or nil
  local deTotal = deEach and deEach * qty or nil

  return {
    id = item.id, link = item.link, name = name, quality = quality, quantity = qty,
    vendorEach = vendorEach, vendorTotal = vendorTotal,
    ahEach = ahEach, ahTotal = ahTotal,
    deEach = deEach, deTotal = deTotal,
    ahFromCache = ahFromCache, ahAge = ahAge,
    stale = ahFromCache and ahAge ~= nil and ns.Prices.isStale(ahAge) or false,
    value = ahTotal or vendorTotal or 0,
    lastSeen = item.lastSeen,
  }
end

local function visible(row, filter, needle)
  if type(filter) ~= "table" then return true end
  if type(filter.qualities) == "table" and not filter.qualities[row.quality] then return false end
  if num(filter.minValue) and row.value < filter.minValue then return false end
  if needle and not string.find(string.lower(row.name), needle, 1, true) then return false end
  return true
end

local function byName(a, b)
  local an, bn = string.lower(a.name), string.lower(b.name)
  if an ~= bn then return an < bn end
  return a.id < b.id
end

-- Descending by key(row), ties by name then id.
local function descending(key)
  return function(a, b)
    local ka, kb = key(a), key(b)
    if ka ~= kb then return ka > kb end
    return byName(a, b)
  end
end

local SORTS = {
  ah = descending(function(r) return r.ahTotal or 0 end),
  vendor = descending(function(r) return r.vendorTotal or 0 end),
  recent = descending(function(r) return r.lastSeen or 0 end),
  name = byName,
}

-- Filtered, sorted rows and their vendor / AH totals for an items map
-- ({ [itemID] = { id, link, qty, lastSeen } }); shared by the session and the
-- inventory tabs.
local function collect(items, opts)
  local filter = opts.filter
  local needle
  if type(filter) == "table" and type(filter.search) == "string" and filter.search ~= "" then
    needle = string.lower(filter.search)
  end

  local rows = {}
  for _, item in pairs(items) do
    if type(item) == "table" and num(item.id) and num(item.qty) and item.qty > 0 then
      local row = makeRow(item, opts)
      if visible(row, filter, needle) then rows[#rows + 1] = row end
    end
  end
  table.sort(rows, SORTS[opts.sort] or SORTS.ah)

  local totals = { vendor = 0, ah = 0, unpriced = 0, filtered = View.isFiltered(filter) }
  for _, r in ipairs(rows) do
    totals.vendor = totals.vendor + (r.vendorTotal or 0)
    totals.ah = totals.ah + (r.ahTotal or 0)
    if r.ahEach == nil then totals.unpriced = totals.unpriced + 1 end
  end
  return rows, totals
end

-- Inventory tabs (bags, bank): rows and totals only, no clock, rates, raw gold
-- or top finds.
function View.buildInventory(items, opts)
  local rows, totals = collect(items, opts)
  return { rows = rows, top = {}, totals = totals, kind = "inventory" }
end

-- History tab, list level: one row per archived session (newest first), shown
-- through the normal row layout. The DE line carries the session's raw gold.
-- opts.formatDate(timestamp) -> text.
function View.buildHistory(list, opts)
  opts = opts or {}
  local rows = {}
  local totals = { vendor = 0, ah = 0, unpriced = 0, filtered = false }
  for i, e in ipairs(type(list) == "table" and list or {}) do
    if ns.History.valid(e) then
      local when = opts.formatDate and opts.formatDate(e.startedAt) or tostring(e.startedAt)
      rows[#rows + 1] = {
        id = -i, historyIndex = i, name = when .. "  " .. ns.History.duration(e.elapsed),
        quality = 1, quantity = e.nItems,
        vendorTotal = e.vendor, ahTotal = e.ah, deTotal = e.gold, deLabel = "Gold: ",
        icon = "Interface\\Icons\\INV_Misc_Note_01", hint = "Click to show the items",
        value = e.ah, lastSeen = e.startedAt,
      }
      totals.vendor = totals.vendor + e.vendor
      totals.ah = totals.ah + e.ah
    end
  end
  return { rows = rows, top = {}, totals = totals, kind = "inventory", history = true }
end

-- History tab, detail level: the items of one archived session like the Bags
-- tab, with the session's date, length and raw gold as the footer note.
function View.buildHistoryDetail(entry, opts)
  opts = opts or {}
  local ok = ns.History.valid(entry)
  local view = View.buildInventory(ok and entry.items or {}, opts)
  if ok then
    local when = opts.formatDate and opts.formatDate(entry.startedAt) or tostring(entry.startedAt)
    view.note = when .. " - " .. ns.History.duration(entry.elapsed) .. " - Gold " .. ns.Money.format(entry.gold)
  end
  view.history = true
  return view
end

function View.build(session, opts)
  local rows, totals = collect(session.items, opts)
  local elapsed = ns.Session.elapsed(session, opts.now)
  if num(elapsed) and elapsed >= View.MIN_RATE_SECONDS then
    totals.vendorPerHour = totals.vendor * 3600 / elapsed
    totals.ahPerHour = totals.ah * 3600 / elapsed
  end

  -- Raw gold is income of its own: never filtered, counted equally on both
  -- sides of the combined totals.
  local goldTotal = ns.Session.goldTotal(session)
  if goldTotal < 0 then goldTotal = 0 end
  local gold = { total = goldTotal }
  local combined = { vendor = totals.vendor + goldTotal, ah = totals.ah + goldTotal }
  if num(elapsed) and elapsed >= View.MIN_RATE_SECONDS then
    gold.perHour = goldTotal * 3600 / elapsed
    combined.vendorPerHour = combined.vendor * 3600 / elapsed
    combined.ahPerHour = combined.ah * 3600 / elapsed
  end

  local ranked = {}
  for _, r in ipairs(rows) do
    if r.value > 0 then ranked[#ranked + 1] = r end
  end
  table.sort(ranked, descending(function(r) return r.value end))
  local top = {}
  for i = 1, math.min(View.TOP_COUNT, #ranked) do top[i] = ranked[i] end

  return { rows = rows, top = top, totals = totals, gold = gold, combined = combined }
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
