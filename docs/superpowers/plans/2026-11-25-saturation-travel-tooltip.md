# Saturation, travel pause, tooltip sale info Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a saturation slider docked to the game's color picker, a clock pause on flight paths and transports, and TSM sale levels in the game's item tooltips.

**Architecture:** pure math / decisions in `Theme.lua`, `Core.lua` (pure helpers), `UI/ItemTooltip.lua` (pure line builder); client glue in `UI/Widgets.lua` and `Core.checkRest`.

**Tech Stack:** Lua 5.1, plain-Lua test harness (`lua tests/run.lua`), luacheck.

**Spec:** `docs/superpowers/specs/2026-11-25-saturation-travel-tooltip-design.md`

## Global Constraints

- Lua 5.1 only; texts through `ns.L` with German in `Locales/deDE.lua`; option labels at most 24 glyphs.
- Unconfirmed client APIs get `UNVERIFIED (check in client)` and a `docs/CHECKLIST.md` line.
- README / DEVELOPMENT / CHANGELOG updated in the same change.

## Review Focus

- Grey colors (s = 0) keep their value when the slider raises saturation (hue 0, red) without errors.
- Slider and wheel updating each other must not loop.
- Teleports / falling must not count as a transport.
- Travel pause must not start a clock stopped by hand or AFK.
- Items without TSM data get no sale line.

---

### Task 1: HSV math + saturation slider

**Files:** `AnotherLedger/Theme.lua`, `AnotherLedger/UI/Widgets.lua`, `tests/test_theme.lua`, locales.

**Produces:** `Theme.rgbToHsv(r, g, b) -> h, s, v` (all 0..1), `Theme.hsvToRgb(h, s, v) -> r, g, b`, `Theme.withSaturation(r, g, b, s) -> r, g, b`.

- [ ] Tests: round trips of pure red / grey / a mixed color; `withSaturation(0.5,0.5,0.5,1)` stays grey-valued red-hue (0.5,0,0); `withSaturation(1,0,0,0)` = (1,1,1).
- [ ] Implement; slider in `Widgets.pickColor` (UNVERIFIED), hidden when the picker hides.

### Task 2: Travel pause

**Files:** `Core.lua`, `Options.lua`, `DB.lua`, tests (`test_core.lua`, `test_wiring.lua`).

**Produces:** `Core.transportMoved(prev, cur, ownSpeed, falling) -> bool` (prev/cur `{ x, y, t }`), `Core.traveling()`; option `travelPause` (default true); `Core.checkRest` rests on `resting and cityPause or traveling and travelPause`.

- [ ] Tests: 5 s, 60 yd, speed 0 -> true; speed 7 and 40 yd -> false; falling -> false; > 60 yd/s (teleport) -> false; nil prev -> false. Wiring: `UnitOnTaxi` true + heartbeat rests the clock; false again wakes it.

### Task 3: Sale info in item tooltips

**Files:** `UI/ItemTooltip.lua`, `UI/Rows.lua` (share the MARKET table), tests.

**Produces:** `ItemTooltip.marketLine(rateLevel, volumeLevel) -> parts list or nil`.

- [ ] Tests: ("ok","low") gives two colored parts; (nil,nil) -> nil. `add` adds the line with `showMarket` on and TSM market data.

### Task 4: Docs, locale, lint, commit
