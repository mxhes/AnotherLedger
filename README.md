# LootPrice

WoW Forever addon: a game-styled Session Ledger showing vendor and auction house value of everything you loot.

Design: docs/superpowers/specs/2026-11-12-loot-price-design.md

## What it shows

The Session Ledger is a draggable, resizable, scrollable window:

- **Rows**: one per looted item (icon, quality-colored name, quantity) with the vendor value and the auction house (AH) value side by side. Newly looted rows flash.
- **Top finds**: the most valuable finds of the session.
- **Totals**: vendor total, AH total and gold per hour for each, following the visible (filtered) rows.
- **Filter marker**: a small "filtered" marker while a filter is active.
- **Unpriced count**: how many items have no price.
- **Age tag**: an AH price older than 12 hours is shown in orange with its age, for example `(14h)`.

## Requirements

Vendor prices need nothing. AH prices need [TradeSkillMaster](https://www.tradeskillmaster.com/) or Auctionator (both optional). TSM is asked first, then Auctionator. Without either, the AH column shows `n/a`.

## Commands

- `/lp` - toggle the window
- `/lp show` | `/lp hide` - show or hide the window
- `/lp start` | `/lp stop` - start or stop the session clock
- `/lp reset` - clear the session
- `/lp keep on|off` - keep the session across logins
- `/lp tsm <source>` - TSM price source (e.g. `DBMarket`)
- `/lp demo` - adds fake sample loot and temporarily seeds fake AH prices for a few real item IDs; `/lp reset`, the Reset button and logout remove the fake prices again. Use it only to check the UI.
- `/lp help` - list the commands

## Settings

- **Keep session across relogs** (`/lp keep on|off`, default off): a new login starts a fresh session by default; with `/lp keep on` the running session (loot, timer) survives logout.
- **TSM price source** (`/lp tsm <source>`, default `DBMarket`): the TSM price source string used for AH values.
- Window position, size, visibility, filter and sort are remembered automatically.

## Filters and sorts

- Filters: quality toggles, minimum value (gold), text search. They persist across relogs.
- Sorts: AH value (default, highest first), vendor value, most recent, name.

## Known limit: age tags

TSM and Auctionator return a number without a scan time. The age is the time since the source last returned a price for that item. If the source returns nothing, the last known price is shown with its age. A source that silently serves old scan data looks fresh.

## Tests

`lua tests/run.lua` from the repo root (exit code 1 on any failure). Plain Lua, no WoW client needed; the UI cannot be tested outside the client.

## Install / development

Copy or symlink the `LootPrice/` folder into `World of Warcraft/<client>/Interface/AddOns/`. Packaging uses the BigWigs packager (`.pkgmeta`); the `.toc` version is filled in from the git tag.

## Before release

- [ ] Confirm the `## Interface:` number in `LootPrice/LootPrice.toc` (currently 110207, a placeholder): `/dump select(4, GetBuildInfo())` in the Forever client.
- [ ] Verify the packager config (`.pkgmeta`) with a dry run: the zip must contain exactly one `LootPrice/` folder with the `.toc` inside. The first packager dry run decides whether `.pkgmeta` must move into `LootPrice/` (then drop `package-as` and the ignore list).
- [ ] Re-verify the price API signatures in the client (spec risk 1): `TSM_API.GetCustomPriceValue("DBMarket", "i:<itemID>")` and `Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID)`; flagged in code comments until confirmed.
- [ ] Run the in-client checks below on a fresh `LootPriceDB` / `LootPriceCharDB` (delete the saved-variable files for one launch).

### In-client verification checklist

Core and loot
- [ ] `/reload`: no Lua errors, also on login with the window hidden
- [ ] `/lp help`; `/lp`, `show`, `hide`, `start`, `stop`, `reset`, `keep`, `tsm`
- [ ] `/lp demo` (adds fake loot and temporarily seeds fake AH prices for a few real item IDs; removed again by `/lp reset`, the Reset button and logout, so use it only to check the UI): six rows, quality colors, `n/a` for Light Leather, orange `(14h)` tag on Kingsblood, stale / no-AH rows
- [ ] Loot a vendor item, then `/dump LootPriceCharDB.session.items`
- [ ] `GetCurrentRegionName` and `C_GameRules.GetCurrentGameModeRecordID` return values (cache key non-nil)
- [ ] `CHAT_MSG_LOOT` parsing against the real `LOOT_ITEM_*` globals
- [ ] Logout / relogin with keep on; with keep off a new login starts fresh
- [ ] `GET_ITEM_INFO_RECEIVED` throttle; `C_Timer.After` exists

Window
- [ ] Appears tan tinted, border looks right (edgeSize / insets may need tuning); title readable (ink color on the gold font object)
- [ ] Drag by header; resize with the grip, never below 320x240; position unchanged after resize ends
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
- [ ] Title is not overlapped by the timer at 320 px
- [ ] Button look and font (`UIPanelButtonTemplate`); Start / Stop enabled states
- [ ] Reset popup appears and OnAccept resets
- [ ] The X button persists the hidden state across `/reload`

Summary footer
- [ ] Two-line footer fits at 320 px and 24 px height (small font height about 10)
- [ ] No overlap of filtered / unpriced with the rates at long values
- [ ] Gold edge texture visible on the parchment
- [ ] Top finds shows / hides and the list reflows
- [ ] Em dash renders in FRIZQT; rates show an em dash in the first minute
- [ ] `/lp demo` totals match the rows

Filter bar
- [ ] Row 2 layout at 320 px (`InputBoxTemplate` insets and hints)
- [ ] Quality menu stays open on toggle and colors render
- [ ] Minimum gold applies on Enter / blur and reverts on Escape
- [ ] Search narrows live; the sort cycle reorders; the filter underline appears and disappears
- [ ] The filter persists after `/reload`; no keyboard capture when unfocused
