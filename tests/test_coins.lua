local h = ...
local ns = h.load({ "Util.lua", "Money.lua", "Theme.lua", "UI/Coins.lua" })
local M, C = ns.Money, ns.UI.Coins

h.test("Money.parts: the shown units, each with its coin, zero as copper", function()
  M.setIcons(false)
  h.eq(M.parts(12345), { gold = "1g", silver = "23s", copper = "45c" })
  h.eq(M.parts(10045), { gold = "1g", copper = "45c" }) -- no silver: no silver part
  h.eq(M.parts(500), { silver = "5s" })
  h.eq(M.parts(0), { copper = "0c" })
  h.eq(M.parts(-250), { silver = "-2s", copper = "50c" }) -- the sign before the first unit
  h.eq(M.parts(nil), nil)
  -- the same units as Money.format, also with the gold-only style
  M.setStyle("gold")
  h.eq(M.parts(12345), { gold = "1g" })
  h.eq(M.parts(345), { silver = "3s", copper = "45c" })
  M.setStyle("full")
  -- colored like formatColored
  local colors = { moneyGold = { 1, 0.8, 0 }, moneySilver = { 0.8, 0.8, 0.8 }, moneyCopper = { 0.8, 0.5, 0.2 } }
  h.eq(M.parts(105, colors).copper, M.colorCode(colors.moneyCopper) .. "5c|r")
  M.setIcons(true)
  h.eq(M.parts(100).silver, "1" .. M.ICONS.silver)
end)

h.test("Coins.columns: copper at the right, then silver and gold, unused columns take no room", function()
  local right, total = C.columns({ gold = 30, silver = 20, copper = 18 }, 3)
  h.eq(right, { copper = 0, silver = 21, gold = 44 })
  h.eq(total, 74)
  -- no copper anywhere in the group (gold-only style): silver is flush right
  right, total = C.columns({ gold = 30, silver = 20, copper = 0 }, 3)
  h.eq(right.silver, 0); h.eq(right.gold, 23); h.eq(total, 53)
  right, total = C.columns({}, 3)
  h.eq(total, 0)
end)

h.test("Coins.groupWidths / groupWidth: the widest part per unit, or the widest text", function()
  local w = C.groupWidths({
    { gold = 12, silver = 14, copper = 0, text = 0 },
    { gold = 0, silver = 9, copper = 16, text = 0 },
    { gold = 0, silver = 0, copper = 0, text = 40 }, -- "bound"
  })
  h.eq(w, { gold = 12, silver = 14, copper = 16, text = 40 })
  h.eq(C.groupWidth(w, 3), 12 + 3 + 14 + 3 + 16)
  h.eq(C.groupWidth({ gold = 0, silver = 0, copper = 5, text = 40 }, 3), 40)
end)
