local h = ...
local ns = h.load({ "Util.lua", "Worth.lua" })
local W = ns.Worth

h.test("Worth.note saves a character's snapshot; bad input saves nothing", function()
  local db = {}
  h.eq(W.note(db, "Me-Realm", { bags = 100, bank = 50, money = 7, at = 9 }), true)
  h.eq(db.worth["Me-Realm"], { bags = 100, bank = 50, money = 7, at = 9 })
  -- never scanned bank: no bank field
  W.note(db, "Alt-Realm", { bags = 1, money = 2, at = 3 })
  h.eq(db.worth["Alt-Realm"].bank, nil)
  h.eq(W.note(db, "", { bags = 1, money = 2 }), false)
  h.eq(W.note(db, "X", { bags = "a", money = 2 }), false)
  h.eq(W.note(db, "X", nil), false)
  h.eq(W.note(nil, "X", { bags = 1, money = 1 }), false)
  h.eq(db.worth.X, nil)
end)

h.test("Worth.list: richest first with totals, the own character marked, and the sum", function()
  local db = { worth = {
    ["A-R"] = { bags = 10, money = 5, at = 1 },
    ["B-R"] = { bags = 100, bank = 200, money = 1, at = 2 },
    ["C-R"] = { bags = 15, money = 0, at = 3 },
    broken = "x",
  } }
  local list, sum = W.list(db, "A-R")
  h.eq(#list, 3)
  h.eq(list[1].key, "B-R"); h.eq(list[1].total, 301)
  -- A and C both 15: by name
  h.eq(list[2].key, "A-R"); h.eq(list[2].own, true)
  h.eq(list[3].key, "C-R"); h.eq(list[3].own, false)
  h.eq(sum, 331)
  local empty, none = W.list({}, "A-R")
  h.eq(#empty, 0); h.eq(none, 0)
end)

h.test("Worth.find matches a whole key or one prefix (case ignored); forget drops it", function()
  local db = { worth = { ["Alpha-Realm"] = {}, ["Alpine-Realm"] = {}, ["Beta-Realm"] = {} } }
  h.eq(W.find(db, "beta"), "Beta-Realm")
  h.eq(W.find(db, " ALPHA-REALM "), "Alpha-Realm")
  h.eq(W.find(db, "alp"), nil) -- two match
  h.eq(W.find(db, "gamma"), nil)
  h.eq(W.find(db, ""), nil)
  h.eq(W.forget(db, "Beta-Realm"), true)
  h.eq(db.worth["Beta-Realm"], nil)
  h.eq(W.forget(db, "Beta-Realm"), false)
end)
