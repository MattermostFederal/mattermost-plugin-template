GO ?= $(shell command -v go 2> /dev/null)
NPM ?= $(shell command -v npm 2> /dev/null)
CURL ?= $(shell command -v curl 2> /dev/null)
MM_DEBUG ?=

# ====================================================================================
# Enclave / offline build support
#
# `make enclave-stage` runs on a networked machine and gathers everything `make
# dist` needs: Go modules into vendor/, npm packages into build/enclave/.
# `make enclave-bundle` packs those with the source into a single tarball;
# inside the enclave, `make dist` then builds with no network.
#
# Both are generated artifacts, deliberately gitignored rather than committed:
# plugins that never target an enclave carry no cost, and there is no vendor
# tree that can drift from go.mod as dependencies are bumped.
#
# See docs/ENCLAVE.md for the full procedure.
# ====================================================================================

ENCLAVE_DIR ?= $(CURDIR)/build/enclave
NPM_CACHE_DIR ?= $(ENCLAVE_DIR)/npm-cache
# sha256 of the webapp/package-lock.json the cache above was populated from, so
# enclave-preflight can tell a usable cache from a stale one.
NPM_CACHE_LOCK_STAMP ?= $(ENCLAVE_DIR)/package-lock.sha256

# npm resolves some transitive dependencies (lightningcss, @parcel/watcher) to
# prebuilt, platform-specific binaries. Stage every platform the enclave might
# build on, so the bundle does not depend on which machine staged it.
ENCLAVE_NPM_PLATFORMS ?= linux/x64/glibc linux/arm64/glibc linux/x64/musl darwin/arm64 darwin/x64

# Node major version the webapp build requires; kept in sync with .nvmrc.
ENCLAVE_NODE_VERSION ?= $(shell cat .nvmrc 2>/dev/null)

# Offline mode enables itself inside a shipped bundle, which `make
# enclave-bundle` marks with build/enclave/OFFLINE. Deliberately not keyed off
# the npm cache: that also exists on the machine that did the staging, which
# still needs a normal networked build. Force it on with OFFLINE=1 to prove a
# build needs no network, or off with OFFLINE=0.
ifeq ($(origin OFFLINE), undefined)
    OFFLINE := $(if $(wildcard $(ENCLAVE_DIR)/OFFLINE),1,)
endif
ifeq ($(OFFLINE),0)
    # `override`, because OFFLINE=0 is only ever given on the command line - and
    # a plain assignment there would lose to it, leaving OFFLINE set to the
    # non-empty string "0" and every check below reading that as "yes, offline".
    # The escape hatch require-network points at has to actually work.
    override OFFLINE :=
endif

ifneq ($(OFFLINE),)
    # Every assignment in this branch is an `override`. A plain assignment loses
    # to a value given on the command line, so `make OFFLINE=1 GOPROXY=https://…`
    # would quietly put the network back into a build whose entire purpose is to
    # prove it needs none. Offline mode is a guarantee, not a default.
    #
    # Resolve Go packages from vendor/ only, and refuse module fetches outright so
    # a missing dependency fails loudly here rather than silently reaching out.
    # A -mod= the caller supplied is dropped rather than prepended to, because Go
    # honours the last occurrence in GOFLAGS - so -mod=mod would otherwise win.
    # Both spellings have to go: Go's flag parser treats --mod=mod exactly like
    # -mod=mod, so filtering only the single-dash form leaves the hole open. The
    # space-separated form needs no handling - Go rejects it outright with
    # `parsing $GOFLAGS: non-flag "vendor"`, which fails closed.
    override GOFLAGS := -mod=vendor $(filter-out -mod=% --mod=%,$(GOFLAGS))
    override GOPROXY := off
    # Never download a Go toolchain: go.mod names a specific version, and the
    # default GOTOOLCHAIN=auto would fetch it from the module proxy. The enclave
    # must provide it; `make enclave-preflight` checks that it does.
    override GOTOOLCHAIN := local
    export GOFLAGS GOPROXY GOTOOLCHAIN
    # --ignore-scripts is required, not just tidiness: webapp's postinstall runs
    # `playwright install chromium`, which fetches ~400MB of browsers from the
    # Playwright CDN and fails the build with no network. (Note that
    # PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD does NOT help here -- it is only honoured
    # by the playwright package's own postinstall, not by an explicit
    # `playwright install` invocation.) Browsers are a `make test` dependency and
    # are never needed to build the plugin. The only other install scripts in the
    # tree are core-js's funding banner and the optional, test-only
    # @parcel/watcher and fsevents, none of which the webpack build uses.
    override NPM_INSTALL_ARGS := ci --offline --ignore-scripts --cache $(NPM_CACHE_DIR) --no-audit --no-fund
else
    # Go switches to vendor mode automatically whenever a vendor/ directory is
    # present. Pin -mod=mod so that a vendor/ left behind by an earlier staging
    # run cannot change how a normal networked build resolves packages, or fail
    # it with "inconsistent vendoring" after a go.mod bump. Prepended, so an
    # explicit GOFLAGS from the environment still wins.
    GOFLAGS := -mod=mod $(GOFLAGS)
    export GOFLAGS
    NPM_INSTALL_ARGS := install
endif

GOPATH ?= $(shell go env GOPATH)
GO_TEST_FLAGS ?= -race
GO_BUILD_FLAGS ?=

ifneq ($(OFFLINE),)
    # These two are interpolated straight onto the `go build` / `go test`
    # command line, where a flag beats GOFLAGS - so -mod=mod here selects the
    # module cache over the staged vendor/ tree just as effectively as setting
    # GOFLAGS would, and sails past the filtering done up there. Same two
    # spellings, same reason.
    #
    # GO_TEST_FLAGS is included even though `make test` refuses to run offline:
    # coverage-backend uses it and is not behind require-network, so the hole is
    # narrower but real.
    override GO_BUILD_FLAGS := $(filter-out -mod=% --mod=%,$(GO_BUILD_FLAGS))
    override GO_TEST_FLAGS := $(filter-out -mod=% --mod=%,$(GO_TEST_FLAGS))
endif

DEFAULT_GOOS := $(shell go env GOOS)
DEFAULT_GOARCH := $(shell go env GOARCH)

export GO111MODULE=on

# We need to export GOBIN to allow it to be set
# for processes spawned from the Makefile
export GOBIN ?= $(PWD)/bin

# You can include assets this directory into the bundle. This can be e.g. used to include profile pictures.
ASSETS_DIR ?= assets

# Verify environment, and define PLUGIN_ID, PLUGIN_VERSION, HAS_SERVER and HAS_WEBAPP as needed.
include build/setup.mk

BUNDLE_NAME ?= $(PLUGIN_ID)-$(PLUGIN_VERSION).tar.gz

# Include custom makefile, if present
ifneq ($(wildcard build/custom.mk),)
	include build/custom.mk
endif

ifneq ($(MM_DEBUG),)
	GO_BUILD_GCFLAGS = -gcflags "all=-N -l"
else
	GO_BUILD_GCFLAGS =
endif

# ====================================================================================
# Default Target
# ====================================================================================

.PHONY: default
default: all

# ====================================================================================
# Build Targets
# ====================================================================================

## Checks the code style, tests, builds and bundles the plugin.
.PHONY: all
all: check-style test dist

## Pre-release checks: git status and changelog validation.
.PHONY: release-check
release-check:
	@echo "Running pre-release checks..."
	@if [ -n "$$(git status --porcelain -- . ':!webapp/package-lock.json')" ]; then \
		echo "ERROR: Working directory has uncommitted changes."; \
		echo "Please commit or stash changes before building a release."; \
		git status --short -- . ':!webapp/package-lock.json'; \
		exit 1; \
	fi
	@if [ ! -f CHANGELOG.md ]; then \
		echo "ERROR: CHANGELOG.md not found."; \
		exit 1; \
	fi
	@if ! grep -q "## \[Unreleased\]" CHANGELOG.md && ! grep -q "## \[$(PLUGIN_VERSION)\]" CHANGELOG.md; then \
		echo "WARNING: CHANGELOG.md may not be updated for version $(PLUGIN_VERSION)."; \
	fi
	@echo "Pre-release checks passed."

## Generate SHA256 checksum for the release bundle.
.PHONY: release-checksum
release-checksum:
	@echo "Generating SHA256 checksum..."
	@cd dist && shasum -a 256 $(BUNDLE_NAME) > $(BUNDLE_NAME).sha256
	@echo "Checksum: $$(cat dist/$(BUNDLE_NAME).sha256)"

## Include SBOMs and CodeQL results in the release bundle and repackage.
.PHONY: release-bundle
release-bundle:
	@echo "Including SBOMs and security reports in release bundle..."
	@if [ -d dist/sbom ]; then \
		cp -r dist/sbom dist/$(PLUGIN_ID)/; \
		echo "SBOMs included in bundle"; \
	else \
		echo "WARNING: No SBOMs found to include"; \
	fi
	@mkdir -p dist/$(PLUGIN_ID)/security
	@if [ -f dist/codeql-go.sarif ]; then \
		cp dist/codeql-go.sarif dist/$(PLUGIN_ID)/security/; \
		echo "Go CodeQL results included"; \
	fi
	@if [ -f dist/codeql-js.sarif ]; then \
		cp dist/codeql-js.sarif dist/$(PLUGIN_ID)/security/; \
		echo "JavaScript CodeQL results included"; \
	fi
	@rm -f dist/$(BUNDLE_NAME)
	@if [ "$$(uname)" = "Darwin" ]; then \
		cd dist && tar --disable-copyfile -cvzf $(BUNDLE_NAME) $(PLUGIN_ID); \
	else \
		cd dist && tar -cvzf $(BUNDLE_NAME) $(PLUGIN_ID); \
	fi

## Sign the plugin bundle with GPG (requires PLUGIN_SIGNING_KEY env var).
.PHONY: release-sign
release-sign:
	@if [ -n "$(PLUGIN_SIGNING_KEY)" ]; then \
		echo "Signing plugin bundle with GPG key $(PLUGIN_SIGNING_KEY)..."; \
		gpg -u $(PLUGIN_SIGNING_KEY) --verbose --personal-digest-preferences SHA256 --detach-sign dist/$(BUNDLE_NAME); \
		echo "Signature: dist/$(BUNDLE_NAME).sig"; \
	else \
		echo "PLUGIN_SIGNING_KEY not set, skipping signing."; \
		echo "To sign, set PLUGIN_SIGNING_KEY to your GPG key ID."; \
	fi

## Create a git tag for the release version.
.PHONY: release-tag
release-tag:
	@echo "Creating git tag v$(PLUGIN_VERSION)..."
	@if git rev-parse "v$(PLUGIN_VERSION)" >/dev/null 2>&1; then \
		echo "ERROR: Tag v$(PLUGIN_VERSION) already exists."; \
		exit 1; \
	fi
	git tag -a "v$(PLUGIN_VERSION)" -m "Release v$(PLUGIN_VERSION)"
	@echo "Tag v$(PLUGIN_VERSION) created. Push with: git push origin v$(PLUGIN_VERSION)"

## Full release build: clean, checks, style, tests, build, SBOM audit, CodeQL, bundle with SBOMs, sign, and checksum.
.PHONY: release
release: release-check clean all sbom-audit codeql-analyze security-gate release-bundle virus-scan release-sign release-checksum
	@echo ""
	@echo "=========================================="
	@echo "Release build complete!"
	@echo "Bundle:   dist/$(BUNDLE_NAME)"
	@echo "Checksum: dist/$(BUNDLE_NAME).sha256"
	@if [ -f dist/$(BUNDLE_NAME).sig ]; then echo "Signature: dist/$(BUNDLE_NAME).sig"; fi
	@echo "SBOMs included in bundle"
	@echo ""
	@echo "To tag this release: make release-tag"
	@echo "=========================================="

## Ensures the plugin manifest is valid
.PHONY: manifest-check
manifest-check:
	./build/bin/manifest check

## Propagates plugin manifest information into the server/ and webapp/ folders.
.PHONY: apply
apply:
	./build/bin/manifest apply

## Builds the server, if it exists, for all supported architectures, unless MM_SERVICESETTINGS_ENABLEDEVELOPER is set.
.PHONY: server
server:
ifneq ($(HAS_SERVER),)
ifneq ($(MM_DEBUG),)
	$(info DEBUG mode is on; to disable, unset MM_DEBUG)
endif
	mkdir -p server/dist;
ifneq ($(MM_SERVICESETTINGS_ENABLEDEVELOPER),)
	@echo Building plugin only for $(DEFAULT_GOOS)-$(DEFAULT_GOARCH) because MM_SERVICESETTINGS_ENABLEDEVELOPER is enabled
	cd server && env CGO_ENABLED=0 $(GO) build $(GO_BUILD_FLAGS) $(GO_BUILD_GCFLAGS) -trimpath -o dist/plugin-$(DEFAULT_GOOS)-$(DEFAULT_GOARCH);
else
	cd server && env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 $(GO) build $(GO_BUILD_FLAGS) $(GO_BUILD_GCFLAGS) -trimpath -o dist/plugin-linux-amd64;
	cd server && env CGO_ENABLED=0 GOOS=linux GOARCH=arm64 $(GO) build $(GO_BUILD_FLAGS) $(GO_BUILD_GCFLAGS) -trimpath -o dist/plugin-linux-arm64;
endif
endif

## Ensures NPM dependencies are installed without having to run this all the time.
webapp/node_modules: $(wildcard webapp/package.json) $(wildcard webapp/package-lock.json)
ifneq ($(HAS_WEBAPP),)
ifneq ($(OFFLINE),)
	@if [ ! -d "$(NPM_CACHE_DIR)" ]; then \
		echo "ERROR: offline build requested but no staged npm cache at $(NPM_CACHE_DIR)."; \
		echo "Run 'make enclave-stage' on a networked machine, or build with OFFLINE=0."; \
		exit 1; \
	fi
endif
	cd webapp && $(NPM) $(NPM_INSTALL_ARGS)
	touch $@
endif

## Builds the webapp, if it exists.
.PHONY: webapp
webapp: webapp/node_modules
ifneq ($(HAS_WEBAPP),)
ifeq ($(MM_DEBUG),)
	cd webapp && $(NPM) run build;
else
	cd webapp && $(NPM) run debug;
endif
endif

## Generates a tar bundle of the plugin for install.
.PHONY: bundle
bundle:
	rm -rf dist/
	mkdir -p dist/$(PLUGIN_ID)
	./build/bin/manifest dist
ifneq ($(wildcard $(ASSETS_DIR)/.),)
	cp -r $(ASSETS_DIR) dist/$(PLUGIN_ID)/
endif
ifneq ($(HAS_PUBLIC),)
	cp -r public dist/$(PLUGIN_ID)/
endif
ifneq ($(HAS_SERVER),)
	mkdir -p dist/$(PLUGIN_ID)/server
	cp -r server/dist dist/$(PLUGIN_ID)/server/
endif
ifneq ($(HAS_WEBAPP),)
	mkdir -p dist/$(PLUGIN_ID)/webapp
	cp -r webapp/dist dist/$(PLUGIN_ID)/webapp/
endif
ifeq ($(shell uname),Darwin)
	cd dist && tar --disable-copyfile -cvzf $(BUNDLE_NAME) $(PLUGIN_ID)
else
	cd dist && tar -cvzf $(BUNDLE_NAME) $(PLUGIN_ID)
endif

	@echo plugin built at: dist/$(BUNDLE_NAME)

## Builds and bundles the plugin.
.PHONY: dist
dist: apply server webapp bundle

# ====================================================================================
# Enclave Targets
#
# `make enclave-bundle` (networked machine) -> carry tarball in -> `make dist`.
# ====================================================================================

ENCLAVE_SRC_NAME ?= $(PLUGIN_ID)-$(PLUGIN_VERSION)-enclave
ENCLAVE_BUNDLE_NAME ?= $(ENCLAVE_SRC_NAME).tar.gz
ENCLAVE_STAGE_TMP := $(ENCLAVE_DIR)/.npm-stage

# Source paths carried into the enclave. Everything `make dist` reads, plus the
# vendored Go modules and the staged npm cache under build/.
ENCLAVE_BUNDLE_PATHS ?= Makefile plugin.json go.mod go.sum vendor build server webapp assets \
	$(wildcard public) $(wildcard docs) $(wildcard README.md) $(wildcard LICENSE) \
	$(wildcard CHANGELOG.md) $(wildcard .nvmrc) $(wildcard .golangci.yml) $(wildcard .gitattributes)

# Host-specific or regenerable artifacts that must not travel in the bundle.
ENCLAVE_BUNDLE_EXCLUDES ?= --exclude=node_modules --exclude=build/bin --exclude=build/codeql \
	--exclude=build/codeql-db --exclude=server/dist --exclude=webapp/dist --exclude=.eslintcache \
	--exclude=.DS_Store --exclude=coverage --exclude=coverage-ct --exclude=test-results

## Verify the enclave provides the toolchain and staged dependencies the build needs.
.PHONY: enclave-preflight
enclave-preflight:
	@echo "Checking enclave build prerequisites..."
	@failed=0; \
	if [ -z "$(GO)" ]; then \
		echo "  FAIL  go not found on PATH"; failed=1; \
	elif ! out=$$(GOTOOLCHAIN=local $(GO) list -m 2>&1); then \
		echo "  FAIL  Go toolchain too old for go.mod, and GOTOOLCHAIN=local forbids downloading one:"; \
		echo "        $$out"; failed=1; \
	else \
		echo "  OK    Go toolchain: $$(GOTOOLCHAIN=local $(GO) env GOVERSION)"; \
	fi; \
	if [ -f vendor/modules.txt ]; then \
		echo "  OK    Go modules vendored: $$(grep -c '^# ' vendor/modules.txt) modules in vendor/"; \
	else \
		echo "  FAIL  vendor/modules.txt missing; run 'make enclave-stage' on a networked machine"; failed=1; \
	fi; \
	if [ -z "$(NPM)" ]; then \
		echo "  FAIL  npm not found on PATH"; failed=1; \
	else \
		echo "  OK    npm $$($(NPM) --version)"; \
	fi; \
	if ! command -v node >/dev/null 2>&1; then \
		echo "  FAIL  node not found on PATH"; failed=1; \
	else \
		have=$$(node --version | sed 's/^v//' | cut -d. -f1); \
		want=$$(echo "$(ENCLAVE_NODE_VERSION)" | cut -d. -f1); \
		if [ -n "$$want" ] && [ "$$have" -lt "$$want" ]; then \
			echo "  FAIL  node $$(node --version) is older than the required v$$want (see .nvmrc)"; failed=1; \
		else \
			echo "  OK    node $$(node --version)"; \
		fi; \
	fi; \
	if [ ! -d "$(NPM_CACHE_DIR)" ]; then \
		echo "  FAIL  no npm cache at $(NPM_CACHE_DIR); run 'make enclave-stage' on a networked machine"; failed=1; \
	elif [ ! -f "$(NPM_CACHE_LOCK_STAMP)" ]; then \
		echo "  FAIL  npm cache has no stage stamp; it predates this check."; \
		echo "        Re-run 'make enclave-stage' on a networked machine."; failed=1; \
	elif [ "$$(cat $(NPM_CACHE_LOCK_STAMP))" != "$$(shasum -a 256 webapp/package-lock.json | cut -d' ' -f1)" ]; then \
		echo "  FAIL  npm cache was staged for a different webapp/package-lock.json."; \
		echo "        Dependencies have changed since; the offline build would fail with"; \
		echo "        ENOTCACHED on whichever package moved. Re-run 'make enclave-stage'."; failed=1; \
	else \
		echo "  OK    npm cache staged at $(NPM_CACHE_DIR), matches webapp/package-lock.json"; \
	fi; \
	if [ -n "$(OFFLINE)" ]; then \
		echo "  OK    offline mode active (GOFLAGS=-mod=vendor GOPROXY=off GOTOOLCHAIN=local)"; \
	else \
		echo "  WARN  offline mode is off; this build may reach the network. Use OFFLINE=1 to forbid it."; \
	fi; \
	if [ "$$failed" -eq 1 ]; then \
		echo ""; \
		echo "Preflight FAILED. See docs/ENCLAVE.md."; \
		exit 1; \
	fi
	@echo "Preflight passed; 'make dist' can build without network access."

# These two targets are the online half of the workflow, so they must ignore the
# offline constraints even if OFFLINE was forced on for the invocation.
enclave-stage enclave-bundle: GOFLAGS :=
enclave-stage enclave-bundle: GOPROXY :=
enclave-stage enclave-bundle: GOTOOLCHAIN := auto

## Stage every dependency the plugin build needs into vendor/ and build/enclave/ (requires network).
.PHONY: enclave-stage
enclave-stage:
	@echo "==> Staging enclave build dependencies (this step requires network access)"
	@echo "--> Vendoring Go modules into vendor/"
	$(GO) mod vendor
	@echo "--> Populating npm cache at $(NPM_CACHE_DIR)"
	@rm -rf $(NPM_CACHE_DIR) $(ENCLAVE_STAGE_TMP)
	@mkdir -p $(NPM_CACHE_DIR) $(ENCLAVE_STAGE_TMP)
	@cp webapp/package.json webapp/package-lock.json $(ENCLAVE_STAGE_TMP)/
	@if [ -f webapp/.npmrc ]; then cp webapp/.npmrc $(ENCLAVE_STAGE_TMP)/; fi
	@set -e; for platform in $(ENCLAVE_NPM_PLATFORMS); do \
		os=$$(echo $$platform | cut -d/ -f1); \
		cpu=$$(echo $$platform | cut -d/ -f2); \
		libc=$$(echo $$platform | cut -s -d/ -f3); \
		echo "--> Caching npm packages for $$os/$$cpu$${libc:+/$$libc}"; \
		( cd $(ENCLAVE_STAGE_TMP) && $(NPM) ci \
			--cache $(NPM_CACHE_DIR) --os=$$os --cpu=$$cpu $${libc:+--libc=$$libc} \
			--ignore-scripts --no-audit --no-fund >/dev/null ); \
	done
	@rm -rf $(ENCLAVE_STAGE_TMP)
	@# Record which lock file this cache was populated from. A cache staged for
	@# an older package-lock.json looks perfectly healthy - the directory is
	@# there, full of tarballs - and then fails the offline build with
	@# ENOTCACHED on whichever dependency moved. enclave-preflight compares this
	@# so that gets caught before a bundle is carried into the enclave.
	@shasum -a 256 webapp/package-lock.json | cut -d' ' -f1 > $(NPM_CACHE_LOCK_STAMP)
	@echo ""
	@echo "Staged: vendor/ ($$(du -sh vendor | cut -f1)), $(NPM_CACHE_DIR) ($$(du -sh $(NPM_CACHE_DIR) | cut -f1))"
	@echo "Verify with: make OFFLINE=1 clean dist"

## Pack source, vendored Go modules and the staged npm cache into one tarball to carry into the enclave.
.PHONY: enclave-bundle
enclave-bundle: enclave-stage
	@echo "==> Packing enclave bundle"
	@rm -rf dist/enclave
	@mkdir -p dist/enclave/$(ENCLAVE_SRC_NAME)
	tar -cf - $(ENCLAVE_BUNDLE_EXCLUDES) $(ENCLAVE_BUNDLE_PATHS) | tar -xf - -C dist/enclave/$(ENCLAVE_SRC_NAME)
	@# Marks the extracted tree as a shipped bundle so the build defaults to offline mode.
	@mkdir -p dist/enclave/$(ENCLAVE_SRC_NAME)/build/enclave
	@touch dist/enclave/$(ENCLAVE_SRC_NAME)/build/enclave/OFFLINE
ifeq ($(shell uname),Darwin)
	cd dist/enclave && tar --disable-copyfile -czf ../$(ENCLAVE_BUNDLE_NAME) $(ENCLAVE_SRC_NAME)
else
	cd dist/enclave && tar -czf ../$(ENCLAVE_BUNDLE_NAME) $(ENCLAVE_SRC_NAME)
endif
	@rm -rf dist/enclave
	@echo ""
	@echo "=========================================="
	@echo "Enclave bundle: dist/$(ENCLAVE_BUNDLE_NAME) ($$(du -h dist/$(ENCLAVE_BUNDLE_NAME) | cut -f1))"
	@echo ""
	@echo "In the enclave:"
	@echo "  tar -xzf $(ENCLAVE_BUNDLE_NAME)"
	@echo "  cd $(ENCLAVE_SRC_NAME)"
	@echo "  make enclave-preflight"
	@echo "  make dist"
	@echo "=========================================="

# ====================================================================================
# Quality Targets
# ====================================================================================

## Internal: fail fast when a target that downloads tooling is run in offline mode.
.PHONY: require-network
require-network:
ifneq ($(OFFLINE),)
	@echo "ERROR: this target downloads tooling and cannot run in offline mode."
	@echo "Only the plugin build (make dist) is staged for the enclave; lint, test"
	@echo "and security tooling must be run on a networked machine."
	@echo "If this machine does have network access, override with OFFLINE=0."
	@exit 1
endif

## Install go tools
install-go-tools: require-network
	@echo Installing go tools
	$(GO) install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.8.0
	$(GO) install gotest.tools/gotestsum@v1.13.0

# check-style, test and test-ci each split in two. Make is free to build a
# target's prerequisites in any order, and to build them concurrently under -j,
# so listing require-network alongside apply and webapp/node_modules does not
# stop those from running first: an offline `make -j test` got as far as syncing
# the plugin and running npm ci before the guard fired. Checking the guard in
# one rule and re-entering make for the real work is what actually orders them,
# serially and in parallel alike.
#
# The wrapper keeps the documented target name; the -impl half carries the real
# prerequisites and recipe.

## Runs eslint and golangci-lint
.PHONY: check-style
check-style: require-network
	@$(MAKE) --no-print-directory check-style-impl

## Internal: the check-style work proper, sequenced behind the offline guard.
.PHONY: check-style-impl
check-style-impl: manifest-check apply webapp/node_modules install-go-tools
	@echo Checking for style guide compliance

ifneq ($(HAS_WEBAPP),)
	cd webapp && npm run lint
	cd webapp && npm run check-types
endif

# It's highly recommended to run go-vet first
# to find potential compile errors that could introduce
# weird reports at golangci-lint step
ifneq ($(HAS_SERVER),)
	@echo Running golangci-lint
	$(GO) vet ./server/...
	$(GOBIN)/golangci-lint run ./server/...
endif

## Runs any lints and unit tests defined for the server and webapp, if they exist.
.PHONY: test
test: require-network
	@$(MAKE) --no-print-directory test-impl

## Internal: the test work proper, sequenced behind the offline guard.
.PHONY: test-impl
test-impl: apply webapp/node_modules install-go-tools
ifneq ($(HAS_SERVER),)
	$(GOBIN)/gotestsum -- -v ./...
endif
ifneq ($(HAS_WEBAPP),)
	cd webapp && $(NPM) run test;
endif

## Runs any lints and unit tests defined for the server and webapp, if they exist, optimized for a CI environment.
.PHONY: test-ci
test-ci: require-network
	@$(MAKE) --no-print-directory test-ci-impl

## Internal: the test-ci work proper, sequenced behind the offline guard.
.PHONY: test-ci-impl
test-ci-impl: apply webapp/node_modules install-go-tools
ifneq ($(HAS_SERVER),)
	$(GOBIN)/gotestsum --format standard-verbose --junitfile report.xml -- ./...
endif
ifneq ($(HAS_WEBAPP),)
	cd webapp && $(NPM) run test;
endif

## Prints Go code coverage summary to terminal.
.PHONY: coverage-backend
coverage-backend: apply
ifneq ($(HAS_SERVER),)
	$(GO) test $(GO_TEST_FLAGS) -coverprofile=server/coverage.txt ./server/...
	$(GO) tool cover -func=server/coverage.txt
endif

## Prints frontend code coverage summary to terminal.
.PHONY: coverage-frontend
coverage-frontend: webapp/node_modules
ifneq ($(HAS_WEBAPP),)
	cd webapp && $(NPM) run test:coverage
	cd webapp && $(NPM) run test:pw-ct-coverage
	@echo ""
	@echo "=== Merged Coverage (unit + component) ==="
	cd webapp && $(NPM) run test:coverage-merged
endif

## Prints code coverage summary for both backend and frontend.
.PHONY: coverage
coverage: coverage-backend coverage-frontend

## Clean removes all build artifacts (but preserves build tools).
.PHONY: clean
clean:
	rm -fr dist/
ifneq ($(HAS_SERVER),)
	rm -fr server/coverage.txt
	rm -fr server/dist
endif
ifneq ($(HAS_WEBAPP),)
	rm -fr webapp/junit.xml
	rm -fr webapp/dist
	rm -fr webapp/node_modules
	rm -fr webapp/coverage
	rm -fr webapp/coverage-ct
	rm -fr webapp/.v8-ct-coverage
endif

## Nuke everything: Docker containers, data, and all build artifacts
.PHONY: nuke
nuke: docker-kill-orphans
	@echo "Nuking everything..."
	@$(DOCKER_COMPOSE) down -v 2>/dev/null || true
	@rm -rf docker/postgres-data docker/mattermost
	@rm -fr dist/
	@rm -fr server/coverage.txt server/dist
	@rm -fr webapp/junit.xml webapp/dist webapp/node_modules
	@rm -fr webapp/coverage webapp/coverage-ct webapp/.v8-ct-coverage
	@rm -fr build/bin/
	@echo "Everything removed. Run 'make docker-setup' to start fresh."

## Generate mocks
.PHONY: mock
mock: require-network
ifneq ($(HAS_SERVER),)
	go install go.uber.org/mock/mockgen@v0.6.0
	@echo "No mocks configured for this plugin. Add your mockgen commands here."
endif

# ====================================================================================
# Docker Development Environment
# ====================================================================================
DOCKER_COMPOSE := docker compose -f docker-compose.dev.yml
MM_PORT ?= 8065

## Start Mattermost and PostgreSQL containers
.PHONY: docker-start
docker-start:
	@echo "Starting Mattermost Enterprise Edition..."
	@mkdir -p docker/mattermost/{config,data,logs,plugins,client-plugins}
	@mkdir -p docker/postgres-data
	@$(DOCKER_COMPOSE) up -d

## Stop containers (preserves data)
.PHONY: docker-stop
docker-stop:
	@$(DOCKER_COMPOSE) stop

## Stop and remove containers
.PHONY: docker-down
docker-down:
	@$(DOCKER_COMPOSE) down

## Remove containers and all data
.PHONY: docker-clean
docker-clean:
	@$(DOCKER_COMPOSE) down -v
	@rm -rf docker/postgres-data docker/mattermost
	@echo "Containers and data removed"

## Kill orphaned Docker containers on the MM port (useful after deleting a worktree)
.PHONY: docker-kill-orphans
docker-kill-orphans:
	@project=$$(docker ps --filter "publish=$(MM_PORT)" \
		--format '{{.Label "com.docker.compose.project"}}' | head -1); \
	if [ -z "$$project" ]; then \
		echo "No containers found on port $(MM_PORT)"; \
	else \
		echo "Stopping compose project: $$project"; \
		docker compose -p $$project down -v; \
		echo "Project $$project removed"; \
	fi

## View Mattermost container logs
.PHONY: docker-logs
docker-logs: docker-check
	@$(DOCKER_COMPOSE) logs -f mattermost

## First-time setup: start containers and create admin user
.PHONY: docker-setup
docker-setup: docker-start
	@echo "Waiting for Mattermost to be ready..."
	@until curl -sf http://localhost:$(MM_PORT)/api/v4/system/ping >/dev/null 2>&1; do \
		sleep 2; \
		echo "Waiting..."; \
	done
	@echo "Creating admin user..."
	@$(DOCKER_COMPOSE) exec -T mattermost mmctl --local user create \
		--email admin@example.com \
		--username admin \
		--password 'password' \
		--system-admin 2>/dev/null || echo "Admin user already exists"
	@echo "Creating default team..."
	@$(DOCKER_COMPOSE) exec -T mattermost mmctl --local team create \
		--name test \
		--display-name "Test" 2>/dev/null || echo "Team 'Test' already exists"
	@echo "Adding admin to Test team..."
	@$(DOCKER_COMPOSE) exec -T mattermost mmctl --local team users add test admin 2>/dev/null || echo "Admin already in Test team"
	@echo ""
	@echo "=========================================="
	@echo "Mattermost ready at http://localhost:$(MM_PORT)"
	@echo "Login: admin / password"
	@echo "Team: Test"
	@echo "=========================================="

## Check if Mattermost container is running
.PHONY: docker-check
docker-check:
	@if ! $(DOCKER_COMPOSE) ps --status running 2>/dev/null | grep -q mattermost; then \
		echo "Error: Mattermost container is not running."; \
		echo "Run 'make docker-setup' first to start the environment."; \
		exit 1; \
	fi

## Build and deploy plugin to Docker Mattermost
.PHONY: docker-deploy
docker-deploy: docker-check dist
	@echo "Deploying plugin to Docker Mattermost..."
	@$(DOCKER_COMPOSE) cp dist/$(BUNDLE_NAME) mattermost:/tmp/$(BUNDLE_NAME)
	@$(DOCKER_COMPOSE) exec -T mattermost mmctl --local plugin add /tmp/$(BUNDLE_NAME) --force
	@$(DOCKER_COMPOSE) exec -T mattermost mmctl --local plugin enable $(PLUGIN_ID)
	@echo "Plugin $(PLUGIN_ID) deployed and enabled"

## Disable and re-enable plugin in Docker
.PHONY: docker-reset
docker-reset: docker-check
	@$(DOCKER_COMPOSE) exec -T mattermost mmctl --local plugin disable $(PLUGIN_ID)
	@$(DOCKER_COMPOSE) exec -T mattermost mmctl --local plugin enable $(PLUGIN_ID)
	@echo "Plugin $(PLUGIN_ID) reset"

## Disable plugin in Docker
.PHONY: docker-disable
docker-disable: docker-check
	@$(DOCKER_COMPOSE) exec -T mattermost mmctl --local plugin disable $(PLUGIN_ID)

## Enable plugin in Docker
.PHONY: docker-enable
docker-enable: docker-check
	@$(DOCKER_COMPOSE) exec -T mattermost mmctl --local plugin enable $(PLUGIN_ID)

## List installed plugins in Docker
.PHONY: docker-plugin-list
docker-plugin-list: docker-check
	@$(DOCKER_COMPOSE) exec -T mattermost mmctl --local plugin list

## Convenience alias: deploy plugin to Docker
.PHONY: deploy
deploy: docker-deploy

## Build and deploy to a Mattermost server running at MM_LOCAL_SITEURL
## (default http://localhost:8065) via the bundled pluginctl tool. Unlike
## `make deploy` (which targets the docker-compose stack), this hits a
## locally-running server directly - useful when you develop against your own
## Mattermost rather than the bundled Docker environment.
##
## pluginctl authenticates via one of (it validates and picks natively):
##   - Local mode (auto-detected default socket, or MM_LOCALSOCKETPATH), or
##   - MM_ADMIN_TOKEN                          (an admin personal access token), or
##   - MM_ADMIN_USERNAME + MM_ADMIN_PASSWORD   (admin login)
## Override the target server with `make deploy-local MM_LOCAL_SITEURL=...`.
MM_LOCAL_SITEURL ?= http://localhost:8065
.PHONY: deploy-local
deploy-local: dist
	@MM_SERVICESETTINGS_SITEURL=$(MM_LOCAL_SITEURL) ./build/bin/pluginctl deploy $(PLUGIN_ID) dist/$(BUNDLE_NAME) || { \
		status=$$?; \
		echo "deploy-local failed. pluginctl authenticates via local mode (default socket or MM_LOCALSOCKETPATH), MM_ADMIN_TOKEN, or MM_ADMIN_USERNAME + MM_ADMIN_PASSWORD."; \
		echo "Or, with an already-authenticated mmctl, install directly:"; \
		echo "  mmctl plugin add dist/$(BUNDLE_NAME) --force && mmctl plugin enable $(PLUGIN_ID)"; \
		exit $$status; \
	}

# ====================================================================================
# SBOM & Vulnerability Scanning
# ====================================================================================

## Install SBOM generation tools
.PHONY: install-sbom-tools
install-sbom-tools: require-network
	@echo "Installing SBOM generation tools..."
	$(GO) install github.com/CycloneDX/cyclonedx-gomod/cmd/cyclonedx-gomod@latest

## Install Grype vulnerability scanner
.PHONY: install-grype
install-grype: require-network
	@if [ ! -x "$(GOBIN)/grype" ]; then \
		echo "Installing Grype via go install (cross-platform, no anchore install.sh)..."; \
		mkdir -p $(GOBIN); \
		GOBIN=$(GOBIN) $(GO) install github.com/anchore/grype/cmd/grype@latest; \
	else \
		echo "Grype already installed"; \
	fi

## Generate Software Bill of Materials (SBOM) in CycloneDX JSON format
.PHONY: sbom
sbom: install-sbom-tools
	@mkdir -p dist/sbom
ifneq ($(HAS_SERVER),)
	@echo "Generating Go SBOM..."
	$(GOBIN)/cyclonedx-gomod mod -json -output dist/sbom/server-sbom.json
endif
ifneq ($(HAS_WEBAPP),)
	@echo "Generating Node.js SBOM..."
	# --omit dev: the plugin bundle ships only production deps; the dev/build
	# toolchain (eslint, webpack, babel) is never in webapp/dist, so its CVEs
	# must not gate releases. Grype still blocks HIGH/CRITICAL in shipped deps.
	cd webapp && npx @cyclonedx/cyclonedx-npm --omit dev --ignore-npm-errors --output-file ../dist/sbom/webapp-sbom.json
endif
	@echo "SBOMs generated in dist/sbom/"
	@ls -la dist/sbom/

## Scan SBOMs for vulnerabilities using Grype (fails on high or critical)
.PHONY: sbom-scan
sbom-scan: install-grype
	@if [ ! -d dist/sbom ]; then \
		echo "No SBOMs found. Run 'make sbom' first."; \
		exit 1; \
	fi
ifneq ($(HAS_SERVER),)
	@echo "Scanning Go dependencies for vulnerabilities..."
	$(GOBIN)/grype sbom:dist/sbom/server-sbom.json --output table --fail-on high
endif
ifneq ($(HAS_WEBAPP),)
	@echo "Scanning Node.js dependencies for vulnerabilities..."
	$(GOBIN)/grype sbom:dist/sbom/webapp-sbom.json --output table --fail-on high
endif

## Generate SBOMs and scan for vulnerabilities
.PHONY: sbom-audit
sbom-audit: sbom sbom-scan

# ====================================================================================
# CodeQL Security Analysis
# ====================================================================================

CODEQL_VERSION ?= 2.20.1
CODEQL_DIR := $(PWD)/build/codeql
CODEQL := $(CODEQL_DIR)/codeql/codeql
CODEQL_DB_DIR := $(PWD)/build/codeql-db

## Install CodeQL CLI
.PHONY: install-codeql
install-codeql: require-network
	@if [ ! -f "$(CODEQL)" ]; then \
		echo "Installing CodeQL CLI v$(CODEQL_VERSION)..."; \
		mkdir -p $(CODEQL_DIR); \
		if [ "$$(uname)" = "Darwin" ]; then \
			CODEQL_PLATFORM="osx64"; \
		else \
			CODEQL_PLATFORM="linux64"; \
		fi; \
		curl -sSL "https://github.com/github/codeql-action/releases/download/codeql-bundle-v$(CODEQL_VERSION)/codeql-bundle-$$CODEQL_PLATFORM.tar.gz" | tar -xz -C $(CODEQL_DIR); \
		echo "CodeQL CLI installed"; \
	else \
		echo "CodeQL CLI already installed"; \
	fi

## Run CodeQL analysis on Go code
.PHONY: codeql-go
codeql-go: install-codeql
ifneq ($(HAS_SERVER),)
	@echo "Running CodeQL analysis on Go code..."
	@rm -rf $(CODEQL_DB_DIR)/go
	@mkdir -p $(CODEQL_DB_DIR)/go
	@mkdir -p dist
	$(CODEQL) database create $(CODEQL_DB_DIR)/go --language=go --source-root=server --overwrite
	$(CODEQL) database analyze $(CODEQL_DB_DIR)/go --format=sarif-latest --output=dist/codeql-go.sarif -- codeql/go-queries
	@echo "Go CodeQL results: dist/codeql-go.sarif"
endif

## Run CodeQL analysis on JavaScript/TypeScript code
.PHONY: codeql-js
codeql-js: install-codeql webapp/node_modules
ifneq ($(HAS_WEBAPP),)
	@echo "Running CodeQL analysis on JavaScript/TypeScript code..."
	@rm -rf $(CODEQL_DB_DIR)/js
	@mkdir -p $(CODEQL_DB_DIR)/js
	@mkdir -p dist
	$(CODEQL) database create $(CODEQL_DB_DIR)/js --language=javascript --source-root=webapp --overwrite
	$(CODEQL) database analyze $(CODEQL_DB_DIR)/js --format=sarif-latest --output=dist/codeql-js.sarif -- codeql/javascript-queries
	@echo "JavaScript/TypeScript CodeQL results: dist/codeql-js.sarif"
endif

## Run CodeQL analysis on all code
.PHONY: codeql-analyze
codeql-analyze: codeql-go codeql-js
	@echo "CodeQL analysis complete. Results in dist/codeql-*.sarif"

## Check CodeQL SARIF reports for critical/high severity issues (level=error in SARIF)
.PHONY: security-gate
security-gate:
	@echo "Checking security scan results for critical/high issues..."
	@failed=0; \
	for sarif in dist/codeql-*.sarif; do \
		[ -f "$$sarif" ] || continue; \
		count=$$(python3 -c "import json,sys;data=json.load(open(sys.argv[1]));print(sum(1 for run in data.get('runs',[]) for result in run.get('results',[]) if result.get('level')=='error'))" "$$sarif"); \
		if [ "$$count" -gt 0 ]; then \
			echo "ERROR: $$sarif contains $$count critical/high severity issue(s)."; \
			failed=1; \
		else \
			echo "OK: $$sarif has no critical/high severity issues."; \
		fi; \
	done; \
	if [ "$$failed" -eq 1 ]; then \
		echo ""; \
		echo "Security gate FAILED: Critical or high severity issues found."; \
		echo "Review the SARIF files in dist/ for details."; \
		exit 1; \
	fi
	@echo "Security gate passed."

# ====================================================================================
# Virus Scanning
# ====================================================================================

## Install ClamAV antivirus scanner
.PHONY: install-clamav
install-clamav: require-network
	@if ! command -v clamscan >/dev/null 2>&1; then \
		echo "Installing ClamAV..."; \
		if [ "$$(uname)" = "Darwin" ]; then \
			brew install clamav; \
		else \
			sudo apt-get update && sudo apt-get install -y clamav; \
		fi; \
	else \
		echo "ClamAV already installed"; \
	fi
	@echo "Updating virus definitions..."
	@if [ "$$(uname)" = "Darwin" ]; then \
		if [ ! -f /opt/homebrew/etc/clamav/freshclam.conf ] && [ -f /opt/homebrew/etc/clamav/freshclam.conf.sample ]; then \
			cp /opt/homebrew/etc/clamav/freshclam.conf.sample /opt/homebrew/etc/clamav/freshclam.conf; \
			sed -i '' 's/^Example/#Example/' /opt/homebrew/etc/clamav/freshclam.conf; \
		fi; \
	else \
		sudo systemctl stop clamav-freshclam 2>/dev/null || true; \
	fi
	@sudo freshclam || freshclam

## Scan dist/ for viruses using ClamAV (fails if any detected)
.PHONY: virus-scan
virus-scan: install-clamav
	@if [ ! -d dist ]; then \
		echo "No dist/ directory found. Run 'make dist' first."; \
		exit 1; \
	fi
	@echo "Scanning release artifacts for viruses..."
	clamscan --recursive --infected --alert-broken dist/
	@echo "Virus scan passed."

# ====================================================================================
# Help
# ====================================================================================

help:
	@cat Makefile build/*.mk | grep -v '\.PHONY' |  grep -v '\help:' | grep -B1 -E '^[a-zA-Z0-9_.-]+:.*' | sed -e "s/:.*//" | sed -e "s/^## //" |  grep -v '\-\-' | sed '1!G;h;$$!d' | awk 'NR%2{printf "\033[36m%-30s\033[0m",$$0;next;}1' | sort
