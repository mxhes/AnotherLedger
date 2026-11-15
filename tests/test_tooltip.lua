local h = ...
local ns = h.load({ "Util.lua", "Money.lua", "Theme.lua", "Tooltip.lua" })
local Tip = ns.Tooltip
local C = ns.Theme.colors

local function sample()
  local t = Tip.new("Wingrest (Waking Shores)")
  Tip.pair(t, "Time: ", "1h 0m")
  Tip.money(t, "Value: ", 40000, 20000)
  Tip.rate(t, "Gold per hour: ", 20000)
  Tip.section(t, "Also good:")
  Tip.rate(t, "  Y", 5000, true)
  Tip.labelled(t, "Places: ", "A, B")
  Tip.note(t, "2h 0m, 3 items")
  Tip.warn(t, "Sells slowly: Ore")
  Tip.hint(t, "Click: waypoint")
  Tip.hint(t, "Right-click: copy")
  return t
end

h.test("Tooltip.text: the plain lines, title first, money unformatted", function()
  local s = Tip.text(sample())
  local M = ns.Money.format
  h.eq(s, table.concat({
    "Wingrest (Waking Shores)",
    "Time: 1h 0m",
    "Value: " .. M(40000) .. "  (" .. M(20000) .. "/h)",
    "Gold per hour: " .. M(20000) .. "/h",
    "Also good:",
    "  Y " .. M(5000) .. "/h",
    "Places: A, B",
    "2h 0m, 3 items",
    "Sells slowly: Ore",
    "Click: waypoint",
    "Right-click: copy",
  }, "\n"))
  h.eq(Tip.text("plain"), "plain")
end)

h.test("Tooltip.render: gold title, tan labels, white values, colored coins", function()
  local ops = Tip.render(sample())
  h.eq(ops[1], { op = "line", text = "Wingrest (Waking Shores)", color = C.tipTitle })
  h.eq(ops[2], { op = "double", left = "Time: ", right = "1h 0m", lc = C.tipLabel, rc = C.tipValue })
  h.eq(ops[3].op, "double")
  h.eq(ops[3].right, ns.Money.formatColored(40000) .. "  (" .. ns.Money.formatColored(20000) .. "/h)")
  h.eq(ops[3].right:find("|c", 1, true) ~= nil, true)
  h.eq(ops[5], { op = "line", text = "Also good:", color = C.tipSection })
  -- a runner-up: its name in the value color, not as a label
  h.eq(ops[6].lc, C.tipValue)
  h.eq(ops[7].op, "line"); h.eq(ops[7].wrap, true)
  h.eq(ops[7].text, ns.Money.colorCode(C.tipLabel) .. "Places: |rA, B")
  h.eq(ops[8].color, C.tipNote)
  h.eq(ops[9].color, C.tipWarn); h.eq(ops[9].wrap, true)
end)

h.test("Tooltip.render: the click hints are green, after one blank line", function()
  local ops = Tip.render(sample())
  local n = #ops
  h.eq(ops[n], { op = "line", text = "Right-click: copy", color = C.tipHint })
  h.eq(ops[n - 1], { op = "line", text = "Click: waypoint", color = C.tipHint })
  h.eq(ops[n - 2], { op = "line", text = " " })
  -- a tooltip of hints only gets no blank line
  local t = Tip.new(nil)
  Tip.hint(t, "Click")
  h.eq(Tip.render(t), { { op = "line", text = "Click", color = C.tipHint } })
end)

h.test("Tooltip.para: a white wrapping paragraph", function()
  local t = Tip.new("T")
  Tip.para(t, "Long text")
  h.eq(Tip.text(t), "T\nLong text")
  h.eq(Tip.render(t)[2], { op = "line", text = "Long text", color = C.tipValue, wrap = true })
end)
