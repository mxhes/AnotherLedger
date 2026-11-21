local ADDON, ns = ...

local L = ns.L

-- Pure inventory scan: turns the bag / bank slots of a client environment into
-- the same `items` map a session holds ({ [key] = { id, key, link, qty, lastSeen } },
-- key = LootParse.itemKey), merging every stack of one item variant into one entry. The engine globals are read
-- from the injected `env` (_G in the client), so everything is testable.
local Inventory = {
  -- Default age after which the bank scan note turns orange; the option
  -- "staleHours" overrides it (Inventory.scanNote's third argument).
  BANK_STALE_SECONDS = 12 * 3600,
  BANK_TABS = 6,
}

local num, count = ns.Util.isNumber, ns.Util.nonNegative

-- Bag container ids: backpack 0, the carried bags and (where the client has
-- one) the reagent bag.
function Inventory.bagIDs(env)
  local ids = { 0 }
  local bags = count(env.NUM_BAG_SLOTS)
  if bags == 0 then bags = 4 end
  for i = 1, bags do ids[#ids + 1] = i end
  local reagent = count(env.NUM_REAGENTBAG_SLOTS)
  for i = bags + 1, bags + reagent do ids[#ids + 1] = i end
  return ids
end

local function bagIndex(env)
  local E = env.Enum
  return type(E) == "table" and type(E.BagIndex) == "table" and E.BagIndex or nil
end

-- Bank container ids. Clients with character bank tabs (retail 11.2 and
-- later: Enum.BagIndex.CharacterBankTab_1..6) scan those tabs; older ones the
-- bank itself (BANK_CONTAINER, -1), the bank bag slots after the carried bags
-- and the reagent bank (REAGENTBANK_CONTAINER, -3) where it exists. The
-- account-wide warband bank is not scanned.
function Inventory.bankIDs(env)
  local E = bagIndex(env)
  if E and num(E.CharacterBankTab_1) then
    local tabs = {}
    for i = 1, Inventory.BANK_TABS do
      local id = E["CharacterBankTab_" .. i]
      if num(id) then tabs[#tabs + 1] = id end
    end
    return tabs
  end
  local ids = { num(env.BANK_CONTAINER) and env.BANK_CONTAINER or -1 }
  local first = count(env.NUM_BAG_SLOTS)
  if first == 0 then first = 4 end
  first = first + count(env.NUM_REAGENTBAG_SLOTS)
  local bankBags = count(env.NUM_BANKBAGSLOTS)
  if bankBags == 0 then bankBags = 7 end
  for i = first + 1, first + bankBags do ids[#ids + 1] = i end
  local reagent = (E and num(E.Reagentbank) and E.Reagentbank) or env.REAGENTBANK_CONTAINER
  if num(reagent) then ids[#ids + 1] = reagent end
  return ids
end

-- Adds one stack to an items map; an invalid id or quantity is skipped.
-- Stacks are merged per item variant (LootParse.itemKey of the link); the
-- first link seen for a variant is kept. `bound`: this stack is soulbound
-- (an equipped BoE item); the entry is `bound` while every stack of it is.
local function addStack(items, id, link, qty, now, bound)
  if not (num(id) and id > 0 and num(qty) and qty > 0) then return end
  local key = id
  if type(link) == "string" and ns.LootParse then
    local k, linkID = ns.LootParse.itemKey(link)
    if k and linkID == id then key = k end
  end
  local item = items[key]
  if not item then
    item = { id = id, key = key, link = nil, qty = 0, lastSeen = now, bound = bound == true or nil }
    items[key] = item
  else
    if bound ~= true then item.bound = nil end
  end
  item.qty = item.qty + qty
  if item.link == nil and type(link) == "string" then item.link = link end
end

-- Reads every slot of the given containers through C_Container. A missing API
-- or a failing call gives an empty / partial result, never an error.
-- C_Container.GetContainerItemInfo returns { itemID, stackCount, hyperlink,
-- isBound }.
function Inventory.scan(env, containerIDs, now)
  local api = env.C_Container
  if type(api) ~= "table" or type(api.GetContainerNumSlots) ~= "function"
      or type(api.GetContainerItemInfo) ~= "function" then
    return {}
  end
  local items = {}
  for _, bag in ipairs(containerIDs) do
    local ok, slots = pcall(api.GetContainerNumSlots, bag)
    if ok and num(slots) then
      for slot = 1, slots do
        local okInfo, info = pcall(api.GetContainerItemInfo, bag, slot)
        if okInfo and type(info) == "table" then
          addStack(items, info.itemID, info.hyperlink, info.stackCount, now, info.isBound)
        end
      end
    end
  end
  return items
end

-- Free and total slots of the bags (Inventory.bagIDs); 0, 0 without the API.
function Inventory.freeSlots(env)
  local api = env.C_Container
  if type(api) ~= "table" or type(api.GetContainerNumFreeSlots) ~= "function"
      or type(api.GetContainerNumSlots) ~= "function" then
    return 0, 0
  end
  local free, total = 0, 0
  for _, bag in ipairs(Inventory.bagIDs(env)) do
    local ok, n = pcall(api.GetContainerNumFreeSlots, bag)
    if ok and num(n) then free = free + n end
    local okSlots, slots = pcall(api.GetContainerNumSlots, bag)
    if okSlots and num(slots) then total = total + slots end
  end
  return free, total
end

function Inventory.scanBags(env, now)
  return Inventory.scan(env, Inventory.bagIDs(env), now)
end

function Inventory.scanBank(env, now)
  return Inventory.scan(env, Inventory.bankIDs(env), now)
end

local L_NEVER = L["Open your bank once to scan it."]
local L_SCANNED = L["Scanned "]
local L_AGO = L[" ago"]
local L_JUST_NOW = L["Scanned just now"]

-- Note under the bank list: when the saved scan was taken. `scannedAt` 0 / nil
-- means never. Returns the text and whether it is stale (older than
-- `staleSeconds`, default BANK_STALE_SECONDS).
function Inventory.scanNote(now, scannedAt, staleSeconds)
  if not num(scannedAt) or scannedAt <= 0 then return L_NEVER, false end
  local age = math.max(0, now - scannedAt)
  local limit = num(staleSeconds) and staleSeconds > 0 and staleSeconds or Inventory.BANK_STALE_SECONDS
  local stale = age >= limit
  if age < 60 then return L_JUST_NOW, stale end
  return L_SCANNED .. ns.Util.shortAge(age) .. L_AGO, stale
end

ns.Inventory = Inventory
