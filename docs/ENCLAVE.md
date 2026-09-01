# Building in an Enclave (air-gapped / no egress)

This plugin can be built with **no network access at all**. Everything `make dist`
needs is either vendored into the repository or staged into a bundle beforehand.

The workflow has two halves:

1. **On a networked machine** — `make enclave-bundle` produces a single
   self-contained tarball.
2. **Inside the enclave** — extract it and run `make dist`. Nothing is fetched.

```
networked machine                    enclave
─────────────────                    ───────
make enclave-bundle    ──tarball──>  tar -xzf ...
                                     make enclave-preflight
                                     make dist   ->  dist/<plugin-id>-<version>.tar.gz
```

## Scope

This covers **building the plugin**: `make dist`, which compiles the Go server for
`linux/amd64` and `linux/arm64`, builds the webapp, and packages the installable
plugin bundle.

It deliberately does **not** cover linting, tests, or the security pipeline
(`make check-style`, `make test`, `make release`). Those download tooling
(golangci-lint, gotestsum, CodeQL, Grype, ClamAV) and browser binaries, and they
fail fast with an explanatory message when run in offline mode. Run them on the
networked side before shipping.

## Enclave prerequisites

The bundle carries dependencies, not the toolchain. The enclave must already
provide:

| Requirement | Version | Why |
|---|---|---|
| Go | the version in `go.mod` (currently **1.26.3**) or newer | Offline builds set `GOTOOLCHAIN=local`, which forbids downloading a toolchain. Go would otherwise fetch the exact version named in `go.mod` from the module proxy. |
| Node.js | the major version in `.nvmrc` | Several dependencies declare `engines: node >= 22`. |
| npm | ships with Node | Installs from the staged cache. |
| GNU make, tar | any recent | Build driver and packaging. |

`make enclave-preflight` verifies all of the above and reports exactly what is
missing. Run it first.

## Step 1 — stage and bundle (networked machine)

```bash
make enclave-bundle
```

This produces `dist/<plugin-id>-<version>-enclave.tar.gz` (~96MB) containing the
source tree, the vendored Go modules, and a pre-populated npm cache.

Two sub-steps run underneath, and can be invoked separately:

- `make enclave-stage` — vendors Go modules into `vendor/` and populates
  `build/enclave/npm-cache`.
- the packaging step — copies the tree into `dist/enclave/` and tars it.

### Cross-platform npm binaries

Some transitive dependencies (`lightningcss`, `@parcel/watcher`) resolve to
**prebuilt, platform-specific binaries**. A cache staged only for the machine
doing the staging would fail on a different OS or CPU.

`enclave-stage` therefore fills the cache for every platform in
`ENCLAVE_NPM_PLATFORMS`, which defaults to:

```
linux/x64/glibc  linux/arm64/glibc  linux/x64/musl  darwin/arm64  darwin/x64
```

Trim or extend it if you know your target:

```bash
make enclave-bundle ENCLAVE_NPM_PLATFORMS="linux/x64/glibc"
```

> **Stage with a current npm.** Selecting musl vs. glibc builds relies on `libc`
> metadata in `package-lock.json`. Older npm releases silently strip those fields
> when they touch the lockfile, which would break musl staging. Use an npm at
> least as new as the one that generated the lockfile, and never commit a
> `package-lock.json` whose only change is dropping `libc` entries.

## Step 2 — build (inside the enclave)

```bash
tar -xzf <plugin-id>-<version>-enclave.tar.gz
cd <plugin-id>-<version>-enclave
make enclave-preflight      # verifies toolchain + staged dependencies
make dist                   # builds with no network access
```

The result is `dist/<plugin-id>-<version>.tar.gz`, the installable plugin bundle.

## How offline mode works

Offline mode turns itself on when `build/enclave/OFFLINE` is present. That marker
is created **only inside the shipped bundle**, so the machine that did the staging
keeps building normally even though it also has a populated `build/enclave/`.

Force it either way:

```bash
make OFFLINE=1 dist     # forbid network access (use this to prove a build is clean)
make OFFLINE=0 dist     # normal networked build
```

When offline mode is active the build sets:

| Setting | Effect |
|---|---|
| `GOFLAGS=-mod=vendor` | Go resolves packages from `vendor/` only. |
| `GOPROXY=off` | Any attempted module fetch is a hard error rather than a silent reach-out. |
| `GOTOOLCHAIN=local` | Never download a Go toolchain. |
| `npm ci --offline --cache build/enclave/npm-cache` | Fails rather than contacting the registry. |
| `npm ci --ignore-scripts` | See below. |

### Why `--ignore-scripts` is required

`webapp/package.json` has a `postinstall` that runs `playwright install chromium`,
which downloads ~400MB of browsers from the Playwright CDN and **fails the build
in an enclave**. Playwright browsers are a `make test` dependency and are never
needed to build the plugin.

Note that the `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD` environment variable does *not*
help here — it is only honoured by the Playwright package's own postinstall, not
by an explicit `playwright install` invocation. `--ignore-scripts` is what
actually prevents it.

The only other install scripts in the dependency tree are `core-js`'s funding
banner and the optional, test-only `@parcel/watcher` and `fsevents`. None affect
the webpack build output.

## Nothing is committed

Every offline dependency is a **generated artifact**, produced by
`make enclave-stage` and carried in the tarball:

| Path | In git? | Notes |
|---|---|---|
| `vendor/` | no (~24MB) | Vendored Go modules. Gitignored. |
| `build/enclave/npm-cache` | no (~94MB) | Multi-platform npm cache. Gitignored. |
| `build/enclave/OFFLINE` | no | Marker written into the bundle only. |

This is deliberate. This repo is a **template that other plugins inherit**, and
most of them will never target an enclave. Committing a vendor tree would tax
every one of them with ~24MB, permanent history growth on each dependency bump,
and an obligation to re-run `go mod vendor` on top of every Dependabot PR.
Generating it on demand costs the enclave workflow one `make enclave-stage` and
costs everyone else nothing.

It is also the better supply-chain position. Go does **not** verify `vendor/`
against `go.sum` when building with `-mod=vendor`, and no reviewer meaningfully
audits a 600k-line vendor diff. Staging regenerates the tree from `go.sum`-
verified modules every time, and the resulting bundle can be checksummed and
signed (`make release-checksum`, `make release-sign`).

The practical consequence: **a bare `git clone` cannot build offline** — you need
the bundle. Reaching your git host does not change that: `/vendor/` and
`build/enclave/` are both gitignored, so a clone carries neither the Go modules
nor the npm cache an offline build resolves against. The enclave has to receive
the bundle — or the same staged artifacts — from an approved artifact source.

There is nothing to keep in sync. `make enclave-stage` always regenerates from
whatever `go.mod` and `package-lock.json` currently say, so a bundle is
consistent by construction. Just re-run it after a dependency change.

Forget to, and `make enclave-preflight` says so. It records the hash of the
`package-lock.json` each cache was staged from and compares it, because a stale
cache is otherwise indistinguishable from a good one — the directory is there,
full of tarballs — right up until the offline build dies with `ENOTCACHED` on
whichever dependency moved. Better to learn that on the staging machine than
after carrying a bundle into the enclave.

## Verifying a build really is hermetic

`GOPROXY=off` and `npm ci --offline` make network access an error rather than a
fallback, so a successful `make OFFLINE=1 dist` is already strong evidence. To
prove it end to end, build the bundle in a container with no network:

```bash
docker run --rm --network none \
  -v "$PWD/dist/<plugin-id>-<version>-enclave.tar.gz:/in/bundle.tar.gz:ro" \
  <image-with-go-and-node> bash -c '
    mkdir -p /work && tar -xzf /in/bundle.tar.gz -C /work
    cd /work/<plugin-id>-<version>-enclave
    make enclave-preflight && make dist'
```

## Troubleshooting

**`go: go.mod requires go >= 1.26.3 (running go X.Y.Z; GOTOOLCHAIN=local)`**
The enclave's Go is older than `go.mod` requires. Install a newer Go; the build
will not download one.

**`npm error code ENOTCACHED` / `request to https://registry.npmjs.org/... failed`**
The staged cache is missing a package for this platform. Re-run
`make enclave-stage` on the networked machine with the enclave's platform
included in `ENCLAVE_NPM_PLATFORMS`.

**`go: inconsistent vendoring`**
A `vendor/` left over from an earlier staging run has gone stale against
`go.mod`. Re-run `make enclave-stage`, or just `rm -rf vendor`. Normal networked
builds pin `-mod=mod` precisely so a stale `vendor/` cannot affect them; this
only bites in offline mode.

**`ERROR: offline build requested but no staged npm cache`**
`OFFLINE=1` was set outside a bundle. Run `make enclave-stage` first, or build
with `OFFLINE=0`.

**`ERROR: this target downloads tooling and cannot run in offline mode.`**
You invoked a lint/test/security target inside the enclave. These are out of
scope; run them on the networked side.
