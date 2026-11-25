# AnotherLedger development

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
- No build step: the client loads `AnotherLedger/*.lua` in the order of
  `AnotherLedger/AnotherLedger.toc`. Copy or symlink `AnotherLedger/` into
  `World of Warcraft/<client>/Interface/AddOns/`.
- Tests: `lua tests/run.lua` from the repo root (exit 1 on any failure).
  GitLab CI (`.gitlab-ci.yml`) runs them under Lua 5.1 and 5.4 on every push.
- Lint: `luacheck AnotherLedger` (config `.luacheckrc`; CI job `lint`). It
  flags leaked or misspelled globals, unused variables and overwritten
  values. A WoW API the code starts to read goes in `read_globals`, a global
  it writes in `globals`. Shadowing and unused arguments are not checked.

## Code layout

Files without `UI/` in their path are plain Lua: every client call is passed in
or looked up at call time, so the tests run them. `UI/` files touch WoW globals
only inside functions.

| File | Job |
| --- | --- |
| `embeds.xml` | loads the libraries the packager puts in `Libs/` (LibStub, CallbackHandler, LibDataBroker, LibDBIcon); the addon works without them. Each library is also an `## OptionalDeps` entry (the standalone addon's folder name), so a copy the player installed loads first and LibStub keeps the newest one; `UI/Broker.lua` looks them up through LibStub at login, never from `Libs/` directly |
| `Util.lua` | shared helpers (number checks, clamp, deep copy, age text, chat output, `Util.setting(key, fallback)` for options read outside `Options.lua`) |
| `Locale.lua`, `Locales/` | translations (`ns.L`, English text as key): deDE |
| `Money.lua` | coin text: letters or coin icons, colored, the "large amounts" style |
| `Theme.lua` | look and feel: colors, fonts, sizes, textures |
| `Tooltip.lua` | rich tooltips built as data (Daily, History, Zones, options) and rendered with the theme colors |
| `DB.lua` | saved-variable defaults and repair |
| `LootParse.lua` | loot, money and currency chat messages into links, copper and currencies; item keys with bonus IDs |
| `Mobs.lua` | loot, gold and looted count per mob (NPC ID) and gathering node (object ID); pure, Core feeds it from the loot window |
| `Prices.lua`, `Sources/` | price lookup with a saved cache; one file per price source (`Sources/Scan.lua`: AnotherLedger scan, `Sources/Sales.lua`: Own sales) |
| `Scan.lua` | AnotherLedger scan, pure: market value / lowest of a listing set, the daily average, the packed storage, the chunked reader of a full read, the 15-minute wait |
| `Trade.lua` | Trade section, pure: the per-realm store (log, totals, open posts, mail keys), trade kinds, mail recording, statistics, the own sale price |
| `Session.lua`, `History.lua`, `Inventory.lua` | the running session, past sessions, bag and bank scans |
| `Options.lua` | option registry and the built-in options |
| `OptionsLook.lua` | Appearance options that set the look: single colors, color presets, skin and its parts |
| `Profiles.lua` | settings profiles (per character), export / import strings |
| `View.lua` | the rows and totals a tab shows (Session, Inventory's Bags and Bank, History sessions), the compact view, the session CSV; its shared helpers are `View.internal` (only for the two files below) |
| `ViewZones.lua` | History Zones and Mobs, the Daily farm pick, their CSV export, the drop index of the item tooltips |
| `ViewTrade.lua` | the Trade tab's Items and Log views |
| `Waypoint.lua` | the farm spot as a `/way` line, TomTom waypoint or the game's map pin |
| `Worth.lua` | pure: every character's saved net worth (`AnotherLedgerDB.worth`), the list and sum for All characters, `/al worth forget` |
| `Stats.lua` | `/al stats`, pure: the estimated saved-file size of each part (History and its mob data, scan, Trade log, price cache, the character file, the rest) |
| `Slash.lua`, `Demo.lua` | slash commands, `/al demo` |
| `UI/Fonts.lua` | the addon's own font objects: typeface, px sizes, the font list |
| `UI/Widgets.lua` | two-tone buttons, icon buttons, texts, lines, tooltips, menus |
| `UI/Coins.lua` | amounts in gold / silver / copper columns (list, compact drops, footer, Top finds) |
| `UI/Window.lua` | the frame: header rows, list area, footer, compact area, sizes per layout |
| `UI/Rows.lua`, `UI/Header.lua`, `UI/Summary.lua`, `UI/FilterBar.lua` | list rows, header buttons and clock, footer table and Top finds, filter bar |
| `UI/Tabs.lua` | tab registry and tab buttons |
| `UI/DailyFarm.lua`, `UI/Compact.lua` | the Daily strip; the compact layout's body |
| `UI/OptionsPanel.lua` | the options panel and the page in the game's options window |
| `UI/Minimap.lua`, `UI/Broker.lua` | own minimap button; LibDataBroker source and LibDBIcon button |
| `UI/ItemTooltip.lua` | drop chances in the game's item tooltips (hooked at login) |
| `UI/ScanButton.lua` | the AnotherLedger scan button on the auction house window |
| `UI/RowSwitch.lua` | switches at the right end of the sub-tab row: the Trade tab's 7 days / 30 days / All (`UI.TradePeriod`, db.tradePeriod) and History > Mobs' All / Mobs / Nodes (`UI.MobKind`, db.mobKind) |
| `UI/Export.lua` | the copy box (CSV, `/way` line) |
| `UI/Ledger.lua` | controller: builds the view of the shown tab and feeds the parts |
| `Core.lua` | events: login, loot capture, bank scan, redraw requests, session goals, zone sessions, rate samples; `Core.events` is the event table every Core file adds to; `Core.refreshUI` / `requestRefresh` / `dataChanged` for the other Core files |
| `CorePrices.lua` | Core's price section: the cache key (`Core.cacheKey`, `renewKey`), `Core.buildPrices`, the no-price-addon hint, destroy professions, the price trend, `lookupPrice` / `unitValue` / `sessionValue` |
| `CoreLists.lua` | Core's item lists: ignore, keep and watch lists, the watch alert |
| `CoreHistory.lua` | Core's History section: every character's History list, delete / clear / merge, `/al undo` |
| `CoreScan.lua` | Core's AnotherLedger scan section: `/al scan`, the full read, the passive search results, the reminder |
| `CoreTrade.lua` | Core's Trade section: auction post / cancel hooks, the sold line, auction mails, player trades |
| `Boot.lua` | loads last: `Core.init()` in the client (registers every handler of `Core.events`) |
| `Bindings.xml` | key bindings (not in the `.toc`: the client loads it by name); each runs a `/al` command, names in `Slash.BINDINGS` |
| `Media/Skins/*.tga` | skin textures (Stud 16 x 16; Dotted 8 x 2; Rounded 128 x 16 backdrop edge strip), grey-scale, tinted by the theme colors (`Theme.textures.skin*`) |
| `Media/Fonts/` | Inter Regular and SemiBold (SIL Open Font License, `Inter-LICENSE.txt`); `Theme.fontFiles.inter*`, offered by the Font option, Inter is the Modern skin's font |
| `Media/Logo.tga` | the logo (leather ledger book with the AL coin), 64 x 64 uncompressed 32-bit TGA: `## IconTexture`, the minimap and broker icon (`Theme.textures.logo`) |

The logo is drawn by `tools/render_logo.py` (repo root, Pillow, not packaged):
`python tools/render_logo.py` writes `AnotherLedger/Media/Logo.tga` and the
512 px `docs/logo.png` used by the README. Change the shapes or colors there
and run it again; don't edit the images by hand. The skin textures come from
`tools/render_skins.py` the same way (`--preview DIR` writes enlarged PNGs).
It also holds the planned Grain / Leather window backgrounds (512 x 512, lit,
tileable); `--backgrounds DIR` writes them outside the addon. They are not
shipped yet: the window background is always flat (`Theme.backdropSpec`).

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
  true` stores the value in `AnotherLedgerDB.account` (shared by every profile:
  `historyLimit`, `tradeLogDays`, `mobDataDays`, `accountZones`, `minimapButton`); `get` / `store` functions
  keep the value elsewhere (the profile choice) and `Options.applyAll` skips
  such an option; `picked(db, value)` runs only on a choice in the panel
  (`Options.pick`), not at login (the color preset writes the single colors
  there). `intercept(db, value)` runs in `Options.pick` first; `true` sets
  nothing (TSM price's "Custom..." entry, `Options.CUSTOM`, opens a text box).
  A dropdown with `free = true` also keeps any typed string. `inactive =
  function() return reason or nil end` says why the option does nothing right
  now (the price addon it needs is not loaded): `Options.inactive(spec)`; the
  panel then draws its block at `Theme.options.inactiveAlpha` (still usable)
  and `Options.tooltip` adds the reason as a warning line. A new kind of
  control is one factory in `Panel.WIDGETS` (`UI/OptionsPanel.lua`) plus its
  height in `Options.HEIGHTS`. The panel's column width, gaps and control
  sizes are `Theme.options`.
- **Price source**: a file in `Sources/` (in the `.toc` after
  `Sources\Sources.lua`) ending with `ns.Sources.register({ key, label, create
  = function(env, setting) return { name, get = function(itemID, link) ... end
  } end })`. It joins the lookup order and the AH price source dropdown.
  Optional: `createDisenchant`, `createMarket` and `present(env)` (its addon
  is loaded, `Sources.isPresent`; `Sources.anyPresent` drives the login hint
  and the scan reminder). A selected source whose addon is not loaded acts as
  Auto (`Sources.effective`, used by `Sources.gate` / `allowed` with `env`)
  and its dropdown entry says `(not loaded)` (`Sources.choices(env)`).
  `Sources.offers(field, env)`: a loaded source has `createDisenchant` /
  `createMarket` (the dimmed options). The disenchant value is the first of
  every source's `createDisenchant` that answers (TSM, then Auctionator). See
  `Sources/Auctionator.lua`. A source's `get` may
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
  (`AnotherLedgerDB.sorts[slot]`, first `defaultSort`, see `Tabs.sortSlot` /
  `Ledger.currentSort`); the others share `AnotherLedgerDB.sort`. The filter bar
  reads and sets it through the accessor `Ledger.init` hands it. A view may
  set `headerInfo` (a short text the header shows right of the title on tabs
  without the session controls).
- **Slash command**: `ns.Slash.define({ name, help, run = function(arg) ...
  end })`; `help` shows in `/al help`. A key binding is a `<Binding>` in
  `Bindings.xml` that runs the command (`SlashCmdList["ANOTHERLEDGER"]("name")`)
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
  `Theme.colors` key except `Theme.FIXED_COLORS` as `"rrggbb"`). The
  `anotherledger` entry is built from `Theme.colors` at load.
  `Theme.applyPreset(id)` sets them in place. The option `colorPreset` comes
  first in Colors, so `Options.applyAll` lays down the palette and the single
  colors go on top (its `apply` also re-applies the stored single colors).
  `Options.applyAll` applies a single color or skin part that is not saved
  without storing it (its default follows the preset / skin), and runs inside
  `Ledger.batch`, so the window redraws once at its end instead of per option;
  picking a preset in the panel writes the single colors. A color option's
  default is its preset's color (`Options.presetColor(id, key)` via
  `Options.defaultFor(key, settings)`); `Options.presetEdited` drives the
  "(edited)" label. Item quality colors (`Theme.qualityColor`) and coin colors
  are fixed at the game's values. Tooltip colors (`tip*`) must stay readable on
  the dark game tooltip (`Theme.TOOLTIP_BG`); no panel color option sets them
  except Tooltip labels. tests/test_theme.lua checks completeness and contrast
  per preset.
- **Own color presets**: `AnotherLedgerDB.colorPresets` (account-wide, not in
  a profile) is a list of `{ name, base, colors }`: `base` is the
  `Theme.presets` id it was saved on, `colors` the single color options
  (`colorText`, ...). Their option value is `Options.USER_PRESET .. name`
  (`"user:Mine"`); `Options.userPreset(id)`, `Options.basePreset(id)` resolve
  it, and every Theme color no option sets comes from the base. The dropdown's
  last entry has the value `Options.CUSTOM` (never stored: `normalize`
  rejects it); its `intercept` asks for a name and calls
  `Options.saveColorPreset(db, name, replace)`. `Options.deleteColorPreset(id)`
  moves every profile using it to the base with its colors filled in.
  `Profiles.encode` exports such a profile as the base plus its colors.
- **Profiles** (`Profiles.lua`): `AnotherLedgerDB.profileUsers` maps
  `"Name-Realm"` to the profile it uses (noted at login by `Core.linkHistory`
  and on a switch; rename and delete keep it current) for the "Used by" line.
  `AnotherLedgerDB.profiles[name]` holds the
  options; `AnotherLedgerCharDB.profile` names the character's (Default when
  missing or deleted). At `ADDON_LOADED`, after `DB.migrateAccount`,
  `Profiles.init` points `AnotherLedgerDB.settings` at the active profile (filled
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
- **Skins**: `Theme.skins` (Modern, Classic, Forge, Slate, Gilded) name one
  choice per part of `Theme.skinParts` (border, buttons, lines, tabs) plus
  `listBox`; Modern also names `font` and `preset`, which its `picked` sets
  (`fontFace`, then `Options.pick` of `colorPreset`, so the single colors
  follow). New profiles default to Modern (`DB.defaults.settings`); saved
  profiles keep their stored skin, font and preset. Border Rounded is a
  backdrop with the edge strip `Media/Skins/Rounded.tga`
  (`Theme.sizes.roundedEdge` / `roundedInset`). Tabs Pills (`Tabs.pillLook`)
  fill the selected tab with `buttonFill` and draw `tabBorderSelected` as a
  `tabUnderline` line over one full base line. Lines Zebra draws dividers like
  Plain and makes the list rows drop their separators for a stripe on every
  second row (`Rows.striped`, `skinScales.zebra`). The options `skinBorder` ... `skinListBox` (`Options.SKIN_PARTS`)
  write `Theme.style` through `Theme.setStyle` and call
  `Widgets.applySkin()`, which re-runs `applyBackdrop` (`Theme.backdropSpec`;
  borders other than Round are line rectangles `frame.skinEdges` from
  `Theme.edgeRects`, Gilded adds `frame.skinStuds`), repaints the buttons
  (`paint`: Bronze bands, Raised edge lines `b.raise`, Flat), restyles every
  `Widgets.rule` (styled dividers: row separators, the Top finds and compact
  dividers, the tab base lines, option section lines; colors from
  `Theme.lineColors`) and runs the `Widgets.onSkin` hooks (tab shape
  `Tabs.reshapeAll`, the sunken list `Window.applyListBox`). Picking a skin
  writes its parts (`picked`); a part's default is the chosen skin's
  (`Options.defaultFor`), so `Options.skinEdited` drives "(edited)".
  `Window.paintLook` colors the edge lines and the list box with opacity and
  brightness. Plain bars that are no dividers (goal bar, Top finds quality
  edge, filter underline) stay `Widgets.line`.
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
  mill or prospect), else Auctionator's disenchant price, shown as `Destroy`;
  it counts whenever one of them is loaded, whatever the AH price source. A row with no vendor, AH or destroy value gets
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
  30 s (no tooltip for objects). Names, GUIDs and cast targets the client
  hands over as secret values (`issecretvalue`, in instances and combat) are
  dropped unread through `Util.isSecret` / `Util.plainString`: comparing one
  errors and taints the addon. No name is saved without one:
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
  place. It values each mob's items like Zones (today's price, else the
  entry's saved one) and sorts by value, per loot (`perLoot` = value / `looted`) or name;
  `Ledger.mobOpen` is the opened mob. A mob row's `hint` builds its tooltip on
  hover (looted, value, gold, per loot, its top 3 places, its best drops). The
  view has no rates, so the footer shows no per hour column.
- **Price trend** (`itemTooltipTrend`, `UI/ItemTooltip.lua`): `Core.priceTrend`
  asks `TSM.trend` (DBMarket against DBHistorical) first, else
  `Scan.trendOf` on this realm's scan bucket: the newest day's value (`m` /
  `l` by the Scan price option) against the weighted average of the days
  before (`am` / `al`), only while the newest is at most
  `Scan.TREND_MAX_AGE` (3 days) old. `ItemTooltip.trendLine` words and colors
  it (`TREND_COLOR_FROM`, 5%: `marketGood` / `marketBad`). The ledger rows
  show the game's item tooltip, so they get the line from the same hook.
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
- **History Totals** (`View.buildTotals`, subtab `totals`): this character's
  saved sessions summed per ISO week inside each calendar month (a week
  spanning two months gives two rows), value as on the session rows. Sorted
  by `recent`: month headings (`isHeading`, `periodKey` `"m:YYYY-MM"`, folded
  through `Ledger.periodFold` like the Sessions headings) over their weeks;
  by `ah` / `perHour`: the week rows alone. Week rows have `id = 0`, so
  they take no click and no row menu. Month names are `L["January"]` ...
- **Bags footer**: `buildInventory` sets `totals.sellSplit` (best value of
  the rows not kept, by `bestKind`; the footer tooltip's Sell split). The
  Bags tab adds `View.addWorth(view, money, bags, bank)` (`totals.money`,
  `totals.bagsWorth`, `totals.bank`, `totals.worth`: the Summary rows Gold on
  hand / Net worth) and the free slots (`Inventory.freeSlots`) to the
  header; `PLAYER_MONEY` redraws it. Net worth is unfiltered:
  `View.inventoryWorth` values the bag items and the last bank scan
  (`chardb.bank`) without the filter (ignored items stay out).
- **Net worth of all characters** (`Worth.lua`): `Tabs.noteWorth(ctx)` saves
  `{ bags, bank, money, at }` (copper, valued then) under `Core.character` in
  `AnotherLedgerDB.worth` while Bags is shown, and `Ledger.noteWorth` does it
  at `PLAYER_LOGOUT` and for `/al worth` (not while the demo's prices are in).
  With two or more saved, the Bags tab sets `totals.allWorth` (the Summary
  row All characters) and `view.worthList` (the tooltip's per character
  lines, with the age of other characters' snapshots). Alts are not valued
  again with today's prices; `/al worth forget <name>` drops a character.
- **Resting** (`cityPause`, `Core.checkRest` on `PLAYER_UPDATE_RESTING`):
  `Session.rest` keeps `running` true but folds the time into `elapsedBase`
  and stops the place time (`resting = "city"`); `Session.wake` restarts it.
  Loot and gold still count. Stop, reset and login (`resume`) handle it.
  `travelPause` rests it the same way with `resting = "travel"` (the header
  says Traveling) while `Core.traveling()` (`UnitOnTaxi`: flight paths only;
  boats and zeppelins are not detected). `PLAYER_CONTROL_LOST` / `GAINED`
  check it at once.
- **Short sessions** (`minSessionMinutes`, `Core.isShort`): a session with
  loot shorter than that is not archived by Session per zone / instance; at
  login a short saved session with loot (its `elapsedBase`; demo sessions
  never) is kept, then started like a new one: `afkPaused` cleared, running,
  `startedAt` = the login. Empty sessions start over as before. `/al reset`
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
  counts, and never twice. A loot window opened before the last one settled
  continues its bookkeeping (`lootWindow.open` counts the windows on it; only
  the last close settles it), so a money line that comes after the next
  window opened is not counted a second time.
- **Places**: each loot and gold event notes its zone (an instance with its
  difficulty is a zone of its own) and subzone, and, outside instances, the
  map position. Time per place only counts while the clock runs. Sessions
  saved before places existed show under `No time recorded` (one place) or
  `Unknown place` (several); both sort last (`row.sortsLast`). The
  difficulty name comes from `GetInstanceInfo`, else
  `GetDifficultyInfo(difficultyID)`, else the last one seen in that instance
  (`Core.placeOf(env, remembered)`), so a loading screen that reports none
  does not split a dungeon in two. The instance key ("Session per instance",
  "Open in instances") is the instance name alone, and only in dungeons and
  raids (`instanceType` party / raid); the split skips a stopped clock.
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
- **History cache** (`ViewZones.lua`): Zones, Mobs and the Daily farm add
  up the saved History once per `opts.historyKey` (`History.combine`'s key,
  which ends in `History.version`: every change through `History.add`,
  `prune`, `remove`, `clear`, `restore`, `adopt` or `History.changed()`
  counts it up, so code that edits a list in place must call
  `History.changed()`). The running session (`live` entry) is laid over that
  as copies of the places and mobs it looted (`fresh`). The item rows and
  totals of a closed, saved place or mob are kept per `opts.valueKey`
  (`Ledger.valueKey`: the options and lists that value items, the filter,
  demo mode and an epoch that moves once per price refresh interval and at
  the next build after `Ledger.valuesChanged()` (item data for a listed item:
  a burst of events moves it once). Zones / Mobs keep the saved sessions' item
  IDs per History key (`itemIDsOf` in `UI/Tabs.lua`). Without both keys
  nothing is cached (tests, CSV export). Only an opened place or mob sorts
  its rows (`collect(items, opts, unsorted)`). `lua tests/bench_zones.lua
  [sessions]` times the views over a made-up History (not part of the run).
- **History prices**: an entry keeps the unit prices its totals were made of
  (`items[key].price`, archive time, loot time as fallback). An opened session
  lists its items at those (`opts.savedPrices`), so they add up to its row;
  Zones and the Daily farm value the same loot at today's prices.
- **Confirmations** go through `Widgets.confirm(text, button, onAccept,
  onCancel)` (one shared popup). An option can ask before a value is stored
  with `confirm = function(value) return question or nil end` (History kept).
- **CSV export** (`History.csv`): one line per session, amounts in gold with
  four decimals, then the currencies (`Name x3; Other x1`) and the note.
  `/al export session` writes `View.itemsCsv` of an unfiltered `View.build`,
  `/al export mobs` `View.mobsCsv` (every mob of an unfiltered
  `View.buildMobs`, by value),
  `/al export zones` `View.zonesCsv` (every subzone from `View.zoneTable`,
  quest items left out). Fields go through `History.csvField`.
- **Ignore list** (`AnotherLedgerDB.ignored = { [itemID] = name }`, Core
  `ignoreItem` / `unignoreItem` / `ignoredList`): `opts.ignored` makes
  `collect` skip those items, so every list, total, Top find, compact drop,
  Zones place and the Daily farm leave them out; `Core.sessionValue`, the drop
  alert and the goals too. They stay recorded. History rows subtract them at
  their saved unit prices (`History.totals(e, ignored)`).
- **Watch list** (`AnotherLedgerDB.watched` = `{ [itemID] = name }` like the
  ignore list, `watchedNames` = `{ [lower case text] = text }`; Core
  `watchItem` / `unwatchItem` / `watchName` / `unwatchName`):
  `Core.recordLoot` calls `Core.watchAlert` before the stopped-clock check, so
  it alerts with the clock stopped too (only real loot: `countsAsLoot` comes
  first). `Core.watchMatch` (pure) matches the ID or a text in the link's
  name. The alert is a chat line, `SOUNDKIT.RAID_WARNING` and
  `UIErrorsFrame:AddMessage`. `/al watch` / `/al unwatch` (Slash.lua), the
  row menu (`Ledger.rowMenu`) and the option button `watchedItems` edit it.
- **Keep list** (`AnotherLedgerDB.kept`, Core `keepItem` / `unkeepItem` /
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
  `opts.goalSeconds` (`goalMinutes` * 60) reaches compact as `goalSeconds`.
  `View.goalFraction(goal, elapsed, goalSeconds)` (gold goal first, else
  the minutes goal) sizes the compact bar and the full header's bar
  (`header:SetGoal`, along the bottom of the title row, Session tab only,
  updated on every tick).
- **Notes**: `entry.note` (`History.setNote`: trimmed, one line, at most
  `History.NOTE_MAX` characters, cut on UTF-8 boundaries) follows the start on
  line 1 of the session row and is part of its search text. Entered through
  `Widgets.prompt` (the shared text popup). `entry.label` (`History.setLabel`,
  right-click Rename, at most `History.LABEL_MAX`) replaces the main place in
  line 2 of the row only; `places`, Zones and the CSV keep the real ones. A
  merge keeps the newer session's label.
- **Inventory tab**: key `inventory`, sub-tabs `bags` and `bank`; it
  watches both data kinds (`watches = { bags = true, bank = true }`,
  `Tabs.watches`). The old tab keys `bags` / `bank` are `Tabs.ALIASES`:
  `Tabs.resolve` maps them to the tab and sub-tab, so `Ledger.setTab("bank")`
  and a saved `db.tab` from before open the sub-tab (the login rewrites
  `db.tab` / `db.subtab.inventory`).
- **Option headings**: a spec's `heading` is drawn above it
  (`Options.layout` returns `heads`); `newColumn` starts the next column, and
  a section with one breaks its columns only there (Appearance: Colors).
- **Options categories**: a list down the left side (`Panel.nav`, one button
  per `Options.sections()` entry, colors from `Panel.navLook`: the chosen one
  filled with a `tabBorderSelected` bar, the same for every skin), a divider,
  then the section's options in two columns. The list is `Theme.options.navWidth`
  wide or as wide as its longest label (`Panel.navWidth`).
- **Options window height**: `Panel.tabbedHeight(section, columns, count)` per
  section (at least the list's height);
  `tabbed.select` calls `tabbed.onResize`, which re-anchors a CENTER-placed
  panel by its TOP and sets the height. `db.optionsWindow` = `{ x, top }`
  (offset of the top edge's middle from the screen's top middle); an older
  `{ x, y }` (CENTER) still opens there.
- **Account-wide History**: `AnotherLedgerDB.histories = { ["Name-Realm"] = list
  }`. At login `Core.linkHistory` adopts the character's old
  `AnotherLedgerCharDB.history` into it (`History.adopt`, no duplicates by start)
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
  ` / `. The merged entry takes the newer session's Auction from
  (`ahMinGain`) and works its `best` out again at it, per session (each at
  its own item prices), adding the two up. `Core.mergeHistory(index)`
  replaces the session at `index` with its merge with `index + 1` (the next older one); `Ledger.mergeHistory` keeps the
  opened session open. `Core.archiveSession` moves the opened index down one
  (a new entry goes first); a row menu finds its session again by the entry
  (`historyIndexOf` in `UI/Ledger.lua`), so Merge and Delete never hit
  another session after a split saved one.
- **Undo**: `Core.deleteHistory`, `Core.clearHistory` and `Core.mergeHistory`
  push `{ restore = entries, drop = merged | nil }` on a stack kept for the
  login; `Core.undoDelete` (`/al undo`) removes `drop` (a merge) and puts
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
  Each drop row shows the list rows' item tooltip (`Rows.showTooltip` with
  `Rows.tooltipLink` / `Rows.tooltipLines`, set in `part:Update`), takes
  Shift / Ctrl-click (`Rows.modifiedClick`) and stays a drag handle.
  A drop's name carries its quantity in the hint color (`Compact.nameText`);
  an unpriced drop shows `?` like its list row (`Rows.rowText`). Option
  `compactIcons`: a texture before the name (`Rows.iconOf(row)`), the name
  re-anchored after it on each update.
- **Hide worthless** (`hideWorthless` -> `opts.hideWorthless`): `collect` and
  the compact drops skip `row.worthless` rows; totals are unchanged (they are
  worth 0).
- **Unpriced first**: `row.unpriced` (no AH price, not bound, not
  worthless; `makeRow` in `View.lua`) is what the footer counts and what
  `Rows.rowText` marks `?`. Bound is the bind type (`info.bound`) or, in
  Bags and Bank, a soulbound stack (`isBound` of
  `C_Container.GetContainerItemInfo`; `item.bound` while every stack is). A click on the notes line (`Summary.attach`, mouse only
  while something is unpriced) runs `Ledger.toggleUnpricedFirst`;
  `opts.unpricedFirst` wraps the item sort (`unpricedFirst(inner)` in
  `View.lua`) and `Summary.notesText(view, true)` says "listed first".
- **No price addon** (`Core.priceAddonHint`, at login): a source spec's
  `present(env)` (TSM, Auctionator) says its addon is loaded
  (`Sources.anyPresent`); without one a chat line once per account
  (`AnotherLedgerDB.priceHintShown`, cleared when one is found again).
- **Reset note** (`resetNote`): `Core.resetSession` returns the saved entry
  (`Core.archiveSession` does); the Reset button and `/al reset`
  (`Header.requestReset` -> `doReset`) then open `Ledger.editNote(entry)`.
  The automatic splits call `Core.resetSession` directly and never ask.
- **Fonts**: `UI/Fonts.lua` makes the addon's own copies of the game fonts
  (`AnotherLedger<Key>`) in `Ledger.init`; typeface and px sizes change live and
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
- **Text fits** (long translations): text buttons built with
  `Widgets.fitButton(b, texts, base)` (Start / Stop, Reset, Quality, Sort,
  the Trade period, the AH scan button) are as wide as their widest label
  (`Widgets.fitWidth`, measured with `GetUnboundedStringWidth`), at least
  the theme width; `Widgets.refitButtons` runs again in `Ledger.relayout`.
  `Ledger.measureHeader` adds up what header rows 1 to 4 need (the pure
  `Header.rowNeed`, `FilterBar.rowNeed`, `Tabs.rowNeed` with the widest of
  `Tabs.titles()`, the fitted buttons and the tab strips) and passes it to
  `Window.setHeaderWidth`; the resize minimum is the largest of the theme's,
  the rows' (`setMinWidth`) and the header's. `tests/test_overflow.lua` runs
  the same functions with estimated widths (`Theme.sizes.charPx` /
  `smallCharPx` per glyph) for English and every `Locales/` file: the header
  fits the default window, option labels stay at 24 glyphs, option buttons
  and closed dropdowns (a choice's `short` text) fit the 150 px control, and
  the footer labels fit their columns.
- **Anchor corner**: a layout switch (`Window.applyMode`), a wider minimum
  (`setMinWidth`, `setHeaderWidth`) and larger font sizes (`applySizes`) resize through
  `resizeKeepingCorner`, which keeps `db.window.corner` (`"TOPLEFT"`, ...)
  in place (`Window.keepCorner`). The corner is picked by `Window.cornerFor`
  (the one nearest the screen edges) only after a drag or a resize by the
  player (`Window.rememberCorner`), or once when none is saved. Picking it
  from the center at every switch made the window walk: the taller full
  layout moves the center over the screen middle, and the way back kept the
  other edge. `ensureOnScreen` can still push a window that would run off
  the screen.
- **Redraws**: the clock and rates every second (running clock, ticking tabs or
  compact); prices and age tags at the **Price refresh** interval on every tab
  while the window is shown, clock running or not; everything at once on loot,
  gold, bag / bank changes, filters, sorts and options. Several loot messages
  in one frame share one redraw.
- **Button text**: `Widgets.buttonColors` passes the label color through
  `Theme.readableOn(color, fill)`: below `Theme.MIN_TEXT_CONTRAST` against the
  button background it turns near-black or white (the arrow follows).
- **Button look** (`Widgets.button`, `Widgets.iconButton`): the backdrop's
  edge is a dark outer line (`buttonFill` x `Widgets.BUTTON_OUTLINE`); inside
  it `b.fill` holds three BACKGROUND textures (top third `buttonFill` x
  `BUTTON_TOP`, bottom third x `BUTTON_BOTTOM`, the middle a vertical
  gradient between them) and `inner`, a child frame whose backdrop edge is
  the preset's button edge color. Hover lightens both halves
  (`BUTTON_HOVER`) and uses the hover edge; OnMouseDown paints "pressed"
  (halves swapped), OnMouseUp hover or normal. Inputs keep the flat backdrop.
- **Trade section** (`Trade.lua`, `Sources/Sales.lua`, Core's trade section in `CoreTrade.lua`,
  the `trade` tab in `UI/Tabs.lua`, `View.buildTradeItems` /
  `View.buildTradeLog`, `UI/RowSwitch.lua`): per realm key
  (`Scan.currentRealmKey`), nothing is recorded while it is unknown. A client
  without `GetCurrentRegionName` or `C_GameRules.GetCurrentGameModeRecordID`
  uses `Core.NO_KEY_PART` ("any") for that part of the key instead of
  waiting for good. Items and Log follow the filter bar (`tradeVisible`:
  quality only on rows of one item); Log sorts by `recent`, `gold`, `name`.
  - Posts and cancels: `hooksecurefunc` on `C_AuctionHouse.PostItem` /
    `PostCommodity` / `CancelAuction` (`Core.hookAuctionCalls`, at login and
    when `Blizzard_AuctionHouseUI` loads); `Trade.addPost` keeps an open post
    (2 days) so a sale mail, which only names the item, finds its item key.
  - `CHAT_MSG_SYSTEM` matching `ERR_AUCTION_SOLD_S` (`Core.formatPattern`)
    keeps a "buyer found" mark with that moment's market (`Trade.markSold`).
  - `MAIL_INBOX_UPDATE` reads every mail: seller invoices (also
    `seller_temp_invoice`) are sales, buyer invoices (auctions won and
    purchases, UNVERIFIED) are `buy` entries keyed by the attached item's
    link (else the item ID of the name), the expired / cancelled subjects
    returns. A sale mail not opened yet has no invoice (Open All empties it
    unread): its subject (`AUCTION_SOLD_MAIL_SUBJECT`, the amount in
    brackets, UNVERIFIED) makes it a sale marked `estimate`, priced from the
    open post's unit price less `Trade.AH_CUT` (5%), else the money received.
    `Trade.recordInbox` takes one inbox read (temporary invoices
    first) through `Trade.recordMail`: a mail key (character, subject,
    sender, money; other mails also the invoice fields, `Trade.legacyMailKey`,
    which sale mails recorded before still match) keeps the expiry of every
    copy seen, and a copy counts as seen when a remembered expiry is within
    `MAIL_DRIFT` (300 s) and not already matched in this read, so identical
    mails are each counted once and a re-read never twice; a sale mail is
    the same mail opened or not. After a whole inbox read (every mail shown,
    `GetInboxNumItems` shown >= total, and read) the character's remembered
    sale mails not seen in it are forgotten, so an equal sale mail coming
    later counts. A sale from a temporary
    invoice is marked `temp` (its `Trade.saleKey`); the final invoice of the
    same sale clears the mark instead of adding a sale. A sale takes the
    amount off the newest open post of that name (link names lose a
    reagent's `|A...|a` quality icon) and the market from the oldest mark,
    else `Core.marketAt` (the first live source other than Own sales,
    `Prices:marketPrice`). Cancel mails are only remembered (counted at the
    auction house).
  - Trades: `TRADE_ACCEPT_UPDATE` snapshots both sides (slots 1-6, gold,
    `UnitName("NPC")`); `UI_INFO_MESSAGE` with `ERR_TRADE_COMPLETE` records
    it (`Trade.addTrade`, also up to 1 s after `TRADE_CLOSED`);
    `Trade.classify` makes it a `tsale`, `tbuy` or `trade`. A trade sale of
    several kinds splits the gold (`Trade.splitGold`) and is marked `split`:
    it counts in Sold and Gold, not in the comparison or Own sales.
  - A `buy` counts `bought` and `spent` in its item's totals (totals saved
    before have neither: read as 0). Items rows show the gold earned less
    `spent` (`View.buildTradeItems`; an item only bought is listed with a
    negative value, the minimum value filter takes the amount), `N bought`
    and a Purchases section in the hover; the Log shows a `buy` as gold
    paid out.
  - Totals per item key are kept for good (`Trade.add`), the log for
    **Trade log kept** days (`Core.pruneTrade` at login).
    `Trade.itemStats(bucket, since, now)` gives the Items rows (from the log
    with a period, from the totals for All); rate = AH sold / (AH sold +
    expired + cancelled) in units, none for name-only sales;
    `Trade.salePrice` the Own sales price (gold before the cut per unit,
    age of the newest sale) from an index built once per log change (not
    saved), which also answers `Trade.hasItemID`. Core signals `dataChanged("trade")`.
- **AnotherLedger scan** (`Scan.lua`, `Sources/Scan.lua`, Core's scan section in `CoreScan.lua`,
  `UI/ScanButton.lua`): whenever the client has
  `C_AuctionHouse.ReplicateItems` (`Core.scanAvailable`), also next to TSM
  and Auctionator (Auto asks them first, so the scan answers what they lack).
  `Core.startScan` (the button, `/al scan` through `Core.scanCommand`, which
  prints why it can't) needs the auction house open, a known realm key and
  the wait over
  (`Scan.waitLeft(AnotherLedgerCharDB.scanAt, now)`, `Scan.WAIT` = 900 s). It
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
  last full read is missing or older than a day, and never while a source's
  `present` is true. `Core.priceAddonHint` stays
  quiet while the realm's bucket has items. The button (`ScanButton.text`:
  ready / `Reading 42%` / the wait as m:ss) is made on the first show, set as
  `Core.onScanChange` and counts down with a 1 s ticker while shown. It hangs
  below `AuctionHouseFrame`'s bottom right corner, `sizes.scanButtonLevel`
  frame levels above it. The game loads that window on demand, so when it is
  missing at `AUCTION_HOUSE_SHOW` the button tries again on the next frame and
  on `ADDON_LOADED` of `Blizzard_AuctionHouseUI` (while the auction house is
  open, `Core.auctionHouseOpen`).
- **Price cache**: prices last seen more than 30 days ago are dropped at login
  (`Prices.CACHE_MAX_AGE`). `/al demo` seeds temporary fake prices that reset
  and logout remove.

## Saved state

The addon was called LootLedger until v0.3.0 (folder, saved variables
`LootLedgerDB` / `LootLedgerCharDB`, `/ll`). The rename to AnotherLedger
starts with fresh saved data: there is no migration, since the game keeps
saved variables per addon folder and the old file is never loaded.

- `AnotherLedgerDB` (account): `profiles` (options per profile; `settings` is the
  active one while logged in and is not saved), `account` (account-wide
  options), `colorPresets` (the player's own color presets), `renamed` (old profile name -> new, so other characters follow a
  rename at their next login), `minimapAngle`, `profilesMigrated` /
  `accountMigrated` (one-time migrations), `window` (position, full size
  `width` / `height`, compact size `compact`, `hidden`, `corner`: the corner a
  resize keeps), `mode` (layout),
  `tab` and `subtab`, `filter`, `sort` (item lists) and `sorts` (History
  Sessions / Zones), `optionsWindow` (where the options panel was dragged to,
  `{ x, y }` from the screen center), `profileUsers`, `minimapIcon`
  (LibDBIcon), `cache` (prices), `ignored` (the ignore list), `kept` (the keep
  list), `watched` / `watchedNames` (the watch list), `worth` (every
  character's net worth, Worth.lua) and `histories` (every character's History, see "Account-wide
  History"), `professions` (`"Name-Realm"` -> `{ enchanting = true, ... }`,
  for the option Destroy values), `scan` (AnotherLedger scan: `[realm key] = {
  lastFull, items = { [itemKey] = packed } }`, see AnotherLedger scan), `trade`
  (Trade tab: `[realm key] = { log, totals, posts, pending, mails }`, see
  Trade section) and `tradePeriod` (`"7"`, `"30"` or `"all"`).
- `AnotherLedgerCharDB` (character): the session (items, gold, places with time,
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
(purchases are not loot; the auction house ones also drive the AnotherLedger
scan), and `REPLICATE_ITEM_LIST_UPDATE`, `COMMODITY_SEARCH_RESULTS_UPDATED`,
`ITEM_SEARCH_RESULTS_UPDATED` (AnotherLedger scan), `MAIL_INBOX_UPDATE`,
`CHAT_MSG_SYSTEM`, `TRADE_ACCEPT_UPDATE` and `UI_INFO_MESSAGE` (Trade
section). An event the client does not know is skipped.

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
"translation" })`, listed in the `.toc` after `Locale.lua`. Only English and German are
kept (French, Spanish, Italian, Portuguese and Russian were dropped after
v0.5.0: nobody could check them). `tests/test_locale.lua` fails
on an entry of any language that the code no longer uses or whose `%s` /
`%d` placeholders differ from the English text (string.format has no
positional arguments; only the date format `%Y-%m-%d` may reorder).
`tests/test_overflow.lua` loads the addon in every language and checks the
fixed spaces (see "Text fits"). Spaces at either end of a key are part of
the text (`"Sort: "`, `" items"`): keep them in the translation. A new
language is a new file there plus its `.toc` line; Korean and Chinese
glyphs are about twice as wide (the overflow test already counts them so)
and need a check of the custom fonts (`fontFace`) in those clients.

## Packaging

The BigWigs packager runs from the repo root (it needs a git checkout as its
top directory) with the root `.pkgmeta`. It copies the repo to
`.release/AnotherLedger/`, and `move-folders` makes the inner `AnotherLedger/` folder
the one addon folder of the zip (the docs, tests and CI files are ignored). It
fetches the libraries into `AnotherLedger/Libs/` (git-ignored) and fills in the
`.toc` version from the git tag. CI builds the zip on every tag (job `package`)
and offers a manual `package-dry-run` on any branch, which lists the zip's
files in the job log. A tag uploads the zip to CurseForge (project 1817047,
`## X-Curse-Project-ID` in the `.toc`) with the protected CI variable
`CF_API_KEY`, which only pipelines of protected refs get: `v*` tags are
protected tags (maintainers only). The release notes are the root `CHANGELOG.md` (`manual-changelog` in
`.pkgmeta`), kept short: one line or two per player-visible change, no
internals. The release steps are in [CHECKLIST.md](CHECKLIST.md).
