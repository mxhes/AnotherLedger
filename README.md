# LootLedger

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
already contains them. A copy of the `LootLedger/` folder from the repository
needs these four libraries in its `Libs/` folder, or the game warns
`Error loading LootLedger/Libs/...` at login (the addon still works, with its own
minimap button and no data broker display):

| Library | Goes to | Download |
| --- | --- | --- |
| LibStub | `LootLedger/Libs/LibStub/LibStub.lua` | [CurseForge](https://www.curseforge.com/wow/addons/libstub) |
| CallbackHandler-1.0 | `LootLedger/Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua` | [CurseForge](https://www.curseforge.com/wow/addons/callbackhandler) |
| LibDataBroker-1.1 | `LootLedger/Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua` | [GitHub](https://github.com/tekkub/libdatabroker-1-1) |
| LibDBIcon-1.0 | `LootLedger/Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua` | [CurseForge](https://www.curseforge.com/wow/addons/libdbicon-1-0) |

The file has to sit at exactly that path: copy just the library's folder
(with the `.lua` file in it) out of the download. Installing them as separate
addons does not remove the warning.

**Updating the libraries yourself**: you can also install any of the four as
its own addon (in `Interface/AddOns/`, from the links above) and update it
whenever you like. LootLedger then uses that copy; the one that comes with
LootLedger is only used when it is newer or when you don't have the library
installed.

## The window

Open it with `/ll`, the minimap button or a data broker display (Titan Panel,
ElvUI, ...). It has two layouts; switch with the **arrow button** next to the
gear, a double-click on the title, or `/ll compact`. Each layout keeps its own
size; the corner nearest to the screen edge stays where it is when you switch.

**Compact** is for a glance between pulls: your gold per hour in large type,
the session total (with a session goal: `Session 312g / 500g`), the last four
drops with their value and source tag (framed, as in the list), and the Daily
farm line. Until the session earns something the rate shows `—/h`. Hover the gold per
hour for the breakdown: time, items, raw gold, total, the best find, how far
the goal is and, after a few minutes, a small graph of your gold per hour over
the session (one bar per stretch of clock time) to see when a spot dries up.
The same graph shows when you hover the totals of the Session tab. Click the clock to start or stop the session; a red `Paused`
shows while it is stopped. Before the first drop the list says so (or that the
clock is stopped).

**Full** is the detailed ledger:

- **Header**: the session clock (red while stopped), **Start / Stop**,
  **Reset**, the layout arrow, the gear (options) and close. While the clock
  is stopped, loot and gold are not counted; the chat says so once. On Bags
  and Bank the header shows how many items are listed, on History how many
  sessions.
- **Filter bar**: quality (the button shows how many are shown, e.g.
  `Quality 6/8`; the menu starts with one-click choices such as `Uncommon and
  better`), minimum value in gold, text search and the sort (Value, Vendor,
  Name, Recent). Filters are remembered; the small x next to the sort clears
  them all. Session, Bags and Bank share one sort; History's Sessions and
  Zones each keep their own (Sessions start newest first).
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
  line under the table says how far you are (`Goal 62%`). On History and
  Zones the footer adds up the listed sessions or places, with gold per hour
  over their recorded time.
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
  visit the banker once (until then the list says `Not scanned yet.` and the total shows `—`); after
  that the tab shows the last scan and its age.
- **History**: your past sessions, newest first. Each row shows when it
  started (`Today 20:21`, `Yesterday`, a weekday, then the date) and your note,
  its length, item count and main place, and its value (with the raw gold,
  unless **Count raw gold** is off). A session is saved when you reset it, when a new
  login starts a fresh one, or (option) when you enter or leave a dungeon. A
  session keeps the prices of the day it was saved, so its value doesn't change
  later. Sort the sessions by Value, Recent or Gold/h; the search (date, note,
  length, place) and the minimum value pick sessions, and the footer adds up
  the listed ones. Click a session to list its items; right-click it to add a
  note (`Wingrest herbs, 2 alts`), merge it or delete it; hover it for places,
  currencies, values and gold per hour. **Merge with the older session** joins
  a session with the one started before it (say a dungeon run you left and
  re-entered): items, gold, time and places add up, the time between the two
  does not count. Merge again to join three or more. `/ll undo` takes back the
  last merge or delete until you log out or reload. `/ll export` copies the History as CSV for
  a spreadsheet. **Clear History** (options) deletes all of it.
- **History > Zones**: which places are worth farming. All sessions of all
  your characters (option **Zones: all characters**) grouped by zone and
  subzone, each with its time, gold per hour and item count (sort by
  **Gold/h**). Click a zone to open its subzones, a subzone to list its items.
  A zone's time includes the subzones where nothing was looted, so its gold
  per hour is not too high. `Unknown place` and `No time recorded` come last.
  Quest items have their own group and don't count toward any place. Zones
  and the Daily farm use today's prices. A dungeon counts as one place even
  when the game briefly reports no difficulty. The header says how many
  places are listed, the Daily farm's place has the same star as the strip,
  and a dungeon's difficulty is shortened in the list (`Razorfen Downs (N)`;
  the tooltip has the full name). Hover the footer to see which items have no
  auction price yet (`2 unpriced`).

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
Options > AddOns > LootLedger. Hover any option for what it does and its
default. Changes apply at once. Drag the options window to move it; it opens
there from then on (until then, next to the ledger). **Opacity** and **Brightness** apply to the
options window as well. **Lock window** also hides the resize grip;
with **Snap to grid** the window snaps onto the lines of the Edit Mode grid
when you drop it close to one;
anything that deletes History asks first.

| Tab | Options |
| --- | --- |
| Window | Opacity, Brightness, Scale, Lock window, Snap to grid, Start hidden, Hide in combat, Minimap button, Reset minimap button |
| Prices | AH price source, TSM price, TSM sale info, Sells well / okay from, High / Medium volume from, Price refresh, Old price after, AH cut (5%), Auction from, Destroy values |
| List | Sort at login, Large amounts, Coin icons, Count raw gold, Currencies, Top finds, Show raw gold row, Compact: last drops, Item icons, Price per unit, Ignored items, Kept items, Scroll to new loot |
| Session | Keep session, Crafted and bought, Drop alert (gold), Alert sound, Session goal (gold), Session goal (minutes), Session summary in chat, Pause when AFK, Pause in cities, Session per instance, Session per zone, Zone change delay, Min. session length |
| History | Daily farm, Daily farm: min. time, Zones: all characters, Export History, Clear History, History kept |
| Look | Font, Font outline, Font shadow, List text, Totals text, Section titles, Color preset, Text, Titles and totals, Hints, Vendor, Auction, Destroy, Tooltip labels, Window background, Window border, Button background, Reset colors |
| Profiles | Profile, New profile, Copy profile, Rename profile, Delete profile, Reset profile, Export profile, Import profile |

**Color preset** changes the whole look at once: the window, the lines, the
tabs, the buttons and the scrollbar. **LootLedger** is the dark leather look,
**Blizzard** is black and bronze with red buttons like the game's own
windows, **Midnight** is dark blue, **TSM-style** is slate with a gold-orange
accent and **Parchment** is a light tan with light text and dark brown buttons
(it also turns on a thin font outline so all text reads on the light
background, like the labels on the game's maps). Item
quality and coin colors always stay the game's own. After a preset you can
still change single colors; the preset then shows "(edited)".

**Colors**: click a swatch to pick a color in the game's color picker (the
window changes while you pick, Cancel puts the old color back); right-click it
for the preset's color. **Reset colors** goes back to the chosen preset's colors.
Tooltips keep the game's dark tooltip on every preset.

**Session summary in chat** writes one line whenever a session is saved to
History: its length, main place, worth and gold per hour. **History kept**
counts per character and applies to all of them.

**Profiles**: every option is part of a profile, except **History kept**,
**Zones: all characters** and **Minimap button**, which count for the whole
account. Each character picks its own profile; new characters use
**Default**. Hover **Profile** to see which characters use the chosen one. **New profile** starts from the defaults, **Copy profile** from
the current one; Default can't be renamed or deleted. **Reset profile** sets
every option of the current profile back to its default (it asks first). **Export profile** shows
the profile as one line of text to copy into a chat or a file; **Import
profile** opens a box to paste such a line, asks for a name (and before
overwriting a profile of that name) and switches to it. Settings an import
does not understand are skipped and counted in chat. Window position and
size, filters, the ignore and keep lists and History are not part of a
profile. Updating to the version with profiles starts with the default
settings once.

**Font outline** (None, Thin, Thick) puts a dark outline around all LootLedger
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

**Pause in cities** (on by default) stops the clock while you are in a city or
inn, so selling and mailing don't lower your gold per hour; loot and gold
still count. The compact window says Resting. A clock you stopped yourself
stays stopped when you leave.

**Min. session length** (2 minutes by default) keeps very short sessions out
of History: a session shorter than that just continues when a new zone or
instance or a fresh login would start a new one. Reset always saves it; Off
saves every session.

**Price per unit** shows the value of one item on a stack of several instead
of the whole stack; totals and tooltips stay the same.

**Key bindings**: Esc > Options > Key Bindings > AddOns > LootLedger has keys
for showing the window, switching compact / full and starting / stopping the
clock.

## Commands

| Command | Does |
| --- | --- |
| `/ll` (or `/lootledger`) | show or hide the window |
| `/ll show`, `/ll hide` | show or hide it |
| `/ll start`, `/ll stop`, `/ll clock` | start, stop or switch the session clock |
| `/ll compact` | switch between the compact and the full layout |
| `/ll reset` | clear the session (saved to History; asks first when it holds many items or is worth 100 gold or more) |
| `/ll keep on` / `off` | keep the session across logins |
| `/ll tsm <price>` | the TSM price to use, e.g. `DBMarket` (also the option TSM price: pick a common one or Custom... to type any TSM price) |
| `/ll export` | the History as CSV in a copy box |
| `/ll export session`, `/ll export zones` | the session's items, or every Zones place, as CSV |
| `/ll undo` | take back the last merge or delete in History (or the cleared History) |
| `/ll demo` | sample loot and temporary sample prices, to look at the window |
| `/ll help` | list the commands |

A `/reload` always keeps the session; a new login starts a fresh one unless
**Keep session** is on.

## Good to know

- **Value rules**: *AH cut (5%)* (on by default) counts Auction values after
  the auction house's fee; the item tooltip says so. *Auction from* counts an
  item as Vendor unless its Auction value beats the vendor price by the set
  percent. *Destroy values* can count destroy values only when one of your
  characters (or this one) has the profession: Enchanting for gear,
  Inscription for herbs, Jewelcrafting for ore. Your characters' professions
  are noted when you log in on them. Sessions already in History keep the
  prices they were saved with.
- **Price age**: TSM and Auctionator don't say when they last scanned, so the
  age tag is the time since the source last gave a price for that item.
- **Languages**: English and German. Loot and money messages are read from the
  game's own texts, so they work in every client language.
- **Install**: copy the `LootLedger/` folder into
  `World of Warcraft/<client>/Interface/AddOns/`.
- **Coming from LootPrice** (the addon's old name): delete the old `LootPrice`
  folder. To keep your History, options and lists, rename the saved files
  `LootPrice.lua` to `LootLedger.lua` while the game is closed, in
  `WTF/Account/<account>/SavedVariables/` and in each character's
  `SavedVariables/` folder under `WTF/Account/<account>/<realm>/<character>/`.
