# Options window: fonts, text sizes, short labels with tooltips

Draft for review. Correct anything in the table below; German texts follow
the approved English.

## Decisions (from your answers)

- **Font list**: the fonts the game itself uses (read from its own font
  objects, so they exist), the well-known WoW fonts (Friz Quadrata, Arial
  Narrow, Skurri, Morpheus, ...) and every LibSharedMedia font other addons
  register. Cause of the empty list today: the check `SetFont(...) and true`
  drops every font, because on retail `SetFont` returns nothing even when it
  works; only an explicit `false` will count as "cannot load".
- **Text sizes**: dropdowns of px sizes (List text and Totals text 8 to 18 px,
  Section titles 10 to 24 px) instead of sliders.
- **Labels**: short; the details move into a tooltip shown when hovering the
  option (its label or its control).
- **Tooltip**: gold title (the option name), 1 to 3 lines on what it does and
  where you see it, then `Default: ...` in grey. Same tooltip style as the
  Daily / History ones.

## Labels and tooltips

**Window**

| Option | Short label | Tooltip | Default |
| --- | --- | --- | --- |
| alpha | Opacity | Fades the window's background and border. Text and rows stay fully visible. | 100 % |
| brightness | Brightness | Makes the dark background lighter or darker. 100 % is the normal look, 0 % is black. | 100 % |
| windowScale | Scale | Size of the whole window. It keeps its center on the screen. | 100 % |
| lockWindow | Lock window | The window can't be moved or resized. | Off |
| startHidden | Start hidden | The window stays closed at login. Open it with the minimap button or /lp. | Off |
| combatHide | Hide in combat | Hides the window when combat starts and shows it again afterwards, but only if it was open. A window you closed yourself stays closed. | Off |
| minimapButton | Minimap button | Shows the LootPrice button on the minimap. Left-click shows or hides the window, right-click opens these options. | On |
| minimapReset | Reset minimap button | Moves the minimap button back to the bottom left of the minimap. | (button) |

**Prices**

| Option | Short label | Tooltip | Default |
| --- | --- | --- | --- |
| priceSource | AH price source | Where auction prices come from. Auto asks TSM first, then Auctionator. | Auto |
| tsmSource | TSM price | The TSM price used for AH values, e.g. DBMarket or DBMinBuyout. Same as /lp tsm. | DBMarket |
| showMarket | TSM sale info | With TSM loaded, shows under each item name how well it sells in your region (well / okay / poorly) and how many sell per day. | On |
| saleRateGood | Sells well from | Region sale rate (0 to 1) from which an item counts as selling well. | 0.50 |
| saleRateOk | Sells okay from | Region sale rate from which an item counts as selling okay. Below it, it sells poorly. | 0.10 |
| soldHigh | High volume from | Average number sold per day in your region from which an item is High volume. Empty = never. | 100 |
| soldMedium | Medium volume from | Average number sold per day from which an item is Medium volume. Below it, Low volume. | 10 |
| refreshSeconds | Price refresh | How often prices and age tags are looked up again while the clock runs. The Daily farm is worked out again at the same pace. | 30 s |
| staleHours | Old price after | A cached AH price older than this shows its age tag in orange. | 12 h |

**Display**

| Option | Short label | Tooltip | Default |
| --- | --- | --- | --- |
| defaultSort | Sort at login | The list's order at every login. The sort button still changes it for the rest of the session. | Best value |
| goldDisplay | Large amounts | How amounts of 1 gold and more are shown: all coins, gold and silver, or gold only. Smaller amounts always show in full. | Gold, silver and copper |
| coinIcons | Coin icons | Shows the game's coin icons instead of the letters g, s and c, wherever amounts appear. | On |
| includeGold | Raw gold in Total | Adds the gold you looted to the Total row of the footer. Off leaves the Total row out. | On |
| showCurrencies | Currencies | Lists looted currencies after the items. | On |
| dailyFarm | Daily farm | Shows the Daily strip: the place in your History with the best gold per hour at today's prices. | On |
| dailyFarmMinutes | Daily farm: min. time | How long you must have farmed a place before the Daily strip can pick it. | 20 min |
| showTopFinds | Top finds | Shows the session's three most valuable finds under the footer. | On |
| showFooterGold | Raw gold row | Shows the Raw gold row in the footer table. | On |
| compactDrops | Compact: last drops | How many of the last drops the compact window lists. 0 hides them. | 4 |
| showIcons | Item icons | Shows the item icon at the start of each list row. Off starts the text at the left edge. | On |
| fontFace | Font | Typeface of all LootPrice text. WoW default uses the game font of your client's language. Other addons are not affected. | WoW default |
| fontSizeRows | List text | Size of the list text. The rows grow and shrink with it. | 12 px |
| fontSizeTotals | Totals text | Size of the footer table and Top finds. | 12 px |
| fontSizeTitles | Section titles | Size of section titles such as Top finds. | 16 px |

**Session and alerts**

| Option | Short label | Tooltip | Default |
| --- | --- | --- | --- |
| keepSession | Keep session | The session and its clock carry over to your next login instead of starting fresh. Same as /lp keep. | Off |
| alertGold | Drop alert (gold) | A chat line when one drop is worth at least this much gold. 0 or empty turns it off. | Off |
| alertSound | Alert sound | Plays a sound with the drop alert. | Off |
| countCrafted | Crafted and bought | Counts items you craft, and items you get at a vendor, mailbox, trade or the auction house, as loot. | Off |
| afkPause | Pause when AFK | Stops the clock while you are AFK and starts it again when you are back. | Off |
| instanceSession | Session per instance | Saves the session to History and starts a new one whenever you enter or leave a dungeon or raid. | Off |
| exportHistory | Export History | Opens a copy box with your History as CSV, for a spreadsheet. Same as /lp export. | (button) |
| historyLimit | History kept | How many sessions History keeps. 0 keeps none, empty keeps all. Lowering it deletes the oldest at once. | 50 |

## Build notes (my calls)

- Each option gets a `tooltip` field in `Options.define` (text through
  `ns.L`); the panel shows it with the existing rich tooltip (`ns.Tooltip`),
  so no option is named in the panel code. The default line comes from
  `DB.defaults.settings` through `Options.valueText`.
- Saved sizes stay numbers; a dropdown of numbers validates like the other
  dropdowns, and an odd saved value (from the old slider) falls back to the
  default only if it is outside the list (all old slider steps were whole px,
  so none are lost).
- The option keys and saved values do not change.
