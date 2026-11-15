# Daily farm — design

## Intent

When the player logs in, the Ledger window tells them where their time pays
best today: the zone / subzone they have farmed with the highest gold per hour,
valued with the current AH prices. It is a "where do I go now" aid, not an
analysis view (that is History → Zones).

## Goals

- A strip at the top of the Ledger window, above the tabs, on every tab:
  `★ Daily farm: <Subzone> (<Zone>)  ~1,240g/h ›`
- Click opens History → Zones with that zone and subzone expanded.
- Tooltip: zone, subzone, recorded time, value, gold per hour, and the
  runner-ups (2nd and 3rd place) with their gold per hour.
- `⚠ slow selling` note when most of the pick's AH value comes from slow
  sellers (TSM only); its tooltip names those items.

## Non-goals / anti-goals

- No chat message at login (user picked the strip only).
- No sale-rate weighting of the ranking: the value is the Zones value
  (best of vendor / AH / disenchant, plus raw gold).
- No new saved data; nothing is frozen per day.
- Anti-goal: a pick that jumps while farming, or one won by a few lucky
  minutes.

## Constraints

- History is per character (`LootPriceCharDB.history`); each character gets
  its own pick. No eligible place → the strip is hidden.
- Pure computation outside `UI/`, tested with `h.load`; Lua 5.1.
- Texts via `ns.L` with German in `Locales/deDE.lua`; look in `Theme.lua`.

## Approaches

1. **Recomputed on every redraw from saved History only (picked).** A pure
   function next to `View.buildZones` reuses its aggregation and pricing.
   The running session is excluded, so the pick only moves when prices
   change (AH scan, TSM data update). Always current prices, no saved state.
2. Frozen once per day, saved in chardb with the date. Rejected: with
   Auctionator the first login of the day usually precedes the scan, so the
   day would be frozen on yesterday's prices; avoiding that needs a
   "prices are ready" rule and extra state.

## How (decided)

- `View.dailyFarm(entries, opts)` (pure): aggregates History entries with the
  existing `aggregateZones` (quest items, `Unknown place` and `No time
  recorded` excluded), values each subzone like `buildZones` (filters from
  the filter bar ignored), keeps subzones with time >= the minimum, ranks by
  gold per hour. Returns `{ best, runnersUp = {2nd, 3rd}, slow = { items } or nil }`
  or nil.
- Slow selling: using the existing market levels (`View.marketLevels`,
  options `saleRateGood` / `saleRateOk`), a pick is slow when more than half
  of its AH value comes from items whose sale rate is in the bad level.
  No market data → never slow.
- New ledger part `UI/DailyFarm.lua` registered with `ns.UI.Ledger.register`;
  window layout shifts the tabs down while the strip is shown.
- Options (`Options.define`, category of the window / History section):
  `dailyFarm` checkbox (default on) and `dailyFarmMinMinutes` slider
  (default 20, 5–120).
- README: feature text, options, layout table, in-client checklist.
  Wiring test: strip shows the top place from a booted addon with History.

## Left to the builder

- Exact strip height, colors and icon (Theme tokens).
- Whether the strip computes in `Update` only (it should not need `Tick`).
- Tie-break order (suggested: more recorded time wins).
