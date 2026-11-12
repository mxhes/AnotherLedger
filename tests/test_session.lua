local h = ...
local ns = h.load({ "Session.lua" })
local S = ns.Session
local L = "|cff0070dd|Hitem:5::::::::|h[Thing]|h|r"

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

h.test("Session.new and elapsed", function()
  local s = S.new(100)
  h.eq(s.running, true)
  h.eq(s.startedAt, 100)
  h.eq(S.elapsed(s, 100), 0)
  h.eq(S.elapsed(s, 160), 60)
end)

h.test("Session.add accumulates and updates lastSeen", function()
  local s = S.new(100)
  h.eq(S.add(s, 5, L, 3, 110), true)
  h.eq(S.add(s, 5, L, 2, 120), true)
  h.eq(s.items[5].qty, 5)
  h.eq(s.items[5].lastSeen, 120)
  h.eq(s.items[5].id, 5)
  h.eq(s.items[5].link, L)
end)

h.test("Session.add rejects bad input", function()
  local s = S.new(0)
  h.eq(S.add(s, 5, L, 0, 1), false)
  h.eq(S.add(s, 5, L, -2, 1), false)
  h.eq(S.add(s, 5, L, "3", 1), false)
  h.eq(S.add(s, 5, L, nil, 1), false)
  h.eq(S.add(s, 5, L, 1.5, 1), false)
  h.eq(S.add(s, "5", L, 1, 1), false)
  h.eq(S.add(s, nil, L, 1, 1), false)
  h.eq(count(s.items), 0)
end)

h.test("Session stop/start", function()
  local s = S.new(100)
  S.add(s, 5, L, 3, 110)
  S.stop(s, 200)
  h.eq(s.running, false)
  h.eq(S.elapsed(s, 500), 100)
  h.eq(S.add(s, 5, L, 1, 300), false)
  h.eq(s.items[5].qty, 3)
  S.stop(s, 400)
  h.eq(S.elapsed(s, 500), 100)
  S.start(s, 600)
  h.eq(S.elapsed(s, 660), 160)
  S.start(s, 640)
  h.eq(S.elapsed(s, 660), 160)
  h.eq(S.add(s, 5, L, 1, 700), true)
end)

h.test("Session.reset keeps run state", function()
  local s = S.new(0)
  S.add(s, 5, L, 3, 10)
  S.reset(s, 50)
  h.eq(count(s.items), 0)
  h.eq(s.running, true)
  h.eq(S.elapsed(s, 50), 0)
  h.eq(S.elapsed(s, 80), 30)
  S.stop(s, 90)
  S.add(s, 5, L, 1, 91)
  S.reset(s, 100)
  h.eq(s.running, false)
  h.eq(S.elapsed(s, 200), 0)
  h.eq(count(s.items), 0)
end)

h.test("Session suspend/resume", function()
  local s = S.new(0)
  S.suspend(s, 100)
  S.resume(s, 10000)
  h.eq(S.elapsed(s, 10060), 160)
  local t = S.new(0)
  S.stop(t, 100)
  S.suspend(t, 200)
  S.resume(t, 10000)
  h.eq(t.running, false)
  h.eq(S.elapsed(t, 20000), 100)
end)

h.test("Session.login", function()
  h.eq(S.login(nil, true, 5).running, true)
  h.eq(S.elapsed(S.login(nil, true, 5), 5), 0)
  local saved = S.new(0)
  S.add(saved, 5, L, 3, 10)
  S.suspend(saved, 100)
  local fresh = S.login(saved, false, 5)
  h.eq(count(fresh.items), 0)
  h.eq(S.elapsed(fresh, 5), 0)
  h.eq(saved.items[5].qty, 3)
  local kept = S.login(saved, true, 5000)
  h.eq(kept.items[5].qty, 3)
  h.eq(S.elapsed(kept, 5060), 160)
end)

h.test("Session.login survives corrupt saved data", function()
  local bad = {
    42, "x", true, {},
    { startedAt = "a", running = true, elapsedBase = 0, items = {} },
    { startedAt = 0, running = "yes", elapsedBase = 0, items = {} },
    { startedAt = 0, running = true, elapsedBase = "0", items = {} },
    { startedAt = 0, running = true, elapsedBase = 0, items = 7 },
    { startedAt = 0, running = true, elapsedBase = 0, items = { [5] = "oops" } },
    { startedAt = 0, running = true, elapsedBase = 0, items = { [5] = { id = 5, qty = "3", lastSeen = 1 } } },
    { startedAt = 0, running = true, elapsedBase = 0, items = { [5] = { id = 5, qty = -1, lastSeen = 1 } } },
    { startedAt = 0, running = true, elapsedBase = 0 / 0, items = {} },
  }
  for i, b in ipairs(bad) do
    local s
    local ok, err = pcall(function() s = S.login(b, true, 7) end)
    if not ok then error("case " .. i .. " threw: " .. tostring(err)) end
    h.eq(s.running, true, "case " .. i)
    h.eq(count(s.items), 0, "case " .. i)
    h.eq(S.elapsed(s, 7), 0, "case " .. i)
  end
end)

h.test("Session record is plain data", function()
  local s = S.new(1)
  S.add(s, 5, L, 1, 2)
  local function plain(t)
    h.eq(getmetatable(t), nil)
    for _, v in pairs(t) do
      local ty = type(v)
      if ty == "table" then plain(v)
      elseif ty ~= "number" and ty ~= "string" and ty ~= "boolean" then error("non-plain " .. ty) end
    end
  end
  plain(s)
end)

h.test("Session.needsResetConfirm", function()
  local s = S.new(0)
  for i = 1, 24 do S.add(s, i, L, 1, 1) end
  h.eq(S.itemCount(s), 24)
  h.eq(S.needsResetConfirm(s), false)
  S.add(s, 25, L, 1, 1)
  h.eq(S.itemCount(s), 25)
  h.eq(S.needsResetConfirm(s), true)
  h.eq(S.LARGE_SESSION_ITEMS, 25)
end)

h.test("Session.new has zero gold", function()
  local s = S.new(0)
  h.eq(s.gold, 0)
  h.eq(S.goldTotal(s), 0)
end)

h.test("Session.addGold accumulates one total", function()
  local s = S.new(0)
  h.eq(S.addGold(s, 150, 1), true)
  h.eq(S.addGold(s, 1050, 2), true)
  h.eq(s.gold, 1200)
  h.eq(S.goldTotal(s), 1200)
end)

h.test("Session.addGold rejects stopped and bad amounts", function()
  local s = S.new(0)
  for _, bad in ipairs({ 0, -5, 1.5, "10", 0 / 0, math.huge, -math.huge }) do
    h.eq(S.addGold(s, bad, 1), false)
  end
  h.eq(S.addGold(s, nil, 1), false)
  S.stop(s, 5)
  h.eq(S.addGold(s, 10, 6), false)
  h.eq(s.gold, 0)
  S.start(s, 7)
  h.eq(S.addGold(s, 10, 8), true)
end)

h.test("Session.reset zeroes gold", function()
  local s = S.new(0)
  S.addGold(s, 10, 1)
  S.reset(s, 5)
  h.eq(s.gold, 0)
end)

local function rec(gold)
  return { startedAt = 0, running = true, elapsedBase = 50,
    items = { [5] = { id = 5, qty = 2, lastSeen = 1 } }, gold = gold }
end

h.test("Session.login migrates a record without gold", function()
  local s = S.login(rec(nil), true, 100)
  h.eq(s.gold, 0)
  h.eq(S.elapsed(s, 100), 50)
end)

h.test("Session.login keeps a valid number and sums the old table", function()
  h.eq(S.login(rec(700), true, 9).gold, 700)
  h.eq(S.login(rec({ looted = 70, quest = 30 }), true, 9).gold, 100)
  h.eq(S.login(rec({ looted = 70 }), true, 9).gold, 70)
  h.eq(S.login(rec({ looted = -5, quest = 30 }), true, 9).gold, 30)
  h.eq(S.login(rec({ looted = 0 / 0, quest = "9" }), true, 9).gold, 0)
  h.eq(S.login(rec({ looted = math.huge, quest = 4 }), true, 9).gold, 4)
end)

h.test("Session.login resets other malformed gold to 0, keeps the rest", function()
  for i, g in ipairs({ "x", true, -1, 0 / 0, math.huge, -math.huge }) do
    local s = S.login(rec(g), true, 9)
    h.eq(s.gold, 0, "case " .. i)
    h.eq(s.items[5].qty, 2, "case " .. i)
    h.eq(S.elapsed(s, 9), 50, "case " .. i)
  end
end)
