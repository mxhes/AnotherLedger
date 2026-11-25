# AnotherLedger checklist

What still has to be confirmed in the Forever client, and the release steps.

Code that relies on an unconfirmed client API carries an
`UNVERIFIED (check in client)` comment; add a line here whenever you add one,
and remove both once it is confirmed.

## Open checks

None: everything up to v0.8.0 is confirmed in the client.

## Release steps

1. `main` is green: `lua tests/run.lua` passes locally and the `test` jobs
   (Lua 5.1 and 5.4) and the `lint` job pass in GitHub Actions.
2. The open checks above are done in the client, or knowingly left for a
   later release.
3. `## Interface:` in `AnotherLedger/AnotherLedger.toc` matches the client
   (`/dump select(4, GetBuildInfo())`, 16001 today).
4. Run the CI workflow by hand on `main` (Actions > CI > Run workflow): the `package-dry-run` job's log lists one
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
   then `git push origin v0.4.2`). The tag's workflow run gets the repository secret `CF_API_KEY` (the CurseForge API token, set under Settings > Secrets and variables > Actions). The `package` job builds
   the zip (the `.toc` version comes from the tag), uploads it to CurseForge
   (project 1817047, `## X-Curse-Project-ID` in the `.toc`) and keeps it as the run's artifact for 30 days.
7. Check the `package` job log: `CurseForge ID: 1817047 [token set]` near the
   top and `Uploading ... Success!` before `Packaging complete.`; then the file
   on CurseForge shows the changelog and the game version (the packager maps
   `## Interface: 16001` to `1.60.1`). Without `[token set]` the upload is
   skipped silently. After adding a missing secret, re-run the tag's workflow run (Actions, the run, Re-run all jobs).
