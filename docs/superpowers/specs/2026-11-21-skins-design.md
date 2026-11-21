# Skins: border, background, button and line styles

Date: 2026-11-21. Status: draft for approval.

## Intent

The player wants more looks for the ledger than today's one: new styles for
the window border, the background, the buttons and the lines, each picked in
the options, with a look like the Blacksmithing window in their screenshot
(dark grained panel, thin bevelled bronze frame, sunken list box, flat dark
buttons with a light edge) as the main inspiration.

## Goals

- Four option pickers, one per part: **Border**, **Background**, **Buttons**,
  **Lines**, plus a **Sunken list** checkbox (the darker inset box behind the
  list rows, from the screenshot).
- A **Skin** dropdown on top that sets all five at once. Changing a single
  part afterwards shows the skin as "(edited)", like the color presets.
- Four skins (mockups shown in the brainstorm, picked by the player):

  | Skin | Border | Background | Buttons | Lines | Sunken list |
  | --- | --- | --- | --- | --- | --- |
  | Classic (default) | Round | Flat | Bronze | Gold | off |
  | Forge | Bevel | Grain | Raised | Groove | on |
  | Slate | Thin | Flat | Flat | Plain | off |
  | Gilded | Gilded | Leather | Bronze | Dotted | off |

- Every part works with every color preset: the styles give the shape and
  shading, the colors still come from `Theme.colors` (panelTint, panelBorder,
  buttonFill / buttonEdge, goldLine / rowSeparator / divider / tabBorder).
- Opacity and brightness keep working on every border and background.
- Switching a skin or part takes effect at once, without /reload.
- The ledger window (full and compact), the options window and the export
  window all follow the picks (they share `Widgets.applyBackdrop`).

## Non-goals

- No layout or size changes: header rows, minimum sizes, row heights and
  insets stay as they are, so `tests/test_overflow.lua` and the size budgets
  in `Theme.sizes` stay valid. (The screenshot's centered title bar and red
  close button are left out for this reason.)
- Skins do not change colors. Gilded looks best with the Blizzard color
  preset; the README says so, but picking a skin never touches the colors.
- No gold section bars (the screenshot's "Reagents" headers): the lists have
  no section headings to put them on. Goes to `docs/BACKLOG.md`.
- No game textures beyond what the addon already uses (unreliable paths on
  Forever).

## Anti-goals

- Classic must look exactly like today; nobody who never opens the option
  sees a change.
- A missing or refused texture must never leave the window without a frame or
  background (fall back to the flat style).

## Approaches considered

1. **Lines plus own textures (picked).** Edges, bevels, grooves and button
   shading are built from 1 px flat lines (`Interface\\Buttons\\WHITE8X8`,
   pixel-snapped with `Widgets.pixels` / `snapPoint`); only what lines cannot
   draw ships as addon textures (grain, leather, gilded edge with corner
   studs, dotted line), drawn by a Python script like the logo. Sharp at any
   scale, tinted by the color presets, always loads.
2. Lines only: no image files, but Grain and Leather would be flat, so Forge
   and Gilded lose the surface texture that the screenshot is about.
3. Game textures: least work, but paths are not confirmed on Forever (see the
   `parchment` comment in `Theme.lua`); a missing one is a green box.

## The parts

**Border** (window frame; also decides the tab shape):
- Round: today's tooltip edge (`frameBorder`), rounded tabs (today).
- Bevel: 1 px dark outer line, 1 px `panelBorder` line, 1 px dark inner line
  (a carved frame). Square tabs.
- Thin: 1 px dark outer line and 1 px `panelBorder` line inside. Square tabs.
- Gilded: a dark outer line and a double `panelBorder` line (lines like
  Bevel), plus a small stud texture `Media\\Skins\\Stud` in each corner,
  grey-scale so `panelBorder` tints it. Square tabs. (Lines instead of a
  backdrop edge file: the edge file's piece layout and rotation are not
  confirmed on Forever; the stud is one plain texture.)

**Background** (window fill, tinted with `panelTint` as today):
- Flat: today's flat tile.
- Grain: `Media\\Skins\\Grain`, a tileable fine noise, near white so the tint
  keeps the preset's color.
- Leather: `Media\\Skins\\Leather`, a tileable soft leather grain.

**Buttons** (every `Widgets.button` / `iconButton`, inputs keep their box):
- Bronze: today's three bands with the inner edge line.
- Raised: one flat fill, a light line on top and left and a dark one at the
  bottom and right (swapped while pressed), from `buttonFill`.
- Flat: one flat fill and a 1 px `buttonEdge` line.
Hover, pressed, disabled and the red warning edge stay in every style.

**Lines** (row separators, the Top finds divider, the tab base line, the
filter underline, option section lines, the compact divider):
- Gold: today (one line in its color).
- Groove: a dark line with a light line right under it (both from the line's
  color, darker and lighter).
- Plain: one line in a neutral mix of the line color and `panelTint`, no gold.
- Dotted: `Media\\Skins\\Dotted`, tiled along the line.

**Sunken list**: a box behind the list rows, `panelTint` darker, with a
groove edge; the rows keep their size and position (the box sits in the
existing padding).

## Where it lives

- `Theme.lua`: the texture paths, `Theme.skinParts` (each part's choices) and
  `Theme.skins` (the four rows of the table above). Pure helpers there or in
  a new pure file: `skin(id)`, `skinEdited(settings)`, the colors a style
  derives (groove dark / light, raised top / bottom), so tests cover them.
- `DB.defaults.settings`: `skin = "classic"`, `skinBorder = "round"`,
  `skinBackground = "flat"`, `skinButtons = "bronze"`, `skinLines = "gold"`,
  `skinListBox = false`. Per profile, like the colors.
- `Options.lua`: a Skin dropdown and the five parts, in the Look section
  above the color preset. Picking a skin writes its five parts (`picked`, as
  `colorPreset` does with the colors). Labels at most 24 characters, German
  texts in `Locales/deDE.lua`.
- `UI/Widgets.lua`: backdrop, button and line drawing read the picks; a
  `Widgets.applySkin()` redraws every tracked region (the `tracked` table
  already lists backdrops, buttons and lines). `UI/Tabs.lua`, `UI/Rows.lua`
  (separators), `UI/Summary.lua`, `UI/Compact.lua`, `UI/FilterBar.lua` and
  `UI/OptionsPanel.lua` draw their lines through the shared line helper.
- `tools/render_skins.py`: draws the four `.tga` files (Grain, Leather,
  Stud, Dotted) into
  `AnotherLedger/Media/Skins/` (Pillow, fixed seed, power-of-two sizes).

## Tests and checks

- Every skin names a valid choice for each part; every texture path in
  `Theme.textures` that points into `Media\\` exists on disk.
- Picking a skin writes its parts; a changed part makes it "(edited)";
  unknown stored values fall back to Classic's part (`Options.normalize`).
- Wiring test: switching skin and each part with the window open runs
  without errors and leaves every backdrop / button / line repainted.
- Overflow test covers the new labels in both languages.
- `docs/CHECKLIST.md`: addon textures as backdrop edge / tiled background,
  the dotted line's horizontal tiling, each skin's look at UI scales 0.64 and
  1.0, opacity and brightness on each background. Marked
  `UNVERIFIED (check in client)` until the player confirms.

## Calls made while writing this up

- Every border stays inside today's 16 px edge / 5 px fill inset, so the
  content inset (padding + 4) does not move.
- The game tooltips (item and rich tooltips) are not skinned.
- Sunken list shows in the full layout only; the compact layout keeps its
  divider line.
- Only the Round border uses a backdrop edge file (today's); the other three
  are drawn as line rectangles inside the frame plus, for Gilded, four studs.
- Styled lines are opt-in (`Widgets.rule`): the goal progress bar and the
  Top finds quality edge stay plain `Widgets.line` regions.

## Left to the builder

- Exact pixel art of the four textures and the grey levels (must read well
  under all four color presets).
- How Groove / Raised derive their dark and light colors (a scale of the
  base color, as `Widgets.BUTTON_*` do today).
- Selected-tab look for square tabs (keep the gold edge and glow).
