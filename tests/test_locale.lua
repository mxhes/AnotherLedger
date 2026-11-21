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

-- Every entry of every language translates a text the addon really uses,
-- with the same %s / %d placeholders in the same order (string.format).
h.test("Locale: no language has keys the code does not use or other placeholders", function()
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
  local function placeholders(s)
    local out = {}
    for p in s:gmatch("%%[-%d.]*[%a%%]") do out[#out + 1] = p end
    return table.concat(out, " ")
  end
  local files = {}
  local list = assert(io.popen(isWindows and "dir /b AnotherLedger\\Locales\\*.lua" or "ls AnotherLedger/Locales"))
  for name in list:lines() do
    name = name:gsub("\r", "")
    if name:match("%.lua$") then files[#files + 1] = name end
  end
  list:close()
  local hasGerman = false
  for _, name in ipairs(files) do if name == "deDE.lua" then hasGerman = true end end
  h.eq(hasGerman, true)
  local unknown, wrong = {}, {}
  for _, name in ipairs(files) do
    local captured
    local fake = { Locale = { register = function(_, strings) captured = strings end } }
    assert(loadfile("AnotherLedger/Locales/" .. name))("AnotherLedger", fake)
    for key, text in pairs(captured) do
      if not used[key] then unknown[#unknown + 1] = name .. ": " .. key end
      -- the date format may reorder its fields (os.date, not string.format)
      if key ~= "%Y-%m-%d" and placeholders(key) ~= placeholders(text) then wrong[#wrong + 1] = name .. ": " .. key end
    end
  end
  table.sort(unknown)
  table.sort(wrong)
  h.eq(unknown, {})
  h.eq(wrong, {})
end)

h.test("Locale: no language lists a key twice (luacheck W314 in CI)", function()
  local twice = {}
  for _, name in ipairs({ "deDE.lua" }) do
    local seen = {}
    for line in io.lines("AnotherLedger/Locales/" .. name) do
      local key = line:match('^%s*%["(.-)"%]%s*=')
      if key then
        if seen[key] then twice[#twice + 1] = name .. ": " .. key end
        seen[key] = true
      end
    end
  end
  h.eq(twice, {})
end)
