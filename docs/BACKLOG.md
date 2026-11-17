# Backlog

Feature ideas from the November 2026 review that are not built yet, for later.
Sizes: S = under an hour, M = a few hours, L = a bigger piece of work.

## Farming and sessions

### Compare with the last session or the place's average (M)
The compact rate turns green or red against your average gold per hour for the
current zone (from the History Zones data), so you see at a glance whether this
run beats your usual.
- Needs: the current zone's average from `View.buildZones` / `aggregateZones`
  (value / time of that zone), passed into `View.buildCompact`.
- Open: average of the zone or of the subzone; how many minutes before the
  comparison means something (like the Daily farm's minimum time).

## Selling and items

### Vendor-trash total and "Sell junk" (S/M)
The Bags tab shows the total of all grey items ("Grey items: 4g 20s"). At a
merchant, one button sells all of them.
- Needs: the grey total from the Bags view rows (quality 0); a button that
  shows only while a merchant window is open (`MERCHANT_SHOW` / `_CLOSED`
  are already tracked in `Core.lua`).
- Client: `C_Container.UseContainerItem(bag, slot)` at a merchant sells an
  item. It is protected against bulk use on some clients, so sell in small
  batches with a short delay. UNVERIFIED (check in client) on Forever.

## Release

### CurseForge (S)
Publish the addon on CurseForge, so the CI packager uploads every tagged
release.
- Needs: the CurseForge project, `## X-Curse-Project-ID` in
  `LootLedger/LootLedger.toc`, and the `CF_API_KEY` CI variable in GitLab.

## Already built (from the same review)

Session goal, session notes, ignore list, price per unit, compact breakdown
tooltip, keybindings, scroll memory per tab, quality presets, clear-filter
hint, account-wide Zones, undo for deleted sessions, session and Zones CSV
export. Later: merging History sessions (with undo), session per zone, the
gold per hour graph, the keep list (kept / sellable in Bags and Bank).
