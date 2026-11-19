# LootLedger scan: own auction house prices (design)

First of two pieces. The second, a Trade section (player trades, auction
sales, posted / cancelled / expired auctions and statistics from them, plus
an "Own sales" price source), gets its own design after this one is built.

## Why

LootLedger values loot at the best of vendor, AH and destroy prices, but AH
prices only come from TSM or Auctionator. A player with neither sees vendor
prices only, so Session, Bags, Zones, the Daily pick and every total
undervalue most loot. The Trade section is aimed at exactly that player, and
its "how do my prices compare" statistics also need a market price. So
LootLedger first learns to read the auction house itself.

The original design (2026-11-12) listed "no built-in AH scanner" as a
non-goal; the player has changed that.

## Goals

1. **Full scan.** While the auction house is open and neither TSM nor
   Auctionator is loaded, the player can read the whole auction house in one
   go: a **LootLedger scan** button on the auction house window, `/ll scan`
   and a key binding. The game allows one full read every 15 minutes; the
   button shows the time left, then "Ready".
2. **No freeze.** The read results are processed a chunk per frame, so the
   game stays responsive. The button shows progress ("Reading 42%"). Closing
   the auction house mid-scan stops cleanly and keeps what was processed.
3. **Passive recording.** With the scanner available, the auction listings the
   player opens anyway (an item's or a commodity's search results) are
   recorded too, keeping shopped-for items fresh between full scans.
4. **Prices.** Per item variant (`LootParse.itemKey`) and per day: the
   **market value** (average unit price of the cheapest 15% of the listed
   units) and the **lowest price** (cheapest unit buyout). The price the addon
   uses is a recent average of those days (see Decided: averaging).
5. **Option: Scan price** (`scanPrice`, Prices category): "Market value"
   (default) or "Lowest price". The player picks which of the two the addon
   uses everywhere.
6. **Price source.** A new source **LootLedger scan** (key `scan`), asked
   after TSM and Auctionator: Auto becomes "Auto (TSM, then Auctionator, then
   LootLedger scan)", and the AH price source dropdown can pick it alone. Its
   prices count everywhere AH prices count today (rows, totals, Top finds,
   Zones, Daily pick, minimum filter, drop alert, AH cut, Auction from).
   Tooltips name the source "LootLedger scan" with its age, like the cache.
7. **Reminder** (option `scanReminder`, default on): opening the auction house
   with the scanner available and no full scan in the last 24 hours (or none
   ever) prints one chat line suggesting `/ll scan` or the button.
8. **Chat lines**: scan done ("LootLedger: scan done, 18 342 items priced
   (4.1 s)."), scan stopped (auction house closed), scan refused (still on
   the game's wait; the time left).
9. **No price addon hint** (`Core.priceAddonHint`): its text also points to
   the scan, and it is not shown while scan prices exist for this realm.

## Non-goals

- Scanning while TSM or Auctionator is loaded (the button and passive
  recording are off; they already do this better). Prices saved by earlier
  scans stay usable if the player picks LootLedger scan in the dropdown.
- Automatic full scans (a full read can stall the game for a moment; the
  player decides when).
- Targeted per-item searches of the player's items (throttled, slow).
- Battle pets (all share one cage item ID), bids without buyout, sale rate /
  sold per day (no market data source), destroy values.
- Browse results (the list of items before opening one): their minimum price
  mixes every variant of an item, so they are not recorded.
- Any statistics or UI in the ledger window beyond the source name and age:
  that is the Trade section.

## Anti-goals

- A saved file so large that login or `/reload` slows down noticeably.
- A scan that freezes the game for seconds or breaks the auction house UI.
- Overwriting a good price with "no data": an item missing from a later scan
  keeps its earlier values.
- One underpriced or overpriced auction setting an item's value everywhere.

## Constraints

- Lua 5.1; pure logic outside `UI/` with client calls injected (tests run it).
- The client APIs below are unconfirmed on this client: each gets an
  `UNVERIFIED (check in client)` comment and a CHECKLIST line.
- Saved size: budget about 1.5 MB of saved text for 30 000 item variants per
  realm; the stored form per item is a short string, not a nested table.
- Every option: default in `DB.defaults.settings`, label 24 characters at
  most, tooltip, German text.

## Approaches

Considered:

- **A. Full scan button** (the game's full auction house read, once per 15
  minutes): every item priced in one go; needs chunked processing.
- **B. Targeted searches** of the items the player has (bags, bank, session,
  History): exact current prices, but the game throttles searches (minutes
  for a few hundred items) and new loot has no price.
- **C. Passive only**: record the listings the player opens. No effort,
  spotty coverage.

**Picked: A plus C.** A gives every item a price at once; C costs little and
keeps items the player shops for fresh. B is too slow and blind to new items.

## Decided

**Client calls** (all `UNVERIFIED (check in client)`):

- Full read: `C_AuctionHouse.ReplicateItems()`, then on
  `REPLICATE_ITEM_LIST_UPDATE`: `C_AuctionHouse.GetNumReplicateItems()`,
  `GetReplicateItemInfo(i)` (count = 3rd return, buyout = 10th, itemID = 17th,
  hasAllInfo = 18th; indices start at 0) and `GetReplicateItemLink(i)`. Unit
  price = buyout / count. Entries without buyout are skipped.
- Passive: `COMMODITY_SEARCH_RESULTS_UPDATED(itemID)` with
  `C_AuctionHouse.HasFullCommoditySearchResults(itemID)`,
  `GetNumCommoditySearchResults` and `GetCommoditySearchResultInfo(itemID, i)`
  (`unitPrice`, `quantity`); `ITEM_SEARCH_RESULTS_UPDATED(itemKey)` with
  `HasFullItemSearchResults`, `GetNumItemSearchResults` and
  `GetItemSearchResultInfo(itemKey, i)` (`buyoutAmount`, `quantity`,
  `itemLink`). Only full result sets are recorded (a partial list would make
  the market value wrong).
- Auction house open / closed: the existing `AUCTION_HOUSE_SHOW` /
  `AUCTION_HOUSE_CLOSED` handlers in Core (also used for "purchases are not
  loot") gain the scanner's calls.
- The 15-minute wait is tracked by the addon (time of the last
  `ReplicateItems` call, saved per character so a `/reload` keeps it). When no
  `REPLICATE_ITEM_LIST_UPDATE` arrives within 60 s, the scan is reported as
  refused by the game and the wait is not restarted.

**Market value** of one listing set (one item key): sort units by unit price,
take the cheapest 15% of the units (at least one), average their unit price,
round down to copper. Lowest = the cheapest unit price. Computed per item key
over all its listings of the scan.

**Averaging** (the player's "recent average"; the form is the builder's
call below):

- One value pair (market, lowest) per item per day (the day number from
  `time()`, so the same day everywhere). A later full scan or passive listing
  on the same day replaces that day's values for the items it saw.
- The price used is a time-weighted average of the daily values where a
  day's weight halves every 5 days, so recent days count most and one odd day
  is diluted. Kept as a running average (`prev`, `prevDay`) plus today's
  values, not a list of 14 days: that is what keeps the saved size inside the
  budget. Same-day replacement works because today's values are stored apart
  from the average of the days before.
- An item whose newest value is older than 14 days is not answered by the
  source (and dropped from the saved data at login).

**Storage**: `LootLedgerDB.scan = { [realmKey] = { lastFull = time, items = {
[itemKey] = "packed" } } }` with `realmKey` = the price cache key
(`Core.cacheKey`) plus the realm name (non-commodity listings are per realm).
The packed string holds day, today's market and lowest, the running averages
and their day, as base-36 integers joined by a separator. `Scan.pack` /
`Scan.unpack` are the only code that knows the format. The last full read time
for the 15-minute wait lives in `LootLedgerCharDB.scanAt`.

**Lookup**: the source answers for the exact item key, then for the plain item
ID's entry (a plain item listed on the AH), else nil. The chosen kind comes
from `scanPrice`, read live. Like every live source, its answers also land in
the existing price cache (`db.cache`, source name "LootLedger scan"); that
needs no special case.

**Files**:

| File | Job |
| --- | --- |
| `Scan.lua` (after `Prices.lua`) | pure: market value / lowest of a listing set, daily merge and averaging, pack / unpack, prune, lookup, the chunked reader (client calls and the frame timer injected), the 15-minute wait |
| `Sources/Scan.lua` (after `Sources/Auctionator.lua`) | registers the `scan` source over `ns.db.scan` and `scanPrice`; no `present` (it is LootLedger itself) |
| `UI/ScanButton.lua` | the button on the auction house window (made on first `AUCTION_HOUSE_SHOW`, only while the scanner is available), its progress / wait text |
| `Core.lua` | events, availability (`Core.scanAvailable`: neither TSM nor Auctionator present), the reminder, the login prune |
| `Slash.lua`, `Bindings.xml` | `/ll scan`, binding `LOOTLEDGER_SCAN` |

**Texts**: every new text through `ns.L` with German in `Locales/deDE.lua`;
option labels "Scan price" and "Scan reminder".

**Docs**: README (how to scan, the two options, the price order),
DEVELOPMENT (files, how the scan works, saved state, events), CHECKLIST (each
unverified call, the button position, a scan's duration and freeze, the saved
size after a full scan).

## Builder's calls

- Chunk size / time budget per frame (aim: no frame over ~10 ms).
- Entries whose link is not loaded yet (`hasAllInfo` false): wait for item
  data with a cap or fall back to the item ID key; whichever keeps the scan
  short and the variants right in most cases.
- The exact packed format and separator, the half-life constant's name.
- Where exactly on the auction house window the button sits (clear of the
  game's own buttons), its look from `Theme.lua`.
- Test split: pure tests for `Scan.lua`, wiring tests with a fake
  `C_AuctionHouse` for the events, the button's availability and `/ll scan`.
