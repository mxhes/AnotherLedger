# LootPrice – Design (WoW Forever addon)

Status: draft for approval. Derived from the Docs plan "WoW Forever Loot Price Addon: Plan" plus a brainstorm on 2026-11-12. Where the two differ, this document wins (the toasts were dropped).

## Intent
A Lua addon for the WoW Forever client (modern retail engine and API: retail loot events, `C_Item`, `C_AuctionHouse`). While the player plays, it records everything looted, gathered or crafted and shows what it is worth: the **vendor price** and the **auction house (AH) price**. The player glances at one always-visible screen to see how much money they made, or could make.

The screen should feel like a **game feature**, not a stats overlay on a flat background. That is the main quality bar.

## Goals
- One always-visible **Session Ledger** window showing the session's loot with vendor and AH prices side by side.
- Session totals and gold/hour for vendor and AH separately, plus raw gold (looted and quest money) and an items + gold total.
- A "Top finds" block of the most valuable stacks.
- Player control over the session (start / stop / reset / keep across relogs), the view (filter, sort, size, position) and visibility.
- Everything the player customizes survives relogs.

## Non-goals (first version)
- No toasts / popups on loot. The ledger itself is the feedback.
- No built-in AH scanner, no external price feed (Battle.net web API). Prices come only from TSM / Auctionator that the player already runs.
- No session history UI. The data is shaped so history can be added later (see Data).
- No custom art. Built-in Blizzard textures and fonts only, but the look is isolated so it can be swapped later (see Look).

## Anti-goals (a failure even if it technically works)
- It looks like a generic debug panel or a table on a stale background.
- Totals that silently hide missing data: an item with no AH price must be visibly `n/a`, never a quiet 0 that looks real.
- Stale AH prices shown as if fresh.

## The Session Ledger

### Layout
A parchment-style panel in a stone/wood frame ("quest log" look), titled "Session Ledger".
1. **Header:** session timer, buttons **Start**, **Stop**, **Reset**, **Hide**, a filter control.
2. **Top finds:** highlighted block with the 2-3 most valuable stacks (gold-edged rows). Ranked by AH value, falling back to vendor value when an item has no AH price (builder: pick the exact count and tie-breaking).
3. **Ledger:** scrollable list, one row per item: quality-colored icon frame, item name in quality color, quantity, `Vendor: <money> | AH: <money>`. Rows aggregate by item ID (a stack of the same item is one row with a summed quantity).
4. **Footer:** three stacked blocks, each under a small muted label and a thin separator: **Items** (Vendor total, AH total, gold/hour for each; a small "filtered" marker while a filter is active, "N unpriced"), **Raw gold** (see below) and **Items + gold** (combined Vendor and AH totals with their own gold/hour).

Mock reference: the "A" direction with "Top finds" from "C" (browser mockup, 2026-11-12). Example row: `[Heavy Leather] x24  Vendor: 1g 20s | AH: 4g 50s`.

### Window behavior
- Always on screen by default. A **Hide** button collapses it; a slash command (`/lp`, exact subcommands the builder's call) brings it back.
- Draggable and resizable by the player. Position, size and hidden state persist.
- The list scrolls to accommodate long sessions.

### Loot feedback
- When an item is looted, its row **flashes briefly** so the player can acknowledge it. This applies to a new row and to a quantity increase on an existing row.
- Guess to confirm/implement: a new item scrolls into view; a valuable find gets a stronger flash than a cheap one. Builder's call on the details.

### Filtering and sorting
- Everything looted is recorded; nothing is dropped by default.
- The **player filters the view**: quality toggles, minimum value, text search (guess, agreed as the starting set).
- Default sort: AH value, highest first.
- **Totals and gold/hour follow the visible (filtered) rows.** The totals bar shows a "filtered" marker when a filter is active.
- Filter settings persist across relogs.

## Raw gold
Money is income of its own, next to the item list.
- **Sources:** gold looted from creatures and containers, including group splits and the guild-bank form (`CHAT_MSG_MONEY`, parsed from `YOU_LOOT_MONEY`, `LOOT_MONEY_SPLIT`, `YOU_LOOT_MONEY_GUILD` (first amount only) and the `GOLD_AMOUNT` / `SILVER_AMOUNT` / `COPPER_AMOUNT` globals), and gold from quest turn-ins (`QUEST_TURNED_IN`, `moneyReward` in copper; 0, nil and non-numbers are ignored). Other players' loot is out of scope.
- **Quest reward items need no special handling:** they arrive through `CHAT_MSG_LOOT` like any item and sit in the normal list.
- **Session data:** the session record gains `gold = { looted, quest }` (copper). Stop ignores gold like loot, Reset clears it. A saved record without `gold` (older versions) is migrated with zeros; a malformed `gold` table is replaced by zeros.
- **Filters do not touch raw gold.** The Items block follows the visible rows as before.
- **Footer blocks:** the Raw gold block shows the total with gold/hour and the `looted` / `quest` breakdown (`0c` until the first gold arrives). The Items + gold block combines the item totals (visible rows) with the raw gold on both sides: combined Vendor = item vendor total + raw gold, combined AH = item AH total + raw gold (unpriced items still count 0), each with its own gold/hour (same running-time rule and 60 s minimum as the item rates). The "filtered" marker stays on the Items block only.

## Sessions
- Buttons: **Start**, **Stop**, **Reset**.
- A **new login starts a fresh session** (default).
- Setting **"Keep session across relogs"**: when on, the running session (loot, timer) survives logout via `SavedVariables`.
- **Stop** freezes the timer and ignores new loot until Start. Gold/hour uses running time only, not wall-clock time.
- **Reset** clears loot and timer; asks for confirmation when the session holds a lot of loot (threshold: builder's call).
- No history in the first version, but session data is stored as a self-contained session record (start, running time, items) so a list of past sessions can be added later without a rewrite.

## Prices
- Display: vendor and AH side by side, never only the higher one.
- **AH source:** TSM first, then Auctionator, then `n/a`. Both load on Forever (confirmed).
  - TSM: `TSM_API.GetCustomPriceValue("DBMarket", "i:<itemID>")`. The source string may become a setting.
  - Auctionator: `Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID)`. Fallback when TSM is missing or has no price.
- **Vendor:** always `C_Item.GetItemInfo(link)` `sellPrice` field. Late item data is handled via `GET_ITEM_INFO_RECEIVED`.
- **Missing data:** AH shows `n/a`. In the AH total, items with no AH price count as 0.
- **Stale data:** show the last known AH price with an **age tag**, colored when older than 12 hours (color and tag format are the builder's call; the mock uses orange `(14h)`).
- Forever crafting reagents have no quality tiers, so prices are keyed by plain item ID.
- List TSM and Auctionator under `## OptionalDeps` in the `.toc` so they load first.
- Signatures are to be re-verified against the versions running on Forever when implementing (the plan marked this done; re-check is cheap).

## Cache
- `SavedVariables`, one entry per item ID with a timestamp, so the last known price survives relogs. Updated whenever a fresh price is read.
- Cache key: `{region}-{gameModeRecordID}`. Forever has region-locked rulesets (PvP, Normal, RP, RP PvP) instead of realms. Detect with `C_GameRules.GetCurrentGameModeRecordID()` (readable form `C_GameRules.GetActiveGameMode()`). If the call returns nil early, skip the cache write.
- Game mode record IDs for PvP / Normal / RP / RP PvP, and the name lookup, were confirmed in the plan.

## Loot capture
- Listen to `CHAT_MSG_LOOT` (covers gathering too); parse item link and quantity from the `LOOT_ITEM_SELF` and `LOOT_ITEM_SELF_MULTIPLE` global strings.
- Scope: the player's own loot, gathered items and crafted materials (as in the plan).

## Look (built-in assets, swappable)
- Use built-in Blizzard textures, backdrops and fonts (parchment, dialog/tooltip borders, quality colors, standard coin icons).
- **All look decisions (texture paths, fonts, colors, sizes) live in one module/table** (e.g. `Theme.lua`), so custom art can replace them later without touching logic.

## Module layout (from the plan, toast module removed)
```
LootPrice/
  LootPrice.toc
  Core.lua             -- init, events, saved vars, slash commands
  Sources/Vendor.lua
  Sources/TSM.lua
  Sources/Auctionator.lua
  Prices.lua           -- source priority, cache read/write
  Session.lua          -- session record, start/stop/reset, totals, gold/hour
  Theme.lua            -- all textures, fonts, colors
  UI.lua               -- Session Ledger: frame, rows, top finds, totals, flashes, filter
```

## Settings (persisted)
Window position/size/hidden, filter and sort, keep-session-across-relogs, TSM price source string (optional).

## Packaging and release
GitHub repo (new, separate from the `spells` game), BigWigs packager to CurseForge, Wago and WoWInterface.

## Decided by the player vs. left to the builder
Decided: no toasts; always-visible ledger with hide + slash command; draggable/resizable/scrollable; Start/Stop/Reset + keep-across-relogs (default fresh); everything recorded, player filters, totals follow the filter, filter persists; built-in assets with a swappable theme; history later.

## Calls made by the designer (not decided by the player; check these)
1. **Unverifiable APIs:** the price sources sit behind one thin interface (`GetPrice(itemID)`), so a wrong TSM/Auctionator call is a one-file fix. The first in-client test is to verify each call; unverified calls are flagged in code comments until then.
1a. **Vendor price lookup:** the vendor price is looked up by item ID (`C_Item.GetItemInfo(itemID)`, `Sources/Vendor.lua`) rather than by `GetItemInfo(link)`, because rows aggregate by item ID; scaled gear whose sell price differs per link is an accepted inaccuracy.
2. **Age tag semantics:** TSM/Auctionator return a number with no scan time. Age = time since the source last returned a non-nil price for that item (cache stores `price` and `seenAt`). If the source returns nil, the cached price is shown with its age. Known limit: a source that silently returns old scan data looks fresh. Document this limit in the settings/help text.
3. **Cache use:** every lookup reads the source first; a non-nil result is written to the cache (throttled); nil falls back to the cache; no cache means `n/a`. Prices are looked up when an item is looted and when the ledger redraws (throttled).
4. **Unpriced marker:** the totals bar shows "N unpriced" next to the AH total when rows have no AH price, supporting the anti-goal on hidden missing data.
5. **Loot scope:** the player's own loot (`LOOT_ITEM_SELF`, `_MULTIPLE`), roll wins / pushed loot (`LOOT_ITEM_PUSHED_SELF`, `_MULTIPLE`), and crafted items (`LOOT_ITEM_CREATED_SELF`, `_MULTIPLE`). Out of scope: other players' loot, mail, auction purchases, currencies. Quest reward items are covered by these same messages; quest and looted money is tracked as raw gold (see Raw gold).
6. **Gold/hour** = total / total running time of the session (no rolling window); the same rule applies to the raw gold and combined rates.
7. **Timer across relogs:** only played (running) time counts; time spent logged out does not.
8. **Saved variables:** one account-wide `LootPriceDB` (price cache, window/filter/sort settings) and per-character session data (`LootPriceCharDB`). The `## Interface:` number is read from the Forever client at implementation time.
9. **Game mode nil at load:** retry on `PLAYER_ENTERING_WORLD`; until the key is known, read prices live and do not write the cache.
10. **Tests:** pure logic (`Prices`, `Session`, loot string parsing, totals/filter math) is written without client calls so it can be unit-tested with plain Lua; UI is checked in the client. No Ace3, plain frames.

Builder's call: exact slash subcommands, Top finds count/ranking ties, flash style and duration, age-tag color/format, reset-confirmation threshold, default window size, row layout details, how to test (WoW has no headless runtime; pure logic in `Prices`/`Session` should be unit-testable outside the client).
