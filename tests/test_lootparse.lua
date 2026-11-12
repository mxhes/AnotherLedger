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

local GM = {
  YOU_LOOT_MONEY = "You loot %s",
  LOOT_MONEY_SPLIT = "Your share of the loot is %s.",
  YOU_LOOT_MONEY_GUILD = "You loot %s (%s deposited to guild bank)",
  LOOT_MONEY = "%s loots %s.",
  GOLD_AMOUNT = "%d Gold",
  SILVER_AMOUNT = "%d Silver",
  COPPER_AMOUNT = "%d Copper",
}
local mc = ns.LootParse.compileMoney(GM)
local function money(msg) return ns.LootParse.parseMoney(mc, msg) end

h.test("parseMoney gold, silver and copper together", function()
  h.eq(money("You loot 1 Gold, 23 Silver, 4 Copper"), 12304)
  h.eq(money("You loot 12 Gold, 3 Silver, 45 Copper"), 120345)
end)

h.test("parseMoney any subset of units", function()
  h.eq(money("You loot 5 Silver"), 500)
  h.eq(money("You loot 7 Copper"), 7)
  h.eq(money("You loot 2 Gold"), 20000)
  h.eq(money("You loot 2 Gold, 9 Copper"), 20009)
  h.eq(money("You loot 3 Silver, 9 Copper"), 309)
end)

h.test("parseMoney split share and guild form (first amount only)", function()
  h.eq(money("Your share of the loot is 1 Gold, 2 Silver."), 10200)
  h.eq(money("Your share of the loot is 9 Copper."), 9)
  h.eq(money("You loot 10 Gold (2 Gold deposited to guild bank)"), 100000)
  h.eq(money("You loot 1 Gold, 50 Silver (30 Silver deposited to guild bank)"), 15000)
end)

h.test("parseMoney ignores other players and garbage", function()
  h.eq(money("Bob loots 5 Silver."), nil)
  h.eq(money("Bob loots 1 Gold, 5 Silver."), nil)
  h.eq(money("You loot a sword"), nil)
  h.eq(money("You loot 5 Silverx"), nil)
  h.eq(money("You loot 5 Silver, 5 Silver"), nil)
  h.eq(money("You loot 5 Silver, junk"), nil)
  h.eq(money("You loot "), nil)
  h.eq(money(""), nil)
  h.eq(money(nil), nil)
  h.eq(money(42), nil)
  h.eq(ns.LootParse.parseMoney(nil, "You loot 5 Silver"), nil)
end)

h.test("parseMoney zero amounts are not income", function()
  h.eq(money("You loot 0 Copper"), nil)
  h.eq(money("You loot 0 Gold, 0 Silver, 0 Copper"), nil)
end)

h.test("parseMoney huge amounts", function()
  h.eq(money("You loot 999999 Gold, 99 Silver, 99 Copper"), 9999999999)
end)

h.test("compileMoney skips missing globals", function()
  local empty = ns.LootParse.compileMoney({})
  h.eq(ns.LootParse.parseMoney(empty, "You loot 5 Silver"), nil)
  local noUnits = ns.LootParse.compileMoney({ YOU_LOOT_MONEY = "You loot %s" })
  h.eq(ns.LootParse.parseMoney(noUnits, "You loot 5 Silver"), nil)
  local onlySilver = ns.LootParse.compileMoney({ YOU_LOOT_MONEY = "You loot %s", SILVER_AMOUNT = "%d Silver" })
  h.eq(ns.LootParse.parseMoney(onlySilver, "You loot 5 Silver"), 500)
  h.eq(ns.LootParse.parseMoney(onlySilver, "You loot 5 Gold"), nil)
end)
