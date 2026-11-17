local h = ...
local ns = h.load({ "Util.lua", "Waypoint.lua" })
local W = ns.Waypoint

local place = { zone = "Waking Shores", sub = "Wingrest", pos = { mapID = 2022, x = 0.4523, y = 0.6181 } }

h.test("Waypoint.name is the subzone with its zone", function()
  h.eq(W.name(place), "Wingrest (Waking Shores)")
  h.eq(W.name({ zone = "Z", sub = "Z" }), "Z")
  h.eq(W.name({ zone = "Z" }), "Z")
end)

h.test("Waypoint.text is the TomTom /way line", function()
  h.eq(W.text(place), "/way #2022 45.2 61.8 Wingrest")
  h.eq(W.text({ zone = "Z", sub = "Z" }), nil)
  h.eq(W.text({ zone = "Z", pos = { mapID = 1, x = 0.5, y = 0.5 } }), "/way #1 50.0 50.0 Z")
end)

h.test("Waypoint.set prefers TomTom", function()
  local got
  local env = { TomTom = { AddWaypoint = function(self, m, x, y, opts)
    got = { m, x, y, opts.title, opts.from }
    return { m, x, y } -- TomTom returns the waypoint uid
  end } }
  h.eq(W.set(env, place), "tomtom")
  h.eq(got[1], 2022); h.near(got[2], 0.4523); h.near(got[3], 0.6181)
  h.eq(got[4], "Wingrest (Waking Shores)"); h.eq(got[5], "LootLedger")
end)

h.test("Waypoint.set falls back to the game's map pin", function()
  local pin, tracked
  local env = {
    TomTom = { AddWaypoint = function() error("broken") end },
    UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m, x, y } end },
    C_Map = { SetUserWaypoint = function(p) pin = p end },
    C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) tracked = v end },
  }
  h.eq(W.set(env, place), "map")
  h.eq(pin[1], 2022); h.eq(tracked, true)
  h.eq(W.set({}, place), nil)
  h.eq(W.set(env, { zone = "Z", sub = "A" }), nil)
  env.C_Map.SetUserWaypoint = function() error("no pin here") end
  env.TomTom = nil
  h.eq(W.set(env, place), nil)
end)

h.test("Waypoint.set: a TomTom call that sets nothing falls back to the map pin", function()
  local pin
  local env = {
    TomTom = { AddWaypoint = function() return nil end },
    UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m, x, y } end },
    C_Map = { SetUserWaypoint = function(p) pin = p end },
  }
  h.eq(W.set(env, place), "map")
  h.eq(pin[1], 2022)
end)

h.test("Waypoint.set: no map pin on a map that does not allow one", function()
  local pin
  local env = {
    UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m, x, y } end },
    C_Map = { SetUserWaypoint = function(p) pin = p end,
      CanSetUserWaypointOnMap = function(m) h.eq(m, 2022); return false end },
  }
  h.eq(W.set(env, place), nil)
  h.eq(pin, nil)
  env.C_Map.CanSetUserWaypointOnMap = function() return true end
  h.eq(W.set(env, place), "map")
end)
