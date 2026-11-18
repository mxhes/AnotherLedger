# Review batch: fixes, value rules, Bags, History days, Mobs (design)

From the third review (screenshots of the full window, Bags, Bank, History
Sessions / Zones and every options tab). The player picked these items; the
numbers are the review's.

## Why

The player farms and levels with the ledger open. The screenshots showed
numbers that mislead (an unscanned bank worth "0c", city time lowering a
zone's gold per hour, 22-second History rows, Auction values before the AH
fee, Destroy values a Warrior can't get) and questions the addon can't answer
yet (what is in my bags worth at the vendor vs the AH, what did today earn,
which mob pays). The goal is honest numbers and those answers, without making
the window busier.

## Goals

Small fixes
1. **Zones header count**: History > Zones shows "6 places" in the header like
   Sessions shows "16 sessions" (count of top-level zone rows listed).
2. **Unscanned bank**: the footer shows "—" instead of "0c" until the first
   scan; only one "not scanned" message (keep the list's empty text, drop the
   footer hint, or the other way round: builder's call, one message).
3. **Reset colors** sets the colors back to the *chosen* preset (clears
   "(edited)"), not to the LootLedger preset.
4. **Minimum session length** (option, number of minutes, default 2, 0 = off):
   an automatic split (Session per zone, Session per instance, a new login
   without Keep session) does not archive a session shorter than that; the
   session simply continues (its loot and time carry on into what would have
   been the next one). A manual Reset still archives whatever it has.
   An empty session keeps today's behaviour (clock starts over).
5. **Pause in cities** (option, default on): in a rest area (city, inn) the
   clock stops counting *time*, but loot, raw gold and quest gold still count.
   Leaving the rest area restarts the time. Zones and the Daily farm therefore
   get no rest-area time either. The header shows the clock as paused
   (`Resting` instead of `Paused`), and a manual Stop still wins (the
   player's stopped clock is not restarted on leaving a city).
6. **Session options layout**: Session goal (gold) and Session goal (minutes)
   sit next to each other / in one block with Drop alert and Alert sound.
7. **Zone name truncation**: a place label "Instance (Difficulty)" shortens
   the difficulty first (`(N)`, `(H)`, `(M)`, `(M+)`, else the first letter)
   before the name is cut with "...". The tooltip keeps the full label.
9. **Unpriced hint**: hovering the footer's "2 unpriced" lists those items
   (name and quantity, at most ~10, then "and N more").
11. **Daily pick in Zones**: the subzone the Daily farm picked (and its zone
   row) gets a small star / marker in History > Zones.

Prices
12. **Destroy values** option: `Always` (default, today's behaviour) /
    `If one of my characters can` / `If this character can` / `Never`.
    Each character's professions are saved at login (account-wide table,
    per character). The kind of destroy follows the item: weapons and armor
    need Enchanting, herbs need Inscription, ore needs Jewelcrafting.
    An item whose destroy doesn't count has no `de` value (its row then
    shows Vendor or Auction).
13. **AH cut** option (checkbox, default on): Auction values are 95% of the
    AH price (the 5% auction house fee). Applies to rows, totals, the
    session value, alerts, goals, new History sessions, Zones and the Daily
    farm. Item tooltips show the price after the cut and say so.
14. **Auction from** option (slider, percent over vendor, 0 to 100, default
    0 = off): an item counts as Auction only when its AH value (after the
    cut) is at least that much above its vendor price; else Vendor wins.
    The AH value stays visible in the tooltip.
15. **TSM price** becomes a dropdown: DBMarket, DBMinBuyout,
    DBRegionMarketAvg, DBRecent, DBHistorical, and "Custom..." which opens a
    text box for any TSM price string (today's behaviour). `/ll tsm` keeps
    working.

Bags
16. **Gold on hand** and **Net worth** (items + gold) rows in the Bags footer
    (Bags only; Bank stays as it is).
17. **Sell split** in the tooltip of the Sellable row: what of the sellable
    total is best sold at a vendor, on the AH, or destroyed (by each row's
    best source).
18. **Free bag slots** in the Bags header: "54 items · 9 free" (normal bags
    plus the reagent bag; the tooltip may split them).

History, Daily farm
20. **History > Mobs** sub-tab (third, after Zones): every mob and gathering
    node you looted, across saved sessions plus the running one, following
    **Zones: all characters**. One row per mob (by NPC ID; nodes by object
    ID): name, kills (or nodes looted), value per kill, total value; second
    line: corpses looted and the main place. Sorts: Value, Per kill, Kills,
    Name. Click a mob to list its drops (like a subzone lists its items).
    The footer adds up the listed rows. Header count "14 mobs".
    - Data comes from the loot window: on LOOT_OPENED each slot's source
      GUIDs (GetLootSourceInfo) and link / quantity / money are read; what the
      player actually takes (LOOT_SLOT_CLEARED) is credited to the source
      (a slot shared by several corpses is split by their quantities).
    - Kills come from the combat log: a kill by the player or the group
      (PARTY_KILL with a group source, or UNIT_DIED of a unit the group
      fought) counts for that NPC ID. Mobs killed but never looted (no loot,
      or looted by a group member) still count as kills, so value per kill
      is honest. Nodes have no kills; their row counts nodes looted.
    - Names: from nameplates, target and mouseover (GUID -> name, kept per
      NPC ID), the combat log's dest name, else a tooltip lookup of the GUID;
      saved with the data so old rows keep their name.
    - Stored per session (`session.mobs`) and copied into History entries;
      items valued at the session's saved prices like Zones.
    - Client APIs (GetLootSourceInfo, LOOT_SLOT_CLEARED, COMBAT_LOG_EVENT_
      UNFILTERED / CombatLogGetCurrentEventInfo, the tooltip name lookup) are
      UNVERIFIED on Forever: guard every call, and when the combat log is
      unavailable the Mobs tab still works with looted counts only ("kills"
      column then shows looted).
21. **Day headings in History > Sessions** (only while sorted by Recent):
    one heading row per day for Today, Yesterday and the other days of this
    week, one per week for older sessions ("Week 46"). The heading shows the
    number of sessions, their total time, value and gold per hour. Click a
    heading to fold / unfold its sessions (remembered until logout). Search
    and filters apply to the sessions; a heading only shows when it has
    visible sessions and adds up only those.
22. **Daily farm: my level only** (option, default off): only places whose
    zone level range (the game's map level range, C_Map.GetMapLevels,
    UNVERIFIED) fits the character's level are picked; places without a
    known range are kept.

Window and options
24. Window options (all default off): **Open on first loot** (a hidden
    window opens when the session's first item is counted), **Open in
    instances** (opens on entering a dungeon / raid, hides again on leaving if
    this option opened it), **Hide in cities** (hides in rest areas, comes
    back on leaving if this option hid it). A window the player closed or
    opened by hand is not fought: the options only undo their own action.
25. **Reset profile** button on the Profiles tab: the current profile's
    options back to the defaults (asks first).
26. **Option names**: "Raw gold in Total" -> **Count raw gold**, "Raw gold
    row" -> **Show raw gold row** (German too).

## Non-goals

- The review's other items (Top finds by sort, row icons in History,
  vendor-trash total / Sell junk, the drop alert upgrade, the account-wide
  view of all characters' bags).
- Recomputing old History sessions with the new value rules (see Approaches).
- CSV export of the Mobs tab; mob data for the compact layout.
- Configurable AH fee (it is the fixed 5%).

## Anti-goals

- Losing loot: no option may drop recorded loot or gold (short sessions fold,
  city time stops but loot counts).
- A busier window: new numbers go into tooltips or existing rows where they
  can; the Bags footer grows by two rows only.
- Options that fight the player (auto-show / hide only undo their own action).
- Breaking the pure / client split: all new logic outside `UI/` stays pure and
  tested with plain Lua 5.1.

## Constraints

- Lua 5.1, the project's conventions (CLAUDE.md): options via
  `Options.define` with a default in `DB.defaults.settings`, short labels, a
  tooltip; texts through `ns.L` with German in `Locales/deDE.lua`; money in
  copper; docs updated in the same change; UNVERIFIED comments and
  CHECKLIST lines for client calls that weren't run in the client.
- Saved data must stay small: History keeps 200 sessions per character, so
  `mobs` per entry keeps only NPC ID, name, kills, looted, gold and
  `items = { [key] = qty }`.
- Profiles: new options are profile options except where noted; the saved
  professions table is account-wide data, not an option.

## Approaches

Value rules (12, 13, 14)
- **A (picked): at lookup.** `Prices` applies the AH cut and the Destroy rule
  to what `lookup` returns (the cache keeps the raw AH price), and one best-
  value function with the "Auction from" rule replaces the five places that
  pick the best value today (View rows, `Core.unitValue`, `History.snapshot`,
  `History.totals`, the CSV). New History sessions are saved with adjusted
  prices; old ones keep theirs. Small and safe.
- B: at display. All of History follows the current settings; History would
  rebuild each entry's total from its items on every view. About twice the
  work and slower. Not picked.

Value per mob (20)
- A: loot window only (looted corpses, no kills). Simpler, but value per kill
  would be value per *looted* corpse.
- **B (picked): loot window plus combat log kills.** True kills and value
  per kill; more work and the combat log is unverified on this client, so it
  degrades to A when unavailable.

Bags sell split (17)
- Rows under Sellable (mockup A) or **tooltip only (picked)**: keeps the list
  tall; the footer grows by Gold on hand and Net worth only.

Day totals (21)
- **Day headings, weeks for older (picked)**; alternatives were day headings
  only, or footer lines.

## Decided by the player

City pause = time stops, loot counts. Short sessions fold into the next.
AH cut on by default. Destroy option default Always. Auction from = percent
over vendor. Daily farm filter = my level only. Auto-show = open on first
loot, open in instances, hide in cities (no Esc close). Names = Count raw
gold / Show raw gold row. Bags split in the tooltip. Day headings with weeks.
Mobs under History, following Zones: all characters. Value rules at lookup.
Mob data with combat log kills.

## Builder's calls (marked as proposals)

- Defaults: Minimum session length 2 min; Pause in cities on; Daily farm my
  level only off; window auto-show options off; Auction from 0%.
- Option tabs: Pause in cities, Minimum session length -> Session; AH cut,
  Auction from, Destroy values -> Prices; Daily farm: my level only ->
  History; the three window options -> Window; Reset profile -> Profiles.
- The kind of destroy per item class (Enchanting / Inscription /
  Jewelcrafting) uses the item's class and subclass from GetItemInfo; items of
  other classes count their destroy value under `If ... can` only when the
  character has any of the three.
- Heading fold state and the Mobs drill-down state live on the ledger like
  `zoneOpen`.
- The exact wording of new labels (24 characters at most) and tooltips.
- Pause in cities and Pause when AFK are independent: AFK stops the clock
  fully as today; resting only stops time. A short session kept at login
  (item 4) behaves like Keep session for that one session.
- Auction from: an item with no vendor price (0) counts as Auction whenever
  it has an AH price.
- Mobs follows the session's rules: nothing (loot or kills) is counted while
  the clock is stopped; the ignore list hides items there too; loot without a
  source (bag containers, quest rewards, mail) is not in Mobs. A mob with
  kills but no loot still gets a row (value 0), sorted last.
- Weeks in the day headings start on Monday.
- My level only reads the level range of the map the place's loot positions
  were recorded on; instances use their map too.
- Auto-show / hide never acts in combat when Hide in combat hid the window,
  and never at login when Start hidden is on (it waits for the next trigger).
