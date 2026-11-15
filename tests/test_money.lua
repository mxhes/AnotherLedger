local h = ...
local ns = h.load({ "Util.lua", "Money.lua" })

local cases = {
  { 12000, "1g 20s" }, { 45000, "4g 50s" }, { 620000, "62g" }, { 800, "8s" },
  { 5, "5c" }, { 10005, "1g 5c" }, { 0, "0c" }, { nil, "n/a" },
  { -12000, "-1g 20s" }, { 12345.7, "1g 23s 45c" },
}
for _, c in ipairs(cases) do
  h.test("Money.format(" .. tostring(c[1]) .. ")", function()
    h.eq(ns.Money.format(c[1]), c[2])
  end)
end

local colors = {
  moneyGold = { 1.0, 0.82, 0.0 },
  moneySilver = { 0.78, 0.78, 0.81 },
  moneyCopper = { 0.93, 0.65, 0.37 },
}
local G, S, C = "|cffffd100", "|cffc7c7cf", "|cffeda65e"

h.test("Money.formatColored gold silver copper", function()
  h.eq(ns.Money.formatColored(123456, colors),
    G .. "12g|r " .. S .. "34s|r " .. C .. "56c|r")
end)

h.test("Money.formatColored single units, zero, nil, negative", function()
  h.eq(ns.Money.formatColored(800, colors), S .. "8s|r")
  h.eq(ns.Money.formatColored(0, colors), C .. "0c|r")
  h.eq(ns.Money.formatColored(nil, colors), "n/a")
  h.eq(ns.Money.formatColored(-12000, colors), "-" .. G .. "1g|r " .. S .. "20s|r")
end)

h.test("Money.formatColored without colors is the plain text", function()
  h.eq(ns.Money.formatColored(123456), ns.Money.format(123456))
  h.eq(ns.Money.formatColored(nil), "n/a")
end)

h.test("Money.formatColored strips back to Money.format", function()
  for _, v in ipairs({ 0, 5, 800, 10005, 123456, -12000, 12345.7 }) do
    local plain = ns.Money.formatColored(v, colors):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    h.eq(plain, ns.Money.format(v))
  end
end)

h.test("Money.formatColored reads ns.Theme colors lazily", function()
  ns.Theme = { colors = colors }
  h.eq(ns.Money.formatColored(100), S .. "1s|r")
  ns.Theme = nil
end)

h.test("Money.setStyle: gold-only and no-copper from 1 gold up, small amounts stay full", function()
  local M = h.load({ "Util.lua", "Money.lua" }).Money
  M.setStyle("gold")
  h.eq(M.format(12345678), "1234g")
  h.eq(M.format(-12345678), "-1234g")
  h.eq(M.format(5025), "50s 25c")
  M.setStyle("silver")
  h.eq(M.format(12345678), "1234g 56s")
  h.eq(M.format(5025), "50s 25c")
  M.setStyle("bogus")
  h.eq(M.format(12345678), "1234g 56s 78c")
end)

h.test("Money.colorCode gives the color escape of a color table", function()
  h.eq(ns.Money.colorCode({ 1, 0, 0, 1 }), "|cffff0000")
  h.eq(ns.Money.colorCode({ 0, 0.5, 1 }), "|cff0080ff")
end)

h.test("Money.setIcons: the game's coin icons replace g / s / c", function()
  local M = h.load({ "Util.lua", "Money.lua" }).Money
  local I = M.ICONS
  h.eq(I.gold, "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t")
  h.eq(I.silver, "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t")
  h.eq(I.copper, "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t")
  h.eq(M.iconsOn(), false)
  M.setIcons(true)
  h.eq(M.iconsOn(), true)
  h.eq(M.format(12345), "1" .. I.gold .. " 23" .. I.silver .. " 45" .. I.copper)
  h.eq(M.format(0), "0" .. I.copper)
  h.eq(M.format(-500), "-5" .. I.silver)
  h.eq(M.format(nil), "n/a")
  -- colored: the digits keep their coin color, the icon follows inside it
  h.eq(M.formatColored(10100, colors), G .. "1" .. I.gold .. "|r " .. S .. "1" .. I.silver .. "|r")
  M.setStyle("gold")
  h.eq(M.format(12345678), "1234" .. I.gold)
  M.setStyle("full")
  M.setIcons(false)
  h.eq(M.format(12345), "1g 23s 45c")
end)
