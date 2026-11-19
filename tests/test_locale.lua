local h = ...
local ns = h.load({ "Locale.lua" })

h.test("Locale: a missing translation is the English text", function()
  h.eq(ns.L["Vendor: "], "Vendor: ")
  h.eq(ns.Locale.current(), "enUS")
end)

h.test("Locale.register only takes the client language", function()
  h.eq(ns.Locale.register("deDE", { ["Vendor: "] = "Händler: " }, "enUS"), false)
  h.eq(ns.L["Vendor: "], "Vendor: ")
  h.eq(ns.Locale.register("deDE", { ["Vendor: "] = "Händler: ", ["x"] = "" }, "deDE"), true)
  h.eq(ns.L["Vendor: "], "Händler: ")
  h.eq(ns.L["x"], "x")
end)

-- Every German entry translates a text the addon really uses.
h.test("Locale: deDE has no keys the code does not use", function()
  local used = {}
  local isWindows = package.config:sub(1, 1) == "\\"
  local cmd = isWindows and "dir /s /b AnotherLedger\\*.lua" or "find AnotherLedger -name '*.lua'"
  local pipe = assert(io.popen(cmd))
  for path in pipe:lines() do
    path = path:gsub("\r", "")
    if not path:find("Locales", 1, true) then
      local fh = assert(io.open(path, "r"))
      local text = fh:read("*a")
      fh:close()
      for key in text:gmatch('L%["(.-)"%]') do used[key] = true end
      for key in text:gmatch('local L_[%w_]+ = "(.-)"') do used[key] = true end
    end
  end
  pipe:close()
  local captured
  local fake = { Locale = { register = function(_, strings) captured = strings end } }
  assert(loadfile("AnotherLedger/Locales/deDE.lua"))("AnotherLedger", fake)
  local unknown = {}
  for key in pairs(captured) do
    if not used[key] then unknown[#unknown + 1] = key end
  end
  table.sort(unknown)
  h.eq(unknown, {})
end)
