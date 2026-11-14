local h = ...
local ns = h.load({ "Util.lua", "UI/Minimap.lua" })
local M = ns.UI.Minimap

h.test("Minimap.offset: angle in degrees to a point on the rim", function()
  local x, y = M.offset(0, 100)
  h.near(x, 100); h.near(y, 0)
  x, y = M.offset(90, 100)
  h.near(x, 0); h.near(y, 100)
  x, y = M.offset(225, 100)
  h.near(x, -70.7106781, 1e-4); h.near(y, -70.7106781, 1e-4)
end)

h.test("Minimap.angleOf: inverse of offset, 0..360", function()
  h.near(M.angleOf(10, 0), 0)
  h.near(M.angleOf(0, 10), 90)
  h.near(M.angleOf(-10, 0), 180)
  h.near(M.angleOf(0, -10), 270)
  h.near(M.angleOf(0, 0), 0)
end)
