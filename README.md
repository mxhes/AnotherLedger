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

**Libraries** (only when you install from the source code): the release zip
already contains them. A copy of the `LootPrice/` folder from the repository
needs these four libraries in its `Libs/` folder, or the game warns
`Error loading LootPrice/Libs/...` at login (the addon still works, with its own
minimap button and no data broker display):

| Library | Goes to | Download |
| --- | --- | --- |
| LibStub | `LootPrice/Libs/LibStub/LibStub.lua` | [CurseForge](https://www.curseforge.com/wow/addons/libstub) |
| CallbackHandler-1.0 | `LootPrice/Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua` | [CurseForge](https://www.curseforge.com/wow/addons/callbackhandler) |
| LibDataBroker-1.1 | `LootPrice/Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua` | [GitHub](https://github.com/tekkub/libdatabroker-1-1) |
| LibDBIcon-1.0 | `LootPrice/Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua` | [CurseForge](https://www.curseforge.com/wow/addons/libdbicon-1-0) |

The file has to sit at exactly that path: copy just the library's folder
(with the `.lua` file in it) out of the download. Installing them as separate
addons does not remove the warning.

**Updating the libraries yourself**: you can also install any of the four as
its own addon (in `Interface/AddOns/`, from the links above) and update it
whenever you like. LootPrice then uses that copy; the one that comes with
LootPrice is only used when it is newer or when you don't have the library
installed.

## The window

Open it with `/lp`, the minimap button or a data broker display (Titan Panel,
ElvUI, ...). It has two layouts; switch with the **arrow button** next to the
gear, a double-click on the title, or `/lp compact`. Each layout keeps its own
size.

**Compact** is for a glance between pulls: your gold per hour in large type,
the session total (with a session goal: `Session 312g / 500g`), the last four
drops with their value and source tag (framed, as in the list), and the Daily
farm line. Hover the gold per
hour for the breakdown: time, items, raw gold, total, the best find, how far
the goal is and, after a few minutes, a small graph of your gold per hour over
the session (one bar per stretch of clock time) to see when a spot dries up.
The same graph shows when you hover the totals of the Session tab. Click the clock to start or stop the session; a red `Paused`
shows while it is stopped. Before the first drop the list says so (or that the
clock is stopped).

**Full** is the detailed ledger:

- **Header**: the session clock (red while stopped), **Start / Stop**,
  **Reset**, the layout arrow, the gear (options) and close. While the clock
  is stopped, loot and gold are not counted; the chat says so once.
- **Filter bar**: quality (the button shows how many are shown, e.g.
  `Quality 6/8`; the menu starts with one-click choices such as `Uncommon and
  better`), minimum value in gold, text search and the sort (Value, Vendor,
  Name, Recent). Filters are remembered; the small x next to the sort clears
  them all.
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
  Ctrl-click tries it on. Right-click an item to **ignore** it (a hearthstone,
  a quest item): it then counts nowhere, in no list, total, alert or goal, on
  every character; **Ignored items** in the options takes it back. Top finds
  work the same way. An empty list says why: no loot yet, the clock is
  stopped, or nothing matches the filters. Each tab keeps its scroll position
  until you log out.
- **Footer**: the value and gold per hour of your **Items**, the **Raw gold**
  you looted (creatures, containers, group shares, quest rewards) and the
  **Total**. Hover it for vendor / AH / best totals. With a session goal, the
  line under the table says how far you are (`Goal 62%`). History and Zones
  have no footer; their list runs to the bottom of the window.
- **Top finds**: the three most valuable finds of the session.

Amounts show with the game's coin icons (or as `12g 34s 56c`, see Options),
gold, silver and copper each in its own column, so the coins line up down the
list, the footer, Top finds and the compact drops.
Items that can't be sold on the auction house (soulbound, quest items) count
at their vendor value. Gear with a different item level or sockets gets its own
row and price. Currencies are listed after the items.

## Tabs

- **Session**: everything looted since the session started.
- **Bags**: what is in your bags right now, valued the same way. Right-click
  an item and pick **Keep (not for sale)** for tools, consumables you use or
  gear sets: the row says `(kept)` and the footer splits the total into
  **Kept** and **Sellable**. The keep list is the same in Bags and Bank and
  for all characters; **Kept items** in the options lists it.
- **Bank**: your bank. The game only shows it to addons while it is open, so
  visit the banker once; after that the tab shows the last scan and its age.
- **History**: your past sessions, newest first. Each row shows when it
  started (`Today 20:21`, `Yesterday`, a weekday, then the date) and your note,
  its length, main place and item count, and its value (with the raw gold,
  unless **Raw gold in Total** is off). A session is saved when you reset it, when a new
  login starts a fresh one, or (option) when you enter or leave a dungeon. A
  session keeps the prices of the day it was saved, so its value doesn't change
  later. Sort the sessions by Value, Recent or Gold/h; the search (date, note,
  length, place) and the minimum value pick sessions, and the footer adds up
  the listed ones. Click a session to list its items; right-click it to add a
  note (`Wingrest herbs, 2 alts`), merge it or delete it; hover it for places,
  currencies, values and gold per hour. **Merge with the older session** joins
  a session with the one started before it (say a dungeon run you left and
  re-entered): items, gold, time and places add up, the time between the two
  does not count. Merge again to join three or more. `/lp undo` takes back the
  last merge or delete until you log out or reload. `/lp export` copies the History as CSV for
  a spreadsheet. **Clear History** (options) deletes all of it.
- **History > Zones**: which places are worth farming. All sessions of all
  your characters (option **Zones: all characters**) grouped by zone and
  subzone, each with its time, gold per hour and item count (sort by
  **Gold/h**). Click a zone to open its subzones, a subzone to list its items.
  A zone's time includes the subzones where nothing was looted, so its gold
  per hour is not too high. `Unknown place` and `No time recorded` come last.
  Quest items have their own group and don't count toward any place. Zones
  and the Daily farm use today's prices. A dungeon counts as one place even
  when the game briefly reports no difficulty.

## Daily farm

The gold strip above the tabs names the subzone from your History (of all
your characters, like Zones) with the best gold per hour at today's prices, e.g. `Daily: 1,240g/h  Wingrest
(Waking Shores)`. Only saved sessions count (so farming doesn't move today's
pick), and a place needs 20 minutes of recorded time by default. A place whose
value comes mostly from items that sell poorly is marked `slow selling`.

- **Click**: sets a waypoint to where you looted there (TomTom, or the map pin).
- **Shift-click**: opens History > Zones at that place (from the compact
  layout too: it switches to the full one).
- **Right-click**: shows the `/way` line to copy.
- **Hover**: time, value, exact gold per hour, the next two places and the
  slow sellers.

## Options

Open them with the gear, a right-click on the minimap button, or Esc >
Options > AddOns > LootPrice. Hover any option for what it does and its
default. Changes apply at once. **Opacity** and **Brightness** apply to the
options window as well. **Lock window** also hides the resize grip;
with **Snap to grid** the window snaps onto the lines of the Edit Mode grid
when you drop it close to one;
anything that deletes History asks first.

| Tab | Options |
| --- | --- |
| Window | Opacity, Brightness, Scale, Lock window, Snap to grid, Start hidden, Hide in combat, Minimap button, Reset minimap button |
| Prices | AH price source, TSM price, TSM sale info, Sells well / okay from, High / Medium volume from, Price refresh, Old price after |
| Display | Sort at login, Large amounts, Coin icons, Raw gold in Total, Currencies, Daily farm, Daily farm: min. time, Zones: all characters, Top finds, Raw gold row, Compact: last drops, Item icons, Price per unit, Ignored items, Kept items, Scroll to new loot, Font, Font outline, Font shadow, List text, Totals text, Section titles |
| Session and alerts | Keep session, Drop alert (gold), Alert sound, Session goal (gold), Session goal (minutes), Crafted and bought, Pause when AFK, Session per instance, Session per zone, Zone change delay, Export History, Clear History, History kept |
| Colors | Text, Titles and totals, Hints, Vendor, Auction, Destroy, Tooltip labels, Window background, Window border, Button background, Reset colors |

**Colors**: click a swatch to pick a color in the game's color picker (the
window changes while you pick, Cancel puts the old color back); right-click it
for the default. By default text is white, and vendor values are cream, auction
values blue and destroy values grey, in the list and in the tooltips.

**Font outline** (None, Thin, Thick) puts a dark outline around all LootPrice
text, which reads better over a bright background; **Font shadow** turns the
game's soft text shadow on or off. Both change the window right away and leave
other addons alone.

By default crafted items and purchases (vendor, mail, trade, auction house)
are not counted as loot; **Crafted and bought** turns that on.

**Session goals**: with **Session goal (gold)** set, the compact window shows
the total against it and a chat line says when the session is worth that much
(counted like the compact total). **Session goal (minutes)** says in chat when
the clock reaches that time, with what the session is worth. Each goal is
announced once per session; **Alert sound** plays with them.

**Session per zone** saves the session to History and starts a new one when
you change zones, so History rows stay apart when you hop between farm spots.
It waits until you stayed in the new zone for the **Zone change delay** (2
minutes by default): a short detour or a cave entrance does not split the
session, and flight paths never count. Loot from those minutes still belongs
to the old session. An empty session just starts its clock over. While the
clock is stopped nothing splits.

**Price per unit** shows the value of one item on a stack of several instead
of the whole stack; totals and tooltips stay the same.

**Key bindings**: Esc > Options > Key Bindings > AddOns > LootPrice has keys
for showing the window, switching compact / full and starting / stopping the
clock.

## Commands

| Command | Does |
| --- | --- |
| `/lp` (or `/lootprice`) | show or hide the window |
| `/lp show`, `/lp hide` | show or hide it |
| `/lp start`, `/lp stop`, `/lp clock` | start, stop or switch the session clock |
| `/lp compact` | switch between the compact and the full layout |
| `/lp reset` | clear the session (saved to History; asks first when it holds many items or is worth 100 gold or more) |
| `/lp keep on` / `off` | keep the session across logins |
| `/lp tsm <price>` | the TSM price to use, e.g. `DBMarket` |
| `/lp export` | the History as CSV in a copy box |
| `/lp export session`, `/lp export zones` | the session's items, or every Zones place, as CSV |
| `/lp undo` | take back the last merge or delete in History (or the cleared History) |
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
