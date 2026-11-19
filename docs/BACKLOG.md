# Backlog

Feature ideas that are not built yet, for later.
Sizes: S = under an hour, M = a few hours, L = a bigger piece of work.

## Open ideas

- Auction house purchases (buying, bids placed) in the Trade Log and
  statistics. M
- COD mail between players as sales. M
- Profit per item (material cost of crafted items against the sale price). L
- Destroy values without TSM and Auctionator: own disenchant / mill /
  prospect tables priced with AnotherLedger scan prices. L

From the fifth review (2026-11-19, screenshots of Bags and compact):

- "Unpriced" reads wrong on a row that has a vendor value: call it "no AH
  price" (`N without AH price (marked ?)`), and let the footer tooltip say
  why: no TSM / Auctionator and no scan yet ("scan at the auction house:
  `/al scan`"), or the price addon has no price for them. S
- Option to show the source tag only when the best value is not Vendor
  (every row in a typical Bags list says `Vendor`). S
- Bags header: color the free slots orange / red when few are left
  (`2 free`). S
- Net worth counts bags and gold only: add the last bank scan (and maybe
  the alts' bags and banks), or rename it "Bags + gold". S-M
- Trade > Log: show trade purchases with a minus sign (gold paid out). S
- Compact: optional item icons in Last drops; a dimmer color for the
  quantity (`x47`) so names stand out. Decide whether compact drops show
  `?` like the list does. S
- Sort button: right-click steps back to the previous sort, or reverses the
  order (reversing needs every view's sort to take a direction). S / M
- At a vendor: a "Sell vendor items" button on the Bags tab that sells the
  rows whose best value is Vendor, skipping kept and ignored items, after a
  confirmation with count and total (buyback holds only the last 12). M

## Already built

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
From the fourth review: Hide worthless, gold per hour on History session
rows, the Mobs hover tooltip, the compact 15 minute rate and goal bar, the
chat hint without a price addon, Reset: ask for a note, `/al export mobs`
and unpriced items first from the footer note. After it: Mobs counts with
the clock stopped and with fast loot addons, and drop chances show in the
Mobs tooltips and in the game's item tooltips.
Then: AnotherLedger scan (own auction house prices without TSM or Auctionator:
full scan, passive recording, Scan price, Scan reminder), gilded two-tone
buttons, and the Trade tab (auction and trade recording, Items and Log, Own
sales price source, Trade log kept).
