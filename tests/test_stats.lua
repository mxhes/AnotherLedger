local h = ...
local ns = h.load({ "Util.lua", "Stats.lua" })
local S = ns.Stats

h.test("Stats.size estimates the saved text of values and tables", function()
  h.eq(S.size("ab"), 4)
  h.eq(S.size(12), 2)
  h.eq(S.size(true), 4)
  -- {\n\t["a"] = 1,\n}
  h.eq(S.size({ a = 1 }), 3 + 1 + 5 + 3 + 1 + 2)
  -- list entries carry a "-- [n]" note
  h.eq(S.size({ "x" }) > S.size({ k = "x" }) - 3, true)
end)

h.test("Stats.size counts a table met twice once (aliases)", function()
  local shared = { a = string.rep("x", 100) }
  local once = S.size({ p = shared })
  h.eq(S.size({ p = shared, alias = shared }) < once + 20, true)
end)

h.test("Stats.collect splits the account data and counts its parts", function()
  local list = { { startedAt = 1, items = {}, mobs = { ["npc:1"] = { looted = 3 } } }, { startedAt = 2, items = {} } }
  local db = {
    histories = { ["A-Realm"] = list, ["B-Realm"] = {} },
    scan = { r1 = { items = { [1] = "a,b", [2] = "c" } }, r2 = { items = { [3] = "d" } } },
    trade = { r1 = { log = { {}, {}, {} } } },
    cache = { k = { [1] = {}, [2] = {} } },
    settings = { alpha = 1 },
  }
  local chardb = { history = list, session = { items = { [1] = { qty = 1 } } } }
  local st = S.collect(db, chardb)
  local by = {}
  for _, p in ipairs(st.parts) do by[p.key] = p end
  h.eq(by.history.n, 2); h.eq(by.history.m, 2); h.eq(by.history.mobs > 0, true)
  h.eq(by.scan.n, 3); h.eq(by.scan.m, 2)
  h.eq(by.trade.n, 3)
  h.eq(by.cache.n, 2)
  h.eq(by.character.size > 0, true)
  h.eq(st.parts[#st.parts].key, "other")
  -- the character's History alias is not counted twice
  h.eq(by.character.size < by.history.size, true)
  local sum = 0
  for _, p in ipairs(st.parts) do sum = sum + p.size end
  h.eq(sum, st.total)
  h.eq(#S.lines(st), #st.parts + 1)
end)

h.test("Stats.bytes reads as B, KB or MB", function()
  h.eq(S.bytes(312), "312 B")
  h.eq(S.bytes(4300), "4.2 KB")
  h.eq(S.bytes(1887437), "1.8 MB")
end)
