local h = ...

-- CHANGELOG.md stays short (it is also the CurseForge release notes): the
-- newest entry has only bullets, at most MAX_BULLETS of them, each at most
-- MAX_CHARS characters (one or two lines). See docs/CHECKLIST.md, release
-- step 5.
local MAX_BULLETS = 10
local MAX_CHARS = 160

local function newestEntry(text)
  local lines, entry, inEntry = {}, nil, false
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = (line:gsub("\r$", ""))
  end
  for _, line in ipairs(lines) do
    if line:match("^## ") then
      if inEntry then break end
      inEntry, entry = true, { title = line, lines = {} }
    elseif inEntry then
      entry.lines[#entry.lines + 1] = line
    end
  end
  return entry
end

-- Bullets of an entry: { text, ... } with continuation lines joined; `stray`
-- lists lines that are neither a bullet nor its continuation.
local function bullets(entry)
  local out, stray = {}, {}
  for _, line in ipairs(entry.lines) do
    if line:match("^%- ") then
      out[#out + 1] = line:sub(3)
    elseif line:match("^%s+%S") and #out > 0 then
      out[#out] = out[#out] .. " " .. line:match("^%s+(.-)%s*$")
    elseif line:match("%S") then
      stray[#stray + 1] = line
    end
  end
  return out, stray
end

h.test("CHANGELOG.md: the newest entry is short (bullets only, few and brief)", function()
  local f = assert(io.open("CHANGELOG.md", "r"))
  local text = f:read("*a")
  f:close()
  local entry = newestEntry(text)
  h.eq(entry ~= nil, true)
  h.eq(entry.title:match("^## v%d+%.%d+%.%d+$") ~= nil, true)
  local list, stray = bullets(entry)
  h.eq(stray, {})
  h.eq(#list > 0, true)
  h.eq(#list <= MAX_BULLETS, true)
  local long = {}
  for _, b in ipairs(list) do
    if #b > MAX_CHARS then long[#long + 1] = b end
  end
  h.eq(long, {})
end)

h.test("CHANGELOG.md check: catches a long entry and stray text", function()
  local many = { "## v9.9.9", "" }
  for i = 1, MAX_BULLETS + 1 do many[#many + 1] = "- item " .. i end
  local list = bullets(newestEntry(table.concat(many, "\n")))
  h.eq(#list, MAX_BULLETS + 1)
  local e = newestEntry("# T\n\n## v1.0.0\n\nIntro text.\n- one\n  two\n\n## v0.9.0\n\n- old\n")
  local l, stray = bullets(e)
  h.eq(l, { "one two" })
  h.eq(stray, { "Intro text." })
end)
