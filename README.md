# Mattermost Plugin Template

A minimal Mattermost plugin template with both server (Go) and webapp (TypeScript/React) components. Use this as a starting point for building new Mattermost plugins.

## What's included

- **Server**: A minimal Go plugin registering a `/template hello` slash command.
- **Webapp**: A minimal React plugin registering a channel header button that pops a greeting.
- **Build tooling**: Makefile, mattermost-plugin-starter-template build scripts, CI workflows.
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

## Vulnerability scanning

The template ships with a CycloneDX SBOM and grype-based vulnerability audit:

- `make sbom` - generate CycloneDX SBOMs for the Go server and npm webapp into `dist/sbom/`
- `make sbom-scan` - run grype against the SBOMs and fail on high or critical CVEs
- `make sbom-audit` - `sbom` then `sbom-scan` in one step

Suppress known-false-positive findings by adding entries to `.grype.yaml` with a short reason. Typical reasons include: dev-only transitive dependency (not in the shipped bundle) or runtime dependency that Mattermost externalizes (e.g. react, redux).

See the [Mattermost plugin developer docs](https://developers.mattermost.com/extend/plugins/) for more information.
