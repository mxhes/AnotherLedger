# AnotherLedger

WoW **Forever** (retail engine, Interface 16001) addon in Lua 5.1: a "Session Ledger" window that values everything you loot (vendor, AH, disenchant), with Bags / Bank / History (Sessions, Zones, Mobs with drop chances) / Trade (auction and trade sales) tabs, its own AH scan, a compact layout and a Daily farm pick. The addon folder is `AnotherLedger/` inside the repo.

Docs:
- `README.md`: player guide (keep it free of texture paths, API names and pixel sizes).
- `docs/DEVELOPMENT.md`: code layout, registries, how things work, saved state, events, packaging.
- `docs/CHECKLIST.md`: what still has to be confirmed in the client, and release steps.
- `docs/BACKLOG.md`: feature ideas not built yet (move an entry to "Already built" when done).
- `docs/superpowers/`: design specs and plans per feature (history, not kept in sync).

## Commands

- Tests: `lua tests/run.lua` from the repo root (plain Lua, no client; exit 1 on failure). Run after every change; all must pass. Local `lua` is 5.4; GitLab CI also runs 5.1 (the client's version), so write 5.1 code (no `goto`, `//`, `table.unpack`, integer-only APIs).
- Lint: `luacheck AnotherLedger` (`.luacheckrc`; CI job `lint` fails on any warning). A WoW API the code starts to read goes in its `read_globals`.
- No build step: the client loads `AnotherLedger/*.lua` in the order of `AnotherLedger/AnotherLedger.toc`. The addon must work without `Libs/` (packager-fetched, git-ignored).
- Remote: GitLab `origin` (https://gitlab.com/mhhenjes/lootledger), branch `main` (protected: changes go in through merge requests; `glab` works on the project). Commits are `feat:` / `fix:` / `refactor:` / `docs:` style, one line summary plus a short body.

## Architecture

- **Pure vs client code.** Files outside `UI/` are plain Lua; every client call is injected or looked up at call time, so tests load them with `h.load({...})`. Files in `UI/` touch WoW globals only **inside functions**, never at file load.
- **Namespace.** Every file starts `local ADDON, ns = ...` and publishes one table (`ns.Options`, `ns.UI.Window`, ...). State: `ns.db` (`AnotherLedgerDB`, account), `ns.chardb` (`AnotherLedgerCharDB`), `ns.session`, `ns.prices`.
- **Load order** (the `.toc`): embeds.xml, Util, Locale, Locales/*, Money, Theme, Tooltip, DB, LootParse, Prices, Scan, Trade, Sources/*, Session, Mobs, History, Inventory, Worth, Stats, Options, OptionsLook, Profiles, View, ViewZones, ViewTrade, Waypoint, Slash, Demo, UI/Fonts, UI/Widgets ... UI/ItemTooltip, UI/ScanButton, UI/TradePeriod, UI/Ledger, Core, CorePrices, CoreLists, CoreHistory, CoreScan, CoreTrade, Boot last. Boot calls `Core.init`, which wires every `Core.events` handler (unknown events are skipped).
- **Data flow.** `Core` events -> `Session` / `Inventory` -> `UI.Ledger.refresh` builds a view via the shown tab's `build` (`View.lua`, pure) -> each registered part draws it. Nothing redraws while the window is hidden.
- **Registries** (add things in one place; UI code never names them): options `Options.define`, price sources `ns.Sources.register`, tabs `ns.UI.Tabs.define`, slash commands `ns.Slash.define`, window parts `ns.UI.Ledger.register`. Details in `docs/DEVELOPMENT.md`.
- **Items** are keyed by `LootParse.itemKey(link)` (`"<id>:<bonus IDs>"` for variants); `item.id` stays numeric. A row's value is the best of vendor, AH and disenchant (`Prices.best`).
- **Look** lives in `Theme.lua` (colors incl. `tip*`, fonts, sizes, textures); change the look there, not in UI files. Fonts are the addon's own copies (`UI/Fonts.lua`); face and px sizes change live.
- **Tooltips** with structure (Daily, History, Zones, options) are built as data with `ns.Tooltip` and shown with `Widgets.showTextTooltip(owner, tip)`.

## Conventions and gotchas

- **Options**: a default in `DB.defaults.settings`, a short `label` (24 characters at most; a test checks) and a `tooltip` with the details. Validate through `Options.normalize`, read with `Options.get`.
- **Texts** go through `ns.L` (English text as key; `local L_X = L["Text"]` at file top). Add the German text to `Locales/deDE.lua`; English and German are the only languages (the others were dropped after v0.5.0). `tests/test_locale.lua` fails on keys the code no longer uses or with other `%s` / `%d` placeholders, so remove the entries when you change an English text. `tests/test_overflow.lua` checks that both languages fit the header, the option labels (24 glyphs) and the footer columns.
- Money is always **copper**; format with `ns.Money` (it follows the coin-icon and large-amount options).
- New `.lua` file: add it to the `.toc` (the wiring test loads from it) and the layout table in `docs/DEVELOPMENT.md`. A new named global frame goes in the `allowed` list of the "no unexpected globals leak" test.
- History lists change only through `History` functions (or call `History.changed()` after an edit in place): Zones / Mobs / Daily farm cache over `History.version`.
- Tests: `tests/test_*.lua` get the harness as `...` (`h.test`, `h.eq`, `h.near`, `h.load`). `tests/test_wiring.lua` boots the addon from the `.toc` against fake frames and drives real events; add a wiring test for anything that crosses files. Fake frames answer **any unset field with a no-op function**, so initialize optional fields to `false` and check tables with `type(x) == "table"`.
- An unconfirmed client API gets an `UNVERIFIED (check in client)` comment and a line in `docs/CHECKLIST.md`; say in your report it was not run in the client. Remove both once the user confirms it.
- **Changelogs are short**: a `CHANGELOG.md` entry (also the CurseForge release notes) has one bullet per player-visible change, one or two lines each, about ten bullets at most, small fixes grouped in one "Fixes:" bullet, no internals. Details belong in `README.md`.
- Update the docs in the same change: player-visible behavior and option names in `README.md`, internals in `docs/DEVELOPMENT.md`, client checks in `docs/CHECKLIST.md`.
- **Editing on Windows (Git Bash):** heredocs and `sed` strip backslashes (`"Interface\\Icons\\..."`), and some heredocs with quotes fail to parse. Edit Lua with the Write / Edit tools; for scripted multi-file edits write a Python file with the Write tool and run it (build backslashes with `chr(92)`, CR LF with `chr(13) + chr(10)`). Files are CRLF or LF: read with `newline=''`, normalize, and write back with the original line ending. Git's LF -> CRLF warnings are harmless.

## Where to look first

| Task | Start in |
| --- | --- |
| a new setting | `Options.lua`, `DB.lua`, then the code that reads it via `Options.get` |
| prices wrong / missing | `Prices.lua`, `Sources/`, `CorePrices.lua` (`Core.buildPrices`) |
| loot or gold not captured | `LootParse.lua`, `Core.lua` (`CHAT_MSG_LOOT`, `CHAT_MSG_MONEY`) |
| what a tab shows | `UI/Tabs.lua`, `View.lua` (Zones / Mobs / Daily: `ViewZones.lua`, Trade: `ViewTrade.lua`) |
| window layout / sizes | `Theme.lua` (`sizes`), `UI/Window.lua`, `UI/Summary.lua`, `UI/Rows.lua` |
| compact layout, header | `UI/Compact.lua`, `UI/Header.lua`, `View.buildCompact` |
| Daily farm, waypoints | `View.dailyFarm`, `UI/DailyFarm.lua`, `Waypoint.lua` |
| tooltips | `Tooltip.lua`, `Theme.colors.tip*` |
| fonts | `UI/Fonts.lua`, `Theme.fonts` |
| translations | `Locale.lua`, `Locales/` |
| History, Zones, Totals, CSV export | `History.lua`, `CoreHistory.lua`, `View.buildHistory` / `buildTotals`, `UI/Export.lua` |
| own AH scan | `Scan.lua`, `Sources/Scan.lua`, `CoreScan.lua`, `UI/ScanButton.lua` |
| Trade tab, sales, purchases | `Trade.lua`, `Sources/Sales.lua`, `CoreTrade.lua`, `ViewTrade.lua` (`View.buildTradeItems` / `buildTradeLog`) |
| Mobs tab, drop chances | `Mobs.lua`, `Core.snapshotLoot`, `View.buildMobs`, `UI/ItemTooltip.lua` |
| profiles | `Profiles.lua` |
| options window / minimap | `Options.lua`, `UI/OptionsPanel.lua`, `UI/Minimap.lua` |
| colors, color presets, skins | `OptionsLook.lua`, `Theme.lua` |
| data broker / LibDBIcon | `UI/Broker.lua`, `embeds.xml`, `.pkgmeta` |
| CI / packaging / release | `.gitlab-ci.yml`, `.pkgmeta`, `docs/CHECKLIST.md` (release steps) |
