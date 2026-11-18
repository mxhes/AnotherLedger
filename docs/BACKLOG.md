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

### Top finds only when it adds something (S)
Sorted by Value, Top finds shows the same three items the list starts with and
takes about three rows. Hide it while sorting by Value, or let it collapse.
- Needs: `View.build` / `Summary.topBoxHeight` know the sort; the Top finds
  option stays as the off switch.

### Better drop alert (S)
Show the drop alert on screen too (not only in chat), and add an "any epic"
trigger next to the gold amount.
- Needs: a raid-warning style frame or `UIErrorsFrame:AddMessage` for the
  text; a quality option next to Drop alert (gold) in `Options.lua`.

## History

### Row icons from the best item (S)
Every History session and Zones row has the same icon. Use the session's or
place's most valuable item instead, so a good run stands out.
- Needs: the best item per session / place in `sessionRow` and `placeRow`
  (`View.lua`), its icon via `itemInfo`.

## Selling and items

### Account-wide inventory (L)
Bags and bank of all characters, with a value per character and an account
net worth; the warband bank (not scanned yet, `Inventory.bankIDs`) belongs
here too.
- Needs: bag scans saved per character (like the bank scan), a new tab or
  sub-tab, and the warband bank container IDs (UNVERIFIED on Forever).

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
From the second review: separate sorts for History Sessions and Zones, the
History footer, header counts, a movable options window, the session summary
in chat and "Used by" for profiles.
From the third review: Zones header count, unpriced items in the footer
tooltip, the Daily pick starred in Zones, short difficulty names, Reset
profile, AH cut, Auction from, Destroy values, the TSM price dropdown,
Min. session length, Pause in cities, Gold on hand / Net worth / Sell split
/ free slots in Bags, day headings in History, Daily farm: my level, the
window's Open on first loot / Open in instances / Hide in cities, and
History > Mobs.
