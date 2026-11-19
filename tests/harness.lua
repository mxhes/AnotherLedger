-- Minimal test harness. Lua 5.1-compatible.
local h = { passed = 0, failed = 0 }

local function deepEq(a, b, seen)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  seen = seen or {}
  if seen[a] == b then return true end
  seen[a] = b
  for k, v in pairs(a) do
    if not deepEq(v, b[k], seen) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function show(v)
  if type(v) ~= "table" then return tostring(v) end
  local parts = {}
  for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. show(x) end
  table.sort(parts)
  return "{" .. table.concat(parts, ", ") .. "}"
end

function h.eq(actual, expected, msg)
  if not deepEq(actual, expected) then
    error((msg and (msg .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
  end
end

function h.near(a, b, eps)
  eps = eps or 1e-6
  if type(a) ~= "number" or type(b) ~= "number" or a ~= a or b ~= b or math.abs(a - b) > eps then
    error("expected " .. tostring(a) .. " near " .. tostring(b) .. " (eps " .. tostring(eps) .. ")", 2)
  end
end

-- Loads each file into one shared ns table. Paths resolve under AnotherLedger/
-- unless they start with "tests/". Locale.lua (ns.L, needed by every file
-- with texts) is loaded first unless the list names it.
function h.load(files)
  local ns = {}
  local list, hasLocale = {}, false
  for _, file in ipairs(files) do if file == "Locale.lua" then hasLocale = true end end
  if not hasLocale then list[1] = "Locale.lua" end
  for _, file in ipairs(files) do list[#list + 1] = file end
  for _, file in ipairs(list) do
    local path = file
    if file:sub(1, 6) ~= "tests/" then path = "AnotherLedger/" .. file end
    local chunk, err = loadfile(path)
    if not chunk then error("cannot load " .. path .. ": " .. tostring(err), 2) end
    chunk("AnotherLedger", ns)
  end
  return ns
end

function h.test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    h.passed = h.passed + 1
    print("ok   " .. name)
  else
    h.failed = h.failed + 1
    print("FAIL " .. name .. ": " .. tostring(err))
  end
end

return h
