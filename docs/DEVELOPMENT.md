# LootLedger development

How the addon is built and how to extend it. The player guide is
[README.md](../README.md); the in-client checks and release steps are in
[CHECKLIST.md](CHECKLIST.md), ideas for later in [BACKLOG.md](BACKLOG.md).
`docs/superpowers/` holds the design specs and
plans of each feature (history; not kept in sync with the code).

## Setup

- Repository: <https://gitlab.com/mhhenjes/lootledger> (GitLab, branch
  `main`; changes go in through merge requests).
  `git clone https://gitlab.com/mhhenjes/lootledger.git`
- Lua 5.1 (the client's version). Local tests may run on 5.4, so avoid 5.2+
  features (`goto`, `//`, `table.unpack`, integer-only APIs).
- No build step: the client loads `LootLedger/*.lua` in the order of
  `LootLedger/LootLedger.toc`. Copy or symlink `LootLedger/` into
  `World of Warcraft/<client>/Interface/AddOns/`.
- Tests: `lua tests/run.lua` from the repo root (exit 1 on any failure).
  GitLab CI (`.gitlab-ci.yml`) runs them under Lua 5.1 and 5.4 on every push.

## Code layout

Files without `UI/` in their path are plain Lua: every client call is passed in
or looked up at call time, so the tests run them. `UI/` files touch WoW globals
only inside functions.

| File | Job |
| --- | --- |
| `embeds.xml` | loads the libraries the packager puts in `Libs/` (LibStub, CallbackHandler, LibDataBroker, LibDBIcon); the addon works without them. Each library is also an `## OptionalDeps` entry (the standalone addon's folder name), so a copy the player installed loads first and LibStub keeps the newest one; `UI/Broker.lua` looks them up through LibStub at login, never from `Libs/` directly |
| `Util.lua` | shared helpers (number checks, clamp, age text, chat output, `Util.setting(key, fallback)` for options read outside `Options.lua`) |
| `Locale.lua`, `Locales/` | translations (`ns.L`, English text as key); `Locales/deDE.lua` is German |
| `Money.lua` | coin text: letters or coin icons, colored, the "large amounts" style |
| `Theme.lua` | look and feel: colors, fonts, sizes, textures |
| `Tooltip.lua` | rich tooltips built as data (Daily, History, Zones, options) and rendered with the theme colors |
| `DB.lua` | saved-variable defaults and repair |
| `LootParse.lua` | loot, money and currency chat messages into links, copper and currencies; item keys with bonus IDs |
| `Mobs.lua` | loot, gold and looted count per mob (NPC ID) and gathering node (object ID); pure, Core feeds it from the loot window |
| `Prices.lua`, `Sources/` | price lookup with a saved cache; one file per price source (`Sources/Scan.lua`: LootLedger scan) |
| `Scan.lua` | LootLedger scan, pure: market value / lowest of a listing set, the daily average, the packed storage, the chunked reader of a full read, the 15-minute wait |
| `Session.lua`, `History.lua`, `Inventory.lua` | the running session, past sessions, bag and bank scans |
| `Options.lua` | option registry and the built-in options |
| `Profiles.lua` | settings profiles (per character), export / import strings |
| `View.lua` | the rows and totals a tab shows, History Zones, the Daily farm pick, the compact view |
| `Waypoint.lua` | the farm spot as a `/way` line, TomTom waypoint or the game's map pin |
| `Slash.lua`, `Demo.lua` | slash commands, `/ll demo` |
| `UI/Fonts.lua` | the addon's own font objects: typeface, px sizes, the font list |
| `UI/Widgets.lua` | bronze buttons, icon buttons, texts, lines, tooltips, menus |
| `UI/Coins.lua` | amounts in gold / silver / copper columns (list, compact drops, footer, Top finds) |
| `UI/Window.lua` | the frame: header rows, list area, footer, compact area, sizes per layout |
| `UI/Rows.lua`, `UI/Header.lua`, `UI/Summary.lua`, `UI/FilterBar.lua` | list rows, header buttons and clock, footer table and Top finds, filter bar |
| `UI/Tabs.lua` | tab registry and tab buttons |
| `UI/DailyFarm.lua`, `UI/Compact.lua` | the Daily strip; the compact layout's body |
| `UI/OptionsPanel.lua` | the options panel and the page in the game's options window |
| `UI/Minimap.lua`, `UI/Broker.lua` | own minimap button; LibDataBroker source and LibDBIcon button |
| `UI/ItemTooltip.lua` | drop chances in the game's item tooltips (hooked at login) |
| `UI/ScanButton.lua` | the LootLedger scan button on the auction house window |
| `UI/Export.lua` | the copy box (CSV, `/way` line) |
| `UI/Ledger.lua` | controller: builds the view of the shown tab and feeds the parts |
| `Core.lua` | events: login, loot capture, bank scan, redraw requests, session goals, ignore and keep lists, zone sessions, rate samples, History lists and undo (loads last) |
| `Bindings.xml` | key bindings (not in the `.toc`: the client loads it by name); each runs a `/ll` command, names in `Slash.BINDINGS` |

Data flow: `Core` events -> `Session` / `Inventory` -> `UI.Ledger.refresh`
builds a view with the shown tab's `build` (`View.lua`) -> every registered part
draws it. Nothing redraws while the window is hidden; it catches up on show.

## Extending: registries

Each of these is one call in one place; the UI never names them.

- **Option**: a default in `DB.defaults.settings`, then `Options.define({ key,
  category, type, label, tooltip, ..., apply })` in `Options.lua`. `label` is
  short (24 characters at most, a test checks it); `tooltip` says what it does
  and is shown on hover with the default. `category` is `window`, `prices`,
  `display` (tab List), `session`, `history`, `look` (fonts and colors) or
  `profiles`. Types: `slider` (`min`, `max`, `step`, `format`), `dropdown`
  (`choices` list or function), `checkbox`, `number` (whole number, empty =
  unlimited, optional `zeroText`), `text`, `color` (`"rrggbb"`), `button`
  (`action`). `tooltipExtra = function() -> text` adds a live line to the
  tooltip (the profile's characters). Values are validated by type and fall
  back to the default; `apply` runs on change and for the saved value at
  login. Read it with `Options.get(ns.db, key)`. Optional fields: `account =
  true` stores the value in `LootLedgerDB.account` (shared by every profile:
  `historyLimit`, `accountZones`, `minimapButton`); `get` / `store` functions
  keep the value elsewhere (the profile choice) and `Options.applyAll` skips
  such an option; `picked(db, value)` runs only on a choice in the panel
  (`Options.pick`), not at login (the color preset writes the single colors
  there). `intercept(db, value)` runs in `Options.pick` first; `true` sets
  nothing (TSM price's "Custom..." entry, `Options.CUSTOM`, opens a text box).
  A dropdown with `free = true` also keeps any typed string. A new kind of
  control is one factory in `Panel.WIDGETS` (`UI/OptionsPanel.lua`) plus its
  height in `Options.HEIGHTS`. The panel's column width, gaps and control
  sizes are `Theme.options`.
- **Price source**: a file in `Sources/` (in the `.toc` after
  `Sources\Sources.lua`) ending with `ns.Sources.register({ key, label, create
  = function(env, setting) return { name, get = function(itemID, link) ... end
  } end })`. It joins the lookup order and the AH price source dropdown.
  Optional: `createDisenchant`, `createMarket` and `present(env)` (its addon
  is loaded; `Sources.anyPresent` drives the login hint and turns the
  LootLedger scan off). See `Sources/Auctionator.lua`. A source's `get` may
  return the age of its price in seconds as a second value; the lookup then
  sets `ahAge` to it and `ahAged = true`, and the row shows the age tag and
  the old price rule like a cached price (`Sources/Scan.lua` does). The cache
  remembers such a price as seen `age` seconds ago, not now, so it never looks
  younger there than it is.
- **Tab**: `ns.UI.Tabs.define({ key, label, title, build = function(ctx)
  return view end, ... })` in `UI/Tabs.lua`; optional `sessionControls` (clock
  and buttons), `ticks` (rates follow the clock), `watches` (data kind that
  redraws it), `hasItem` and `subtabs` (see the comment at the top of the
  file). A view with its own `sorts` list keeps its own sort
  (`LootLedgerDB.sorts[slot]`, first `defaultSort`, see `Tabs.sortSlot` /
  `Ledger.currentSort`); the others share `LootLedgerDB.sort`. The filter bar
  reads and sets it through the accessor `Ledger.init` hands it. A view may
  set `headerInfo` (a short text the header shows right of the title on tabs
  without the session controls).
- **Slash command**: `ns.Slash.define({ name, help, run = function(arg) ...
  end })`; `help` shows in `/ll help`. A key binding is a `<Binding>` in
  `Bindings.xml` that runs the command (`SlashCmdList["LOOTLEDGER"]("name")`)
  plus its name in `Slash.BINDINGS` (and in the wiring test's allowed
  globals).
- **Row menu**: `Ledger.rowMenu(row)` returns the right-click entries of a row
  (`{ text, onClick, title = true }`), shown with `Widgets.openMenu(frame,
  entries, "button")`. Menu entries may carry their own `kind`.
- **Window part**: `ns.UI.Ledger.register(part)`; `part:Update(view, session,
  now)` on every full redraw, optional `part:Tick(...)` each second while the
  clock runs (keep it cheap).
- **Rich tooltip**: build it with `ns.Tooltip` (`new`, `pair`, `money`, `rate`,
  `para`, `labelled`, `section`, `note`, `warn`, `hint`) and show it with
  `ns.UI.Widgets.showTextTooltip(owner, tip)`. Colors are `Theme.colors.tip*`.
  A row's `hint` may be a function that builds the tooltip on hover
  (`Tooltip.resolve`); History and Zones rows do that.

## How things work

- **Color presets**: `Theme.presets` (`id`, `label`, `colors` = every
  `Theme.colors` key except `Theme.FIXED_COLORS` as `"rrggbb"`, optional
  `outline`). The `lootledger` entry is built from `Theme.colors` at load.
  `Theme.applyPreset(id)` sets them in place. The option `colorPreset` comes
  first in Colors, so `Options.applyAll` lays down the palette and the single
  colors go on top; picking a preset in the panel writes the single colors
  (and the outline). A color option's default is its preset's color
  (`Options.defaultFor(key, settings)`); `Options.presetEdited` drives the
  "(edited)" label. Item quality colors (`Theme.qualityColor`) and coin colors
  are fixed at the game's values. Tooltip colors (`tip*`) must stay readable on
  the dark game tooltip (`Theme.TOOLTIP_BG`); no panel color option sets them
  except Tooltip labels. tests/test_theme.lua checks completeness and contrast
  per preset.
- **Profiles** (`Profiles.lua`): `LootLedgerDB.profileUsers` maps
  `"Name-Realm"` to the profile it uses (noted at login by `Core.linkHistory`
  and on a switch; rename and delete keep it current) for the "Used by" line.
  `LootLedgerDB.profiles[name]` holds the
  options; `LootLedgerCharDB.profile` names the character's (Default when
  missing or deleted). At `ADDON_LOADED`, after `DB.migrateAccount`,
  `Profiles.init` points `LootLedgerDB.settings` at the active profile (filled
  with defaults except the single colors, whose default is the preset), so
  every `Options.get(ns.db, key)` reads it; at `PLAYER_LOGOUT`
  `Profiles.beforeLogout` clears that alias so the profile is saved once.
  The first login with profiles drops the old settings table
  (`profilesMigrated`). `Profiles.encode` / `decode`: `LP1:key=value;...`, only
  values that differ from the default, booleans `t` / `f`, numbers in full,
  `% ; =` percent-encoded; decode takes a value only if `Options.normalize`
  keeps it as it is. The import paste box is `UI/Export.lua` in edit mode
  (`Export.edit(title, onAccept)`).
- **Colors**: `Options.COLOR_OPTIONS` lists each color option with the
  `Theme.colors` keys it sets; its default in `DB.defaults.settings` must
  equal those theme colors (a test checks). `Theme.setColor` overwrites the r,
  g, b of the color table in place, so code that reads `Theme.colors` at draw
  time (tooltips, rows on refresh) follows by itself. Regions colored once at
  creation are remembered by `UI/Widgets.lua` (`setTextColor`, `line`,
  buttons, inputs, `applyBackdrop`) and `Widgets.recolor(changed)` paints them
  again; then `Window.applyLook` (opacity and brightness via
  `Window.paintLook`, for the ledger window and the options panel alike) and a
  refresh run. A text colored with a non-theme color (item quality) goes
  through `Widgets.setTextRGB`, which drops it from the list. Vendor / AH /
  Destroy labels in tooltips use `Theme.sourceColor(source)`
  (`Tooltip.money(..., source)`, `Rows.tooltipLines`, `Summary.tooltipLines`).
  The swatch opens the game picker through `Widgets.pickColor`.
- **Footer**: History and Zones show the same table as the Session tab: the
  listed sessions (or places) added up, rates over their recorded time
  (Zones: only subzones with time count in the rate, `timedRates` in
  `View.lua`). `view.scope` (set in `UI/Tabs.lua`) is the footer tooltip's
  last line: which sessions the numbers count. The raw gold row and whether
  gold counts in the totals both come from the option `rawGold`
  (`Util.rawGold()` -> counted, row; `Util.goldCounted()`). `DB.migrateSettings`
  turns the old `includeGold` / `showFooterGold` booleans into it (in
  `Profiles.point` and on profile import).
- **Item keys**: `LootParse.itemKey(link)` is the item ID for plain items and
  `"<id>:<sorted bonus IDs>"` for variants; every item map, the price cache and
  row keys use it. Price lookups take `(itemID, link)`.
- **Value** of a row is the best of vendor, AH and disenchant (`Prices.best`);
  it drives the sort `Value`, Top finds, the minimum filter and the drop
  alert. Items that can never be sold on the AH (bind types 1, 4, 7, 8, 9) are
  never counted as unpriced; an AH price a source still reports for them
  counts like any other. The `de` value is TSM's `Destroy` price (disenchant,
  mill or prospect), shown as `Destroy`; it counts whenever TSM is loaded,
  whatever the AH price source. A row with no vendor, AH or destroy value gets
  `worthless = true` and `Rows.rowText` shows a dash for it.
  `View.itemValue(item, lookup, ahMinGain)` is one item's value the same way
  (`Core.sessionValue`).
- **Mobs**: `LOOT_READY` reads every slot (`Mobs.readSlot`; `LOOT_OPENED` only
  when no `LOOT_READY` came: fast loot addons empty the window on
  `LOOT_READY`, before `LOOT_OPENED`), each `LOOT_SLOT_CLEARED` credits its
  slot to the sources (`Mobs.credit`), so loot left in a corpse counts for
  nobody. No kills: registering `COMBAT_LOG_EVENT_UNFILTERED` is forbidden for
  addons on this client (ADDON_ACTION_FORBIDDEN even inside the `pcall` of
  `Core.init`, so never add it to `events`; a wiring test guards this), and
  `kills` stays 0. Mob names come from name plates, target and mouseover, else
  the unit tooltip; a node takes the target of the player's last
  `UNIT_SPELLCAST_SENT` (the gathering cast) when the loot window opens within
  30 s (no tooltip for objects). No name is saved without one:
  `View.buildMobs` shows "NPC 12345" / "Object 1731" and takes the newest
  saved name (the first History entry's, the running session's over all). Coin
  slots wait for `settleLoot`, which scales them (`Mobs.scaleMoney`) to the
  copper the window actually brought (chat plus the money change), so a
  group's split counts your share. Recorded with the clock stopped too, never
  in demo mode (`Core.mobsCounting`); `History.snapshot` saves a session that
  has only mob loot. Drop chances: when the window is read
  (`Core.snapshotLoot`), `Mobs.noteWindow` counts each source GUID once in
  `seen` and each item once per GUID in `drops[itemKey]`, taken or not
  (per-login GUID sets in `mobState`). `View.buildMobs` sums them over the
  entries that have `seen` and sets `dropCount` / `dropSeen` on a mob's item
  rows; `View.dropChanceText`, `View.likelyDrops` and `Rows.tooltipLines` show
  them. The game's item tooltips (`UI/ItemTooltip.lua`, option
  `itemTooltipDrops`): `View.dropIndex` over `Core.zoneHistory()` plus the
  running session gives per item ID the mobs with `n` / `seen` (variants added
  up), `View.dropTooltipLines` the lines. The index is cached until the
  History key, the session's mob table or `Core.mobsVersion` (counted up per
  loot window read) changes. Hooked through
  `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ...)`,
  else `OnTooltipSetItem` of GameTooltip and ItemRefTooltip. Stored in
  `session.mobs` and History entries' `mobs`. `View.buildMobs` (History >
  Mobs) adds them up over the Zones entries (the running session included); a
  mob's `places` count corpses like `looted`, and the most counted is its main
  place. It values each mob's items like Zones (the entry's saved price, else
  live) and sorts by value, per loot (`perLoot` = value / `looted`) or name;
  `Ledger.mobOpen` is the opened mob. A mob row's `hint` builds its tooltip on
  hover (looted, value, gold, per loot, its top 3 places, its best drops). The
  view has no rates, so the footer shows no per hour column.
- **Automatic window** (`showOnLoot`, `showInInstance`, `hideInCities`):
  `Core.autoWindow` calls `Window.autoShow / autoHide(reason)`, which remember
  the reason (`shownBy` / `hiddenBy`); `autoUndo(reason)` reverses only its
  own action. The two marks are independent (a loot-opened window hidden and
  shown again by a city keeps `shownBy`), a hand show / hide clears both, and
  while either is set the saved hidden flag is not touched. During combat
  with Hide in combat (`Window.inCombat`) a show only marks the window for
  `combatShow`, and a hide cancels that.
- **Daily farm level** (`dailyFarmLevel`): the Ledger passes
  `opts.levelFits(mapID)` (`Core.levelFits` with `UnitLevel`) to
  `View.dailyFarm`, which skips a place with a position whose map answers
  `false`; the level is part of the farm cache key.
- **History headings**: sorted by Recent, `View.buildHistory` puts a heading
  row (`isHeading`, `periodKey` from `History.period`: a day this week, else
  an ISO week via `History.isoWeek`) over the visible sessions of each
  period. `Ledger.periodFold` holds the folded keys for the Lua session.
- **Bags footer**: `buildInventory` sets `totals.sellSplit` (best value of
  the rows not kept, by `bestKind`; the footer tooltip's Sell split). The
  Bags tab adds `View.addWorth(view, GetMoney())` (`totals.money`,
  `totals.worth`: the Summary rows Gold on hand / Net worth) and the free
  slots (`Inventory.freeSlots`) to the header; `PLAYER_MONEY` redraws it.
- **Resting** (`cityPause`, `Core.checkRest` on `PLAYER_UPDATE_RESTING`):
  `Session.rest` keeps `running` true but folds the time into `elapsedBase`
  and stops the place time (`resting = true`); `Session.wake` restarts it.
  Loot and gold still count. Stop, reset and login (`resume`) handle it.
- **Short sessions** (`minSessionMinutes`, `Core.isShort`): a session with
  loot shorter than that is not archived by Session per zone / instance; at
  login a short saved session with loot (its `elapsedBase`; demo sessions
  never) is kept, then started like a new one: `afkPaused` cleared, running,
  `startedAt` = the login. Empty sessions start over as before. `/ll reset`
  and the Reset button always archive.
- **Value rules** apply at lookup, never to saved History prices: `Prices.new{
  rules = ... }` cuts 5% off `ah` (option `ahCut`; the gross price stays in
  `ahGross`, and a row with it gets `ahCut = true` for the tooltip) and drops
  `de` when `Prices.destroyAllowed(destroyMode, kind, own, all)` says no;
  `deBlocked = true` then tells makeRow and `History.snapshot` to skip the
  `de` saved at loot time too. The kind comes from the item class
  (`Prices.destroyKind`, via `GetItemInfoInstant`), the professions from
  `db.professions[character]` (`Core.noteProfessions` at login, where an empty
  read keeps a saved set, and on `SKILL_LINES_CHANGED`; the union of all
  characters is cached until they change, and the rules table until `ahCut` or
  `destroyMode` does). The cache stores raw prices. `Prices.best(vendor, ah,
  de, minGainPct)` is the one best-value pick (View, History, Core): the AH
  counts only when it beats vendor by the `ahMinGain` percent. A History entry
  keeps the Auction from it was saved with (`ahMinGain`): `History.totals`
  takes ignored items off at it (`History.gainOf`, 0 for older entries) and an
  opened session values its items the same way. A saved price (`item.price`,
  History items) has `cut = true` when its `ah` is after the AH cut
  (`Session.setPrice`, `History.snapshot`; a merge keeps it only when every
  part was), and only those rows get the cut note.
- **Money** is always copper. `Money.format` / `formatColored` follow the
  `goldDisplay` style and the coin-icon setting (`Money.setIcons`).
- **Raw gold** comes from `CHAT_MSG_MONEY` (`YOU_LOOT_MONEY`,
  `LOOT_MONEY_SPLIT`, the first amount of `YOU_LOOT_MONEY_GUILD` and
  `LOOT_MONEY_SPLIT_GUILD`) and `QUEST_TURNED_IN`; filters never touch it.
  Backstop: between `LOOT_OPENED` and one second after `LOOT_CLOSED`, a rise
  of `GetMoney()` beyond what the messages counted is recorded too
  (`Core.missingGold`), so a message form the parser does not know still
  counts, and never twice.
- **Places**: each loot and gold event notes its zone (an instance with its
  difficulty is a zone of its own) and subzone, and, outside instances, the
  map position. Time per place only counts while the clock runs. Sessions
  saved before places existed show under `No time recorded` (one place) or
  `Unknown place` (several); both sort last (`row.sortsLast`). The
  difficulty name comes from `GetInstanceInfo`, else
  `GetDifficultyInfo(difficultyID)`, else the last one seen in that instance
  (`Core.placeOf(env, remembered)`), so a loading screen that reports none
  does not split a dungeon in two. The instance key ("Session per instance")
  is the instance name alone.
- **Stopped clock**: `Core.recordLoot`, `recordGold` and `recordCurrency`
  ignore events while the clock is stopped and say so once in chat per stop.
  The Mobs record does not depend on the clock (see Mobs).
- **Row lines**: line 2 of a row is `row.detail` when set (History sessions:
  length, gold per hour, item count, place; Zones places: time, gold per
  hour, item count),
  else the TSM sale info. Rows without `quantity` show none. `view.empty`
  (`View.emptyText`) is the text `Rows` shows centered in an empty list.
- **History sessions**: `View.buildHistory` sorts only with `opts.sort` set
  (`ah`, `recent`, `perHour`; others work as `ah`). Search (start, length,
  place) and minimum value pick sessions; the opened one always shows, its
  items filtered by quality only. A row's value is the items' best plus raw
  gold (`Util.goldCounted()`). Row names use `opts.shortDate`
  (`History.shortDate`), tooltips `opts.formatDate`.
- **Zones time**: a zone's time and the footer's rates count every subzone's
  time, also subzones whose loot the filter hides or that have none.
- **Daily farm** (`View.dailyFarm`): saved History only, valued at current
  prices, places with at least the minimum time, quest items and the
  no-time / unknown places left out, filter bar ignored. `slow` when more than
  half the AH value comes from items with a bad sale rate. The spot is the
  averaged loot position on the map looted most (clamped to the map). The
  Ledger caches the pick until History, its options (including the price
  source and TSM price) or the price interval change. `DailyFarm.wire(button)`
  gives the strip and the compact line the same clicks, hover and drag.
- **History prices**: an entry keeps the unit prices its totals were made of
  (`items[key].price`, archive time, loot time as fallback). An opened session
  lists its items at those (`opts.savedPrices`), so they add up to its row;
  Zones and the Daily farm value the same loot at today's prices.
- **Confirmations** go through `Widgets.confirm(text, button, onAccept,
  onCancel)` (one shared popup). An option can ask before a value is stored
  with `confirm = function(value) return question or nil end` (History kept).
- **CSV export** (`History.csv`): one line per session, amounts in gold with
  four decimals, then the currencies (`Name x3; Other x1`) and the note.
  `/ll export session` writes `View.itemsCsv` of an unfiltered `View.build`,
  `/ll export mobs` `View.mobsCsv` (every mob of an unfiltered
  `View.buildMobs`, by value),
  `/ll export zones` `View.zonesCsv` (every subzone from `View.zoneTable`,
  quest items left out). Fields go through `History.csvField`.
- **Ignore list** (`LootLedgerDB.ignored = { [itemID] = name }`, Core
  `ignoreItem` / `unignoreItem` / `ignoredList`): `opts.ignored` makes
  `collect` skip those items, so every list, total, Top find, compact drop,
  Zones place and the Daily farm leave them out; `Core.sessionValue`, the drop
  alert and the goals too. They stay recorded. History rows subtract them at
  their saved unit prices (`History.totals(e, ignored)`).
- **Keep list** (`LootLedgerDB.kept`, Core `keepItem` / `unkeepItem` /
  `keptList`; both lists are made by `itemList(field)` in `Core.lua`):
  `opts.kept` makes `View.buildInventory` set `row.kept` and
  `totals.kept` / `totals.sellable` (only while a listed row is kept).
  `Summary.tableLayout` then shows the rows `items`, `kept`, `sellable`;
  `Rows.rowText` adds `(kept)` after the name. The row menu entry only shows
  on an inventory view.
- **Heartbeat**: one `C_Timer.NewTicker` of `HEARTBEAT_SECONDS` (5 s) runs
  `Core.heartbeat`: the time goal, the zone delay and the rate samples.
- **Session per zone** (`zoneSession`, `zoneSessionMinutes`): the pure
  `Core.zoneSwitch(state, place, now, away, grace)` keeps the session's
  zone and a pending new one (`Core.placeOf` labels, so an instance is a zone
  too); it says yes once the player stayed `grace` seconds in the new zone,
  being away (a flight, `UnitOnTaxi`, or resting, `IsResting`) or a return
  clears the pending zone.
  `Core.checkZone` runs it on the zone events, loading screens and the
  heartbeat; it splits only with the option on and the clock running (an
  empty session is reset without a chat line). `checkInstance` sets the zone
  after its own split, so one move never splits twice.
- **Gold per hour graph**: `Core.sampleRate` (heartbeat) adds
  `{ t = elapsed, v = worth }` to `session.samples` once per
  `Session.sampleStep` of running clock (`Session.addSample`: past
  `SAMPLES_MAX` every other sample goes and the step doubles; cleared by
  `Session.reset`, not saved to History). `View.rateGraph` turns them into
  per-stretch rates (`view.graph`, `compact.graph`), `View.addRateGraph`
  into tooltip lines; `Tooltip.bars` / `Tooltip.barsText` draw the bars as
  inline textures (`Theme.textures.graphBar`, `sizes.graphHeight` /
  `graphWidth`). `Widgets.addTooltipLines` adds a rich tooltip to a shown
  GameTooltip (the Session footer tooltip).
- **Session goals** (`goalGold`, `goalMinutes`): `Core.checkGoals(withValue)`
  after loot and gold (gold goal) and on the heartbeat (time goal); the pure
  `Core.goalsReached` decides, `session.goalsNoted` (cleared by
  `Session.reset`) keeps each goal from being announced twice. `opts.goal`
  (copper) gives `view.goal` / `compact.goal` = `{ value, goal }`: the
  unfiltered total like compact; `Summary.notesText` shows the percent.
- **Notes**: `entry.note` (`History.setNote`: trimmed, one line, at most
  `History.NOTE_MAX` characters, cut on UTF-8 boundaries) follows the start on
  line 1 of the session row and is part of its search text. Entered through
  `Widgets.prompt` (the shared text popup).
- **Account-wide History**: `LootLedgerDB.histories = { ["Name-Realm"] = list
  }`. At login `Core.linkHistory` adopts the character's old
  `LootLedgerCharDB.history` into it (`History.adopt`, no duplicates by start)
  and points `ns.chardb.history` at that list; `PLAYER_LOGOUT` drops the alias
  so the list is saved once. Without a character name (tests) History stays
  per character. `Core.zoneHistory()` gives Zones (`ctx.zoneHistory`), the
  Daily farm and the Zones export every character's lists (`History.combine`,
  with a change key for the farm cache) or, with `accountZones` off, the
  character's own.
- **Merge**: `History.merge(a, b)` builds a new entry from two sessions
  without touching them: earliest start, summed elapsed time (the gap does not
  count), gold, values and currencies; items by key with quantities added and
  prices averaged by quantity; Zones sub-zones summed (time, gold, items,
  map cells); places of the more valuable session first; notes joined with
  ` / `. `Core.mergeHistory(index)` replaces the session at `index` with its
  merge with `index + 1` (the next older one); `Ledger.mergeHistory` keeps the
  opened session open.
- **Undo**: `Core.deleteHistory`, `Core.clearHistory` and `Core.mergeHistory`
  push `{ restore = entries, drop = merged | nil }` on a stack kept for the
  login; `Core.undoDelete` (`/ll undo`) removes `drop` (a merge) and puts
  `restore` back in start order (`History.restore`).
- **Scroll memory**: `Ledger` keeps `list.offset` per tab / sub-tab for the
  login (`rememberScroll` / `restoreScroll` around tab switches).
- **Price per unit** (`unitPrice`): `Rows.rowText` shows the counted source's
  unit value on rows with a quantity above 1.
- **Compact** (`View.buildCompact`) ignores the filter bar: every item plus raw
  gold when it counts (`Util.goldCounted()`); the last drops come from
  `session.recent` (`dropLimit` is the option; `Compact.titleText` hides the
  title at 0). `recent` is `View.recentRate(samples, elapsed, total)`: the
  gold per hour from the newest rate sample at least `View.RECENT_SECONDS`
  (15 min) old to now, shown right of the drops title (`Compact.recentText`)
  and in the hover. With a goal, `Compact.goalFraction` sizes a gold bar
  (`sizes.compactGoalBarHeight`) over the divider; it follows a resize on the
  next redraw. It also returns `items`, `gold`, `elapsed`, `top`, `goal` and
  `graph` for the hover breakdown (`Compact.hint`) over the rate and total.
- **Hide worthless** (`hideWorthless` -> `opts.hideWorthless`): `collect` and
  the compact drops skip `row.worthless` rows; totals are unchanged (they are
  worth 0).
- **Unpriced first**: `row.unpriced` (no AH price, not bound) is what the
  footer counts. A click on the notes line (`Summary.attach`, mouse only
  while something is unpriced) runs `Ledger.toggleUnpricedFirst`;
  `opts.unpricedFirst` wraps the item sort (`unpricedFirst(inner)` in
  `View.lua`) and `Summary.notesText(view, true)` says "listed first".
- **No price addon** (`Core.priceAddonHint`, at login): a source spec's
  `present(env)` (TSM, Auctionator) says its addon is loaded
  (`Sources.anyPresent`); without one a chat line once per account
  (`LootLedgerDB.priceHintShown`, cleared when one is found again).
- **Reset note** (`resetNote`): `Core.resetSession` returns the saved entry
  (`Core.archiveSession` does); the Reset button and `/ll reset`
  (`Header.requestReset` -> `doReset`) then open `Ledger.editNote(entry)`.
  The automatic splits call `Core.resetSession` directly and never ask.
- **Fonts**: `UI/Fonts.lua` makes the addon's own copies of the game fonts
  (`LootLedger<Key>`) in `Ledger.init`; typeface and px sizes change live and
  the window re-lays itself out. The source tag font is pinned to Arial Narrow
  (`Theme.fontFiles`). On retail `SetFont` returns nothing, so only an explicit
  `false` means a font cannot load.
- **Font outline / shadow** (`fontOutline`, `fontShadow`): `Fonts.applyStyle`
  sets the outline flags (`Fonts.flags`; "none" keeps the game font's own
  flags) and the shadow (`Fonts.shadowOf`: the game font's shadow, saved at
  install, or 1 px black when it has none) on every own font object, the
  pinned source tag font too. `setFace` uses the current outline, so a size or
  typeface change keeps it. An outline widens every glyph (about 1 px Thin,
  2 px Thick: `Theme.sizes.outlineGlyphPx`), so `Fonts.applySizes` adds that
  to the footer's glyph estimates (`summaryCharPx`, `markerCharPx`) and the
  clock (`timerWidth`, `timerGlyphs`; `Header`'s part has a `Relayout`).
  Outlined text and its coin icons also draw a few px past the end the client
  measures, and the client centers outlined text a little left: per outline,
  `outlineOverhangPx`, `outlineTagShiftPx` and `outlineTagPadPx` (measured
  from client screenshots) become `textOverhang` (room right of an amount:
  `Rows.labelGap`, the compact total and drops, the footer columns and
  `Summary.tableWorstWidth`), `tagTextShift` and `tagPadExtra` (the source
  tag's text and height). The tag's edges draw above its text. The
  option then calls `Ledger.relayout` now and on the next frame (`C_Timer.After
  0`), when the client has drawn the new font; `list:Relayout` empties the
  pooled rows' texts first, as a FontString given the same text again can
  keep its old width.
- **Coin columns** (`UI/Coins.lua`): the amounts of the list rows, compact
  drops, footer table and Top finds are cells with one right-aligned
  FontString per unit (`Money.parts`) plus one for a plain text (em dash,
  `bound`, `?`). `Coins.align(cells)` lays out the shown cells of one column
  together: each unit column is as wide as its widest part, a unit no cell
  uses takes no room (`Coins.columns`), `coinGap` between columns. So every
  coin of a kind lines up down the column, and the parts are short enough
  that an outlined font's width error stays small. `Rows.rowText`,
  `Summary.rowTexts` and `Summary.topLines` hand over the number (`copper`,
  `valueCopper`, `rateCopper`) next to the text; a cell's `GetText` returns
  the whole amount as one text. The compact rate and total stay one text.
- **Source tags** (Vendor / Auction / Destroy): one widget for the list rows
  and the compact drops, `Rows.sourceTag` / `Rows.setSourceTag`. Four edge
  textures in the source color (tracked, so a color option recolors them
  live). A thin line drawn from a fractional screen position comes out 0, 1
  or 2 px thick, so everything about the box is whole screen pixels: its size,
  edge thickness (`rowTagEdge`) and text offset are computed in pixels
  (`Widgets.pixelSize`, from `PixelUtil.GetPixelToUIUnitFactor`), and
  `Widgets.snapPoint` anchors it and then moves it by less than a pixel onto
  the grid (read back with `GetLeft` / `GetTop`). The window moves the boxes
  off the grid again, so `Window.endDrag` redraws. Height
  (`Rows.sourceBoxPixels`): font + `rowTagPadY` px above and below, one pixel
  more when the letters (`rowTagCapRatio` of the font) would sit half a pixel
  off; the text line sits at a whole pixel offset from the top. Width: the
  widest tag (`Rows.sourceBoxWidth`, from `list.measured.source`, also kept as
  `Rows.widestSource` for the compact drops), text centered.
  `rowLineInset` keeps the box clear of the separator above the row; the
  separators are whole pixels thick too.
- **Snap to grid** (`snapToGrid`): `Window.endDrag` runs the pure
  `Window.snapToGrid` with the Edit Mode grid spacing (lines through the screen
  center and every spacing from it, in UIParent units, converted to the
  frame's scale) and `Theme.sizes.gridSnapDistance`; each axis moves its
  nearest edge or center onto a line within that distance. Unknown spacing =
  no snap.
- **Redraws**: the clock and rates every second (running clock, ticking tabs or
  compact); prices and age tags at the **Price refresh** interval on every tab
  while the window is shown, clock running or not; everything at once on loot,
  gold, bag / bank changes, filters, sorts and options. Several loot messages
  in one frame share one redraw.
- **Button text**: `Widgets.buttonColors` passes the label color through
  `Theme.readableOn(color, fill)`: below `Theme.MIN_TEXT_CONTRAST` against the
  button background it turns near-black or white (the arrow follows).
- **LootLedger scan** (`Scan.lua`, `Sources/Scan.lua`, Core's scan section,
  `UI/ScanButton.lua`): only while no source's `present` is true and the
  client has `C_AuctionHouse.ReplicateItems` (`Core.scanAvailable`).
  `Core.startScan` (the button, `/ll scan` through `Core.scanCommand`, which
  prints why it can't) needs the auction house open, a known realm key and
  the wait over
  (`Scan.waitLeft(LootLedgerCharDB.scanAt, now)`, `Scan.WAIT` = 900 s). It
  calls `ReplicateItems`, stamps `scanAt` and waits for
  `REPLICATE_ITEM_LIST_UPDATE`; without it within 60 s it restores the old
  `scanAt` and says the game did not answer. The event starts
  `Scan.newReader` over `GetReplicateItemInfo` / `GetReplicateItemLink`:
  `Scan.CHUNK` (2000) entries per `C_Timer.After(0)`, unit price = buyout /
  count, grouped per `LootParse.itemKey` (the item ID when the link is not
  loaded; such an item ID set is dropped when the same read has variant keys
  of that item, as it would mix the variants), same unit prices merged, no
  buyout / battle pets (item 82800, never priced, also not by search results
  or lookups) skipped. `AUCTION_HOUSE_CLOSED` stops it; `onDone` commits what it has
  (`Scan.commit`) and sets the bucket's `lastFull` only for a complete read.
  Passive: full `COMMODITY_SEARCH_RESULTS_UPDATED` /
  `ITEM_SEARCH_RESULTS_UPDATED` sets (the `HasFull*` check) are committed the
  same way; browse results are not (their minimum mixes the variants).
  `Scan.listingValues`: market = the average unit price of the cheapest 15%
  of the units (at least one), lowest = the cheapest unit. `Scan.record`
  keeps per key today's `m` / `l` and time `t` and the weighted average `am` /
  `al` of the days before up to day `ad` with its total weight `aw`: every day
  weighs 1 on its own day and halves every 5 days after, so a later day folds
  the old day in as `(am * aw * w + m) / (aw * w + 1)` with `w = 0.5 ^ (days /
  5)`; a same-day value replaces `m` / `l`. `Scan.price` blends the average
  and today the same way and
  answers nothing past `Scan.MAX_AGE` (14 days, pruned at login by
  `Core.pruneScan`). Stored packed (`Scan.pack` / `unpack`: base-36 integers
  joined by `,`), so a full scan stays small in the saved file. The source
  reads `Scan.bucket(ns.db, Scan.currentRealmKey())` (price cache key plus
  `GetRealmName()`) live and the option `scanPrice`. The reminder
  (`scanReminder`) prints once per login on `AUCTION_HOUSE_SHOW` when the
  last full read is missing or older than a day. `Core.priceAddonHint` stays
  quiet while the realm's bucket has items. The button (`ScanButton.text`:
  ready / `Reading 42%` / the wait as m:ss) is made on the first show, set as
  `Core.onScanChange` and counts down with a 1 s ticker while shown.
- **Price cache**: prices last seen more than 30 days ago are dropped at login
  (`Prices.CACHE_MAX_AGE`). `/ll demo` seeds temporary fake prices that reset
  and logout remove.

## Saved state

- `LootLedgerDB` (account): `profiles` (options per profile; `settings` is the
  active one while logged in and is not saved), `account` (account-wide
  options), `renamed` (old profile name -> new, so other characters follow a
  rename at their next login), `minimapAngle`, `profilesMigrated` /
  `accountMigrated` (one-time migrations), `window` (position, full size
  `width` / `height`, compact size `compact`, `hidden`), `mode` (layout),
  `tab` and `subtab`, `filter`, `sort` (item lists) and `sorts` (History
  Sessions / Zones), `optionsWindow` (where the options panel was dragged to,
  `{ x, y }` from the screen center), `profileUsers`, `minimapIcon`
  (LibDBIcon), `cache` (prices), `ignored` (the ignore list), `kept` (the keep
  list) and `histories` (every character's History, see "Account-wide
  History"), `professions` (`"Name-Realm"` -> `{ enchanting = true, ... }`,
  for the option Destroy values), `scan` (LootLedger scan: `[realm key] = {
  lastFull, items = { [itemKey] = packed } }`, see LootLedger scan).
- `LootLedgerCharDB` (character): the session (items, gold, places with time,
  positions, recent drops, the goals already announced and the rate samples)
  and the bank scan, `profile` (the name of the profile it uses) and `scanAt`
  (the last full auction house read, for the game's 15-minute wait).
  `history` is only written here by versions before the account-wide History.
- The addon was called LootPrice. At `ADDON_LOADED`, Core takes over
  `LootPriceDB` / `LootPriceCharDB` when the new tables are missing (a player
  renamed the old saved files), then clears the old globals.

## Events

`CHAT_MSG_LOOT`, `CHAT_MSG_MONEY`, `CHAT_MSG_CURRENCY`, `QUEST_TURNED_IN`,
`GET_ITEM_INFO_RECEIVED`, `LOOT_READY` / `LOOT_OPENED` / `LOOT_CLOSED`,
`PLAYER_ENTERING_WORLD`, `PLAYER_LOGOUT`, `BAG_UPDATE_DELAYED`,
`BANKFRAME_OPENED` / `BANKFRAME_CLOSED`, `PLAYERBANKSLOTS_CHANGED` /
`PLAYERREAGENTBANKSLOTS_CHANGED`, `PLAYER_REGEN_DISABLED` /
`PLAYER_REGEN_ENABLED`, `PLAYER_FLAGS_CHANGED`, `ZONE_CHANGED` /
`ZONE_CHANGED_INDOORS` / `ZONE_CHANGED_NEW_AREA`, and the
`SKILL_LINES_CHANGED`, `PLAYER_UPDATE_RESTING`, `PLAYER_MONEY`, the Mobs
events (`LOOT_SLOT_CLEARED`, `UNIT_SPELLCAST_SENT`, `NAME_PLATE_UNIT_ADDED`,
`PLAYER_TARGET_CHANGED`, `UPDATE_MOUSEOVER_UNIT`; never
`COMBAT_LOG_EVENT_UNFILTERED`, which is forbidden on this client), the
`MERCHANT_*`, `MAIL_*`, `TRADE_*`, `AUCTION_HOUSE_*` show / closed events
(purchases are not loot; the auction house ones also drive the LootLedger
scan), and `REPLICATE_ITEM_LIST_UPDATE`, `COMMODITY_SEARCH_RESULTS_UPDATED`,
`ITEM_SEARCH_RESULTS_UPDATED` (LootLedger scan). An event the client does not know is skipped.

## Tests

`tests/test_*.lua` get the harness as `...` (`h.test`, `h.eq`, `h.near`,
`h.load`). `tests/test_wiring.lua` boots the whole addon from the `.toc`
against a stub client (fake frames) and drives real events; add a wiring test
for anything that crosses files. To keep its ~170 boots fast, the `.toc` files
are compiled to bytecode once per run (each boot only loads them into a fresh
env) and all fake frames share one method table; keep new fake methods in that
shared table. The real UI can't be tested outside the client:
anything relying on an unconfirmed client API gets an
`UNVERIFIED (check in client)` comment and a line in
[CHECKLIST.md](CHECKLIST.md).

## Localization

Texts go through `ns.L` (English text as key). A language is one
`Locales/<locale>.lua` with `ns.Locale.register("<locale>", { ["English"] =
"translation" })`, listed in the `.toc` after `Locale.lua`.
`tests/test_locale.lua` fails on a German entry the code no longer uses.

## Packaging

The BigWigs packager runs from the repo root (it needs a git checkout as its
top directory) with the root `.pkgmeta`. It copies the repo to
`.release/LootLedger/`, and `move-folders` makes the inner `LootLedger/` folder
the one addon folder of the zip (the docs, tests and CI files are ignored). It
fetches the libraries into `LootLedger/Libs/` (git-ignored) and fills in the
`.toc` version from the git tag. CI builds the zip on every tag (job `package`)
and offers a manual `package-dry-run` on any branch, which lists the zip's
files in the job log. CurseForge upload needs the CI variable
`CF_API_KEY` and `## X-Curse-Project-ID: <id>` in the `.toc`. The release
steps are in [CHECKLIST.md](CHECKLIST.md).
