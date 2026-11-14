# LootPrice

WoW **Forever** (retail-engine, Interface 16001) addon in Lua 5.1: a "Session Ledger" window that values everything you loot (vendor + AH price), with Bags / Bank / History tabs. Addon folder is `LootPrice/` inside the repo; `README.md` is the user-facing doc and the in-client verification checklist; `docs/superpowers/` has the original design and plan (history, not kept in sync).

## Commands

- Tests: `lua tests/run.lua` from the repo root (plain Lua, no client; exit 1 on failure). Run after every change; all must pass. Local `lua` is 5.4; GitLab CI (`.gitlab-ci.yml`) also runs Lua 5.1 (the client's version), so write 5.1 code (no `goto`, `//`, `table.unpack`, integer-only APIs).
- No build step. The addon is `LootPrice/*.lua` loaded in the order of `LootPrice/LootPrice.toc`. Release zips come from the BigWigs packager with `LootPrice/.pkgmeta` (`-t LootPrice`); it fetches the libraries into `LootPrice/Libs/` (git-ignored, loaded by `embeds.xml`). The addon must work without `Libs/`.
- Remote: GitLab `origin`, branch `main`. Commits are `feat:` / `fix:` / `refactor:` style, one line summary plus a short body.

## Architecture

- **Pure vs client code.** Files outside `UI/` are plain Lua; every client call is injected or looked up at call time, so tests load them with `h.load({...})`. Files in `UI/` touch WoW globals (`CreateFrame`, ...) only **inside functions**, never at file load.
- **Namespace.** Every file starts `local ADDON, ns = ...` and publishes one table: `ns.Options`, `ns.UI.Window`, ... State: `ns.db` (`LootPriceDB`, account), `ns.chardb` (`LootPriceCharDB`), `ns.session`, `ns.prices`.
- **Load order matters** (the `.toc`): embeds.xml, Util, Locale, Locales/*, Money, Theme, DB, LootParse, Prices, Sources/*, Session, History, Inventory, Options, View, Slash, Demo, UI/Fonts, UI/Widgets ... UI/Ledger, Core last. Core wires events at login (unknown events are skipped); `Core.init` runs only when `CreateFrame` exists.
- **Items are keyed by `LootParse.itemKey(link)`**: the item ID for plain items, `"<id>:<sorted bonus IDs>"` for variants. Session / bank / bag / History item maps, the price cache and row keys (`row.key`, flash, scroll) use it; `item.id` stays the numeric item ID. Price lookups take `(itemID, link)`.
- **Value** of a row is the best of vendor, AH and disenchant (`View.best`); sort key `"ah"` is that value.
- **Registries (add things in one place):**
  - options: `Options.define` in `Options.lua` (+ default in `DB.defaults.settings`, `category` = section). Panel and the options page (`UI/OptionsPanel.lua`) are generated from `Options.entries()`; never name an option in the UI code. Types: slider, dropdown, checkbox, number, text, button.
  - price sources: `ns.Sources.register` in `Sources/*.lua`.
  - tabs: `ns.UI.Tabs.define` in `UI/Tabs.lua`.
  - slash commands: `ns.Slash.define` in `Slash.lua`.
  - ledger parts: `ns.UI.Ledger.register(part)` (`Update` on full redraw, optional `Tick` each second).
- **Data flow.** `Core` events -> `Session` / `Inventory` data -> `UI.Ledger.refresh` builds a view via the shown tab's `build` (`View.lua`, pure) -> each part draws it. Nothing redraws while the window is hidden; it catches up on show.
- **Fonts / sizes.** `UI/Fonts.lua` makes the addon's own copies of the game fonts (`LootPrice<Key>`) and rewrites `Theme.fonts` / `Theme.sizes` once in `Ledger.init`; typeface changes live, px sizes need `/reload`.
- **Look** lives in `Theme.lua` (colors, fonts, sizes); change the look there, not in the UI files.

## Conventions and gotchas

- New `.lua` file: add it to the `.toc` (the wiring test loads files from the `.toc`) and to the README layout table. A new named global frame must be added to the `allowed` list of the "no unexpected globals leak" test in `tests/test_wiring.lua`.
- Tests: `tests/test_*.lua` get the harness as `...` (`h.test`, `h.eq`, `h.near`, `h.load`). `tests/test_wiring.lua` boots the whole addon from the `.toc` against a stub client (fake frames) and drives real events; add a wiring test for anything that crosses files. The real UI cannot be tested outside the client.
- Anything that depends on a client API that was not confirmed carries an `UNVERIFIED (check in client)` comment, and a line in the README in-client checklist. Add both when you rely on a new API, and say in your report that it is not run in the client.
- Saved variables: new settings need a default in `DB.defaults.settings`; `DB.applyDefaults` fills and type-repairs them. Prefer validating through `Options.normalize` over ad-hoc checks.
- Money is always **copper** internally; format with `ns.Money`.
- **Texts** go through `ns.L` (`Locale.lua`, English text as key): `local L = ns.L` then `L["Text"]`, or `local L_X = L["Text"]` at file top. Add the German text to `Locales/deDE.lua`; `tests/test_locale.lua` fails on German keys the code no longer uses. `h.load` loads `Locale.lua` automatically.
- **Backslashes in paths** (`"Interface\\Icons\\..."`, `"Fonts\\FRIZQT__.TTF"`): shell heredocs and `sed` strip them. Write and edit Lua with the Write / Edit tools (or build strings with `chr(92)` in a Python script), then run the tests, which fail on a bad escape.
- The tool environment is Windows with Git Bash; `lua` is on the PATH. Git warns about LF -> CRLF; harmless.
- Update `README.md` (feature text, option list, layout table, in-client checklist) in the same change as the feature.

## Where to look first

| Task | Start in |
| --- | --- |
| a new setting | `Options.lua`, `DB.lua`, then the code that reads it via `Options.get` |
| prices wrong / missing | `Prices.lua`, `Sources/`, `Core.buildPrices` |
| loot not captured | `LootParse.lua`, `Core.lua` (`CHAT_MSG_LOOT`, `CHAT_MSG_MONEY`) |
| what a tab shows | `UI/Tabs.lua`, `View.lua` |
| window layout / sizes | `Theme.lua` (`sizes`), `UI/Window.lua`, `UI/Summary.lua` (`tableLayout`), `UI/Rows.lua` |
| fonts | `UI/Fonts.lua`, `Theme.fonts` |
| translations | `Locale.lua`, `Locales/` |
| History, CSV export | `History.lua`, `View.buildHistory`, `UI/Export.lua` |
| data broker / LibDBIcon | `UI/Broker.lua`, `embeds.xml`, `LootPrice/.pkgmeta` |
| CI / packaging | `.gitlab-ci.yml`, `LootPrice/.pkgmeta` |
| options window / minimap | `UI/OptionsPanel.lua`, `UI/Minimap.lua` |
