# Plugin Template Guidelines

## Overview

This is a minimal Mattermost plugin template. The server is written in Go and the webapp in TypeScript/React.

## Architecture

- `server/` - Go plugin code. Entry point is `main.go` which calls `plugin.ClientMain(&Plugin{})`. The `Plugin` struct in `plugin.go` embeds `plugin.MattermostPlugin` and implements lifecycle hooks (`OnActivate`, `OnConfigurationChange`).
- `webapp/` - TypeScript/React webapp. Entry point is `src/index.tsx`. The `Plugin` class's `initialize()` method receives a `PluginRegistry` and Redux `Store` and is where components and hooks are registered.
- `plugin.json` - plugin manifest. Generates `server/manifest.go` and `webapp/src/manifest.ts` at build time (both gitignored).
- `build/` - build tooling from mattermost-plugin-starter-template (`setup.mk`, `custom.mk`, `manifest/`, `pluginctl/`).
- `assets/` - plugin icon and other static assets bundled at the top level.

## Coding conventions

- Match the style of surrounding code.
- Keep the plugin minimal: avoid adding features or abstractions that are not part of the core template.
- Server: follow Mattermost plugin API conventions. Use `p.API.LogError`/`LogWarn`/`LogInfo` for logging.
- Webapp: prefer functional React components with hooks.

## Build and test

- `make dist` - build the plugin bundle
- `make check-style` - lint both Go and webapp code
- `make test` - run tests
- `make deploy` - build and deploy to a running Mattermost server

## Air-gapped (enclave) builds

`make dist` is able to run with **no network access**. See
[`docs/ENCLAVE.md`](docs/ENCLAVE.md) for the full workflow; the essentials:

- `make enclave-bundle` (networked machine) produces a self-contained tarball;
  inside the enclave, `make dist` builds from it. `make enclave-preflight`
  checks the enclave has a new enough Go and Node.
- `vendor/` and `build/enclave/` are **generated artifacts and gitignored** —
  `make enclave-stage` produces them and the tarball carries them. Don't commit
  either: plugins that never target an enclave should carry no cost, and there
  is no vendor tree to drift from `go.mod`.
- Offline mode auto-enables inside a shipped bundle, or explicitly via
  `make OFFLINE=1 dist` — useful to prove a change didn't introduce a fetch. It
  sets `GOFLAGS=-mod=vendor GOPROXY=off GOTOOLCHAIN=local` and installs npm
  packages from a staged cache with `--offline --ignore-scripts`.
- Only the **plugin build** is supported offline. Lint, test and security
  targets download tooling and deliberately fail fast in offline mode.
- Don't add a webapp `postinstall` step that downloads anything, and prefer Go
  dependencies that vendor cleanly — both break the enclave build.

## Commits and releases

This repo automates releases with **release-please** driven by
[Conventional Commits](https://www.conventionalcommits.org/). Full details live
in [`docs/RELEASING.md`](docs/RELEASING.md); the essentials:

- **Write conventional commit subjects** (and PR titles, since PRs squash-merge).
  The prefix drives the version bump: `feat:` → minor, `fix:`/`perf:`/`deps:` →
  patch, `feat!:` or a `BREAKING CHANGE:` footer → major. `chore:`/`docs:`/
  `test:`/`refactor:`/`style:`/`build:`/`ci:` don't bump or appear in the
  changelog.
- **Do not** hand-edit `plugin.json`'s `version` or `CHANGELOG.md` for a normal
  release — release-please owns them via its Release PR. The version is seeded at
  `0.1.0`.
- A release ships when the maintainer merges the open "chore(main): release
  X.Y.Z" PR, which tags `vX.Y.Z` and fires `release.yml`.

## CI and security

Workflows live in `.github/workflows/`: `pr.yml` (style/test/build), `security.yml`
(SBOM + Grype + CodeQL → Code Scanning), `release-please.yml`, and `release.yml`.
Everything is reproducible locally through `make` — CI runs the same targets, so
verify changes with these before pushing:

- `make check-style && make test` - what `pr.yml` gates on
- `make sbom-audit` - dependency CVE scan (fails on HIGH/CRITICAL)
- `make codeql-analyze && make security-gate` - static analysis + finding gate
- `make release` - the full security-gated pipeline `release.yml` runs on a tag

When touching dependencies or adding code, expect the security workflow to gate
the PR. Suppress false-positive CVEs in `.grype.yaml` with a documented reason
(never blanket-ignore). See [`docs/SECURITY.md`](docs/SECURITY.md) for the full
process, the Code Scanning requirement, and release signing.

GitHub Actions are pinned to full commit SHAs with a `# vX.Y.Z` comment. When
adding or bumping an action, resolve the tag to its commit SHA and keep the
comment accurate — don't use floating tags like `@v4`.
