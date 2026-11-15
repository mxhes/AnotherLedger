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
