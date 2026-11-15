# Farm waypoint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Left-click on the Daily farm strip sets a waypoint (TomTom, else the game's map pin) to where the loot happened; Shift-click opens Zones; right-click shows the `/way` line in the copy box.

**Architecture:** Core reads the player's map position on each loot / gold event and Session sums it per subzone (`pos = { [mapID] = { x, y, n } }`). `View.aggregateZones` merges the sums across History, `View.dailyFarm` gives each place an averaged `pos`. A new pure `Waypoint.lua` formats the `/way` text and sets the waypoint through an injected env. `UI/DailyFarm.lua` routes the three clicks.

**Tech Stack:** Lua 5.1 WoW addon, plain-Lua tests (`lua tests/run.lua`).

**Spec:** `docs/superpowers/specs/2026-11-15-farm-waypoint-design.md`

## Global Constraints

- Lua 5.1 only; run `lua tests/run.lua` after every step, all pass.
- Files outside `UI/` pure; client calls through an injected `env` (`_G` in the client).
- Texts through `ns.L`, German in `Locales/deDE.lua`.
- Every new client API carries `UNVERIFIED (check in client)` and a README checklist line.
- New `.lua` file: add to `.toc` and to the README layout table.
- Write Lua with the Write / Edit tools; never put raw control characters in source (`"\1"` escapes only).
- Commits `feat:` / `fix:` with a short body, ending `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Inside an instance / API missing / position nil** → nothing recorded, no error; strip left-click falls back to Zones.
2. **Old History without `pos`, or a malformed `pos`** (non-table, non-number fields, n = 0) → ignored, never a nil-arithmetic error.
3. **A subzone looted on two maps** → the map with the larger `n` wins; its own average, not a mix of maps.
4. **TomTom present but `AddWaypoint` errors** → falls back to the game pin, no Lua error to the user.
5. **Position exactly 0,0** (the client's "unknown") → not recorded.

---

### Task 1: Record positions

**Files:**
- Modify: `LootPrice/Core.lua`, `LootPrice/Session.lua`
- Test: `tests/test_core.lua`, `tests/test_session.lua`, `tests/test_wiring.lua`

**Interfaces:**
- Produces:
  - `Core.positionOf(env) -> mapID, x, y | nil` (pure over `env`): `env.C_Map.GetBestMapForUnit("player")`, then `env.C_Map.GetPlayerMapPosition(mapID, "player")` and its `:GetXY()`; nil when any call is missing / fails / returns nil, when x or y is outside 0..1, or when both are 0. UNVERIFIED comment.
  - `Session.notePlacePos(session, mapID, x, y)`: adds to the current place slot (`currentSlot`): `slot.pos[mapID] = { x = sumX, y = sumY, n = count }`; ignores non-number input.
  - `Session.zoneSnapshot` copies `pos` (only entries with number x, y and n > 0).
  - `Core.recordLoot` / `Core.recordGold` call `Session.notePlacePos(ns.session, Core.positionOf(_G))` once per event, right after `notePlaceLoot` / `notePlaceGold`.

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/test_core.lua
h.test("Core.positionOf reads the player's map position", function()
  local pos = { GetXY = function() return 0.452, 0.618 end }
  local env = { C_Map = { GetBestMapForUnit = function(u) h.eq(u, "player"); return 2022 end,
    GetPlayerMapPosition = function(m, u) h.eq(m, 2022); h.eq(u, "player"); return pos end } }
  local m, x, y = Core.positionOf(env)
  h.eq(m, 2022); h.near(x, 0.452); h.near(y, 0.618)
end)

h.test("Core.positionOf gives nil without a usable position", function()
  h.eq(Core.positionOf({}), nil)
  h.eq(Core.positionOf({ C_Map = { GetBestMapForUnit = function() return nil end } }), nil)
  local function env(px, py)
    return { C_Map = { GetBestMapForUnit = function() return 1 end,
      GetPlayerMapPosition = function() return { GetXY = function() return px, py end } end } }
  end
  h.eq(Core.positionOf(env(0, 0)), nil)
  h.eq(Core.positionOf(env(1.5, 0.2)), nil)
  h.eq(Core.positionOf({ C_Map = { GetBestMapForUnit = function() return 1 end,
    GetPlayerMapPosition = function() return nil end } }), nil)
  h.eq(Core.positionOf({ C_Map = { GetBestMapForUnit = function() error("x") end } }), nil)
end)

-- tests/test_session.lua
h.test("Session.notePlacePos sums positions per map on the current place", function()
  local s = S.new(0)
  S.enterPlace(s, "Z", "A", 0)
  S.notePlacePos(s, 2022, 0.4, 0.6)
  S.notePlacePos(s, 2022, 0.6, 0.8)
  S.notePlacePos(s, 2023, 0.1, 0.1)
  S.notePlacePos(s, nil, 0.1, 0.1)
  S.notePlacePos(s, 2022, "x", 0.1)
  local pos = s.zones.Z.subs.A.pos
  h.near(pos[2022].x, 1.0); h.near(pos[2022].y, 1.4); h.eq(pos[2022].n, 2)
  h.eq(pos[2023].n, 1)
  local snap = S.zoneSnapshot(s, 0)
  h.eq(snap.Z.subs.A.pos[2022].n, 2)
  s.zones.Z.subs.A.pos[9] = { x = "bad", n = 1 }
  h.eq(S.zoneSnapshot(s, 0).Z.subs.A.pos[9], nil)
end)
```

Wiring (`tests/test_wiring.lua`, next to the Daily farm tests; extend `bootInZone`'s env with a `C_Map` stub reading `ctx.pos = { map, x, y }`):

```lua
h.test("wiring: loot and gold record the map position of their place", function()
  local ctx = bootInZone("Waking Shores", "Wingrest")
  ctx.pos = { 2022, 0.4, 0.6 }
  startWorld(ctx, false)
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  ctx.pos = { 2022, 0.6, 0.8 }
  fire(ctx, "CHAT_MSG_MONEY", "You loot 5 Silver")
  ctx.pos = nil -- e.g. inside an instance
  fire(ctx, "CHAT_MSG_LOOT", LOOT)
  local pos = ctx.ns.session.zones["Waking Shores"].subs.Wingrest.pos[2022]
  h.eq(pos.n, 2); h.near(pos.x, 1.0)
  ctx.now = ctx.now + 60
  slash(ctx, "reset")
  h.eq(ctx.ns.chardb.history[1].zones["Waking Shores"].subs.Wingrest.pos[2022].n, 2)
  h.eq(ctx.errors, {})
end)
```

- [ ] **Step 2: Run to verify they fail** — `lua tests/run.lua`; Expected: FAIL (`positionOf` / `notePlacePos` nil).
- [ ] **Step 3: Implement** the interfaces above.
- [ ] **Step 4: Run the tests** — `lua tests/run.lua`; Expected: all pass.
- [ ] **Step 5: Commit** `feat: record the map position of loot per place`

---

### Task 2: Averaged spot and the waypoint module

**Files:**
- Create: `LootPrice/Waypoint.lua` (in `.toc` after `View.lua`)
- Modify: `LootPrice/View.lua`, `LootPrice/LootPrice.toc`, `LootPrice/Locales/deDE.lua`
- Test: `tests/test_view.lua`, new `tests/test_waypoint.lua`

**Interfaces:**
- Consumes: `pos` on History subzones (Task 1).
- Produces:
  - `aggregateZones` slots carry `pos` sums merged across entries (valid entries only: number x, y, n > 0).
  - `View.dailyFarm` places (`best` and `runnersUp`) carry `pos = { mapID = number, x = 0..1, y = 0..1 }` or nil: the map with the largest `n` (ties: lower mapID), `x = sumX / n`, `y = sumY / n`.
  - `ns.Waypoint.text(place) -> string | nil`: `string.format("/way #%d %.1f %.1f %s", mapID, x * 100, y * 100, sub)` (`sub` = `place.sub`, or `place.zone` when `sub` is nil); nil without `place.pos`.
  - `ns.Waypoint.set(env, place) -> "tomtom" | "map" | nil`: with `place.pos`, tries `env.TomTom:AddWaypoint(mapID, x, y, { title = name, from = "LootPrice" })` (name = `DailyFarm`-style "Sub (Zone)" passed in as `place.title` or built from sub / zone) under pcall; on success `"tomtom"`. Else `env.C_Map.SetUserWaypoint(env.UiMapPoint.CreateFromCoordinates(mapID, x, y))` and `env.C_SuperTrack.SetSuperTrackedUserWaypoint(true)` under pcall → `"map"`. Nil when neither works or no pos. UNVERIFIED comments on all four APIs.

- [ ] **Step 1: Write the failing tests**

```lua
-- tests/test_view.lua (Daily farm section)
h.test("View.dailyFarm gives each place the averaged spot of its main map", function()
  local a = zentry({ [1] = 4 }, { Z = { subs = { A = { time = 3600, gold = 0, items = { [1] = 4 },
    pos = { [2022] = { x = 0.8, y = 1.2, n = 2 }, [2023] = { x = 0.5, y = 0.5, n = 1 } } } } } })
  local b = zentry({ [1] = 1 }, { Z = { subs = { A = { time = 600, gold = 0, items = { [1] = 1 },
    pos = { [2022] = { x = 0.4, y = 0.6, n = 1 }, [7] = { x = "bad", y = 1, n = 1 } } } } } })
  local f = V.dailyFarm({ a, b }, { lookup = zlookup }, 0)
  h.eq(f.best.pos.mapID, 2022)
  h.near(f.best.pos.x, 0.4); h.near(f.best.pos.y, 0.6)
  local old = V.dailyFarm({ zentry({ [1] = 4 }, { Z = { subs = { A = zsub(3600, { [1] = 4 }) } } }) },
    { lookup = zlookup }, 0)
  h.eq(old.best.pos, nil)
end)

-- tests/test_waypoint.lua (h.load({ "Util.lua", "Waypoint.lua" }))
local place = { zone = "Waking Shores", sub = "Wingrest", pos = { mapID = 2022, x = 0.4523, y = 0.6181 } }

h.test("Waypoint.text is the TomTom /way line", function()
  h.eq(W.text(place), "/way #2022 45.2 61.8 Wingrest")
  h.eq(W.text({ zone = "Z", sub = "Z" }), nil)
end)

h.test("Waypoint.set prefers TomTom", function()
  local got
  local env = { TomTom = { AddWaypoint = function(self, m, x, y, opts) got = { m, x, y, opts.title } end } }
  h.eq(W.set(env, place), "tomtom")
  h.eq(got[1], 2022); h.near(got[2], 0.4523); h.eq(got[4], "Wingrest (Waking Shores)")
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
end)
```

- [ ] **Step 2: Run to verify they fail** — Expected: FAIL (`pos` nil on places; `ns.Waypoint` nil — add the file to the `.toc` first so the wiring test still loads).
- [ ] **Step 3: Implement** the interfaces above.
- [ ] **Step 4: Run the tests** — Expected: all pass.
- [ ] **Step 5: Commit** `feat: averaged farm spot and the waypoint module`

---

### Task 3: Strip clicks, hover text, README

**Files:**
- Modify: `LootPrice/UI/DailyFarm.lua`, `LootPrice/Locales/deDE.lua`, `README.md`
- Test: `tests/test_dailyfarm.lua`, `tests/test_wiring.lua`

**Interfaces:**
- Consumes: `best.pos`, `ns.Waypoint.text`, `ns.Waypoint.set` (Task 2); `ns.UI.Export.show(text)`; `ns.Util.say`.
- Produces:
  - `DailyFarm.click(button, shift)` (called from `OnClick(self, button)` with `IsShiftKeyDown()`): `"RightButton"` → `Export.show(Waypoint.text(best))` when there is a text, else nothing; `"LeftButton"` with shift, or without `best.pos` → `Ledger.showFarm`; else `Waypoint.set(_G, best)` and `say(L["Waypoint set: "] .. placeName(best))`; when `set` returns nil, `say(L["No waypoint could be set."])`.
  - `RegisterForClicks("LeftButtonUp", "RightButtonUp")` in `attach`.
  - `DailyFarm.hint(farm)`: the last line `L_CLICK` becomes, with `best.pos`, `L["Click: waypoint"]`, `L["Shift-click: open it in Zones"]`, `L["Right-click: copy the /way line"]`; without `best.pos` the old `L["Click to open it in Zones"]`.

- [ ] **Step 1: Write the failing tests**

Pure (`tests/test_dailyfarm.lua`): `hint` of a farm with `best.pos` contains `ns.L["Click: waypoint"]` and `ns.L["Right-click: copy the /way line"]` and not `ns.L["Click to open it in Zones"]`; without `pos` the reverse.

Wiring (`tests/test_wiring.lua`, `bootWithFarm` with `ctx.pos = { 2022, 0.4, 0.6 }` set before the loot; stub `env.IsShiftKeyDown = function() return ctx.shift end`, `env.TomTom` with a recording `AddWaypoint`):

```lua
h.test("wiring: strip clicks set a waypoint, open Zones, show the /way line", function()
  -- left-click: TomTom gets 2022 / 0.4 / 0.6, a chat line names the place, tab unchanged
  -- shift-click: tab history, subtab zones, zoneOpen.sub == "Wingrest"
  -- right-click: Export frame shown with text "/way #2022 40.0 60.0 Wingrest"
end)

h.test("wiring: a place without a position opens Zones on click", function()
  -- bootWithFarm without ctx.pos: left-click opens Zones; right-click shows no copy box
end)
```

(Drive clicks with `DF.button._scripts.OnClick(DF.button, "LeftButton")`; read the export text from `ctx.ns.UI.Export.frame.text`.)

- [ ] **Step 2: Run to verify they fail.**
- [ ] **Step 3: Implement** the interfaces above; German texts.
- [ ] **Step 4: README** — Daily farm feature text (the three clicks; positions recorded from now on, none in instances; TomTom else the game pin), `Waypoint.lua` in the layout table, saved state note (`pos` per subzone), in-client checklist: `C_Map.GetBestMapForUnit` / `GetPlayerMapPosition` give the minimap coordinates; TomTom waypoint and arrow; without TomTom the map pin is set and tracked (`C_Map.SetUserWaypoint`, `UiMapPoint.CreateFromCoordinates`, `C_SuperTrack.SetSuperTrackedUserWaypoint`); right-click copy box; `/way` line pasted into chat with TomTom gives the same spot.
- [ ] **Step 5: Run the tests** — Expected: all pass.
- [ ] **Step 6: Commit** `feat: daily farm waypoint clicks`
