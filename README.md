# LootPrice

WoW Forever addon: a game-styled Session Ledger showing vendor and auction house value of everything you loot.

Design: docs/superpowers/specs/2026-11-12-loot-price-design.md

## What it shows

The Session Ledger is a draggable, resizable, scrollable window with rounded corners (a thin tan edge, like the tabs):

- **Header**: the title, the session clock, one **Start / Stop** button (it reads Start while the clock is stopped and Stop while it runs), Reset, the gear (options) and the game's close button. Under it the filter bar (quality, minimum gold, search, sort) and the tab buttons: tabs open at the bottom, standing on a thin tan line, with a rounded tan edge and the window's own background (so the opacity and brightness options apply to them too); the selected one has a bright gold edge and a gold glow from its top and opens into the list (the line is open below it); hovering a tab lights its edge.
- **Rows**: one per looted item (icon, quality-colored name, quantity) with the quantity (`xN`) right after the name and the vendor and auction house (AH) values stacked in a block that is right-aligned and adaptive (each amount directly after its label, amounts and labels lined up; the block hugs the right edge and shifts left only as far as the longest amount currently shown needs; the AH age tag follows the AH amount; long names are clipped, the quantity stays visible). Hovering a row shows the item's tooltip. A thin quiet separator line runs between rows. Newly looted rows flash.
- **Value**: a row is worth the best of its vendor, AH and disenchant (`DE:`) totals; the label of that line is gold. The value sorts the list (sort `Value`), picks the Top finds, drives the minimum value filter and the drop alert. Items that can never be sold on the AH (soulbound, quest, warbound) show `AH: bound` and are not counted as unpriced.
- **Item variants**: gear with bonus IDs (other item level, sockets, ...) gets its own row and is priced as that variant (TSM item string with bonus IDs, Auctionator by link, vendor price of the variant).
- **Currencies**: currencies you receive (`You receive currency: ...`) are listed after the items with their quantity (no value); the option **Show currencies in the list** hides them.
- **Money colors**: every amount is shown as `12g 34s 56c` with gold, silver and copper in their own colors (the real game coin colors, bright on the dark panel); `n/a` stays plain.
- **Top finds**: the most valuable finds of the session (best value) (hovering one shows its item tooltip), at the bottom of the window under the footer table, with a gold divider line above it (hidden together with the block when there are no finds).
- **Footer**: a small table with the best value and the gold per hour of each row (columns **Value** and **/h**; a rate shows `—` until there is one):
  - **Items**: the best value of the visible (filtered) rows.
  - **Raw gold**: gold looted from creatures and containers (including group splits) plus gold from quest turn-ins. Raw gold is never touched by the item filters; it shows `0c` until the first gold arrives.
  - **Total** (gold): items + raw gold.
  - A small notes line under the table, only when there is something to say: `filtered` while a filter is active, `N unpriced` for items without an AH price (both orange) and, on the Bank tab, the scan age.
  - Hovering the table shows the vendor, AH and best totals with their rates, for the items and for items + gold.
  - Bags and Bank show only the Items row (no rates).
- **Quest rewards**: reward items are ordinary looted items (the client announces them like any other item) and appear in the list; only the money of a quest is tracked as raw gold.
- **Crafted and bought items** are not loot: `You create: ...` messages and items received while a merchant, mailbox, trade or auction house window is open are ignored unless **Count crafted items and purchases** is on.
- **Places**: every loot and gold event notes where it happened (the zone, or the instance and its difficulty, e.g. `The Stonevault (Heroic)`); History shows them.
- **Age tag**: any AH price taken from the cache (the source returned nothing) shows its age, for example `(3h)`; the tag turns orange once the price is older than the limit set in the options (12 hours by default).

## Tabs

Four tabs sit in the header between the filters and the list; the window, rows, filters and sorts are the same on all of them (the filter bar and sort apply to every tab and are shared):

- **Session**: the loot ledger described above (default).
- **Bags**: every item in your bags (backpack, carried bags, reagent bag), identical stacks merged into one row, valued like loot rows (vendor, AH, age tag). The footer is the single Items block (vendor and AH totals, unpriced count, `filtered` marker); no clock, rates, raw gold or Top finds. The list refreshes when your bags change.
- **Bank**: the same for your bank: the character bank tabs on clients that have them, else the bank, its bank bags and the reagent bank (the account-wide warband bank is not scanned). The client only lets addons read the bank while its window is open, so LootPrice scans it while you are at the banker and saves the scan per character; away from the bank the tab shows the last scan with a note (`Scanned 3h ago`, orange after the **Mark cached prices as old after** time, 12 h by default). Before the first visit it says `Open your bank once to scan it.`

- **History**: past sessions of this character, newest first. A session is saved when it would be thrown away: the Reset button or `/lp reset`, a fresh login with keep-session off, or entering / leaving an instance with **New session for each dungeon or raid** (empty sessions and `/lp demo` loot are skipped). Each row shows the start date and time (`2026-11-14 18:20`), the length and the main place, the number of different items, vendor and AH totals (prices at the time it was saved; an item without a live price uses the price seen when it was looted) and the raw gold. Hovering a row shows the details: all places, vendor / AH / best / raw gold with their gold per hour. Click a session to open it: it moves to the top of the list and its items and currencies are listed right under it (filter and sort apply); click it again to collapse. The footer table adds up all saved sessions (all three rows, rates over their summed length). `/lp export` (or **Export History as CSV** in the options) opens a copy box with the History as CSV. How many sessions are kept: option **History sessions kept**.

The last tab is remembered.

## Options

Three ways in, all showing the same options:

- the **gear button** at the top right of the header (left of the close button) opens the options panel next to the window (Esc or the gear closes it);
- the **minimap button**: left click shows / hides the window, right click opens the options panel, drag moves it around the minimap (drawn by LibDBIcon when it is loaded, which also makes it work with minimap button collectors);
- a **data broker** (LibDataBroker, for Titan Panel, ElvUI, ChocolateBar, ...): shows the session's best value plus raw gold and its rate; same clicks, tooltip with the totals;
- the page **LootPrice** in the game's own options window (Esc > Options > AddOns).

The panel has two columns and four sections. Settings are stored in `LootPriceDB.settings` and applied at login (invalid saved values are repaired).

**Window**
- **Window opacity** (0-100 %, default 100 %): fades the background and border; text and rows stay opaque.
- **Window brightness** (0-200 %, default 100 %): multiplies the background and border color; 100 % is the theme color, above that the dark panel gets lighter, 0 % is black.
- **Window scale** (70-150 %, default 100 %): the window keeps its center on the screen.
- **Lock window**: no moving or resizing.
- **Start hidden at login**.
- **Hide in combat, show again afterwards** (default off): hides the window when combat starts and shows it again when combat ends, but only if it was visible before; a window you hid yourself stays hidden.
- **Show minimap button** (default on) and **Reset minimap button position** (back to the bottom left).

**Prices**
- **AH price source**: `Auto (TSM, then Auctionator)` (default), `TSM` or `Auctionator`. With one chosen, the other is not asked. A price cached from the other source shows with its age tag until it is refreshed.
- **TSM price source** (default `DBMarket`): the TSM price string; same as `/lp tsm`.
- **Price refresh interval** (10-120 s, default 30 s): how often prices and age tags are looked up again while the clock runs.
- **Mark cached prices as old after** (1-72 h, default 12 h): when the orange age tag appears.

**Display**
- **Sort order (at login)**: best value (default), vendor value, name or most recent. The sort button of the filter bar still changes it for the rest of the session; at the next login the list starts with this order again.
- **Amounts of 1 gold and more**: gold, silver and copper (default), gold and silver, or gold only. Amounts under 1 gold always show in full.
- **Add raw gold to the combined total** (default on): with it off, the Total row is left out of the footer table.
- **Show currencies in the list** (default on).
- **Font**: the typeface of all addon text. `WoW default` (default) keeps the game's own font for your client's language; the list also offers the built-in fonts the client loads (Arial Narrow, Skurri, Morpheus) and every font registered with LibSharedMedia when another addon provides it. Changes at once. The addon uses its own copies of the game fonts, so other addons are not affected.
- **List text size**, **Totals text size** (totals and Top finds) and **Section title size**: the size in px of the main font of that part (defaults 12, 12 and 16; the smaller fonts of that part keep their proportion). The matching row heights scale with it. The sizes are set before the window is built, so a change takes effect after `/reload` (the **Reload UI** button does it). The buttons, filter bar and header keep their size.

**Session and alerts**
- **Keep the session across logins** (default off): same as `/lp keep`.
- **Alert for drops worth (gold)**: a chat line when one drop (best value times quantity) is worth at least this much; 0 or empty = off (default). **Play a sound with the alert** adds a sound.
- **Count crafted items and purchases** (default off): see "Crafted and bought items" above.
- **Pause the clock while AFK** (default off): the clock stops when you go AFK and runs again when you are back (only if it was running; Start / Stop by hand ends the pause).
- **New session for each dungeon or raid** (default off): a loading screen into, out of or between instances saves the session to History and starts a new one.
- **Export History as CSV**: same as `/lp export`.
- **History sessions kept**: a number (default 50), `0` for none, or an empty box for unlimited; lowering it deletes the oldest ones at once.

### Adding an option

The panel is built from a registry, it never names an option. To add one:

1. Put its default in `DB.defaults.settings` (`LootPrice/DB.lua`). Buttons have no value and no default.
2. Register it in `LootPrice/Options.lua` with one `Options.define({ key, category, type, label, ... , apply = function(value) ... end })`. `category` is a section id from `Options.CATEGORIES` (`window`, `prices`, `display`, `session`); without one the option lands in an "Other" section. Types: `slider` (`min`, `max`, `step`, optional `format`), `dropdown` (`choices = { { value, label }, ... }` or a function returning that list), `checkbox`, `number` (whole number, empty = unlimited), `text` (any non-empty text) and `button` (`action` runs on click). Values are validated by type and fall back to the default; `apply` makes the value take effect (and also runs for the saved value at login).
3. Read it where it is needed with `Options.get(ns.db, key)`.

A new kind of control is one factory in `Panel.WIDGETS` (`LootPrice/UI/OptionsPanel.lua`) plus its block height in `Options.HEIGHTS`. The panel grows to fit.

## When the window updates

- **Every second** (session tab, clock running): only the clock and the per-hour rates.
- **Every 30 seconds by default** (option **Price refresh interval**; session tab, clock running): prices and age tags are looked up again.
- **At once** when something changes: loot, raw gold, a bag or bank change on its tab, a filter, sort or option. Several loot messages of one frame (area loot) share one redraw.
- **Never while the window is hidden** (also when hidden by the combat option). Loot is still recorded; the window catches up when it is shown.

Cached AH prices that were last seen more than 30 days ago are removed from the saved file at login (`Prices.CACHE_MAX_AGE`).

## Code layout and extending

Files load in the order of `LootPrice/LootPrice.toc`. Modules without `UI/` in their path are plain Lua with every client call passed in, so the tests can run them.

| File | Job |
| --- | --- |
| `embeds.xml` | loads the libraries the packager puts in `Libs/` (LibStub, CallbackHandler, LibDataBroker, LibDBIcon) |
| `Util.lua` | shared helpers (number checks, clamp, age text, chat output) |
| `Locale.lua`, `Locales/` | translations (`ns.L`, English text as key); `Locales/deDE.lua` is German |
| `Money.lua`, `Theme.lua`, `DB.lua` | coin text, look and feel, saved-variable defaults |
| `LootParse.lua` | turns loot, money and currency chat messages into item links, copper and currencies; item keys with bonus IDs |
| `Prices.lua`, `Sources/` | price lookup with a saved cache; one file per price source |
| `Session.lua`, `History.lua`, `Inventory.lua` | the session, the archive of past sessions, bag and bank scans |
| `View.lua` | turns items and prices into the rows and totals a tab shows |
| `Options.lua`, `Slash.lua`, `Demo.lua` | option registry, slash commands, `/lp demo` |
| `UI/Widgets.lua` | shared buttons, texts, lines, tooltips, context menu |
| `UI/Window.lua`, `UI/Rows.lua`, `UI/Header.lua`, `UI/Summary.lua`, `UI/FilterBar.lua`, `UI/OptionsPanel.lua` | the window and its parts; the options panel and the page in the game's options window |
| `UI/Tabs.lua` | tab registry and tab buttons |
| `UI/Fonts.lua` | the addon's own font objects: typeface option and px sizes |
| `UI/Minimap.lua` | the minimap button (own button when LibDBIcon is not loaded) |
| `UI/Broker.lua` | LibDataBroker data source and the LibDBIcon button |
| `UI/Export.lua` | the CSV copy box (`/lp export`) |
| `UI/Ledger.lua` | controller: builds the view of the shown tab and feeds the parts |
| `Core.lua` | events: login, loot capture, bank scan, redraw requests |

Three more things are registries like the options, so adding one touches a single place:

- **A price source**: a new file in `Sources/` (listed in the `.toc` after `Sources\Sources.lua`) that ends with `ns.Sources.register({ key, label, create = function(env, setting) return { name, get = function(itemID) ... end } end })`. It joins the lookup order and the **AH price source** dropdown by itself. See `Sources/Auctionator.lua`.
- **A tab**: `ns.UI.Tabs.define({ key, label, title, build = function(ctx) return view end, ... })` in `UI/Tabs.lua`. `build` returns a view from `View.lua`; optional fields say whether the tab shows the session clock (`sessionControls`), follows it (`ticks`), which data change redraws it (`watches`) and which items it lists (`hasItem`).
- **A slash command**: `ns.Slash.define({ name, help, run = function(arg) ... end })`. The `help` line shows up in `/lp help`.

A window part that should redraw with the ledger registers itself with `ns.UI.Ledger.register(part)`: `part:Update(view, session, now)` runs on every full redraw, an optional `part:Tick(view, session, now)` once a second while the clock runs (keep it cheap).

## Events used

`CHAT_MSG_LOOT` (items), `CHAT_MSG_MONEY` (raw gold looted; parsed from `YOU_LOOT_MONEY`, `LOOT_MONEY_SPLIT`, `YOU_LOOT_MONEY_GUILD` (first amount only) and the `GOLD_AMOUNT` / `SILVER_AMOUNT` / `COPPER_AMOUNT` globals), `QUEST_TURNED_IN` (`moneyReward` in copper), `GET_ITEM_INFO_RECEIVED`, `PLAYER_ENTERING_WORLD`, `PLAYER_LOGOUT`, `BAG_UPDATE_DELAYED` (bags tab refresh, bank rescan while the bank is open), `BANKFRAME_OPENED` / `BANKFRAME_CLOSED` (bank scan), `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` (combat auto hide), `CHAT_MSG_CURRENCY` (currencies), `PLAYERBANKSLOTS_CHANGED` / `PLAYERREAGENTBANKSLOTS_CHANGED` (bank rescan), `PLAYER_FLAGS_CHANGED` (AFK pause), `MERCHANT_*`, `MAIL_*`, `TRADE_*`, `AUCTION_HOUSE_*` `_SHOW` / `_CLOSED` (purchases are not loot). An event the client does not know is skipped at registration.

## Requirements

Vendor prices need nothing. AH prices need [TradeSkillMaster](https://www.tradeskillmaster.com/) or Auctionator (both optional). TSM is asked first, then Auctionator. Without either, the AH column shows `n/a`. The data broker and LibDBIcon button need the libraries the packager adds (`Libs/`); a development copy without them uses its own minimap button.

Items that can be disenchanted get a third line, `DE:`, with the disenchant value (TSM's `Destroy` price source, times the quantity). It needs TSM and is hidden for items TSM has no disenchant value for. The check `TSM_API.GetCustomPriceValue("Destroy", "i:<itemID>")` is unverified in the client.

## Commands

- `/lp` (or `/lootprice`) - toggle the window
- `/lp show` | `/lp hide` - show or hide the window
- `/lp start` | `/lp stop` - start or stop the session clock
- `/lp reset` - clear the session (asks for confirmation once the session holds 25 or more distinct items)
- `/lp keep on|off` - keep the session across logins
- `/lp tsm <source>` - TSM price source (e.g. `DBMarket`); prices cached under the old source stay in the cache until they refresh
- `/lp export` - the History as CSV in a copy box
- `/lp demo` - adds fake sample loot, a little gold (12s 40c) and temporarily seeds fake AH prices for a few real item IDs; `/lp reset`, the Reset button and logout remove the fake prices again. Use it only to check the UI (needs a running session).
- `/lp help` - list the commands

## Saved state

Options are in `LootPriceDB.settings` (see Options). Window position, size, visibility, last tab and filter are remembered automatically (`LootPriceDB`; the sort starts each login with **Sort order (at login)**); the session, the bank scan and History are per character (`LootPriceCharDB`). A real login starts a fresh session unless **Keep the session across logins** is on; a `/reload` always keeps it.

## Filters and sorts

- Filters: quality toggles, minimum value (gold), text search. They persist across relogs.
- Sorts: best value (`Value`, default, highest first), vendor value, most recent, name.

## Known limit: age tags

TSM and Auctionator return a number without a scan time. The age is the time since the source last returned a price for that item. If the source returns nothing, the last known price is shown with its age. A source that silently serves old scan data looks fresh (also noted in `/lp help`).

## Tests

`lua tests/run.lua` from the repo root (exit code 1 on any failure). Plain Lua, no WoW client needed; the UI cannot be tested outside the client. GitLab CI (`.gitlab-ci.yml`) runs them under Lua 5.1 (the client's version) and 5.4 on every push.

## Localization

Texts go through `ns.L` (`Locale.lua`): `L["Vendor: "]` is the text of the client language when a file in `Locales/` has it, else the English text. A new language is one file `Locales/<locale>.lua` with `ns.Locale.register("<locale>", { ["English text"] = "translation", ... })`, listed in the `.toc` after `Locale.lua`. German (`deDE`) is included; `tests/test_locale.lua` fails on a German entry the code no longer uses. Loot, money and currency messages are parsed from the client's own strings, so they work in every language.

## Install / development

Copy or symlink the `LootPrice/` folder into `World of Warcraft/<client>/Interface/AddOns/`. Packaging uses the BigWigs packager with `LootPrice/.pkgmeta` (run with `-t LootPrice`); it fetches the libraries into `LootPrice/Libs/` (git-ignored) and fills in the `.toc` version from the git tag. CI builds the zip on every tag (job `package`, artifacts) and offers a manual dry run on `main` (`package-dry-run`). Uploading to CurseForge needs the CI variable `CF_API_KEY` and `## X-Curse-Project-ID: <id>` in the `.toc`.

## Before release

- [x] `## Interface:` number in `LootPrice/LootPrice.toc` confirmed as 16001 (`/dump select(4, GetBuildInfo())` in the Forever client).
- [ ] Run the CI jobs once: `test` passes under Lua 5.1 and 5.4; the manual `package-dry-run` zip contains exactly one `LootPrice/` folder with the `.toc` and `Libs/` (LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0) inside (the external URLs in `LootPrice/.pkgmeta` are unverified).
- [ ] For CurseForge: create the project, add `## X-Curse-Project-ID` to the `.toc` and the `CF_API_KEY` CI variable.
- [ ] Re-verify the price API signatures in the client (spec risk 1): `TSM_API.GetCustomPriceValue("DBMarket", "i:<itemID>")` and `Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID)`; flagged in code as `UNVERIFIED (check in client)` comments until confirmed.
- [ ] Run the in-client checks below on a fresh `LootPriceDB` / `LootPriceCharDB` (delete the saved-variable files for one launch).

### In-client verification checklist

Core and loot
- [ ] `/reload`: no Lua errors, also on login with the window hidden
- [ ] `/lp help`; `/lp`, `show`, `hide`, `start`, `stop`, `reset`, `keep`, `tsm`
- [ ] `/lp demo` (adds fake loot and temporarily seeds fake AH prices for a few real item IDs; removed again by `/lp reset`, the Reset button and logout, so use it only to check the UI): six rows, 12s 40c of raw gold, quality colors, `n/a` for Light Leather, orange `(14h)` tag on Kingsblood, stale / no-AH rows
- [ ] Loot a vendor item, then `/dump LootPriceCharDB.session.items`
- [ ] `GetCurrentRegionName` and `C_GameRules.GetCurrentGameModeRecordID` return values (cache key non-nil)
- [ ] `CHAT_MSG_LOOT` parsing against the real `LOOT_ITEM_*` globals
- [ ] Logout / relogin with keep on keeps the session; with keep off a real relog starts fresh, while `/reload` keeps the session
- [ ] `GET_ITEM_INFO_RECEIVED` throttle; `C_Timer.After` exists

Window
- [ ] Appears as a dark brown leather panel with rounded corners: the thin `Interface\Tooltips\UI-Tooltip-Border` edge (16 px, fill inset 5 px) reads as a frame and no square fill corner shows outside it, also on the options panel and the CSV copy box and at 0 % / 200 % brightness; title readable (ink color on the gold font object)
- [ ] Drag by header; resize with the grip, never below the minimum (428 px high, so the list keeps four rows beside a full Top finds block; at least 350 px wide, wider if the font needs it for the Vendor/AH block); position unchanged after resize ends
- [ ] `/reload` keeps position, size and hidden state; `/lp hide` then `/lp show`; `/lp` toggles
- [ ] Changing UI scale / resolution never leaves it off-screen
- [ ] Grip texture shows; the 0.001-height top box does not break the list layout; `setTopBoxHeight(40)` reflows
- [ ] `SetClipsChildren` / `SetResizeBounds` exist on 11.x (`SetMinResize` fallback is included)

Rows and list
- [ ] Hovering a row shows the item tooltip (all three tabs) and it hides on leaving; wheel scrolling still works over rows; a hovered row whose data refreshes keeps a correct tooltip (`GameTooltip:SetHyperlink` with a stored link or `item:<id>`)
- [ ] Mouse wheel and scrollbar scroll; resizing re-lays out rows
- [ ] Vendor/AH block on the right (Vendor upper line, AH lower line), the amount directly after its label, labels and amounts line up down the list, the quantity after the name, long names clipped with an ellipsis (quantity stays), the window minimum width adapts to the measured font (also at the minimum width with a long amount like `123456g 78s 90c`); two text lines fit the 28 px row without touching
- [ ] Right block hugs the right edge and shifts left for longer amounts; separators visible but quiet
- [ ] Looting flashes the row, a hidden row scrolls into view, a stack increase re-flashes
- [ ] An uncached item shows the link name, then corrects on `GET_ITEM_INFO_RECEIVED`
- [ ] The ticker updates only while the session runs

Tabs (Bags / Bank / History)
- [ ] Three tab buttons (Session, Bags, Bank) in the third header row under the filters, above the list; the tabs are open at the bottom (the `Interface\Tooltips\UI-Tooltip-Border` edge on a `BackdropTemplate` frame, its bottom edge cut off by the button's `SetClipsChildren`), show the window background with no fill of their own and follow the opacity and brightness options, the line under the row is open below the selected tab, the selected one has a gold edge, white text and a gold glow fading down from its top (`Texture:SetGradient` with `CreateColor`, or `SetGradientAlpha` on older clients), hovering a tab lights its edge, and clicking the selected tab again does nothing; the window title changes to Bag Ledger / Bank Ledger; Start / Stop, Reset and the timer hide on Bags and Bank, the close button stays
- [ ] Bags: every bag item appears once with its summed stack count; moving, looting, selling and splitting stacks update the list; opening the window on the Bags tab shows current contents
- [ ] Bags footer shows only the Items row (no column titles, no rates, no Top finds) and the list uses the freed space; switching back to Session restores all rows
- [ ] Bank: before any visit the list is empty with "Open your bank once to scan it."; opening the bank fills it; closing the bank and walking away keeps the list with "Scanned ... ago" (orange after 12 h); the scan survives `/reload` and relog
- [ ] `C_Container.GetContainerItemInfo` returns `{ itemID, stackCount, hyperlink }`, and `BANK_CONTAINER`, `NUM_BAG_SLOTS`, `NUM_REAGENTBAG_SLOTS`, `NUM_BANKBAGSLOTS` match the real bag / bank container ids on Forever (`/dump BANK_CONTAINER, NUM_BAG_SLOTS, NUM_REAGENTBAG_SLOTS, NUM_BANKBAGSLOTS`); items in bank bags and the reagent bank/warband bank (if the client has them) are included or deliberately skipped
- [ ] The last tab is restored after `/reload`

Options
- [ ] Minimap button: shows near the bottom left of the minimap, left click toggles the window, right click opens the options panel, dragging moves it around the rim and the place survives `/reload`; the option hides it and **Reset minimap button position** brings it back; the tooltip lists the clicks; `INV_Misc_Coin_01`, `MiniMap-TrackingBorder` and `UI-Minimap-ZoomButton-Highlight` textures exist
- [ ] Options page: a **LootPrice** entry exists under Esc > Options > AddOns (`Settings.RegisterCanvasLayoutCategory`), shows the same sections and values as the panel (two columns fit the page width) and edits apply at once
- [ ] Panel sections (Window, Prices, Display, Session and alerts) show a gold title with a line, no title sits alone at the bottom of a column, and the panel fits on the screen
- [ ] Font dropdown lists WoW default and the fonts the client loads; picking one changes all addon text at once and **WoW default** restores it; other addons' fonts do not change; the text size sliders plus **Reload UI** resize the list, totals and titles without clipped text (also at 18 px / 24 px)
- [ ] Window scale keeps the window in place; Lock window blocks dragging and resizing; Start hidden at login hides it after `/reload`
- [ ] Alert: a drop worth more than the set gold prints a chat line (and plays `SOUNDKIT.UI_EPICLOOT_TOAST` with the sound option); Add raw gold to the combined total off hides the Total row; Amounts of 1 gold and more changes every amount; Price refresh interval and the old-price age take effect
- [ ] Gear button sits left of the close button, shows the icon (`Interface\Icons\Trade_Engineering`) with a tooltip "Options"; the title is not overlapped at 350 px; the panel opens to the right of the window, Esc and the gear close it
- [ ] Window opacity slider (0-100 %): the window background and border fade live down to fully transparent (text stays solid); Window brightness slider (0-200 %) darkens / lightens the background and border; the values show in the slider titles and survive `/reload`; `OptionsSliderTemplate` exists and its own texts are hidden
- [ ] Price source dropdown lists Auto / TSM / Auctionator (menu works with `MenuUtil` or the legacy dropdown), the choice changes the AH prices live and survives `/reload`
- [ ] Combat checkbox: with it on the window hides on entering combat and returns after; a window hidden by hand stays hidden; turning the option off mid-combat brings it back

Header
- [ ] Title is not overlapped by the timer at 350 px
- [ ] Button look and font (`UIPanelButtonTemplate`); the one Start / Stop button reads Start while stopped and Stop while running, and a click does the matching thing
- [ ] Reset popup appears and OnAccept resets
- [ ] The close button (`UIPanelCloseButton` at 20 px; also on the options panel and the CSV copy box) looks right, closes without the template's own hide, and persists the hidden state across `/reload`
- [ ] German client: quality menu and sort button are translated (`Nach: Händler` fits the sort button)

Raw gold and quest rewards
- [ ] Gold looted from a creature, and from a container, appears in the Raw gold total and in the combined totals
- [ ] A group split (`Your share of the loot is ...`) is counted once; with a guild bank cut only the first amount counts
- [ ] Turning in a quest with a gold reward adds that gold to the same Raw gold total; a quest without gold changes nothing
- [ ] A quest reward item shows up as a normal row in the item list
- [ ] Raw gold ignores the item filters and the `filtered` marker only concerns the Items row; Stop ignores gold, Reset clears it, a kept session keeps it across relogs
- [ ] `CHAT_MSG_MONEY` texts match the real `YOU_LOOT_MONEY` / `LOOT_MONEY_SPLIT` / `GOLD_AMOUNT` globals (`/dump YOU_LOOT_MONEY, GOLD_AMOUNT`; the ", " unit separator is assumed)

Summary footer
- [ ] The footer table (72 px: column titles + Items / Raw gold / Total, 18 px each) fits at 350 px wide and 428 px high with the 12 pt font; the Value and /h columns line up, also with the German labels (`Gegenstände`) and values up to `123456g 78s 90c` / `999g 59s 59c/h` (width estimate in `Theme.sizes.summaryCharPx`)
- [ ] The Total row is gold, the column titles muted; the notes line appears only with filtered / unpriced / a bank note, and the list reflows when it does
- [ ] Hovering the footer shows the vendor / AH / best tooltip (`GameTooltip:AddDoubleLine`) and it hides on leaving
- [ ] Gold edge texture visible on the dark panel
- [ ] Top finds sits at the bottom under the footer table; its gold divider line (above it) is visible, disappears with the block when there are no finds, and the list and summaries reflow; the last Top finds value stays clear of the resize grip
- [ ] Dark leather look: ink, quality colors, the orange age tag and the `Top finds` header are readable, the gold divider is visible (colors in `Theme.lua` were tuned by computed contrast only)
- [ ] Colored money: bright gold / silver / copper letters read well on the dark panel in rows, Top finds, totals and the per-hour rates
- [ ] Top finds shows / hides and the list reflows; hovering a find shows its item tooltip; the block is gone on the Bags and Bank tabs
- [ ] Em dash renders in FRIZQT; rates show an em dash in the first minute
- [ ] `/lp demo` totals match the rows

Filter bar
- [ ] Row 2 layout at 350 px (`InputBoxTemplate` insets and hints)
- [ ] Quality menu stays open on toggle and colors render
- [ ] Minimum gold applies on Enter / blur and reverts on Escape
- [ ] Search narrows live; the sort cycle reorders; the filter underline appears and disappears
- [ ] The filter persists after `/reload`; no keyboard capture when unfocused

Variants, values and currencies
- [ ] Two drops of one gear item with different item levels show as two rows; `TSM_API.ToItemString(link)` and `Auctionator.API.v1.GetAuctionPriceByItemLink` price each variant; the bonus ID count is the 13th link field (`/dump` an item link)
- [ ] The gold label marks the best line (Vendor / AH / DE); the `Value` sort and Top finds follow the best value; the Best total and rate fit in the footer title rows at 350 px
- [ ] A soulbound or quest item shows `AH: bound` and is not counted as unpriced (`GetItemInfo` 14th return bindType 1 / 4 / 7 / 8 / 9)
- [ ] A currency gain (`CHAT_MSG_CURRENCY`, `CURRENCY_GAINED*` globals) adds a currency row with icon and tooltip (`C_CurrencyInfo.GetCurrencyInfo`)
- [ ] Crafting (`You create`) and buying from a merchant add nothing with the option off and are counted with it on; a quest reward still counts; the `MERCHANT_*` / `MAIL_*` / `TRADE_*` / `AUCTION_HOUSE_*` events exist
- [ ] Money parsing in a non-English client (another unit separator than ", ")

Places, automatic sessions, export
- [ ] `GetInstanceInfo` / `GetRealZoneText` give the zone outside and `Instance (Difficulty)` inside; History rows show the main place and the tooltip all places and rates
- [ ] New session for each dungeon or raid: entering and leaving a dungeon each save a History entry; a loading screen in the open world does not
- [ ] Pause the clock while AFK: `/afk` stops the clock, moving again restarts it (`PLAYER_FLAGS_CHANGED`, `UnitIsAFK`)
- [ ] `/lp export` and the options button open the copy box (`UIPanelScrollFrameTemplate`), the CSV is selected, Ctrl+C copies it, Esc closes it

Bank
- [ ] Forever has character bank tabs (`Enum.BagIndex.CharacterBankTab_1`) or the old bank: the right one is scanned; the reagent bank (`REAGENTBANK_CONTAINER`) is included where it exists; moving items in the bank's own slots updates the scan (`PLAYERBANKSLOTS_CHANGED`)

Libraries and language
- [ ] Packaged build: the minimap button is LibDBIcon's (dragging, hiding, reset), the broker shows in Titan Panel / ElvUI; a dev copy without `Libs/` loads without Lua errors (missing `embeds.xml` files only) and shows the own button
- [ ] German client: texts are German, nothing clips (longer labels in the options panel and footer)

History tab (unverified in the client)
- [ ] Reset with loot adds a row to History; `/lp demo` then reset does not; relog (keep off) archives the old session; `/reload` does not
- [ ] History rows show date and time (`date("%Y-%m-%d %H:%M")`), length, item count, Vendor / AH / Gold lines; clicking a row moves it to the top with its items under it, a second click collapses it; the tab title is Session History
- [ ] Options: the `History sessions kept` box (`InputBoxTemplate`) accepts a number, empty = unlimited, Enter/focus loss saves, Esc reverts; lowering it prunes at once
