# Daily farm Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A strip at the top of the Ledger window names the character's best farming subzone by gold per hour at current prices, with runner-ups and a slow-selling note.

**Architecture:** A pure `View.dailyFarm` reuses the History Zones aggregation (`aggregateZones`, `collect`) over saved History only. `Ledger.buildView` attaches its result to every view as `view.dailyFarm`; a new ledger part `UI/DailyFarm.lua` draws it on a new header row between the filter row and the tab row, and a click opens History → Zones at that subzone.

**Tech Stack:** Lua 5.1 WoW addon, plain-Lua tests (`lua tests/run.lua`).

**Spec:** `docs/superpowers/specs/2026-11-15-daily-farm-design.md`

## Global Constraints

- Lua 5.1 only (no `goto`, `//`, `table.unpack`); run `lua tests/run.lua` after every step, all pass.
- Files outside `UI/` stay pure; `UI/` touches WoW globals only inside functions.
- Every text through `ns.L` with the German text in `Locales/deDE.lua`; colors / sizes in `Theme.lua`.
- New options only via `Options.define` + default in `DB.defaults.settings`; the UI never names an option.
- Client APIs not confirmed carry `UNVERIFIED (check in client)` and a README checklist line.
- Write Lua with the Write / Edit tools (backslashes in paths).
- Commits: `feat:` one-line summary + short body, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A character with no History, or only places under the minimum time** → strip hidden, no error, header back to its normal height.
2. **The running session** must not change the pick (loot in a new place during play leaves `view.dailyFarm` unchanged).
3. **The filter bar** (search text, quality, minimum value) must not change the pick: Daily farm ignores `opts.filter`.
4. **Items with no price at all** in a place → valued 0, never a nil-arithmetic error; places with value 0 can still lose but never crash.
5. **`showMarket` off or no TSM** (`opts.market == nil`, rows without `rateLevel`) → `slow` is nil, no note.

---

### Task 1: `View.dailyFarm` (pure ranking)

**Files:**
- Modify: `LootPrice/View.lua` (new section after `View.buildZones`)
- Test: `tests/test_view.lua` (new section after the History Zones tests; reuse `zentry`, `zsub`, `zlookup`)

**Interfaces:**
- Produces: `View.dailyFarm(entries, opts, minSeconds) -> farm | nil`
  - `entries`: History entries (array; the caller passes saved History only).
  - `opts`: View options (`lookup`, `itemInfo`, `isQuest`, `includeGold`, `market`); `opts.filter` and `opts.sort` are ignored.
  - `minSeconds`: number; a subzone needs `time >= minSeconds`.
  - `farm = { best = place, runnersUp = { place, place? }, slow = { names = { string, ... } } | nil }`
  - `place = { zone = string, sub = string, time = seconds, value = copper, perHour = copper }`
  - nil when no subzone qualifies.

- [ ] **Step 1: Write the failing tests**

```lua
-- Daily farm
local function farmEntries()
  return {
    zentry({ [1] = 4, [3] = 1 }, {
      Z = { subs = { A = zsub(3600, { [1] = 4 }), Short = zsub(60, { [3] = 1 }) } },
      Y = { subs = { B = zsub(1800, {}, 300) } },
    }),
  }
end

h.test("View.dailyFarm picks the subzone with the best gold per hour", function()
  local f = V.dailyFarm(farmEntries(), { lookup = zlookup }, 1200)
  h.eq(f.best.zone, "Y"); h.eq(f.best.sub, "B")
  h.eq(f.best.perHour, 600); h.eq(f.best.time, 1800); h.eq(f.best.value, 300)
  h.eq(#f.runnersUp, 1)
  h.eq(f.runnersUp[1].sub, "A"); h.eq(f.runnersUp[1].perHour, 400)
end)

h.test("View.dailyFarm skips places under the minimum time, quest items and no-time loot", function()
  -- "Short" (60 s, 1000c/min) would win without the minimum.
  local f = V.dailyFarm(farmEntries(), { lookup = zlookup }, 1200)
  for _, p in ipairs(f.runnersUp) do h.eq(p.sub ~= "Short", true) end
  local quest = V.dailyFarm(farmEntries(), { lookup = zlookup, isQuest = function(id) return id == 1 end }, 1200)
  h.eq(quest.best.sub, "B"); h.eq(#quest.runnersUp, 1); h.eq(quest.runnersUp[1].perHour, 0)
  h.eq(V.dailyFarm({ zentry({ [1] = 9 }, nil, { "Z" }) }, { lookup = zlookup }, 0), nil)
end)

h.test("View.dailyFarm returns nil without qualifying places", function()
  h.eq(V.dailyFarm({}, { lookup = zlookup }, 1200), nil)
  h.eq(V.dailyFarm(farmEntries(), { lookup = zlookup }, 7200), nil)
  h.eq(V.dailyFarm(nil, {}, 0), nil)
end)

h.test("View.dailyFarm keeps at most two runner-ups, ties go to more time", function()
  local e = zentry({ [1] = 8 }, { Z = { subs = {
    A = zsub(3600, { [1] = 2 }), B = zsub(7200, { [1] = 4 }), C = zsub(1800, { [1] = 1 }), D = zsub(1800, {}),
  } } })
  local f = V.dailyFarm({ e }, { lookup = zlookup }, 0)
  h.eq(f.best.sub, "B") -- 200/h like A and C, most time
  h.eq(#f.runnersUp, 2)
  h.eq(f.runnersUp[1].sub, "A"); h.eq(f.runnersUp[2].sub, "C")
end)

h.test("View.dailyFarm ignores the filter and raw gold follows includeGold", function()
  local f = V.dailyFarm(farmEntries(), { lookup = zlookup, filter = { search = "nothing" } }, 1200)
  h.eq(f.best.sub, "B")
  f = V.dailyFarm(farmEntries(), { lookup = zlookup, includeGold = false }, 1200)
  h.eq(f.best.sub, "A")
end)

h.test("View.dailyFarm flags slow selling only with market data", function()
  local lookup = function(id)
    if id == 1 then return { ah = 100, saleRate = 0.01 } end
    return { ah = 50, saleRate = 0.9 }
  end
  local e = zentry({ [1] = 2, [2] = 1 }, { Z = { subs = { A = zsub(3600, { [1] = 2, [2] = 1 }) } } })
  local t = { rateGood = 0.5, rateOk = 0.1 }
  local f = V.dailyFarm({ e }, { lookup = lookup, market = t }, 0)
  h.eq(#f.slow.names, 1); h.eq(f.slow.names[1], "I1")
  h.eq(V.dailyFarm({ e }, { lookup = lookup }, 0).slow, nil)
  local fast = function() return { ah = 100, saleRate = 0.9 } end
  h.eq(V.dailyFarm({ e }, { lookup = fast, market = t }, 0).slow, nil)
  local unpriced = V.dailyFarm({ zentry({ [9] = 1 }, { Z = { subs = { A = zsub(3600, { [9] = 1 }) } } }) },
    { lookup = function() return nil end, market = t }, 0)
  h.eq(unpriced.best.value, 0); h.eq(unpriced.slow, nil)
end)
```

(`zentry` items have no `itemInfo`, so row names come from the link: `"I1"`. Adjust the name assertion to whatever `link("I1")` yields in this file if it differs.)

- [ ] **Step 2: Run to verify they fail**

Run: `lua tests/run.lua`
Expected: FAIL, `attempt to call field 'dailyFarm' (a nil value)`.

- [ ] **Step 3: Implement `View.dailyFarm(entries, opts, minSeconds)` in `LootPrice/View.lua`**

- Build a local options table from `opts` with `filter = nil` (copy the fields; do not mutate the caller's table, it is the shared `viewOpts`).
- `aggregateZones(entries, opts.isQuest)`; drop the quest map. Skip `sub == View.NO_TIME_SUB` and `zone == View.UNKNOWN_ZONE`.
- Per subzone: `collect(s.items, o)` → `value = t.best + (includeGold ~= false and s.gold or 0)`, `perHour = ns.History.perHour(value, s.time)`; keep when `s.time > 0 and s.time >= minSeconds`.
- Sort: `perHour` desc, then `time` desc, then `zone .. sub` asc (deterministic). `best` = first, `runnersUp` = next two.
- Slow (only `best`): over its rows, `slowAh` = sum of `ahTotal` where `rateLevel == "bad"`, `allAh` = sum of all `ahTotal`; `slow = { names = ... }` when `allAh > 0 and slowAh * 2 > allAh`, names of the bad rows by `ahTotal` desc, at most 5. Otherwise nil.

- [ ] **Step 4: Run the tests**

Run: `lua tests/run.lua`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add LootPrice/View.lua tests/test_view.lua
git commit -m "feat: View.dailyFarm ranks saved places by gold per hour"
```

---

### Task 2: Options and the ledger wiring

**Files:**
- Modify: `LootPrice/DB.lua` (`DB.defaults.settings`), `LootPrice/Options.lua`, `LootPrice/UI/Ledger.lua`, `LootPrice/Locales/deDE.lua`
- Test: `tests/test_options.lua` (or wherever option defaults are tested; follow the existing pattern), `tests/test_wiring.lua`

**Interfaces:**
- Consumes: `View.dailyFarm` (Task 1).
- Produces:
  - settings `dailyFarm` (boolean, default `true`) and `dailyFarmMinutes` (number, default `20`, slider 5–120 step 5), both `category = "display"`, `apply = refreshUI`.
  - `view.dailyFarm` on every view built by `Ledger.buildView` (nil when the option is off or nothing qualifies).
  - `Ledger.showFarm(zone, sub)`: switches to tab `"history"`, sub-tab `"zones"`, sets `Ledger.zoneOpen = { zone = zone, sub = sub }`, refreshes.

- [ ] **Step 1: Write the failing tests**

Options test: `Options.get(db, "dailyFarm") == true`, `Options.get(db, "dailyFarmMinutes") == 20`, and a stored `dailyFarmMinutes = 500` normalizes into the 5–120 range (match how the existing slider normalize tests assert).

Wiring test in `tests/test_wiring.lua`, modelled on "wiring: the Zones sub-tab groups all sessions by zone and subzone" (line ~1283), with a `chardb.history` holding one entry whose `zones` has `Z.subs.A` (3600 s, linen x3) and `Y.subs.B` (600 s, linen x9):

```lua
h.test("wiring: the daily farm is picked from saved History only", function()
  -- boot with that chardb, startWorld, show the window
  local farm = ctx.ns.UI.Ledger.view.dailyFarm
  h.eq(farm.best.zone, "Z"); h.eq(farm.best.sub, "A") -- B is under 20 min
  -- loot in the running session at another place: the pick stays
  -- (fire zone change to "X", fire CHAT_MSG_LOOT LOOT, refresh)
  h.eq(ctx.ns.UI.Ledger.view.dailyFarm.best.sub, "A")
  -- option off: no farm
  ctx.ns.Options.set(ctx.ns.db, "dailyFarm", false); ctx.ns.UI.Ledger.refresh()
  h.eq(ctx.ns.UI.Ledger.view.dailyFarm, nil)
end)

h.test("wiring: showFarm opens History Zones at the place", function()
  -- same boot; ctx.ns.UI.Ledger.showFarm("Z", "A")
  h.eq(ctx.ns.UI.Ledger.tab, "history"); h.eq(ctx.ns.UI.Ledger.subtab, "zones")
  h.eq(ctx.ns.UI.Ledger.zoneOpen.zone, "Z"); h.eq(ctx.ns.UI.Ledger.zoneOpen.sub, "A")
end)
```

(Use the file's real helpers and the real option setter name; the comments mark what each block drives.)

- [ ] **Step 2: Run to verify they fail**

Run: `lua tests/run.lua`
Expected: FAIL on the new tests (`dailyFarm` nil / `showFarm` nil).

- [ ] **Step 3: Implement**

- `DB.defaults.settings`: `dailyFarm = true`, `dailyFarmMinutes = 20`.
- `Options.define` both (labels `L["Show the daily farm"]`, `L["Daily farm: minimum time in a place"]`, format minutes like the existing duration sliders).
- `Ledger.buildView`: after `Tabs.build`, if the view is a table and the option is on, `view.dailyFarm = ns.View.dailyFarm(savedHistory, viewOpts, minutes * 60)` with `savedHistory = ns.chardb and ns.chardb.history or {}`. The `priceMemo` is already reset for this build, so prices are shared with the tab.
- `Ledger.showFarm(zone, sub)`: `Ledger.setTab("history")`, `Ledger.setSubtab("zones")`, then set `zoneOpen` and `Ledger.refresh()`.
- German texts in `deDE.lua`.

- [ ] **Step 4: Run the tests**

Run: `lua tests/run.lua`
Expected: all pass (including `test_locale.lua`).

- [ ] **Step 5: Commit**

```bash
git add LootPrice/DB.lua LootPrice/Options.lua LootPrice/UI/Ledger.lua LootPrice/Locales/deDE.lua tests/
git commit -m "feat: daily farm options and ledger wiring"
```

---

### Task 3: The strip (header row, ledger part, README)

**Files:**
- Create: `LootPrice/UI/DailyFarm.lua`
- Modify: `LootPrice/UI/Window.lua`, `LootPrice/Theme.lua`, `LootPrice/LootPrice.toc` (after `UI/Summary.lua`, before `UI/Ledger.lua`; follow where Header/Summary sit), `LootPrice/Locales/deDE.lua`, `README.md`
- Test: `tests/test_wiring.lua` (and a pure test of the label in `tests/test_view.lua` or a new `tests/test_dailyfarm.lua` loaded with `h.load`)

**Interfaces:**
- Consumes: `view.dailyFarm`, `Ledger.showFarm` (Task 2).
- Produces:
  - `Window.setFarmRow(shown)`: shows / hides a new `header.rowFarm` between `row2` and `row3` (`row3` re-anchored to `rowFarm`). Header height = `headerHeight + (farm and headerRowHeight or 0) + (subtab and headerRowHeight or 0)`; `setSubtabRow` and `setFarmRow` share one local state so neither overwrites the other. Hidden row: height `0.001` (UNVERIFIED (check in client): a near-zero-height row keeps the rows below in place).
  - `ns.UI.DailyFarm.label(farm) -> string` (pure): `L["Daily farm: "] .. place .. "  ~" .. Money.format(best.perHour) .. L["/h"]`, `place` = `sub` when `sub == zone`, else `sub .. " (" .. zone .. ")"`; appends `"  " .. L["slow selling"]` (colored `Theme.colors.marketBad`) when `farm.slow`.
  - `ns.UI.DailyFarm.hint(farm) -> string` (pure): lines for zone, subzone, `L_TIME` duration, value, gold per hour, then `L["Also good: "]` lines for each runner-up (`place  ~x/h`), then, with `slow`, `L["Sells slowly: "] .. table.concat(names, ", ")`, then `L["Click to open it in Zones"]`.
  - Part registered with `ns.UI.Ledger.register`; `Update(view)` shows the row with the label when `view.dailyFarm`, else hides it; click calls `Ledger.showFarm(best.zone, best.sub)`; tooltip from `hint`. Attach in `Ledger.init` with `attach(UI.DailyFarm, ...)` on `frame.header.rowFarm`. `UI.DailyFarm.shown` mirrors the row state (for tests).
  - Theme: `colors.dailyFarm` (gold, like `tabTextSelected`), a star icon texture path in `Theme.textures.dailyFarm` (`"Interface\\Common\\ReputationStar"`, UNVERIFIED (check in client)).

- [ ] **Step 1: Write the failing tests**

Pure label / hint test (with `h.load`):

```lua
h.test("DailyFarm.label names the subzone and zone with the rate", function()
  local f = { best = { zone = "Z", sub = "A", time = 3600, value = 40000, perHour = 40000 }, runnersUp = {} }
  local s = DF.label(f)
  h.eq(s:find("A (Z)", 1, true) ~= nil, true)
  h.eq(s:find("slow", 1, true), nil)
  f.best.sub = "Z"
  h.eq(DF.label(f):find("(Z)", 1, true), nil)
  f.slow = { names = { "Ore" } }
  h.eq(DF.label(f):find(ns.L["slow selling"], 1, true) ~= nil, true)
  h.eq(DF.hint(f):find("Ore", 1, true) ~= nil, true)
end)
```

Wiring tests, same boot as Task 2:
- with a qualifying History: `ctx.ns.UI.DailyFarm.shown == true` and `frame.header` height is `headerHeight + headerRowHeight` on the Session tab, `+ 2 * headerRowHeight` on History.
- empty History (fresh character): `shown == false`, header height `headerHeight`.
- the row's `OnClick` script (`_scripts.OnClick`) switches to History → Zones at the place.
- add any new named global frame to the `allowed` list of "no unexpected globals leak" (prefer unnamed frames).

- [ ] **Step 2: Run to verify they fail**

Run: `lua tests/run.lua`
Expected: FAIL (`ns.UI.DailyFarm` nil; the wiring test loads files from the `.toc`, so add the file to the `.toc` first and it fails on the assertions instead).

- [ ] **Step 3: Implement** the interfaces above: `Window.setFarmRow`, `UI/DailyFarm.lua`, Theme entries, `.toc` line, German texts.

- [ ] **Step 4: Update `README.md`**
- Feature text: a **Daily farm** bullet after History > Zones (what it ranks, saved History only, the minimum time, click opens Zones, slow-selling note needs TSM sale info).
- Option list: the two options.
- Layout table: `UI/DailyFarm.lua`.
- In-client checklist: strip appears between filters and tabs and the list moves down one row; hidden on a character without History; the star texture shows; click opens Zones at the place; the slow note appears with TSM on a place of slow sellers.

- [ ] **Step 5: Run the tests**

Run: `lua tests/run.lua`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add LootPrice/UI/DailyFarm.lua LootPrice/UI/Window.lua LootPrice/UI/Ledger.lua LootPrice/Theme.lua LootPrice/LootPrice.toc LootPrice/Locales/deDE.lua README.md tests/
git commit -m "feat: daily farm strip in the ledger window"
```
