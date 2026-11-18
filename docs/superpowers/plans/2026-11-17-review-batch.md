# Review batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the 22 review items of the spec: small fixes, value rules (AH cut, Auction from, Destroy values), TSM price dropdown, short-session folding, city pause, Bags worth / split / free slots, History day headings, Daily farm level filter, window auto-show, and History > Mobs with kills.

**Architecture:** Pure logic goes into the existing pure modules (`Prices`, `Session`, `History`, `View`, `Inventory`, `Options`) plus one new pure module `Mobs.lua`; `Core.lua` wires the client events; `UI/` draws. Value rules apply in `Prices.lookup` (AH cut, Destroy rule) and one best-value function `Prices.best` (Auction from) that replaces the five places that pick the best value today.

**Tech Stack:** Lua 5.1 (WoW Forever, Interface 16001), plain-Lua tests (`lua tests/run.lua`).

**Spec:** `docs/superpowers/specs/2026-11-17-review-batch-design.md`

## Global Constraints

- Lua 5.1 only: no `goto`, `//`, `table.unpack` (use `unpack` or `select`), integer-only APIs. Local `lua` is 5.4; CI also runs 5.1.
- Files outside `UI/` are pure: every client call injected or looked up at call time. `UI/` files touch WoW globals only inside functions.
- Every new option: default in `DB.defaults.settings`, `Options.define` with a `label` of at most 24 characters and a `tooltip`; read with `Options.get` / `ns.Util.setting`.
- Every new text through `ns.L` (`local L_X = L["Text"]` at file top) with the German text in `Locales/deDE.lua`; remove German entries of English texts that change (`tests/test_locale.lua` fails otherwise).
- Money is copper; format with `ns.Money`.
- New `.lua` file: add to `LootLedger/LootLedger.toc` and the layout table in `docs/DEVELOPMENT.md`.
- Client calls not run in the client: `-- UNVERIFIED (check in client)` comment and a line in `docs/CHECKLIST.md`.
- Docs in the same task: player-visible behavior and option names in `README.md`, internals in `docs/DEVELOPMENT.md`.
- Fake frames in `tests/test_wiring.lua` answer any unset field with a no-op function: initialize optional fields to `false`, check tables with `type(x) == "table"`.
- Edit Lua with the Write / Edit tools (Git Bash strips backslashes in heredocs / sed).
- No option may drop recorded loot or gold (spec anti-goal). Auto-show / hide only undo their own action.
- Run `lua tests/run.lua` after every task; all must pass. Commit per task: `feat:` / `fix:` / `refactor:` / `docs:`, one-line summary plus a short body, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. AH cut applied twice: a cached AH price, a price saved at loot time (`item.price`) and an opened History session must each show 95% of the raw AH price once, never 90.25%. Test in Task 3.
2. City pause vs manual Stop: stopping the clock in a city and then leaving the city must not restart it; AFK pause inside a city must not be undone by leaving the city. Test in Task 6.
3. Short session at login with Keep session off: the session (with loot) is kept running, not archived and not lost; a long one is archived as today. Test in Task 5.
4. A loot slot shared by several corpses (area loot) with uneven quantities, and a money slot: each source gets its own quantity / copper; a slot left in the window (not cleared) credits nothing. Test in Task 11.
5. Day headings with a search or minimum value: a heading adds up only its visible sessions and disappears when none is visible; any sort other than Recent shows no headings. Test in Task 8.

---

### Task 1: Zones polish (header count, short difficulty, unpriced hover, Daily star)

Spec items 1, 7, 9, 11.

**Files:**
- Modify: `LootLedger/View.lua` (`buildZones`, `placeRow`, `collect`), `LootLedger/History.lua` (count text), `LootLedger/UI/Summary.lua` (`tooltipLines`), `LootLedger/UI/Ledger.lua` (`currentContext`: `viewOpts.dailyPick`), `LootLedger/UI/Rows.lua` (star marker), `LootLedger/Theme.lua` (`textures.dailyStar`), `LootLedger/Locales/deDE.lua`
- Test: `tests/test_view.lua`, `tests/test_summary.lua`

**Interfaces:**
- Produces: `History.placeCount(n) -> string` ("1 place" / "6 places"); `View.shortPlace(label) -> string`; zone view `headerInfo`; row field `daily = true`; `totals.unpricedNames = { "Name x3", ... }` (at most `View.UNPRICED_NAMES = 10`) and `totals.unpriced` as today; `opts.dailyPick = { zone = string, sub = string } | nil`.

- [ ] **Step 1: Write the failing tests** in `tests/test_view.lua`:

```lua
h.test("buildZones: header counts the zone rows", function()
  -- two zones with loot -> headerInfo "2 places"; no rows -> nil
end)
h.test("View.shortPlace shortens the difficulty first", function()
  h.eq(V.shortPlace("Razorfen Downs (Normal)"), "Razorfen Downs (N)")
  h.eq(V.shortPlace("Uldaman (Heroic)"), "Uldaman (H)")
  h.eq(V.shortPlace("Deadmines (Mythic Keystone)"), "Deadmines (M+)")
  h.eq(V.shortPlace("Deadmines (Mythic)"), "Deadmines (M)")
  h.eq(V.shortPlace("Stratholme (Timewalking)"), "Stratholme (T)")
  h.eq(V.shortPlace("Riverglades"), "Riverglades")
end)
h.test("buildZones: row name uses the short label, the tooltip the full one", function() end)
h.test("collect: unpriced names with quantity, at most 10 then the count", function()
  -- 12 unpriced unbound items -> #totals.unpricedNames == 10, totals.unpriced == 12
end)
h.test("buildZones: opts.dailyPick marks the subzone and its zone row (daily = true)", function() end)
```

In `tests/test_summary.lua`: `tooltipLines` with `totals.unpricedNames = { "Ore x2" }`, `totals.unpriced = 3` ends with a header line `"Unpriced"`, the line `"Ore x2"` and `"and 2 more"`.

- [ ] **Step 2: Run** `lua tests/run.lua`. Expected: the new tests FAIL.
- [ ] **Step 3: Implement.** `shortPlace`: replace a trailing `(Difficulty)` by its short form: Normal -> N, Heroic -> H, Mythic -> M, a name containing "Keystone" or "+" -> M+, anything else -> its first letter (UTF-8 safe: first character, not first byte). Match the German difficulty names too (Normal, Heroisch, Mythisch, "Mythisch+"/"Schlüsselstein"). `placeRow` uses `shortPlace(label)` for `name`; `placeHint` keeps `label`. `buildZones` sets `headerInfo = #zoneRows > 0 and History.placeCount(#zoneRows) or nil` and `daily = true` on the matching zone and subzone rows. `collect` builds `unpricedNames` (`name .. " x" .. qty`). `Summary.tooltipLines` appends the Unpriced section with `L["and %d more"]`. Rows draws `Theme.textures.dailyStar` as an inline texture before the name of a `daily` row (`|T<path>:0|t `). `Ledger.currentContext` sets `viewOpts.dailyPick` from the cached Daily farm's `best` (zone, sub) or nil.
- [ ] **Step 4: Run** `lua tests/run.lua`. Expected: all PASS.
- [ ] **Step 5: Docs and commit.** README History > Zones: header count, star on the Daily pick, short difficulty, unpriced hover. `git commit -m "feat: Zones header count, short difficulty, unpriced hover, Daily star"`.

### Task 2: Bank unscanned, Reset colors, option names, Reset profile, Session options order

Spec items 2, 3, 6, 25, 26.

**Files:**
- Modify: `LootLedger/UI/Tabs.lua` (bank `build`), `LootLedger/UI/Summary.lua` (`rowTexts`, `notesText`), `LootLedger/Inventory.lua` (`scanNote`), `LootLedger/Options.lua` (`resetColors`, labels, Session option order), `LootLedger/Profiles.lua` (`Profiles.reset`, button), `LootLedger/Locales/deDE.lua`
- Test: `tests/test_summary.lua`, `tests/test_options.lua`, `tests/test_profiles.lua`, `tests/test_wiring.lua`

**Interfaces:**
- Produces: view field `unscanned = true` (Bank before the first scan); `Profiles.reset(db) -> true` (clears the active profile's settings table to the defaults, keeps the profile's name and users).

- [ ] **Step 1: Write the failing tests:**
  - `test_summary`: `Summary.rowTexts({ kind = "inventory", unscanned = true, totals = { best = 0 } }, fmt).items.value == "—"` and `notesText` of that view is nil.
  - `test_wiring`: Bank tab before any scan shows the empty text `"Not scanned yet. Open your bank once to scan it."` and no note.
  - `test_options`: after `Options.pick(db, "colorPreset", "midnight")` and `Options.pick(db, "colorText", "123456")`, running the `resetColors` action leaves `colorPreset == "midnight"`, `colorText` equal to the Midnight preset's text color, and `Options.presetEdited(db.settings) == false`.
  - `test_options`: `Options.byKey.includeGold.label == "Count raw gold"`, `Options.byKey.showFooterGold.label == "Show raw gold row"`.
  - `test_options`: in `Options.layout(<session specs>, 2)` the keys `goalGold` and `goalMinutes` are in the same column and `alertGold`, `alertSound`, `goalGold`, `goalMinutes` are consecutive in that column.
  - `test_profiles`: a profile with `alpha = 0.5` -> `Profiles.reset(db)` -> `db.settings.alpha == nil` (falls back to the default), the profile still exists under its name and stays active.
- [ ] **Step 2: Run** `lua tests/run.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.** Bank build: `view.unscanned = not wasScanned(bank)`; empty text as above; `view.note` only when scanned. `rowTexts`: `items.value = "—"` (em dash, as the rate column already uses) when `view.unscanned`. `resetColors` action: `Options.pick(ns.db, "colorPreset", Options.get(ns.db, "colorPreset"))`. Rename both labels (German: "Rohgold mitzählen", "Rohgold-Zeile zeigen"; remove the old German keys). Session category definition order: Keep session, Crafted and bought, Pause when AFK, Session summary in chat, Session per instance, Session per zone, Zone change delay, Drop alert (gold), Alert sound, Session goal (gold), Session goal (minutes) (Tasks 5 and 6 append their options after Pause when AFK). Profiles button `profileReset`, label "Reset profile", tooltip "Sets every option of this profile back to its default.", asks with `Widgets.confirm` first, then `Profiles.reset`, `Options.applyAll(ns.db)`, refresh.
- [ ] **Step 4: Run** `lua tests/run.lua`. Expected: all PASS.
- [ ] **Step 5: Docs and commit.** README: Bank tab text, Reset colors (back to the chosen preset), new option names in the Options table, Reset profile. `git commit -m "fix: unscanned bank, Reset colors keeps the preset, clearer option names, Reset profile"`.

### Task 3: Value rules: AH cut, Auction from, Destroy values

Spec items 12, 13, 14.

**Files:**
- Modify: `LootLedger/Prices.lua`, `LootLedger/View.lua` (`View.best`, `makeRow`, `opts.ahMinGain`), `LootLedger/History.lua` (`snapshot`, `totals`), `LootLedger/Core.lua` (`buildPrices`, `unitValue`, professions scan, `SKILL_LINES_CHANGED`), `LootLedger/UI/Ledger.lua` (`viewOpts.ahMinGain`, `farmKey`), `LootLedger/Options.lua`, `LootLedger/DB.lua`, tooltips in `LootLedger/UI/Rows.lua` (or wherever the item tooltip lists the values), `LootLedger/Locales/deDE.lua`
- Test: `tests/test_prices.lua`, `tests/test_view.lua`, `tests/test_history.lua`, `tests/test_core.lua`, `tests/test_wiring.lua`

**Interfaces:**
- Produces:
  - `Prices.AH_CUT = 0.05`
  - `Prices.best(vendor, ah, de, minGainPct) -> best, kind` (kind `"vendor" | "ah" | "de"`); AH counts only when `vendor == nil or vendor <= 0 or ah >= vendor * (1 + minGainPct / 100)`; `minGainPct` nil = 0. `View.best` delegates to it with a 4th argument.
  - `Prices.new(opts)` takes `opts.rules = function() -> { ahCut = bool, destroyAllowed = function(itemID, link) -> bool } | nil`.
  - `lookup` result: `ah` after the cut (floored to copper), `ahGross` = the raw AH price (only when the cut applied), `de` nil when `destroyAllowed` returns false. The cache keeps the raw price.
  - `Prices.destroyAllowed(mode, kind, own, any) -> bool`; `mode` `"always" | "any" | "self" | "never"`; `kind` from `Prices.destroyKind(classID, subclassID) -> "enchanting" | "inscription" | "jewelcrafting" | nil`; `own` / `any` = sets `{ enchanting = true, ... }` of this character / all characters. A nil kind is allowed under "any" / "self" when the set has any of the three.
  - `Prices.professionSet(skillLines) -> set` from a list of skill line IDs: 333 enchanting, 773 inscription, 755 jewelcrafting.
  - `History.snapshot(session, lookup, now, minGain)`, `History.totals(e, ignored, minGain)` (extra last argument).
  - `Core.professions(env) -> set` (GetProfessions / GetProfessionInfo 7th return = skillLine; UNVERIFIED), saved in `db.professions[Core.characterKey(env)]` at login and on `SKILL_LINES_CHANGED`.
  - Options: `ahCut` (checkbox, default true, Prices, label "AH cut (5%)"), `ahMinGain` (slider 0..100 step 5, default 0, Prices, label "Auction from", format "+%d%% over vendor" / "Off" at 0), `destroyMode` (dropdown, default "always", Prices, label "Destroy values", choices Always / If one of my characters can / If this character can / Never).

- [ ] **Step 1: Write the failing tests:**

```lua
-- test_prices.lua
h.test("Prices.best: Auction from needs the gain over vendor", function()
  h.eq(select(2, P.best(100, 115, nil, 20)), "vendor")
  h.eq(select(2, P.best(100, 120, nil, 20)), "ah")
  h.eq(select(2, P.best(0, 5, nil, 50)), "ah")      -- no vendor price
  h.eq(select(2, P.best(100, 115, 300, 20)), "de")
  h.eq(select(2, P.best(100, 115, nil, nil)), "ah") -- 0 = off
end)
h.test("lookup: AH cut on live and cached prices, cache keeps the raw price", function()
  -- live 10000 with rules ahCut -> ah == 9500, ahGross == 10000, cache entry price == 10000
  -- next lookup from the cache only -> ah == 9500 (not 9025)
end)
h.test("lookup: destroy rule drops de", function() end)
h.test("Prices.destroyKind / destroyAllowed / professionSet", function()
  h.eq(P.destroyKind(4, 2), "enchanting")   -- armor
  h.eq(P.destroyKind(2, 7), "enchanting")   -- weapon
  h.eq(P.destroyKind(7, 9), "inscription")  -- trade goods: herb
  h.eq(P.destroyKind(7, 7), "jewelcrafting")-- trade goods: metal and stone
  h.eq(P.destroyAllowed("always", "enchanting", {}, {}), true)
  h.eq(P.destroyAllowed("never", "enchanting", { enchanting = true }, { enchanting = true }), false)
  h.eq(P.destroyAllowed("self", "enchanting", {}, { enchanting = true }), false)
  h.eq(P.destroyAllowed("any", "enchanting", {}, { enchanting = true }), true)
  h.eq(P.professionSet({ 333, 164 }).enchanting, true)
end)
-- test_view.lua
h.test("makeRow: saved History prices are not cut again", function()
  -- opts.savedPrices with item.price.ah = 9500 -> row.ahEach == 9500
end)
h.test("makeRow: opts.ahMinGain decides the best source", function() end)
-- test_history.lua
h.test("snapshot / totals use the minimum gain", function() end)
```

`test_wiring`: with `ahCut` on and a fake TSM price of 10000, a looted item's Session row shows `ahEach == 9500`; turning `ahCut` off shows 10000 (no reload).

- [ ] **Step 2: Run** `lua tests/run.lua`. Expected: FAIL.
- [ ] **Step 3: Implement** the interfaces above. `Core.buildPrices` passes `rules` reading the options at call time; `destroyAllowed(itemID, link)` gets class / subclass from `C_Item.GetItemInfoInstant` (returns itemID, type, subType, equipLoc, icon, classID, subclassID), own set from `db.professions[charKey]`, any set = union over `db.professions`. Replace every best-value pick: `View.best` callers (with `opts.ahMinGain`), `Core.unitValue` (with the setting), `History.snapshot` and `History.totals` (`math.max(v, a, d)` -> `Prices.best(...)`), the CSV `counted_as`. The item tooltip's Auction line shows the price after the cut with "(after 5% AH cut)" while the option is on. `Ledger.farmKey` includes `ahCut`, `ahMinGain`, `destroyMode`. Mark `GetProfessions`, `GetProfessionInfo` and `GetItemInfoInstant` UNVERIFIED (Forever) in code and CHECKLIST.
- [ ] **Step 4: Run** `lua tests/run.lua`. Expected: all PASS.
- [ ] **Step 5: Docs and commit.** README Prices tab rows and "Good to know" (old History sessions keep the prices they were saved with). DEVELOPMENT: value rules section (`Prices.best`, `rules`, `db.professions`). `git commit -m "feat: AH cut, Auction from and Destroy values options"`.

### Task 4: TSM price dropdown

Spec item 15.

**Files:**
- Modify: `LootLedger/Options.lua` (`tsmSource` spec, `Options.pick`, `Options.normalize`), `LootLedger/UI/OptionsPanel.lua` only if the dropdown needs the custom label, `LootLedger/Locales/deDE.lua`
- Test: `tests/test_options.lua`, `tests/test_wiring.lua`

**Interfaces:**
- Produces: dropdown spec fields `free = true` (normalize accepts any non-empty trimmed string, like `text`) and `intercept = function(db, value) -> handled` (called by `Options.pick` before setting; `true` = nothing is set). `Options.CUSTOM = "\1custom"`.

- [ ] **Step 1: Write the failing tests** in `test_options.lua`: `Options.normalize(byKey.tsmSource, "  DBRecent ")` -> `"DBRecent"`; `"first(DBMinBuyout, DBMarket)"` is kept; `""` -> default `"DBMarket"`; the choices are DBMarket, DBMinBuyout, DBRegionMarketAvg, DBRecent, DBHistorical, then "Custom..." (`Options.CUSTOM`), plus the current value as its own choice when it is not one of the five; `Options.pick(db, "tsmSource", Options.CUSTOM)` leaves `tsmSource` unchanged and calls the prompt (inject `ns.UI.Widgets.prompt` as a recorder). `test_wiring`: `/ll tsm DBRecent` still sets it.
- [ ] **Step 2: Run** `lua tests/run.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.** `tsmSource` becomes `type = "dropdown", free = true`, `choices` function as above, `intercept` opens `Widgets.prompt(L["TSM price:"], L["OK"], current, function(text) Options.pick(db, "tsmSource", text) end)` for `Options.CUSTOM`. Keep the tooltip text.
- [ ] **Step 4: Run** `lua tests/run.lua`. Expected: all PASS.
- [ ] **Step 5: Docs and commit.** README TSM price row. `git commit -m "feat: TSM price as a dropdown with custom prices"`.

### Task 5: Minimum session length (fold short sessions)

Spec item 4.

**Files:**
- Modify: `LootLedger/Core.lua` (`checkZone`, `checkInstance`, `PLAYER_ENTERING_WORLD`), `LootLedger/Options.lua`, `LootLedger/DB.lua`, `LootLedger/Locales/deDE.lua`
- Test: `tests/test_core.lua`, `tests/test_wiring.lua`

**Interfaces:**
- Produces: `Core.isShort(session, now, minMinutes) -> bool` (pure: true when `minMinutes > 0` and `Session.elapsed(session, now) < minMinutes * 60`). Option `minSessionMinutes` (number, default 2, Session tab, label "Min. session length", tooltip explaining folding; 0 = off).

- [ ] **Step 1: Write the failing tests:** `test_core`: `isShort` at 22 s with 2 -> true, at 120 s -> false, with 0 -> false. `test_wiring`: (a) Session per zone on, loot, 30 s, then a zone change held past the delay -> no History entry, the loot is still in the session; (b) same at 10 minutes -> one History entry as today; (c) login (not reload) with Keep session off and a saved 1-minute session with loot -> `ns.session` is that session, History unchanged; (d) the same with a 30-minute session -> archived as today; (e) `/ll reset` on a 20 s session still archives it.
- [ ] **Step 2: Run** `lua tests/run.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.** In `checkZone` / `checkInstance`, when the session has loot and `Core.isShort`, skip the reset (the session continues; `zoneState` still moves to the new zone). At login: `keep = keepSession or isReloadingUi or (previous valid and Core.isShort(previous, <its elapsed>, minutes))` — elapsed of a saved session is its `elapsedBase` (offline time never counts).
- [ ] **Step 4: Run** `lua tests/run.lua`. Expected: all PASS.
- [ ] **Step 5: Docs and commit.** README Session options and "Session per zone" paragraph. `git commit -m "feat: short sessions continue instead of becoming History rows"`.

### Task 6: Pause in cities (time stops, loot counts)

Spec item 5.

**Files:**
- Modify: `LootLedger/Session.lua`, `LootLedger/Core.lua` (`PLAYER_UPDATE_RESTING`, login, `startSession`, `stopSession`), `LootLedger/UI/Header.lua`, `LootLedger/UI/Compact.lua`, `LootLedger/Options.lua`, `LootLedger/DB.lua`, `LootLedger/Locales/deDE.lua`
- Test: `tests/test_session.lua`, `tests/test_wiring.lua`

**Interfaces:**
- Produces: `Session.rest(session, now)` (running stays true; elapsed folded into `elapsedBase`, `runningSince = nil`, open place stretch closed, `at.since = nil`, `session.resting = true`; no-op when stopped or already resting); `Session.wake(session, now)` (undoes it: `runningSince = now`, `at.since = now`, `resting = nil`; no-op when not resting). `Session.stop` clears `resting`; `Session.enterPlace` starts `at.since` only when running and not resting. Option `cityPause` (checkbox, default true, Session tab after Pause when AFK, label "Pause in cities"). Header / compact show `L["Resting"]` instead of `L["Paused"]` while `session.resting`.

- [ ] **Step 1: Write the failing tests:** `test_session`: rest at 100 after start at 0 -> elapsed 100 at 500; `Session.add` while resting returns true; wake at 500 -> elapsed 150 at 550; zone time of the current place does not grow while resting; `stop` while resting -> `resting == nil`, `running == false`. `test_wiring`: `IsResting` fake true + `PLAYER_UPDATE_RESTING` -> clock frozen, loot still recorded, quest gold still recorded; resting false -> clock runs; Stop in a city then leave -> still stopped; option off -> no change.
- [ ] **Step 2: Run** `lua tests/run.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.** Core `checkRest()`: `IsResting()` (UNVERIFIED on Forever) and the option; rest when resting and running and not AFK-paused; wake when not resting (or option off) and `session.resting`. Call it on `PLAYER_UPDATE_RESTING`, after login setup, after `startSession`, and from `Options` apply of `cityPause`.
- [ ] **Step 4: Run** `lua tests/run.lua`. Expected: all PASS.
- [ ] **Step 5: Docs and commit.** README (clock section, Session options), CHECKLIST (`IsResting`, `PLAYER_UPDATE_RESTING`). `git commit -m "feat: Pause in cities stops the clock but keeps counting loot"`.

### Task 7: Bags footer: gold on hand, net worth, sell split, free slots

Spec items 16, 17, 18.

**Files:**
- Modify: `LootLedger/View.lua` (`buildInventory`), `LootLedger/Inventory.lua`, `LootLedger/UI/Tabs.lua` (bags `build`, `watches` money), `LootLedger/UI/Summary.lua` (`ROWS`, `tableLayout`, `rowTexts`, `tooltipLines`), `LootLedger/Core.lua` (`PLAYER_MONEY` -> `dataChanged("bags")`), `LootLedger/Locales/deDE.lua`
- Test: `tests/test_view.lua`, `tests/test_summary.lua`, `tests/test_wiring.lua`

**Interfaces:**
- Produces: `totals.sellSplit = { vendor, ah, de }` (best value of non-kept rows by `bestKind`) on every inventory view; `View.addWorth(view, money)` sets `totals.money`, `totals.worth = totals.best + money`; `Inventory.freeSlots(env) -> free, total` over `Inventory.bagIDs(env)` with `C_Container.GetContainerNumFreeSlots` / `GetContainerNumSlots`; `History.freeCount(n)` ("9 free"); Summary rows `"money"` ("Gold on hand") and `"worth"` ("Net worth"), shown after items / kept / sellable when `totals.money ~= nil`.

- [ ] **Step 1: Write the failing tests:** `test_view`: rows with best kinds vendor 100, ah 300, de 50 and one kept ah row 200 -> `sellSplit == { vendor = 100, ah = 300, de = 50 }`; `addWorth(view, 56200)` -> `worth == best + 56200`. `test_summary`: layout rows for an inventory view with money and kept -> `{ "items", "kept", "sellable", "money", "worth" }`, without kept -> `{ "items", "money", "worth" }`; `tooltipLines` has a "Sell split" section with Vendor / Auction / Destroy lines. `test_wiring`: Bags header shows `"3 items · 9 free"` with a fake bag of 12 slots and 3 items; Bank has no money rows.
- [ ] **Step 2: Run** `lua tests/run.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.** Bags build: `View.addWorth(view, GetMoney())`, `headerInfo = itemCount .. " · " .. History.freeCount(free)`; drop the cached `bagItems` view on `PLAYER_MONEY` too.
- [ ] **Step 4: Run** `lua tests/run.lua`. Expected: all PASS.
- [ ] **Step 5: Docs and commit.** README Bags tab. `git commit -m "feat: Bags shows gold on hand, net worth, the sell split and free slots"`.

### Task 8: History day headings

Spec item 21.

**Files:**
- Modify: `LootLedger/History.lua` (period helpers), `LootLedger/View.lua` (`buildHistory`), `LootLedger/UI/Ledger.lua` (`Ledger.periodFold`, click), `LootLedger/UI/Rows.lua` (heading style), `LootLedger/Locales/deDE.lua`
- Test: `tests/test_history.lua`, `tests/test_view.lua`, `tests/test_wiring.lua`

**Interfaces:**
- Produces: `History.isoWeek(year, month, day) -> week` (ISO 8601, Monday first); `History.period(t, now, dateFn) -> key, label` where `dateFn` is `os.date`-like: same day -> `"d:YYYY-MM-DD"`, "Today"; the day before -> "Yesterday"; other days of the current Monday-week -> weekday name (`L["Monday"]` ...); older -> `"w:YYYY-WW"`, `L["Week %d"]`. `opts.dateFn`, `opts.folded = { [periodKey] = true }`. Heading row: `{ periodKey, isHeading = true, name = label, detail = "5 sessions · 6h 3m", value, bestLineTotal, perHour, quality = 1, icon = Theme.textures.calendar }`. Headings only when `opts.sort == "recent"`.

- [ ] **Step 1: Write the failing tests:** `test_history`: `isoWeek(2026, 11, 17) == 47`, `isoWeek(2027, 1, 1) == 53`, `isoWeek(2026, 1, 1) == 1`; `period` for now = Tue 2026-11-17 12:00 local: same day -> "Today", Mon 16th -> "Yesterday", Sun 15th -> "Week 46" (previous week). `test_view`: three sessions today, one yesterday, sort recent -> rows heading, 3 sessions, heading, 1 session; heading value = sum of its visible sessions; a search hiding yesterday's session -> no Yesterday heading; `opts.folded["d:2026-11-16"]` -> heading present, its session hidden, footer still counts it; sort "ah" -> no headings; an opened session stays at the top above all headings.
- [ ] **Step 2: Run** `lua tests/run.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.** `Ledger.periodFold` (reset at logout only), click on `row.periodKey` toggles it and refreshes; Rows: heading rows use the titles color and no right-click menu.
- [ ] **Step 4: Run** `lua tests/run.lua`. Expected: all PASS.
- [ ] **Step 5: Docs and commit.** README History. `git commit -m "feat: History Sessions grouped under day and week headings"`.

### Task 9: Daily farm: my level only

Spec item 22.

**Files:**
- Modify: `LootLedger/View.lua` (`dailyFarm`), `LootLedger/Core.lua` (`Core.levelFits`), `LootLedger/UI/Ledger.lua` (`viewOpts.levelFits`, `farmKey`), `LootLedger/Options.lua`, `LootLedger/DB.lua`, `LootLedger/Locales/deDE.lua`
- Test: `tests/test_view.lua`, `tests/test_core.lua`

**Interfaces:**
- Produces: `opts.levelFits = function(mapID) -> true | false | nil` (nil = unknown, kept); `Core.levelFits(env, mapID, level) -> bool | nil` using `C_Map.GetMapLevels(mapID)` (min, max; UNVERIFIED): fits when `min <= level <= max`, nil when the call or values are missing. Option `dailyFarmLevel` (checkbox, default false, History tab, label "Daily farm: my level").

- [ ] **Step 1: Write the failing tests:** `test_view`: two places, the better one's `pos.mapID` fails `levelFits` -> the other is `best`; a place without `pos` is kept; `levelFits` nil -> both kept. `test_core`: `levelFits` with fake `GetMapLevels` returning 35, 45 -> 42 true, 50 false; missing API -> nil.
- [ ] **Step 2: Run** `lua tests/run.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.** `dailyFarm` skips a place when `opts.levelFits` exists, the place has `pos`, and it returns `false`. Ledger sets `viewOpts.levelFits` only with the option on (player level from `UnitLevel("player")`) and adds option and level to `farmKey`.
- [ ] **Step 4: Run** `lua tests/run.lua`. Expected: all PASS.
- [ ] **Step 5: Docs and commit.** README Daily farm, CHECKLIST (`C_Map.GetMapLevels`). `git commit -m "feat: Daily farm can keep to places of your level"`.

### Task 10: Window auto-show / hide

Spec item 24.

**Files:**
- Modify: `LootLedger/UI/Window.lua`, `LootLedger/Core.lua` (first loot, instance change, resting), `LootLedger/Options.lua`, `LootLedger/DB.lua`, `LootLedger/Locales/deDE.lua`
- Test: `tests/test_wiring.lua`

**Interfaces:**
- Produces: `Window.autoShow(reason)` (shows a hidden window and remembers `Window.shownBy = reason`; does nothing when shown already), `Window.autoHide(reason)` (hides a shown window and remembers `Window.hiddenBy = reason`), `Window.autoUndo(reason)` (only undoes its own action of that reason). `Window.show` / `Window.hide` (by hand) clear both marks. Neither acts while `hiddenByCombat`. Options (Window tab, default false): `showOnLoot` "Open on first loot", `showInInstance` "Open in instances", `hideInCities` "Hide in cities".

- [ ] **Step 1: Write the failing tests** (`test_wiring`): hidden window + `showOnLoot` + first loot -> shown; second loot after closing by hand -> stays hidden. `showInInstance`: entering an instance shows, leaving hides; closed by hand inside -> leaving does nothing; shown by hand before -> leaving keeps it shown. `hideInCities`: resting hides, leaving shows; opened by hand in the city -> stays. Combat-hidden window is left alone.
- [ ] **Step 2: Run** `lua tests/run.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.** Core calls: first counted item of a session (`Session.itemCount == 1` after add) -> `autoShow("loot")`; `checkInstance` -> `autoShow("instance")` on entering an instance key, `autoUndo("instance")` on leaving; `checkRest` -> `autoHide("city")` / `autoUndo("city")`. Not at login while Start hidden is on (the first trigger is the next event).
- [ ] **Step 4: Run** `lua tests/run.lua`. Expected: all PASS.
- [ ] **Step 5: Docs and commit.** README Window options. `git commit -m "feat: window opens on first loot or in instances and hides in cities"`.

### Task 11: Mobs data (pure)

Spec item 20, data part.

**Files:**
- Create: `LootLedger/Mobs.lua` (after `Session.lua` in the `.toc`)
- Modify: `LootLedger/LootLedger.toc`, `LootLedger/Session.lua` (`new`, `reset`, `login` keep `mobs`), `LootLedger/History.lua` (`snapshot` copies `mobs`, `merge` merges them), `docs/DEVELOPMENT.md` (layout table)
- Test: `tests/test_mobs.lua` (new), `tests/test_history.lua`, `tests/test_session.lua`

**Interfaces:**
- Produces (`ns.Mobs`, pure):
  - `Mobs.idOf(guid) -> key, kind` : `"Creature-0-1-2-3-12345-0000ABCD"` -> `"npc:12345", "npc"`; `"Vehicle-..."` -> npc; `"GameObject-0-1-2-3-1731-..."` -> `"obj:1731", "node"`; players, pets and anything else -> nil.
  - `Mobs.readSlot(env, slot) -> { kind = "item" | "money", link, qty, sources = { { guid, qty }, ... } } | nil` from `GetLootSlotType`, `GetLootSlotLink`, `GetLootSlotInfo` (3rd return = quantity), `GetLootSourceInfo` (guid1, qty1, guid2, qty2, ...). Money: `qty` = sum of source quantities (copper). UNVERIFIED.
  - `Mobs.credit(mobs, slot, place, names, state)` : one cleared slot -> for each source with a known `idOf` key, that entry gets `items[itemKey] += sourceQty` (item) or `gold += sourceQty` (money), `places[place] += 1`, `name` from `names[key]` when known, and `Mobs.noteLooted` for its GUID.
  - `Mobs.noteLooted(mobs, key, guid, state)`: `looted += 1` the first time a GUID is seen; the seen GUIDs live in `state.lootedGUIDs` (the caller's per-login state, never saved).
  - `Mobs.addKill(mobs, key, name, place)`: `kills += 1`.
  - `Mobs.combat(state, subevent, sourceGUID, sourceFlags, destGUID) -> killedGUID | nil` : a `*_DAMAGE` / `*_MISSED` from a group source (flags & 0x7 ~= 0: mine, party, raid affiliation) marks `state.fought[destGUID]`; `PARTY_KILL` from a group source, or `UNIT_DIED` / `UNIT_DESTROYED` of a fought GUID, returns `destGUID` once (`state.killed`).
  - `Mobs.copy(mobs) -> table` (valid entries only) and `Mobs.merge(a, b) -> table`.
  - Entry shape: `mobs[key] = { name, kind, kills, looted, gold, items = { [itemKey] = qty }, places = { [place] = n } }`.

- [ ] **Step 1: Write the failing tests** in `tests/test_mobs.lua` (load `Util.lua`, `LootParse.lua`, `Mobs.lua`):

```lua
h.test("idOf parses creatures, vehicles and nodes", function()
  h.eq(M.idOf("Creature-0-3110-0-12-2546-000012ABCD"), "npc:2546")
  h.eq(select(2, M.idOf("GameObject-0-3110-0-12-1731-000012ABCD")), "node")
  h.eq(M.idOf("Player-3110-0ABCDEF"), nil)
  h.eq(M.idOf("Pet-0-3110-0-12-416-0100ABCD"), nil)
end)
h.test("credit splits a shared slot by source quantity", function()
  -- slot { kind = "item", link = <Linen Cloth>, qty = 5, sources = { { guid = A, qty = 2 }, { guid = B, qty = 3 } } }
  -- -> mobs[A].items[2589] == 2, mobs[B].items[2589] == 3
end)
h.test("credit adds copper per source for a money slot", function() end)
h.test("combat: party kill and died-after-damage count once", function()
  -- SPELL_DAMAGE from flags 0x511 on G, then UNIT_DIED of G -> G; again -> nil
  -- PARTY_KILL from an outsider (flags 0x548) -> nil
end)
h.test("merge adds kills, looted, gold, items and places", function() end)
```

`test_history`: snapshot keeps `mobs`, merge of two entries adds their mobs. `test_session`: `reset` clears `mobs`, `login` with keep keeps them.

- [ ] **Step 2: Run** `lua tests/run.lua`. Expected: FAIL.
- [ ] **Step 3: Implement** `Mobs.lua` and the Session / History changes. Add it to the `.toc` and the DEVELOPMENT layout table.
- [ ] **Step 4: Run** `lua tests/run.lua`. Expected: all PASS (the wiring test boots from the `.toc` with the new file).
- [ ] **Step 5: Commit.** `git commit -m "feat: Mobs data: loot per corpse and node, group kills"`.

### Task 12: Mobs capture in Core

Spec item 20, client wiring.

**Files:**
- Modify: `LootLedger/Core.lua`, `docs/CHECKLIST.md`
- Test: `tests/test_wiring.lua`

**Interfaces:**
- Consumes: Task 11 (`Mobs.readSlot`, `credit`, `noteLooted`, `combat`, `addKill`, `idOf`).
- Produces: events `LOOT_OPENED` (extended: snapshot every slot with `readSlot`), `LOOT_SLOT_CLEARED(slot)` (credit that slot), `LOOT_CLOSED` (drop the snapshot), `COMBAT_LOG_EVENT_UNFILTERED` (via `CombatLogGetCurrentEventInfo`: timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName), `NAME_PLATE_UNIT_ADDED(unit)`, `PLAYER_TARGET_CHANGED`, `UPDATE_MOUSEOVER_UNIT` (remember `UnitGUID` -> `UnitName` per mob key in a name table kept for the login, plus `destName` from the combat log). Nothing is credited or counted while the clock is stopped or in demo mode; resting still counts. Names missing at credit time are filled from the tooltip lookup `C_TooltipInfo.GetHyperlink("unit:" .. guid)` first line, else `"NPC 12345"`.

- [ ] **Step 1: Write the failing tests** (`test_wiring`, with fake loot API functions on `env`): a loot window with two slots from one corpse, both cleared -> `ns.session.mobs["npc:2546"]` has the items, `looted == 1`; a slot not cleared credits nothing; a combat log kill by the player adds `kills == 1` with the name from the event; clock stopped -> nothing; a missing `CombatLogGetCurrentEventInfo` -> no error, loot still credited.
- [ ] **Step 2: Run** `lua tests/run.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.** Guard every client call with `type(fn) == "function"` and `pcall`; UNVERIFIED comments on each; CHECKLIST lines: loot source info, `LOOT_SLOT_CLEARED`, combat log access, tooltip name lookup.
- [ ] **Step 4: Run** `lua tests/run.lua`. Expected: all PASS.
- [ ] **Step 5: Commit.** `git commit -m "feat: record loot per mob and node and group kills"`.

### Task 13: History > Mobs tab

Spec item 20, view.

**Files:**
- Modify: `LootLedger/View.lua` (`View.buildMobs`), `LootLedger/UI/Tabs.lua` (sub-tab `mobs`), `LootLedger/UI/Ledger.lua` (`Ledger.mobOpen`, click), `LootLedger/UI/FilterBar.lua` (sort labels `perKill` "Per kill", `kills` "Kills"), `LootLedger/Theme.lua` (`textures.mob`, `textures.node`), `LootLedger/Locales/deDE.lua`
- Test: `tests/test_view.lua`, `tests/test_wiring.lua`

**Interfaces:**
- Consumes: entries with `mobs` (Task 11), the running session's `mobs`.
- Produces: `View.buildMobs(entries, opts, openKey) -> view` (`kind = "mobs"`, `history = true`, `headerInfo` = `History.mobCount(n)` "14 mobs"); row `{ mobKey, name, detail = "34 kills · 28s each · Riverglades" (nodes: "6 looted · 80s each · node"), value, bestLineTotal, perKill, kills, sortsLast = (value == 0) }`; items valued with saved prices like Zones (reuse `addZoneItem`), gold with `opts.includeGold`; per kill = value / kills (nodes and kill-less mobs: / looted). Sorts: `ah`, `perKill`, `kills`, `name`; default `ah`. Footer: listed rows added up; `opts.ignored` items left out.

- [ ] **Step 1: Write the failing tests** (`test_view`): two entries with the same mob add up; per kill = (items + gold) / kills; a mob with kills and no loot sorts last with value 0; opened mob lists its item rows under it; sort `kills` orders by kills; the ignore list removes an item's value. `test_wiring`: History > Mobs sub-tab exists after Zones, follows Zones: all characters, header shows the count.
- [ ] **Step 2: Run** `lua tests/run.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `lua tests/run.lua`. Expected: all PASS.
- [ ] **Step 5: Docs and commit.** README History > Mobs paragraph (kills come from the combat log; looted = corpses or nodes taken from; what isn't counted). DEVELOPMENT: Mobs data flow. `git commit -m "feat: History Mobs tab with value per kill"`.

### Task 14: Final check

**Files:** `README.md`, `docs/DEVELOPMENT.md`, `docs/CHECKLIST.md`, `docs/BACKLOG.md`

- [ ] **Step 1:** Read the spec's Goals list and tick each item against the code; fix gaps.
- [ ] **Step 2:** `docs/BACKLOG.md`: add the review items not built (Top finds by sort, History row icons, drop alert upgrade, account-wide inventory) and list the built ones under "Already built".
- [ ] **Step 3:** Run `lua tests/run.lua`. Expected: `N passed, 0 failed`. If a Lua 5.1 interpreter is available (`lua5.1`), run it there too.
- [ ] **Step 4:** Commit `docs: review batch docs and backlog`.
