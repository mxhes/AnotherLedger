# LootPrice

WoW Forever addon: a game-styled Session Ledger showing vendor and auction house value of everything you loot.

Design: docs/superpowers/specs/2026-11-12-loot-price-design.md

## What it shows

The Session Ledger is a draggable, resizable, scrollable window:

- **Rows**: one per looted item (icon, quality-colored name, quantity) with the vendor value and the auction house (AH) value side by side. Newly looted rows flash.
- **Money colors**: every amount is shown as `12g 34s 56c` with gold, silver and copper in their own colors (the real game coin colors, bright on the dark panel); `n/a` stays plain.
- **Top finds**: the most valuable finds of the session, with a gold divider line between them and the list (hidden together with the block when there are no finds).
- **Totals**: vendor total, AH total and gold per hour for each, following the visible (filtered) rows, in a larger font than the old small one.
- **Filter marker**: a small "filtered" marker while a filter is active.
- **Unpriced count**: how many items have no AH price.
- **Age tag**: any AH price taken from the cache (the source returned nothing) shows its age, for example `(3h)`; the tag turns orange once the price is older than 12 hours.

## Requirements

Vendor prices need nothing. AH prices need [TradeSkillMaster](https://www.tradeskillmaster.com/) or Auctionator (both optional). TSM is asked first, then Auctionator. Without either, the AH column shows `n/a`.

## Commands

- `/lp` (or `/lootprice`) - toggle the window
- `/lp show` | `/lp hide` - show or hide the window
- `/lp start` | `/lp stop` - start or stop the session clock
- `/lp reset` - clear the session (asks for confirmation once the session holds 25 or more distinct items)
- `/lp keep on|off` - keep the session across logins
- `/lp tsm <source>` - TSM price source (e.g. `DBMarket`); prices cached under the old source stay in the cache until they refresh
- `/lp demo` - adds fake sample loot and temporarily seeds fake AH prices for a few real item IDs; `/lp reset`, the Reset button and logout remove the fake prices again. Use it only to check the UI (needs a running session).
- `/lp help` - list the commands

## Settings

- **Keep session across relogs** (`/lp keep on|off`, default off): a real login starts a fresh session by default; with `/lp keep on` the running session (loot, timer) survives logout. A `/reload` is not a new login: it always keeps the session.
- **TSM price source** (`/lp tsm <source>`, default `DBMarket`): the TSM price source string used for AH values.
- Window position, size, visibility, filter and sort are remembered automatically.

## Filters and sorts

- Filters: quality toggles, minimum value (gold), text search. They persist across relogs.
- Sorts: AH value (default, highest first), vendor value, most recent, name.

## Known limit: age tags

TSM and Auctionator return a number without a scan time. The age is the time since the source last returned a price for that item. If the source returns nothing, the last known price is shown with its age. A source that silently serves old scan data looks fresh (also noted in `/lp help`).

## Tests

`lua tests/run.lua` from the repo root (exit code 1 on any failure). Plain Lua, no WoW client needed; the UI cannot be tested outside the client.

## Install / development

Copy or symlink the `LootPrice/` folder into `World of Warcraft/<client>/Interface/AddOns/`. Packaging uses the BigWigs packager (`.pkgmeta`); the `.toc` version is filled in from the git tag.

## Before release

- [x] `## Interface:` number in `LootPrice/LootPrice.toc` confirmed as 16001 (`/dump select(4, GetBuildInfo())` in the Forever client).
- [ ] Verify the packager config (`.pkgmeta`) with a dry run: the zip must contain exactly one `LootPrice/` folder with the `.toc` inside. The first packager dry run decides whether `.pkgmeta` must move into `LootPrice/` (then drop `package-as` and the ignore list).
- [ ] Re-verify the price API signatures in the client (spec risk 1): `TSM_API.GetCustomPriceValue("DBMarket", "i:<itemID>")` and `Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID)`; flagged in code as `UNVERIFIED (check in client)` comments until confirmed.
- [ ] Run the in-client checks below on a fresh `LootPriceDB` / `LootPriceCharDB` (delete the saved-variable files for one launch).

### In-client verification checklist

Core and loot
- [ ] `/reload`: no Lua errors, also on login with the window hidden
- [ ] `/lp help`; `/lp`, `show`, `hide`, `start`, `stop`, `reset`, `keep`, `tsm`
- [ ] `/lp demo` (adds fake loot and temporarily seeds fake AH prices for a few real item IDs; removed again by `/lp reset`, the Reset button and logout, so use it only to check the UI): six rows, quality colors, `n/a` for Light Leather, orange `(14h)` tag on Kingsblood, stale / no-AH rows
- [ ] Loot a vendor item, then `/dump LootPriceCharDB.session.items`
- [ ] `GetCurrentRegionName` and `C_GameRules.GetCurrentGameModeRecordID` return values (cache key non-nil)
- [ ] `CHAT_MSG_LOOT` parsing against the real `LOOT_ITEM_*` globals
- [ ] Logout / relogin with keep on keeps the session; with keep off a real relog starts fresh, while `/reload` keeps the session
- [ ] `GET_ITEM_INFO_RECEIVED` throttle; `C_Timer.After` exists

Window
- [ ] Appears as a dark brown leather panel, the border reads as a frame (edgeSize / insets may need tuning); title readable (ink color on the gold font object)
- [ ] Drag by header; resize with the grip, never below 350x240; position unchanged after resize ends
- [ ] `/reload` keeps position, size and hidden state; `/lp hide` then `/lp show`; `/lp` toggles
- [ ] Changing UI scale / resolution never leaves it off-screen
- [ ] Grip texture shows; the 0.001-height top box does not break the list layout; `setTopBoxHeight(40)` reflows
- [ ] `SetClipsChildren` / `SetResizeBounds` exist on 11.x (`SetMinResize` fallback is included)

Rows and list
- [ ] Mouse wheel and scrollbar scroll; resizing re-lays out rows
- [ ] Looting flashes the row, a hidden row scrolls into view, a stack increase re-flashes
- [ ] An uncached item shows the link name, then corrects on `GET_ITEM_INFO_RECEIVED`
- [ ] The ticker updates only while the session runs

Header
- [ ] Title is not overlapped by the timer at 350 px
- [ ] Button look and font (`UIPanelButtonTemplate`); Start / Stop enabled states
- [ ] Reset popup appears and OnAccept resets
- [ ] The X button persists the hidden state across `/reload`

Summary footer
- [ ] Two-line footer fits at 350 px and 38 px height with the 12 pt font; worst case `Vendor: 999g 59s 59c` over `999g 59s 59c/h` plus the `N unpriced` / `filtered` marker does not clip (width estimate in `Theme.sizes.summaryCharPx`; raise `minWidth` if it does)
- [ ] No overlap of filtered / unpriced with the rates at long values
- [ ] Gold edge texture visible on the dark panel
- [ ] Gold divider line between Top finds and the list is visible, disappears with the block when there are no finds, and does not shift the list rows
- [ ] Dark leather look: ink, quality colors, the orange age tag and the `Top finds` header are readable, the gold divider is visible (colors in `Theme.lua` were tuned by computed contrast only)
- [ ] Colored money: bright gold / silver / copper letters read well on the dark panel in rows, Top finds, totals and the per-hour rates
- [ ] Top finds shows / hides and the list reflows
- [ ] Em dash renders in FRIZQT; rates show an em dash in the first minute
- [ ] `/lp demo` totals match the rows

Filter bar
- [ ] Row 2 layout at 350 px (`InputBoxTemplate` insets and hints)
- [ ] Quality menu stays open on toggle and colors render
- [ ] Minimum gold applies on Enter / blur and reverts on Escape
- [ ] Search narrows live; the sort cycle reorders; the filter underline appears and disappears
- [ ] The filter persists after `/reload`; no keyboard capture when unfocused
