local h = ...
local ns = h.load({ "Util.lua", "Theme.lua", "UI/Widgets.lua" })
local W = ns.UI.Widgets
local C = ns.Theme.colors

h.test("Widgets.buttonColors: bronze edge, gold on hover, dimmed when disabled", function()
  local n = W.buttonColors("normal")
  h.eq(n.fill, C.buttonFill); h.eq(n.edge, C.buttonEdge); h.eq(n.text, C.buttonText)
  h.eq(W.buttonColors("hover").edge, C.buttonEdgeHover)
  h.eq(W.buttonColors("hover").text, C.buttonText)
  local d = W.buttonColors("disabled")
  h.eq(d.text, C.buttonTextDisabled); h.eq(d.edge, C.buttonEdge)
  h.eq(W.buttonColors("unknown"), n)
end)

h.test("Widgets.buttonColors: light top, dark bottom and an outer line from the fill", function()
  local T = ns.Theme
  local n = W.buttonColors("normal")
  h.eq(n.top, T.scaleColor(C.buttonFill, W.BUTTON_TOP))
  h.eq(n.bottom, T.scaleColor(C.buttonFill, W.BUTTON_BOTTOM))
  h.eq(n.outline, T.scaleColor(C.buttonFill, W.BUTTON_OUTLINE))
  h.eq(n.top[1] > n.bottom[1], true)
  local hv = W.buttonColors("hover")
  h.eq(hv.top[1] > n.top[1] and hv.bottom[1] > n.bottom[1], true)
end)

h.test("Widgets.buttonColors: pressed swaps the halves and lights the edge", function()
  local n, p = W.buttonColors("normal"), W.buttonColors("pressed")
  h.eq(p.top, n.bottom); h.eq(p.bottom, n.top)
  h.eq(p.edge, C.buttonEdgeHover)
  h.eq(W.buttonColors("pressed", true).edge, C.buttonWarnEdgeHover)
end)

h.test("Widgets.pixelError: distance past the nearest whole pixel", function()
  h.near(W.pixelError(10.3, 1), 0.3, 1e-9)
  h.near(W.pixelError(10.7, 1), -0.3, 1e-9)
  h.near(W.pixelError(3.4, 0.8), 0.2, 1e-9) -- 4 pixels of 0.8 = 3.2
end)

h.test("Widgets.pixels / snapPoint: whole screen pixels through PixelUtil, plain units without", function()
  -- a region whose rect follows its last SetPoint offset
  local region = { GetEffectiveScale = function() return 0.5 end }
  function region:ClearAllPoints() self.pt = nil end
  function region:SetPoint(point, rel, relPoint, x, y) self.pt = { point, rel, relPoint, x, y } end
  function region:GetLeft() return 100.3 + self.pt[4] end
  function region:GetTop() return 200.9 + self.pt[5] end
  h.eq(W.pixelSize(region), nil)
  h.eq(W.pixels(region, 1), 1) -- no PixelUtil: the units as they are
  W.snapPoint(region, "LEFT", "rel", "RIGHT", 2, 0)
  h.eq(region.pt, { "LEFT", "rel", "RIGHT", 2, 0 })
  _G.PixelUtil = { GetPixelToUIUnitFactor = function() return 0.4 end } -- one pixel = 0.8 units
  local ok, err = pcall(function()
    h.near(W.pixelSize(region), 0.8, 1e-9)
    h.near(W.pixels(region, 1), 0.8, 1e-9)
    h.near(W.pixels(region, 1.7), 1.6, 1e-9) -- 2.125 pixels -> 2
    h.near(W.pixels(region, 0.1), 0.8, 1e-9) -- at least one pixel
    W.snapPoint(region, "LEFT", "rel", "RIGHT", 2, 0)
    local left, top = region:GetLeft(), region:GetTop()
    h.near(W.pixelError(left, 0.8), 0, 1e-9); h.near(W.pixelError(top, 0.8), 0, 1e-9)
    h.eq(math.abs(region.pt[4] - 2) < 0.8 and math.abs(region.pt[5]) < 0.8, true)
    -- a region without a usable scale keeps the plain units
    h.eq(W.pixels({ GetEffectiveScale = function() return nil end }, 2), 2)
  end)
  _G.PixelUtil = nil
  if not ok then error(err, 0) end
end)

h.test("Widgets.buttonColors: a warning button keeps its red tint in every state", function()
  for _, state in ipairs({ "normal", "hover", "disabled" }) do
    local c = W.buttonColors(state, true)
    h.eq(c.edge, state == "hover" and C.buttonWarnEdgeHover or C.buttonWarnEdge)
    h.eq(c.text, state == "disabled" and C.buttonTextDisabled or C.buttonWarnText)
  end
end)

h.test("Widgets.buttonColors: a light button background turns the text dark", function()
  local fill = { C.buttonFill[1], C.buttonFill[2], C.buttonFill[3], C.buttonFill[4] }
  C.buttonFill[1], C.buttonFill[2], C.buttonFill[3] = 1, 0.82, 0
  local ok, err = pcall(function()
    local n = W.buttonColors("normal")
    h.eq(n.text ~= C.buttonText, true)
    h.eq(ns.Theme.contrast(n.text[1], n.text[2], n.text[3], 1, 0.82, 0) >= 3, true)
    local d = W.buttonColors("disabled").text
    h.eq(ns.Theme.contrast(d[1], d[2], d[3], 1, 0.82, 0) >= 3, true)
    h.eq(W.buttonColors("normal", true).text, n.text)
  end)
  for i = 1, 4 do C.buttonFill[i] = fill[i] end
  if not ok then error(err, 0) end
end)

h.test("Theme.readableOn: a readable color stays, else dark or light", function()
  local T = ns.Theme
  local red = { 1, 0, 0, 1 }
  h.eq(T.readableOn(red, { 0, 0, 0 }), red)
  h.eq(T.readableOn({ 1, 1, 1, 1 }, { 1, 1, 0.9 })[1] < 0.5, true)
  h.eq(T.readableOn({ 0, 0, 0, 1 }, { 0.05, 0.05, 0.1 })[1], 1)
end)

h.test("Widgets.arrowCoords: turns the right-pointing arrow texture up or down", function()
  -- SetTexCoord(ULx, ULy, LLx, LLy, URx, URy, LRx, LRy): the source's right
  -- edge (x = 1, the tip) lands on the top edge for up, the bottom for down.
  local up = { W.arrowCoords("up") }
  h.eq(up, { 1, 0, 0, 0, 1, 1, 0, 1 })
  h.eq(up[1], 1); h.eq(up[5], 1) -- UL and UR sample x = 1
  local down = { W.arrowCoords("down") }
  h.eq(down, { 0, 1, 1, 1, 0, 0, 1, 0 })
  h.eq(down[3], 1); h.eq(down[7], 1) -- LL and LR sample x = 1
end)

h.test("Widgets.buttonColors: raised light / dark from the fill, swapped while pressed", function()
  local T = ns.Theme
  local n, p = W.buttonColors("normal"), W.buttonColors("pressed")
  h.eq(n.light, T.scaleColor(C.buttonFill, T.skinScales.raisedLight))
  h.eq(n.dark, T.scaleColor(C.buttonFill, T.skinScales.raisedDark))
  h.eq(p.light, n.dark); h.eq(p.dark, n.light)
end)
