local h = ...
local ns = h.load({ "Theme.lua", "UI/Tabs.lua" })
local T = ns.UI.Tabs

h.test("Tabs: keys, validity, labels and titles", function()
  h.eq(T.KEYS, { "session", "bags", "bank" })
  h.eq(T.valid("bags"), true)
  h.eq(T.valid("nope"), false)
  h.eq(T.valid(nil), false)
  h.eq(T.label("bank"), "Bank")
  h.eq(T.title("bags"), "Bag Ledger")
  h.eq(T.title("bogus"), "Session Ledger")
end)
