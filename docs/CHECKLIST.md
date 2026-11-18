# LootLedger checklist

What still has to be confirmed in the Forever client, and the release steps.

Code that relies on an unconfirmed client API carries an
`UNVERIFIED (check in client)` comment; add a line here whenever you add one,
and remove both once it is confirmed.

## Open checks

- Item tooltips (`UI/ItemTooltip.lua`, UNVERIFIED):
  `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn)`
  runs for bag, chat link and loot window tooltips, and `tooltip:GetItem()`
  gives the link there. Check: hover an item a mob dropped since drop
  chances exist; the tooltip ends with `LootLedger drop chance` and the mobs.

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
