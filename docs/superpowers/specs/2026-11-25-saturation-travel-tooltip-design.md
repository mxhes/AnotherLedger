# Saturation slider, travel pause, sale info in item tooltips

Three small features asked for together (approved 2026-11-25).

## 1. Saturation in the game's color picker

Intent: setting a color's saturation directly is fiddly on the wheel alone.

Approaches: (a) our own slider docked under the game's ColorPickerFrame,
shown only when AnotherLedger opened the picker (picked: keeps the game's
picker, little code); (b) an own picker window (much more code, unfamiliar).

Design: `Widgets.pickColor` shows a "Saturation" slider (0-100 %) under the
picker. It starts at the color's HSV saturation; moving it sets S and keeps
hue and value; moving the wheel updates the slider (guarded against loops).
Cancel restores the old color as before. HSV math is pure in `Theme.lua`
(`Theme.rgbToHsv`, `Theme.hsvToRgb`) with tests. The docking is client code,
UNVERIFIED.

## 2. Clock pause while traveling

Option `travelPause` ("Pause while traveling", default on): the clock rests
like "Pause in cities" (Session.rest / wake; loot still counts) while on a
flight path (`UnitOnTaxi`) or on a boat / zeppelin. Transports are guessed on
the 5 s heartbeat: the world position (`UnitPosition`) moved clearly faster
than the player's own speed (`GetUnitSpeed`) while not falling. Own flying
mounts do not pause. Transport detection is UNVERIFIED.

## 3. Sale info in item tooltips

The game's item tooltip gets one line with the TSM levels ("Sells okay, Low
volume") in the market colors, with the window's cutoffs; off with
"TSM sale info" (`showMarket`).

Left to the builder: thresholds of the transport guess, slider placement.
