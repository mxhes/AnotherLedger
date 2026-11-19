# Button look: gilded two-tone (design)

## Why

The LootLedger scan button looked out of place on the auction house window:
a flat colored block with a thin edge, next to the game's beveled buttons.
The player wants one look for the addon's buttons that fits both the
auction house and the LootLedger window, without copying the game's buttons.

## Approaches

Four mockups were shown: A gilded inset (dark fill, thin gold line inside
the edge), B bronze plate (two-tone bronze), C ledger stamp (red accent strip,
coin mark), D engraved frame (double gold edge). **Picked: A, with a light
top and a dark bottom** (from B), and the split between them **softened**:
the top third light, the bottom third dark, the middle third fading.

## Decided

- Every bronze text button and icon button (`Widgets.button`,
  `Widgets.iconButton`): an outer dark 1 px line, a fill of three bands (top
  light, middle fading, bottom dark), and the preset's edge color as a 1 px
  line just inside the outer line. Inputs, tabs and the window are unchanged.
- Colors come from the preset (no new color options): top =
  `buttonFill` x 1.8, bottom = `buttonFill` x 0.75, outer line = `buttonFill`
  x 0.3. Hover: both halves a little lighter and the hover edge color.
  Pressed (mouse held down): the two halves swap. Disabled and warning as
  before (dim text and edge; red edge and text).
- The middle band uses `Texture:SetGradient("VERTICAL", CreateColor(...))`
  like the tab glow (`UI/Tabs.lua`), `SetGradientAlpha` on older clients,
  else a flat mid color.

## Builder's calls

The factors above are starting values; tune them so the default and the
Blizzard preset read like the mockup.
