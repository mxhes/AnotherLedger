local h = ...
local ns = h.load({ "Money.lua" })

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
