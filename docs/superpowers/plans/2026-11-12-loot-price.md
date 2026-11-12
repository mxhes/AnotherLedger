# LootPrice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A WoW Forever addon whose always-visible, game-styled "Session Ledger" shows everything the player loots with vendor and auction house value, session totals and gold/hour.

**Architecture:** All logic that can run outside the client (money format, loot-string parsing, price lookup and cache, session record, view building with filter/sort/totals, saved-variable defaults, slash parsing) lives in plain Lua modules loaded with `local ADDON, ns = ...`, and is unit-tested with a tiny harness under a stock Lua. Client-bound code (price-source adapters, Core events, UI frames) is a thin layer over those modules; adapters take their global environment as a parameter so they are testable too, and UI is verified in the client with a `/lp demo` command.

**Tech Stack:** Lua 5.1-compatible code (WoW), plain frames (no Ace3), a stock Lua 5.1-5.4 interpreter for tests, BigWigs packager for release.

**Spec:** `docs/superpowers/specs/2026-11-12-loot-price-design.md` (read it first; the section "Calls made by the designer" is binding).

## Global Constraints

- Lua code must be 5.1-compatible: no `goto`, no bit operators, no `//`, use `unpack or table.unpack`.
- No toasts or popups on loot. The ledger row flash is the only loot feedback.
- No built-in AH scanner and no external price feed. AH prices come only from TSM, then Auctionator, then `n/a`.
- Built-in Blizzard textures and fonts only; every texture path, font, color and size lives in `LootPrice/Theme.lua`.
- Vendor price is `C_Item.GetItemInfo(itemID)` 11th return value (`sellPrice`); late data handled via `GET_ITEM_INFO_RECEIVED`. Prices are keyed by plain item ID (no quality tiers).
- Cache key `{region}-{gameModeRecordID}` from `C_GameRules.GetCurrentGameModeRecordID()`; nil means skip cache writes, retry on `PLAYER_ENTERING_WORLD`.
- Stale AH price: shown with age tag, colored when older than 12 hours (`> 43200` s). Missing: `n/a`. Missing AH counts 0 in the AH total, and the totals bar shows `N unpriced`.
- Gold/hour = total / running time only (stopped and logged-out time excluded), computed over the visible (filtered) rows.
- Saved variables: account-wide `LootPriceDB`, per-character `LootPriceCharDB`. `.toc` has `## OptionalDeps: TradeSkillMaster, Auctionator`.
- Session data is a self-contained record so a history list can be added later; no history UI now.
- Commit messages end with the attribution line from the session's system reminder.
- Tests: `lua tests/run.lua` from the repo root (exit code 1 on any failure).

## Plan decisions (not in the spec, flag in review)

- "Minimum value" in the filter compares a row's **value** = AH total, falling back to vendor total when AH is `n/a`. Top finds ranks by the same value, among the **visible** rows.
- Reset keeps the running/stopped state. Large-session confirmation threshold: 25 distinct items (`Session.LARGE_SESSION_ITEMS`).
- Gold/hour shows `—` while running time is under 60 s.
- Flash is `strong` when the value added by the loot is at least 10g (`View.STRONG_FLASH_VALUE = 100000` copper).
- Slash commands: `/lp` toggles, `show`, `hide`, `start`, `stop`, `reset`, `keep on|off`, `tsm <priceSource>`, `demo`, `help`.

## Review Focus

1. A price source that errors, returns 0, a negative, NaN or a non-number: shown as `n/a`, never a Lua error (Tasks 4, 5).
2. Item info not cached when looted (name/quality/vendor nil): row still appears from the link, fixes itself on `GET_ITEM_INFO_RECEIVED` (Tasks 7, 8).
3. Just-started or zero running time: gold/hour is `—`, never `inf`/`nan` (Task 7).
4. Item names containing `%`, `(`, `x2`, `]`: parsing returns the full link and the right quantity; other players' loot and currency links are ignored (Task 3).
5. Missing, partial or wrongly typed saved variables (fresh install, older version, hand-edited): defaults fill in, no error (Task 8). Window dragged off-screen after a resolution change is clamped back (Task 9).

---

## File structure

```
LootPrice/                       (the addon folder; repo root also holds tests/, docs/, .pkgmeta)
  LootPrice.toc
  Money.lua            pure   copper -> "1g 20s"
  Theme.lua            pure   every texture/font/color/size
  DB.lua               pure   saved-variable defaults
  LootParse.lua        pure   chat string -> link, quantity
  Prices.lua           pure   lookup, cache, age, cache key
  Sources/Vendor.lua   client price source adapters (env injected)
  Sources/TSM.lua
  Sources/Auctionator.lua
  Session.lua          pure   session record, timer, lifecycle
  View.lua             pure   filter, sort, top finds, totals, flash level
  Slash.lua            pure   slash parsing
  UI/Window.lua        frame, drag, resize, hide, persist
  UI/Rows.lua          scrolling rows, flash
  UI/Header.lua        timer + Start/Stop/Reset/Hide
  UI/Summary.lua       top finds + totals bar
  UI/FilterBar.lua     quality, min value, search, sort
  UI/Ledger.lua        controller: builds the view, refreshes the parts
  Core.lua             events, saved vars, slash wiring
tests/
  run.lua, harness.lua, test_<module>.lua
.pkgmeta
```

Load order in the `.toc`: Money, Theme, DB, LootParse, Prices, Sources/*, Session, View, Slash, UI/*, Core.

---

### Task 1: Scaffold and test harness

**Files:**
- Create: `LootPrice/LootPrice.toc`, `tests/harness.lua`, `tests/run.lua`, `tests/test_harness.lua`

**Interfaces:**
- Produces: `harness.load(files: string[]) -> ns` (loads each `LootPrice/<file>` with `loadfile(path)("LootPrice", ns)` into one shared `ns` table); `harness.test(name, fn)`; `harness.eq(actual, expected, msg?)` (deep equality for tables); `harness.near(a, b, eps?)`. Each `tests/test_*.lua` is a chunk that receives `h` as `...`.

- [ ] **Step 1: Install a Lua interpreter** if `lua -v` fails: `winget install DEVCOM.Lua`, then reopen the shell. Any 5.1-5.4 is fine.
- [ ] **Step 2: Write the failing test** `tests/test_harness.lua`: `h.test("eq compares tables deeply", ...)` asserting `h.eq({1,{a=2}},{1,{a=2}})` passes and `pcall(h.eq,{1},{2})` returns false; `h.test("load shares ns", ...)` loads `{"Money.lua"}` and asserts `ns.Money` is a table (fails until Task 2, so for now load a temp file `tests/fixtures/ns_probe.lua` that sets `ns.probe = true`; harness resolves paths under `LootPrice/` unless the file starts with `tests/`).
- [ ] **Step 3: Run** `lua tests/run.lua` — Expected: FAIL (harness missing).
- [ ] **Step 4: Implement** `harness.lua` and `run.lua` (run.lua globs `tests/test_*.lua` via `io.popen("dir /b tests\\test_*.lua")` on Windows or `ls` elsewhere, prints `ok`/`FAIL name: message` per test and a summary, `os.exit(1)` on failure). Write the `.toc` with `## Interface:` set from the client (`/dump select(4, GetBuildInfo())` in game, ask the user to run it if no client access), `## Title: LootPrice`, `## SavedVariables: LootPriceDB`, `## SavedVariablesPerCharacter: LootPriceCharDB`, `## OptionalDeps: TradeSkillMaster, Auctionator`, and the file list from "Load order" (files not yet created are listed anyway; later tasks create them).
- [ ] **Step 5: Run** `lua tests/run.lua` — Expected: all PASS.
- [ ] **Step 6: Commit** `feat: addon scaffold and test harness`.

---

### Task 2: Money formatting

**Files:** Create `LootPrice/Money.lua`; Test `tests/test_money.lua`

**Interfaces:**
- Produces: `ns.Money.format(copper: number|nil) -> string`.

- [ ] **Step 1: Write the failing tests** (`h.eq(ns.Money.format(x), expected)`): `12000 -> "1g 20s"`, `45000 -> "4g 50s"`, `620000 -> "62g"`, `800 -> "8s"`, `5 -> "5c"`, `10005 -> "1g 5c"`, `0 -> "0c"`, `nil -> "n/a"`, `-12000 -> "-1g 20s"`, `12345.7 -> "1g 23s 45c"` (floors fractions).
- [ ] **Step 2: Run** `lua tests/run.lua` — Expected: FAIL (`ns.Money` nil).
- [ ] **Step 3: Implement** `Money.format(copper)`; show only non-zero units, gold/silver/copper letters, sign prefix for negatives.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat: money formatting`.

---

### Task 3: Loot string parsing

**Files:** Create `LootPrice/LootParse.lua`; Test `tests/test_lootparse.lua`

**Interfaces:**
- Produces: `ns.LootParse.compile(G: table<string,string>) -> compiled` (reads `LOOT_ITEM_SELF`, `LOOT_ITEM_SELF_MULTIPLE`, `LOOT_ITEM_PUSHED_SELF`, `LOOT_ITEM_PUSHED_SELF_MULTIPLE`, `LOOT_ITEM_CREATED_SELF`, `LOOT_ITEM_CREATED_SELF_MULTIPLE`; missing keys skipped); `ns.LootParse.parse(compiled, msg: string) -> link: string|nil, quantity: integer|nil`; `ns.LootParse.itemID(link: string) -> integer|nil`.

- [ ] **Step 1: Write the failing tests** with `G` = the six English strings (`"You receive loot: %s."`, `"You receive loot: %sx%d."`, `"You receive item: %s."`, `"You receive item: %sx%d."`, `"You create: %s."`, `"You create: %sx%d."`) and `L = "|cff1eff00|Hitem:3356::::::::60:::::|h[Kingsblood]|h|r"`:
  - `parse(c, "You receive loot: "..L..".")` -> `L, 1`; with `L.."x5."` -> `L, 5`; pushed and created variants likewise (`"You create: "..L..".")` -> `L, 1`).
  - a multiple string never returns a link ending in `x5` (multiples are tried first).
  - name with specials: `L2 = "|cffffffff|Hitem:1::::::::60:::::|h[Potion (100%) of x2]|h|r"` -> returns `L2` whole, quantity 1; and `L2.."x3."` -> `L2, 3`.
  - `"Bob receives loot: "..L.."."` -> `nil`; currency link `"You receive loot: |cffffffff|Hcurrency:1|h[Honor]|h|r."` -> `nil`; `""` -> `nil`.
  - `itemID(L) == 3356`, `itemID("nonsense") == nil`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** `compile` by escaping Lua magic characters in the literal parts and replacing `%s` with `(.+)` and `%d` with `(%d+)`, anchored with `^...$`, multiples ordered first; `parse` rejects any capture that lacks `|Hitem:`.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat: parse loot chat messages`.

---

### Task 4: Price lookup, cache, age

**Files:** Create `LootPrice/Prices.lua`; Test `tests/test_prices.lua`

**Interfaces:**
- Produces: `ns.Prices.new(opts) -> prices` where `opts = { sources = {{name=string, get=function(itemID)->number|nil}, ...}, vendor = function(itemID)->number|nil, cache = table, key = function()->string|nil, now = function()->number }`; `prices:lookup(itemID) -> { vendor: number|nil, ah: number|nil, ahSource: string|nil, ahAge: number|nil }` (`ahSource == "cache"` for fallback, `ahAge == 0` for live); `ns.Prices.cacheKey(region: string|nil, modeID: number|nil) -> string|nil`; `ns.Prices.formatAge(seconds) -> string`; `ns.Prices.isStale(seconds) -> boolean`; constants `Prices.STALE_AFTER = 43200`, `Prices.WRITE_INTERVAL = 60`. Cache layout: `cache[key][itemID] = { price = number, seenAt = number }`.
- Consumes: sources from Task 5 (same `{name, get}` shape).

- [ ] **Step 1: Write the failing tests** (fake sources/clock):
  - live price: source `TSM` returns 4500 at now=1000 -> `ah==4500, ahSource=="TSM", ahAge==0`, and `cache["EU-1"][5]` equals `{price=4500, seenAt=1000}`.
  - first source nil, second returns 300 -> `ahSource` is the second's name.
  - all nil, cache has `{price=4500, seenAt=1000}`, now = 1000+14*3600 -> `ah==4500, ahSource=="cache", ahAge==50400`, `isStale(50400)==true`.
  - nothing anywhere -> `ah==nil, ahAge==nil, ahSource==nil`.
  - `key()` returns nil: live price still returned, `cache` table stays empty.
  - throttle: same price looked up again at 1010 keeps `seenAt==1000`; at 1061 `seenAt==1061`; a changed price at 1010 rewrites immediately.
  - bad values: sources returning `0`, `-1`, `0/0`, `"abc"`, `true`, and a source that calls `error()` are all treated as nil (falls through to the next source / cache).
  - vendor: returns 1200 -> `vendor==1200`; nil -> `nil`; 0 -> `0`.
  - `cacheKey("EU", 7) == "EU-7"`, `cacheKey("EU", nil) == nil`, `cacheKey(nil, 7) == nil`.
  - `formatAge(30)=="1m"`, `formatAge(120)=="2m"`, `formatAge(14*3600)=="14h"`, `formatAge(3*86400)=="3d"`; `isStale(43200)==false`, `isStale(43201)==true`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the signatures above. Wrap every source call in `pcall`; accept only finite numbers `> 0`.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat: price lookup with cache and age`.

---

### Task 5: Price source adapters

**Files:** Create `LootPrice/Sources/Vendor.lua`, `LootPrice/Sources/TSM.lua`, `LootPrice/Sources/Auctionator.lua`; Test `tests/test_sources.lua`

**Interfaces:**
- Produces: `ns.Sources.Vendor.get(env: table, itemID) -> number|nil` (`env.C_Item.GetItemInfo(itemID)` 11th return); `ns.Sources.TSM.new(env, getSource: function()->string) -> {name="TSM", get=fn}` (calls `env.TSM_API.GetCustomPriceValue(getSource(), "i:"..itemID)`); `ns.Sources.Auctionator.new(env) -> {name="Auctionator", get=fn}` (calls `env.Auctionator.API.v1.GetAuctionPriceByItemID("LootPrice", itemID)`). In the client `env` is `_G`.

- [ ] **Step 1: Write the failing tests** with fake `env` tables: Vendor returns the 11th value (fake returns 10 filler values then 1200 -> 1200); `env.C_Item` missing -> nil; `GetItemInfo` returning nothing -> nil. TSM: passes `"DBMarket"` and `"i:5"` (assert received args), returns the number; `env.TSM_API` missing -> nil; function that errors -> nil (no throw); returns `nil` -> nil. Auctionator: passes caller id `"LootPrice"` and the item ID; missing API table -> nil; errors -> nil.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the three adapters, each `pcall`-guarded and returning only numbers.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat: vendor, TSM and Auctionator price sources`.

---

### Task 6: Session record

**Files:** Create `LootPrice/Session.lua`; Test `tests/test_session.lua`

**Interfaces:**
- Produces (all pure, `now` in seconds): `Session.new(now) -> session` with fields `{startedAt, running, runningSince, elapsedBase, items = {[itemID] = {id, link, qty, lastSeen}}}`; `Session.add(session, itemID, link, qty, now) -> boolean` (false and no change while stopped); `Session.elapsed(session, now) -> number`; `Session.start(session, now)`; `Session.stop(session, now)`; `Session.reset(session, now)`; `Session.suspend(session, now)` (logout: fold running time, keep `running` flag); `Session.resume(session, now)`; `Session.login(saved: table|nil, keep: boolean, now) -> session`; `Session.itemCount(session) -> integer`; `Session.needsResetConfirm(session) -> boolean`; `Session.LARGE_SESSION_ITEMS = 25`.

- [ ] **Step 1: Write the failing tests:** new(100): `elapsed(100)==0`, `elapsed(160)==60`. `add(s,5,L,3,110)` true, again qty 2 -> `items[5].qty==5`, `lastSeen` updated. `stop(s,200)` -> `elapsed(500)==100`; `add` while stopped returns false, qty unchanged; `start(s,600)` -> `elapsed(660)==160`; stop twice and start twice are no-ops. `reset` while running: items empty, `elapsed==0` from now, still running; `reset` while stopped stays stopped. suspend/resume: `new(0)`, `suspend(s,100)`, `resume(s,10000)` -> `elapsed(10060)==160`; a stopped session stays stopped through suspend/resume. `login(nil,true,5)` -> fresh; `login(saved,false,5)` -> fresh (saved untouched); `login(saved,true,5)` -> same loot, resumed. `needsResetConfirm`: 24 items false, 25 true.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the interface above.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat: session record and timer`.

---

### Task 7: View (filter, sort, top finds, totals, flash)

**Files:** Create `LootPrice/View.lua`; Test `tests/test_view.lua`

**Interfaces:**
- Consumes: a session (Task 6); `lookup(itemID) -> {vendor, ah, ahSource, ahAge}` (Task 4 result shape); `itemInfo(itemID) -> {name: string, quality: integer}|nil`.
- Produces: `View.build(session, opts) -> view` with `opts = {now, filter, sort, lookup, itemInfo}`;
  `view = { rows = Row[], top = Row[], totals = {vendor, ah, unpriced, vendorPerHour: number|nil, ahPerHour: number|nil, filtered: boolean} }`;
  `Row = {id, link, name, quality, quantity, vendorEach, vendorTotal, ahEach, ahTotal, ahFromCache: boolean, ahAge, stale: boolean, value, lastSeen}` (`value = ahTotal or vendorTotal or 0`; name falls back to the `[...]` text of the link and quality to 1 when `itemInfo` returns nil);
  `filter = {qualities = set(0..7)|nil, minValue = copper, search = string}`; `sort = "ah"|"vendor"|"name"|"recent"`; `View.isFiltered(filter) -> boolean`; `View.indexOf(rows, itemID) -> integer|nil`; `View.flashLevel(unitValue: number|nil, addedQty: integer) -> "normal"|"strong"`; constants `View.TOP_COUNT = 3`, `View.MIN_RATE_SECONDS = 60`, `View.STRONG_FLASH_VALUE = 100000`.

- [ ] **Step 1: Write the failing tests** using a small fake session and lookups:
  - rows aggregate one per item ID with quantity and per-unit/total prices; default sort `"ah"` is AH total descending, ties by name then id; `"vendor"`, `"name"` (ascending), `"recent"` (lastSeen descending) each tested with 3 items.
  - filter: `qualities = {[3]=true}` hides others; `minValue` compares `value` (an item with AH `n/a` and vendor 500 has value 500); `search="kings"` matches `"Kingsblood"` case-insensitively and treats `"("` literally (plain find); `isFiltered` false for `{minValue=0, search="", qualities=nil}` and for a full 0..7 set, true otherwise.
  - totals follow visible rows only: with a filter hiding one row the sums exclude it and `filtered==true`; `ah` counts missing AH as 0 and `unpriced` counts rows with `ahEach==nil`.
  - per hour: elapsed 3600 s and AH total 1200000 -> `ahPerHour == 1200000`; elapsed 30 s -> `nil` (not inf/nan); elapsed 0 -> `nil`.
  - top: at most 3 rows, by `value` descending, ties by name then id, zero-value rows excluded, taken from visible rows.
  - `itemInfo` returning nil: row name equals `Kingsblood` parsed from the link, quality 1, no error; `lookup` returning all-nil: `value==0`, `ahEach==nil`.
  - stale: row with `ahFromCache` and age 50400 has `stale==true`; live price has `stale==false`.
  - `indexOf(rows, id)` returns the 1-based index or nil; `flashLevel(60000, 2)=="strong"`, `flashLevel(1000, 5)=="normal"`, `flashLevel(nil, 1)=="normal"`, `flashLevel(100000, 1)=="strong"`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the interface above (pure; compare names with `string.lower` and plain `string.find`).
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat: ledger view with filter, sort, top finds, totals`.

---

### Task 8: Saved-variable defaults, slash parsing, Core wiring

**Files:** Create `LootPrice/DB.lua`, `LootPrice/Slash.lua`, `LootPrice/Core.lua`; Test `tests/test_db.lua`, `tests/test_slash.lua`

**Interfaces:**
- Produces: `ns.DB.defaults` = `{version=1, cache={}, settings={keepSession=false, tsmSource="DBMarket"}, window={point="CENTER", x=0, y=0, width=420, height=360, hidden=false}, filter={qualities={[0..7]=true}, minValue=0, search=""}, sort="ah"}`; `ns.DB.applyDefaults(saved: table|nil, defaults: table) -> table` (fills missing keys recursively, replaces values whose type differs from the default's, never mutates `defaults`, leaves keys unknown to `defaults` such as `cache[...]` alone); `ns.Slash.parse(msg: string) -> command: string, arg: string|nil` (`""` -> `"toggle"`; command lowercased, argument keeps its case).
- Produces (client, in `Core.lua`): `ns.db` (account), `ns.chardb`, `ns.session`, `ns.prices`; `ns.Core.recordLoot(link, qty)`; calls `ns.UI.refresh()` / `ns.UI.flash(itemID, level)` only `if ns.UI` exists.

- [ ] **Step 1: Write the failing tests:** `applyDefaults(nil, D)` deep-equals `D` and is a copy (mutating it leaves `D` unchanged); `applyDefaults({settings={keepSession=true}}, D)` keeps `keepSession=true` and fills `tsmSource`; `{settings="oops"}` becomes the default settings table; `{window={width="x"}}` gets `width==420`; extra `cache` entries survive. Slash: `""->"toggle"`, `"show"->"show"`, `"KEEP on"->"keep","on"`, `"tsm DBMinBuyout"->"tsm","DBMinBuyout"`, `"  reset "->"reset"`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** `DB.lua` and `Slash.lua`.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Implement `Core.lua`** (client-only, no unit test): on `ADDON_LOADED` (our addon) apply defaults to `LootPriceDB` and `LootPriceCharDB`; on `PLAYER_LOGIN` create `ns.session = Session.login(ns.chardb.session, ns.db.settings.keepSession, time())`, store it in `ns.chardb.session`, build `ns.prices` with sources `{TSM, Auctionator}` over `_G`, `vendor = Sources.Vendor.get(_G, id)`, `cache = ns.db.cache`, `key` from `Prices.cacheKey(GetCurrentRegionName(), C_GameRules.GetCurrentGameModeRecordID())` (guard missing API with `pcall`), `now = time`; on `PLAYER_ENTERING_WORLD` re-evaluate the key; on `CHAT_MSG_LOOT` parse with `LootParse` (compiled once from the real globals) and call `recordLoot`; `recordLoot` adds to the session, then `UI.flash(itemID, View.flashLevel(unitValue, qty))` and `UI.refresh()`; on `GET_ITEM_INFO_RECEIVED` request a throttled (0.2 s) `UI.refresh()`; on `PLAYER_LOGOUT` call `Session.suspend`. Register `/lp` via `Slash.parse`: `toggle/show/hide` call `UI.Window`, `start/stop/reset` act on `ns.session` (reset goes through the confirmation in Task 11), `keep on|off` and `tsm <source>` write settings and print the new value, `demo` injects 6 fake looted items with fake links and varied qualities (dev aid for UI checks), `help` prints the list.
- [ ] **Step 6: Verify in client:** `/reload`, no Lua errors; `/lp help` lists the commands; loot a vendor item and confirm via `/dump LootPriceCharDB.session.items`.
- [ ] **Step 7: Commit** `feat: saved defaults, slash parsing and core event wiring`.

---

### Task 9: Theme and ledger window

**Files:** Create `LootPrice/Theme.lua`, `LootPrice/UI/Window.lua`; Test `tests/test_theme.lua`

**Interfaces:**
- Produces: `ns.Theme` with `textures` (parchment, frame border, row highlight, resize grip), `fonts` (title, body, number), `colors` (ink, stale orange, gold, flash normal/strong, panel tint), `sizes` (min width 320, min height 240, row height, padding), `Theme.qualityColor(quality: integer, onParchment: boolean) -> r, g, b` (0..1, darker variants for parchment); `ns.UI.Window.create(db) -> frame` with child frames `frame.header`, `frame.topBox`, `frame.listArea`, `frame.footer`; `Window.show()`, `Window.hide()`, `Window.toggle()`, `Window.isShown() -> boolean`.

- [ ] **Step 1: Write the failing test:** every key above exists in `Theme`; `qualityColor(q, true/false)` for q = 0..7 returns three numbers in `[0,1]`; out-of-range quality returns the quality-1 color.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement `Theme.lua`** with built-in Blizzard paths (parchment-style background, dialog/tooltip border, standard fonts). Verify each texture path in the client before relying on it (`/run f=CreateFrame("Frame",nil,UIParent,"BackdropTemplate")` style check) and pick a replacement when one is missing.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Implement `Window.lua`:** a `BackdropTemplate` frame in the quest-log look titled "Session Ledger", regions stacked header / topBox / listArea / footer, movable by dragging the title area, resizable with a grip (`SetResizable(true)`, `SetResizeBounds(sizes.minWidth, sizes.minHeight)`), `SetClampedToScreen(true)`, position/size/hidden written to `db.window` on drag stop, resize stop and hide/show, restored on create; a visible Hide control is added by Task 11.
- [ ] **Step 6: Verify in client:** window appears parchment-styled, drag, resize (cannot go below minimum), `/reload` keeps position, size and hidden state; `/lp hide` then `/lp show` works; changing UI scale or resolution never leaves it off-screen.
- [ ] **Step 7: Commit** `feat: themed ledger window`.

---

### Task 10: Ledger rows, flash, controller

**Files:** Create `LootPrice/UI/Rows.lua`, `LootPrice/UI/Ledger.lua`

**Interfaces:**
- Consumes: `View.build`, `View.indexOf`, `Window.create` regions, `ns.prices:lookup`, `ns.session`, `ns.db.filter`, `ns.db.sort`.
- Produces: `Rows.attach(listArea) -> list` with `list:SetData(rows: Row[])`, `list:Flash(itemID, level: "normal"|"strong")`, `list:ScrollToItem(itemID)`; `ns.UI.Ledger.refresh()` (builds the view from live data via `itemInfo = C_Item.GetItemInfo`-backed function and updates every attached part); `ns.UI.refresh = Ledger.refresh`; `ns.UI.flash(itemID, level)` (refresh, then scroll to the row if it is outside the visible range, then flash it).

- [ ] **Step 1: Implement `Rows.lua`:** a scroll frame (FauxScrollFrame-style) with a pool of row frames sized to the visible height; each row: quality-colored icon frame with the item texture, name in quality color (`Theme.qualityColor(q, true)`), `×qty`, `Vendor: <Money> | AH: <Money>`, `n/a` when nil, the age tag `(14h)` from `Prices.formatAge` when `ahFromCache`, in `Theme.colors.stale` when `stale`; flash = a highlight texture with an alpha-animation group using `Theme.colors.flash*` (strong = brighter and longer).
- [ ] **Step 2: Implement `Ledger.lua`:** `refresh()` as above, called every second by an `OnUpdate` accumulator while the window is shown and the session is running (updates timer and gold/hour), and immediately on loot.
- [ ] **Step 3: Verify in client** with `/lp demo`: six rows with quality-colored names, vendor and AH side by side, `n/a` for the unpriced demo item, an orange age tag on the stale demo item, list scrolls with the mouse wheel, looting a real item flashes its row and a new row scrolls into view if hidden; a stack increase re-flashes the existing row; an item whose info is not cached shows its link name and corrects itself shortly after.
- [ ] **Step 4: Commit** `feat: scrolling ledger rows with loot flash`.

---

### Task 11: Header (timer and session buttons)

**Files:** Create `LootPrice/UI/Header.lua`

**Interfaces:**
- Produces: `Header.attach(headerFrame, handlers) -> header` with `handlers = {start, stop, reset, hide}` (functions) and `header:SetElapsed(seconds)`, `header:SetRunning(boolean)`; the Reset button asks `StaticPopup` confirmation only when `Session.needsResetConfirm(ns.session)`.
- Consumes: `Session` (Task 6), `Money`/`Theme` for text; `Ledger.refresh` calls `SetElapsed`/`SetRunning` each tick.

- [ ] **Step 1: Implement** the header: timer text `HH:MM:SS` (running time only), buttons Start, Stop, Reset, Hide in the quest-log style; Start disabled while running and Stop disabled while stopped; Hide hides the window (the slash command restores it); the three session buttons share handlers with `/lp start|stop|reset`.
- [ ] **Step 2: Verify in client:** timer runs; Stop freezes it and a looted item does not appear while stopped; Start resumes where it left off; Reset with fewer than 25 items clears immediately, with 25 or more asks for confirmation (`/lp demo` repeatedly, or `/run` to add items); `/lp keep on`, `/reload`: session and timer survive and logged-out time is not counted; with keep off, `/reload` starts a fresh session.
- [ ] **Step 3: Commit** `feat: session header with timer and controls`.

---

### Task 12: Top finds and totals bar

**Files:** Create `LootPrice/UI/Summary.lua`

**Interfaces:**
- Consumes: `view.top`, `view.totals` (Task 7), `Money.format`.
- Produces: `Summary.attach(topBox, footer) -> summary` with `summary:Set(view)`.

- [ ] **Step 1: Implement** the Top finds block (up to 3 gold-edged rows: quality-colored name, quantity, value in gold; hidden when empty) and the totals bar: `Vendor: <total>`, `AH: <total>` plus `N unpriced` when `unpriced > 0`, and `<perHour>/h` for each (`—` when `nil`), with a `filtered` marker when `totals.filtered`.
- [ ] **Step 2: Verify in client** with `/lp demo`: top finds shows the three most valuable stacks (AH value, vendor fallback), totals match the visible rows by hand-adding two prices, `N unpriced` appears for the unpriced demo item, gold/hour shows `—` during the first minute and a number after.
- [ ] **Step 3: Commit** `feat: top finds and totals bar`.

---

### Task 13: Filter bar

**Files:** Create `LootPrice/UI/FilterBar.lua`

**Interfaces:**
- Produces: `FilterBar.attach(frame, db, onChange) -> bar`; edits `db.filter` and `db.sort` in place and calls `onChange()` after each edit.
- Consumes: `View.isFiltered`, `Theme`.

- [ ] **Step 1: Implement** the controls: quality toggles 0..7 (a dropdown menu with checkboxes, using whichever of `MenuUtil` or `UIDropDownMenuTemplate` exists in the Forever client), minimum value in gold (edit box, empty = 0), search edit box (case-insensitive), sort dropdown (`ah`, `vendor`, `name`, `recent`); a visible "filter active" state on the bar when `View.isFiltered(db.filter)`; place it in the header's second row.
- [ ] **Step 2: Verify in client** with `/lp demo`: unticking a quality hides those rows, totals and top finds change accordingly with the `filtered` marker, min value and search narrow the list, every sort order reorders the rows, and after `/reload` the same filter and sort are still active.
- [ ] **Step 3: Commit** `feat: ledger filter and sort bar`.

---

### Task 14: Packaging and release prep

**Files:** Create `.pkgmeta`; Modify `README.md`, `LootPrice/LootPrice.toc`

- [ ] **Step 1:** `.pkgmeta` with `package-as: LootPrice` and ignore list (`tests`, `docs`, `.superpowers`); add `## Version: @project-version@`, `## Notes`, `## Author` to the `.toc`; README sections: what it shows, commands, settings, the known age-tag limit from the spec ("a source that silently serves old scan data looks fresh"), how to run the tests.
- [ ] **Step 2:** Run `lua tests/run.lua` — Expected: all PASS; then a final in-client pass of every verification step in Tasks 8-13 on a fresh `LootPriceDB` (delete the saved-variable files for one launch).
- [ ] **Step 3: Commit** `chore: packaging and readme`. (Creating the GitHub repo and wiring CurseForge/Wago/WoWInterface tokens is outward-facing: do it only when the user asks.)
