# Footer Value Table Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three stacked footer blocks (158 px) with a compact table: rows Items / Raw gold / Total, columns Value (best) and /h, a notes line, and the vendor / AH split in a hover tooltip.

**Architecture:** `UI/Summary.lua` gets pure helpers (`tableLayout`, `rowTexts`, `notesText`, `tooltipLines`, `tableWorstWidth`) that the tests pin; `Summary.attach` draws the table from them. `Theme.sizes` loses the block sizes and gains `footerRowHeight`; `UI/Fonts.lua` scales and recomputes the new sizes. Top finds and the `View` data are unchanged.

**Tech Stack:** Lua 5.1 (WoW Forever client), plain-Lua tests (`lua tests/run.lua`).

**Spec:** `docs/superpowers/specs/2026-11-15-footer-table-design.md`

## Global Constraints

- Lua 5.1 code (no `goto`, `//`, `table.unpack`); WoW globals only inside functions in `UI/`.
- All texts through `ns.L`; German in `Locales/deDE.lua`; `tests/test_locale.lua` fails on German keys no longer used (remove them).
- Money is copper; format with `ns.Money.formatColored` (tests pass `ns.Money.format`).
- A missing rate shows an em dash (`"\226\128\148"`), never `n/a`.
- Look values (sizes, colors, fonts) live in `Theme.lua`.
- `lua tests/run.lua` must pass after each task.
- No commits unless the user asks (the working tree carries other uncommitted work).

## Review Focus

1. Totals text size option (`fontSizeTotals`) not 12: `footerRowHeight` / `footerNoteHeight` scale and `footerHeight` / `minHeight` are recomputed (test in Task 2).
2. Bank tab with a stale scan note **and** unpriced items: one notes line holding both, orange (test in Task 1).
3. Option **Add raw gold to the combined total** off (`view.noCombined`): Total row hidden and the footer 54 px; on again: back to 72 (wiring test in Task 2).
4. Session -> Bags -> Session: rows, titles and the /h column hidden on Bags come back on Session (wiring test in Task 2).
5. History / a fresh session with no rates: every rate cell is the em dash, no `n/a` (test in Task 1).

---

### Task 1: Pure table helpers (additive)

Task 1 only adds; the old footer keeps working until Task 2 switches over.

**Files:**
- Modify: `LootPrice/UI/Summary.lua` (pure helpers section: add the helpers below)
- Modify: `LootPrice/Theme.lua` (add `sizes.footerRowHeight = 18`, `colors.columnTitle`)
- Test: `tests/test_summary.lua` (add tests)

**Interfaces:**
- Produces:
  - `Summary.ROWS = { "items", "gold", "total" }`
  - `Summary.tableLayout(view) -> { rows = {key...}, rates = bool, titles = bool, notes = bool, height = number }`
    - inventory (`view.kind == "inventory"`): rows `{ "items" }`, rates false, titles false
    - `view.noCombined`: rows `{ "items", "gold" }`
    - otherwise (also `nil` / `{}`): all three, rates true, titles true
    - `notes = Summary.notesText(view) ~= nil`
    - height = (titles and 1 or 0) * footerRowHeight + #rows * footerRowHeight + (notes and footerNoteHeight or 0)
  - `Summary.rowTexts(view, formatMoney) -> { items = {value, rate}, gold = {value, rate}, total = {value, rate} }`
    - items: `totals.best`, `totals.bestPerHour`; gold: `gold.total`, `gold.perHour`; total: `combined.best`, `combined.bestPerHour`
    - value = money of the amount (0 when nil); rate = `Summary.rateText(perHour, formatMoney)`
  - `Summary.notesText(view) -> text|nil, orange:boolean` — parts in order: `L["filtered"]` if `totals.filtered`; `N .. L[" unpriced"]` if `totals.unpriced > 0`; `view.note`. Joined with `" · "` (`" \194\183 "`). orange = filtered or unpriced or `view.noteStale`. nil when no part.
  - `Summary.tooltipLines(view, formatMoney) -> { {left, right}, ... }` — a title line `{ L["Items"], "" }`, then `Vendor: ` / `AH: ` / `Best: ` with the amount, and `"  " .. rateText(rate)` appended when the view has rates; then the same under `L["Items + gold"]` from `view.combined` unless inventory or `noCombined`.
  - `Summary.tableWorstWidth() -> number` = `(11 + 15 + 14) * summaryCharPx + 6 + 8`
  - Theme: `sizes.footerRowHeight = 18` (`footerNoteHeight` stays 16); `colors.columnTitle` = the `colors.hint` values.

- [ ] **Step 1: Write the failing tests** in `tests/test_summary.lua`:

```lua
h.test("tableLayout: session, inventory, noCombined", function()
  local r = ns.Theme.sizes.footerRowHeight
  local s = S.tableLayout({ totals = {} })
  h.eq(s.rows, { "items", "gold", "total" }); h.eq(s.rates, true); h.eq(s.titles, true)
  h.eq(s.height, 72); h.eq(4 * r, 72)
  h.eq(S.tableLayout(nil).height, 72)
  local inv = S.tableLayout({ kind = "inventory", totals = {} })
  h.eq(inv.rows, { "items" }); h.eq(inv.rates, false); h.eq(inv.titles, false); h.eq(inv.height, 18)
  h.eq(S.tableLayout({ noCombined = true, totals = {} }).rows, { "items", "gold" })
  h.eq(S.tableLayout({ noCombined = true, totals = {} }).height, 54)
  h.eq(S.tableLayout({ kind = "inventory", note = "x", totals = {} }).height, 18 + 16)
end)

h.test("rowTexts: best value and rate per row, em dash without a rate", function()
  local t = S.rowTexts({ totals = { best = 1000, bestPerHour = 300 }, gold = { total = 50 },
    combined = { best = 1050, bestPerHour = 320 } }, M.format)
  h.eq(t.items.value, M.format(1000)); h.eq(t.items.rate, M.format(300) .. "/h")
  h.eq(t.gold.value, M.format(50)); h.eq(t.gold.rate, "\226\128\148")
  h.eq(t.total.value, M.format(1050)); h.eq(t.total.rate, M.format(320) .. "/h")
  local e = S.rowTexts({}, M.format)
  h.eq(e.items.value, "0c"); h.eq(e.total.rate, "\226\128\148")
  for _, row in pairs(e) do h.eq(row.rate:find("n/a", 1, true), nil) end
end)

h.test("notesText: markers and bank note on one line", function()
  h.eq(S.notesText({ totals = {} }), nil)
  local text, orange = S.notesText({ totals = { filtered = true, unpriced = 3 } })
  h.eq(text, "filtered \194\183 3 unpriced"); h.eq(orange, true)
  text, orange = S.notesText({ kind = "inventory", totals = {}, note = "Scanned 3h ago" })
  h.eq(text, "Scanned 3h ago"); h.eq(orange, false)
  text, orange = S.notesText({ totals = { unpriced = 2 }, note = "Scanned 2d ago", noteStale = true })
  h.eq(text, "2 unpriced \194\183 Scanned 2d ago"); h.eq(orange, true)
end)

h.test("tooltipLines: items and items + gold with rates; inventory without", function()
  local view = { totals = { vendor = 1, ah = 2, best = 2, vendorPerHour = 10, ahPerHour = 20, bestPerHour = 20 },
    combined = { vendor = 3, ah = 4, best = 4 } }
  local l = S.tooltipLines(view, M.format)
  h.eq(l[1], { "Items", "" })
  h.eq(l[2], { "Vendor: ", M.format(1) .. "  " .. M.format(10) .. "/h" })
  h.eq(l[5], { "Items + gold", "" })
  h.eq(#l, 8)
  local inv = S.tooltipLines({ kind = "inventory", totals = { vendor = 1, ah = 2, best = 2 } }, M.format)
  h.eq(#inv, 4); h.eq(inv[2], { "Vendor: ", M.format(1) })
  h.eq(#S.tooltipLines({ noCombined = true, totals = view.totals, combined = view.combined }, M.format), 4)
end)

h.test("table worst case fits the minimum window width", function()
  local T = ns.Theme.sizes
  h.eq(S.tableWorstWidth() <= T.minWidth - 2 * (T.padding + 4), true)
end)

```

- [ ] **Step 2: Run `lua tests/run.lua`** — expected: the new tests FAIL (`tableLayout` is nil).
- [ ] **Step 3: Implement** the helpers and the two Theme additions per Interfaces.
- [ ] **Step 4: Run `lua tests/run.lua`** — expected: all pass.

---

### Task 2: Switch the footer to the table

**Files:**
- Modify: `LootPrice/UI/Summary.lua` (rewrite the footer part of `Summary.attach`; Top finds part unchanged; remove `totalsText`, `goldText`, `combinedText`, `bestText`, `footerLayout`, `footerHeightFor`, `footerHalfWidth`, `footerWorstWidth`; `requiredWindowHeight` uses `Summary.tableLayout({}).height`)
- Modify: `LootPrice/Theme.lua` (`footerHeight = 72`, `minHeight = 428` with the comment `24 + 84 + 88 + 4 * 40 + 72 = 428`; remove `footerLabelHeight`, `footerLabelGap`, `footerItemsHeight`, `footerGoldHeight`, `footerTotalHeight`, `fonts.blockLabel`)
- Modify: `LootPrice/UI/Fonts.lua` (totals group sizes `{ "footerRowHeight", "footerNoteHeight", "topRowHeight" }`; titles group fonts `{ "topHeader" }`, sizes `{ "topHeaderHeight" }`; `Fonts.install` sets `s.footerHeight = 4 * s.footerRowHeight` before recomputing `minHeight`)
- Modify: `LootPrice/Locales/deDE.lua` (add `["Total"] = "Gesamt"`; remove keys test_locale reports, e.g. `["Gold "]`)
- Modify: `README.md` (Footer bullet, in-client checklist lines about the footer blocks)
- Test: `tests/test_summary.lua` (remove the tests of the removed helpers; add the minHeight test below), `tests/test_theme.lua` (key list: drop the removed sizes, add `footerRowHeight`; expect `footerHeight` 72, `minHeight` 428), `tests/test_fonts.lua` (`h.eq(ns.Theme.sizes.footerHeight, 4 * ns.Theme.sizes.footerRowHeight)`; with `fontSizeTotals` above 12 assert `footerRowHeight > 18`), `tests/test_wiring.lua`

**Interfaces:**
- Consumes: everything Task 1 produces.
- Produces: `summary.cells[key] = { label, value, rate }` FontStrings for `key` in `Summary.ROWS`; `summary.titles = { value, rate }`; `summary.notes` FontString; `summary.table` the hover frame. `summary:Set(view)` / part `Update` / `Tick` keep their names; `Tick` refreshes only the rate cells.

- [ ] **Step 1: Write the failing wiring tests** in `tests/test_wiring.lua`:

```lua
h.test("wiring: footer table height follows the tab and Include raw gold", function()
  local ctx = boot()
  startWorld(ctx, false)
  local L, footer = ctx.ns.UI.Ledger, ctx.ns.UI.Window.frame.footer
  L.refresh()
  h.eq(footer:GetHeight(), 72)
  L.setTab("bags")
  h.eq(footer:GetHeight(), 18)
  h.eq(ctx.ns.UI.Summary.instance.cells.gold.label:IsShown(), false)
  L.setTab("session")
  h.eq(footer:GetHeight(), 72)
  h.eq(ctx.ns.UI.Summary.instance.cells.gold.label:IsShown(), true)
  h.eq(ctx.ns.UI.Summary.instance.cells.items.rate:IsShown(), true)
  ctx.ns.Options.set(ctx.ns.db, "includeGold", false)
  L.refresh()
  h.eq(footer:GetHeight(), 54)
  h.eq(ctx.errors, {})
end)
```

In `tests/test_summary.lua`:

```lua
h.test("minHeight leaves the list at least four rows beside a full Top finds block", function()
  local T = ns.Theme.sizes
  h.eq(S.requiredWindowHeight(), 24 + 84 + 88 + 4 * 40 + 72)
  h.eq(T.minHeight, 428)
  h.eq(T.footerHeight, 72)
end)
```

- [ ] **Step 2: Run `lua tests/run.lua`** — expected: FAIL (`cells` is nil, minHeight 514).
- [ ] **Step 3: Rewrite the footer part of `Summary.attach`:** one row frame per `Summary.ROWS` key plus a titles row, each `footerRowHeight` high, stacked from the footer top in `tableLayout(view).rows` order (re-anchor on `SetKind`). Cells: label left (`T.fonts.summary`, ink; Total row label and value in `T.colors.gold`), rate right-aligned at the right edge, value right-aligned ending `rateColumnWidth + 8` px left of the edge (rate column width = `14 * summaryCharPx`); without rates the value ends at the right edge. Titles row: `L["Value"]` and `L["/h"]` in `T.fonts.summaryMarker` / `T.colors.columnTitle`. Notes line under the last row: `summaryMarker` font, `stale` color when orange else ink. The footer frame `EnableMouse(true)` with `OnEnter` filling `GameTooltip` via `AddDoubleLine` from `Summary.tooltipLines(view)` (keep the last view on the summary) and `OnLeave` = `W.hideTooltip`; mark `-- UNVERIFIED (check in client): GameTooltip:AddDoubleLine on the footer`. Call `Window.setFooterHeight(layout.height)` when the height changes.
- [ ] **Step 4: Texts and docs:** add `["Total"] = "Gesamt"` to deDE; remove German keys `tests/test_locale.lua` reports as unused. README: replace the **Footer** bullet with the table description (rows, columns, notes line, tooltip, Bags/Bank one row, that option off drops Total); in the in-client checklist replace the footer-block lines with: table columns line up at 350 px with German texts; hovering the footer shows the vendor / AH tooltip; notes line appears only with filtered / unpriced / bank note.
- [ ] **Step 5: Run `lua tests/run.lua`** — expected: all pass.
