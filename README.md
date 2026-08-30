# grawgo-ci

The container image every [grawgo](https://github.com/GrawRadiosondes/grawgo) CI job runs
inside, published as `docker.io/grawradiosondes/grawgo-ci:<semver>`.

Its only job is to be already-provisioned: the self-hosted `ephemeral-runners` pods start
with PHP 8.5, the extensions grawgo needs, composer, bun and node in place, so a job goes
straight to `composer install` instead of building an environment first.

## Who consumes it

Four grawgo jobs, all on `runs-on: ephemeral-runners`:

| Workflow | Job | What it runs |
| --- | --- | --- |
| `build.yml` | `bun` | `composer install`, `bun run build` (vite), license checker |
| `tests.yml` | `type-unit-feature-ui` | pest — type coverage, unit, feature, browser, `--min=100` line coverage |
| `analytics.yml` | `phpstan` | `composer run phpstan` |
| `analytics.yml` | `phpcs` | `composer run phpcs` |

Also referenced by grawgo's parked `.devcontainer/devcontainer.json.later`.

## What is in it, and what is deliberately not

**In:** PHP 8.5 with `bcmath gd intl mysqli pcntl pdo_mysql pdo_pgsql pgsql sockets zip`,
pcov, `memory_limit = 1G`, composer, bun, node + python3 + node-gyp (tree-sitter builds
with it), git, and Playwright's OS dependencies **for chromium only** — bare `install-deps`
also drags in the firefox and webkit stacks, for browsers nothing here launches.

**Not in, on purpose:**

- **Browser binaries.** Only `playwright install-deps` is baked, because it needs root and
  apt. grawgo pins `playwright` to an exact version and its `renovate.json` disables
  auto-bumps to keep NixOS developers in lockstep with nixpkgs — baking browsers would
  couple every one of those bumps to an image rebuild. grawgo's tests job installs the
  browser itself, from its own `bun.lock`.
- **xdebug.** CI collects line coverage and never step-debugs; pcov is much faster at that.
  The smoke test asserts xdebug is *absent*, because with both loaded xdebug takes over
  coverage and the speed-up quietly disappears.
- **nginx, mkcert, baked TLS certificates.** They only ever served the parked devcontainer;
  the active one uses the Sail compose stack. Baked certificates also expire (825-day leaf
  limit) in an image with no rebuild cadence.
- **A checkout of grawgo.** The build used to clone the private grawgo repo purely to copy
  three nginx configs into this public image. Dropping nginx dropped the clone, which is
  what lets this repo build itself in GitHub Actions with no extra credentials.

## The extension list tracks grawgo's `composer.json`

`Dockerfile`'s `docker-php-ext-install` list mirrors the `ext-*` requires in grawgo's
`composer.json`. Nothing here can check that automatically — grawgo is private and this
image cannot read it — so the guard lives on the other side: `composer check-platform-reqs`
runs as the first step of grawgo's `bun` job and names any missing extension in one line,
instead of letting it surface as a confusing resolution error deep inside `composer install`.

Note that `curl`, `fileinfo`, `mbstring`, `xml`, `sqlite3`, `pdo_sqlite` and `pdo` are
compiled into `php:*-cli` and so are *not* in the Dockerfile's list. `ext-sqlite3` is what
grawgo's entire `sqlite_testing` suite runs on; the smoke test asserts all of them anyway,
so a base image that stops shipping one fails here rather than in grawgo.

## How a change reaches grawgo

1. Open a pull request here. Its CI builds the image and runs the full smoke test — nothing
   is published.
2. Merge to `main`. `publish.yml` derives the next patch version from the highest git tag,
   builds, smoke tests, creates the tag, and pushes `<semver>` plus `latest`.
3. Renovate opens a pull request in grawgo bumping the `container:` lines. **grawgo's own CI
   runs inside the new image**, so the bump has to go green before it affects anyone.

That last step is the whole point. The image used to be `:latest`, built by hand on a
laptop, and a single push silently changed CI for every branch and every historical commit
at once — the one unpinned input in a repository whose whole philosophy is reproducibility.

Rebuilds also happen weekly on a schedule, so base-image security patches land as ordinary
version bumps, and can be triggered by hand with `workflow_dispatch`.

## Local build

```bash
docker build -t grawgo-ci:candidate .
scripts/smoke-test.sh grawgo-ci:candidate
```

`scripts/smoke-test.sh` is the same script CI runs before publishing: it checks the tooling,
asserts every extension above, asserts pcov present and xdebug absent, checks the ini
settings, and installs and launches chromium to prove `install-deps` was sufficient.

## Repository secrets

`publish.yml` needs `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` for
`docker.io/grawradiosondes/grawgo-ci`. It checks for them before doing any work, so a
missing credential fails in seconds rather than after a full build.
