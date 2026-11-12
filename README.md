# LootPrice

WoW Forever addon: a game-styled Session Ledger showing vendor and auction house value of everything you loot.

Design: docs/superpowers/specs/2026-11-12-loot-price-design.md

## What it shows

The Session Ledger is a draggable, resizable, scrollable window:

- **Rows**: one per looted item (icon, quality-colored name, quantity) with the quantity (`xN`) right after the name and the vendor and auction house (AH) values stacked in a block that is right-aligned and adaptive (each amount directly after its label, amounts and labels lined up; the block hugs the right edge and shifts left only as far as the longest amount currently shown needs; the AH age tag follows the AH amount; long names are clipped, the quantity stays visible). Hovering a row shows the item's tooltip. A thin quiet separator line runs between rows. Newly looted rows flash.
- **Money colors**: every amount is shown as `12g 34s 56c` with gold, silver and copper in their own colors (the real game coin colors, bright on the dark panel); `n/a` stays plain.
- **Top finds**: the most valuable finds of the session (hovering one shows its item tooltip), at the bottom of the window under the three summaries, with a gold divider line above it (hidden together with the block when there are no finds).
- **Footer**: three stacked blocks, each under a small muted label and a thin separator line:
  - **Items**: vendor total and AH total with a per-hour rate for each, following the visible (filtered) rows; a small "filtered" marker while a filter is active and the count of items without an AH price.
  - **Raw gold**: gold looted from creatures and containers (including group splits) plus gold from quest turn-ins, as one total with gold per hour. Raw gold is never touched by the item filters; it shows `0c` until the first gold arrives.
  - **Items + gold**: combined Vendor and AH totals with a rate each (raw gold counts equally on both sides; the item part follows the visible rows).
- **Quest rewards**: reward items are ordinary looted items (the client announces them like any other item) and appear in the list; only the money of a quest is tracked as raw gold.
- **Age tag**: any AH price taken from the cache (the source returned nothing) shows its age, for example `(3h)`; the tag turns orange once the price is older than 12 hours.

## Tabs

Three tabs hang below the window's bottom edge; the window, rows, filters and sorts are the same on all of them (the filter bar and sort apply to every tab and are shared):

- **Session**: the loot ledger described above (default).
- **Bags**: every item in your bags (backpack, carried bags, reagent bag), identical stacks merged into one row, valued like loot rows (vendor, AH, age tag). The footer is the single Items block (vendor and AH totals, unpriced count, `filtered` marker); no clock, rates, raw gold or Top finds. The list refreshes when your bags change.
- **Bank**: the same for your bank. The client only lets addons read the bank while its window is open, so LootPrice scans it while you are at the banker and saves the scan per character; away from the bank the tab shows the last scan with a note (`Scanned 3h ago`, orange after 12 h). Before the first visit it says `Open your bank once to scan it.`

The last tab is remembered.

## Events used

`CHAT_MSG_LOOT` (items), `CHAT_MSG_MONEY` (raw gold looted; parsed from `YOU_LOOT_MONEY`, `LOOT_MONEY_SPLIT`, `YOU_LOOT_MONEY_GUILD` (first amount only) and the `GOLD_AMOUNT` / `SILVER_AMOUNT` / `COPPER_AMOUNT` globals), `QUEST_TURNED_IN` (`moneyReward` in copper), `GET_ITEM_INFO_RECEIVED`, `PLAYER_ENTERING_WORLD`, `PLAYER_LOGOUT`, `BAG_UPDATE_DELAYED` (bags tab refresh, bank rescan while the bank is open), `BANKFRAME_OPENED` / `BANKFRAME_CLOSED` (bank scan).

## Requirements

Vendor prices need nothing. AH prices need [TradeSkillMaster](https://www.tradeskillmaster.com/) or Auctionator (both optional). TSM is asked first, then Auctionator. Without either, the AH column shows `n/a`.

## Commands

- `/lp` (or `/lootprice`) - toggle the window
- `/lp show` | `/lp hide` - show or hide the window
- `/lp start` | `/lp stop` - start or stop the session clock
- `/lp reset` - clear the session (asks for confirmation once the session holds 25 or more distinct items)
- `/lp keep on|off` - keep the session across logins
- `/lp tsm <source>` - TSM price source (e.g. `DBMarket`); prices cached under the old source stay in the cache until they refresh
- `/lp demo` - adds fake sample loot, a little gold (12s 40c) and temporarily seeds fake AH prices for a few real item IDs; `/lp reset`, the Reset button and logout remove the fake prices again. Use it only to check the UI (needs a running session).
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
- [ ] `/lp demo` (adds fake loot and temporarily seeds fake AH prices for a few real item IDs; removed again by `/lp reset`, the Reset button and logout, so use it only to check the UI): six rows, 12s 40c of raw gold, quality colors, `n/a` for Light Leather, orange `(14h)` tag on Kingsblood, stale / no-AH rows
- [ ] Loot a vendor item, then `/dump LootPriceCharDB.session.items`
- [ ] `GetCurrentRegionName` and `C_GameRules.GetCurrentGameModeRecordID` return values (cache key non-nil)
- [ ] `CHAT_MSG_LOOT` parsing against the real `LOOT_ITEM_*` globals
- [ ] Logout / relogin with keep on keeps the session; with keep off a real relog starts fresh, while `/reload` keeps the session
- [ ] `GET_ITEM_INFO_RECEIVED` throttle; `C_Timer.After` exists

Window
- [ ] Appears as a dark brown leather panel, the border reads as a frame (edgeSize / insets may need tuning); title readable (ink color on the gold font object)
- [ ] Drag by header; resize with the grip, never below the minimum (422 px high, so the list keeps four rows beside a full Top finds block; at least 350 px wide, wider if the font needs it for the Vendor/AH block); position unchanged after resize ends
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

Tabs (Bags / Bank)
- [ ] Three tab buttons hang under the window's bottom edge (Session, Bags, Bank); the selected one is disabled; the window title changes to Bag Ledger / Bank Ledger; Start / Stop / Reset and the timer hide on Bags and Bank, the X stays
- [ ] Bags: every bag item appears once with its summed stack count; moving, looting, selling and splitting stacks update the list; opening the window on the Bags tab shows current contents
- [ ] Bags footer shows only the Items block (no Raw gold, no Items + gold, no Top finds) and the list uses the freed space; switching back to Session restores all blocks
- [ ] Bank: before any visit the list is empty with "Open your bank once to scan it."; opening the bank fills it; closing the bank and walking away keeps the list with "Scanned ... ago" (orange after 12 h); the scan survives `/reload` and relog
- [ ] `C_Container.GetContainerItemInfo` returns `{ itemID, stackCount, hyperlink }`, and `BANK_CONTAINER`, `NUM_BAG_SLOTS`, `NUM_REAGENTBAG_SLOTS`, `NUM_BANKBAGSLOTS` match the real bag / bank container ids on Forever (`/dump BANK_CONTAINER, NUM_BAG_SLOTS, NUM_REAGENTBAG_SLOTS, NUM_BANKBAGSLOTS`); items in bank bags and the reagent bank/warband bank (if the client has them) are included or deliberately skipped
- [ ] The last tab is restored after `/reload`

Header
- [ ] Title is not overlapped by the timer at 350 px
- [ ] Button look and font (`UIPanelButtonTemplate`); Start / Stop enabled states
- [ ] Reset popup appears and OnAccept resets
- [ ] The X button persists the hidden state across `/reload`

Raw gold and quest rewards
- [ ] Gold looted from a creature, and from a container, appears in the Raw gold total and in the combined totals
- [ ] A group split (`Your share of the loot is ...`) is counted once; with a guild bank cut only the first amount counts
- [ ] Turning in a quest with a gold reward adds that gold to the same Raw gold total; a quest without gold changes nothing
- [ ] A quest reward item shows up as a normal row in the item list
- [ ] Raw gold ignores the item filters and the `filtered` marker stays on the Items block only; Stop ignores gold, Reset clears it, a kept session keeps it across relogs
- [ ] `CHAT_MSG_MONEY` texts match the real `YOU_LOOT_MONEY` / `LOOT_MONEY_SPLIT` / `GOLD_AMOUNT` globals (`/dump YOU_LOOT_MONEY, GOLD_AMOUNT`; the ", " unit separator is assumed)

Summary footer
- [ ] The three footer blocks (146 px: Items 38, Raw gold 16, Items + gold 38, plus an 18 px gold title row each) fit at 350 px wide and 422 px high with the 12 pt font; no line clips: the Raw gold line (`Gold <total>` left, rate right) stays inside the 326 px content width for amounts up to 999g 59s 59c
- [ ] Labels `Items`, `Raw gold`, `Items + gold` are readable (muted) and the thin separator runs to the right of each label
- [ ] Item block worst case `Vendor: 999g 59s 59c` over `999g 59s 59c/h` plus the `N unpriced` / `filtered` marker does not clip (width estimate in `Theme.sizes.summaryCharPx`; raise `minWidth` if it does)
- [ ] No overlap of filtered / unpriced with the rates at long values
- [ ] Gold edge texture visible on the dark panel
- [ ] Top finds sits at the bottom under the summaries; its gold divider line (above it) is visible, disappears with the block when there are no finds, and the list and summaries reflow; the last Top finds value stays clear of the resize grip
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
