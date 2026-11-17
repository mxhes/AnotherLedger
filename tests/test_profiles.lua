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

-- Export / import strings ------------------------------------------------------

h.test("encode only changed values", function()
  h.eq(P.encode({}), "LP1:")
  h.eq(P.encode({ alpha = 0.5, coinIcons = false }), "LP1:alpha=0.5;coinIcons=f")
  h.eq(P.encode({ alpha = 1, coinIcons = true }), "LP1:") -- the defaults
end)

h.test("encode keeps large numbers", function()
  local s = P.encode({ goalGold = 123456789 })
  h.eq(s:find("goalGold=123456789", 1, true) ~= nil, true)
end)

h.test("encode compares colors with the profile's preset", function()
  h.eq(P.encode({ colorPreset = "midnight", colorBackground = ns.Theme.preset("midnight").colors.panelTint }),
    "LP1:colorPreset=midnight")
  h.eq(P.encode({ colorPreset = "midnight", colorBackground = "261a0f" }),
    "LP1:colorBackground=261a0f;colorPreset=midnight")
end)

h.test("round trip", function()
  local s = { colorPreset = "tsm", colorText = "ff0000", tsmSource = "max(DBMarket;x=1%)",
    alpha = 0.35, goalGold = 987654321, coinIcons = false, fontOutline = "THICKOUTLINE" }
  local text = P.encode(s)
  h.eq(text:find("max(DBMarket;", 1, true), nil) -- ; escaped
  local back, taken, skipped = P.decode(text)
  h.eq(skipped, 0)
  h.eq(taken, 7)
  for k, v in pairs(s) do h.eq(back[k], v, k) end
end)

h.test("decode skips unknown and invalid", function()
  local back, taken, skipped = P.decode("  LP1:alpha=0.5;nope=1;alpha2=x;windowScale=9  ")
  h.eq(back, { alpha = 0.5 })
  h.eq(taken, 1)
  h.eq(skipped, 3)
  back, taken, skipped = P.decode("LP1:coinIcons=yes;alpha=abc;colorText=zz")
  h.eq(back, nil)
end)

h.test("decode rejects garbage", function()
  for _, bad in ipairs({ "", "hello", "LP2:alpha=1", "LP1:nope=1", "LP1:", 5 }) do
    local back, err = P.decode(bad)
    h.eq(back, nil, tostring(bad))
    h.eq(type(err), "string", tostring(bad))
  end
end)

h.test("decode ignores account options", function()
  local back, taken, skipped = P.decode("LP1:historyLimit=5;alpha=0.5")
  h.eq(back, { alpha = 0.5 })
  h.eq(taken, 1); h.eq(skipped, 1)
  h.eq(P.encode({ historyLimit = 5 }), "LP1:")
end)

-- Profiles section of the options -------------------------------------------

h.test("profiles section", function()
  local sections = O.sections()
  local last = sections[#sections]
  h.eq(last.id, "profiles")
  local keys = {}
  for _, spec in ipairs(last.specs) do
    keys[#keys + 1] = spec.key
    h.eq(#spec.label <= 24, true, spec.key)
    h.eq(type(spec.tooltip), "string", spec.key)
  end
  h.eq(table.concat(keys, ","), "profile,profileNew,profileCopy,profileRename,profileDelete,profileExport,profileImport")
end)

h.test("the profile dropdown reads and switches the character's profile", function()
  local db, chardb = fresh()
  ns.db, ns.chardb = db, chardb
  P.create(db, "Farm")
  h.eq(O.get(db, "profile"), "Default")
  local values = {}
  for _, c in ipairs(O.choices(O.spec("profile"))) do values[#values + 1] = c.value end
  h.eq(values, { "Default", "Farm" })
  O.set(db, "profile", "Farm")
  h.eq(P.active(chardb), "Farm")
  h.eq(db.settings == db.profiles.Farm, true)
  h.eq(db.settings.profile, nil) -- not stored in a profile
  O.applyAll(db) -- skips it
  h.eq(P.active(chardb), "Farm")
  h.eq(P.encode({ profile = "Farm" }), "LP1:")
  ns.db, ns.chardb = nil, nil
end)

h.test("rename keeps other characters on the renamed profile", function()
  local db, a = fresh()
  local b = { profile = "Farm" }
  P.create(db, "Farm")
  P.activate(db, a, "Farm")
  h.eq(P.rename(db, a, "Farm", "Gold"), true)
  P.beforeLogout(db)
  P.init(db, b) -- character B logs in later
  h.eq(P.active(b), "Gold")
  h.eq(db.settings == db.profiles.Gold, true)
  -- renamed twice, and a new profile under the old name wins over the map
  h.eq(P.rename(db, b, "Gold", "Silver"), true)
  local c = { profile = "Farm" }
  P.init(db, c)
  h.eq(P.active(c), "Silver")
  P.create(db, "Farm")
  local d = { profile = "Farm" }
  P.init(db, d)
  h.eq(P.active(d), "Farm")
end)

h.test("users: who uses a profile follows rename and delete", function()
  local db, chardb = fresh()
  P.create(db, "Farm")
  P.noteUser(db, "Wren-Realm", "Farm")
  P.noteUser(db, "Ada-Realm", "Farm")
  P.noteUser(db, "Bob-Realm", "Default")
  h.eq(P.users(db, "Farm"), { "Ada-Realm", "Wren-Realm" })
  P.rename(db, chardb, "Farm", "Gold")
  h.eq(P.users(db, "Farm"), {})
  h.eq(P.users(db, "Gold"), { "Ada-Realm", "Wren-Realm" })
  P.delete(db, chardb, "Gold")
  h.eq(P.users(db, "Default"), { "Ada-Realm", "Bob-Realm", "Wren-Realm" })
  P.noteUser(db, nil, "Default") -- unknown character: nothing noted
  h.eq(#P.users(db, "Default"), 3)
end)

h.test("the profile tooltip lists its characters", function()
  local db, chardb = fresh()
  ns.db, ns.chardb = db, chardb
  P.noteUser(db, "Wren-Realm", "Default")
  local text = ns.Tooltip.text(O.tooltip(O.spec("profile")))
  h.eq(text:find("Used by: Wren-Realm", 1, true) ~= nil, true)
  ns.db, ns.chardb = nil, nil
end)
