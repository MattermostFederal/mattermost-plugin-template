---
name: add-help-docs
description: Use when plugin code changes need to be reflected in user-facing documentation (README.md, docs/, the admin setting text in plugin.json, or help pages under public/ if the plugin adds them). Trigger after adding or modifying admin settings, slash commands, REST endpoints, build or release targets, or any user-visible message, or before cutting a release.
user-invocable: true
---

# Add Help Docs

Keep the documentation in sync with the code.

This template ships no generated docs and no generator script. Every edit is by
hand. Documentation lives in:

| File | Covers | Kept in sync with |
|---|---|---|
| `README.md` | What the plugin does, how to build, deploy and use it, its slash commands and settings | The overall surface |
| `plugin.json` `settings_schema` | The `display_name`, `help_text`, `header` and `footer` an admin reads in the System Console | `server/configuration.go` |
| `docs/ENCLAVE.md` | Air-gapped builds: `enclave-stage`, `enclave-bundle`, `enclave-preflight`, `OFFLINE` | The enclave section of `Makefile` |
| `docs/RELEASING.md` | Conventional Commits, release-please, the release pipeline | `.github/workflows/release*.yml`, `.release-please-config.json` |
| `docs/SECURITY.md` | SBOM, Grype, CodeQL, the security gate, signing | `.github/workflows/security.yml`, `.grype.yaml`, the security targets in `Makefile` |
| `CLAUDE.md` | Architecture, conventions, build and CI summaries for agents | All of the above, in brief |
| `public/**` (if present) | Static help pages served at `/plugins/<id>/public/**` | Whatever they document |

`CHANGELOG.md` is **not** in scope: release-please owns it.

## When to Use

- After adding, renaming, or removing an admin setting in `plugin.json` or a field on `configuration`
- After adding or changing a slash command or its arguments in `server/command.go`
- After adding or changing an HTTP route (`ServeHTTP`) or a webapp registration a user can see
- After changing any user-visible message text
- After changing a `make` target, a workflow, or the enclave procedure that a doc describes
- Before cutting a release

## When NOT to Use

- Pure refactors with no user-visible change
- Test-only changes
- Changes already documented in a previous commit on the same branch

## Workflow

Run these steps in order. **Always produce a plan and get explicit user
confirmation before editing any documentation file.**

Before starting, create tasks using TaskCreate for each applicable step. Mark
each complete with TaskUpdate as you finish it.

### 1. Survey what changed

```bash
git diff main...HEAD -- server/ webapp/src/ plugin.json Makefile build/ .github/ docs/ README.md
git log main..HEAD --oneline
```

Focus on: new or renamed settings; new slash commands or arguments; new routes;
changed `make` targets or workflow steps; and any changed string a user can see.

### 2. Produce a plan

Write a short plan and present it. It must list which files will be edited and
the specific user-visible change driving each edit, plus anything intentionally
left alone and why. Wait for explicit confirmation before continuing.

### 3. Update the docs

Edit only the files whose scope actually changed. Match the existing tone and
heading structure.

#### Change-to-file matrix

| What changed | Files to update |
|---|---|
| New or renamed setting | `plugin.json` (`display_name`, `help_text`), and the settings section of `README.md` |
| New or renamed slash subcommand | `README.md`, plus the subcommand list in the bare and unknown-subcommand replies in `server/command.go` |
| New HTTP route or webapp surface | `README.md` |
| Changed user-facing message text | Anywhere that quotes it, verbatim |
| New or changed `make` target | `README.md` or the `docs/` page that owns it, and the Build and test section of `CLAUDE.md` |
| Enclave build change | `docs/ENCLAVE.md` and the Air-gapped section of `CLAUDE.md` |
| Release or workflow change | `docs/RELEASING.md` or `docs/SECURITY.md`, and the matching section of `CLAUDE.md` |

#### Rules

1. **No em dashes, US spelling**, per `CLAUDE.md`. `check-style` does not lint
   Markdown or JSON text, so check by eye.
2. **Preserve heading anchors.** Docs link into each other (`docs/ENCLAVE.md`
   and friends are linked from `CLAUDE.md`). If you must rename a heading,
   update every link to it.
3. **Quote messages verbatim.** A doc whose text does not match the Go string
   is worse than none, because search will not find it.
4. **Do not hand-edit `plugin.json`'s `version` or `CHANGELOG.md`.**
   release-please owns both.
5. **Help pages under `public/` must work offline.** No CDN, no web fonts, no
   external images: they must render on an air-gapped host.

### 4. Verify

```sh
make check-style
make test
make dist
```

`make dist` regenerates `server/manifest.go` and `webapp/src/manifest.ts` from
`plugin.json`, so a malformed settings edit fails there. If `public/` exists,
confirm it is in the bundle:

```sh
tar tzf dist/com.mattermost.plugin-template-*.tar.gz | grep public/
```

Tests do not cover whether the prose is any good: read what you wrote.

### 5. Report

Summarize which files changed and why, and anything intentionally left alone.

## Common Mistakes

- Skipping the plan step. Always write the plan and get confirmation first.
- Adding a setting to `configuration` without `display_name` and `help_text` in `plugin.json`.
- Adding a slash subcommand without updating the "Available subcommands" replies.
- Editing `CHANGELOG.md` by hand.
- Renaming a heading another doc links to.
- Using em dashes.
- Hardcoding the plugin id. It belongs in `plugin.json` only; Go reads it from
  the generated `manifest`, the webapp from `webapp/src/manifest.ts`. If a Go
  helper is ever needed it must be a **function**, not a package-level `var`,
  because var initializers run before the generated `init()` populates the
  manifest.
