# AnotherLedger

## v0.8.0

- Color picker: a Saturation slider under the game's picker.
- Pause while traveling (on by default): the clock rests on flight paths,
  boats and zeppelins; loot still counts.
- Item tooltips show the TSM sale info (sells well / okay, volume).

## v0.7.2

- Compact layout: hovering a drop shows its item tooltip.
- Fixes: auction sales emptied with Open All now show in Trade; the
  period and Mobs / Nodes switches mark the current choice and no longer
  cause Lua warnings.

## v0.7.1

- Skins: the Grain and Leather window backgrounds and the Background
  option are removed for now; every skin uses the flat background.

## v0.7.0

- Skins: Classic, Forge, Slate and Gilded change the window's border,
  background, buttons and lines (restart the game once after updating).
- History > Mobs: gathering nodes are tagged, and a button lists all, only
  mobs or only nodes.
- History sessions: right-click Rename gives a session's place your own
  name; Delete asks first.
- Session goal bar under the title on the Session tab, for the gold or the
  minutes goal.
- Trade footer shows Earned, Spent and Net; the Log adds up its entries.
- The options window is only as tall as the shown tab.
- Fixes: Totals weeks over two months, "Session per instance" only in
  dungeons and raids, profile "Used by", repeated drops merge in compact.

## v0.6.0

- Auction house purchases in the Trade tab: the Log shows what you
  bought, Items shows the gold left after costs.
- History > Totals: your sessions added up per week and month.
- Compact: optional item icons before the last drops; the quantity is
  dimmer so names stand out.
- Languages: English and German only (the others were dropped).

## v0.5.0

- Watch list: `/al watch` or right-click an item; a sound and a
  screen alert when you loot it.
- Price trend in item tooltips.
- Net worth counts your bank, and with more characters all of
  them (`/al worth`).
- French, Spanish, Italian, Portuguese and Russian.
- `/al stats` and the option Mob data kept.
- Buttons fit their text in every language; Zones, Mobs and
  the Daily farm are faster.
- Fixes: reason for "without AH price", Hide Vendor tags,
  colored free bag slots, minus sign on trade purchases.

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
