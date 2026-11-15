# LootPrice

A World of Warcraft **Forever** addon that values everything you loot. The
Session Ledger window lists each item with what it is worth (vendor, auction
house or disenchant, whichever is highest), adds up your gold per hour, and
tells you where your best farm is today.

- Developers: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
- In-client checks and release steps: [docs/CHECKLIST.md](docs/CHECKLIST.md)

## Requirements

Vendor prices work on their own. Auction prices need
[TradeSkillMaster](https://www.tradeskillmaster.com/) or Auctionator (both
optional; TSM is asked first). Destroy values (what disenchanting, milling or
prospecting gives) and the "sells well / poorly" info need TSM. Waypoints use TomTom when it is installed, else the game's own
map pin.

## The window

Open it with `/lp`, the minimap button or a data broker display (Titan Panel,
ElvUI, ...). It has two layouts; switch with the **arrow button** next to the
gear, a double-click on the title, or `/lp compact`. Each layout keeps its own
size.

**Compact** is for a glance between pulls: your gold per hour in large type,
the session total, the last four drops with their value and source, and the
Daily farm line. Click the clock to start or stop the session; a red `Paused`
shows while it is stopped.

**Full** is the detailed ledger:

- **Header**: the session clock (red while stopped), **Start / Stop**,
  **Reset**, the layout arrow, the gear (options) and close.
- **Filter bar**: quality (the button shows how many are shown, e.g.
  `Quality 6/8`), minimum value in gold, text search and the sort (Value,
  Vendor, Name, Recent). Filters are remembered; the small x next to the sort
  clears them all.
- **Daily strip**: today's best farm (see below).
- **Tabs**: Session, Bags, Bank and History (below).
- **List**: one row per item: icon, name and quantity, and on the right its
  value with a tag saying where it comes from: `Vendor`, `Auction` or
  `Destroy` (disenchant, mill or prospect). With TSM, a second line says how
  well it sells in your region.
  A price taken from the cache shows its age, e.g. `(3h)`, in orange once it
  is old; an item with no auction price is marked `?`. New loot flashes (and
  the Session list scrolls to it, see **Scroll to new loot**). Hover a row for
  the item tooltip with all its values; Shift-click links the item in chat,
  Ctrl-click tries it on. Top finds work the same way.
- **Footer**: the value and gold per hour of your **Items**, the **Raw gold**
  you looted (creatures, containers, group shares, quest rewards) and the
  **Total**. Hover it for vendor / AH / best totals. History and Zones have no
  footer; their list runs to the bottom of the window.
- **Top finds**: the three most valuable finds of the session.

Amounts show with the game's coin icons (or as `12g 34s 56c`, see Options).
Items that can't be sold on the auction house (soulbound, quest items) count
at their vendor value. Gear with a different item level or sockets gets its own
row and price. Currencies are listed after the items.

## Tabs

- **Session**: everything looted since the session started.
- **Bags**: what is in your bags right now, valued the same way.
- **Bank**: your bank. The game only shows it to addons while it is open, so
  visit the banker once; after that the tab shows the last scan and its age.
- **History**: your past sessions, newest first, with their length, main place
  and value. A session is saved when you reset it, when a new login starts a
  fresh one, or (option) when you enter or leave a dungeon. A session keeps the
  prices of the day it was saved, so its value doesn't change later. Click a
  session to list its items, right-click it to delete it; hover it for places,
  currencies, values and gold per hour. `/lp export` copies the History as CSV
  for a spreadsheet. **Clear History** (options) deletes all of it.
- **History > Zones**: which places are worth farming. All sessions grouped by
  zone and subzone, each with its time, value and gold per hour (sort by
  **Gold/h**). Click a zone to open its subzones, a subzone to list its items.
  Quest items have their own group and don't count toward any place. Zones
  and the Daily farm use today's prices.

## Daily farm

The gold strip above the tabs names the subzone from your History with the
best gold per hour at today's prices, e.g. `Daily: 1,240g/h  Wingrest
(Waking Shores)`. Only saved sessions count (so farming doesn't move today's
pick), and a place needs 20 minutes of recorded time by default. A place whose
value comes mostly from items that sell poorly is marked `slow selling`.

- **Click**: sets a waypoint to where you looted there (TomTom, or the map pin).
- **Shift-click**: opens History > Zones at that place.
- **Right-click**: shows the `/way` line to copy.
- **Hover**: time, value, exact gold per hour, the next two places and the
  slow sellers.

## Options

Open them with the gear, a right-click on the minimap button, or Esc >
Options > AddOns > LootPrice. Hover any option for what it does and its
default. Changes apply at once. **Lock window** also hides the resize grip;
anything that deletes History asks first.

| Tab | Options |
| --- | --- |
| Window | Opacity, Brightness, Scale, Lock window, Start hidden, Hide in combat, Minimap button, Reset minimap button |
| Prices | AH price source, TSM price, TSM sale info, Sells well / okay from, High / Medium volume from, Price refresh, Old price after |
| Display | Sort at login, Large amounts, Coin icons, Raw gold in Total, Currencies, Daily farm, Daily farm: min. time, Top finds, Raw gold row, Compact: last drops, Item icons, Scroll to new loot, Font, List text, Totals text, Section titles |
| Session and alerts | Keep session, Drop alert (gold), Alert sound, Crafted and bought, Pause when AFK, Session per instance, Export History, Clear History, History kept |
| Colors | Text, Titles and totals, Hints, Vendor, Auction, Destroy, Tooltip labels, Window background, Window border, Button background, Reset colors |

**Colors**: click a swatch to pick a color in the game's color picker (the
window changes while you pick, Cancel puts the old color back); right-click it
for the default. By default text is white, and vendor values are cream, auction
values blue and destroy values grey, in the list and in the tooltips.

By default crafted items and purchases (vendor, mail, trade, auction house)
are not counted as loot; **Crafted and bought** turns that on.

## Commands

| Command | Does |
| --- | --- |
| `/lp` (or `/lootprice`) | show or hide the window |
| `/lp show`, `/lp hide` | show or hide it |
| `/lp start`, `/lp stop` | start or stop the session clock |
| `/lp compact` | switch between the compact and the full layout |
| `/lp reset` | clear the session (saved to History; asks first when it holds many items or is worth 100 gold or more) |
| `/lp keep on` / `off` | keep the session across logins |
| `/lp tsm <price>` | the TSM price to use, e.g. `DBMarket` |
| `/lp export` | the History as CSV in a copy box |
| `/lp demo` | sample loot and temporary sample prices, to look at the window |
| `/lp help` | list the commands |

A `/reload` always keeps the session; a new login starts a fresh one unless
**Keep session** is on.

## Good to know

- **Price age**: TSM and Auctionator don't say when they last scanned, so the
  age tag is the time since the source last gave a price for that item.
- **Languages**: English and German. Loot and money messages are read from the
  game's own texts, so they work in every client language.
- **Install**: copy the `LootPrice/` folder into
  `World of Warcraft/<client>/Interface/AddOns/`.
