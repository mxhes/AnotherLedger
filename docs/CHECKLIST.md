# AnotherLedger checklist

What still has to be confirmed in the Forever client, and the release steps.

Code that relies on an unconfirmed client API carries an
`UNVERIFIED (check in client)` comment; add a line here whenever you add one,
and remove both once it is confirmed.

## Open checks

None. Everything up to v0.4.3 is confirmed in the client.

## Release steps

1. `main` is green: `lua tests/run.lua` passes locally and the `test` jobs
   (Lua 5.1 and 5.4) pass in GitLab CI.
2. The open checks above are done in the client, or knowingly left for a
   later release.
3. `## Interface:` in `AnotherLedger/AnotherLedger.toc` matches the client
   (`/dump select(4, GetBuildInfo())`, 16001 today).
4. Run the manual `package-dry-run` job on `main`: its log lists one
   `AnotherLedger/` folder with the `.toc`, the code and `Libs/` (LibStub,
   CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0), and no `docs/`,
   `tests/` or `CLAUDE.md`.
5. Add the version's entry on top of `CHANGELOG.md` (merged into `main`):
   the packager sends it to CurseForge as the release notes.
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
