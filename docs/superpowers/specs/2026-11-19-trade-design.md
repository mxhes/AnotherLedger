# Trade section (design)

## Why

Players without TSM have no way to see what they sell, what sells best and
whether they sell too cheap. LootLedger already values what they loot; the
Trade section closes the loop by recording what they sell (auction house and
player trades) and comparing it with the market. Their own sale prices then
also become a price source for the whole addon, after the LootLedger scan.

## Goals

- Record auction house events: posted, cancelled, expired, sold (with the real
  price, the auction house cut, the amount and the buyer).
- Record finished player trades: date, character, partner, items and gold
  each way.
- A trade where only items went out and only gold came in is a **sale**; only
  gold out and items in is a **purchase**. Every other trade (gifts, alt
  transfers, swaps) is logged but kept out of the statistics. Purchases are
  logged and kept out of the sales statistics.
- Statistics per item: sold count, gold earned, sell rate, average price
  against the market **on the day of the sale**.
- New price source **Own sales**: LootLedger's own data comes as the scan
  first, own sales only when the scan has no price. The full order stays
  TSM, Auctionator, LootLedger scan, Own sales.

## Non-goals

- Buying from the auction house (purchases there), bids placed, COD mail
  between players. They can be added later (backlog).
- Per-character statistics: one record per realm, shared by all characters
  (each entry still names its character).
- Profit per item (cost of materials, crafting).

## Anti-goals

- A sale counted twice because the same mail is opened again, read by two
  characters, or because the chat line and the mail both report it.
- Trade or mail items leaking into the loot (already excluded while those
  windows are open; must stay so).
- A noticeable stall when opening a full mailbox.
- A sale price guessed from the posted price when the mail gives the real one.

## Constraints

- Lua 5.1, pure code outside `UI/` with injected client calls, texts through
  `ns.L` with German in `Locales/deDE.lua`, options with a default, a label of
  at most 24 characters and a tooltip (see `CLAUDE.md`).
- Every client API not yet confirmed gets `UNVERIFIED (check in client)` and
  a line in `docs/CHECKLIST.md`.
- Money in copper; items keyed by `LootParse.itemKey(link)`.

## Approaches

- **A. Read the mail, watch the auction house (picked).** Posting and
  cancelling from the auction house; sold and expired from the mailbox
  (the sale mail carries the real price, cut, amount and buyer); the chat
  line "A buyer has been found for your auction of X" marks a sale early;
  trades read from the trade window before both accept and saved when the
  game reports the trade complete. Exact prices; sales show after a mailbox
  visit.
- B. Chat lines only: instant, but the price is guessed from the posting
  (wrong for partial stack sales and reposts), expired still needs mail.
- C. Compare the owned auctions list on each auction house visit: no mail
  needed, but nothing updates away from the auction house and expired cannot
  be told from sold.

Picked A because exact prices are what makes "how do my prices compare"
worth having, and players visit the mailbox after selling anyway.

## Decided

### Recording

- **Posted:** each auction or commodity posted (item key, amount, unit price,
  duration, time). Posting a stack splits into one entry per post call.
- **Cancelled:** the cancelled auction (item key, amount left) from the
  auction house; the returned mail is not counted again.
- **Expired:** from the "Auction expired" mail (item from its attachment).
- **Sold:** from the sale mail's invoice (item name, buyer, sale price, cut,
  amount). The item key comes from the matching posted entry (same item name,
  newest open post); without one, from the item ID the client gives for the
  name, else the entry keeps only the name and stays out of the price source.
  - **Earned** = sale price minus the cut (the deposit is not counted).
  - The **market price on the day of the sale** is taken when the "buyer
    found" chat line comes (the player is online when it sells), else when
    the mail is read. It is the addon's value for the item at that moment
    from the usual order without Own sales; none -> the sale is kept but
    marked "not compared" and left out of the comparison.
- **Player trades:** at the last accept, the items and gold of both sides and
  the partner's name are taken; the trade is saved only when the game
  reports it complete (a cancelled trade saves nothing).
  - *Builder's call:* a trade sale of several different items for one sum
    splits the gold by each item's market value (equally per unit when one
    has none) for Sold and Gold, but only a trade of a single item kind
    feeds the Own sales price and the market comparison, since the split is
    an estimate. The market price is taken at the trade.
- *Builder's call:* a sale mail is recorded from the temporary invoice (sent
  before the money arrives) or the final one, whichever is read first; the
  two are joined as one sale.
- Each mail is recorded once: a key from what does not change while it sits
  in the inbox (subject, sender, money, invoice fields and its expiry time
  rounded to the minute) is remembered until the mail would have expired.
  The early chat-line mark and the later mail are joined into one sale.

### Storage

- Account-wide per realm, under the same realm key as the scan
  (`Scan.realmKey`). Per realm: a **log** of entries (packed like the scan),
  **totals** per item key (posted, sold, expired, cancelled amounts, gold
  earned, sales compared and their market sum), the open posts and the seen
  mail keys.
- New option **Trade log kept** (days, default 90): log entries older than
  that are dropped at login; totals stay.

### Statistics (the Trade tab)

- A **Trade** tab after History with two sub-tabs.
- **Items**: one row per item sold: item, Sold (amount, auction house and
  trade sales together), Gold (earned, after the cut), Rate (sold out of
  sold + expired + cancelled, in units, auction house only), vs market
  (average sale price per unit against the average market price of the
  compared sales, as +/- percent). Sorted by gold by default; every column
  sorts. A time filter: 7 days, 30 days, All (7 and 30 from the log, All from
  the totals). The footer: sold, expired and cancelled counts and the gold
  earned. Hovering a row lists its sales (date, amount, price, market, buyer
  or partner).
- **Log**: every entry newest first: date, what (Posted, Cancelled, Expired,
  Sold, Trade sale, Trade purchase, Trade), item and amount, gold, the other
  player, the character.

### Own sales price source

- Key `sales`, label `Own sales`, registered after the LootLedger scan.
- Price per unit = the amount-weighted average of the gross sale price per
  unit (before the cut, so it matches the other sources, which are listing
  prices) of the item key's sales in the log; age = time since the newest of
  them. Items with variants stay apart (item keys).
- *Builder's call:* it follows the price source option the same way the
  scan does (it is only used where the scan would be).

## Left to the builder

- Exact client calls (mail invoice, the auction house post / cancel calls or
  events, the trade window and the "trade complete" message) and how to hook
  posting; each one UNVERIFIED until checked in the client.
- The packed format, the seen-mail key details, and the hover tooltip layout
  (through `ns.Tooltip`).
- Sort and column widths in `Theme.sizes`; German texts.
