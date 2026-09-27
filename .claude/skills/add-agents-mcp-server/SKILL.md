---
name: add-agents-mcp-server
description: Add an MCP (Model Context Protocol) server to this plugin so the Mattermost Agents plugin can call its tools. Use when exposing plugin operations to Agents' LLM agents, or when wiring up the `pluginmcp` helper from mattermost-plugin-agents.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
---

# Add Agents MCP Server

Add a cross-plugin MCP (Model Context Protocol) server to this plugin so the
[Mattermost Agents plugin](https://github.com/mattermost/mattermost-plugin-agents)
can discover and call its tools. Uses the
`github.com/mattermost/mattermost-plugin-agents/v2/external/pluginmcp` helper, which
handles tool-name namespacing, inter-plugin auth, user-ID propagation, and async
registration retries.

MCP is **another transport onto operations this plugin already has**, alongside
the slash command (and any HTTP API added later). The transport decides who may
ask, never what the answer is built from: every tool calls the same function
the slash command does.

## Read first

- Root [`CLAUDE.md`](../../CLAUDE.md): the conventions, the no-comment rule,
  the dependency licensing rules, the enclave constraints, and the worktree
  workflow.
- `server/plugin.go`: the `Plugin` struct and `OnActivate`.
- `server/command.go`: the existing operations a tool should reuse.
- `server/configuration.go`: the settings pattern, if this ships behind a switch.

## Prerequisites

Confirm these still hold before starting:

- **`min_server_version`** is `11.8.0` in `plugin.json`, above the `11.3` the
  helper's `Plugin.PluginHTTPStream` needs. No bump required.
- **Go** is `1.26.7` in the single root `go.mod`. There is no `server/go.mod`;
  the module is `github.com/MattermostFederal/mattermost-plugin-template`
  and everything under `server/` is `package main`. If this plugin was created
  from the template and renamed, use its own module path and id throughout.
- **The plugin id** is `com.mattermost.plugin-template`, reverse-DNS and free
  of `__`. Double-underscore is the namespace separator on the Agents side.
- **There is no `ServeHTTP` yet.** Phase 6 adds one.
- **There is no `pluginapi` client.** Tool handlers call `p.API` directly.

No `plugin.json` changes are required for MCP itself. A switch (Phase 7) is a
separate decision.

## Blocking gate: dependency licensing

The bundle ships to customers, so **verify the license of
`mattermost-plugin-agents` and `modelcontextprotocol/go-sdk` before adding
either**, including anything they pull in transitively. Root `CLAUDE.md` forbids
GPL/AGPL/SSPL outright and puts LGPL/MPL/EPL off limits by default.

Mattermost's first-party plugins are not uniformly licensed, and some carry a
source-available license rather than Apache 2.0. Do not assume. Check the
upstream `LICENSE` file, and after `go mod tidy` run `make sbom` and read the
licenses it reports for every new module.

If the license is copyleft, source-available, unclear or unstated: **stop and
ask.** Present alternatives and tradeoffs rather than adding it. That is the
maintainer's call.

The dependencies must also vendor cleanly (`CLAUDE.md`, enclave builds): after
adding them, `make enclave-stage` followed by `make OFFLINE=1 dist` must pass.

## Instructions

### Phase 0: Prepare a worktree

This repo uses the bare-repo plus worktree layout. **Never work in `main/`.**

1. From the project root, confirm the tree is clean and refresh the trunk.
2. `git --git-dir=.bare worktree add agents-mcp main -b feat/agents-mcp`
3. Add the new worktree to the `folders` array in `project.code-workspace`.
4. Work from `agents-mcp/` for everything below.

### Phase 1: Add dependencies

Edit the root `go.mod`:

```
require (
    github.com/mattermost/mattermost-plugin-agents/v2 v2.7.0
    github.com/modelcontextprotocol/go-sdk v1.7.0
)
```

Then `go mod tidy` from the repo root, and the license check above.

**The module path carries `/v2`.** The unversioned path still resolves on the
module proxy, but its latest tag (`v1.14.2`) declares
`module github.com/mattermost/mattermost-plugin-ai` and ships no `external/`
directory at all, so it cannot satisfy this import.

Pin the go-sdk to whatever the agents release requires rather than its own
latest tag, so the two halves of the MCP stack agree; `v2.7.0` requires
`v1.7.0`. Check a newer agents release's `go.mod` before bumping either.

If the release you want does not export `external/pluginmcp/`, ask the
maintainer before pinning a pseudo-version or adding a `replace` against a local
checkout. A `replace` must not reach a release build.

### Phase 2: Add MCP server fields to the Plugin struct

In `server/plugin.go`, beside `configurationLock`:

```go
mcpServerLock sync.RWMutex
mcpServer     *pluginmcp.Server
```

The lock guards initialization in `OnActivate` against concurrent reads from
`ServeHTTP`, which the server may call on another goroutine.

### Phase 3: Create `server/mcp.go`

This file owns the MCP server lifecycle. Indirect `pluginmcp.NewServer`,
`Register` and `Unregister` through package-level `var`s so tests can substitute
them without a live Agents plugin.

Follow this repo's error handling: `errors.Wrap` from `github.com/pkg/errors`,
and `p.API.LogWarn`/`LogError` with key-value pairs. **Write no prose
comments** (root `CLAUDE.md`).

```go
package main

import (
    "net/http"
    "strings"

    "github.com/mattermost/mattermost-plugin-agents/v2/external/pluginmcp"
    "github.com/pkg/errors"
)

const mcpPath = "/mcp"

var (
    mcpNewServer = pluginmcp.NewServer

    mcpRegister = func(server *pluginmcp.Server) error {
        return server.Register()
    }

    mcpUnregister = func(server *pluginmcp.Server) error {
        return server.Unregister()
    }
)

func (p *Plugin) ensureMCPServer() error {
    p.mcpServerLock.Lock()
    defer p.mcpServerLock.Unlock()

    if p.mcpServer != nil {
        return nil
    }

    if manifest.Id == "" || manifest.Version == "" || strings.TrimSpace(manifest.Name) == "" {
        return errors.New("the manifest is missing an id, a version or a name")
    }

    server := mcpNewServer(p.API, pluginmcp.Config{
        PluginID:       manifest.Id,
        Name:           manifest.Name + " MCP",
        Path:           mcpPath,
        ExposeExternal: true,
        Version:        manifest.Version,
    })

    p.registerMCPTools(server)
    p.mcpServer = server
    return nil
}

func (p *Plugin) registerMCPServerBestEffort() {
    server := p.currentMCPServer()
    if server == nil {
        return
    }

    if err := mcpRegister(server); err != nil {
        p.API.LogWarn("MCP registration unavailable; continuing activation", "err", err.Error())
    }
}

func (p *Plugin) unregisterMCPServerBestEffort() {
    server := p.currentMCPServer()
    if server == nil {
        return
    }

    if err := mcpUnregister(server); err != nil {
        p.API.LogWarn("MCP unregister failed; continuing shutdown", "err", err.Error())
    }
}

func (p *Plugin) serveMCPIfMatch(w http.ResponseWriter, r *http.Request) bool {
    if r.URL.Path != mcpPath && !strings.HasPrefix(r.URL.Path, mcpPath+"/") {
        return false
    }

    server := p.currentMCPServer()
    if server == nil {
        http.Error(w, "Not ready.", http.StatusServiceUnavailable)
        return true
    }

    server.ServeHTTP(w, r)
    return true
}

func (p *Plugin) currentMCPServer() *pluginmcp.Server {
    p.mcpServerLock.RLock()
    defer p.mcpServerLock.RUnlock()

    return p.mcpServer
}
```

`manifest` is the package-level value `make` generates into `server/manifest.go`
from `plugin.json`. Read it inside functions only: it is populated by a
generated `init()`, after package-level `var` initializers run.

`Register()` returns immediately and retries asynchronously (1s, 2s, 4s, 8s, up
to 15 attempts) until the Agents plugin acknowledges, so activation is never
blocked on a plugin that is not up yet.

### Phase 4: Create `server/mcp_tools.go`

**Reuse the operations, do not reimplement them.** If a tool does what a slash
subcommand does, first extract the pure part of that handler in
`server/command.go` into a function both the command and the tool call, rather
than growing a second copy that can drift. For the template's `hello`
subcommand that is the reply text:

```go
func helloMessage() string {
    return "Hello from the Plugin Template!"
}
```

Tool names are prefixed automatically. Here `com.mattermost.plugin-template`
sanitizes to `com_mattermost_plugin-template__`, so the LLM sees
`com_mattermost_plugin-template__hello` while you write `hello`.

```go
package main

import (
    "context"

    "github.com/mattermost/mattermost-plugin-agents/v2/external/pluginmcp"
    "github.com/modelcontextprotocol/go-sdk/mcp"
)

type HelloArgs struct{}

type HelloOutput struct {
    Message string `json:"message" jsonschema:"The greeting the plugin returns"`
}

func (p *Plugin) registerMCPTools(server *pluginmcp.Server) {
    pluginmcp.AddTool(server, &mcp.Tool{
        Name:        "hello",
        Description: "Return the plugin's greeting, the same text as the hello slash command.",
    }, p.helloTool)
}

func (p *Plugin) helloTool(_ context.Context, _ *mcp.CallToolRequest, _ HelloArgs) (*mcp.CallToolResult, HelloOutput, error) {
    return nil, HelloOutput{Message: helloMessage()}, nil
}
```

Replace `hello` with the plugin's real operations once it has them.

Handler signature is the go-sdk's `mcp.ToolHandlerFor[In, Out]`:

```
func(context.Context, *mcp.CallToolRequest, In) (*mcp.CallToolResult, Out, error)
```

Return `(nil, out, nil)` and the helper packs `out` into a `CallToolResult`.
Return a non-nil `*mcp.CallToolResult` to control the response fully
(multi-content replies, `IsError`).

Aim for **about 10 tools maximum** with union-typed args rather than many
narrow ones: every tool costs schema tokens in every LLM request.

### Phase 5: Wire into `OnActivate` and `OnDeactivate`

In `server/plugin.go`, after `RegisterCommand` succeeds, since a tool handler
may depend on anything activation sets up:

```go
func (p *Plugin) OnActivate() error {
    if err := p.API.RegisterCommand(getCommand()); err != nil {
        return errors.Wrap(err, "failed to register the slash command")
    }

    if err := p.ensureMCPServer(); err != nil {
        return errors.Wrap(err, "failed to initialize the MCP server")
    }
    p.registerMCPServerBestEffort()

    return nil
}

func (p *Plugin) OnDeactivate() error {
    p.unregisterMCPServerBestEffort()
    return nil
}
```

There is no `OnDeactivate` in the template today. Adding one for
`unregisterMCPServerBestEffort` is fine; keep it unconditional so a failure
elsewhere does not leave a stale registration on the Agents side.

`Register()` errors are logged and swallowed. A down Agents plugin must never
fail this plugin's activation.

### Phase 6: Add `ServeHTTP` and route MCP requests

The template has no HTTP handler. Add `server/http.go`:

```go
package main

import (
    "net/http"

    "github.com/mattermost/mattermost/server/public/plugin"
)

func (p *Plugin) ServeHTTP(_ *plugin.Context, w http.ResponseWriter, r *http.Request) {
    if p.serveMCPIfMatch(w, r) {
        return
    }

    http.NotFound(w, r)
}
```

If the plugin already has a `ServeHTTP`, add the match to it instead, **before
any method restriction and before any session check**. MCP is a POST transport,
so a match placed below a GET-only refusal is answered with 405. A plugin
request carries no user session, so a match placed below a
`Mattermost-User-ID` check is refused, or redirected to login, which an MCP
client reads as a malformed response rather than an auth failure.

Do **not** add an auth gate of your own around `serveMCPIfMatch`.
`pluginmcp.Server.ServeHTTP` already rejects requests without
`Mattermost-Plugin-ID: mattermost-ai`, a header Mattermost strips from external
requests, so only inter-plugin RPC can set it.

### Phase 7: Decide on an admin switch

Ask the maintainer whether MCP ships behind an `EnableMCP` setting. It is not
automatic.

If it gets one: a field on `configuration` in `server/configuration.go` that is
**false at zero**, a matching entry in `plugin.json`'s
`settings_schema.settings` with `display_name` and `help_text`, and a read of
`p.getConfiguration()` at the point of use rather than a value captured at
activation. Then update `README.md`.

A switch read at registration time will not retract a registration the Agents
plugin already holds until this plugin re-activates. Say so in the setting's
`help_text`.

Do not hand-edit `plugin.json`'s `version`; release-please owns it.

### Phase 8: Record the invariants

Nothing in this feature may be explained by a code comment. Add what a later
change would otherwise break to root `CLAUDE.md`:

- **The user-scoping rule.** Agents propagates a user id, and
  `pluginmcp.GetUserID(ctx)` is the only trustworthy way to read it. A tool that
  acts for a user must go through that function and must refuse when it returns
  `""`. Never read `Mattermost-User-ID` from the headers directly in an MCP
  tool, and check that user's permissions on anything the tool touches.
- **The routing order.** The `/mcp` match sits above any method check and any
  session check in `ServeHTTP`, and each is a separate defect if moved.
- **The tool budget**, and what "about ten" is protecting.

Carry the rest in the code and in test names rather than in prose.

### Phase 9: Tests

Add `server/mcp_test.go` and `server/mcp_tools_test.go`, using
`plugintest.API` from `github.com/mattermost/mattermost/server/public/plugin/plugintest`
for `p.API`. Put the invariant in the test name
(`TestRoundToNormalizesNegativeZero` style), not in a comment above it. Cover at
least:

- `TestMCPRouteAcceptsPost`: a POST to `/mcp` is not answered with 405 or 404.
- `TestMCPRefusesWhenTheServerIsNotReady`.
- `TestMCPHelloMatchesTheSlashCommand`: the tool's answer equals what the slash
  command replies for the same operation.
- `TestMCPToolsRefuseAnAbsentUserID` for any user-scoped tool.
- `TestActivationSucceedsWhenRegistrationFails`.
- A round-trip through `httptest.Server` with
  `Mattermost-Plugin-ID: mattermost-ai` set, using the go-sdk client for
  `ListTools` and `CallTool`.

Override `mcpNewServer` / `mcpRegister` / `mcpUnregister` rather than reaching
for a live Agents plugin. A test that wants "every tool" must read the registry
rather than list the names.

### Phase 10: Docs

Run the `add-help-docs` skill, or at minimum add the MCP tools and any switch to
`README.md`.

### Phase 11: Verify

1. `make check-style`
2. `make test`
3. `make sbom-audit` (fails on HIGH/CRITICAL CVEs in the new dependencies)
4. `make dist`
5. `make enclave-stage && make OFFLINE=1 dist`, to prove the new modules vendor
6. End to end: `make docker-setup` then `make deploy` (Mattermost on `:8065`,
   `admin`/`password`). Install the Agents plugin from a build with cross-plugin
   MCP support, open its system console **Tools** tab, and confirm the tools
   appear as `com_mattermost_plugin-template__<name>` with per-tool policy
   controls. Tail `make docker-logs` for `Connected to plugin MCP server
   com.mattermost.plugin-template`; its absence means `Register()` never
   succeeded.

Commit with a conventional subject, `feat:` for the feature. No Claude
attribution, no em dashes, US spelling.

## Configuration reference

```go
type Config struct {
    PluginID       string // required; must equal plugin.json "id"
    Name           string // human-readable; shown in admin UI
    Path           string // this plugin's MCP endpoint, "/mcp"
    ExposeExternal bool   // if true, tools may appear on Agents' external MCP aggregate
                          // (still subject to admin Enabled toggle and per-tool policy)
    Version        string // optional; defaults to "0.0.1"
}
```

## API reference

- `pluginmcp.NewServer(api, cfg) *Server`: `p.API` satisfies the `PluginAPI`
  interface.
- `pluginmcp.AddTool[In, Out](s, tool, handler)`: a free function, not a method,
  because Go disallows type parameters on methods.
- `(*Server).ServeHTTP(w, r)`: an `http.Handler`; route to it for requests under
  `cfg.Path`.
- `(*Server).Register() error`: starts async registration, returns immediately,
  retries in a goroutine.
- `(*Server).Unregister() error`: synchronously cancels pending retries and POSTs
  one unregister.
- `pluginmcp.GetUserID(ctx) string`: returns the user id stashed by `ServeHTTP`,
  or `""` if absent.

## Constraints and gotchas

- **Route above any method check and any session check.** MCP is POST, and a
  plugin request carries no session. See Phase 6.
- **`GetUserID` is the only user source.** It is trustworthy only inside a
  request that arrived through `pluginmcp.Server.ServeHTTP`; external callers
  cannot inject one. A tool that reads the header directly is a disclosure bug.
- **Tool-name sanitization.** `AddTool` prepends `{sanitizedPluginID}__`,
  replacing any character outside `[A-Za-z0-9_-]` with `_` to satisfy
  `^[a-zA-Z0-9_-]{1,128}$`. An already-prefixed name is not double-prefixed.
- **Do not double-gate auth.** A plugin-id check of your own around
  `serveMCPIfMatch` is redundant and will likely break the helper's.
- **Registration is one-shot per `OnActivate`.** If the Agents plugin restarts,
  admin-persisted entries come back but a never-saved registration returns only
  when this plugin re-activates. Permanent errors log `registration with Agents
  plugin failed permanently` and stop.
- **Tool budget.** Roughly 20 to 200 schema tokens per tool in every LLM
  request. Prefer union-typed args over many narrow tools.
- **`ExposeExternal` vs admin `Enabled`.** Each register POST sends
  `expose_external` from `Config`. Admins still control the server's `Enabled`
  state and per-tool policy in the Agents console, and those survive
  re-registration.
- **No webapp half.** MCP is server-only.

## Troubleshooting

- **Tool missing from the admin Tools tab.** Look for `Connected to plugin MCP
  server <pluginID>` in the Agents log. Absence means `Register()` was never
  called or kept failing; the retry loop logs `gave up after N attempts` on
  terminal failure and `failed permanently` on a non-retriable 4xx.
- **`GetUserID` returns `""`.** Either the request did not go through
  `pluginmcp.Server.ServeHTTP` (typical in unit tests, where you inject a context
  yourself), or `ServeHTTP` is not routing to it: check `mcpPath` matches
  `Config.Path`.
- **Registration keeps retrying.** Agents disabled, in a crash loop, or
  `cfg.PluginID` does not match `plugin.json`'s `id` (Agents returns a
  non-retriable 403).
- **405 on a local POST to `/mcp`.** The match is below a method check in
  `ServeHTTP`. See Phase 6.
- **A 401 or login redirect instead of an MCP response.** The match is below a
  session check in `ServeHTTP`.
- **403 during a local curl.** Expected. Mattermost strips
  `Mattermost-Plugin-ID` from external requests. Test through the Agents plugin
  or a unit test that sets the header.

## References

- Helper package: `mattermost-plugin-agents/v2/external/pluginmcp/` (`README.md`,
  `pluginmcp.go`, `server.go`, `tools.go`, `context.go`, `registration.go`).
- Reference implementation: `mattermost-plugin-demo` branch
  `IDEA-006-cross-plugin-mcp`, specifically `server/mcp.go`,
  `server/mcp_tools.go`, `server/activate_hooks.go`, `server/http_hooks.go` and
  `server/mcp_tools_test.go`. Its layout differs from this repo's: it has a
  separate `server/go.mod`, a `pluginapi` client, and split hook files. Take the
  shape, not the paths.
- MCP Go SDK: <https://github.com/modelcontextprotocol/go-sdk>.
