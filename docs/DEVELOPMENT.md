# LootPrice development

How the addon is built and how to extend it. The player guide is
[README.md](../README.md); the in-client checks and release steps are in
[CHECKLIST.md](CHECKLIST.md). `docs/superpowers/` holds the design specs and
plans of each feature (history; not kept in sync with the code).

## Setup

- Lua 5.1 (the client's version). Local tests may run on 5.4, so avoid 5.2+
  features (`goto`, `//`, `table.unpack`, integer-only APIs).
- No build step: the client loads `LootPrice/*.lua` in the order of
  `LootPrice/LootPrice.toc`. Copy or symlink `LootPrice/` into
  `World of Warcraft/<client>/Interface/AddOns/`.
- Tests: `lua tests/run.lua` from the repo root (exit 1 on any failure).
  GitLab CI (`.gitlab-ci.yml`) runs them under Lua 5.1 and 5.4 on every push.

## Code layout

Files without `UI/` in their path are plain Lua: every client call is passed in
or looked up at call time, so the tests run them. `UI/` files touch WoW globals
only inside functions.

| File | Job |
| --- | --- |
| `embeds.xml` | loads the libraries the packager puts in `Libs/` (LibStub, CallbackHandler, LibDataBroker, LibDBIcon); the addon works without them |
| `Util.lua` | shared helpers (number checks, clamp, age text, chat output, `Util.setting(key, fallback)` for options read outside `Options.lua`) |
| `Locale.lua`, `Locales/` | translations (`ns.L`, English text as key); `Locales/deDE.lua` is German |
| `Money.lua` | coin text: letters or coin icons, colored, the "large amounts" style |
| `Theme.lua` | look and feel: colors, fonts, sizes, textures |
| `Tooltip.lua` | rich tooltips built as data (Daily, History, Zones, options) and rendered with the theme colors |
| `DB.lua` | saved-variable defaults and repair |
| `LootParse.lua` | loot, money and currency chat messages into links, copper and currencies; item keys with bonus IDs |
| `Prices.lua`, `Sources/` | price lookup with a saved cache; one file per price source |
| `Session.lua`, `History.lua`, `Inventory.lua` | the running session, past sessions, bag and bank scans |
| `Options.lua` | option registry and the built-in options |
| `View.lua` | the rows and totals a tab shows, History Zones, the Daily farm pick, the compact view |
| `Waypoint.lua` | the farm spot as a `/way` line, TomTom waypoint or the game's map pin |
| `Slash.lua`, `Demo.lua` | slash commands, `/lp demo` |
| `UI/Fonts.lua` | the addon's own font objects: typeface, px sizes, the font list |
| `UI/Widgets.lua` | bronze buttons, icon buttons, texts, lines, tooltips, menus |
| `UI/Window.lua` | the frame: header rows, list area, footer, compact area, sizes per layout |
| `UI/Rows.lua`, `UI/Header.lua`, `UI/Summary.lua`, `UI/FilterBar.lua` | list rows, header buttons and clock, footer table and Top finds, filter bar |
| `UI/Tabs.lua` | tab registry and tab buttons |
| `UI/DailyFarm.lua`, `UI/Compact.lua` | the Daily strip; the compact layout's body |
| `UI/OptionsPanel.lua` | the options panel and the page in the game's options window |
| `UI/Minimap.lua`, `UI/Broker.lua` | own minimap button; LibDataBroker source and LibDBIcon button |
| `UI/Export.lua` | the copy box (CSV, `/way` line) |
| `UI/Ledger.lua` | controller: builds the view of the shown tab and feeds the parts |
| `Core.lua` | events: login, loot capture, bank scan, redraw requests (loads last) |

Data flow: `Core` events -> `Session` / `Inventory` -> `UI.Ledger.refresh`
builds a view with the shown tab's `build` (`View.lua`) -> every registered part
draws it. Nothing redraws while the window is hidden; it catches up on show.

## Extending: registries

Each of these is one call in one place; the UI never names them.

- **Option**: a default in `DB.defaults.settings`, then
  `Options.define({ key, category, type, label, tooltip, ..., apply })` in
  `Options.lua`. `label` is short (24 characters at most, a test checks it);
  `tooltip` says what it does and is shown on hover with the default.
  `category` is `window`, `prices`, `display`, `session` or `colors`. Types: `slider`
  (`min`, `max`, `step`, `format`), `dropdown` (`choices` list or function),
  `checkbox`, `number` (whole number, empty = unlimited, optional `zeroText`),
  `text`, `color` (`"rrggbb"`), `button` (`action`). Values are validated by type and fall back to
  the default; `apply` runs on change and for the saved value at login. Read it
  with `Options.get(ns.db, key)`. A new kind of control is one factory in
  `Panel.WIDGETS` (`UI/OptionsPanel.lua`) plus its height in `Options.HEIGHTS`.
- **Price source**: a file in `Sources/` (in the `.toc` after
  `Sources\Sources.lua`) ending with `ns.Sources.register({ key, label,
  create = function(env, setting) return { name, get = function(itemID, link) ... end } end })`.
  It joins the lookup order and the AH price source dropdown. See
  `Sources/Auctionator.lua`.
- **Tab**: `ns.UI.Tabs.define({ key, label, title, build = function(ctx) return view end, ... })`
  in `UI/Tabs.lua`; optional `sessionControls` (clock and buttons), `ticks`
  (rates follow the clock), `watches` (data kind that redraws it), `hasItem`
  and `subtabs` (see the comment at the top of the file).
- **Slash command**: `ns.Slash.define({ name, help, run = function(arg) ... end })`;
  `help` shows in `/lp help`.
- **Window part**: `ns.UI.Ledger.register(part)`; `part:Update(view, session, now)`
  on every full redraw, optional `part:Tick(...)` each second while the clock
  runs (keep it cheap).
- **Rich tooltip**: build it with `ns.Tooltip` (`new`, `pair`, `money`, `rate`,
  `para`, `labelled`, `section`, `note`, `warn`, `hint`) and show it with
  `ns.UI.Widgets.showTextTooltip(owner, tip)`. Colors are `Theme.colors.tip*`.
  A row's `hint` may be a function that builds the tooltip on hover
  (`Tooltip.resolve`); History and Zones rows do that.

## How things work

- **Colors**: `Options.COLOR_OPTIONS` lists each color option with the
  `Theme.colors` keys it sets; its default in `DB.defaults.settings` must equal
  those theme colors (a test checks). `Theme.setColor` overwrites the r, g, b
  of the color table in place, so code that reads `Theme.colors` at draw time
  (tooltips, rows on refresh) follows by itself. Regions colored once at
  creation are remembered by `UI/Widgets.lua` (`setTextColor`, `line`,
  buttons, inputs, `applyBackdrop`) and `Widgets.recolor(changed)` paints them
  again; then `Window.applyLook` (opacity and brightness via
  `Window.paintLook`, for the ledger window and the options panel alike) and
  a refresh run. A text colored with a
  non-theme color (item quality) goes through `Widgets.setTextRGB`, which
  drops it from the list. Vendor / AH / Destroy labels in tooltips use
  `Theme.sourceColor(source)` (`Tooltip.money(..., source)`, `Rows.tooltipLines`,
  `Summary.tooltipLines`). The swatch opens the game picker through
  `Widgets.pickColor`.
- **Footer**: `Summary.tableLayout` gives height 0 and no lines for History and
  Zones (`view.history`); the table frame hides and the list reaches the bottom.

- **Item keys**: `LootParse.itemKey(link)` is the item ID for plain items and
  `"<id>:<sorted bonus IDs>"` for variants; every item map, the price cache and
  row keys use it. Price lookups take `(itemID, link)`.
- **Value** of a row is the best of vendor, AH and disenchant (`View.best`); it
  drives the sort `Value`, Top finds, the minimum filter and the drop alert.
  Items that can never be sold on the AH (bind types 1, 4, 7, 8, 9) are never
  counted as unpriced; an AH price a source still reports for them counts like
  any other. The `de` value is TSM's `Destroy` price
  (disenchant, mill or prospect), shown as `Destroy`.
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
- **Row lines**: line 2 of a row is `row.detail` when set (History sessions:
  length, place, item count; Zones places: time, gold per hour, item count),
  else the TSM sale info. Rows without `quantity` show none. `view.empty`
  (`View.emptyText`) is the text `Rows` shows centered in an empty list.
- **History sessions**: `View.buildHistory` sorts only with `opts.sort` set
  (`ah`, `recent`, `perHour`; others work as `ah`). Search (start, length,
  place) and minimum value pick sessions; the opened one always shows, its
  items filtered by quality only. A row's value is the items' best plus raw
  gold (`includeGold`). Row names use `opts.shortDate` (`History.shortDate`),
  tooltips `opts.formatDate`.
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
  four decimals, the last column the currencies (`Name x3; Other x1`).
- **Compact** (`View.buildCompact`) ignores the filter bar: every item plus raw
  gold when `includeGold` is on; the last drops come from `session.recent`.
- **Fonts**: `UI/Fonts.lua` makes the addon's own copies of the game fonts
  (`LootPrice<Key>`) in `Ledger.init`; typeface and px sizes change live and
  the window re-lays itself out. The source tag font is pinned to Arial Narrow
  (`Theme.fontFiles`). On retail `SetFont` returns nothing, so only an explicit
  `false` means a font cannot load. Every framed source tag box is as wide as
  the widest tag (`Rows.sourceBoxWidth`, from `list.measured.source`), so the
  boxes line up and each text sits centered.
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
- **Price cache**: prices last seen more than 30 days ago are dropped at login
  (`Prices.CACHE_MAX_AGE`). `/lp demo` seeds temporary fake prices that reset
  and logout remove.

## Saved state

- `LootPriceDB` (account): `settings` (options, including the minimap angle),
  `window` (position, full size `width` / `height`, compact size `compact`,
  `hidden`), `mode` (layout), `tab` and `subtab`, `filter`, `sort`,
  `minimapIcon` (LibDBIcon) and `cache` (prices).
- `LootPriceCharDB` (character): the session (items, gold, places with time,
  positions and recent drops), the bank scan and History.

## Events

`CHAT_MSG_LOOT`, `CHAT_MSG_MONEY`, `CHAT_MSG_CURRENCY`, `QUEST_TURNED_IN`,
`GET_ITEM_INFO_RECEIVED`, `LOOT_OPENED` / `LOOT_CLOSED`, `PLAYER_ENTERING_WORLD`, `PLAYER_LOGOUT`,
`BAG_UPDATE_DELAYED`, `BANKFRAME_OPENED` / `BANKFRAME_CLOSED`,
`PLAYERBANKSLOTS_CHANGED` / `PLAYERREAGENTBANKSLOTS_CHANGED`,
`PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED`, `PLAYER_FLAGS_CHANGED`,
`ZONE_CHANGED` / `ZONE_CHANGED_INDOORS` / `ZONE_CHANGED_NEW_AREA`, and the
`MERCHANT_*`, `MAIL_*`, `TRADE_*`, `AUCTION_HOUSE_*` show / closed events
(purchases are not loot). An event the client does not know is skipped.

## Tests

`tests/test_*.lua` get the harness as `...` (`h.test`, `h.eq`, `h.near`,
`h.load`). `tests/test_wiring.lua` boots the whole addon from the `.toc`
against a stub client (fake frames) and drives real events; add a wiring test
for anything that crosses files. The real UI can't be tested outside the client:
anything relying on an unconfirmed client API gets an
`UNVERIFIED (check in client)` comment and a line in
[CHECKLIST.md](CHECKLIST.md).

## Localization

Texts go through `ns.L` (English text as key). A language is one
`Locales/<locale>.lua` with `ns.Locale.register("<locale>", { ["English"] = "translation" })`,
listed in the `.toc` after `Locale.lua`. `tests/test_locale.lua` fails on a
German entry the code no longer uses.

## Packaging

The BigWigs packager with `LootPrice/.pkgmeta` (`-t LootPrice`) fetches the
libraries into `LootPrice/Libs/` (git-ignored) and fills in the `.toc` version
from the git tag. CI builds the zip on every tag (job `package`) and offers a
manual `package-dry-run` on `main`. CurseForge upload needs the CI variable
`CF_API_KEY` and `## X-Curse-Project-ID: <id>` in the `.toc`.
