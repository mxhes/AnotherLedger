local ADDON, ns = ...

-- History Zones, Mobs and the Daily farm (pure, like View.lua; loads after it),
-- their CSV export and the drop chances of the game's item tooltips.

local L = ns.L
local View = ns.View
local I = View.internal
local num = ns.Util.isNumber
local lower = string.lower
local L_CLICK_CLOSE = L["Click to collapse"]
local L_CLICK_OPEN = L["Click to show the items"]
local L_NO_HISTORY = L["No saved sessions yet. A session is saved when you reset it."]
local L_NO_MOBS = L["No mob loot recorded yet. What you loot from mobs and nodes while the clock runs shows here."]
local L_PER_HOUR = L["/h"]
local NO_LOOKUP = I.NO_LOOKUP
local SORTS = I.SORTS
local addGold = I.addGold
local append = I.append
local byName = I.byName
local collect = I.collect
local copyOpts = I.copyOpts
local descendingKnown = I.descendingKnown
local detailText = I.detailText
local searchNeedle = I.searchNeedle
local sortsLastAfter = I.sortsLastAfter
local timedRates = I.timedRates
local topRows = I.topRows

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
-- No "+ / -" before the name: the indent shows the level, the tooltip the
-- click, and long place names keep the room (the window is narrow).
local function placeRow(p, label, open, indent, clickText, last)
  local parts = {}
  if p.time > 0 then parts[#parts + 1] = ns.History.duration(p.time) end
  if p.perHour then parts[#parts + 1] = ns.Money.format(ns.Money.roundRate(p.perHour)) .. L_PER_HOUR end
  parts[#parts + 1] = ns.History.itemCount(p.count)
  return {
    id = 0, key = p.key, zoneKey = p.zoneKey, subKey = p.subKey, open = open,
    name = indent .. View.shortPlace(label), detail = indent .. detailText(parts),
    sortName = lower(label), quality = 1, sortsLast = last or false,
    vendorTotal = p.vendor, ahTotal = p.ah, bestLineTotal = p.value,
    value = p.value, perHour = p.perHour, placeTime = p.time, lastSeen = p.lastSeen,
    icon = MAP_ICON, hint = function() return placeHint(p, label, open, clickText) end,
  }
end

-- The place sorts: rows marked sortsLast after the others, then the chosen order.
local function placeSort(key)
  return sortsLastAfter(SORTS[key] or SORTS.ah)
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
  -- The listed places with recorded time: the footer's rates divide only
  -- their value by timeSum, like the zone rows (timedValue).
  local timed = { vendor = 0, ah = 0, best = 0, gold = 0 }

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
        if sp.time > 0 then sp.perHour = ns.History.perHour(sp.value, sp.time) end
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
        if s.time > 0 then
          timed.vendor, timed.ah, timed.best = timed.vendor + t.vendor, timed.ah + t.ah, timed.best + t.best
          timed.gold = timed.gold + s.gold
        end
      end
    end
    if #subRows > 0 then
      if zp.time > 0 then zp.perHour = ns.History.perHour(zp.timedValue, zp.time) end
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
  return timedRates(view, timed, timeSum, opts.includeGold)
end

-- ---------------------------------------------------------------------------
-- History Mobs: every mob (by NPC ID) and node (by object ID) of the saved
-- sessions plus the running one: what it dropped (valued like Zones: today's
-- prices, the saved ones for what has none), its gold, how often it was looted and the value per loot
-- (corpse or node; kills are not known on this client, Mobs.lua). The search
-- and the minimum value pick mobs; the qualities filter their items. The mob
-- at `openKey` lists its items under it.

local L_N_LOOTED = L[" looted"]
local L_PER_LOOT = L[" per loot"]
local L_NPC, L_OBJECT = L["NPC %s"], L["Object %s"] -- a mob or node never named
local mobOpts, mobFilter = {}, {}

local MOB_SORTS = { ah = SORTS.ah, name = SORTS.name, perLoot = descendingKnown("perLoot") }

-- Under the value sorts a mob that dropped nothing goes last; by name the
-- order is plain.
local function mobSort(key)
  if key == "name" then return MOB_SORTS.name end
  return sortsLastAfter(MOB_SORTS[key] or MOB_SORTS.ah)
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

-- The places of a mob, most loot first (ties by name), at most `n`.
local function topPlaces(places, n)
  local list = {}
  for p, count in pairs(places) do list[#list + 1] = { name = p, n = count } end
  table.sort(list, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return a.name < b.name
  end)
  for i = #list, n + 1, -1 do list[i] = nil end
  return list
end

local L_LOOTED = L["Looted: "]
local L_PER_LOOT_LABEL = L["Per loot: "]
local L_WHERE = L["Where"]
local L_BEST_DROPS = L["Best drops"]
local L_DROP_CHANCES = L["Drop chance (%d looted)"]
local MOB_TIP_LINES = 3

-- A drop chance as text: "35%", one decimal under 10% ("2.5%"), "<0.1%"
-- below that; nil without data (`seen` corpses, `n` of them had the item).
function View.dropChanceText(n, seen)
  if not (num(n) and num(seen) and seen > 0 and n > 0) then return nil end
  local pct = 100 * math.min(n, seen) / seen
  if pct < 0.1 then return "<0.1%" end
  if pct < 10 then return string.format("%.1f%%", pct) end
  return string.format("%d%%", math.floor(pct + 0.5))
end

-- The item rows with a drop chance, likeliest first (ties by name), at most `n`.
function View.likelyDrops(rows, n)
  local list = {}
  for _, r in ipairs(rows) do
    if num(r.dropCount) and num(r.dropSeen) and r.dropSeen > 0 then list[#list + 1] = r end
  end
  table.sort(list, function(a, b)
    local ca, cb = a.dropCount / a.dropSeen, b.dropCount / b.dropSeen
    if ca ~= cb then return ca > cb end
    return byName(a, b)
  end)
  for i = #list, n + 1, -1 do list[i] = nil end
  return list
end

-- A mob row's tooltip (ns.Tooltip): how often it was looted, its value, raw
-- gold and value per loot, where it was looted most and its best drops.
-- `fig` = { looted, value, gold, perLoot, places, items (its item rows) }.
local function mobHint(fig, label, open)
  local Tip = ns.Tooltip
  local tip = Tip.new(label)
  Tip.pair(tip, L_LOOTED, tostring(fig.looted))
  Tip.money(tip, L_VALUE, fig.value)
  if fig.gold > 0 then Tip.money(tip, L_RAW_GOLD, fig.gold) end
  if fig.perLoot then Tip.money(tip, L_PER_LOOT_LABEL, math.floor(fig.perLoot + 0.5)) end
  local places = topPlaces(fig.places, MOB_TIP_LINES)
  if #places > 0 then
    Tip.section(tip, L_WHERE)
    for _, p in ipairs(places) do Tip.pair(tip, p.name, p.n .. L_N_LOOTED) end
  end
  local best = topRows(fig.items, MOB_TIP_LINES)
  if #best > 0 then Tip.section(tip, L_BEST_DROPS) end
  for _, r in ipairs(best) do
    local chance = View.dropChanceText(r.dropCount, r.dropSeen)
    Tip.money(tip, r.name .. " x" .. r.quantity .. (chance and ("  " .. chance) or ""), r.value)
  end
  -- The likeliest drops, from the corpses whose loot window was read.
  local likely = View.likelyDrops(fig.items, MOB_TIP_LINES)
  if #likely > 0 then
    Tip.section(tip, string.format(L_DROP_CHANCES, fig.seen))
    for _, r in ipairs(likely) do
      Tip.pair(tip, r.name, View.dropChanceText(r.dropCount, r.dropSeen))
    end
  end
  Tip.hint(tip, open and L_CLICK_CLOSE or L_CLICK_OPEN)
  return tip
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
        if type(key) == "string" and type(m) == "table" and num(m.looted) and num(m.gold) then
          local a = all[key]
          if not a then
            a = { kind = m.kind == "node" and "node" or "npc", looted = 0, gold = 0, items = {}, places = {} }
            all[key] = a
          end
          -- The newest name: the first History entry's, the running session's
          -- (last) over all.
          if type(m.name) == "string" and m.name ~= "" and (a.name == nil or e.live) then a.name = m.name end
          a.looted, a.gold = a.looted + m.looted, a.gold + m.gold
          for itemKey, qty in pairs(type(m.items) == "table" and m.items or NO_LOOKUP) do
            local src = num(qty) and qty > 0 and mobItemSource(e, itemKey)
            if src then addZoneItem(a.items, src, itemKey, qty) end
          end
          for p, n in pairs(type(m.places) == "table" and m.places or NO_LOOKUP) do
            if type(p) == "string" and num(n) then a.places[p] = (a.places[p] or 0) + n end
          end
          -- Drop chances: only data that recorded `seen` (older data has none).
          if num(m.seen) and m.seen > 0 then
            a.seen = (a.seen or 0) + m.seen
            if not a.drops then a.drops = {} end
            for itemKey, n in pairs(type(m.drops) == "table" and m.drops or NO_LOOKUP) do
              if num(n) and n > 0 then a.drops[itemKey] = (a.drops[itemKey] or 0) + n end
            end
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
    for _, r in ipairs(items) do
      local n = a.drops and a.drops[r.key]
      if n then r.dropCount, r.dropSeen = n, a.seen end
    end
    local gold = withGold and a.gold or 0
    local value = t.best + gold
    local label = a.name or ((a.kind == "node" and L_OBJECT or L_NPC):format(key:match(":(%d+)$") or "?"))
    local isOpen = key == openKey
    local perLoot = a.looted > 0 and value / a.looted or nil
    local parts = { a.looted .. L_N_LOOTED }
    if perLoot then parts[#parts + 1] = ns.Money.format(math.floor(perLoot + 0.5)) .. L_PER_LOOT end
    local place = mainPlace(a.places)
    if place then parts[#parts + 1] = View.shortPlace(place) end
    local fig = { looted = a.looted, value = value, gold = a.gold, perLoot = perLoot, places = a.places,
      items = items, seen = a.seen }
    local row = {
      id = 0, key = "m:" .. key, mobKey = key, looted = a.looted, perLoot = perLoot,
      -- For the CSV export (View.mobsCsv).
      label = label, kind = a.kind, gold = a.gold, place = place, itemCount = #items,
      name = (isOpen and "- " or "+ ") .. label, detail = detailText(parts), sortName = lower(label),
      quality = 1, sortsLast = value <= 0,
      vendorTotal = t.vendor, ahTotal = t.ah, bestLineTotal = value, value = value,
      icon = a.kind == "node" and ns.Theme.textures.node or ns.Theme.textures.mob,
      hint = function() return mobHint(fig, label, isOpen) end,
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
    empty = View.emptyText(rows, filter, L_NO_MOBS),
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
          local perHour = ns.History.perHour(value, s.time)
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
-- CSV export of History Zones (/al export zones).

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
          gold = s.gold, perHour = ns.History.perHour(value, s.time), count = #rows }
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

-- ---------------------------------------------------------------------------
-- Drop chances for the game's item tooltips (UI/ItemTooltip.lua).

-- The item ID of a drops key (an item ID, or "<id>:<bonus IDs>").
local function idOfKey(key)
  return tonumber(key) or tonumber(tostring(key):match("^(%d+)"))
end

-- Who drops what, over the Mobs entries (History plus the running session,
-- like History > Mobs): { [itemID] = { { key, name, kind, n, seen }, ... } },
-- `n` the corpses of that mob that had the item (variants of an item added
-- up), `seen` the mob's corpses whose loot was read. Only data with `seen`
-- (recorded since drop chances exist) counts.
function View.dropIndex(entries)
  local mobs = {}
  for _, e in ipairs(type(entries) == "table" and entries or {}) do
    if type(e) == "table" and type(e.mobs) == "table" then
      for key, m in pairs(e.mobs) do
        if type(key) == "string" and type(m) == "table" and num(m.seen) and m.seen > 0 then
          local a = mobs[key]
          if not a then
            a = { kind = m.kind == "node" and "node" or "npc", seen = 0, drops = {} }
            mobs[key] = a
          end
          -- The newest name, as in History > Mobs.
          if type(m.name) == "string" and m.name ~= "" and (a.name == nil or e.live) then a.name = m.name end
          a.seen = a.seen + m.seen
          for itemKey, n in pairs(type(m.drops) == "table" and m.drops or NO_LOOKUP) do
            local id = idOfKey(itemKey)
            if id and num(n) and n > 0 then a.drops[id] = (a.drops[id] or 0) + n end
          end
        end
      end
    end
  end
  local index = {}
  for key, a in pairs(mobs) do
    local name = a.name or ((a.kind == "node" and L_OBJECT or L_NPC):format(key:match(":(%d+)$") or "?"))
    for id, n in pairs(a.drops) do
      local list = index[id]
      if not list then
        list = {}
        index[id] = list
      end
      list[#list + 1] = { key = key, name = name, kind = a.kind, n = math.min(n, a.seen), seen = a.seen }
    end
  end
  -- Likeliest first; ties: more corpses seen (a surer number), then name.
  for _, list in pairs(index) do
    table.sort(list, function(a, b)
      local ca, cb = a.n / a.seen, b.n / b.seen
      if ca ~= cb then return ca > cb end
      if a.seen ~= b.seen then return a.seen > b.seen end
      return a.name < b.name
    end)
  end
  return index
end

View.DROP_TOOLTIP_LINES = 4
local L_DROPS_FROM = L["AnotherLedger drop chance"]
local L_DROP_OF = L["%s (%d of %d)"]
local L_MORE_SOURCES = L["and %d more"]

-- The lines an item tooltip gets: a heading, then up to `max` mobs as
-- { left = name, right = "35% (7 of 20)" } and a "and N more" line; nil
-- when nothing is known about the item.
function View.dropTooltipLines(index, itemID, max)
  local list = type(index) == "table" and index[itemID]
  if type(list) ~= "table" or #list == 0 then return nil end
  max = max or View.DROP_TOOLTIP_LINES
  local lines = { { left = L_DROPS_FROM, heading = true } }
  for i = 1, math.min(max, #list) do
    local s = list[i]
    lines[#lines + 1] = { left = s.name, right = L_DROP_OF:format(View.dropChanceText(s.n, s.seen), s.n, s.seen) }
  end
  if #list > max then lines[#lines + 1] = { left = L_MORE_SOURCES:format(#list - max), more = true } end
  return lines
end

-- Every mob of the History Mobs data (no filter, by value): name, kind (npc
-- or node), corpses looted, value (items plus raw gold when it counts), raw
-- gold, value per loot, main place and how many different items.
View.MOBS_CSV_HEADER = "mob,kind,looted,value_g,raw_gold_g,per_loot_g,main_place,items"
local mobsCsvOpts = {}

function View.mobsCsv(entries, opts)
  copyOpts(mobsCsvOpts, opts or {})
  mobsCsvOpts.filter, mobsCsvOpts.sort = nil, "ah"
  local History = ns.History
  local field, gold = History.csvField, History.goldNumber
  local out = { View.MOBS_CSV_HEADER }
  for _, r in ipairs(View.buildMobs(entries, mobsCsvOpts).rows) do
    if r.mobKey then
      out[#out + 1] = table.concat({
        field(r.label), r.kind, tostring(r.looted), gold(r.value), gold(r.gold),
        r.perLoot and gold(r.perLoot) or "", r.place and field(r.place) or "", tostring(r.itemCount),
      }, ",")
    end
  end
  return table.concat(out, "\n")
end
