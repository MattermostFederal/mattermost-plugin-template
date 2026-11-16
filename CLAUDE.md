# Plugin Template Guidelines

## Overview

This is a minimal Mattermost plugin template. The server is written in Go and the webapp in TypeScript/React.

## Architecture

- `server/` - Go plugin code. Entry point is `main.go` which calls `plugin.ClientMain(&Plugin{})`. The `Plugin` struct in `plugin.go` embeds `plugin.MattermostPlugin` and implements lifecycle hooks (`OnActivate`, `OnConfigurationChange`).
- `webapp/` - TypeScript/React webapp. Entry point is `src/index.tsx`. The `Plugin` class's `initialize()` method receives a `PluginRegistry` and Redux `Store` and is where components and hooks are registered.
- `plugin.json` - plugin manifest. Generates `server/manifest.go` and `webapp/src/manifest.ts` at build time (both gitignored).
- `build/` - build tooling from mattermost-plugin-starter-template (`setup.mk`, `custom.mk`, `manifest/`, `pluginctl/`).
- `assets/` - plugin icon and other static assets bundled at the top level.

## Plugin engineering standard

Every plugin created from this template follows the same methodology, so all
plugins build, release, preview, test, document and expose their capabilities
the same way. This section is the shared standard. When a plugin's own needs
call for something different, write the difference down in that plugin's
`CLAUDE.md` rather than drifting silently.

### Readiness checklist (definition of done)

A plugin is ready when:

| Area | Expectation |
|---|---|
| Build & release | `pr.yml`, `release-please.yml` and `release.yml` pass; release artifact validated |
| Preview | The `preview` label produces a working server, and `.preview/deploy.sh` seeds whatever a reviewer needs to try the plugin |
| Testing | Backend and frontend each reach ≥90% overall and ≥80% for every file, with authorization and visibility tests as well as happy paths |
| Slash commands | Useful subcommands with help, autocomplete, input validation, clear errors and permission checks |
| Help | Help is built into the plugin, kept current, and checked against the code |
| Security | `security-review-all` has been run, findings triaged by a human, fixes covered by regression tests |
| MCP | MCP considered and implemented for the operations it suits |
| Walkthrough | Someone has used the plugin end to end on a preview server and the feedback is written down |

### Workflow

- Use the repo skills in `.claude/skills/` rather than improvising; they are
  expected to become release gates.
- For anything beyond a small fix: `create-plan` (saves to
  `implementation-plans/YY-MM-DD-NN-<name>.md`) → `review-plan` → approval →
  `create-code` → `review-code`.
- One branch and PR per work item. Add the `preview` label so reviewers can
  click through the change.
- Run `cleanup` to tear down worktrees after their PRs merge.

| Skill | When to run it |
|---|---|
| `security-review-all` | When adopting the standard, before each release, and after changes to auth, HTTP routes or hooks. Read-only. |
| `add-backend-tests` | Until the Go gate passes (≥90% overall, no file <80%) |
| `add-frontend-tests` | Until the webapp gate passes (same thresholds, Playwright only) |
| `add-slash-cmds` | After adding REST endpoints or features, and before releases |
| `add-help-docs` | After changing settings, commands, endpoints or user-visible behavior, and before releases |
| `add-agents-mcp-server` | To add the MCP server, and again later to expose new tools |

### Bringing a plugin up to the standard

When adopting the standard in an existing plugin, work in this order:

1. **Baseline (no code changes).** Run `security-review-all` and save the
   report, but don't fix anything yet: the fixes can reshape code you would
   otherwise write tests for. Record coverage baselines with
   `make coverage-backend` and `make coverage-frontend`. Walk through every
   user flow on a preview server and note what is clunky. Combine these into
   a gap report against the readiness checklist.
2. **Harden.** Fix security findings worst first, one PR per finding or small
   cluster, each with a regression test. Then bring backend and frontend
   coverage up to the gate.
3. **Match the standard.** Add slash commands, help docs and MCP, as described
   below.
4. **Polish.** Fix the UX problems from the walkthrough, then demo the plugin
   and record the feedback.

Before each release, re-run `security-review-all`, both test skills and
`add-help-docs`.

### Testing

- The 90/80 thresholds are what the test skills require before they report
  success. CI does not enforce them yet (`make test` has no coverage
  threshold), so run the skills yourself.
- The frontend uses Playwright only (`*.spec.ts` unit tests, `*.pw.tsx`
  component tests). Don't add Jest. Migrate any existing Jest suites to Playwright.
- Test permissions and visibility, not only happy paths: a non-member, a
  regular user, a team admin and a system admin should each see and be able
  to do only what they are allowed to.
- `server/manifest.go` is generated. Run `make apply` (or any make target)
  before a bare `go test`, or the build fails with `undefined: manifest`.

### One shared operation per capability

Implement each capability once, as a server-side operation, and have every
front end (REST/UI, slash commands, MCP tools, calls from other plugins or
automation) call it. Behavior must never fork between them. Move logic out
of HTTP handlers into these operations where needed. Each operation enforces
authorization itself, based on the caller's identity, so a new transport
can't skip the checks.

### Slash commands

- Every plugin ships a slash command with subcommands, autocomplete and a
  `help` subcommand. Commands make features discoverable and give automation
  a stable way to drive the plugin.
- `add-slash-cmds` compares REST endpoints with subcommands and suggests new
  ones. Review its suggestions instead of accepting them all. Record rejected
  suggestions in the skill file as "do not suggest" so they don't come back.
- A subcommand enforces exactly the same permission checks as its REST
  counterpart. Reply ephemerally unless the output is meant for the whole
  channel.

### Help docs

- Serve help from the plugin bundle (`public/help/*.html`): setup,
  permissions, workflows, a commands page and troubleshooting. Add a
  server test that checks the help pages against the code, for example that
  every slash subcommand and setting is documented and every link resolves.
- Update help in the same PR as any change to a setting, command,
  authorization rule or visible behavior. Run `add-help-docs` to catch drift.

### MCP server

- Use `add-agents-mcp-server` to expose operations to the Mattermost Agents
  plugin. MCP is just another front end to the shared operations.
- MCP calls keep the caller's identity and permission checks. An agent is
  not an admin.
- Start with read-only tools. Add write tools only when they act with the
  requesting user's identity and permissions.
- Check the license of every dependency before adding it, `pluginmcp` included.

### Security

- Treat `security-review-all` findings as leads that need human triage. An
  AI review does not replace the established security process.
- Pay particular attention to authorization boundaries, private-channel
  membership and data visibility, leakage through search, summaries or
  aggregates, privileged admin operations and their audit trail, and
  sensitive material committed to the repo.
- Take the user's identity only from the `Mattermost-User-Id` header. Never
  trust user or actor IDs in request bodies or post props.

## Coding conventions

- Match the style of surrounding code.
- Don't add speculative features or abstractions. In this template repo itself, keep the plugin minimal and limit it to the shared standard.
- Server: follow Mattermost plugin API conventions. Use `p.API.LogError`/`LogWarn`/`LogInfo` for logging.
- Webapp: prefer functional React components with hooks.

## Build and test

- `make dist` - build the plugin bundle
- `make check-style` - lint both Go and webapp code
- `make test` - run tests
- `make coverage` - Go and webapp coverage (`coverage-backend`, `coverage-frontend`)
- `make deploy` - build and deploy to a running Mattermost server

Webapp coverage uses c8 over V8 data. Unit tests (`*.spec.ts`) run under c8 in Node; component tests (`*.pw.tsx`) run in Chromium, so `webapp/playwright/ct-coverage.ts` collects coverage through CDP and must be where they import `test` and `expect` from (eslint enforces it). Collection is skipped when `CI` is set, since it roughly doubles the run, so read coverage numbers from a local run. The fixture must keep every entry in a source map's `sources`: mappings index into that array, and dropping entries makes c8 silently report nothing.

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
(SBOM + Grype + CodeQL → Code Scanning), `release-please.yml`, `release.yml`, and
`preview.yml` (the `preview` PR label deploys `pr.yml`'s `plugin-dist` artifact to a
throwaway server; keep that artifact a single `dist/*.tar.gz`). Server setup beyond the
bundle goes in `.preview/` (`mattermost.env` for `MM_*` settings, `deploy.sh` run after
install), which both the preview and `make deploy` apply; previews read it from the base
branch, so changes reach them only after merge.
Everything is reproducible locally through `make` — CI runs the same targets, so
verify changes with these before pushing:

- `make check-style && make test` - what `pr.yml` gates on
- `make sbom-audit` - dependency CVE scan (fails on HIGH/CRITICAL)
- `make govulncheck` - reachable Go vulnerability scan (fails on any)
- `make codeql-analyze && make security-gate` - static analysis + finding gate
- `make release` - the full security-gated pipeline `release.yml` runs on a tag

When touching dependencies or adding code, expect the security workflow to gate
the PR. Suppress false-positive CVEs in `.grype.yaml` with a documented reason
(never blanket-ignore). See [`docs/SECURITY.md`](docs/SECURITY.md) for the full
process, the Code Scanning requirement, and release signing.

GitHub Actions are pinned to full commit SHAs with a `# vX.Y.Z` comment. When
adding or bumping an action, resolve the tag to its commit SHA and keep the
comment accurate — don't use floating tags like `@v4`.
