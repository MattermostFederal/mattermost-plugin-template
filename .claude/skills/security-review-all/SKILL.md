---
name: security-review-all
description: Whole-product offensive security audit of this plugin. Hunts for exploitable holes across the server hooks, slash commands, HTTP routes, the webapp, and the build and release pipeline, proves each one against the code, and reports them ranked by impact with a fix. Use for periodic audits, before a release, or when asked to find security holes. Read-only.
user-invocable: true
---

# Security Review

You are a god tier security researcher. Find security holes in this product so we
can fix them.

Think like an attacker with a Mattermost account, a malicious plugin installed
beside this one, a compromised dependency, or a crafted message pasted into chat. The
goal is real, exploitable findings with a concrete path from attacker input to
impact, not a checklist of best practices.

This skill is read-only. Do not edit, commit or push. Do not run anything that
reaches the network or mutates the working tree.

## Usage

```
/security-review-all                  # The whole product
/security-review-all <path>           # Focus on one file or directory
/security-review-all --diff           # Only what changed on this branch since the trunk
```

## Step 1: Map the attack surface

Read `CLAUDE.md` first. Its conventions and the invariants it documents are the
product's own statement of what must hold; every one is a hypothesis to break.
This starts as a minimal template, so enumerate what the plugin actually has
today rather than trusting this table: grep for `ServeHTTP`, `MessageWillBePosted`,
`OnPluginClusterEvent`, `KVSet`, `registerPostTypeComponent`,
`dangerouslySetInnerHTML` and friends, and add a row for every entry point you
find. Then note who controls each one:

| Surface | Attacker | Where |
|---|---|---|
| Slash command arguments | Any user in any channel | `server/command.go` |
| Plugin settings | System admin, or whoever can write `config.json` | `server/configuration.go`, `plugin.json` `settings_schema` |
| Plugin hooks (activation, config change, any post or user hook added later) | Depends on the hook; post hooks are any user who can post | `server/plugin.go`, `server/*.go` |
| HTTP routes, if `ServeHTTP` is added | Any logged in user, or anyone who can craft a URL | `server/*.go` |
| Inter-plugin requests (`Mattermost-Plugin-ID`), if any | Any other installed plugin | `server/*.go` |
| KV store, if used | The reader, other readers, cluster peers | `server/*.go` |
| Webapp rendering | Authors of any post the reader views, and API data | `webapp/src/**` |
| Build and release | Upstream dependencies and Actions | `build/`, `Makefile`, `.github/workflows/`, `go.mod`, `webapp/package.json`, `.grype.yaml` |

## Step 2: Hunt

Run the lenses below as parallel read-only `Explore` or `general-purpose`
agents, one per lens, each told the surface table above, told to cite
`file:line`, and told to return candidates with an attack path rather than
general advice. With a path argument, keep only the lenses that touch it. Skip
a lens whose surface does not exist in the code yet, and say so in the report.

1. **Authorization and identity.** Every HTTP route checks
   `Mattermost-User-ID` (set by the server, stripped from external requests)
   and the permission the operation needs, not merely that a user exists. Can a
   user act on a channel, team, post or file they cannot see? Does a slash
   command check the caller's permission in the channel it acts on? Is
   `Mattermost-Plugin-ID` trusted only for what another plugin may do?
2. **Injection into rendered output.** XSS in webapp components: every
   `dangerouslySetInnerHTML`, `innerHTML`, `href` built from data
   (`javascript:` URLs), and anything that echoes author or API text. Server
   side, `html/template` versus `text/template`. Markdown injection in
   ephemeral replies or bot posts: can input make the plugin emit a link, image
   or mention the user did not write?
3. **Denial of service.** Inputs that panic in a hook (a panic in a plugin hook
   can take the plugin down), unbounded loops or allocations driven by message
   or argument size, and slow work on the posting path.
4. **Parser and input abuse.** Every place user input is split, parsed or
   decoded: slash command `fields`, JSON bodies without size limits, numbers,
   paths.
5. **SSRF, files and paths.** Any server-side fetch, filestore read, or path
   built from input, including URLs taken from settings.
6. **Secrets and configuration.** Secrets in settings shown to non-admins,
   logged, or sent to the webapp. Settings that are trusted without validation
   in `OnConfigurationChange`.
7. **Cluster and cache.** `OnPluginClusterEvent` payloads trusted without
   checks, KV keys built from input that let one user overwrite another's data,
   and caches that serve one user's data to another.
8. **Supply chain and release.** Actions not pinned to a full SHA, workflow
   `pull_request_target` or script injection from PR titles, secrets exposed to
   forks, copyleft or vulnerable dependencies, a webapp `postinstall` that
   fetches (it also breaks the enclave build), and anything `.grype.yaml`
   suppresses without a real reason.

Also check error paths: does any log line or user-facing error leak a path, a
stack, a token or another user's data?

## Step 3: Prove it

A finding without proof is a guess. For each candidate:

- Trace the data flow from the attacker's input to the sink, reading the actual
  code at every hop. Drop it if a check anywhere on the path stops it.
- Name the attacker's required position (anonymous, any user, channel member,
  another plugin, admin, filesystem access). Admin-only and filesystem-only
  issues are real but rank lower.
- Where it is cheap and safe, write a failing test in the scratchpad or run the
  existing test that exercises the vulnerable path with a crafted input
  (`go test ./server/... -run 'TestName'`, or `cd webapp && npm run test:pw -- <file>` / `npm run test:pw-ct -- <file>`) to confirm. Never leave the working tree changed.
- Mark each finding CONFIRMED (proven or traced end to end) or PLAUSIBLE
  (traced, but depends on something you could not verify).

Be adversarial with yourself. Discard theoretical issues, defense-in-depth
nits with no path to impact, and anything the product's invariants already
explain as deliberate.

## Step 4: Report

Rank by severity, then by confidence. For each finding give:

- **Title** and severity (Critical, High, Medium, Low)
- **Location:** `file:line`
- **Attacker:** who can trigger it
- **Attack:** the exact input and the steps
- **Impact:** what they get
- **Fix:** the minimal change, and the regression test that should hold it

End with a short list of the surfaces you reviewed and found clean, so the next
audit knows what was covered, and anything you could not assess. Offer to fix
the confirmed findings; do not fix them unasked.
