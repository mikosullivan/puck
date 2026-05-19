# Project Overview

<a id="introduction"></a>
## Introduction

~~~json
{"vibecode": {
	"section": "what_is_this",
	"role": "introduces the Puck ecoverse organized around its three core packages",
	"key_concepts": ["Puck_ecoverse", "Puck_protocol", "Charlie", "Mikobase"]
}}
~~~

This project is the **Puck ecoverse** — a suite of interconnected
software for storing, querying, and programming with objects across
different languages and systems. The ecoverse is organized around
**three core packages**:

- **Puck** — a remote object protocol
- **Charlie** — a programming language
- **Mikobase** — a live object store

Each package has its own features and its own canonical specs. The
sections below cover the design principles that span all three
packages, walk through each package and its core features, and
report implementation status.

---

<a id="design-principles"></a>
## Design principles

~~~json
{"vibecode": {
	"section": "design_principles",
	"role": "the design principles that span all three packages",
	"key_concepts": ["no_nanny_code", "safe_defaults_with_explicit_overrides",
		"security_guarantees_not_nanny"]
}}
~~~

<a id="no-nanny-code"></a>
### No nanny code

Puck provides safe defaults but there are ways to override those
defaults if you choose:

- **Nanny code** says "you can't, because I think you shouldn't."
- **Safe defaults** say "you have to be explicit if you want to."
- **Security guarantees** say "you can't, because allowing this would
  break the trust model the rest of the system depends on."

The first is what we avoid. The second and third stay. When in doubt:
if a developer wants to do something legitimate that the API blocks
without giving them a way through, that's nanny code.

---

<a id="puck"></a>
## Puck

~~~json
{"vibecode": {
	"section": "puck_package",
	"role": "describes the Puck protocol and its features: UNS, %puck lookup and call, version window, library resolution, blockchain",
	"key_concepts": ["object_protocol", "UNS", "puck_lookup", "remote_method_invocation",
		"version_window", "library_resolution_through_puck", "blockchain_identity"]
}}
~~~

Puck is a **protocol for working with objects across languages and
systems**. It gives every object in the ecoverse a global address (a
UNS) and a uniform way to retrieve, query, and invoke methods on
objects regardless of where they physically live.

See [puck.md](puck/puck.md) for the full protocol spec.

<a id="features"></a>
### Features

- **UNS (Universal Namespace).** Every class and well-known object has
  a URL-shaped global address — your domain gives you a unique
  namespace (`foo.com/character`); built-ins live under
  `puck.uno/...`. UNS is naming/identity, not type hierarchy:
  `puck.uno/touchstone/error/x` is not a subclass of
  `puck.uno/error/x` unless explicitly declared.
- **`%puck[UNS]` lookup.** Charlie code retrieves objects by UNS:
  `%puck['foo.com/character']`. The puck (the resolver object)
  walks a configured chain of providers — local cache, network
  sources, blockchain attestations — and returns the right thing or
  null.
- **`%puck.call` remote method invocation.** Explicit cross-process /
  cross-host method calls with `%chain` forwarded automatically and a
  defined error model (target-not-found, transport, auth, propagated
  remote exceptions).
- **Version window.** Each puck carries an immutable `[lower, upper]`
  timestamp window that bounds which versions of an object are
  eligible to be returned. Derived pucks can narrow the window
  (one-way ratchet); you can't broaden it. Enables reproducible
  builds and historical queries.
- **Libraries are cached, not installed.** Charlie has no install
  step, no lockfile, no manifest. Libraries are referenced by UNS in
  source code and resolved on demand through the provider chain.
  Cached locally on first use; subsequent references hit the cache.
- **Blockchain identity and provenance.** The Puck blockchain
  provides cryptographically anchored identity and signed
  attestations for library versions — see
  [blockchain.md](charlie/blockchain.md).

---

<a id="charlie"></a>
## Charlie

~~~json
{"vibecode": {
	"section": "charlie_package",
	"role": "describes the Charlie language and its features: canonical runtime format, classes, functions, single-threaded with opt-in forking, role-based security, multi-syntax architecture preserved",
	"key_concepts": ["lightweight_embeddable_language", "CharlieJSON_runtime_format",
		"classes_with_inheritance", "functions_closures",
		"single_threaded_by_default_forking_opt_in", "role_based_security",
		"exception_handling", "multi_syntax_architecture_preserved"]
}}
~~~

Charlie is a **lightweight, embeddable programming language**. It
is designed from the ground up to support running untrusted code.
Designed to run inside a Mikobase engine, a browser, a CLI, or anywhere
else without external runtime dependencies beyond the engine itself.

See [charlie.md](charlie/charlie.md) for the language reference.

<a id="features-1"></a>
### Features

- **Built for running untrusted code.** Functions only have
access to what is explicitely sent to them as parameters.
They do not have universal access to file systems or network
connections. They can only use resources like that if you
explicitly send them in as paramters. See [roles.md](charlie/roles.md).
- **[Classes and inheritance](charlie/charlie.md#classes).**
  `class 'UNS' ... end` defines a class with fields, properties,
  methods, and helpers. Bare/anonymous classes
  (`class\n    inherits ... end`) for cases where identity comes
  from location rather than UNS.
- **[Functions and closures](charlie/charlie.md#functions).**
  `function &name(args) ... end` for named functions; closures
  capture lexical scope; functions don't. Parameters carry metadata
  via a uniform hash form (`{lazy: true, classes: ['string']}`);
  first-class param manipulation via `$foo.params['bar']`.
- **Single-threaded; forking opt-in.** One execution
  context per engine. The opt-in forking feature spawns isolated
  Charlie processes that coordinate through shared
  [Mikobases](mikobase/mikobase.md) — no shared-memory primitives,
  no locks.
- **Exception handling.** Standard `catch`/`raise` for user-territory
  exceptions; `%chain.warn`/`throw`/`error`/`exit`/`abort` for
  engine-aware flag-raising. Stack traces on every exception. See
  [charlie-runtime.md](charlie/charlie-runtime.md).
- **Built-in [HTTP middleware](charlie/http-middleware/http-middleware.md) family.**
  [Touchstone](charlie/http-middleware/touchstone.md) provides the
  per-request infrastructure (transactions, sessions, body buffering,
  CSP). [Sammy](charlie/http-middleware/sammy.md) is a built-in
  framework on Touchstone for route-style serving.

---

<a id="mikobase"></a>
## Mikobase

~~~json
{"vibecode": {
	"section": "mikobase_package",
	"role": "describes the Mikobase object store and its features: Q0 query language, class-based NoSQL, three v1 engines, worldlets as export format, live process model; temporal history is an opt-in mode",
	"key_concepts": ["live_object_store", "Q0_JSON_query_language", "class_based_NoSQL",
		"three_v1_engines", "worldlets_as_export_format",
		"live_process_not_passive_file", "temporal_history_opt_in"]
}}
~~~

Mikobase is a **live object store** — in memory, file-backed, or
served over a network. It supports class definitions, transactions,
locking, and a JSON query language. Both database-shaped use
(long-lived service backing store) and worldlet-shaped use (packaged,
portable snapshots) are first-class.

See [mikobase.md](mikobase/mikobase.md) for the full spec.

<a id="features-2"></a>
### Features

- **Q0 JSON-based query language.** Every query is a JSON object:
  `{"action": "select", "class": "foo.com/character"}`. SQL-shaped
  semantics on top of a class-based model. Engines translate Q0 to
  SQL on the SQLite engines or to JSON-traversal on the worldlet
  engine.
- **Class-based, NoSQL.** Records have a class, a stable UUID
  identity, and a typed `bucket` of fields. Class definitions live in
  the mikobase itself.
- **Three v1 engines.** SQLite file-backed, SQLite in-memory
  (`:memory:`), and a worldlet-direct engine that operates on
  worldlet JSON in place — built for very short-lived workloads (AI
  conversations) where SQLite import/export overhead would dominate.
- **Worldlets as an export format.** A worldlet is a serialized
  export of a mikobase — a single portable JSON document containing
  classes, records, and files. Round-trips through import/export,
  sharable, can be the live storage of the worldlet-direct engine.
- **Opt-in temporal history.** Records overwrite in place by default.
  A mikobase set to `"temporal": true` at initialization keeps an
  append-only history of every write, supporting rollback and
  time-travel queries. Most workloads don't need this; turn it on
  when audit history is a real requirement.
- **Live process model.** A mikobase is not a passive file — it
  requires a maintaining process. Connecting to a mikobase means
  connecting to a live process, whether in-memory locally, a server
  on the same machine, or a remote service over HTTP.

---

<a id="implementation-status"></a>
## Implementation status

~~~json
{"vibecode": {
	"section": "implementation_status",
	"role": "tracks the development status of each Puck ecoverse component",
	"key_concepts": ["active_development", "design_phase", "lua_reference_engine", "Q0",
		"Charlie", "v01_hello_world_shipped"]
}}
~~~

| Component | Status |
|---|---|
| Charlie Lua reference engine | V0.01 hello-world ships; 213 tests passing. V0.02 (Charlie source via transpiler) and V0.03–V0.05 plans drafted. |
| Charlie language | V0.01 surface shipped; broader language spec in active design. |
| CharlieJSON | Canonical runtime format; V0.01 fixture-and-engine path is fully wired. |
| Mikobase engine | Design only. V1 plan ships three engines (SQLite file, SQLite `:memory:`, worldlet-direct); none yet implemented. |
| Q0 query language | Designed; will be implemented as SQL passthrough on the SQLite engines and against the JSON structure on the worldlet engine. |
| Worldlet (packaged mikobase) | Format spec exists; import/export to be implemented alongside the Mikobase engines. |
| Forking (opt-in Charlie feature) | Early design; not in active development. |
| Puck protocol | Early design. |
