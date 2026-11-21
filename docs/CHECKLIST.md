# AnotherLedger checklist

What still has to be confirmed in the Forever client, and the release steps.

Code that relies on an unconfirmed client API carries an
`UNVERIFIED (check in client)` comment; add a line here whenever you add one,
and remove both once it is confirmed.

## Open checks

Everything up to v0.4.3 is confirmed in the client. New since then (only run
against the test fakes):

- Watch list (`Core.watchAlert`, UNVERIFIED): `/al watch` with a shift-clicked
  item link, then loot it: a chat line, the raid warning sound
  (`SOUNDKIT.RAID_WARNING`) and a gold line in the middle of the screen
  (`UIErrorsFrame:AddMessage`); also with the clock stopped.
- Buttons fit their labels (`Widgets.fitButton`, `Ledger.measureHeader`):
  Start / Stop, Reset, Quality, Sort and the Trade period button are not cut
  off (German: Zurücksetzen); the window can't be made narrower than the
  five tabs need (about 390 px in English, the Trade tab was cut off below
  that); after changing the font size the buttons fit again.
- Auction purchases (`readMail` in `CoreTrade.lua`, UNVERIFIED): buy an
  item and a commodity on the auction house, open the mailbox: Trade > Log
  shows `Bought` with the seller and the price paid as a minus; Items shows
  `N bought` and the gold earned less the cost; opening the mailbox again
  adds nothing.
- History > Totals: month headings with their weeks; a heading folds; Value
  and Gold/h rank the weeks; German month names.
- Compact: the drops' quantity in the quieter color; **Compact: item icons**
  shows the icons and the names move right of them (and back when off).
- The `lint` CI job installs luacheck and passes (first run).
- Price trend (`TSM.trend`, UNVERIFIED): with TSM, an item tooltip shows
  `AnotherLedger price trend +N% vs 60 days` (TSM answers `DBHistorical`);
  without TSM, after scans on two days, `vs earlier days`.

- Skins (UNVERIFIED): every skin with every color preset, at UI scale 0.64
  and 1.0: Forge and Gilded show their Grain / Leather background (addon
  `.tga` as tiled backdrop `bgFile`), the Bevel / Thin / Gilded edge lines are
  one pixel and sharp, the Gilded studs sit on the corners, square tabs on
  every border but Round, the Dotted lines are dashes (`SetHorizTile` in
  `Widgets.rule`), Groove shows a light line under each separator, Raised
  buttons light on top and pressed swap, the Sunken list box sits behind the
  rows (full layout only). Opacity and Brightness fade / lighten the edge
  lines and the list box like the window. Switching skin, a single part or the
  profile restyles at once without /reload; the options and export windows
  follow too. New `.tga` files need a client restart (a /reload does not
  see them): check Forge / Gilded after a restart, and whether `SetTexture`
  returns false for a missing file (the stud / dotted fallbacks rely on it).

## Release steps

1. `main` is green: `lua tests/run.lua` passes locally and the `test` jobs
   (Lua 5.1 and 5.4) and the `lint` job pass in GitLab CI.
2. The open checks above are done in the client, or knowingly left for a
   later release.
3. `## Interface:` in `AnotherLedger/AnotherLedger.toc` matches the client
   (`/dump select(4, GetBuildInfo())`, 16001 today).
4. Run the manual `package-dry-run` job on `main`: its log lists one
   `AnotherLedger/` folder with the `.toc`, the code and `Libs/` (LibStub,
   CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0), and no `docs/`,
   `tests/` or `CLAUDE.md`.
5. Add the version's entry on top of `CHANGELOG.md` (merged into `main`):
   the packager sends it to CurseForge as the release notes. Keep it short
   and precise: one bullet per player-visible change, one or two lines
   each, about ten bullets at most, small fixes together in one "Fixes:"
   bullet; no internals (refactors, tests, caches), no option details or
   reasons (those go in `README.md`).
6. Tag `main` with the version as a maintainer (`git tag -a v0.4.2 -m ...`,
   then `git push origin v0.4.2`). `v*` tags are protected tags (maintainers
   only), which is what gives the tag pipeline the protected, masked CI/CD
   variable `CF_API_KEY` (the CurseForge API token). The `package` job builds
   the zip (the `.toc` version comes from the tag), uploads it to CurseForge
   (project 1817047, `## X-Curse-Project-ID` in the `.toc`) and keeps it in the
   job's artifacts for 30 days.
7. Check the `package` job log: `CurseForge ID: 1817047 [token set]` near the
   top and `Uploading ... Success!` before `Packaging complete.`; then the file
   on CurseForge shows the changelog and the game version (the packager maps
   `## Interface: 16001` to `1.60.1`). Without `[token set]` the upload is
   skipped silently. Retrying the job doesn't help: a pipeline keeps the
   protection it was created with, so start a new pipeline on the tag (CI/CD >
   Pipelines > Run pipeline, pick the tag).
