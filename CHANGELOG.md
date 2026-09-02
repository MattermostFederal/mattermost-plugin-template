# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0](https://github.com/MattermostFederal/mattermost-plugin-template/compare/v0.1.3...v0.2.0) (2026-09-02)


### Features

* build the plugin offline in an air-gapped enclave ([536edb9](https://github.com/MattermostFederal/mattermost-plugin-template/commit/536edb9f29b0791f574fdb8728130315a1b3561c))
* build the plugin offline in an air-gapped enclave ([f68fc4b](https://github.com/MattermostFederal/mattermost-plugin-template/commit/f68fc4b00ab8dc3e783a1433fd7b6c4558af8052))


### Bug Fixes

* catch a stale npm cache in preflight, not at build time ([50792cf](https://github.com/MattermostFederal/mattermost-plugin-template/commit/50792cfe445ce109bf500175c43b3810ef785cc0))
* **ci:** least-privilege secrets + correct SARIF ref on release call ([7fa9d3f](https://github.com/MattermostFederal/mattermost-plugin-template/commit/7fa9d3f19eece515a82102773b5d55b418703145))
* **ci:** publish release assets via reusable workflow ([6a594d3](https://github.com/MattermostFederal/mattermost-plugin-template/commit/6a594d39cd51b23fc166f7ac5c954b7e755826fa))
* **ci:** publish release assets via reusable workflow ([f9fb57e](https://github.com/MattermostFederal/mattermost-plugin-template/commit/f9fb57eec631aebcccbdb92b65dee224dbfc6b4e))
* **ci:** set Grype fail-build to false to unblock dependabot PRs ([52ff964](https://github.com/MattermostFederal/mattermost-plugin-template/commit/52ff9645b6e38b1953ec5b5f117d2784a8748cd5))
* **ci:** set Grype fail-build to false to unblock dependabot PRs ([02465c3](https://github.com/MattermostFederal/mattermost-plugin-template/commit/02465c33c4518c28763d601aaee1f3ad8920289a))
* **deps:** bump Go to 1.26.7 and mattermost/server/public to v0.4.4 ([c2ef8a2](https://github.com/MattermostFederal/mattermost-plugin-template/commit/c2ef8a2712cd3405adf54bad8541bf84ed87bb3d))
* make offline mode hold against the command line, and fail fast ([355670f](https://github.com/MattermostFederal/mattermost-plugin-template/commit/355670f9d6218b616187673e57d02a3b4b3fa542))
* pin Node 22 in .nvmrc to match CI and dependency engines ([11a182b](https://github.com/MattermostFederal/mattermost-plugin-template/commit/11a182b4516ad6d6bf7b8ef1902b5c712bdc7f2d))
* pin Node 22 in .nvmrc to match CI and dependency engines ([0edb1b6](https://github.com/MattermostFederal/mattermost-plugin-template/commit/0edb1b60a550f6d069202eb011ff8dafecd526aa))
* strip --mod as well as -mod from offline GOFLAGS ([10c502c](https://github.com/MattermostFederal/mattermost-plugin-template/commit/10c502c1651b5f9d68031bdd9963f0747974828a))
* strip -mod from GO_BUILD_FLAGS and GO_TEST_FLAGS when offline ([444fbb4](https://github.com/MattermostFederal/mattermost-plugin-template/commit/444fbb45ae239b4d36dc023fc1cccc3d93cdc055))


### Dependencies

* **actions:** bump github/codeql-action/upload-sarif ([05633d7](https://github.com/MattermostFederal/mattermost-plugin-template/commit/05633d724696ddc9a0e110916e041c25184b588a))
* **actions:** bump the actions-minor-patch group across 1 directory with 2 updates ([a12b6e3](https://github.com/MattermostFederal/mattermost-plugin-template/commit/a12b6e3ab6feeced14c24a8e64491fa3671adeee))
* **webapp:** bump the npm-minor-patch group across 1 directory with 8 updates ([8e10415](https://github.com/MattermostFederal/mattermost-plugin-template/commit/8e1041580f25610f7a0e7d13b720b9e06893ded9))
* **webapp:** bump the npm-minor-patch group in /webapp with 3 updates ([d71269f](https://github.com/MattermostFederal/mattermost-plugin-template/commit/d71269f498f4220fbcb2c32dbf3dbffc67aa03e0))

## [0.1.3](https://github.com/MattermostFederal/mattermost-plugin-template/compare/v0.1.2...v0.1.3) (2026-08-03)


### Bug Fixes

* **deps:** bump Go + npm deps to clear HIGH CVEs blocking the Grype gate ([55f9fb7](https://github.com/MattermostFederal/mattermost-plugin-template/commit/55f9fb7c57b0e02aa524830bedc81d174f61cc26))


### Dependencies

* **actions:** Bump actions/setup-go from 6.5.0 to 7.0.0 ([8980846](https://github.com/MattermostFederal/mattermost-plugin-template/commit/8980846a8030dd758982386476e5023dc9ba69ba))
* **actions:** Bump actions/setup-node from 6.4.0 to 7.0.0 ([d0c713b](https://github.com/MattermostFederal/mattermost-plugin-template/commit/d0c713b529928e2f47d30d765c987d2aa1271109))
* **actions:** Bump the actions-minor-patch group across 1 directory with 2 updates ([cf33824](https://github.com/MattermostFederal/mattermost-plugin-template/commit/cf3382450a1698d35aa804a94e55d5abde4cddf0))
* **webapp:** Bump the npm-minor-patch group across 1 directory with 13 updates ([2843573](https://github.com/MattermostFederal/mattermost-plugin-template/commit/2843573c6128bb24eb60b7a9f3f8262b7358a2cf))

## [0.1.2](https://github.com/MattermostFederal/mattermost-plugin-template/compare/v0.1.1...v0.1.2) (2026-07-13)


### Bug Fixes

* **ci:** make Grype/CodeQL SARIF ingestible + visibility-aware upload ([8240d2b](https://github.com/MattermostFederal/mattermost-plugin-template/commit/8240d2b9a114bebb33497b9eea105edffeecdc14))
* **ci:** make Grype/CodeQL SARIF ingestible + visibility-aware upload ([068059f](https://github.com/MattermostFederal/mattermost-plugin-template/commit/068059f26fcf512676c01fddd45e974b7263b8f5))


### Dependencies

* **actions:** Bump the actions-minor-patch group with 2 updates ([a0ab947](https://github.com/MattermostFederal/mattermost-plugin-template/commit/a0ab947d10181c9fed5dae29174a797efa12c330))
* **webapp:** Bump the npm-minor-patch group in /webapp with 2 updates ([285e32e](https://github.com/MattermostFederal/mattermost-plugin-template/commit/285e32ec272fd66fafbabd0f5c172a8d198236e0))

## [0.1.1](https://github.com/MattermostFederal/mattermost-plugin-template/compare/v0.1.0...v0.1.1) (2026-07-06)


### Bug Fixes

* **ci:** mkdir dist in codeql-go/codeql-js before writing SARIF ([d1f6233](https://github.com/MattermostFederal/mattermost-plugin-template/commit/d1f6233cbe6f3e5e018ec1f8bb8a15789583350e))
* **dependabot:** ignore eslint majors + drop include:scope double-scope ([53ce60b](https://github.com/MattermostFederal/mattermost-plugin-template/commit/53ce60b96bdcf3cbe6b657b7e3b24d44d59a2c87))
* **dependabot:** ignore eslint majors + fix double-scope commit prefixes ([9e52dda](https://github.com/MattermostFederal/mattermost-plugin-template/commit/9e52dda3bd10b1a7b0654873fe51c8e9f0e0d398))


### Dependencies

* **actions:** Bump actions/cache from 4.2.3 to 6.1.0 ([0dbfdaf](https://github.com/MattermostFederal/mattermost-plugin-template/commit/0dbfdaf3aac6c705fee1663fc5f21a7ff2b50fb0))
* **actions:** Bump actions/upload-artifact from 4.4.3 to 7.0.1 ([39e8847](https://github.com/MattermostFederal/mattermost-plugin-template/commit/39e884730626ba98699d9a9d1baf167fc67a425e))
* **actions:** Bump github/codeql-action/upload-sarif ([c34b70c](https://github.com/MattermostFederal/mattermost-plugin-template/commit/c34b70cd3b1e54b5a7f77840a68a3cc683c7c94d))
* **actions:** Bump googleapis/release-please-action from 4.2.0 to 5.0.0 ([4c7f7c8](https://github.com/MattermostFederal/mattermost-plugin-template/commit/4c7f7c8c6eac3ba5813277fd80abead6de47659c))

## [Unreleased]

### Added
- Initial plugin template.
