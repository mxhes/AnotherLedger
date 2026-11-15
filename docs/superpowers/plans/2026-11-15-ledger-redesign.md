# Ledger redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A compact glance mode in the same window, one bronze dark button style, list rows with one counted value plus a source tag, and the footer / Daily farm / Top finds fixes from the 2026-11-15 screenshot review.

**Architecture:** Pure helpers carry every rule (row texts, tooltip lines, button colors, compact view, which parts a mode shows) and are unit tested; `UI/` files only draw. The mode is Ledger state saved in `db.mode`; `Window.applyMode` shows / hides the full-mode frames and applies the mode's size; a new ledger part `UI/Compact.lua` draws `View.buildCompact`.

**Tech Stack:** Lua 5.1 WoW addon, plain-Lua tests (`lua tests/run.lua`).

**Spec:** `docs/superpowers/specs/2026-11-15-ledger-redesign-design.md`

## Global Constraints

- Lua 5.1 only; `lua tests/run.lua` after every step, all pass.
- Pure code outside `UI/`; `UI/` touches globals only inside functions.
- Look in `Theme.lua` only (colors, sizes, fonts, textures); options only via `Options.define` + `DB.defaults.settings`; texts via `ns.L` with German in `Locales/deDE.lua`.
- New `.lua` files in the `.toc` and README layout table; new named global frames in the wiring test's `allowed` list (prefer unnamed).
- Unconfirmed client APIs: `UNVERIFIED (check in client)` + README checklist line.
- Write Lua with Write / Edit; no raw control characters; mind CRLF in edited files.
- Commits `feat:` / `fix:` + short body + `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- README updated in the same task as each feature.

## Review Focus

1. **History / Zones place rows and currency rows** (no single source, no price) → plain amount without tag, no `?`, no error.
2. **Switching mode while hidden, in combat (combat hide), with the window locked, or with a saved size smaller than the mode's minimum** → no error; size clamped to the mode minimum; position kept.
3. **Compact with an empty session, a stopped clock, `compactDrops = 0`, `dailyFarm` off** → no error, the blocks collapse, the Paused marker shows when stopped.
4. **A double-click on the title after a drag** → only a real double-click switches mode; dragging still moves the window.
5. **Old saved `db.window` without per-mode sizes** → full mode uses the old width / height; compact starts at its default.

---

### Task 1: List rows — one counted value with a source tag

**Files:** Modify `LootPrice/UI/Rows.lua`, `LootPrice/Theme.lua`, `LootPrice/Locales/deDE.lua`, `README.md`; Test `tests/test_rows.lua`, `tests/test_wiring.lua`.

**Interfaces:**
- Produces:
  - `Rows.rowText(row, formatMoney)` returns `{ name, qty, amount, source, tag, tagStale, unpriced, market }`:
    - `amount` = `formatMoney(row.value)` when `row.bestKind` is set; else `L["bound"]` text when `row.bound`; else `"?"`. Rows that bring their own total (`row.bestLineTotal`, History / Zones place rows) use it as `amount`, `source = nil`.
    - `source` = `row.bestKind` ("vendor" / "ah" / "de") or nil; tag text `L["Vendor"]`, `L["AH"]`, `L["DE"]`.
    - `unpriced` = `row.ahEach == nil and not row.bound and not row.isCurrency and row.bestLineTotal == nil` (today's footer rule); drawn as a `?` after the tag.
    - `tag` / `tagStale`: the cached-AH age tag, only when `source == "ah"`.
    - currencies: `amount = ""`, `source = nil`, `unpriced = false`.
  - `Rows.tooltipLines(row, formatMoney) -> { string, ... }`: `Vendor: <total> (<each> each)`, `AH: ...`, `DE: ...` for each known value (each only when qty > 1), the counted one marked with `Theme.colors.best`; empty list for currencies.
  - Theme: `colors.tagVendor`, `colors.tagAh`, `colors.tagDe` (tan / light blue / violet, as the mockup), `sizes.rowTagPad`.
  - The row frame draws one amount right-aligned on line 1 plus the framed tag; line 2 stays the TSM sale line. The vendor / best label strings and `Rows.LABELS` go away (and their German keys).

- [ ] **Step 1: Failing tests** in `tests/test_rows.lua` (replace the old two-label tests):

```lua
h.test("Rows.rowText: one counted value with its source", function()
  local t = R.rowText({ name = "Sword", quantity = 1, value = 18003, bestKind = "vendor",
    vendorTotal = 18003, deTotal = 8803, ahEach = nil }, M.format)
  h.eq(t.amount, M.format(18003)); h.eq(t.source, "vendor"); h.eq(t.unpriced, true)
  t = R.rowText({ name = "Knapsack", quantity = 1, value = 9700, bestKind = "ah", ahEach = 9700,
    ahTotal = 9700, vendorTotal = 5000 }, M.format)
  h.eq(t.source, "ah"); h.eq(t.unpriced, false)
end)

h.test("Rows.rowText: bound, nothing, currency and own totals", function()
  h.eq(R.rowText({ quantity = 1, value = 0, bound = true }, M.format).amount, ns.L["bound"])
  local t = R.rowText({ quantity = 1, value = 500, bestKind = "vendor", vendorTotal = 500, bound = true }, M.format)
  h.eq(t.source, "vendor"); h.eq(t.unpriced, false)
  h.eq(R.rowText({ quantity = 1, value = 0 }, M.format).amount, "?")
  local c = R.rowText({ quantity = 3, isCurrency = true }, M.format)
  h.eq(c.amount, ""); h.eq(c.unpriced, false)
  local p = R.rowText({ quantity = 4, value = 400, bestLineTotal = 400 }, M.format)
  h.eq(p.amount, M.format(400)); h.eq(p.source, nil); h.eq(p.unpriced, false)
end)

h.test("Rows.tooltipLines lists every known value, per unit with qty > 1", function()
  local lines = R.tooltipLines({ quantity = 2, vendorTotal = 100, vendorEach = 50, ahTotal = 300, ahEach = 150,
    bestKind = "ah" }, M.format)
  h.eq(#lines, 2)
  h.eq(lines[1]:find(M.format(100), 1, true) ~= nil, true)
  h.eq(lines[2]:find(M.format(150), 1, true) ~= nil, true)
end)
```

Keep / adapt the existing age-tag and width tests to the new fields.

- [ ] **Step 2: Run, verify FAIL.**
- [ ] **Step 3: Implement** the interfaces; the row tooltip (`OnEnter`) shows the item tooltip and appends `tooltipLines` (UNVERIFIED: `GameTooltip:AddLine` after `SetHyperlink`).
- [ ] **Step 4: README** row description, checklist line (tag colors readable, `?` mark, tooltip values).
- [ ] **Step 5: Run, all pass; commit** `feat: list rows show one counted value with its source`.

---

### Task 2: Footer, Top finds and Daily farm fixes; two display options

**Files:** Modify `LootPrice/UI/Summary.lua`, `LootPrice/UI/DailyFarm.lua`, `LootPrice/Theme.lua`, `LootPrice/Options.lua`, `LootPrice/DB.lua`, `LootPrice/Locales/deDE.lua`, `README.md`; Test `tests/test_summary.lua`, `tests/test_dailyfarm.lua`, `tests/test_options.lua`, `tests/test_db.lua`, `tests/test_wiring.lua`.

**Interfaces:**
- `Summary.rateText(perHour, formatMoney)` → amount without `/h` (em dash without a rate); the column title is `L["per hour"]`.
- Top finds title uses `Theme.fonts.title` (not `topHeader`), `sizes.topHeaderHeight` follows it.
- `DailyFarm.label(farm)` → `L["Daily farm: "] .. rate .. "  " .. place` (rate first), slow note last. `Theme.textures.dailyFarm` = a gold star texture (`"Interface\\Common\\FavoritesIcon"`, UNVERIFIED) with `colors.dailyFarm` vertex color.
- Options (category `"display"`, after `dailyFarmMinutes`): `showTopFinds` (checkbox, default true), `showFooterGold` (checkbox, default true; hides the Raw gold row; Total still follows `includeGold`). `Summary.tableLayout(view)` and the top box read them via `Options.get`.

- [ ] **Step 1: Failing tests**: `rateText(15000, M.format) == M.format(15000)`; `DailyFarm.label` starts with `L["Daily farm: "] .. "~"`; options registered in order and defaults; wiring: `showTopFinds` off collapses the top box (`Window.frame.topBox:IsShown() == false`), `showFooterGold` off drops the Raw gold row from `Summary.tableLayout`.
- [ ] **Step 2: Run, verify FAIL.**
- [ ] **Step 3: Implement.** Ruling recorded in the ledger: coin colors are already one formatter (`Money.formatColored`; silver is near-white by design) — no change.
- [ ] **Step 4: README** footer / options / Daily farm text, checklist (star texture).
- [ ] **Step 5: Run, all pass; commit** `feat: footer per hour column, rate-first daily farm, display options`.

---

### Task 3: One bronze dark button style

**Files:** Modify `LootPrice/UI/Widgets.lua`, `LootPrice/UI/Header.lua`, `LootPrice/UI/FilterBar.lua`, `LootPrice/Theme.lua`, `README.md`; Create `tests/test_widgets.lua`; Test `tests/test_wiring.lua`.

**Interfaces:**
- `Widgets.buttonColors(state, warn) -> { fill, edge, text }` (pure): state `"normal" | "hover" | "disabled"`; from `Theme.colors.buttonFill`, `buttonEdge`, `buttonEdgeHover` (gold), `buttonText`, `buttonTextDisabled`, `buttonWarnEdge`, `buttonWarnText`.
- `Widgets.button(parent, label, width, opts)` — no `UIPanelButtonTemplate`: a `Button` with `BackdropTemplate`, fill + edge from `buttonColors`, label FontString in `fonts.button`; `OnEnter` / `OnLeave` / `OnDisable` / `OnEnable` recolor; keeps `SetText` / `GetText` / `Enable` / `Disable` working for callers. `opts.warn` for Reset.
- `Widgets.iconButton(parent, glyph, size, onClick)` — same style, square, `glyph` = `"gear"` | `"close"` drawn from `Theme.textures.iconGear` / `iconClose` (UNVERIFIED paths).
- Header: options and close become `iconButton`s; Reset `button(..., { warn = true })`. FilterBar inputs use `buttonEdge` for their border.

- [ ] **Step 1: Failing tests**: `buttonColors("hover").edge == Theme.colors.buttonEdgeHover`; warn uses the warn edge / text in every state; disabled text is `buttonTextDisabled`; wiring: `Header` reset button has `warn == true`, options / close buttons are the icon kind (`button.kind == "icon"`), every header and filter button's `kind` is `"bronze"`.
- [ ] **Step 2: Run, verify FAIL.**
- [ ] **Step 3: Implement**; `Widgets.closeButton` removed (no other callers — check `OptionsPanel`, `Export`).
- [ ] **Step 4: README** look text, checklist (hover gold edge, disabled dim, warn tint, glyphs).
- [ ] **Step 5: Run, all pass; commit** `feat: one bronze dark button style`.

---

### Task 4: Last drops and the compact view (pure)

**Files:** Modify `LootPrice/Session.lua`, `LootPrice/Core.lua`, `LootPrice/View.lua`, `LootPrice/Options.lua`, `LootPrice/DB.lua`, `LootPrice/Locales/deDE.lua`; Test `tests/test_session.lua`, `tests/test_view.lua`, `tests/test_options.lua`, `tests/test_db.lua`, `tests/test_wiring.lua`.

**Interfaces:**
- `Session.RECENT_MAX = 4`; `Session.noteRecent(session, key, qty, now)` prepends `{ key, qty, at }`, caps at 4; `Session.new` / `Session.reset` set `recent = {}`; `Session.login` repairs a non-table `recent`; History never copies it.
- `Core.recordLoot` calls `noteRecent` after a counted loot (same place as `notePlaceLoot`).
- `View.buildCompact(session, opts, now) -> { perHour, total, running, drops }`:
  - `total` = items best value (unfiltered) + raw gold when `opts.includeGold ~= false`; `perHour` = `total` over `Session.elapsed` (nil under 60 s, `History.perHour` rule); `running = session.running`.
  - `drops` = up to `opts.compactDrops` rows (default 4), each `makeRow({ id, key, link, qty = event.qty, ... })` from `session.items[event.key]` with the event's own qty; events whose item is gone are skipped.
- Option `compactDrops` (slider 0–4, step 1, default 4, category `"display"`), read into `viewOpts.compactDrops` in `Ledger`.

- [ ] **Step 1: Failing tests**: `noteRecent` order / cap / reset; `buildCompact` ignores `opts.filter` (a search that hides everything still gives the full total), adds raw gold only with `includeGold`, per-drop value uses the event qty (two drops of one item = two rows with their own value), `compactDrops = 0` gives no drops, `perHour` nil under 60 s; wiring: three loots → `ns.session.recent` has 3 entries newest first; reset clears it; History entry has no `recent`.
- [ ] **Step 2: Run, verify FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, all pass; commit** `feat: last drops and the compact view`.

---

### Task 5: Compact mode in the window

**Files:** Create `LootPrice/UI/Compact.lua`; Modify `LootPrice/UI/Window.lua`, `LootPrice/UI/Ledger.lua`, `LootPrice/UI/Header.lua`, `LootPrice/Slash.lua`, `LootPrice/DB.lua`, `LootPrice/Theme.lua`, `LootPrice/LootPrice.toc`, `LootPrice/Locales/deDE.lua`, `README.md`; Test `tests/test_window.lua`, `tests/test_wiring.lua`, `tests/test_slash.lua`.

**Interfaces:**
- `db.mode` (`"full"` default; repaired by `DB.applyDefaults` to `"full"` when not `"full"`/`"compact"`); `db.window.compact = { width, height }` (defaults from `Theme.sizes.compactWidth` 250 / `compactHeight` 190); full keeps `db.window.width` / `height`.
- `Window.modeParts(mode) -> { [name] = shown }` (pure): which of `row2`, `rowFarm`, `row3`, `row4`, `listArea`, `footer`, `topBox`, `compact` show; full = today's rules (rowFarm / row4 / topBox still driven by their setters), compact = only `compact`.
- `Window.applyMode(mode)`: saves the current size into the old mode's slot, applies the new mode's size and minimum (`compactMinWidth` 220 / `compactMinHeight` 140; full keeps today's), shows / hides per `modeParts`, header height = row 1 only in compact. Position untouched.
- `Ledger.mode`, `Ledger.setMode(mode)` (saves `db.mode`, `applyMode`, one refresh); `Ledger.toggleMode()`.
- Header: a `Button` laid over the title text (`header.titleButton`) with `RegisterForClicks("LeftButtonUp")`, `OnDoubleClick` → `Ledger.toggleMode`, and `RegisterForDrag("LeftButton")` forwarding to `Window.beginDrag` / `endDrag` (UNVERIFIED: OnDoubleClick does not fire after a drag). In compact the header hides Start / Stop / Reset; the clock becomes clickable (`Core.startSession` / `stopSession`), dimmed with a red `L["Paused"]` marker when stopped.
- `UI/Compact.lua`: part registered with `Ledger.register`; `Update(view)` draws `Ledger.compactView` (built in `Ledger.buildView` only in compact mode via `View.buildCompact`): big per hour (`Theme.fonts.compactBig`, gold), total, "Last drops" lines (name in quality color, `x<qty>`, value + source tag as Task 1), Daily farm line (same `DailyFarm.click` handlers, rate first). Blocks collapse when empty / off.
- `Slash.define({ name = "compact", help = L["/lp compact - switch compact / full"], run = Ledger.toggleMode })`.

- [ ] **Step 1: Failing tests**: `modeParts` for both modes; `DB.applyDefaults` repairs `mode`; wiring: `/lp compact` switches, `Window.frame.listArea:IsShown() == false`, the compact frame shown, size is the compact default, back to full restores the old size; the title's `OnDoubleClick` toggles; in compact the clock click stops / starts the session and `Compact.paused` mirrors it; mode survives a reload; switching while hidden then showing draws the compact view; `/lp help` lists `compact`.
- [ ] **Step 2: Run, verify FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: README**: modes feature text, `/lp compact`, options (`compactDrops`), layout table (`UI/Compact.lua`), saved state (`db.mode`, compact size), checklist (double-click vs drag, sizes per mode, Paused marker, clock click, combat hide in compact).
- [ ] **Step 5: Run, all pass; commit** `feat: compact mode`.
