# Cheat sheet: core classes

~~~vibecode
{"vibecode": {
	"doc": "cheat_sheets_core_classes",
	"role": "one-view reference to Caspian's built-in class surface: user-facing `core:` classes (JSON primitives written as literals, plus the fetchable classes for HTTP, auth, protected memory, variable objects, clock, randomness) and engine-internal `core:` primitives (aggregate_hash, scope, vault — referenced by name in specs, not typically fetched). Each row links to the canonical spec (where one exists) and gives a one-line purpose. Not spec-authoritative — the linked docs are.",
	"status": "cheat sheet — some entries (core:now, core:random) don't have canonical spec pages yet; those cells link to the notes that establish them",
	"audience": "developers writing Caspian who want a single-page answer to 'what built-in classes exist?'; engine implementers cross-referencing which primitives are named vs anonymous"
}}
~~~

Every class Caspian ships. Two groups: user-facing `core:` classes (six JSON primitives written as literals; everything else reachable by fetch or by class identifier) and engine-internal `core:` primitives that back the runtime.

## `core:` — the reserved namespace

`core:` is the reserved namespace for engine primitives and canonical stdlib classes — anything user code shouldn't need to install because the runtime provides it. `%('core:X')` (shorthand for `%import('core:X')`) is intercepted by the engine and returns its baked-in implementation directly — no network, no cache miss.

## User-facing classes

Reachable by their `core:` class identifier — as the target of `%('core:X')` (each fetch returns a fresh object) or as the type value in a typed parameter, `%self.obj.classes.has?`, etc. Sorted alphabetically.

| Identifier | Purpose |
|---|---|
| [`core:array`](https://puck.uno/requirements/built-in-classes/primitives/array/) | Ordered list of values. Source form: `[1, 2, 3]`. Iteration, mutation, sampling, sorting, subscript access. |
| [`core:auth/api`](https://puck.uno/requirements/protected/auth/api) | Authenticated-API client factory. `.request(url)` returns an HTTP request pre-populated with the configured auth headers; template placeholders are validated (not sanitized) at send time. |
| [`core:boolean`](https://puck.uno/requirements/built-in-classes/primitives/boolean) | The two boolean values. Source form: `true` / `false`. Falsy values in Caspian are strictly `false` and `null` — everything else is truthy. |
| [`core:hash`](https://puck.uno/requirements/built-in-classes/primitives/hash/) | Ordered key-value mapping with string keys. Source form: `{a: 1, b: 2}`. Per-field freezing (`.freeze_field`), tombstone tracking (`.note_deleted`). |
| [`core:http/request`](https://puck.uno/requirements/http/request) | HTTP request class — built-in fields (host, content_type, user_agent), cross-source uniqueness rules, non-negotiable HTTP rules (no CR/LF/NUL byte injection escape hatch, tchar header keys per RFC 7230). |
| `core:net` | Networking primitives — HTTP client transport, sockets, UDS. Reached from [`core:http/request`](https://puck.uno/requirements/http/request) at send time. Canonical spec TBD. |
| `core:now` | Clock — returns the current timestamp source. Canonical spec TBD. |
| [`core:null`](https://puck.uno/requirements/built-in-classes/primitives/null) | The single null value. Source form: `null`. Falsy. Distinct from `false`. Not a placeholder for "any absent value" — Caspian raises rather than silently returning null when a lookup misses. |
| [`core:number`](https://puck.uno/requirements/built-in-classes/primitives/number/) | Numeric values — integers and floats share one class. Source form: `42`, `3.14`, `0xFF`, `2.5e-3`. Source-form annotations (base, scientific) round-trip through CaspJ but drop in CaspM. |
| [`core:protected/hash`](https://puck.uno/requirements/protected/hash/) | Protected-hash class — hash-shaped storage backed by the vault, memory-safe against coredump / log leakage. |
| [`core:protected/hash/http`](https://puck.uno/requirements/protected/hash/http) | HTTP-specialized protected hash — the shape [`core:auth/api`](https://puck.uno/requirements/protected/auth/api) hands off to `%chain.net.http.send`. <!-- STALE: %chain.X syntax being reworked --> |
| [`core:protected/memory`](https://puck.uno/requirements/protected/memory) | Developer-facing protected-mode entry — `.run do ... end` establishes a window during which plaintext values live only in vault-backed storage. |
| [`core:protected/password`](https://puck.uno/requirements/protected/password) | Password class — protected-hash-backed wrapper around a single credential value. |
| `core:random` | Randomness — UUID / number / string / bytes primitives, all drawing from libsodium → OS CSPRNG. Canonical spec TBD. |
| [`core:string`](https://puck.uno/requirements/built-in-classes/primitives/string/) | UTF-8 text. Source form: `'hi'`, `"hi"`, `:foo`, `<<EOF...EOF`. Single-quote / double-quote / symbol-shortcut / heredoc all produce the same class. `:foo` is shorthand for `'foo'` — Caspian has no separate symbol type. |
| [`core:variable`](https://puck.uno/requirements/built-in-classes/variable-object/) | Variable-object class — the storage-slot-as-first-class-object accessed via `$$name`. Guaranteed methods: `.value`, `.value=`, `.freeze`, `.frozen?`. |

The six primitives (`array`, `boolean`, `hash`, `null`, `number`, `string`) also have literal source forms — you write them directly rather than fetching an instance. Every string that crosses into Caspian is auto-encoded as UTF-8 at the boundary; every string produced is UTF-8 (see [concepts § Strings are UTF-8](https://puck.uno/requirements/concepts#strings-are-utf-8)).

## Engine internals

Named `core:` primitives that engine devs reference in specs but Caspian code rarely reaches directly. Not typically fetched — the engine uses them internally and exposes higher-level surfaces on top.

| Identifier | Purpose |
|---|---|
| [`core:aggregate_hash`](https://puck.uno/requirements/lua/aggregate-hash) | Engine-internal walked-view primitive over an ordered array of hash references. Powers `%chain`, scope frames, class-method resolution, delegated environments — one primitive, many roles. |
| [`core:protected/vault`](https://puck.uno/requirements/lua/vault) | Engine-internal secure-memory allocator. Backs every `core:protected/*` class; not typically referenced directly from Caspian. |
| [`core:scope`](https://puck.uno/requirements/lua/scope) | Engine-internal scope runtime — aggregate-hash-based, one per call frame plus one per captured closure. Backs variable resolution and assignment. |

## The `core:` prefix

- **Reserved.** User code cannot mint new `core:X` identifiers. Anything under the `core:` namespace is shipped with Caspian (in the binary or the pre-populated cache tier).
- **Not URL-fetched.** `%('core:X')` doesn't resolve through the fetch-discovery chain — the engine intercepts `core:` and returns its baked-in implementation directly. No network, no cache miss.
- **Distinct from `caspian.uno/*` downloads.** `caspian.uno/*` classes (like `caspian.uno/csv`, `caspian.uno/yaml`) are first-party downloads — they live on the network and go through cache/wire/octocat lookup. `core:` names bypass that entirely.

## Not on this sheet

- **`%X` global methods** — see the [global methods cheat sheet](global-methods) for the eight `%X`-prefixed globals. Some (`%import`, `%stdout`) reach engine surfaces; none of them use `core:` naming.
- **`caspian.uno/*` first-party downloads** — `caspian.uno/csv`, `caspian.uno/yaml`, and the other stdlib-adjacent classes live on the network and go through cache/wire/octocat lookup. Distinct from `core:` names (which bypass fetch-discovery entirely).
