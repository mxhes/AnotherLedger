local h = ...
local ns = h.load({ "Util.lua", "LootParse.lua", "Mobs.lua" })
local M = ns.Mobs

local LINEN = "|cffffffff|Hitem:2589::::::::60:::::::::|h[Linen Cloth]|h|r"
local A = "Creature-0-3110-0-12-2546-000012ABCD"
local B = "Creature-0-3110-0-12-2547-000012ABCE"
local NODE = "GameObject-0-3110-0-12-1731-000012ABCF"

h.test("Mobs.idOf parses creatures, vehicles and nodes", function()
  h.eq({ M.idOf(A) }, { "npc:2546", "npc" })
  h.eq({ M.idOf("Vehicle-0-3110-0-12-3000-000012ABCD") }, { "npc:3000", "npc" })
  h.eq({ M.idOf(NODE) }, { "obj:1731", "node" })
  h.eq(M.idOf("Player-3110-0ABCDEF"), nil)
  -- a secret GUID is never parsed
  local saved = _G.issecretvalue
  _G.issecretvalue = function(v) return v == A end
  h.eq(M.idOf(A), nil)
  h.eq(ns.Util.plainString("x"), "x")
  h.eq(ns.Util.plainString(""), nil)
  _G.issecretvalue = function() error("no") end -- a failing check counts as secret
  h.eq(ns.Util.plainString("x"), nil)
  _G.issecretvalue = saved
  h.eq(ns.Util.isSecret(A), false)
  h.eq(M.idOf("Pet-0-3110-0-12-416-0100ABCD"), nil)
  h.eq(M.idOf(nil), nil)
  h.eq(M.idOf("Creature-0-1"), nil)
end)

h.test("Mobs.readSlot reads an item or money slot and its sources", function()
  local env = {
    GetLootSlotType = function(slot) return slot == 1 and 1 or (slot == 2 and 2 or 3) end,
    GetLootSlotLink = function(slot) return slot == 1 and LINEN or nil end,
    GetLootSlotInfo = function(slot) return 134400, "Linen Cloth", slot == 1 and 5 or 0 end,
    GetLootSourceInfo = function(slot)
      if slot == 1 then return A, 2, B, 3 end
      if slot == 2 then return A, 120, B, 80 end
      return A, 1
    end,
  }
  h.eq(M.readSlot(env, 1), { kind = "item", link = LINEN, qty = 5,
    sources = { { guid = A, qty = 2 }, { guid = B, qty = 3 } } })
  h.eq(M.readSlot(env, 2), { kind = "money", qty = 200, sources = { { guid = A, qty = 120 }, { guid = B, qty = 80 } } })
  h.eq(M.readSlot(env, 3), nil) -- currency
  h.eq(M.readSlot({}, 1), nil)
  -- one source without a quantity takes the slot's
  env.GetLootSourceInfo = function() return A end
  h.eq(M.readSlot(env, 1).sources, { { guid = A, qty = 5 } })
end)

h.test("Mobs.credit splits a shared slot by source quantity", function()
  local mobs, state = {}, {}
  local slot = { kind = "item", link = LINEN, qty = 5, sources = { { guid = A, qty = 2 }, { guid = B, qty = 3 } } }
  M.credit(mobs, slot, "Elwynn Forest", { ["npc:2546"] = "Kobold" }, state)
  h.eq(mobs["npc:2546"].items[2589], 2)
  h.eq(mobs["npc:2547"].items[2589], 3)
  h.eq(mobs["npc:2546"].name, "Kobold")
  h.eq(mobs["npc:2547"].name, nil)
  h.eq(mobs["npc:2546"].kind, "npc")
  h.eq(mobs["npc:2546"].looted, 1)
  h.eq(mobs["npc:2546"].places["Elwynn Forest"], 1)
  -- a second slot of the same corpse: not looted twice
  M.credit(mobs, { kind = "item", link = LINEN, qty = 1, sources = { { guid = A, qty = 1 } } }, "Elwynn Forest", {}, state)
  h.eq(mobs["npc:2546"].looted, 1)
  h.eq(mobs["npc:2546"].items[2589], 3)
  h.eq(mobs["npc:2546"].places["Elwynn Forest"], 1) -- places count corpses, not slots
  -- another corpse of the same mob
  M.credit(mobs, { kind = "item", link = LINEN, qty = 1, sources = { { guid = A .. "1", qty = 1 } } },
    "Elwynn Forest", {}, state)
  h.eq(mobs["npc:2546"].looted, 2)
  h.eq(mobs["npc:2546"].places["Elwynn Forest"], 2)
end)

h.test("Mobs.credit adds copper per source for a money slot; players are skipped", function()
  local mobs, state = {}, {}
  M.credit(mobs, { kind = "money", qty = 200, sources = { { guid = A, qty = 120 }, { guid = "Player-1-2", qty = 80 } } },
    nil, {}, state)
  h.eq(mobs["npc:2546"].gold, 120)
  h.eq(next(mobs["npc:2546"].places), nil)
  local n = 0
  for _ in pairs(mobs) do n = n + 1 end
  h.eq(n, 1)
  M.credit(mobs, { kind = "item", link = LINEN, qty = 2, sources = { { guid = NODE, qty = 2 } } }, "Mine", {}, state)
  h.eq(mobs["obj:1731"].kind, "node")
end)

h.test("Mobs.copy keeps valid entries, merge adds them up", function()
  local a = { ["npc:1"] = { name = "Kobold", kind = "npc", kills = 2, looted = 2, gold = 50,
    items = { [2589] = 3 }, places = { Elwynn = 2 } }, bad = "x", ["npc:9"] = { kind = "npc", kills = "x" } }
  local b = { ["npc:1"] = { kind = "npc", kills = 1, looted = 1, gold = 10, items = { [2589] = 1, ["5:1"] = 1 },
    places = { Elwynn = 1, Westfall = 1 } }, ["obj:7"] = { kind = "node", kills = 0, looted = 1, gold = 0,
    items = {}, places = {} } }
  local c = M.copy(a)
  h.eq(c["npc:1"].items[2589], 3)
  h.eq(c.bad, nil)
  h.eq(c["npc:9"], nil)
  c["npc:1"].items[2589] = 99
  h.eq(a["npc:1"].items[2589], 3) -- a copy
  local m = M.merge(a, b)
  h.eq(m["npc:1"], { name = "Kobold", kind = "npc", kills = 3, looted = 3, gold = 60,
    items = { [2589] = 4, ["5:1"] = 1 }, places = { Elwynn = 3, Westfall = 1 } })
  h.eq(m["obj:7"].looted, 1)
  h.eq(M.merge(nil, nil), {})
end)

h.test("Mobs.scaleMoney scales each source of a money slot to your share", function()
  local slot = { kind = "money", qty = 300, sources = { { guid = A, qty = 200 }, { guid = B, qty = 100 } } }
  local s = M.scaleMoney(slot, 0.5)
  h.eq(s.qty, 150)
  h.eq({ s.sources[1].qty, s.sources[2].qty }, { 100, 50 })
  h.eq(slot.sources[1].qty, 200) -- the original stays
  local item = { kind = "item", link = LINEN, qty = 2, sources = { { guid = A, qty = 2 } } }
  h.eq(M.scaleMoney(item, 0.5), item)
end)

h.test("Mobs.noteWindow: each corpse seen once, each item once per corpse, taken or not", function()
  local mobs, state = {}, {}
  local WOOL = "|cffffffff|Hitem:2592::::::::60:::::::::|h[Wool Cloth]|h|r"
  local slots = {
    [1] = { kind = "item", link = LINEN, qty = 3, sources = { { guid = A, qty = 2 }, { guid = B, qty = 1 } } },
    [2] = { kind = "item", link = LINEN, qty = 1, sources = { { guid = A, qty = 1 } } }, -- a second stack
    [3] = { kind = "item", link = WOOL, qty = 1, sources = { { guid = A, qty = 1 } } },
    [4] = { kind = "money", qty = 50, sources = { { guid = B, qty = 50 } } },
  }
  M.noteWindow(mobs, slots, state)
  local a, b = mobs["npc:2546"], mobs["npc:2547"]
  h.eq(a.seen, 1); h.eq(a.drops[2589], 1); h.eq(a.drops[2592], 1)
  h.eq(b.seen, 1); h.eq(b.drops[2589], 1); h.eq(b.drops[2592], nil)
  -- the same corpse read again (reopened) adds nothing
  M.noteWindow(mobs, slots, state)
  h.eq(a.seen, 1); h.eq(a.drops[2589], 1)
  -- a second corpse of the same mob without wool: wool 1 of 2
  local A2 = "Creature-0-3110-0-12-2546-000012ABDD"
  M.noteWindow(mobs, { { kind = "item", link = LINEN, qty = 1, sources = { { guid = A2, qty = 1 } } } }, state)
  h.eq(a.seen, 2); h.eq(a.drops[2589], 2); h.eq(a.drops[2592], 1)
  -- copy and merge keep them; old entries without them stay without
  local c = M.merge(mobs, mobs)
  h.eq(c["npc:2546"].seen, 4); h.eq(c["npc:2546"].drops[2592], 2)
  local old = M.copy({ ["npc:9"] = { kind = "npc", kills = 0, looted = 1, gold = 0, items = {}, places = {} } })
  h.eq(old["npc:9"].seen, nil); h.eq(old["npc:9"].drops, nil)
end)
