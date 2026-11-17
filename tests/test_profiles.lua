local h = ...
local ns = h.load({ "Util.lua", "Money.lua", "Theme.lua", "Tooltip.lua", "DB.lua", "Sources/Sources.lua", "Sources/TSM.lua",
  "Sources/Auctionator.lua", "Options.lua", "Profiles.lua" })
local P, O = ns.Profiles, ns.Options

local function fresh(settings, profile)
  local db = { settings = settings or {} }
  local chardb = { profile = profile }
  P.init(db, chardb)
  return db, chardb
end

h.test("init drops old settings", function()
  local db, chardb = fresh({ alpha = 0.5 })
  h.eq(O.get(db, "alpha"), 1)
  h.eq(db.profilesMigrated, true)
  h.eq(type(db.profiles.Default), "table")
  h.eq(db.settings == db.profiles.Default, true)
  h.eq(P.active(chardb), "Default")
end)

h.test("init keeps profiles on later logins", function()
  local db, chardb = fresh()
  O.set(db, "alpha", 0.4)
  P.beforeLogout(db)
  P.init(db, chardb)
  h.eq(O.get(db, "alpha"), 0.4)
end)

h.test("activate unknown name falls back to Default", function()
  local db, chardb = fresh(nil, "Gone")
  h.eq(P.active(chardb), "Default")
  h.eq(db.settings == db.profiles.Default, true)
  P.activate(db, chardb, "Nope")
  h.eq(P.active(chardb), "Default")
end)

h.test("create, copy, rename, delete", function()
  local db, chardb = fresh()
  O.set(db, "alpha", 0.3)
  h.eq(P.create(db, "Farm"), true)
  h.eq(db.profiles.Farm.alpha, nil) -- from defaults
  h.eq(P.create(db, "Copy", db.settings), true)
  h.eq(db.profiles.Copy.alpha, 0.3)
  db.profiles.Copy.alpha = 0.9
  h.eq(db.settings.alpha, 0.3) -- deep copy
  local ok, err = P.create(db, "farm")
  h.eq(ok, false); h.eq(type(err), "string")
  ok = P.create(db, string.rep("x", 33))
  h.eq(ok, false)
  ok = P.create(db, "   ")
  h.eq(ok, false)
  h.eq(P.create(db, string.rep("x", 32)), true)
  h.eq(P.rename(db, chardb, "Farm", "farm"), true) -- case only
  h.eq(db.profiles.farm ~= nil and db.profiles.Farm == nil, true)
  h.eq(P.rename(db, chardb, "farm", "Copy"), false)
  h.eq(P.rename(db, chardb, "Default", "Main"), false)
  h.eq(P.delete(db, chardb, "Default"), false)
  h.eq(P.delete(db, chardb, "farm"), true)
  h.eq(db.profiles.farm, nil)
end)

h.test("rename the active profile keeps it active", function()
  local db, chardb = fresh()
  P.create(db, "Farm")
  P.activate(db, chardb, "Farm")
  h.eq(P.rename(db, chardb, "Farm", "Gold"), true)
  h.eq(P.active(chardb), "Gold")
  h.eq(db.settings == db.profiles.Gold, true)
end)

h.test("delete active profile switches to Default", function()
  local db, chardb = fresh()
  P.create(db, "Farm")
  P.activate(db, chardb, "Farm")
  O.set(db, "alpha", 0.2)
  h.eq(P.delete(db, chardb, "Farm"), true)
  h.eq(P.active(chardb), "Default")
  h.eq(O.get(db, "alpha"), 1)
end)

h.test("activate applies the profile's options", function()
  local db, chardb = fresh()
  P.create(db, "Night", { colorPreset = "midnight" })
  ns.db = db
  P.activate(db, chardb, "Night")
  h.eq(ns.Theme.colorToHex(ns.Theme.colors.panelTint), ns.Theme.preset("midnight").colors.panelTint)
  P.activate(db, chardb, "Default")
  h.eq(ns.Theme.colorToHex(ns.Theme.colors.panelTint), "261a0f")
  ns.db = nil
end)

h.test("names order", function()
  local db = fresh()
  P.create(db, "zeta"); P.create(db, "Alpha"); P.create(db, "beta")
  h.eq(P.names(db), { "Default", "Alpha", "beta", "zeta" })
end)

h.test("account options are not in profiles", function()
  local db, chardb = fresh()
  O.set(db, "historyLimit", 5)
  P.create(db, "Farm")
  P.activate(db, chardb, "Farm")
  h.eq(O.get(db, "historyLimit"), 5)
end)
