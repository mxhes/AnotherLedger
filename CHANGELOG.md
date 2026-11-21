# AnotherLedger

## v0.5.0

- Watch list: right-click an item and pick "Watch this item", or type
  `/al watch` with an item link, an item ID or part of a name
  (`/al watch Pattern:`). Looting it plays the raid warning sound and shows a
  line in the middle of the screen. `/al unwatch` and the option Watched items
  take entries off.
- Price trend in item tooltips: with TSM the market value against its 60 day
  average, else your own scan's newest day against the days before (option
  Price trend in tooltips).
- Net worth now counts your bank (as of its last visit) and ignores the
  filter. With more than one character, the Bags footer adds All characters,
  and `/al worth` lists every character's net worth.
- New languages: French, Spanish, Italian, Portuguese (Brazil) and Russian.
  Corrections to the wording are welcome.
- Buttons grow to fit their text in every language, and the window can't be
  made so narrow that the Trade tab is cut off.
- `/al stats` shows how much of the saved files each part takes; the option
  Mob data kept trims old mob data.
- The footer says "without AH price" and tells why in its tooltip; option
  Hide Vendor tags; free bag slots turn orange (5 or fewer) and red (2 or
  fewer); trade purchases show with a minus sign.
- History Zones, Mobs and the Daily farm are much faster with a long History.

## v0.4.3

- Looting in dungeons or in combat no longer raises a "secret string value"
  Lua error. Mobs whose name the game keeps hidden show as "NPC 12345" in
  History > Mobs until their name is seen.

## v0.4.2

- Price sources work in every TradeSkillMaster / Auctionator combination:
  AnotherLedger's own scan fills items the others lack, a chosen source that
  isn't loaded acts as Auto and says so, Auctionator gives price ages and
  disenchant values, and options for a missing addon are dimmed with the
  reason in their tooltip.
- Own color presets: "Save as preset..." in the Color preset dropdown saves
  your current colors under a name, and a button deletes one. Profile exports
  carry them. The Parchment preset is gone.
- Long dropdown texts stay inside their button (the AH price source shows
  "Auto").
- Soulbound items in Bags / Bank no longer show a "?" or count as unpriced,
  and worthless items aren't counted as unpriced either.
- History: an opened session stays open when a split saves one, row menus act
  on their own session, and merged sessions keep the newer one's price source.
- Looting two mobs quickly no longer counts the coins twice.
- The Trade tab's Items and Log follow the filter bar, and Log has its own
  sorts.
- Goal and alert boxes: empty or negative means Off.

## v0.4.1

First release on CurseForge.

- The addon is now called **AnotherLedger** (it was LootLedger before; that
  name was taken). Remove an old `LootLedger` folder from your AddOns. Settings
  and history from the old name don't carry over, and the slash command is now
  `/al` (or `/anotherledger`).
- New logo: a leather ledger with a gold coin, in the addon list, on the
  minimap button and in broker displays.
- Switching between the compact and the full window keeps the window in place.

What the addon does:

- The Session Ledger window values everything you loot at the best of vendor,
  auction house and disenchant price, with gold per hour and a compact layout.
- Bags, Bank, History (sessions, zones, mobs with drop chances) and Trade
  (your auctions, sale mails and trades) tabs.
- The Daily farm pick shows where your best farm is today.
- Auction prices from TradeSkillMaster, Auctionator, AnotherLedger's own
  auction house scan or your own sales.
- English and German.
