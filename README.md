# AnotherLedger

<img src="docs/logo.png" alt="AnotherLedger logo" width="96" align="right">

A World of Warcraft **Forever** addon that values everything you loot. The
Session Ledger window lists each item with what it is worth (vendor, auction
house or disenchant, whichever is highest), adds up your gold per hour, and
tells you where your best farm is today.

AnotherLedger was called LootLedger before (that name was taken). If you used
the old version, remove its `LootLedger` addon folder. Settings and history
from the old name don't carry over, and the slash command is now `/al`.

- Source code and issues: <https://gitlab.com/mhhenjes/lootledger>
- Developers: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
- In-client checks and release steps: [docs/CHECKLIST.md](docs/CHECKLIST.md)

## Requirements

Vendor prices work on their own. Auction prices come from
[TradeSkillMaster](https://www.tradeskillmaster.com/) or Auctionator (both
optional; TSM is asked first) and from AnotherLedger's own auction house scan
(see "Scanning the auction house"), which also fills in items TSM and
Auctionator have no price for. Destroy values (what disenchanting, milling or
prospecting gives) come from TSM, else from Auctionator (disenchanting only);
they count whenever one of them is loaded, whatever the AH price source. The
"sells well / poorly" info needs TSM. Without either addon and without scan
prices, AnotherLedger says so once in chat. Options that need an addon you
don't have show dimmed, and their tooltip says why. Waypoints use TomTom when it is
installed, else the game's own map pin.

**Libraries** (only when you install from the source code): the release zip
already contains them. A copy of the `AnotherLedger/` folder from the repository
needs these four libraries in its `Libs/` folder, or the game warns `Error
loading AnotherLedger/Libs/...` at login (the addon still works, with its own
minimap button and no data broker display):

| Library | Goes to | Download |
| --- | --- | --- |
| LibStub | `AnotherLedger/Libs/LibStub/LibStub.lua` | [CurseForge](https://www.curseforge.com/wow/addons/libstub) |
| CallbackHandler-1.0 | `AnotherLedger/Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua` | [CurseForge](https://www.curseforge.com/wow/addons/callbackhandler) |
| LibDataBroker-1.1 | `AnotherLedger/Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua` | [GitHub](https://github.com/tekkub/libdatabroker-1-1) |
| LibDBIcon-1.0 | `AnotherLedger/Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua` | [CurseForge](https://www.curseforge.com/wow/addons/libdbicon-1-0) |

The file has to sit at exactly that path: copy just the library's folder
(with the `.lua` file in it) out of the download. Installing them as separate
addons does not remove the warning.

**Updating the libraries yourself**: you can also install any of the four as
its own addon (in `Interface/AddOns/`, from the links above) and update it
whenever you like. AnotherLedger then uses that copy; the one that comes with
AnotherLedger is only used when it is newer or when you don't have the library
installed.

## The window

Open it with `/al`, the minimap button or a data broker display (Titan Panel,
ElvUI, ...). It has two layouts; switch with the **arrow button** next to the
gear, a double-click on the title, or `/al compact`. Each layout keeps its own
size; the corner nearest to the screen edge where you last moved or resized
the window stays where it is when you switch, so switching back puts it
exactly where it was. The full window can't be made narrower than its tabs
and buttons need (in some languages a little wider), so nothing is cut off.

**Compact** is for a glance between pulls: your gold per hour in large type,
the session total (with a session goal: `Session 312g / 500g`, and a gold bar
under them that fills up toward the goal), the last four drops with their
value and source tag (framed, as in the list; the quantity in a quieter
color, an item without an auction price marked `?`, and with **Compact: item
icons** its icon in front), and the Daily farm line. After
a quarter hour, `15 min: 120g/h` right of the drops title is the gold per
hour of the last 15 minutes, so you see when a spot slows down. Until the
session earns something the rate shows `—/h`. Hover the gold per hour for the
breakdown: time, items, raw gold, total, the best find, how far the goal is,
the last 15 minutes' rate and, after a few minutes, a small graph of your gold
per hour over the session (one bar per stretch of clock time) to see when a
spot dries up. The same graph shows when you hover the totals of the Session
tab. Click the clock to start or stop the session; a red `Paused` shows while
it is stopped. Before the first drop the list says so (or that the
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
- **Tabs**: Session, Bags, Bank, History and Trade (below).
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
  every character; **Ignored items** in the options takes it back. Pick
  **Watch this item** instead to hear a sound and see a line in the middle
  of the screen whenever you loot it (see "Watch list"). Top finds
  work the same way. An empty list says why: no loot yet, the clock is
  stopped, or nothing matches the filters. Each tab keeps its scroll position
  until you log out.
- **Footer**: the value and gold per hour of your **Items**, the **Raw gold**
  you looted (creatures, containers, group shares, quest rewards) and the
  **Total**. Hover it for vendor / AH / best totals. With a session goal, the
  line under the table says how far you are (`Goal 62%`). On History and
  Zones the footer adds up the listed sessions or places, with gold per hour
  over their recorded time (old loot without recorded time counts in the
  value, not in the rate); its hover says which sessions it counts. Mobs has
  no clock, so no per hour column. The option **Raw gold** decides whether
  the gold counts in the Total and whether it has its own row. Click
  `N without AH price (marked ?)` under the table to list the items without an
  auction price first; click again for the normal sort. Items that can't be
  sold on the auction house (soulbound, also gear bound by equipping it) and
  items nothing pays for are never marked or counted there.
- **Top finds**: the three most valuable finds of the session.

Amounts show with the game's coin icons (or as `12g 34s 56c`, see Options),
gold, silver and copper each in its own column, so the coins line up down the
list, the footer, Top finds and the compact drops. Items that can't be sold on
the auction house (soulbound, quest items) count at their vendor value; an
item nothing pays for (no vendor, auction or destroy value) shows a dash;
**Hide worthless** leaves those out of the lists. Gear with a different item
level or sockets gets its own row and price. Currencies are listed after the
items.

## Tabs

- **Session**: everything looted since the session started.
- **Bags**: what is in your bags right now, valued the same way. Right-click
  an item and pick **Keep (not for sale)** for tools, consumables you use or
  gear sets: the row says `(kept)` and the footer splits the total into
  **Kept** and **Sellable**. The keep list is the same in Bags and Bank and
  for all characters; **Kept items** in the options lists it. The footer also
  shows **Gold on hand** and **Net worth** (your bags, your bank as of its
  last visit and your gold, whatever the filter shows), its tooltip the
  **Sell split** (what the items not kept bring at the vendor, on the AH and
  destroyed), and the header your free bag slots (orange at 5 or fewer, red
  at 2 or fewer). Once you have logged in with a second character, the
  footer adds **All characters**: every character's net worth as it was when
  you last logged out with it (or looked at its Bags); the tooltip lists
  them with their age.
- **Bank**: your bank. The game only shows it to addons while it is open, so
  visit the banker once (until then the list says `Not scanned yet.` and the
  total shows `—`); after that the tab shows the last scan and its age.
- **History**: your past sessions, newest first. Each row shows when it
  started (`Today 20:21`, `Yesterday`, a weekday, then the date) and your
  note, its length, gold per hour, item count and main place, and its value
  (with the raw gold, unless the option **Raw gold** leaves it out). A session
  is saved when you reset it, when a new login starts a fresh one, or (options)
  when you enter or leave a dungeon or change zones. A session keeps the prices of the day it
  was saved, so its value doesn't change later. Sort the sessions by Value,
  Recent or Gold/h; the search (date, note, length, place) and the minimum
  value pick sessions, and the footer adds up the listed ones. Sorted by
  Recent, the sessions sit under headings (Today, Yesterday, the other days of
  this week, then week numbers, with the year for another year's weeks) with
  their count, length and value; click a heading to fold it. Click a session
  to list its items; right-click it to add a note (`Wingrest herbs, 2 alts`),
  merge it or delete it; hover it for places, currencies, values and gold per
  hour. **Merge with the older session** joins a session with the one started
  before it (say a dungeon run you left and re-entered): items, gold, time and
  places add up, the time between the two does not count. Merge again to join
  three or more. `/al undo` takes back the last merge or delete until you log
  out or reload. `/al export` copies the History as CSV for a spreadsheet.
  **Clear History** (options) deletes all of it.
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
  auction price yet (`2 without AH price (marked ?)`); it also says why: no
  price addon and no scan yet, or your price sources don't know those items.
- **History > Mobs**: what each kind of mob and gathering node gave you, over
  the same sessions as Zones: how often you looted it, the value of its loot
  plus its gold, and the value per corpse or node looted. Sort by **Value**,
  **Per loot** or **Name**; click a mob to list its items, hover it for where
  you looted it most, its best drops and its likeliest drops with their drop
  chance; an opened mob's items show theirs in the tooltip (`Drop chance: 35%
  (7 of 20)`). The chance counts every corpse or node whose loot window you
  saw, also items you left in it; loot recorded before this version has no
  chance yet. Every item tooltip in the game (bags, chat links, the loot
  window) lists the mobs and nodes that drop it with their chance (option
  **Drop chance in tooltips**). Loot is credited when you take it from the
  loot window (also with auto loot or a fast loot addon), split by corpse
  when one window holds several; loot you leave in a corpse counts for
  nobody. Mobs counts even while the clock is stopped (the session's own
  lists and totals don't; a session with only mob loot is still saved to
  History). Kills are not counted: the game does not let addons read the
  combat log. A mob's coin counts what you got of it, so in a group your
  share. A mob or node whose name was never seen shows its number. Sessions
  saved before Mobs existed have no mob data.
- **History > Totals**: your saved sessions added up per week and per month,
  to see whether your farming gets better. Sorted by Recent, each month is a
  heading with its total (click it to fold its weeks) and its weeks are
  listed under it, newest first; a week that spans two months shows under
  both with its part. Each row shows the number of sessions, their length,
  the value and the gold per hour. Sorted by Value or Gold/h, the weeks are
  ranked without the month headings, best first.
- **Trade**: what you sell and trade on this realm, from all your characters.
  - **Items** lists every item you sold or bought on the auction house: how
    many you sold (auction house and player trades together), the gold you
    earned after the auction house cut less what your auction house
    purchases of it cost in the coin column (`4 bought` in the second line;
    an item you only bought shows a minus), the sell rate (`75% sold`: sold out of everything you put up,
    expired and cancelled auctions count against it) and your average price
    against the market price on the day of each sale (`+4% vs market`). The
    button at the right picks **7 days**, **30 days** or **All**. Hover a row
    for its sales and purchases one by one (date, amount, price, the market
    then, the other player). The header counts sold, expired, cancelled and
    bought. Sorts: Gold earned, Sold, Sell rate, vs market, Name.
  - **Log** lists every entry, newest first: Posted, Cancelled, Expired, Sold,
    Bought, Trade sale, Trade purchase and Trade, with the date, the other
    player and your character; purchases show the gold you paid with a minus
    sign. Sorts: Recent, Gold earned, Name.
  - The filter bar works on both: the search and the minimum value pick
    items or entries, the quality filter the items (a trade with a player
    has no quality and always stays).
  - Auctions you post or cancel are recorded at the auction house. Sales,
    expired auctions and auctions you won or bought are recorded from the
    mail, so they show once you open your mailbox; a sale mail counts once, also when you open it again or on
    another character. When the "buyer found" line comes while you are
    online, that moment's market price is kept for the comparison.
  - A trade with another player counts as a sale only when you gave items
    and got only gold back (and as a purchase the other way round). Gifts,
    swaps and handing items to your alts are kept in the Log but left out of
    the statistics. When one sum of gold pays for several different items,
    the gold is split by their market value for Sold and Gold, but that
    trade is left out of the price comparison and of Own sales.
  - **Own sales** is also an auction price source for the whole addon, asked
    after AnotherLedger scan: the average price you got per item.
  - **Trade log kept** (History options) sets how many days the Log keeps
    each entry (90 by default); the totals per item stay for **All**.

## Watch list

Put the drops you hope for on the watch list (a rare pet, a recipe, a
mount): each time you loot one, chat names it, the raid warning sound plays
and a gold line shows in the middle of the screen, also while the session
clock is stopped.

- Right-click an item in any list: **Watch this item** (or **Stop watching
  it**).
- `/al watch` with a shift-clicked item link or an item ID watches that
  item; with a text of at least 3 letters it watches every item whose name
  contains it (`/al watch Pattern:` for every pattern).
- `/al watch` alone lists the watch list, `/al unwatch` takes an entry off,
  and **Watched items** in the options (List) shows it to click entries off.

## Daily farm

The gold strip above the tabs names the subzone from your History (of all your
characters, like Zones) with the best gold per hour at today's prices, e.g.
`Daily: 1,240g/h  Wingrest (Waking Shores)`. Only saved sessions count (so
farming doesn't move today's pick), and a place needs 20 minutes of recorded
time by default. A place whose value comes mostly from items that sell poorly
is marked `slow selling`. With **Daily farm: my level** on, only places whose
map is meant for your current level count (places without a known level range
still do).

- **Click**: sets a waypoint to where you looted there (TomTom, or the map pin).
- **Shift-click**: opens History > Zones at that place (from the compact
  layout too: it switches to the full one).
- **Right-click**: shows the `/way` line to copy.
- **Hover**: time, value, exact gold per hour, the next two places and the
  slow sellers.

## Scanning the auction house

AnotherLedger can read the auction house itself, with or without TSM and
Auctionator:

- Open the auction house and click **AnotherLedger scan** just below its
  bottom right corner (or type `/al scan`, or use its key binding). The whole auction house is
  read in one go, a piece at a time so the game stays smooth; the button
  shows `Reading 42%` and chat says how many items got a price. Closing the
  auction house stops the scan and keeps what was read so far.
- The game allows one full scan every 15 minutes; the button shows the time
  left until the next one.
- Between full scans, the listings you open anyway (an item's or a trade
  good's offers) are recorded too, so items you shop for stay fresh.
- For every item it notes the **market value** (the average of the cheapest
  15% of the listed units, so one cheap auction doesn't set the price) and
  the **lowest price**, once per day. The price it uses is a recent average of
  those days: newer days count most, and a price older than 14 days is no
  longer used. The option **Scan price** picks market value or lowest price.
- Prices are kept per realm. Rows priced from a scan carry an age tag like
  cached prices.
- **Scan reminder** (on by default): when you open the auction house and your
  last full scan is more than a day old, one chat line suggests a scan (once
  per login). Not while TSM or Auctionator is loaded, as they bring their own
  prices.
- With TSM or Auctionator loaded, scan prices count for the items those have
  no price for (or for everything, if you pick **AnotherLedger scan** as the
  AH price source).

**Price trend**: every item tooltip in the game (and the rows of the ledger)
shows how the item's price moves, e.g. `AnotherLedger price trend +12% vs 60
days`: with TSM its market value against its 60 day average, else the newest
day of your own scans against the days before (it needs two days with a
scan, the newer one at most three days old). Rises of 5% or more show green,
drops red. **Price trend in tooltips** turns it off.

The order of auction prices is TSM, then Auctionator, then AnotherLedger scan,
then your own sales (Trade tab), then the last price seen earlier. If the
**AH price source** names an addon that isn't loaded, it shows as
`(not loaded)` and works like Auto until the addon is back.

## Options

Open them with the gear, a right-click on the minimap button, or Esc >
Options > AddOns > AnotherLedger. Hover any option for what it does and its
default. Changes apply at once. Drag the options window to move it; it opens
there from then on (until then, next to the ledger). **Opacity** and
**Brightness** apply to the options window as well. **Lock window** also
hides the resize grip; with **Snap to grid** the window snaps onto the lines
of the Edit Mode grid when you drop it close to one; anything that deletes
History asks first.

| Tab | Options |
| --- | --- |
| Window | Opacity, Brightness, Scale, Lock window, Snap to grid, Open on first loot, Open in instances, Hide in cities, Start hidden, Hide in combat, Minimap button, Reset minimap button |
| Prices | AH price source, TSM price, Scan price, Scan reminder, TSM sale info, Sells well / okay from, High / Medium volume from, Price refresh, Old price after, AH cut (5%), Auction from, Destroy values |
| List | Sort at login, Large amounts, Coin icons, Raw gold, Currencies, Hide worthless, Drop chance in tooltips, Price trend in tooltips, Top finds, Compact: last drops, Compact: item icons, Item icons, Price per unit, Hide Vendor tags, Ignored items, Kept items, Watched items, Scroll to new loot |
| Session | Keep session, Crafted and bought, Drop alert (gold), Alert sound, Session goal (gold), Session goal (minutes), Session summary in chat, Reset: ask for a note, Pause when AFK, Pause in cities, Session per instance, Session per zone, Zone change delay, Min. session length |
| History | Daily farm, Daily farm: min. time, Daily farm: my level, Zones: all characters, Export History, Clear History, History kept, Trade log kept, Mob data kept |
| Look | Font, Font outline, Font shadow, List text, Totals text, Section titles, Color preset, Text, Titles and totals, Hints, Vendor, Auction, Destroy, Tooltip labels, Window background, Window border, Button background, Reset colors, Delete color preset |
| Profiles | Profile, New profile, Copy profile, Rename profile, Delete profile, Reset profile, Export profile, Import profile |

**Color preset** changes the whole look at once: the window, the lines, the
tabs, the buttons and the scrollbar. **AnotherLedger** is the dark leather look,
**Blizzard** is black and bronze with red buttons like the game's own
windows, **Midnight** is dark blue and **TSM-style** is slate with a
gold-orange accent. Item
quality and coin colors always stay the game's own. Buttons are light on top
and fade darker toward the bottom, with a thin gold line inside the edge;
**Button background** sets their color. After a preset you can
still change single colors; the preset then shows "(edited)".

**Your own presets**: the last entry of **Color preset**, **Save as
preset...**, asks for a name and saves the colors you have now as a preset of
your own. It shows in the list under the built-in ones on every character and
profile. Saving under the name of one of your presets overwrites it after a
question. **Delete color preset** deletes the chosen preset if it is one of
yours; the colors stay as they are. An exported profile that uses one of your
presets carries its colors, so it looks the same on another account.

**Colors**: click a swatch to pick a color in the game's color picker (the
window changes while you pick, Cancel puts the old color back); right-click it
for the preset's color. **Reset colors** goes back to the chosen preset's
colors. Tooltips keep the game's dark tooltip on every preset.

**Session summary in chat** writes one line whenever a session is saved to
History: its length, main place, worth and gold per hour. **Reset: ask for a
note** opens the note box for the saved session after Reset (Escape skips
it). **History kept** counts per character and applies to all of them.
**Mob data kept** (All by default) keeps what each mob and node dropped only
for the sessions of the last 30, 90, 180 or 365 days: older sessions stay in
History, but no longer count in History > Mobs and the drop chances. Picking
a shorter time asks first. `/al stats` shows how much of the saved files
History, its mob data, the auction house scan, the Trade log and the price
cache take.

**Profiles**: every option is part of a profile, except **History kept**,
**Trade log kept**, **Mob data kept**, **Zones: all characters** and
**Minimap button**, which count for the whole account. Each character picks its own profile; new characters use **Default**.
Hover **Profile** to see which characters use the chosen one. **New profile**
starts from the defaults, **Copy profile** from the current one; Default can't
be renamed or deleted. **Reset profile** sets every option of the current
profile back to its default (it asks first). **Export profile** shows the
profile as one line of text to copy into a chat or a file; **Import profile**
opens a box to paste such a line, asks for a name (and before overwriting a
profile of that name) and switches to it. Settings an import does not
understand are skipped and counted in chat. Window position and size, filters,
the ignore and keep lists and History are not part of a profile. Updating to
the version with profiles starts with the default settings once.

**Font outline** (None, Thin, Thick) puts a dark outline around all AnotherLedger
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
session, and flight paths and time resting in a city or inn never count
(selling in Orgrimmar does not end your Badlands session). Loot from those
minutes still belongs to the old session. An empty session just starts its
clock over. While the clock is stopped nothing splits.

**Open on first loot**, **Open in instances** and **Hide in cities** show or
hide the window for you. Each only undoes what it did itself: close the
window in a dungeon or open it in a city and it stays that way.

**Pause in cities** (on by default) stops the clock while you are in a city or
inn, so selling and mailing don't lower your gold per hour; loot and gold
still count. The compact window says Resting. A clock you stopped yourself
stays stopped when you leave.

**Min. session length** (2 minutes by default) keeps very short sessions out
of History: a session with loot shorter than that just continues when a new
zone or instance or a fresh login would start a new one. After a login it
runs again and counts from that day, even if you had stopped it. An empty
session starts over as before. Reset always saves it; Off saves every
session.

**Hide Vendor tags** leaves the tag blank on rows that count at their vendor
price, so the Auction and Destroy rows stand out (most Bags rows are Vendor).

**Price per unit** shows the value of one item on a stack of several instead
of the whole stack; totals and tooltips stay the same.

**Key bindings**: Esc > Options > Key Bindings > AddOns > AnotherLedger has keys
for showing the window, switching compact / full, starting / stopping the
clock and scanning the auction house.

## Commands

| Command | Does |
| --- | --- |
| `/al` (or `/anotherledger`) | show or hide the window |
| `/al show`, `/al hide` | show or hide it |
| `/al start`, `/al stop`, `/al clock` | start, stop or switch the session clock |
| `/al compact` | switch between the compact and the full layout |
| `/al reset` | clear the session (saved to History; asks first when it holds many items or is worth 100 gold or more) |
| `/al keep on` / `off` | keep the session across logins |
| `/al scan` | read the whole auction house (the auction house must be open) |
| `/al tsm <price>` | the TSM price to use, e.g. `DBMarket` (also the option TSM price: pick a common one or Custom... to type any TSM price) |
| `/al export` | the History as CSV in a copy box |
| `/al export session`, `/al export zones`, `/al export mobs` | the session's items, every Zones place, or every mob and node, as CSV |
| `/al undo` | take back the last merge or delete in History (or the cleared History) |
| `/al watch <item \| text>`, `/al unwatch <item \| text>` | watch an item (link or ID) or every item whose name contains the text; `/al watch` alone lists them |
| `/al worth`, `/al worth forget <name>` | every character's net worth; drop a deleted character from All characters |
| `/al stats` | how much of the saved files each part takes (History, mob data, scan, Trade log, price cache) |
| `/al demo` | sample loot and temporary sample prices, to look at the window |
| `/al help` | list the commands |

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
- **Price age**: TSM doesn't say when it last scanned, so the age tag is the
  time since TSM last gave a price for that item. Auctionator tells how many
  days ago it last saw the item, so its prices carry an age tag from the first
  day on. An AnotherLedger scan price's tag is the time since the item was
  last seen on the auction house.
- **Languages**: English and German, picked from your client's language;
  other clients show English. Loot and money messages are read from the
  game's own texts, so they work in every client language. Slash commands
  stay in English (`/al watch`, ...).
- **Install**: unzip the release zip (it holds the libraries) into
  `World of Warcraft/<client>/Interface/AddOns/`, so the `.toc` ends up in
  `Interface/AddOns/AnotherLedger/`. From the source code, copy the
  `AnotherLedger/` folder of the repository there and add the libraries (see
  Requirements).
- **Bugs and ideas**: open an issue at
  <https://gitlab.com/mhhenjes/lootledger/-/issues>.
- **Coming from LootPrice** (the addon's old name): delete the old `LootPrice`
  folder. To keep your History, options and lists, rename the saved files
  `LootPrice.lua` to `AnotherLedger.lua` while the game is closed, in
  `WTF/Account/<account>/SavedVariables/` and in each character's
  `SavedVariables/` folder under `WTF/Account/<account>/<realm>/<character>/`.
