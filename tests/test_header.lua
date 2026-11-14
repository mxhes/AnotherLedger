local h = ...
local ns = h.load({ "Util.lua", "Theme.lua", "UI/Header.lua" })
local H = ns.UI.Header

h.test("formatElapsed basics", function()
  h.eq(H.formatElapsed(0), "00:00:00")
  h.eq(H.formatElapsed(59), "00:00:59")
  h.eq(H.formatElapsed(61), "00:01:01")
  h.eq(H.formatElapsed(3661), "01:01:01")
end)

h.test("formatElapsed floors fractions", function()
  h.eq(H.formatElapsed(59.99), "00:00:59")
end)

h.test("formatElapsed hours keep growing", function()
  h.eq(H.formatElapsed(360001), "100:00:01")
end)

h.test("formatElapsed bad input", function()
  h.eq(H.formatElapsed(nil), "00:00:00")
  h.eq(H.formatElapsed(-5), "00:00:00")
  h.eq(H.formatElapsed(0 / 0), "00:00:00")
  h.eq(H.formatElapsed("x"), "00:00:00")
  h.eq(H.formatElapsed(math.huge), "00:00:00")
end)

h.test("toggleState: Start while stopped, Stop while running", function()
  h.eq(H.toggleState(true).action, "stop")
  h.eq(H.toggleState(true).label, "Stop")
  h.eq(H.toggleState(false).action, "start")
  h.eq(H.toggleState(false).label, "Start")
  h.eq(H.toggleState(nil).action, "start")
end)
