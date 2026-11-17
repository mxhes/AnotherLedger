local ADDON, ns = ...

local num = ns.Util.isNumber

-- What each mob (by NPC ID) and gathering node (by object ID) dropped, how
-- often it was looted and how many the group killed. Pure: the loot window
-- and combat log calls are passed in (Core wires them). Shape of `mobs`
-- (session.mobs and History entries):
--   mobs[key] = { name, kind = "npc" | "node", kills, looted, gold,
--                 items = { [itemKey] = qty }, places = { [place] = n } }
-- `key` is "npc:<id>" or "obj:<id>". `state` is the caller's per-login
-- bookkeeping (GUIDs seen), never saved.
local Mobs = {}
ns.Mobs = Mobs

-- Per-login GUID sets are emptied once they grow this large (long sessions).
local MAX_GUIDS = 5000

local GUID_KINDS = { Creature = "npc", Vehicle = "npc", GameObject = "node" }

-- "Creature-0-3110-0-12-2546-000012ABCD" -> "npc:2546", "npc";
-- "GameObject-...-1731-..." -> "obj:1731", "node"; anything else nil.
function Mobs.idOf(guid)
  if type(guid) ~= "string" then return nil end
  -- One match, no table: the combat log and mouseover call this often.
  local prefix, idText = guid:match("^([^%-]+)%-[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-([^%-]+)")
  local kind = GUID_KINDS[prefix]
  local id = tonumber(idText)
  if not (kind and id) then return nil end
  return (kind == "node" and "obj:" or "npc:") .. id, kind
end

local function call(env, name, ...)
  local fn = env[name]
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

local LOOT_SLOT_ITEM, LOOT_SLOT_MONEY = 1, 2

-- One loot window slot: { kind = "item" | "money", link, qty, sources =
-- { { guid, qty }, ... } }, or nil (currency, empty, no API). A money slot's
-- qty is its copper, the sum of its sources.
-- UNVERIFIED (check in client) on Forever: GetLootSlotType, GetLootSlotLink,
-- GetLootSlotInfo (3rd return the quantity) and GetLootSourceInfo (guid, qty
-- pairs, copper for money).
function Mobs.readSlot(env, slot)
  local ok, slotType = call(env, "GetLootSlotType", slot)
  if not ok or (slotType ~= LOOT_SLOT_ITEM and slotType ~= LOOT_SLOT_MONEY) then return nil end
  local okInfo, _, _, quantity = call(env, "GetLootSlotInfo", slot)
  local qty = okInfo and num(quantity) and quantity or 0
  local sources = {}
  local okSrc, packed = false, nil
  if type(env.GetLootSourceInfo) == "function" then
    packed = { pcall(env.GetLootSourceInfo, slot) }
    okSrc = packed[1]
  end
  if okSrc then
    local i = 2
    while type(packed[i]) == "string" do
      sources[#sources + 1] = { guid = packed[i], qty = num(packed[i + 1]) and packed[i + 1] or nil }
      i = i + 2
    end
  end
  -- A single source without its quantity has the whole slot.
  if #sources == 1 and sources[1].qty == nil then sources[1].qty = qty end
  for i = #sources, 1, -1 do
    if not num(sources[i].qty) then table.remove(sources, i) end
  end
  if slotType == LOOT_SLOT_MONEY then
    local copper = 0
    for _, s in ipairs(sources) do copper = copper + s.qty end
    return { kind = "money", qty = copper, sources = sources }
  end
  local okLink, link = call(env, "GetLootSlotLink", slot)
  if not (okLink and type(link) == "string") then return nil end
  return { kind = "item", link = link, qty = qty, sources = sources }
end

local function entry(mobs, key, kind)
  local e = mobs[key]
  if not e then
    e = { kind = kind, kills = 0, looted = 0, gold = 0, items = {}, places = {} }
    mobs[key] = e
  end
  return e
end

local function kindOf(key)
  return type(key) == "string" and key:sub(1, 4) == "obj:" and "node" or "npc"
end

local function guidSet(state, field)
  local set = state[field]
  if type(set) ~= "table" or (state[field .. "N"] or 0) >= MAX_GUIDS then
    set = {}
    state[field], state[field .. "N"] = set, 0
  end
  return set
end

local function remember(state, field, guid)
  local set = guidSet(state, field)
  if set[guid] then return false end
  set[guid] = true
  state[field .. "N"] = (state[field .. "N"] or 0) + 1
  return true
end

-- `looted` counts each corpse or node (GUID) once. Returns true for a new one.
function Mobs.noteLooted(mobs, key, guid, state)
  local e = entry(mobs, key, kindOf(key))
  if type(guid) == "string" and remember(state, "lootedGUIDs", guid) then
    e.looted = e.looted + 1
    return true
  end
  return false
end

-- A money slot with every source's copper scaled by `factor` (your share in
-- a group); other slots unchanged. A new table.
function Mobs.scaleMoney(slot, factor)
  if type(slot) ~= "table" or slot.kind ~= "money" or not num(factor) then return slot end
  local sources, total = {}, 0
  for i, s in ipairs(slot.sources or {}) do
    local q = num(s.qty) and math.floor(s.qty * factor + 0.5) or nil
    sources[i] = { guid = s.guid, qty = q }
    total = total + (q or 0)
  end
  return { kind = "money", qty = total, sources = sources }
end

-- One cleared loot slot: each source (a mob or node) gets its own share.
function Mobs.credit(mobs, slot, place, names, state)
  if type(slot) ~= "table" or type(slot.sources) ~= "table" then return end
  local itemKey = slot.kind == "item" and ns.LootParse.itemKey(slot.link) or nil
  if slot.kind == "item" and not itemKey then return end
  for _, s in ipairs(slot.sources) do
    local key, kind = Mobs.idOf(s.guid)
    if key and num(s.qty) and s.qty > 0 then
      local e = entry(mobs, key, kind)
      if itemKey then
        e.items[itemKey] = (e.items[itemKey] or 0) + s.qty
      else
        e.gold = e.gold + s.qty
      end
      local name = type(names) == "table" and names[key] or nil
      if type(name) == "string" and name ~= "" then e.name = name end
      -- A place counts each corpse or node once, like `looted`.
      if Mobs.noteLooted(mobs, key, s.guid, state) and type(place) == "string" then
        e.places[place] = (e.places[place] or 0) + 1
      end
    end
  end
end

function Mobs.addKill(mobs, key, name)
  if type(key) ~= "string" then return end
  local e = entry(mobs, key, kindOf(key))
  e.kills = e.kills + 1
  if type(name) == "string" and name ~= "" then e.name = name end
end

-- Affiliation bits of combat log unit flags: mine, party, raid (0x1 .. 0x4).
local function groupSource(flags)
  return num(flags) and flags % 8 ~= 0
end

-- One combat log event: damage or a miss from the group marks the target as
-- fought; PARTY_KILL from the group, or the death of a fought unit, returns
-- its GUID once.
function Mobs.combat(state, subevent, sourceGUID, sourceFlags, destGUID)
  if type(subevent) ~= "string" or type(destGUID) ~= "string" then return nil end
  if subevent == "PARTY_KILL" then
    if not groupSource(sourceFlags) then return nil end
  elseif subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
    local fought = state.fought
    if not (type(fought) == "table" and fought[destGUID]) then return nil end
  else
    if (subevent:find("_DAMAGE$") or subevent:find("_MISSED$")) and groupSource(sourceFlags) then
      remember(state, "fought", destGUID)
    end
    return nil
  end
  if type(state.fought) == "table" then state.fought[destGUID] = nil end
  if not remember(state, "killed", destGUID) then return nil end
  return destGUID
end

local function validEntry(e)
  return type(e) == "table" and (e.kind == "npc" or e.kind == "node") and num(e.kills) and num(e.looted)
    and num(e.gold) and type(e.items) == "table" and type(e.places) == "table"
end

local function addInto(dst, src)
  for key, e in pairs(src) do
    if type(key) == "string" and validEntry(e) then
      local d = dst[key]
      if not d then
        d = { kind = e.kind, kills = 0, looted = 0, gold = 0, items = {}, places = {} }
        dst[key] = d
      end
      if type(e.name) == "string" and d.name == nil then d.name = e.name end
      d.kills, d.looted, d.gold = d.kills + e.kills, d.looted + e.looted, d.gold + e.gold
      for k, q in pairs(e.items) do
        if num(q) and q > 0 then d.items[k] = (d.items[k] or 0) + q end
      end
      for p, n in pairs(e.places) do
        if type(p) == "string" and num(n) then d.places[p] = (d.places[p] or 0) + n end
      end
    end
  end
  return dst
end

-- A deep copy of the valid entries.
function Mobs.copy(mobs)
  return addInto({}, type(mobs) == "table" and mobs or {})
end

-- The entries of `a` and `b` added up (new table).
function Mobs.merge(a, b)
  local out = Mobs.copy(a)
  return addInto(out, type(b) == "table" and b or {})
end
