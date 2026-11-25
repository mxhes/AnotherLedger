# AnotherLedger checklist

What still has to be confirmed in the Forever client, and the release steps.

Code that relies on an unconfirmed client API carries an
`UNVERIFIED (check in client)` comment; add a line here whenever you add one,
and remove both once it is confirmed.

## Open checks

Everything up to v0.7.1 is confirmed in the client, except:

- Trade, unopened sale mails (`CoreTrade.lua` `readMail`): an "Auction
  successful" mail not opened yet gives no invoice (`GetInboxInvoiceInfo`),
  and its subject carries the amount sold as `Name (4)`. Check: sell a few
  of a stack, empty the mails with Open All, the sales show in Trade > Log
  with the right amount; open one sale mail by hand first, it still counts
  once.
- Trade, mails taken: after emptying the mailbox, a second equal sale
  (same item, amount and price) arriving within a few minutes still counts
  (`GetInboxNumItems` second return is the total in the inbox).
- Saturation slider (`UI/Widgets.lua` `saturationDock`): opening a color
  swatch shows a Saturation slider under the game's color picker at the
  color's saturation; dragging it changes the color live (hue and
  brightness kept), dragging the wheel moves it, Cancel restores the color;
  a picker opened by another addon or the game shows no slider.
- Pause while traveling (`Core.sampleTravel`): on a flight path and while
  standing on a boat / zeppelin the compact window says Traveling and the
  clock stands; walking on the deck may wake it; running, flying on your own
  mount, falling or a portal never rest it.
- Item tooltips with TSM: the `TSM sale info` line shows the levels in their
  colors.
- Compact drops: hovering a drop shows the item tooltip with its values;
  Shift-click links it in chat; dragging a drop still moves the window.

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
