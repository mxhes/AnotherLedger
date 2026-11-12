local ADDON, ns = ...

-- Pure inventory scan: turns the bag / bank slots of a client environment into
-- the same `items` map a session holds ({ [itemID] = { id, link, qty, lastSeen } }),
-- merging every stack of one item into one entry. The engine globals are read
-- from the injected `env` (_G in the client), so everything is testable.
local Inventory = {
  BANK_STALE_SECONDS = 12 * 3600,
}

local function num(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function count(v)
  return num(v) and v > 0 and v or 0
end

-- Bag container ids: backpack 0, the carried bags and (where the client has
-- one) the reagent bag. UNVERIFIED (check in client): NUM_BAG_SLOTS /
-- NUM_REAGENTBAG_SLOTS values on Forever.
function Inventory.bagIDs(env)
  local ids = { 0 }
  local bags = count(env.NUM_BAG_SLOTS)
  if bags == 0 then bags = 4 end
  for i = 1, bags do ids[#ids + 1] = i end
  local reagent = count(env.NUM_REAGENTBAG_SLOTS)
  for i = bags + 1, bags + reagent do ids[#ids + 1] = i end
  return ids
end

-- Bank container ids: the bank itself (BANK_CONTAINER, -1) and the bank bag
-- slots after the carried bags. UNVERIFIED (check in client): BANK_CONTAINER and
-- NUM_BANKBAGSLOTS on Forever.
function Inventory.bankIDs(env)
  local ids = { num(env.BANK_CONTAINER) and env.BANK_CONTAINER or -1 }
  local first = count(env.NUM_BAG_SLOTS)
  if first == 0 then first = 4 end
  first = first + count(env.NUM_REAGENTBAG_SLOTS)
  local bankBags = count(env.NUM_BANKBAGSLOTS)
  if bankBags == 0 then bankBags = 7 end
  for i = first + 1, first + bankBags do ids[#ids + 1] = i end
  return ids
end

-- entries = list of { id, link, qty }; invalid entries are skipped. Returns an
-- items map with the stacks of one item id merged.
function Inventory.merge(entries, now)
  local items = {}
  for _, e in ipairs(entries) do
    if type(e) == "table" and num(e.id) and e.id > 0 and num(e.qty) and e.qty > 0 then
      local item = items[e.id]
      if not item then
        item = { id = e.id, link = nil, qty = 0, lastSeen = now }
        items[e.id] = item
      end
      item.qty = item.qty + e.qty
      if type(e.link) == "string" and item.link == nil then item.link = e.link end
    end
  end
  return items
end

-- Reads every slot of the given containers through C_Container. A missing API
-- or a failing call gives an empty / partial result, never an error.
-- UNVERIFIED (check in client): C_Container.GetContainerItemInfo returns
-- { itemID, stackCount, hyperlink } on Forever.
function Inventory.scan(env, containerIDs, now)
  local api = env.C_Container
  if type(api) ~= "table" or type(api.GetContainerNumSlots) ~= "function"
      or type(api.GetContainerItemInfo) ~= "function" then
    return {}
  end
  local entries = {}
  for _, bag in ipairs(containerIDs) do
    local ok, slots = pcall(api.GetContainerNumSlots, bag)
    if ok and num(slots) then
      for slot = 1, slots do
        local okInfo, info = pcall(api.GetContainerItemInfo, bag, slot)
        if okInfo and type(info) == "table" then
          entries[#entries + 1] = { id = info.itemID, link = info.hyperlink, qty = info.stackCount }
        end
      end
    end
  end
  return Inventory.merge(entries, now)
end

function Inventory.scanBags(env, now)
  return Inventory.scan(env, Inventory.bagIDs(env), now)
end

function Inventory.scanBank(env, now)
  return Inventory.scan(env, Inventory.bankIDs(env), now)
end

local L_NEVER = "Open your bank once to scan it."
local L_SCANNED = "Scanned "
local L_AGO = " ago"
local L_JUST_NOW = "Scanned just now"

-- Note under the bank list: when the saved scan was taken. `scannedAt` 0 / nil
-- means never. Returns the text and whether it is stale (older than 12 h).
function Inventory.scanNote(now, scannedAt)
  if not num(scannedAt) or scannedAt <= 0 then return L_NEVER, false end
  local age = math.max(0, now - scannedAt)
  local stale = age >= Inventory.BANK_STALE_SECONDS
  if age < 60 then return L_JUST_NOW, stale end
  local text
  if age < 3600 then
    text = math.floor(age / 60) .. "m"
  elseif age < 86400 then
    text = math.floor(age / 3600) .. "h"
  else
    text = math.floor(age / 86400) .. "d"
  end
  return L_SCANNED .. text .. L_AGO, stale
end

ns.Inventory = Inventory
