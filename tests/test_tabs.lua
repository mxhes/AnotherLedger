local h = ...
local ns = h.load({ "Util.lua", "Theme.lua", "UI/Tabs.lua" })
local T = ns.UI.Tabs

h.test("Tabs: keys, validity, labels and titles", function()
  h.eq(T.KEYS, { "session", "bags", "bank", "history", "trade" })
  h.eq(T.valid("bags"), true)
  h.eq(T.valid("nope"), false)
  h.eq(T.valid(nil), false)
  h.eq(T.label("bank"), "Bank")
  h.eq(T.title("bags"), "Bag Ledger")
  h.eq(T.title("bogus"), "Session Ledger")
  h.eq(T.valid("history"), true)
  h.eq(T.label("history"), "History")
  h.eq(T.title("history"), "Session History")
end)

h.test("Tabs.define adds a tab; get falls back to the default tab", function()
  local built
  local spec = T.define({ key = "mail", label = "Mail", title = "Mail Ledger", watches = "mail",
    build = function(ctx) built = ctx return { rows = {} } end,
    invalidate = function() built = "dropped" end })
  h.eq(T.KEYS[#T.KEYS], "mail")
  h.eq(T.valid("mail"), true)
  h.eq(T.title("mail"), "Mail Ledger")
  h.eq(T.get("mail") == spec, true)
  h.eq(T.get("nope").key, "session")
  T.get("mail").build("ctx"); h.eq(built, "ctx")
  T.invalidate("bags"); h.eq(built, "ctx") -- another kind of data
  T.invalidate("mail"); h.eq(built, "dropped")
  h.eq(pcall(T.define, { key = "broken" }), false) -- no build function
  h.eq(T.get("session").ticks, true)
  h.eq(T.get("session").sessionControls, true)
  h.eq(T.get("bags").watches, "bags")
  h.eq(T.get("bank").watches, "bank")
end)

h.test("Tabs.look: selected tab is gold with a glow, others dark with a tan edge", function()
  local T = ns.Theme
  local Tabs = ns.UI.Tabs
  local sel = Tabs.look(true, false)
  h.eq(sel.border, T.colors.tabBorderSelected)
  h.eq(sel.glow, true)
  h.eq(sel.text, T.colors.tabTextSelected)
  local idle = Tabs.look(false, false)
  h.eq(idle.border, T.colors.tabBorder)
  h.eq(idle.glow, false)
  h.eq(idle.text, T.colors.tabText)
  -- no fill: the tab shows the window background (its opacity and brightness)
  h.eq(idle.fill, nil)
  h.eq(sel.fill, nil)
  -- hovering an unselected tab lights its edge; the selected tab stays the same
  h.eq(Tabs.look(false, true).border, T.colors.tabBorderHover)
  h.eq(Tabs.look(true, true), sel)
end)

h.test("Tabs.buttonWidth: the theme width, wider for a long label", function()
  local S = ns.Theme.sizes
  local base = ns.Theme.widths.tab
  h.eq(T.buttonWidth(nil), base)
  h.eq(T.buttonWidth(0), base)
  h.eq(T.buttonWidth(30), base)
  h.eq(T.buttonWidth(120), 120 + 2 * S.tabTextPad)
  h.eq(T.buttonWidth(120.4), math.ceil(120.4 + 2 * S.tabTextPad))
end)

h.test("Tabs sub-tabs: default, unknown key and build dispatch", function()
  T.define({ key = "subtest", label = "S", title = "S", build = function() return { which = "own" } end,
    subtabs = {
      { key = "a", label = "A", build = function() return { which = "a" } end },
      { key = "b", label = "B", build = function() return { which = "b" } end, sorts = { "ah", "perHour" } },
    } })
  h.eq(T.subtab("subtest", nil).key, "a")
  h.eq(T.subtab("subtest", "x").key, "a")
  h.eq(T.build("subtest", "b", {}).which, "b")
  h.eq(T.build("subtest", nil, {}).which, "a")
  h.eq(T.sorts("subtest", "b"), { "ah", "perHour" })
  h.eq(T.sorts("subtest", "a"), nil)
  h.eq(T.subtabs("session"), nil)
  h.eq(T.subtab("session", "a"), nil)
  h.eq(T.subtabs("history")[1].key, "sessions")
  h.eq(T.subtabs("history")[2].key, "zones")
  h.eq(T.sorts("history", "zones")[2], "perHour")
end)

h.test("Tabs: Trade comes after History with Items and Log", function()
  local T = ns.UI.Tabs
  h.eq(T.label("trade"), "Trade"); h.eq(T.title("trade"), "Trade Ledger")
  h.eq(T.subtabs("trade")[1].key, "items"); h.eq(T.subtabs("trade")[2].key, "log")
  h.eq(T.sorts("trade", "items"), { "gold", "sold", "rate", "vsMarket", "name" })
end)

h.test("Tabs.edgeSpec: rounded for Round, a square 1 px edge otherwise", function()
  local Th = ns.Theme
  h.eq(T.edgeSpec("round").edgeFile, Th.textures.tabBorder)
  h.eq(T.edgeSpec("round").edgeSize, Th.sizes.tabEdge)
  local sq = T.edgeSpec("bevel")
  h.eq(sq.edgeFile, Th.textures.rowHighlight); h.eq(sq.edgeSize, 1)
  h.eq(sq.insets.left, 0)
end)
