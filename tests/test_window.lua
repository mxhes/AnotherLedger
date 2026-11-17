local h = ...
local ns = h.load({ "Util.lua", "Theme.lua", "UI/Window.lua" })
local clamp = ns.UI.Window.clampToScreen

h.test("clampToScreen keeps a window that fits", function()
  h.eq({ clamp(0, 0, 400, 300, 1000, 800, 1) }, { 0, 0, 400, 300 })
  h.eq({ clamp(-120, 80, 400, 300, 1000, 800, 1) }, { -120, 80, 400, 300 })
end)

h.test("clampToScreen tolerates a window flush against an edge", function()
  -- right edge: center x = (1000 - 400) / 2 = 300
  h.eq({ clamp(300, 0, 400, 300, 1000, 800, 1) }, { 300, 0, 400, 300 })
  h.eq({ clamp(300.9, 0, 400, 300, 1000, 800, 1) }, { 300.9, 0, 400, 300 })
  h.eq({ clamp(0, -250, 400, 300, 1000, 800, 1) }, { 0, -250, 400, 300 })
end)

h.test("clampToScreen moves an off-screen window to the nearest valid spot", function()
  h.eq({ clamp(450, 0, 400, 300, 1000, 800, 1) }, { 300, 0, 400, 300 })
  h.eq({ clamp(-450, 400, 400, 300, 1000, 800, 1) }, { -300, 250, 400, 300 })
  h.eq({ clamp(0, -600, 400, 300, 1000, 800, 1) }, { 0, -250, 400, 300 })
end)

h.test("clampToScreen shrinks a window larger than the screen", function()
  h.eq({ clamp(50, 50, 1200, 900, 1000, 800, 1) }, { 0, 0, 1000, 800 })
  h.eq({ clamp(0, 0, 1200, 300, 1000, 800, 1) }, { 0, 0, 1000, 300 })
end)

h.test("clampToScreen default tolerance is 1 px", function()
  h.eq({ clamp(301, 0, 400, 300, 1000, 800) }, { 301, 0, 400, 300 })
  h.eq({ clamp(302, 0, 400, 300, 1000, 800) }, { 300, 0, 400, 300 })
end)

h.test("effectiveMinWidth raises, never lowers", function()
  local e = ns.UI.Window.effectiveMinWidth
  h.eq(e(350, 400), 400)
  h.eq(e(350, 300), 350)
  h.eq(e(350, 350), 350)
  h.eq(e(350, nil), 350)
  h.eq(e(350, 0 / 0), 350)
end)

h.test("setMinWidth raises bounds and widens a too-narrow frame", function()
  local W = ns.UI.Window
  local bounds, width = nil, 360
  W.frame = {
    SetResizeBounds = function(_, w, ht) bounds = { w, ht } end,
    GetWidth = function() return width end,
    SetWidth = function(_, w) width = w end,
    GetCenter = function() return nil end,
    GetEffectiveScale = function() return 1 end,
    GetHeight = function() return 300 end,
    IsShown = function() return true end,
  }
  W.db = nil
  local saved = _G.UIParent
  _G.UIParent = { GetEffectiveScale = function() return 1 end, GetWidth = function() return 1920 end,
    GetHeight = function() return 1080 end, GetCenter = function() return 960, 540 end }
  W.setMinWidth(420)
  _G.UIParent = saved
  h.eq(bounds, { 420, ns.Theme.sizes.minHeight })
  h.eq(width, 420)
  W.setMinWidth(300) -- never below the Theme minimum
  h.eq(bounds[1], ns.Theme.sizes.minWidth)
  W.frame, W.requiredWidth = nil, nil
end)

h.test("Window.scaledColor scales only the alpha and clamps the scale", function()
  local W = ns.UI.Window
  h.eq(W.scaledColor({ 0.1, 0.2, 0.3, 0.8 }, 0.5), { 0.1, 0.2, 0.3, 0.4 })
  h.eq(W.scaledColor({ 0.1, 0.2, 0.3 }, 0.5), { 0.1, 0.2, 0.3, 0.5 })
  h.eq(W.scaledColor({ 1, 1, 1, 1 }, 2), { 1, 1, 1, 1 })
  h.eq(W.scaledColor({ 1, 1, 1, 1 }, -1), { 1, 1, 1, 0 })
  h.eq(W.scaledColor({ 1, 1, 1, 1 }, "x"), { 1, 1, 1, 1 })
end)

h.test("Window.modeParts: compact shows only the compact body", function()
  local W = ns.UI.Window
  local full = W.modeParts("full")
  h.eq(full.row2, true); h.eq(full.row3, true); h.eq(full.listArea, true); h.eq(full.footer, true)
  h.eq(full.compact, false)
  local c = W.modeParts("compact")
  h.eq(c.compact, true)
  for _, k in ipairs({ "row2", "rowFarm", "row3", "row4", "listArea", "footer", "topBox" }) do h.eq(c[k], false, k) end
  h.eq(W.modeParts("nonsense"), full)
end)

h.test("Window.keepCorner: the corner nearest the screen edge stays put", function()
  local keep = ns.UI.Window.keepCorner
  -- top left: 400 x 400 at (-500, 300) -> 260 x 200 keeps left edge -700 and top edge 500
  h.eq({ keep(-500, 300, 400, 400, 260, 200) }, { -570, 400 })
  -- bottom right keeps the right and bottom edges
  h.eq({ keep(500, -300, 400, 400, 260, 200) }, { 570, -400 })
  -- back again restores the old center
  h.eq({ keep(-570, 400, 260, 200, 400, 400) }, { -500, 300 })
end)

h.test("Window.headerHeight: compact is the title row only", function()
  local W, S = ns.UI.Window, ns.Theme.sizes
  h.eq(W.headerHeight(true, true, "compact"), S.headerRowHeight)
  h.eq(W.headerHeight(true, false, "full"), S.headerHeight + S.headerRowHeight)
end)

h.test("snapToGrid snaps the nearest edge or center onto a grid line within reach", function()
  local snap = ns.UI.Window.snapToGrid
  -- left edge at -195 -> -200; top edge at 150 + 100 = 250 is 50 off: stays
  h.eq({ snap(5, 150, 400, 200, 100, 12) }, { 0, 150 })
  -- center 3 off a line
  h.eq({ snap(103, -8, 300, 300, 100, 12) }, { 100, 0 })
  -- right edge 210 + 45 = 255 -> 250 (closer than left edge 165 and center 210)
  h.eq({ snap(210, 0, 90, 90, 50, 12) }, { 205, 0 })
  -- too far: unchanged; no spacing: unchanged
  h.eq({ snap(30, 30, 10, 10, 100, 12) }, { 30, 30 })
  h.eq({ snap(3, 3, 10, 10, nil, 12) }, { 3, 3 })
  h.eq({ snap(3, 3, 10, 10, 0, 12) }, { 3, 3 })
end)
