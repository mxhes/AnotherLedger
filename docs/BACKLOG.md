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

### Session per zone (M)
An option like "Session per instance", but for a zone change: every new zone
starts a new session, so History rows stay clean when you hop between farm spots.
- Needs: a zone-change check next to `checkInstance` in `Core.lua`, with a
  grace time so a short detour (flight path, a cave entrance) does not split
  the session.

### Gold per hour over time (L)
A small graph of the rate over the session, to see when a spot dries up.
- Needs: a rate sample every minute or so in the session (not in History, or
  thinned out there), and a graph drawn with plain textures (bars), in the
  compact window or a tooltip.

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

### Mark items to keep vs sell (M)
Splits the Bags total into "sellable" and "kept" (tools, consumables you use,
gear sets), so the total answers "what can I actually sell?".
- Needs: a keep list like the ignore list (account-wide, by item ID), a row
  menu entry, and a second total in the Bags footer.

## Already built (from the same review)

Session goal, session notes, ignore list, price per unit, compact breakdown
tooltip, keybindings, scroll memory per tab, quality presets, clear-filter
hint, account-wide Zones, undo for deleted sessions, session and Zones CSV
export. Later: merging History sessions (with undo).
