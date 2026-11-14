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
