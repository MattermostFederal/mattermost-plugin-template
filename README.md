# Mattermost Plugin Template

A minimal Mattermost plugin template with both server (Go) and webapp (TypeScript/React) components. Use this as a starting point for building new Mattermost plugins.

## What's included

- **Server**: A minimal Go plugin registering a `/template hello` slash command.
- **Webapp**: A minimal React plugin registering a channel header button that pops a greeting.
- **Build tooling**: Makefile, mattermost-plugin-starter-template build scripts, CI workflows.
- **CI/CD automation**: PR validation, security scanning (SBOM + Grype + CodeQL), automated releases via [release-please](https://github.com/googleapis/release-please), and Dependabot updates. See [Automation](#automation) below.
- **Editor integration**: `.claude/` (Claude Code agents, commands, skills) and `.vscode/` settings.

## Getting started

1. Rename the plugin id and display name in `plugin.json` to match your new plugin.
2. Update the Go module path in `go.mod` from `github.com/MattermostFederal/mattermost-plugin-template` to your repo path.
3. Replace `assets/icon.svg` with your plugin icon.
4. Build and deploy:

```sh
make deploy
```

## Common commands

- `make dist` - build the plugin bundle
- `make check-style` - lint Go and webapp code
- `make test` - run tests
- `make deploy` - deploy to the Mattermost server specified by `MM_SERVICESETTINGS_SITEURL` and `MM_ADMIN_TOKEN`
- `make enclave-bundle` - pack a self-contained tarball for air-gapped builds

## Air-gapped (enclave) builds

The plugin builds with no network access. On a networked machine run
`make enclave-bundle` to produce a self-contained tarball; inside the enclave,
extract it and run `make dist`. Go modules are vendored and npm packages ship as
a pre-populated cache — both generated at staging time, so plugins that never
target an enclave carry nothing extra.

Prove any build is network-free with `make OFFLINE=1 dist`.

See **[docs/ENCLAVE.md](docs/ENCLAVE.md)** for prerequisites, the staging
workflow, and troubleshooting.

## Automation

The template comes with CI/CD wired up so a new plugin gets releases, security
scanning, and dependency updates for free.

### CI workflows (`.github/workflows/`)

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `pr.yml` | PRs to `main` | Style checks, tests, and a bundle build |
| `security.yml` | PRs, push to `main`, weekly | SBOM + Grype CVE scan and CodeQL (Go + JS/TS), uploaded to Code Scanning |
| `release-please.yml` | push to `main` | Maintains the Release PR (version bump + changelog) |
| `release.yml` | `v*` tag | Full security-gated `make release` + publishes the GitHub Release |

### Releasing

Releases are automated with **release-please** driven by
[Conventional Commits](https://www.conventionalcommits.org/) — you don't
hand-edit versions or the changelog. Commit `feat:`/`fix:` messages, merge the
Release PR release-please keeps open, and the tag + GitHub Release are created
for you.

See **[docs/RELEASING.md](docs/RELEASING.md)** for the commit format, the bump
rules, and the manual fallback.

### Security tooling

The template ships an SBOM + CVE + static-analysis pipeline (CycloneDX, Grype,
CodeQL, ClamAV, optional GPG signing), all reproducible locally via `make`:

- `make sbom-audit` - generate SBOMs and fail on HIGH/CRITICAL CVEs
- `make codeql-analyze && make security-gate` - static analysis + finding gate
- `make release` - the full security-gated pipeline CI runs on a tag

Suppress false positives in `.grype.yaml` with a documented reason. Enabling
GitHub Code Scanning is required for the SARIF upload steps (free on public
repos; needs Advanced Security on private).

See **[docs/SECURITY.md](docs/SECURITY.md)** for the full checklist, the Code
Scanning requirement, suppression guidance, and signing setup.

### Dependency updates

Dependabot (`.github/dependabot.yml`) opens weekly PRs for Go modules, npm
packages, and GitHub Actions, with security updates firing immediately.

See the [Mattermost plugin developer docs](https://developers.mattermost.com/extend/plugins/) for more information.
