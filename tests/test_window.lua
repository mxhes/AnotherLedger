local h = ...
local ns = h.load({ "Theme.lua", "UI/Window.lua" })
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
