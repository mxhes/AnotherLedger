# History Zones Sub-tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A **Sessions | Zones** sub-tab row in History; Zones groups the loot of all saved sessions plus the running one by zone -> subzone -> items, with time, value and gold per hour per place, and quest items in their own group.

**Architecture:** The running session records per place (zone, subzone) the looted quantities, the time spent and the raw gold (`Session.lua`, pure, `now` passed in). `History.snapshot` copies that into each archived entry. A pure `View.buildZones` aggregates entries into rows using the existing row layout and open/close pattern. `UI/Tabs.lua` gains generic sub-tabs; the Window shows a fourth header row while the selected tab has sub-tabs.

**Tech Stack:** Lua 5.1 WoW addon (Forever, Interface 16001), plain-Lua tests (`lua tests/run.lua`).

**Spec:** `docs/superpowers/specs/2026-11-15-history-zones-design.md`

## Global Constraints

- Lua 5.1 only (no `goto`, `//`, `table.unpack`). Run `lua tests/run.lua` from the repo root after every task; all tests pass.
- Files outside `UI/` stay pure (client calls injected / looked up at call time); `UI/` touches WoW globals only inside functions.
- Every user-visible text goes through `ns.L` with the English text as key; add German to `Locales/deDE.lua`.
- New client APIs carry `UNVERIFIED (check in client)` + a README checklist line: `GetSubZoneText`, `ZONE_CHANGED` / `ZONE_CHANGED_INDOORS` / `ZONE_CHANGED_NEW_AREA`, `C_Item.GetItemInfoInstant` class ID 12 (`Enum.ItemClass.Questitem`) for quest items.
- Money in copper; time in seconds.
- Quest items leave the totals **only in Zones**: Session tab, Sessions sub-tab and `History.snapshot` totals are unchanged.
- g/h only from loot with recorded time; never estimated.
- Raw gold counts per place only when `opts.includeGold` is on.
- Look values (heights, colors) go in `Theme.lua`.
- Edit Lua with the Write/Edit tools (backslashes in texture paths).
- Commits: `feat:` / `fix:` / `refactor:` one-line summary + short body, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Plan-level calls (deviations from the spec, argued)

- **Quest items are detected at view time, not stored as a flag.** `opts.isQuest(itemID)` (Ledger, via `C_Item.GetItemInfoInstant`, which needs no item cache) works for old sessions too and needs no `GET_ITEM_INFO_RECEIVED` handling. The spec's stored flag is dropped.
- **Running session time is read without mutation:** `Session.zoneSnapshot(session, now)` returns a copy that includes the open stretch. Used by the view and by `History.snapshot`.
- Quest-money from `QUEST_TURNED_IN` already goes through `Core.recordGold`; it counts at the current place like looted coins.
- `defaultSort` (login option) does not get "Gold per hour"; only the filter-bar button cycles to it, and only while Zones is shown.

## Data shapes (shared by all tasks)

```lua
-- session.zones and entry.zones (History):
zones = {
  [zoneLabel] = {                 -- Core.placeOf label: "Zone" or "Instance (Difficulty)"
    subs = {
      [subLabel] = {               -- GetSubZoneText(), or zoneLabel when empty
        time = seconds,            -- >= 0
        gold = copper,             -- >= 0
        items = { [itemKey] = qty },
      },
    },
  },
}
-- session.at = { zone = zoneLabel, sub = subLabel, since = timestamp or nil }
--   current place; `since` is set only while the clock runs.
```

## Review Focus

1. **Old saved sessions (no `zones`)** must still load, show unchanged in Sessions, and land in Zones as "No time recorded" (single place) or "Unknown place" (several / none) without g/h. Test in Task 3.
2. **Clock stopped / AFK / logout / reload** must not add time: time grows only between `start` and `stop`/`suspend`; `resume` restarts the stretch at `now`. Test in Task 1.
3. **Item looted before any zone is known** (`placeOf` returns nil, e.g. right at login) must still be counted in the session; in Zones it falls under "Unknown place". Test in Task 1 and Task 3.
4. **Saved sort "perHour" on other tabs** must sort like "ah" and the filter-bar label shows "Value"; `FilterBar.repair` must not throw it away. Test in Task 4.
5. **History entries pruned / History reset** must shrink Zones accordingly (it is rebuilt from `chardb.history` each refresh, nothing cached). Wiring test in Task 5.

---

### Task 1: Per-place recording in the session

**Files:**
- Modify: `LootPrice/Session.lua` (new functions; `new`, `start`, `stop`, `reset`, `suspend`, `resume`, `login` keep `zones` / `at` consistent)
- Test: `tests/test_session.lua`

**Interfaces:**
- Produces:
  - `Session.enterPlace(session, zone, sub, now)` — closes the open stretch (adds `now - since` to the old place's `time` if running), then sets `session.at = { zone, sub, since = running and now or nil }`. `zone == nil` sets `session.at = nil`. Same place again: no-op except closing nothing. `sub` nil/"" -> `zone`.
  - `Session.notePlaceLoot(session, key, qty)` — adds `qty` to `zones[at.zone].subs[at.sub].items[key]`; no `at` -> under zone `Session.UNKNOWN_PLACE` (the string key `"?"`), sub `"?"`.
  - `Session.notePlaceGold(session, copper)` — same placement for `gold`.
  - `Session.zoneSnapshot(session, now) -> zones` — deep copy of `session.zones` with the open stretch added (no mutation). Missing `zones` -> `{}`.
  - `Session.UNKNOWN_PLACE = "?"`.
  - Lifecycle: `new` creates `zones = {}`, `at = nil`; `stop` and `suspend` close the stretch and clear `at.since`; `start` and `resume` set `at.since = now` when `at` exists; `reset` empties `zones` and keeps `at` (with `since = now` if running); `login` adds `zones = {}` to old saved sessions and drops a malformed `zones` / `at`.

- [ ] **Step 1: Write the failing tests** in `tests/test_session.lua`:
  - `"Session.enterPlace adds time to the place that was left"`: new(0); enterPlace(s,"Z","A",0); enterPlace(s,"Z","B",100); enterPlace(s,"Y",nil,130) -> `s.zones.Z.subs.A.time == 100`, `s.zones.Z.subs.B.time == 30`, `s.at.zone == "Y"`, `s.at.sub == "Y"`.
  - `"Session place time only grows while the clock runs"`: new(0); enterPlace(s,"Z","A",0); stop(s,50); start(s,500); enterPlace(s,"Z","B",520) -> `A.time == 70`; suspend(s,600); resume(s,1000); `zoneSnapshot(s,1010).Z.subs.B.time == 90`; `s.zones.Z.subs.B.time == 80` (snapshot did not mutate).
  - `"Session.notePlaceLoot and notePlaceGold count at the current place, unknown without one"`: notePlaceLoot(s, 2589, 3) with no `at` -> `s.zones["?"].subs["?"].items[2589] == 3`; after enterPlace("Z","A"): notePlaceLoot(s,"2589:1",2) twice -> `items["2589:1"] == 4`; notePlaceGold(s, 500) -> `A.gold == 500`.
  - `"Session.reset empties zones, login repairs old sessions"`: reset -> `next(s.zones) == nil`, `s.at.zone == "Z"`; `Session.login({ startedAt=1, running=false, elapsedBase=0, items={} }, true, 5).zones` is a table; a saved `zones = "x"` becomes `{}`.

- [ ] **Step 2: Run** `lua tests/run.lua` — Expected: the four new tests FAIL (`enterPlace` nil).

- [ ] **Step 3: Implement** the functions above in `Session.lua`; extend the shape comment at the top. Times use `math.max(0, now - since)`.

- [ ] **Step 4: Run** `lua tests/run.lua` — Expected: all PASS.

- [ ] **Step 5: Commit** `feat: record loot, gold and time per zone and subzone`.

---

### Task 2: Core feeds the places; History stores them

**Files:**
- Modify: `LootPrice/Core.lua` (`Core.subzoneOf`, `Core.updatePlace`, `recordLoot`, `recordGold`, `startSession`, new zone events, `PLAYER_ENTERING_WORLD`)
- Modify: `LootPrice/History.lua` (`snapshot` copies `zones`; header comment)
- Modify: `README.md` (in-client checklist: `GetSubZoneText`, the three `ZONE_CHANGED*` events)
- Test: `tests/test_core.lua`, `tests/test_history.lua`, `tests/test_wiring.lua`

**Interfaces:**
- Consumes: Task 1 `Session.enterPlace`, `notePlaceLoot`, `notePlaceGold`, `zoneSnapshot`.
- Produces:
  - `Core.subzoneOf(env, zone) -> label` — pure over `env`; `env.GetSubZoneText()` non-empty string, else `zone`. `UNVERIFIED (check in client)`.
  - `Core.updatePlace()` — `local zone = Core.placeOf(_G)`; `Session.enterPlace(ns.session, zone, Core.subzoneOf(_G, zone), time())`. Called from `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`, `ZONE_CHANGED_NEW_AREA` (no redraw), every `PLAYER_ENTERING_WORLD` after the session exists, `Core.startSession` before starting, and at the top of `recordLoot` / `recordGold` (cheap safety net, no per-tick check).
  - `recordLoot` calls `Session.notePlaceLoot(ns.session, key, qty)` after a successful `Session.add`; `recordGold` calls `Session.notePlaceGold` after a successful `addGold`.
  - History entry gains `zones = Session.zoneSnapshot(session, now)` (only when `ns.Session.zoneSnapshot` exists; entries keep working without it).

- [ ] **Step 1: Write the failing tests**
  - `tests/test_core.lua` `"Core.subzoneOf uses the subzone, else the zone"`: `{ GetSubZoneText = function() return "Hall" end }` -> `"Hall"`; returns `""` -> `"Zone"`; missing function -> `"Zone"`; erroring function -> `"Zone"`.
  - `tests/test_history.lua` `"History.snapshot keeps the time and loot per place"`: session from the helper with `zones = { Z = { subs = { A = { time = 10, gold = 5, items = { [1] = 3 } } } } }`, `running = true, runningSince = 1000, at = { zone = "Z", sub = "A", since = 1000 }` -> `snapshot(s, lookup, 1100).zones.Z.subs.A.time == 110`, `.items[1] == 3`.
  - `tests/test_wiring.lua` `"wiring: loot and gold are recorded per zone and subzone"`: stub `env.GetRealZoneText` / `env.GetSubZoneText` returning mutable locals; `startWorld`; loot `LOOT` in "Waking Shores"/"Dragonheart Outpost"; change subzone to "Wingrest", fire `ZONE_CHANGED`; loot `lootMsg(2592, 2)` and money "You loot 5 Silver"; assert `ns.session.zones["Waking Shores"].subs["Dragonheart Outpost"].items[2589] == 3`, `...subs.Wingrest.items[2592] == 2`, `...subs.Wingrest.gold == 500`; `slash(ctx, "reset")` -> `ns.chardb.history[1].zones["Waking Shores"]` exists; `ctx.errors` empty.

- [ ] **Step 2: Run** `lua tests/run.lua` — Expected: new tests FAIL.

- [ ] **Step 3: Implement** in `Core.lua` and `History.lua` as in Interfaces; add the events to `events` (unknown ones are skipped by `Core.init`). Add the README checklist lines.

- [ ] **Step 4: Run** `lua tests/run.lua` — Expected: all PASS.

- [ ] **Step 5: Commit** `feat: track the zone and subzone of loot, gold and time`.

---

### Task 3: Pure Zones view

**Files:**
- Modify: `LootPrice/View.lua` (`View.buildZones`, `SORTS.perHour`, item-sort fallback in `collect`, opts doc comment)
- Modify: `LootPrice/Locales/deDE.lua`
- Test: `tests/test_view.lua`

**Interfaces:**
- Consumes: data shapes above; `History.valid`, `History.perHour`, `History.duration`; existing local `collect`, `addGold`, `View.applyRates`, `makeRow`.
- Produces:
  - `View.buildZones(entries, opts, open) -> view` where `entries` = list of `{ items, zones?, places? }` (History entries plus the running session as `{ items = session.items, zones = Session.zoneSnapshot(session, now), places = session.places }`), `open = { zone = label|nil, sub = label|nil }`. History entries failing `History.valid` are skipped; the running pseudo-entry carries `live = true` and skips that check.
  - `opts.isQuest(itemID) -> bool` (optional; nil = no quest items).
  - `View.QUEST_ZONE = "\1quest"`, `View.NO_TIME_SUB = "\1notime"`, `View.UNKNOWN_ZONE = "?"` (= `Session.UNKNOWN_PLACE`): internal keys; display texts `L["Quest items"]`, `L["No time recorded"]`, `L["Unknown place"]`.
  - Row fields: zone rows `zoneKey = label`; subzone rows `zoneKey`, `subKey`; quest group row `zoneKey = View.QUEST_ZONE`. Row `key`s: `"z:" .. zone`, `"s:" .. zone .. "\1" .. sub`, item rows keep their item key (an item appears once on screen: only one subzone is open). Each place row has `perHour` (copper/h or nil), `placeTime` (seconds), `value`, `vendorTotal`, `ahTotal`, `bestLineTotal = value`, `lastSeen` (newest item `lastSeen` in it), `quantity` (item count), `icon = "Interface\\Icons\\INV_Misc_Map_01"`, `hint`.
  - `view.kind = "zones"`, `view.history = true`.

**Aggregation rules (decided here):**
- Item details (`id`, `link`, `price`, `lastSeen`) come from `entry.items[key]`; quantities from `zones[...].items[key]`. Same key across entries/subzones of the same place sums.
- Entry without `zones`: if `Session.placeList(entry.places)` has exactly 1 label -> all its items and `entry.gold` go to that zone, sub `NO_TIME_SUB`; otherwise zone `UNKNOWN_ZONE`, sub `NO_TIME_SUB`. Time 0.
- `opts.isQuest(id)` true -> the item goes to the quest group (no subzones; open it with `open.zone == QUEST_ZONE`), whatever place it came from.
- Sub value = `collect(subItems, opts)` totals `.best` (+ `gold` when `opts.includeGold ~= false`). Zone value = sum of its subs. `perHour = History.perHour(sum of value of subs with time > 0, sum of their time)`; zones/subs with no time have `perHour = nil`.
- Place order: `SORTS[opts.sort]` over place rows, quest group always last. Subzones of the open zone sorted the same way. Items of the open subzone: `collect`'s order; `collect` maps sort `"perHour"` to `SORTS.ah`.
- `SORTS.perHour`: by `perHour` descending, nil after all numbers, then by name.
- Totals: footer `totals = { vendor, ah, best, unpriced, filtered }` over non-quest items of all places; `addGold(view, total place gold, opts.includeGold)`; `View.applyRates(view, total recorded time)`.
- Row name: `(open and "- " or "+ ") .. label .. "  " .. History.duration(time)` (no duration when time 0); subzone rows indented by `"    "`. Hint lines: time, value, raw gold, g/h (or `L["No time recorded"]`), then `L["Click to show the items"]` / `L["Click to collapse"]` (zone rows: `L["Click to show the subzones"]`).

- [ ] **Step 1: Write the failing tests** in `tests/test_view.lua` (load with `View.lua`, `History.lua`, `Session.lua`, prices `{ [1] = { ah = 100 }, [2] = { vendor = 10 }, [3] = { ah = 1000 } }`):
  - `"View.buildZones adds up places across sessions and ranks them"`: two entries, both with zone "Z" sub "A" (`time = 1800`, items `{[1] = 2}`), plus zone "Y" sub "B" (`time = 3600`, items `{[2] = 1}`, gold 50); `sort = "ah"` -> rows `[1].zoneKey == "Z"`, `value == 400`, `placeTime == 3600`, `perHour == 400`; `[2].zoneKey == "Y"`, `value == 60`.
  - `"View.buildZones opens a zone into subzones and a subzone into items"`: `open = { zone = "Z" }` -> row 2 has `subKey == "A"`; `open = { zone = "Z", sub = "A" }` -> row 3 is the item with `id == 1`, `quantity == 4`.
  - `"View.buildZones sorts by gold per hour, places without time last"`: sort `"perHour"`; a place with only a `NO_TIME_SUB` has `perHour == nil` and comes after the timed ones even with a higher value.
  - `"View.buildZones puts old sessions under their only place or Unknown place, without time"`: entry `{ items = {[1]=…qty 1}, places = { Z = 4 }, gold = 0 }` -> zone "Z" has a sub `NO_TIME_SUB`; zone `perHour` from timed subs only (timed value / timed time); entry with `places = { Z = 1, Y = 1 }` -> zone `UNKNOWN_ZONE`.
  - `"View.buildZones groups quest items last, outside the totals"`: `isQuest = function(id) return id == 3 end`; item 3 in zone "Z" -> last row `zoneKey == View.QUEST_ZONE`, `value == 1000`; `view.totals.best` excludes 1000; zone "Z" value excludes it.
  - `"View.buildZones honors includeGold"`: gold 50 in "Y" counts in `value` with `includeGold` default, not with `includeGold = false`.
  - `"collect sorts items by value under the perHour sort"`: `View.buildInventory(items, { sort = "perHour", lookup = … })` returns rows in value order.

- [ ] **Step 2: Run** `lua tests/run.lua` — Expected: new tests FAIL.

- [ ] **Step 3: Implement** `View.buildZones` and the sort changes per the rules above. Add German for every new `L[...]` key to `Locales/deDE.lua`.

- [ ] **Step 4: Run** `lua tests/run.lua` — Expected: all PASS (including `test_locale.lua`).

- [ ] **Step 5: Commit** `feat: zones view of all saved sessions`.

---

### Task 4: Generic sub-tabs, the History sub-tab row and the g/h sort button

**Files:**
- Modify: `LootPrice/UI/Tabs.lua` (spec field `subtabs`, `Tabs.subtabs`, `Tabs.subtab`, `Tabs.build`, History spec)
- Modify: `LootPrice/UI/Window.lua` (`header.row4`, `Window.setSubtabRow(shown)`)
- Modify: `LootPrice/Theme.lua` (`sizes.subtabHeight = 20`, comment; header height with row 4 = `headerHeight + headerRowHeight`)
- Modify: `LootPrice/UI/Ledger.lua` (`Ledger.subtab`, `Ledger.setSubtab`, `Ledger.zoneOpen`, `Ledger.toggleZone`, `viewOpts.isQuest`, row click, sub-tab strip attach)
- Modify: `LootPrice/UI/FilterBar.lua` (`FilterBar.ALL_SORTS`, `FilterBar.nextSort(current, sorts)`, `FilterBar.sortLabel(key, sorts)`, `FilterBar.setSorts(sorts)`)
- Modify: `LootPrice/DB.lua` (`subtab = {}` next to `tab`)
- Modify: `LootPrice/Locales/deDE.lua`, `README.md` (feature text, in-client checklist: `C_Item.GetItemInfoInstant` class 12)
- Test: `tests/test_tabs.lua`, `tests/test_filterbar.lua`

**Interfaces:**
- Consumes: Task 3 `View.buildZones`, `View.QUEST_ZONE`, row fields `zoneKey` / `subKey`; Task 1 `Session.zoneSnapshot`.
- Produces:
  - Tab spec field `subtabs = { { key = "sessions", label = L["Sessions"], build = fn, hasItem = fn?, sorts = {…}? }, { key = "zones", label = L["Zones"], build = fn, sorts = { "ah", "perHour", "vendor", "name", "recent" } } }`; first one is the default.
  - `Tabs.subtabs(key) -> list or nil`; `Tabs.subtab(key, subKey) -> sub spec` (unknown -> first); `Tabs.build(key, subKey, ctx) -> view` (sub spec's `build` when the tab has sub-tabs, else the tab's); `Tabs.sorts(key, subKey) -> list` (sub/tab `sorts`, default `FilterBar.SORTS`).
  - History sub-tab "sessions" = today's History `build`/`hasItem`; "zones" builds `ns.View.buildZones(history entries + running pseudo-entry, ctx.opts, ctx.ledger.zoneOpen)`, `hasItem` checks any entry's items.
  - `Ledger.subtab` (key for the shown tab), saved as `ns.db.subtab[tabKey]`; `Ledger.setSubtab(key)` resets `historyIndex`, `zoneOpen`, list offset, refreshes. `Ledger.toggleZone(zoneKey, subKey)`: clicking a zone row opens it (closes another), clicking it again closes it; a subzone row toggles `zoneOpen.sub`. `Ledger.zoneOpen = {}` when leaving the tab.
  - `Window.setSubtabRow(shown)`: shows/hides `header.row4` and sets the header height (84 or 112). `UNVERIFIED (check in client)` that the list area follows the header height change live.
  - `FilterBar.ALL_SORTS = { "ah", "vendor", "name", "recent", "perHour" }` (used by `repair`); `FilterBar.nextSort(current, sorts)` cycles inside `sorts` (default `FilterBar.SORTS`; a current key not in `sorts` -> `sorts[1]`); `FilterBar.sortLabel(key, sorts)` returns the "Value" label when `key` is not in `sorts`; label `perHour = L["Gold/h"]`. `FilterBar.setSorts(sorts)` updates the button label; Ledger calls it in `applyTab` / `setSubtab`.
  - `viewOpts.isQuest(itemID)`: `C_Item.GetItemInfoInstant` (or global `GetItemInfoInstant`), 6th return `== 12`; pcall, false on error. `UNVERIFIED (check in client)`.

- [ ] **Step 1: Write the failing tests**
  - `tests/test_tabs.lua` `"Tabs sub-tabs: default, unknown key and build dispatch"`: define a tab with two subtabs whose `build` return `{ which = "a" }` / `{ which = "b" }` -> `Tabs.subtab(k, nil).key == "a"`, `Tabs.subtab(k, "x").key == "a"`, `Tabs.build(k, "b", {}).which == "b"`; a tab without subtabs -> `Tabs.subtabs(k) == nil`, `Tabs.build` calls its own `build`; `Tabs.subtabs("history")[2].key == "zones"`.
  - `tests/test_filterbar.lua` `"FilterBar sort cycling respects the allowed sorts"`: `nextSort("recent", ZONES)` == `"ah"` where ZONES is the zones list; `nextSort("ah", ZONES) == "perHour"`; `nextSort("perHour")` == `"ah"` (default list); `sortLabel("perHour")` equals `sortLabel("ah")`; `repair({ sort = "perHour" }).sort == "perHour"`; `repair({ sort = "bogus" }).sort == "ah"`.

- [ ] **Step 2: Run** `lua tests/run.lua` — Expected: new tests FAIL.

- [ ] **Step 3: Implement** the pure parts (`Tabs.*`, `FilterBar.*`), then the client parts (Window row 4, Ledger state and clicks, sub-tab strip via `Tabs.strip(frame.header.row4, items, Ledger.setSubtab)` rebuilt or shown per tab — one strip per tab with sub-tabs, created at `Ledger.init`), Theme sizes, DB default, German texts, README.

- [ ] **Step 4: Run** `lua tests/run.lua` — Expected: all PASS. The "no unexpected globals leak" test still passes (no new named frames).

- [ ] **Step 5: Commit** `feat: Sessions / Zones sub-tabs in History`.

---

### Task 5: End-to-end wiring and docs

**Files:**
- Modify: `tests/test_wiring.lua`
- Modify: `README.md` (feature section for Zones, layout table unchanged unless a file was added, option list unchanged)

**Interfaces:**
- Consumes: everything above (`Ledger.setTab`, `Ledger.setSubtab`, `Ledger.toggleZone`, `L.list.onRowClick`, `L.view.rows`).

- [ ] **Step 1: Write the wiring tests**
  - `"wiring: the Zones sub-tab groups all sessions by zone and subzone"`: zone stubs as in Task 2; loot in "Waking Shores"/"Wingrest", reset; loot in "Ohn'ahran Plains"/"Teerakai", keep running; `L.setTab("history")`; `L.setSubtab("zones")` -> 2 zone rows (one from the running session); click row of "Waking Shores" -> next row has `subKey == "Wingrest"`; click that -> next row is the item with `quantity == 3`; click the zone row again -> collapsed; `ctx.ns.db.subtab.history == "zones"`; `ctx.errors` empty.
  - `"wiring: the sub-tab row only shows on History and the choice survives a reload"`: `setTab("session")` -> `frame.header.row4:IsShown() == false`; `setTab("history")` -> true; reboot with the same db and chardb -> `L.subtab == "zones"`.
  - `"wiring: quest items sit in their own group in Zones only"`: stub `env.C_Item.GetItemInfoInstant` returning class 12 for item 2592; loot it; Session tab `view.totals.best` includes it; Zones last row `zoneKey == View.QUEST_ZONE`, footer `totals.best` excludes it.
  - `"wiring: Zones follows History pruning"`: set the History option limit to 1 with two archived sessions in different zones -> Zones shows only the kept session's zone (plus the running one if it has loot).

- [ ] **Step 2: Run** `lua tests/run.lua` — Expected: PASS (these exercise finished code; a failure is a bug in Tasks 1-4 to fix before committing).

- [ ] **Step 3: Update README.md**: a "Zones" paragraph in the History section (what it shows, g/h only from recorded time, old sessions under "No time recorded" / "Unknown place", quest items group, Gold/h sort only there) and the in-client checklist items from Tasks 2 and 4 (if not yet added): zone events fire on subzone changes; `GetSubZoneText` names match the map; quest items land in the Quest group; the header grows by one row on History and the list follows.

- [ ] **Step 4: Run** `lua tests/run.lua` — Expected: all PASS.

- [ ] **Step 5: Commit** `feat: wiring tests and README for the Zones sub-tab`.
