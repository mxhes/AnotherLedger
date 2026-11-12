# LootPrice

WoW Forever addon: a game-styled Session Ledger showing vendor and auction house value of everything you loot.

Design: docs/superpowers/specs/2026-11-12-loot-price-design.md

## Tests

`lua tests/run.lua` from the repo root (exit code 1 on any failure).

## TODO

- Confirm the `## Interface:` number in `LootPrice/LootPrice.toc` (currently 110207, a placeholder) with `/dump select(4, GetBuildInfo())` in the Forever client.
