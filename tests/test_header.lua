local h = ...
local ns = h.load({ "Theme.lua", "UI/Header.lua" })
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

h.test("buttonStates never both enabled", function()
  local r = H.buttonStates(true)
  h.eq(r.start, false)
  h.eq(r.stop, true)
  local s = H.buttonStates(false)
  h.eq(s.start, true)
  h.eq(s.stop, false)
  h.eq(H.buttonStates(nil).start, true)
end)
