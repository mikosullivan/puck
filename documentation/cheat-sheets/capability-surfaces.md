# Cheat sheet: capability surfaces

~~~vibecode
{"vibecode": {
	"doc": "cheat_sheets_capability_surfaces",
	"role": "unified reference table for every capability that can appear on three surfaces at once: %engine.X (user-only host resource), %chain.X (cross-role chain-mediated capability), and bare %X (shortcut for the chain form). One row per capability, so a reader can go 'ok, for HTTP, what are all my access paths?' and see the whole trio in one place. Not a spec — canonical spec is on each individual doc; this page links to them. Includes status (V1, TBD, post-V1) and notes irregular naming (bare %fetch is short for %chain.puck; %fs skips %chain entirely).",
	"status": "cheat sheet — table plus short prose; not spec-authoritative for any of the entries",
	"audience": "developers writing Caspian who want a single place to answer 'what are all my surfaces for X?'; anyone confused by the three-way relationship between %engine, %chain, and bare %"
}}
~~~

Every host-provided resource in Caspian can appear on up to three surfaces. This page tabulates the whole set in one view. For any given capability, use the surface that matches your role and intent:

- **`%engine.X`** — user-only. The host installed the resource; only `user`-role code may read it. Reach for this to configure or hand across a role boundary.
- **`%chain.X`** — the cross-role form. Seeded from the engine slot at bootstrap; propagated down the chain; grantable / revocable per frame. Reach for this when working with grants, revokes, or ambient capability propagation.
- **Bare `%X`** — a short-form alias for the chain-mediated capability. Not every capability has one; only the ones common enough to earn the shortcut. Where a bare form exists, it and its `%chain.X` counterpart are the same thing.

## The trio table

Sorted alphabetically by capability. `—` means the surface doesn't exist for that entry.

| Capability | `%engine.X` (user-only) | `%chain.X` (cross-role) | Bare `%X` (shortcut) | Status |
|---|---|---|---|---|
| Command-line arguments | [`%engine.argv`](https://puck.uno/documentation/requirements/engine/argv) | [`%chain.argv`](https://puck.uno/documentation/requirements/chain/methods/argv) | — | V1 |
| Cryptographic primitives | `%engine.encryption` | [`%chain.encryption`](https://puck.uno/documentation/requirements/chain/methods/encryption) | — | TBD |
| Environment variables | `%engine.env` | [`%chain.env`](https://puck.uno/documentation/requirements/chain/methods/env) | — | TBD |
| Filesystem (dirjail) | `%engine.fs` | — | [`%fs`](https://puck.uno/documentation/requirements/global-methods/fs) | TBD (bare form skips `%chain`) |
| Forking | `%engine.forks` | [`%chain.forks`](https://puck.uno/documentation/requirements/chain/methods/forks) | — | TBD |
| HTTP client | [`%engine.http_client`](https://puck.uno/documentation/requirements/engine/http_client) | via [`%chain.net.http`](https://puck.uno/documentation/requirements/chain/methods/net) | — | V1 (engine); chain form V1 |
| Lua host info | [`%engine.lua`](https://puck.uno/documentation/requirements/engine/lua) | — | — | V1 (reference engine only) |
| Process manifest | [`%engine.manifest`](https://puck.uno/documentation/requirements/engine/manifest/) | — | — | V1 |
| Networking (broader) | `%engine.net` | [`%chain.net`](https://puck.uno/documentation/requirements/chain/methods/net) | — | TBD |
| Clock | `%engine.now` | [`%chain.now`](https://puck.uno/documentation/requirements/chain/methods/now) | `%now` | TBD (engine); V1 (chain + bare) |
| Platform info | [`%engine.platform`](https://puck.uno/documentation/requirements/engine/platform) | — | — | V1 |
| Object download | `%engine.puck` | [`%chain.puck`](https://puck.uno/documentation/requirements/chain/methods/puck) | `%fetch` | TBD (engine); V1 (chain + bare) |
| Randomness | `%engine.random` | [`%chain.random`](https://puck.uno/documentation/requirements/chain/methods/random) | `%random` | TBD (engine); V1 (chain + bare) |
| Dependency declaration | [`%engine.require`](https://puck.uno/documentation/requirements/engine/require) | — | — | V1 |
| Stderr | [`%engine.stderr`](https://puck.uno/documentation/requirements/engine/stdout-and-stderr) | [`%chain.stderr`](https://puck.uno/documentation/requirements/chain/methods/stdout-and-stderr) | `%stderr` | V1 |
| Stdin | [`%engine.stdin`](https://puck.uno/documentation/requirements/engine/stdin) | [`%chain.stdin`](https://puck.uno/documentation/requirements/chain/methods/stdin) | `%stdin` | V1 |
| Stdout | [`%engine.stdout`](https://puck.uno/documentation/requirements/engine/stdout-and-stderr) | [`%chain.stdout`](https://puck.uno/documentation/requirements/chain/methods/stdout-and-stderr) | `%stdout` | V1 |
| Temp directory | `%engine.tmp` | [`%chain.tmp`](https://puck.uno/documentation/requirements/chain/methods/tmp) | — | TBD |
| Utility paths | [`%engine.util_paths`](https://puck.uno/documentation/requirements/engine/util-paths) | — | — | V1 (user-only; user-mutable) |

Custom host resources: beyond the standard slots, a host may expose application-specific resources under `%engine['name']` — the bracket form is required for anything outside the catalog. See [engine § Custom resources via `%engine['name']`](https://puck.uno/documentation/requirements/engine/#custom-resources-via-enginename).

## Naming irregularities

Two rows where the naming doesn't line up cleanly:

- **`%fetch` is the bare form of `%chain.puck`.** Historical — Puck (the ecoverse) owned the "object-download-by-URL" concept, so the chain slot took the `puck` name; the bare form ended up as `%fetch` because that reads better at call sites. A rename (`puck` → `load` on the chain slot) is deferred until after the Puck / Mikobase extractions from this repo settle.
- **`%fs` skips `%chain`.** The filesystem entry point is `%engine.fs` (user-only) or `%fs` (bare) — no `%chain.fs` in between. Filesystem access is intentionally NOT chain-mediated; the dirjail machinery works differently. See [`%fs`](https://puck.uno/documentation/requirements/global-methods/fs) for the rationale.

## Standalone globals (not in the trio pattern)

Four `%X` names don't fit the engine → chain → bare pattern because they aren't host-provided resources — they're language-level surfaces:

| Global | Purpose | Canonical doc |
|---|---|---|
| `%call` | The current call object (caller's role owns it; carries `.return`, `.blocks`, etc.) | [call/](https://puck.uno/documentation/requirements/global-methods/call/) |
| `%chain` | The chain object itself — the top-level namespace all chain capabilities hang off | [chain/](https://puck.uno/documentation/requirements/chain/) |
| `%engine` | The engine object itself — the top-level namespace all engine slots hang off | [engine/](https://puck.uno/documentation/requirements/engine/) |
| `%self` | The current receiver inside a method body | [global-methods/#self](https://puck.uno/documentation/requirements/global-methods/#self) |
| `%module` | The Module frame the current code was declared in | [global-methods/module/](https://puck.uno/documentation/requirements/global-methods/module/) |

## Deciding which form to use

Rule of thumb, in order of preference for most code:

1. **Bare `%X` when it exists** — shortest, no ambiguity. `%stdout.puts 'hello'` beats `%chain.stdout.puts 'hello'`.
2. **`%chain.X` when you need to grant, revoke, or when the surface has no bare shortcut** — `%chain.encryption.grant(...) do ... end` isn't going to work through the (nonexistent) bare form.
3. **`%engine.X` when you specifically need the user-only view** — configuring the resource at startup, or handing it across a role boundary from `user` code.

The three forms all reach the same underlying capability where they exist; the choice is about ergonomics (bare), semantics (chain, for grant/propagate/revoke), and access role (engine, for user-only).

## Related

- [engine/](https://puck.uno/documentation/requirements/engine/) — canonical `%engine.X` catalog and per-slot pages.
- [chain/](https://puck.uno/documentation/requirements/chain/) — canonical `%chain` mechanism and per-capability pages.
- [global-methods/](https://puck.uno/documentation/requirements/global-methods/) — the ten `%X` globals from the language-level view.
