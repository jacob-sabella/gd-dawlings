# Releasing dawlings

dawlings ships on two channels that share one project history. Each release is a GitHub release
carrying a Linux zip and a Windows zip.

| Channel | Example tag | How it is cut |
| --- | --- | --- |
| **Beta** | `v0.0.3-beta.412` | Automatically, on every push to `master` that changes code, assets or the dawkit pin |
| **Stable** | `v0.0.3` | Manually, via the **Stable Release** workflow |

## Single source of truth

`VERSION` holds the **next target final version** (`0.0.3`). `scripts/set-version.sh` reads, bumps
and writes it, and CI stamps the concrete release string into `project.godot`'s `config/version`
just before an export.

## Pipeline

- `ci.yml` -- the headless suite, on pushes to any branch but `master`; also the test gate below.
- `release-check.yml` -- the suite, then dawkit's native core and a full Linux and Windows export,
  kept as artifacts. Runs on pull requests, on manual dispatch, and as the gate of both channels.
- `release-beta.yml` -- on a push to `master` (docs, screenshots and workflow edits are ignored):
  `release-check`, then a GitHub pre-release with the two zips.
- `release-stable.yml` -- manual: `release-check`, then a final release at `VERSION`'s base, then a
  PR bumping `VERSION` to the next development base (`patch` by default; `minor` or `major` by input).
  To cut a minor or major, first merge a PR bumping `VERSION`, then run the workflow.
- `dependabot.yml` -- weekly: GitHub Actions versions, and the `vendor/dawkit` submodule pin.

dawkit is a public submodule, so no deploy key or token is needed; the default `GITHUB_TOKEN`
creates the releases.
