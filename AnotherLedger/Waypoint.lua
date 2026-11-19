local ADDON, ns = ...

-- Waypoint to a farm spot (Daily farm strip). Pure: every client call goes
-- through the injected `env` (_G in the client).
--   place = { zone, sub, pos = { mapID, x, y } (x / y 0..1) }
local Waypoint = {}
ns.Waypoint = Waypoint

local function hasPos(place)
  local p = type(place) == "table" and place.pos
  return type(p) == "table" and type(p.mapID) == "number" and type(p.x) == "number" and type(p.y) == "number"
end

-- "Subzone (Zone)", or the zone alone when the place is the zone itself.
function Waypoint.name(place)
  if place.sub == nil or place.sub == place.zone then return place.zone end
  return place.sub .. " (" .. place.zone .. ")"
end

-- The TomTom /way line ("/way #2022 45.2 61.8 Wingrest"), or nil without a spot.
function Waypoint.text(place)
  if not hasPos(place) then return nil end
  local p = place.pos
  return string.format("/way #%d %.1f %.1f %s", p.mapID, p.x * 100, p.y * 100, place.sub or place.zone)
end

-- TomTom:AddWaypoint(mapID, x, y, { title, from }) with x / y 0..1 returns the
-- waypoint's uid (nil: nothing was set, e.g. a map TomTom does not know).
local function tomtom(env, place)
  local api = env.TomTom
  if type(api) ~= "table" or type(api.AddWaypoint) ~= "function" then return false end
  local p = place.pos
  local ok, uid = pcall(api.AddWaypoint, api, p.mapID, p.x, p.y, { title = Waypoint.name(place), from = "AnotherLedger" })
  return ok and uid ~= nil
end

-- UiMapPoint.CreateFromCoordinates, C_Map.SetUserWaypoint,
-- C_Map.CanSetUserWaypointOnMap and C_SuperTrack.SetSuperTrackedUserWaypoint.
-- Maps that do not allow a pin (caves and other sub-maps, cities, instances)
-- get none.
local function mapPin(env, place)
  local point, map, track = env.UiMapPoint, env.C_Map, env.C_SuperTrack
  if type(point) ~= "table" or type(point.CreateFromCoordinates) ~= "function"
    or type(map) ~= "table" or type(map.SetUserWaypoint) ~= "function" then return false end
  local p = place.pos
  if type(map.CanSetUserWaypointOnMap) == "function" then
    local okCan, can = pcall(map.CanSetUserWaypointOnMap, p.mapID)
    if not okCan or not can then return false end
  end
  local ok = pcall(function()
    map.SetUserWaypoint(point.CreateFromCoordinates(p.mapID, p.x, p.y))
    if type(track) == "table" and type(track.SetSuperTrackedUserWaypoint) == "function" then
      track.SetSuperTrackedUserWaypoint(true)
    end
  end)
  return ok
end

-- Sets the waypoint: TomTom when it is loaded, else the game's map pin.
-- Returns "tomtom", "map" or nil (no spot, or neither worked).
function Waypoint.set(env, place)
  if type(env) ~= "table" or not hasPos(place) then return nil end
  if tomtom(env, place) then return "tomtom" end
  if mapPin(env, place) then return "map" end
  return nil
end
