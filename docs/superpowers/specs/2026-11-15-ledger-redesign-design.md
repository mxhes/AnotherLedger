# Ledger redesign: compact mode and one bronze style — design

## Intent and why

The Session Ledger is used in two moments:

- **Between pulls, a glance** of a second or two: is this session still worth it,
  did something good drop?
- **After a session (or a stretch of time), a detailed look**: what dropped,
  what it is worth, where it came from.

Today the window serves only the second moment, and it looks inconsistent
(screenshot review, 2026-11-15): four button styles in one header (red
`UIPanelButtonTemplate` text buttons, dark input boxes, a gold gear picture, the
game's red close X); a "Best" line that is not always the best value; plain
amounts next to coin-colored ones; `/h` repeated on every footer amount; a
truncated Daily farm strip that drops the gold per hour; an icon that reads as
an error mark; "Top finds" set larger than the window title.

Goal: an original look that still fits the bronze WoW Forever UI, a compact
mode for the glance, and player control over which parts show.

## Goals

1. **Two modes in one window**, switched by double-clicking the title text
   (header row 1), remembered across logins (`db.mode = "full" | "compact"`).
   - **Compact**: header row 1 (title, clock, options and close icon buttons;
     no Start / Stop / Reset), then a compact body:
     - gold per hour in large gold type, the session total next to it: items
       plus raw gold (raw gold only with **Add raw gold to the combined
       total**), never filtered: the filter bar of full mode does not apply
       to anything compact shows (numbers or last drops);
     - while the session clock is stopped: the clock dimmed and a red
       `Paused` marker; **clicking the clock starts / stops the session**
       (Reset stays full-mode only);
     - "Last drops": the last 4 loot events of the running session, name in
       quality color with quantity, and the counted value;
     - the Daily farm line (same clicks as the strip).
   - **Full**: today's ledger, restyled (below).
   - Each mode keeps its own window size (`db.window.full`, `db.window.compact`
     width / height); position is shared.
2. **One bronze dark button style** for every button: dark fill, bronze edge
   (`Theme.colors.panelBorder`-like), cream text, gold edge on hover, dimmed
   when disabled. Reset keeps a red-tinted edge and text as a warning. Options
   and close become square icon buttons in the same style (gear glyph / X
   glyph drawn as textures or text, not the game's red close button). Filter
   inputs (Min g, Search) keep the dark inset look but use the same edge.
3. **List rows: one counted value with its source.**
   - Line 1: name in quality color, `x<qty>`, right side the counted value
     (the row's `value`, best of vendor / AH / DE) followed by a framed source
     tag: `Vendor`, `AH` or `DE`, each with its own color (style A of the
     mockups). A cached AH price keeps its age tag.
   - Line 2: the TSM sale line as today (two colors stay). Rows without it keep
     the current height (no layout jump).
   - The other values (vendor, AH, DE, per unit and total) move into the row
     tooltip.
   - "Unpriced" keeps today's rule (no AH price, not bound; also what History
     saves). Such rows show their counted value as usual (vendor / DE) plus a
     small `?` mark after the tag; a row with no value at all shows `?` in the
     value spot. The footer note reads "2 unpriced (marked ?)" on the tabs that
     draw item rows. *(Builder's call.)*
   - A bound item shows its counted value with its tag (usually `Vendor`); the
     word `bound` only appears when it has no value at all, and it is never
     marked `?`. *(Builder's call.)*
4. **Coin colors everywhere** amounts are shown (list, footer, Top finds,
   compact, Daily farm): one formatter, `Money.formatColored`.
5. **Footer**: the right column is titled `per hour` once; its amounts drop the
   `/h` suffix.
6. **Daily farm strip**: rate first, place second
   (`★ ~4g/h  Witherbark Village (Arathi Highlands)`) so a narrow window cuts
   the place, not the rate. The icon becomes a gold star in the addon's style
   (a texture or glyph that cannot read as an error mark).
7. **Type sizes**: "Top finds" title drops to the size of the other section
   titles (the header font), below the window title.
8. **Customization** (new options, `Options.define`, category "display"):
   - `showTopFinds` (default on) — full mode
   - `showMarket` stays as it is (TSM sale line)
   - `dailyFarm` stays (strip in full, line in compact)
   - `showFooterGold` (default on) — the Raw gold row of the footer (Total
     follows `includeGold` as today)
   - `compactDrops` (slider 0–4, default 4) — how many last drops compact
     shows; 0 hides the block
   Existing look options stay (opacity, brightness, scale, font, sizes).

## Non-goals

- No timeframe picker for History / Zones (proposed as its own follow-up).
- No change to what is counted or how prices are looked up.
- No change to tabs, History, Zones, Bags, Bank content beyond the shared row
  and button style.
- No separate compact frame.

## Anti-goals

- A compact mode that still needs reading: the glance numbers must be the
  largest text in it.
- Losing anything the full ledger offers today without a way to get it (all
  values stay reachable through the tooltip).
- Breaking position, scale, lock, opacity, combat hide, the minimap toggle,
  `/lp show|hide` in either mode.

## Constraints

- WoW Forever (retail engine, Interface 16001), Lua 5.1; pure code outside
  `UI/`, `UI/` touches globals only inside functions; tests can't see the real
  UI, so pure helpers carry the logic (texts, layouts, which parts show) and
  the client look goes on the README in-client checklist.
- Look lives in `Theme.lua`; options only through `Options.define`; texts
  through `ns.L` with German.
- The addon must work without `Libs/`.

## Approaches

1. **One frame with two layouts (picked).** `Window` gets a mode; compact
   hides the filter row, Daily farm row, tabs / sub-tabs, list, footer and Top
   finds and shows a new `UI/Compact.lua` part. Position, scale, lock,
   opacity, combat hide and the toggles keep working untouched. Cost: size
   rules and parts must know the mode.
2. A second compact frame swapped in place. Isolated code, but two frames to
   keep in sync (position, scale, lock, combat hide, toggles, saved state) and
   every future window option twice. Rejected.
3. Compact as a tab. Tabs live inside the full layout; the user wants a mode
   switched from the title. Rejected. (A UI-layer rewrite was also dropped:
   too much risk for something only checkable in the client.)

## Decided how

- **Mode** state in `Ledger` (`Ledger.mode`), saved as `db.mode`; switch via
  `Ledger.setMode(mode)` (redraws once) and the title double-click; also a
  slash command `/lp compact` (toggle) registered with `ns.Slash.define`.
- **Window**: `Window.applyMode(mode)` shows / hides the header rows 2–4 and
  the list, footer and top box, and applies that mode's saved size and its
  own minimum size (compact minimum from `Theme.sizes`, e.g. 240 × 150).
- **Last drops**: the session keeps the last 4 loot events
  (`session.recent = { { key, qty, at }, ... }`, newest first, capped), set in
  `Core.recordLoot` after a counted loot; not copied into History; reset with
  the session. Each entry shows what that one drop was worth (its own `qty`,
  current prices), so two drops of one item are two lines with their own
  amounts. *(Builder's call.)*
- **Compact view**: a pure `View.buildCompact(session, opts)` returns
  `{ perHour, total, running, drops = { row... } }` (drop rows built like
  `makeRow`, from each event's own qty), ignoring `opts.filter`, with
  `total` / `perHour` = items best value + raw gold when `includeGold`, so the
  compact part only draws.
- **Buttons**: `Widgets.button` becomes the bronze button (own textures /
  backdrop instead of `UIPanelButtonTemplate`); `Widgets.iconButton(parent,
  glyph, size)` for gear / close; `Widgets.button(..., { warn = true })` for
  Reset. Colors and sizes in `Theme`.
- **Rows**: `Rows.rowText` returns `value`, `source` ("vendor" / "ah" / "de" /
  nil), `unpriced`; the two-label right block becomes one amount plus a tag.
  Tooltip lines from a pure `Rows.tooltipLines(row)`.
- **README**: feature text (modes, row values, options), layout table
  (`UI/Compact.lua`), in-client checklist (button look, tags, compact switch,
  sizes per mode, double-click not clashing with drag).

## Left to the builder

- Exact textures and pixel sizes of the bronze buttons and icon glyphs
  (Theme tokens).
- Tag colors per source (Theme tokens; mockup: Vendor tan, AH light blue, DE
  violet).
- How History / Zones place rows (no single source) show their value: plain
  amount without a tag.
