# Farm waypoint — design

## Intent

The Daily farm strip names where to farm; this makes it take the player there.
Clicking the strip sets a waypoint to the spot in that subzone where the loot
happened, and a right-click gives the `/way` line to paste or share.

## Goals

- Record where loot and raw gold were picked up, per zone / subzone.
- Strip clicks:

  | Click | Does |
  | --- | --- |
  | Left | waypoint to the farm spot; opens History > Zones when the place has no position |
  | Shift + left | opens History > Zones at the place (the old left-click) |
  | Right | copy box with `/way #<mapID> <x> <y> <Subzone>` selected; nothing without a position |

- Waypoint: TomTom loaded → TomTom waypoint; else the game's own map pin,
  super-tracked.
- The hover text lists the three clicks (the waypoint lines only with a position).

## Non-goals / anti-goals

- No waypoints from History > Zones rows (strip only, for now).
- No clustering of camps; no positions inside instances (the client gives none).
- No new options.
- Anti-goal: a waypoint that drops you somewhere unrelated (wrong map, a
  default 0,0 position).

## Constraints

- Addons cannot write the clipboard: "copy" is the existing copy box
  (`UI/Export.lua`, `Export.show(text)`), text selected, Ctrl+C, Esc.
- History saved before this change has no positions; those places fall back
  to opening Zones.
- Pure code outside `UI/`; client calls injected or looked up at call time;
  every new API marked UNVERIFIED with a README checklist line.

## Approaches

1. **Running average per subzone (picked).** Each loot / gold event adds the
   player's map position to sums on the subzone slot:
   `pos = { [mapID] = { x = sumX, y = sumY, n = count } }`. The spot is the
   average on the map with the largest `n`. Three numbers per map per
   subzone; merges across sessions like time and gold. Weak spot: two
   separate camps in one subzone average to a point between them.
2. Densest grid cell of up to ~50 kept points per subzone. Finds the real
   camp, but History grows and merging/tests get heavier. Can replace 1
   later without changing the clicks.
3. Position at subzone entry. Usually the edge of the subzone. Dropped.

## How (decided)

- **Position** (Core, injected `env`): `C_Map.GetBestMapForUnit("player")`
  then `C_Map.GetPlayerMapPosition(mapID, "player"):GetXY()`; nil inside
  instances or when either call fails; x / y in 0..1. Positions of exactly
  0,0 are ignored.
- **Session**: `Session.notePlacePos(session, mapID, x, y)` adds to the
  current place's `pos`; called from `Core.recordLoot` / `Core.recordGold`
  next to `notePlaceLoot` / `notePlaceGold` (once per event, not per item
  quantity). `zoneSnapshot` copies `pos`; a bad `pos` is repaired on write
  (`notePlacePos`) and dropped on read (`Session.copyPos`). Quest turn-in
  money records no position; nothing is recorded inside any instance.
- **View**: `aggregateZones` sums `pos` per map across entries;
  `View.dailyFarm` places carry `pos = { mapID, x, y }` (averaged, map with
  most points) or nil.
- **Waypoint text** (pure): `/way #<mapID> <x*100 one decimal> <y*100 one decimal> <sub>`,
  e.g. `/way #2022 45.2 61.8 Wingrest`.
- **UI** (`UI/DailyFarm.lua`): `RegisterForClicks("LeftButtonUp", "RightButtonUp")`;
  TomTom via `TomTom:AddWaypoint(mapID, x, y, { title = sub, from = "LootPrice" })`;
  else `C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))`
  and `C_SuperTrack.SetSuperTrackedUserWaypoint(true)`. A chat line confirms
  ("Waypoint set: Wingrest (Waking Shores)").
- README: feature text, the clicks, saved data note, in-client checklist
  (both waypoint kinds, the copy box, no-position fallback).

## Left to the builder

- Where the waypoint call lives (a small pure-ish helper with injected env is
  preferred, so tests can check which API is used).
- German texts for the new strings.
