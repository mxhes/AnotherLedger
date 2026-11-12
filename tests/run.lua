-- Run from the repo root: lua tests/run.lua
local h = dofile("tests/harness.lua")

local isWindows = package.config:sub(1, 1) == "\\"
local cmd = isWindows and "dir /b tests\test_*.lua 2>nul" or "ls tests/test_*.lua"
local pipe = assert(io.popen(cmd))
local files = {}
for line in pipe:lines() do
  line = line:gsub("\r", ""):gsub("^tests/", "")
  if line:match("^test_.*%.lua$") then files[#files + 1] = line end
end
pipe:close()
table.sort(files)

for _, file in ipairs(files) do
  local chunk, err = loadfile("tests/" .. file)
  if not chunk then
    h.failed = h.failed + 1
    print("FAIL " .. file .. ": " .. tostring(err))
  else
    local ok, runErr = pcall(chunk, h)
    if not ok then
      h.failed = h.failed + 1
      print("FAIL " .. file .. ": " .. tostring(runErr))
    end
  end
end

print(string.format("%d passed, %d failed", h.passed, h.failed))
os.exit(h.failed > 0 and 1 or 0)
