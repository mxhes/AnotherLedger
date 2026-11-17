# Settings profiles and color presets

## Why

The player wants to (a) share their setup with friends or between accounts,
(b) give different characters different setups, and (c) keep a few setups to
switch between. Today every option lives once per account in
`LootPriceDB.settings`, and the look can only be changed color by color.
Screenshots of Blizzard frames, the Friends list, the Spellbook and TSM were
the starting point for ready-made looks, including a light one.

## Goals

1. **Color presets**: one dropdown sets the whole look of the addon.
2. **Saved profiles**: named sets of options, account-wide, chosen per character.
3. **Export / import**: a profile as one line of text; paste a line to create a profile.

## Non-goals

- No frame art: presets recolor; the window edge texture, buttons and icons stay.
- No AceDB / AceSerializer / LibDeflate: the addon must run without `Libs/`.
- No per-preset fonts beyond the Parchment outline (below).
- Window position and size, full/compact layout, filters, sort, the ignore and
  keep lists, History and the minimap angle are not part of a profile.

## Anti-goals

- Item quality and coin colors must never change with a preset.
- An import must never overwrite an existing profile without asking, and a bad
  string must never break the settings (invalid values are skipped).

## Part 1: Color presets

### Behavior

- New dropdown option `colorPreset` at the top of the Colors section, label
  "Color preset". Choices: **LootPrice** (default, today's dark leather),
  **Blizzard**, **Midnight**, **TSM-style**, **Parchment**.
- Picking a preset sets **every** `Theme.colors` key (about 45: text, titles,
  hints, tags, panel, border, buttons incl. warn/hover/disabled, inputs,
  dividers, row separator, flashes, tab edges/glow/text, scrollbar, market
  colors, all `tip*`, stale) and writes the 11 color options (`colorText` ...
  `colorButtons`) to the preset's values, so they show the new look and can be
  tweaked afterwards.
- After a tweak of one of the 11 colors the dropdown shows "<Preset> (edited)".
  Picking the preset again resets to the pure preset. "Reset colors" = the
  LootPrice preset.
- **Parchment** additionally sets `fontOutline` to `"OUTLINE"` when picked
  (only at the moment of picking; the player may turn it off again).
- Brightness and Opacity keep working on every preset.
- Right-click "default" on one of the 11 color options sets the **active
  preset's** value (so the "(edited)" marker clears); export compares the
  colors against the preset too. (Builder's call, accepted.)
- **Tooltips** are the game's shared `GameTooltip`, which stays dark on every
  preset; it is not restyled. The `tip*` colors are part of each preset but
  must stay readable on that dark tooltip (Parchment uses light/warm `tip*`
  colors, not its dark brown text). Contrast tests check `tip*` against the
  tooltip background, not the preset's panel. (My call.)

### Fixed colors

Quality and coin colors are fixed at Blizzard's exact values, whatever the preset:

| | hex |
| --- | --- |
| poor | 9d9d9d |
| common | ffffff |
| uncommon | 1eff00 |
| rare | **0070dd** (today 4a9bff) |
| epic | **a335ee** (today c25bff) |
| legendary | ff8000 |
| artifact | e6cc80 |
| heirloom | 00ccff |
| gold / silver / copper | ffd100 / c7c7cf / eda55f (unchanged) |

### Starting palettes (sampled from the screenshots; builder refines)

| Preset | Panel | Border / accent | Buttons | Text |
| --- | --- | --- | --- | --- |
| LootPrice | 261a0f | 8c6b3d, gold lines | 1a120a | white, gold titles |
| Blizzard | ~171008 | bronze bb8429, gold lines | deep red ~670001 with gold edge | white, gold ffd100 titles |
| Midnight | ~081a2e | slate blue ~39404a, light-blue accents | dark navy | white, gold titles |
| TSM-style | 192428 | 253034 cards, gold-orange dbb431 accent | 0a1519 | white, green/red values |
| Parchment | d3b289 | brown ~6e5536 lines | darker tan | dark brown text, dark brown titles |

### Data model

- Presets live in `Theme.lua` as data: `Theme.presets = { { id, label, colors = { key = "rrggbb", ... }, alphas? , font? } }`,
  a full map of every color key per preset (a test checks completeness).
- Saved state: `colorPreset` (the id) plus the 11 color options. On load:
  apply the preset's full palette, then the 11 color options on top.
- "(edited)" = any of the 11 options differs from the preset's value (computed,
  not stored).

### Tests

- Every preset defines every key of `Theme.colors` with a valid hex.
- Contrast is checked per preset against that preset's own panel: text,
  titles, hints, tags vs panel at least the current thresholds. For Parchment
  the fixed quality/coin colors are exempt (they rely on the outline); for
  dark presets the quality and coin colors are checked too.
- Quality and coin colors equal the table above.
- Picking a preset writes the 11 options; tweaking one makes the label
  "(edited)"; Parchment sets `fontOutline`.

## Part 2: Saved profiles

### Behavior

- Profiles are account-wide: `LootPriceDB.profiles = { [name] = settings }`.
  Each character stores its active profile name in `LootPriceCharDB.profile`;
  missing or unknown -> "Default".
- **Migration (player's decision):** the old `LootPriceDB.settings` is NOT
  carried over. After the update "Default" starts with the addon defaults;
  the old table is dropped. `minimapAngle` (not an option, a position) moves
  out of the profile to the top level of `LootPriceDB` and is kept.
- New options section **Profiles** (`Options.CATEGORIES`, last):
  - dropdown "Profile": all names, sorted, "Default" first; switching applies
    every option immediately (`Options.applyAll`) incl. the look.
  - **New**: asks for a name, starts from defaults.
  - **Copy**: asks for a name, starts from the current profile.
  - **Rename**, **Delete** (with confirmation; "Default" can be neither; a
    character using a deleted profile falls back to "Default").
  - **Export**, **Import** (Part 3).
- Names: trimmed, 1..32 characters, unique (case-insensitive); refused with a
  message otherwise.
- **Account-wide options (not in a profile, not exported):** options that act
  on data or UI shared by all characters stay in `LootPriceDB` itself:
  `historyLimit` (the History is account-wide; a low limit on one profile
  would delete other characters' sessions), `accountZones`, and
  `minimapButton` (LibDBIcon's hide state is account-wide). They are marked
  with `account = true` in `Options.define`; `Options.get/set` read and write
  them at `LootPriceDB.account[key]` (or similar), and the panel shows them as
  usual. (My call.)

### Data model / code

- All code keeps reading options through `Options.get(ns.db, key)` and the
  few direct `ns.db.settings.x` reads (Core.lua) keep working: at login,
  `ns.db.settings` is pointed at the active profile table.
- Builder must make sure the active profile is not saved twice (the alias
  `settings` and `profiles[name]` would serialize as two separate copies):
  clear the alias on `PLAYER_LOGOUT`, or store profiles so the alias is not
  a saved field.
- New pure file `Profiles.lua` (`ns.Profiles`): list, create, copy, rename,
  delete, activate, export, import. UI glue in the options panel.

## Part 3: Export / import

- **Export** opens the existing copy window (`UI/Export.lua`, `Export.show`)
  with one line: `LP1:` followed by `key=value` pairs separated by `;`, only
  options that differ from the defaults. Values: booleans `t`/`f`, numbers as
  whole numbers when integral, else `%.17g` (no precision loss), strings escaped (`%`, `;`, `=` percent-encoded). Includes
  `colorPreset` and the 11 colors.
- **Import** opens a box (paste field + name field + Import button). It parses
  the line, skips unknown keys and values `Options.normalize` would change,
  creates a new profile with the given name and switches to it. If the name
  exists, ask "Overwrite?" first. Message after import: "Imported N settings,
  skipped M."
- A string without the `LP1:` prefix or with nothing usable is refused with a
  message; nothing is created.

## Approaches considered

- **Own profile code and text format (chosen).** Works without `Libs/`, fits
  the existing Options registry, string is readable.
- AceDB-3.0 profiles + AceSerializer/LibDeflate: standard for addons, but needs
  libraries the addon must not depend on.
- Presets that change only the 11 color options: simple, but cannot produce the
  TSM or Parchment looks (gold lines, tabs, scrollbar stay gold-brown). Rejected
  by the player.

## Player's decisions

- Presets change the whole look; light presets are allowed.
- Quality and coin colors fixed at exact Blizzard values.
- Preset list: LootPrice, Blizzard, Midnight, TSM-style, Parchment.
- Parchment readability via a dark text outline.
- Profiles: saved inside, export string and import box, per-character choice.
- Current settings are not migrated; settings may change after the update.

## Left to the builder

- Exact hex values of each preset (start from the table, check in tests and
  against the screenshots).
- Exact dialog widgets (reuse `Widgets.confirm`, the Export window, `text`
  option boxes where it fits).
- Locale strings (English keys + German in `Locales/deDE.lua`).
- Docs: README (presets, profiles), DEVELOPMENT (Profiles.lua, saved state,
  presets), CHECKLIST (anything unverified in the client, e.g. the import box).
