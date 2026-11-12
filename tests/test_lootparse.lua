local h = ...
local ns = h.load({ "LootParse.lua" })

local G = {
  LOOT_ITEM_SELF = "You receive loot: %s.",
  LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d.",
  LOOT_ITEM_PUSHED_SELF = "You receive item: %s.",
  LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d.",
  LOOT_ITEM_CREATED_SELF = "You create: %s.",
  LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d.",
}
local L = "|cff1eff00|Hitem:3356::::::::60:::::|h[Kingsblood]|h|r"
local L2 = "|cffffffff|Hitem:1::::::::60:::::|h[Potion (100%) of x2]|h|r"
local c = ns.LootParse.compile(G)

local function check(msg, link, qty)
  local l, q = ns.LootParse.parse(c, msg)
  h.eq(l, link)
  h.eq(q, qty)
end

h.test("LootParse single/multiple/pushed/created", function()
  check("You receive loot: " .. L .. ".", L, 1)
  check("You receive loot: " .. L .. "x5.", L, 5)
  check("You receive item: " .. L .. ".", L, 1)
  check("You receive item: " .. L .. "x5.", L, 5)
  check("You create: " .. L .. ".", L, 1)
  check("You create: " .. L .. "x5.", L, 5)
end)

h.test("LootParse special characters in name", function()
  check("You receive loot: " .. L2 .. ".", L2, 1)
  check("You receive loot: " .. L2 .. "x3.", L2, 3)
end)

h.test("LootParse rejects others", function()
  check("Bob receives loot: " .. L .. ".", nil, nil)
  check("You receive loot: |cffffffff|Hcurrency:1|h[Honor]|h|r.", nil, nil)
  check("", nil, nil)
end)

h.test("LootParse.itemID", function()
  h.eq(ns.LootParse.itemID(L), 3356)
  h.eq(ns.LootParse.itemID("nonsense"), nil)
end)
