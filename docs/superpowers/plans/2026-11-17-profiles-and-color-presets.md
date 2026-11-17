# Settings Profiles and Color Presets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Five color presets that set the whole look, plus named settings profiles (per character) with one-line export and an import box.

**Architecture:** Presets are data in `Theme.lua` applied through a new `colorPreset` dropdown option that runs before the 11 color options. Profiles live in `LootPriceDB.profiles[name]`; at login `ns.db.settings` is pointed at the active one, so every existing `Options.get(ns.db, key)` read keeps working. A few options that act on shared data are marked `account = true` and live in `LootPriceDB.account`. A new pure `Profiles.lua` does list / create / copy / rename / delete / activate and the `LP1:` codec; the options panel gets a Profiles section.

**Tech Stack:** Lua 5.1 (WoW Forever client, Interface 16001), plain-Lua test harness (`lua tests/run.lua`).

**Spec:** `docs/superpowers/specs/2026-11-17-profiles-and-color-presets-design.md`

## Global Constraints

- Lua 5.1 only: no `goto`, `//`, `table.unpack`, integer-only APIs. CI runs 5.1.
- Must work without `Libs/` (no AceDB / AceSerializer / LibDeflate).
- Files outside `UI/` are pure (client calls injected / looked up at call time); `UI/` files touch WoW globals only inside functions.
- Every option: default in `DB.defaults.settings`, `label` ≤ 24 characters, `tooltip`; validated through `Options.normalize`.
- Every new text through `ns.L` with a German entry in `Locales/deDE.lua`; remove German entries for English texts you change.
- Quality colors exact: poor 9d9d9d, common ffffff, uncommon 1eff00, rare 0070dd, epic a335ee, legendary ff8000, artifact e6cc80, heirloom 00ccff. Coins: ffd100 / c7c7cf / eda55f. Never changed by a preset.
- Preset ids and labels: `lootprice` "LootPrice" (default), `blizzard` "Blizzard", `midnight` "Midnight", `tsm` "TSM-style", `parchment` "Parchment".
- Profile names: trimmed, 1..32 characters, unique case-insensitively; "Default" cannot be renamed or deleted.
- Export string prefix `LP1:`; pairs `key=value` joined by `;`; booleans `t`/`f`; integral numbers as `%d`, others `%.17g`; strings percent-encode `%`, `;`, `=`.
- Old `LootPriceDB.settings` is NOT migrated into "Default" (player's decision), except the account-wide keys and `minimapAngle`, which are not profile settings.
- Run `lua tests/run.lua` after every task; all tests pass. Edit Lua with Write/Edit tools (Windows backslash gotcha in CLAUDE.md).
- Commits: `feat:` / `fix:` / `docs:` one-line summary plus a short body.

## Review Focus

1. Pasting garbage, an empty string, a string from a future version (`LP2:`) or a string with only unknown keys into Import → refused with a message, no profile created (Task 6 test `decode rejects ...`).
2. Logging out and in after switching profiles → the active profile is saved once, not twice; `LootPriceDB.settings` is nil in the saved file (Task 5 wiring test `logout clears settings alias`).
3. Deleting the profile another character uses → that character falls back to "Default" at its next login (Task 5 test `activate unknown name falls back to Default`).
4. First login after the update with `historyLimit = -1` (unlimited) saved → stays unlimited; History is not pruned (Task 4 test `migration keeps account options`).
5. Picking a preset, then `/reload` → custom color tweaks made after the pick survive (preset applies first, color options on top) (Task 3 test `applyAll keeps tweaks over preset`).

---

### Task 1: Exact Blizzard quality colors

**Files:**
- Modify: `LootPrice/Theme.lua:400-412` (QUALITY table and its comment)
- Test: `tests/test_theme.lua`

- [ ] **Step 1: Write the failing test** `quality colors are Blizzard's` in `tests/test_theme.lua`: for q = 0..7 compare `Theme.colorToHex({ T.qualityColor(q) })` with `{ [0]="9d9d9d","ffffff","1eff00","0070dd","a335ee","ff8000","e6cc80","00ccff" }`.
- [ ] **Step 2: Run** `lua tests/run.lua` → FAIL on quality 3 (`4a9bff`).
- [ ] **Step 3:** Set QUALITY 3 to `0x00/255, 0x70/255, 0xdd/255` and 4 to `0xa3/255, 0x35/255, 0xee/255` (write all eight as `/255` fractions so the hex round-trips exactly); comment: "the game's exact colors".
- [ ] **Step 4: Run** `lua tests/run.lua` → PASS (the existing "readable on the dark panel" test still passes: both ≈ 3.5:1).
- [ ] **Step 5: Commit** `fix: exact Blizzard rare and epic quality colors`.

### Task 2: Preset palettes in Theme

**Files:**
- Modify: `LootPrice/Theme.lua` (after `Theme.colors`)
- Test: `tests/test_theme.lua`

**Interfaces:**
- Produces:
  - `Theme.FIXED_COLORS = { moneyGold = true, moneySilver = true, moneyCopper = true }` — keys no preset may contain.
  - `Theme.presets` — array of `{ id = string, label = string, colors = { [key] = "rrggbb" }, outline = "OUTLINE"|nil }`; `colors` holds every key of `Theme.colors` except `FIXED_COLORS`.
  - `Theme.preset(id) -> preset|nil`
  - `Theme.applyPreset(id) -> changed` — sets r, g, b of every listed key in place via `Theme.setColor` (alpha kept); returns `{ [colorTable] = true }` for `Widgets.recolor`; unknown id → applies `lootprice`.
  - `Theme.TOOLTIP_BG = { 0, 0, 0 }` — background `tip*` colors are tested against (the game tooltip is near-black).

- [ ] **Step 1: Write failing tests** in `tests/test_theme.lua`:
  - `every preset sets every color`: for each preset, for each key in `T.colors` not in `FIXED_COLORS`, `T.hexToRGB(p.colors[key])` is non-nil; no preset has a FIXED key; ids are exactly `lootprice, blizzard, midnight, tsm, parchment` in that order.
  - `lootprice preset is today's look`: for every key, `p.colors[key] == T.colorToHex(T.colors[key])` taken **before** any applyPreset (snapshot at test start).
  - `presets are readable on their own panel`: for each preset, panel = its `panelTint`; `ink` ≥ 7; `hint`, `gold`, `stale` ≥ 4.5; `tagVendor`, `tagAh`, `tagDe`, `goldLine` ≥ 3; `buttonText` on `buttonFill` ≥ 4.5. For presets without `outline`, also `moneyGold/Silver/Copper` and qualities 0..7 ≥ 3 on the panel.
  - `tooltip colors readable on the game tooltip`: for each preset, `tipTitle`, `tipSection`, `tipLabel`, `tipValue`, `tipNote`, `tipWarn`, `tipHint` vs `TOOLTIP_BG` ≥ 4.5.
  - `parchment uses an outline`: `T.preset("parchment").outline == "OUTLINE"`; others nil.
  - `applyPreset changes colors in place and keeps alpha`: hold `local d = T.colors.divider; local a = d[4]`, apply `midnight`, `d` is the same table, `T.colorToHex(d) == preset.colors.divider`, `d[4] == a`; apply `lootprice` afterwards to restore.
- [ ] **Step 2: Run** → FAIL (`presets` nil).
- [ ] **Step 3: Implement** the four symbols. The `lootprice` entry is generated from the `Theme.colors` defaults at file load (`colorToHex` of each non-fixed key), so it can never drift. The other four are written out in full; start from the spec's sampled table (Blizzard panel ~171008 / bronze bb8429 / red buttons ~670001; Midnight ~081a2e / slate 39404a; TSM 192428 / 253034 / accent dbb431 / buttons 0a1519; Parchment panel d3b289, ink dark brown ~2b1d0e, lines ~6e5536) and adjust until the tests pass. Parchment `tip*` stay light (as LootPrice's).
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: color preset palettes in Theme`.

### Task 3: The Color preset option

**Files:**
- Modify: `LootPrice/Options.lua` (Colors block ~744-799; `Options.set`, `Options.defaultFor`; new `Options.pick`), `LootPrice/DB.lua` (`colorPreset = "lootprice"` in `settings`), `LootPrice/UI/OptionsPanel.lua:26-27` (local `set` calls `Options.pick`)
- Test: `tests/test_options.lua`

**Interfaces:**
- Consumes: `Theme.presets`, `Theme.preset`, `Theme.applyPreset` (Task 2).
- Produces:
  - Spec field `picked = function(db, value)` — run by `Options.pick` only (a player choice in the panel), never by `Options.applyAll`.
  - `Options.pick(db, key, value) -> value` = `Options.set` then `spec.picked(db, v)` if present.
  - `Options.defaultFor(key, settings?)` — for a key in `COLOR_OPTIONS`, returns the color of the preset named by `(settings or ns.db.settings).colorPreset` (its first Theme key); else `DB.defaults.settings[key]`.
  - `Options.presetEdited(settings) -> bool` — any of the 11 color options differs from `defaultFor(key, settings)`.

- [ ] **Step 1: Write failing tests** in `tests/test_options.lua` (load with Theme, DB, Options as the file already does):
  - `colorPreset is the first Colors option, a dropdown of five`: first spec with `category == "colors"` has key `colorPreset`; choices values in order `lootprice, blizzard, midnight, tsm, parchment`; label ≤ 24.
  - `picking a preset writes the 11 colors`: `Options.pick(db, "colorPreset", "midnight")` → each `db.settings[colorKey] == T.preset("midnight").colors[firstThemeKey]`; `Theme.colors.panelTint` hex equals midnight's.
  - `picking parchment turns the outline on`: `db.settings.fontOutline == "OUTLINE"` after pick; picking `midnight` afterwards does not change `fontOutline`.
  - `applyAll keeps tweaks over preset`: settings `{ colorPreset = "tsm", colorText = "ff0000" }` → `Options.applyAll(db)` → `T.colorToHex(T.colors.ink) == "ff0000"` and `T.colors.panelTint` is TSM's; `db.settings.colorText` still `"ff0000"`.
  - `edited marker`: after pick `midnight`, `valueText(spec, "midnight") == "Midnight"`; after `Options.set(db, "colorText", "ff0000")` it is `"Midnight (edited)"`.
  - `right-click default is the preset's color`: under `midnight`, `Options.defaultFor("colorBackground")` == midnight `panelTint`.
  - `Reset colors picks LootPrice`: action → `db.settings.colorPreset == "lootprice"` and all 11 colors equal DB defaults.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.** Define `colorPreset` (type dropdown, category colors, label `L["Color preset"]`, tooltip `L["Sets the whole look of the window, the buttons and the tooltips at once. You can change single colors afterwards."]`) **before** the `COLOR_OPTIONS` loop so `applyAll` applies it first. `apply(v)`: `Theme.applyPreset(v)`, `Widgets.recolor(changed)`, `applyWindowLook()`, `refreshUI()`. `picked(db, v)`: `Options.set` each of the 11 color options to the preset value; if `preset.outline` then `Options.set(db, "fontOutline", preset.outline)`. `format(v)`: label plus `L[" (edited)"]` when `Options.presetEdited(ns.db and ns.db.settings)`. Reset colors action: `Options.pick(ns.db, "colorPreset", "lootprice")`, then `panel.refreshAll()`. In `OptionsPanel.lua` the local `set` becomes `ns.Options.pick(ns.db, spec.key, value)`; color right-click keeps using `defaultFor(spec.key)` (now preset-aware). Panel must refresh all widgets after a preset pick (call `Panel.refreshAll()` from `picked` via `ns.UI.OptionsPanel` lookup).
- [ ] **Step 4: Run** → PASS. Add German for the two new texts and `" (edited)"` in `Locales/deDE.lua`.
- [ ] **Step 5: Commit** `feat: color preset option`.

### Task 4: Account-wide options and minimap angle

**Files:**
- Modify: `LootPrice/Options.lua` (`Options.get`, `Options.set`; `account = true` on `historyLimit`, `accountZones`, `minimapButton`), `LootPrice/DB.lua` (new `account = {}` and `minimapAngle = 225` at top level of `DB.defaults`; remove `minimapAngle` from `settings`), `LootPrice/UI/Minimap.lua:44,55,111`, `LootPrice/UI/Broker.lua:113,131`
- Test: `tests/test_options.lua`, `tests/test_minimap.lua`, `tests/test_db.lua`

**Interfaces:**
- Produces: spec field `account = true` → `Options.get(db, key)` reads `db.account[key]`, `Options.set` writes `db.account[key]` (creating `db.account`). Defaults stay in `DB.defaults.settings`. Angle read/written at `ns.db.minimapAngle`.
- Produces: `DB.migrateAccount(db)` — pure; once (`db.accountMigrated ~= true`): copy `historyLimit`, `accountZones`, `minimapButton` from `db.settings` into `db.account` when present, copy `db.settings.minimapAngle` to `db.minimapAngle`; set `db.accountMigrated = true`.

- [ ] **Step 1: Write failing tests:**
  - `account options read and write db.account`: `Options.set(db, "historyLimit", -1)` → `db.account.historyLimit == -1`, `db.settings.historyLimit == nil`; `Options.get` returns -1.
  - `migration keeps account options` (`tests/test_db.lua`): `db = { settings = { historyLimit = -1, accountZones = false, minimapButton = false, minimapAngle = 90, alpha = 0.5 } }` → `DB.migrateAccount(db)` → `db.account` has the three values, `db.minimapAngle == 90`; second call changes nothing.
  - Update `tests/test_minimap.lua` expectations from `settings.minimapAngle` to `db.minimapAngle`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement**; call `DB.migrateAccount(LootPriceDB)` in `Core.events.ADDON_LOADED` right after `applyDefaults`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `refactor: account-wide options outside the settings table`.

### Task 5: Profiles (saved, per character)

**Files:**
- Create: `LootPrice/Profiles.lua` (after `Options.lua` in `LootPrice/LootPrice.toc`; add to the layout table in `docs/DEVELOPMENT.md`)
- Modify: `LootPrice/DB.lua` (`profiles = {}` in `DB.defaults`; `profile = "Default"` in `DB.charDefaults`), `LootPrice/Core.lua` (`ADDON_LOADED`, `PLAYER_LOGOUT`)
- Test: `tests/test_profiles.lua` (new), `tests/test_wiring.lua`

**Interfaces:**
- Consumes: `Options.applyAll`, `DB.applyDefaults`, `DB.defaults.settings`.
- Produces (`ns.Profiles`, all pure; `db` = LootPriceDB, `chardb` = LootPriceCharDB):
  - `Profiles.DEFAULT = "Default"`, `Profiles.MAX_NAME = 32`
  - `Profiles.init(db, chardb)` — once (`db.profilesMigrated ~= true`): `db.profiles = { Default = {} }`, `db.profilesMigrated = true` (old `db.settings` is dropped). Always: ensure `db.profiles.Default`; if `chardb.profile` names no profile → `"Default"`; `db.settings = DB.applyDefaults(db.profiles[name], DB.defaults.settings)`.
  - `Profiles.names(db) -> { string }` — "Default" first, rest sorted case-insensitively.
  - `Profiles.active(chardb) -> string`
  - `Profiles.validName(db, name, except?) -> trimmed | nil, errorText` — errors `L["Enter a name."]`, `L["The name is too long."]`, `L["A profile with this name exists."]`.
  - `Profiles.create(db, name, from?) -> ok, err` — `from` = a settings table to deep-copy, else empty.
  - `Profiles.rename(db, chardb, old, new) -> ok, err` (refuses Default; updates `chardb.profile` if it was `old`)
  - `Profiles.delete(db, chardb, name) -> ok, err` (refuses Default; active → switch to Default)
  - `Profiles.activate(db, chardb, name)` — sets `chardb.profile`, points `db.settings`, then `Options.applyAll(db)` (looked up at call time).
  - `Profiles.beforeLogout(db)` — `db.settings = nil`.

- [ ] **Step 1: Write failing tests** in `tests/test_profiles.lua`: `init drops old settings` (old `alpha = 0.5` → `Options.get(db,"alpha") == 1`); `init keeps profiles on later logins`; `activate unknown name falls back to Default`; `create, copy, rename, delete` (copy is a deep copy; rename case-only `foo`→`Foo` allowed; duplicate refused case-insensitively; 33 chars refused; Default rename/delete refused); `delete active profile switches to Default`; `names order`. In `tests/test_wiring.lua`: `logout clears settings alias` — boot, fire `PLAYER_LOGOUT`, `LootPriceDB.settings == nil`, `LootPriceDB.profiles.Default` holds the options; `switching profile applies the look` — create profile with `colorPreset = "midnight"`, activate, `Theme.colors.panelTint` is Midnight's.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `Profiles.lua`; in `Core.events.ADDON_LOADED` call `ns.Profiles.init(ns.db, ns.chardb)` after `DB.migrateAccount`; in `PLAYER_LOGOUT` call `ns.Profiles.beforeLogout(ns.db)` last.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: settings profiles per character`.

### Task 6: Export / import codec

**Files:**
- Modify: `LootPrice/Profiles.lua`
- Test: `tests/test_profiles.lua`

**Interfaces:**
- Produces:
  - `Profiles.encode(settings) -> string` — `"LP1:"` + pairs for every registered non-button, non-account option whose `Options.normalize`d value differs from `Options.defaultFor(key, settings)` (colors compare against the profile's own preset); keys sorted for a stable string. Empty profile → `"LP1:"`.
  - `Profiles.decode(text) -> settings, taken, skipped` or `nil, errorText` — trims whitespace; refuses without `LP1:` prefix (`L["This is not a LootPrice profile."]`) and when nothing usable (`L["Nothing to import."]`). A pair is taken only when the key is a registered non-button, non-account option and `Options.normalize(spec, parsed) == parsed`; else skipped. `colorPreset` is decoded before colors.

- [ ] **Step 1: Write failing tests:** `encode only changed values` (defaults → `"LP1:"`; `alpha = 0.5, coinIcons = false` → `"LP1:alpha=0.5;coinIcons=f"`); `encode keeps large numbers` (`goalGold = 123456789` → contains `goalGold=123456789`); `round trip` (a settings table with a preset, a tweaked color, a string font path containing `;` and `=`, numbers, booleans → `decode(encode(s))` yields equal normalized values); `decode skips unknown and invalid` (`"LP1:alpha=0.5;nope=1;alpha2=x;windowScale=9"` → taken 1, skipped 3 — out-of-range slider is skipped, not clamped); `decode rejects garbage` (`""`, `"hello"`, `"LP2:alpha=1"`, `"LP1:nope=1"` → nil + message); `decode ignores account options` (`historyLimit=5` skipped).
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: profile export and import strings`.

### Task 7: Profiles section in the options, import box, docs

**Files:**
- Modify: `LootPrice/Options.lua` (`CATEGORIES` gains `{ id = "profiles", label = L["Profiles"] }` last; new options), `LootPrice/UI/Export.lua` (editable mode), `LootPrice/Locales/deDE.lua`, `README.md`, `docs/DEVELOPMENT.md`, `docs/CHECKLIST.md`
- Test: `tests/test_options.lua`, `tests/test_wiring.lua`

**Interfaces:**
- Consumes: everything from Task 5 and 6; `Widgets.prompt(text, accept, initial, onAccept)`, `Widgets.confirm(text, accept, onAccept)`, `Export.show(text, title)`, `ns.Util.print`-style chat message (use the existing `Util` message helper).
- Produces: `Export.edit(title, onAccept)` — the same window, text editable and empty, an extra bronze button `L["Import"]` bottom right that calls `onAccept(text)`; `Export.show` restores read-only mode and hides that button.
- New optional spec fields `get = function() -> value` and `store = function(value)`: when present, `Options.get` returns `spec.get()` and `Options.set` calls `spec.store(v)` instead of touching `db.settings`; such options are skipped by `Options.applyAll`, `encode` and `decode`. Dropdown normalize for them checks against their (dynamic) choices as usual.
- Options (category `profiles`, nothing stored in settings):
  - `profile` dropdown, label "Profile": `choices` = function over `Profiles.names(ns.db)`; `get = function() return Profiles.active(ns.chardb) end`; `store = function(v) Profiles.activate(ns.db, ns.chardb, v) end`.
  - Buttons: `profileNew` "New profile", `profileCopy` "Copy profile", `profileRename` "Rename profile", `profileDelete` "Delete profile", `profileExport` "Export profile", `profileImport` "Import profile". New/Copy/Rename use `Widgets.prompt` + `Profiles.validName` (error → chat message, nothing changes); Delete uses `Widgets.confirm`; Export → `Export.show(Profiles.encode(ns.db.settings), L["Profile export"])`; Import → `Export.edit(L["Profile import"], fn)` → `decode` (error → chat) → `Widgets.prompt` for the name → if it exists, `Widgets.confirm(L["Overwrite this profile?"])` → `Profiles.create` (replace) + `activate` → chat `L["Imported %d settings, skipped %d."]`. After every change `OptionsPanel.refreshAll()`.
  - Panel `Widgets.PROMPT_MAX_LETTERS` stays 60; names are capped by `validName`.

- [ ] **Step 1: Write failing tests:** `profiles section` (section order ends with `profiles`; labels ≤ 24; all have tooltips); wiring `import through the box creates and activates a profile` (drive `Export.edit`'s onAccept with an encoded string from another profile, answer the prompt with "Farm" via the fake StaticPopup, then `Profiles.active(LootPriceCharDB) == "Farm"`); wiring `new global frames allowed` (add any new named frame to `allowed`).
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement**; German texts for every new string.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Docs:** README: Color preset and Profiles sections (player words, no API names); note that settings start fresh after the update. DEVELOPMENT: `Profiles.lua`, saved-state changes (`profiles`, `account`, `minimapAngle`, `chardb.profile`, `settings` alias cleared at logout), preset data, `account` / `picked` / `get` spec fields. CHECKLIST: the import box (paste of a long line, Ctrl+V) and the five presets look as intended in the client — mark UNVERIFIED where an API was not run in the client.
- [ ] **Step 6: Run** `lua tests/run.lua` → PASS. **Commit** `feat: profiles section with export and import`.
