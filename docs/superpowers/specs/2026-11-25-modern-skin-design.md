# Modern skin

Approved 2026-11-25. Visual target: the Superdesign board "AnotherLedger Modern
skin" (project 1f73b57e-5726-4d5a-8068-89d91562a699), rules in
`.superdesign/design-system.md`.

## Intent

A flat, clean look in the player's Polaris colors (navy, amber, sky blue) with
a modern sans, next to Classic / Forge / Slate / Gilded.

## Approaches

1. **Full Modern skin (picked):** new skin parts (rounded thin border, Pills
   tabs, Zebra rows, Chip tags), Inter shipped with the addon, a built-in
   Polaris color preset.
2. Quick version from existing parts only (Thin, Flat, Plain, Sunken list) plus
   font and preset: cheap, but tabs, rows and tags keep the Classic shape.

## Decisions

- Picking the Modern skin sets its parts **and** the font (Inter) and the color
  preset (Polaris) in one click. Other skins keep today's behavior (shapes only).
- Inter is also a choice of the Font option, Polaris a built-in color preset,
  so players can combine them with any skin.
- The new parts are ordinary choices of the part options, so they mix with
  other skins too.
- Constraints: flat fills, 1 px lines, textures for rounded corners; no blur.

## Left to the builder

Exact texture for the rounded thin border, which UI pieces read the new parts,
the preset's full color table (from the board's values), test coverage.
