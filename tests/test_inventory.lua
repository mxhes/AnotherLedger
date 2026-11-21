local h = ...
local ns = h.load({ "Util.lua", "LootParse.lua", "Inventory.lua" })
local I = ns.Inventory

local function link(id) return "|cffffffff|Hitem:" .. id .. "::|h[Item" .. id .. "]|h|r" end

-- Inventory.scan over one bag (container 0) holding `slots` = { { id, link, qty } or false, ... }.
local function scanOf(slots, now)
  local env = { C_Container = {
    GetContainerNumSlots = function() return #slots end,
    GetContainerItemInfo = function(_, slot)
      local s = slots[slot]
      if not s then return nil end
      return { itemID = s.id, hyperlink = s.link, stackCount = s.qty }
    end,
  } }
  return I.scan(env, { 0 }, now)
end

h.test("Inventory.scan: stacks of one item merge, invalid slots are skipped", function()
  local items = scanOf({
    { id = 10, link = link(10), qty = 5 },
    { id = 10, link = link(10), qty = 3 },
    { id = 11, link = link(11), qty = 1 },
    { id = 12, qty = 0 },
    { id = "x", qty = 2 },
    { id = 13, qty = -1 },
    false,
  }, 777)
  h.eq(items[10], { id = 10, key = 10, link = link(10), qty = 8, lastSeen = 777 })
  h.eq(items[11].qty, 1)
  h.eq(items[12], nil)
  h.eq(items[13], nil)
end)

h.test("Inventory.bagIDs / bankIDs follow the client constants", function()
  h.eq(I.bagIDs({}), { 0, 1, 2, 3, 4 })
  h.eq(I.bagIDs({ NUM_BAG_SLOTS = 4, NUM_REAGENTBAG_SLOTS = 1 }), { 0, 1, 2, 3, 4, 5 })
  h.eq(I.bankIDs({ BANK_CONTAINER = -1, NUM_BAG_SLOTS = 4, NUM_BANKBAGSLOTS = 2 }), { -1, 5, 6 })
  h.eq(I.bankIDs({ BANK_CONTAINER = -1, NUM_BAG_SLOTS = 4, NUM_REAGENTBAG_SLOTS = 1, NUM_BANKBAGSLOTS = 2 }),
    { -1, 6, 7 })
  h.eq(I.bankIDs({ BANK_CONTAINER = -1, NUM_BAG_SLOTS = 4, NUM_BANKBAGSLOTS = 2, REAGENTBANK_CONTAINER = -3 }),
    { -1, 5, 6, -3 })
end)

h.test("Inventory.bankIDs uses the character bank tabs where the client has them", function()
  local env = { Enum = { BagIndex = { CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8,
    CharacterBankTab_4 = 9, CharacterBankTab_5 = 10, CharacterBankTab_6 = 11, AccountBankTab_1 = 12 } },
    BANK_CONTAINER = -1, NUM_BANKBAGSLOTS = 7 }
  h.eq(I.bankIDs(env), { 6, 7, 8, 9, 10, 11 })
end)

h.test("Inventory.scan keeps item variants (bonus IDs) apart", function()
  local plain = "|Hitem:50::::::::60:::::::::|h[Sword]|h"
  local v1 = "|Hitem:50::::::::60::::2:1477:4802::::::|h[Sword]|h"
  local v2 = "|Hitem:50::::::::60::::1:9999::::::|h[Sword]|h"
  local items = scanOf({
    { id = 50, link = plain, qty = 1 },
    { id = 50, link = v1, qty = 1 },
    { id = 50, link = v1, qty = 1 },
    { id = 50, link = v2, qty = 1 },
  }, 1)
  h.eq(items[50].qty, 1)
  h.eq(items["50:1477:4802"].qty, 2)
  h.eq(items["50:1477:4802"].id, 50)
  h.eq(items["50:9999"].qty, 1)
end)

h.test("Inventory.scanNote follows a given stale limit", function()
  local _, stale = I.scanNote(10000, 10000 - 3700, 3600)
  h.eq(stale, true)
  _, stale = I.scanNote(10000, 10000 - 3700)
  h.eq(stale, false)
end)

local function fakeEnv(bags)
  return {
    C_Container = {
      GetContainerNumSlots = function(bag) return bags[bag] and bags[bag].n or 0 end,
      GetContainerItemInfo = function(bag, slot)
        local s = bags[bag] and bags[bag][slot]
        if not s then return nil end
        return { itemID = s[1], stackCount = s[2], hyperlink = link(s[1]) }
      end,
    },
  }
end

h.test("Inventory.scanBags merges across bags and skips empty slots", function()
  local env = fakeEnv({
    [0] = { n = 3, { 10, 5 }, nil, { 11, 1 } },
    [1] = { n = 2, { 10, 20 } },
    [9] = { n = 1, { 99, 1 } }, -- not a bag id
  })
  local items = I.scanBags(env, 50)
  h.eq(items[10].qty, 25)
  h.eq(items[11].qty, 1)
  h.eq(items[99], nil)
  h.eq(items[10].lastSeen, 50)
end)

h.test("Inventory.scanBank reads the bank container and bank bags", function()
  local env = fakeEnv({
    [-1] = { n = 2, { 20, 2 }, { 21, 4 } },
    [5] = { n = 1, { 20, 3 } },
    [0] = { n = 1, { 10, 1 } },
  })
  local items = I.scanBank(env, 1)
  h.eq(items[20].qty, 5)
  h.eq(items[21].qty, 4)
  h.eq(items[10], nil)
end)

h.test("Inventory.scan survives a missing API and failing calls", function()
  h.eq(I.scanBags({}, 1), {})
  local env = { C_Container = {
    GetContainerNumSlots = function() error("boom") end,
    GetContainerItemInfo = function() error("boom") end,
  } }
  h.eq(I.scanBags(env, 1), {})
  local env2 = { C_Container = {
    GetContainerNumSlots = function() return 2 end,
    GetContainerItemInfo = function(_, slot)
      if slot == 1 then error("boom") end
      return { itemID = 7, stackCount = 2, hyperlink = link(7) }
    end,
  } }
  h.eq(I.scanBags(env2, 1)[7].qty, 2 * 5) -- slot 2 of each of the 5 bags
end)

h.test("Inventory.scanNote: never, just now, minutes, hours, days, stale", function()
  h.eq({ I.scanNote(1000, nil) }, { "Open your bank once to scan it.", false })
  h.eq({ I.scanNote(1000, 0) }, { "Open your bank once to scan it.", false })
  h.eq({ I.scanNote(1000, 990) }, { "Scanned just now", false })
  h.eq({ I.scanNote(1000 + 600, 1000) }, { "Scanned 10m ago", false })
  h.eq({ I.scanNote(1000 + 3 * 3600, 1000) }, { "Scanned 3h ago", false })
  h.eq({ I.scanNote(1000 + 13 * 3600, 1000) }, { "Scanned 13h ago", true })
  h.eq({ I.scanNote(1000 + 2 * 86400, 1000) }, { "Scanned 2d ago", true })
  h.eq({ I.scanNote(500, 1000) }, { "Scanned just now", false }) -- clock went back
end)

h.test("Inventory.scan merges stacks straight from the slots and keeps the first link", function()
  local slots = {
    { itemID = 7, stackCount = 3, hyperlink = "first" },
    { itemID = 7, stackCount = 4, hyperlink = "second" },
    { itemID = 0, stackCount = 4 },   -- invalid id
    { itemID = 8, stackCount = 0 },   -- empty stack
    { itemID = 9, stackCount = 1 },
  }
  local env = { C_Container = {
    GetContainerNumSlots = function() return #slots end,
    GetContainerItemInfo = function(_, slot) return slots[slot] end,
  } }
  local items = I.scan(env, { 0 }, 50)
  h.eq(items, {
    [7] = { id = 7, key = 7, link = "first", qty = 7, lastSeen = 50 },
    [9] = { id = 9, key = 9, qty = 1, lastSeen = 50 },
  })
end)

h.test("Inventory.scan marks an item bound only while every stack of it is soulbound", function()
  local slots = {
    { itemID = 7, stackCount = 1, isBound = true },
    { itemID = 8, stackCount = 1, isBound = true },
    { itemID = 8, stackCount = 1, isBound = false },
  }
  local env = { C_Container = {
    GetContainerNumSlots = function() return #slots end,
    GetContainerItemInfo = function(_, slot) return slots[slot] end,
  } }
  local items = I.scan(env, { 0 }, 50)
  h.eq(items[7].bound, true)
  h.eq(items[8].bound, nil)
end)

h.test("Inventory.freeLevel: orange at five free slots or fewer, red at two", function()
  local I = ns.Inventory
  h.eq(I.freeLevel(10), nil)
  h.eq(I.freeLevel(5), "few")
  h.eq(I.freeLevel(3), "few")
  h.eq(I.freeLevel(2), "low")
  h.eq(I.freeLevel(0), "low")
  h.eq(I.freeLevel(nil), nil)
end)
