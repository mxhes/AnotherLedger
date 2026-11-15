# History "Zones" sub-tab: design

## Intent

The user wants to know **which zones are worth farming**. Today History can only say "this
session was mostly in Waking Shores"; it cannot compare places. The new view adds up the loot of
all saved sessions (plus the running one) per zone / subzone / instance and shows each place's
value, time spent and gold per hour.

## Goals

- A **Zones** sub-tab inside History (next to **Sessions**, the current History list).
- Three levels, using the existing "+ / -" open/close rows:
  zone (or instance + difficulty) -> its subzones -> the items looted there.
- Each zone and subzone row shows: time spent, value (best of vendor / AH / DE, summed, plus raw
  gold), gold per hour.
- Sorting switches between **total value** and **gold per hour** (both available).
- **Quest items** go into their own "Quest items" group at the bottom. They are listed but are
  not counted in any zone total or g/h. **Only in Zones** (user decision): the Session tab, the
  Sessions sub-tab and the totals stored by `History.snapshot` keep counting them, so the
  Sessions and Zones footers may differ by the quest items' value.
- Raw gold (coin loot) is recorded per place and counts toward that place's value and g/h when
  the existing "include raw gold" option is on. (Claude's call, not objected to.)

## Non-goals

- No lifetime record that is never pruned. The view is built **from the saved sessions only**, so
  it follows History (limit, prune, reset). User decision.
- No account-wide view across characters. It is per character, like History. (Claude's call.)
- Currencies are not grouped by zone in v1. (Claude's call: they have no value.)

## Anti-goals

- g/h must not be faked from session-level time. A place without recorded time shows no g/h,
  never an estimate.
- Old saved sessions must keep loading and keep their Sessions view unchanged.

## Constraints (from the project)

- Pure code outside `UI/`, client calls injected. Lua 5.1. Texts through `ns.L` + German.
- New client APIs get `UNVERIFIED (check in client)` + README checklist line:
  `GetSubZoneText`, the `ZONE_CHANGED*` events, the item class ID for quest items.
- Saved variables live in `LootPriceCharDB.history`; old entries have no per-place data.

## Approaches considered (where the view lives)

- **A. Real sub-tabs inside History: picked.** A second button row **Sessions | Zones** shows
  only while History is selected; the last choice is remembered. It is what was asked for,
  keeps the main tab row short, and leaves room for more History views. Costs a new header
  widget and a few pixels while History is shown.
- B. A fifth top-level tab "Zones". Cheapest, but not a sub-tab and crowds the tab row.
- C. A "By zone" toggle in the History header. Cheap, but hard to discover and doesn't read as a view.

## Data

Recording happens in the running session, then is copied into the History snapshot.

- **Place key.** Zone level = `Core.placeOf` today ("Zone" or "Instance (Difficulty)").
  Subzone = `GetSubZoneText()`; empty -> the zone name itself (so every drop has a subzone).
  Inside instances the subzone is used too if the client gives one.
- **Per session**, a new table:
  `zones = { [zone] = { time, gold, subs = { [sub] = { time, gold, items = { [itemKey] = qty } } } } }`
  - `items` holds quantities only; id, link and price stay in `session.items` (no duplication).
  - `time` grows while the session clock runs: the session remembers the current place and since
    when (`placeSince`); on a place change (zone events, entering world), Stop, archive and on
    read, the open stretch is added to the old place. Pure functions in `Session.lua`, `now` passed in.
  - `gold` is added on `CHAT_MSG_MONEY`, at the current place.
- **Quest items** are detected at loot time (item class Quest, or bind type "quest") and flagged
  on the session item (`quest = true`). If item info is not cached yet, decide when it arrives
  (`GET_ITEM_INFO_RECEIVED` already exists) or at view build time.
- **Snapshot** (`History.snapshot`) copies `zones` and the quest flags. The existing `places` count
  stays for the Sessions view.
- **Old sessions** (no `zones`): if `places` has exactly one label, their items go under that zone
  with subzone "Unknown" and **no time**; otherwise under an "Unknown place" group. They add value
  but no g/h.

## View

- `View.buildZones(list, running, opts, open)` (pure) aggregates: for each zone and subzone, the
  summed time, the value (item qty x price from live lookup, saved price fallback, like
  `History.snapshot`) and gold; g/h = `History.perHour`.
- Rows reuse the row layout like `View.buildHistory`: line 1 name + time, line 2 value, the hint
  shows time, value, raw gold and g/h. Open state = which zone and which subzone are expanded
  (ledger state, like `historyIndex`).
- **g/h only from timed loot** (Claude's call): a place's g/h = value of its timed subzones /
  their time. Old loot without time goes into a separate "No time recorded" subzone row; it
  adds to the zone's total but never to its g/h.
- Sorting (Claude's call): the existing single sort setting. A new sort "Gold per hour" is offered
  only while Zones is shown; other tabs treat it as "Best value". In Zones, places sort by
  Best value = total, Gold per hour = g/h (places without time last), Vendor = vendor total,
  Recent = last loot there, Name = name. Items inside a subzone use the same sort, with
  "Gold per hour" falling back to Best value. The filter (search, quality) applies to item rows.
- Raw gold follows the existing "include raw gold" option (`opts.includeGold`), like the
  Sessions view, so the two sub-tabs agree (Claude's call).
- The footer adds up all places, like the Sessions view.
- "Quest items" group: always last, its own value is shown but excluded from the footer totals.

## UI

- Sub-tab row: generic, not History-specific: a tab spec may declare `subtabs = { {key,label,build}, ... }`;
  `UI/Tabs.lua` draws the second row when the selected tab has them. Selection saved in `ns.db`
  (e.g. `db.subtab.history`). Sizes / colors in `Theme.lua`.
- Clicking rows: zone row toggles its subzones; subzone row toggles its items.

## Left to the builder

- Exact event list for place changes, and whether to also check the place on the 1 s tick as a safety net.
- Names of fields / functions, the hint wording, the German texts.
- Whether CSV export gets a per-zone variant (not required).
- Tests: pure tests for time accounting, aggregation, old-entry fallback, quest grouping; a wiring
  test that loots in two zones and checks the Zones view.
- README: feature text, layout table, in-client checklist lines.
