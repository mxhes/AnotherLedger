# AnotherLedger checklist

What still has to be confirmed in the Forever client, and the release steps.

Code that relies on an unconfirmed client API carries an
`UNVERIFIED (check in client)` comment; add a line here whenever you add one,
and remove both once it is confirmed.

## Open checks

- Rename to AnotherLedger: with the old `LootLedger` folder removed and the
  new `AnotherLedger` folder installed (restart the client), the addon list
  shows AnotherLedger with the AL logo, `/al` and `/anotherledger` toggle the
  window, the key bindings sit under the AnotherLedger header, and settings
  and a session survive a `/reload` (new `AnotherLedger.lua` in
  SavedVariables).

- Item tooltips (`UI/ItemTooltip.lua`, UNVERIFIED):
  `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn)`
  runs for bag, chat link and loot window tooltips, and `tooltip:GetItem()`
  gives the link there. Check: hover an item a mob dropped since drop
  chances exist; the tooltip ends with `AnotherLedger drop chance` and the mobs.

- AnotherLedger scan (`Core.lua` scan section, `UI/ScanButton.lua`,
  UNVERIFIED; run with TSM and Auctionator disabled):
  - `C_AuctionHouse.ReplicateItems()` is answered by
    `REPLICATE_ITEM_LIST_UPDATE`, once per 15 minutes; a second call within
    the wait is ignored by the game (the addon's own wait matches it).
  - `GetReplicateItemInfo(i)` is 0-based, with count 3rd, buyout 10th and
    itemID 17th; `GetReplicateItemLink(i)` gives links with bonus IDs, and
    how many are nil on a first scan after login (those are keyed by item ID,
    and dropped for items whose variants the same scan saw).
  - A full scan: how long it takes, whether the game stalls during
    `ReplicateItems` or the reading, and the size of `AnotherLedger.lua` in
    SavedVariables afterwards (budget about 1.5 MB per realm).
  - Passive: opening a trade good fires `COMMODITY_SEARCH_RESULTS_UPDATED`
    with `HasFullCommoditySearchResults` and 1-based
    `GetCommoditySearchResultInfo` (`unitPrice`, `quantity`); opening gear
    fires `ITEM_SEARCH_RESULTS_UPDATED` with `HasFullItemSearchResults` and
    `GetItemSearchResultInfo` (`buyoutAmount`, `quantity`, `itemLink`).
  - The scan button counts the game's wait down after a scan (it shows
    below the auction house window: confirmed).
  - The reminder line shows on the first auction house visit of a login, and
    the login hint mentions `/al scan` and stays quiet once prices exist.

- Trade section (`Core.lua` trade section, UNVERIFIED):
  - Posting through the auction house UI calls `C_AuctionHouse.PostItem`
    (itemLocation, duration, quantity, bid, buyout) or `PostCommodity`
    (itemLocation, duration, quantity, unitPrice), and cancelling calls
    `CancelAuction(auctionID)` while the owned auction is still listed
    (`GetOwnedAuctionInfo` with `auctionID`, `itemLink`, `quantity`). Check:
    post and cancel, then `/dump AnotherLedgerDB.trade` shows a post and a cancel.
  - The chat line `ERR_AUCTION_SOLD_S` comes as `CHAT_MSG_SYSTEM` with the
    item name.
  - Mail: `GetInboxHeaderInfo` (sender 3rd, subject 4th, money 5th, daysLeft
    7th), `GetInboxInvoiceInfo` (invoiceType `seller` /
    `seller_temp_invoice`, itemName, buyer, bid, buyout, deposit, consignment,
    count 11th); expired and cancelled mails match
    `AUCTION_EXPIRED_MAIL_SUBJECT` / `AUCTION_REMOVED_MAIL_SUBJECT` and carry
    the item as attachment 1. A sale is recorded once, also after reopening
    the mailbox or on another character.
  - Trades: `TRADE_ACCEPT_UPDATE` on accept, slots 1-6 through
    `GetTradePlayerItemLink` / `Info` (count 3rd) and the Target versions,
    `GetPlayerTradeMoney` / `GetTargetTradeMoney`, `UnitName("NPC")`; the
    `ERR_TRADE_COMPLETE` message as `UI_INFO_MESSAGE` before `TRADE_CLOSED`
    or within a second after it. Check: sell an item to another player for
    gold; the Trade log shows a trade sale.

To look at in the client after the fourth review (2026-11-18), only run
against the test fakes so far:

- Compact: the goal bar over the divider (thickness, color, follows a
  resize) and `15 min: ...` right of the drops title (a long title like
  `Paused: click the clock to start.` is cut before it).
- Footer: clicking `N unpriced (marked ?)` sorts those first, its hover
  hint shows, and the table's own hover still works elsewhere.
- Reset with **Reset: ask for a note** on: the note box opens after the
  "large session" confirmation too.
- Session per zone no longer splits while resting in a city (`IsResting`).
- Login without TSM and Auctionator: the chat hint shows once.

## Release steps

1. `main` is green: `lua tests/run.lua` passes locally and the `test` jobs
   (Lua 5.1 and 5.4) pass in GitLab CI.
2. The open checks above are done in the client, or knowingly left for a
   later release.
3. `## Interface:` in `AnotherLedger/AnotherLedger.toc` matches the client
   (`/dump select(4, GetBuildInfo())`, 16001 today).
4. Run the manual `package-dry-run` job on `main`: its log lists one
   `AnotherLedger/` folder with the `.toc`, the code and `Libs/` (LibStub,
   CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0), and no `docs/`,
   `tests/` or `CLAUDE.md`.
5. Add the version's entry on top of `CHANGELOG.md` (merged into `main`):
   the packager sends it to CurseForge as the release notes.
6. Tag `main` with the version as a maintainer (`git tag -a v0.4.2 -m ...`,
   then `git push origin v0.4.2`). `v*` tags are protected tags (maintainers
   only), which is what gives the tag pipeline the protected, masked CI/CD
   variable `CF_API_KEY` (the CurseForge API token). The `package` job builds
   the zip (the `.toc` version comes from the tag), uploads it to CurseForge
   (project 1817047, `## X-Curse-Project-ID` in the `.toc`) and keeps it in the
   job's artifacts for 30 days.
7. Check the `package` job log: `CurseForge ID: 1817047 [token set]` near the
   top and `Uploading ... Success!` before `Packaging complete.`; then the file
   on CurseForge shows the changelog and the game version (the packager maps
   `## Interface: 16001` to `1.60.1`). Without `[token set]` the upload is
   skipped silently. Retrying the job doesn't help: a pipeline keeps the
   protection it was created with, so start a new pipeline on the tag (CI/CD >
   Pipelines > Run pipeline, pick the tag).
