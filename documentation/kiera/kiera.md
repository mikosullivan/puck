# Kiera

Kiera is a foreign object API — a protocol for working with remote objects across different
languages and systems. It is the umbrella that holds the mikobase, KScript, and Q0 together.
See [overview.md](../overview.md) for the full picture.

Class names in Kiera use UNS strings (URLs without the `https://` prefix), providing a
globally unique namespace. For example: `kiera.uno/mikobase`, `foo.com/character`.

The mikobase, Q0, and the object model are all Kiera components under the `kiera.uno` namespace.

See [ideas/marina.md](../ideas/marina.md) for a prior design exploration.

---

## `%kiera`

vibecode: {
	"section": "kiera_system_method",
	"role": "documents the %kiera system method for accessing the global Kiera object namespace",
	"key_concepts": ["%kiera", "UNS_lookup", "built-in_objects", "kiera.uno_default_namespace", "bare_name_shorthand"]
}

`%kiera` is a KScript system method that returns a **kiera object** — see
"The Kiera Object" below for the full model. `%kiera[UNS]` is a shorthand that
returns the object registered at that UNS address (the kiera's lookup method
in convenience form).

In the first version, only a predefined set of built-in objects are available. When
remote object retrieval lands, libraries will be resolved on demand — the engine pulls
from a configurable chain of providers (typically a local cache first, then remote
sources), with no install step. See [overview.md — Libraries Are Cached, Not Installed](../overview.md#libraries-are-cached-not-installed).

`%kiera` is scoped via `%chain` (the current kiera lives in the chain).
Because `%chain` is wiped at role boundaries (see [roles.md](../kscript/roles.md)),
the current kiera does not propagate across role boundaries; each role gets
its own world. When there is no kiera in the chain, `%kiera` returns plain
null.

### Shorthand for built-in classes

Bare names in `%kiera[...]` — any key without a domain — resolve to `kiera.uno/...`:

```
%kiera['null']         # same as %kiera['kiera.uno/null']
%kiera['true']         # same as %kiera['kiera.uno/true']
%kiera['mikobase/memory']  # same as %kiera['kiera.uno/mikobase/memory']
```

`kiera.uno` is the default namespace for `%kiera` lookups.

---

---

## The Kiera Object

```
vibecode: {
    "section": "kiera_object",
    "role": "documents the kiera object — what %kiera returns — including its structure (getters + faucets), version window, lookup mechanism, and per-getter roles",
    "key_concepts": ["kiera_holds_getters", "getters_hold_faucets", "per_getter_role",
        "version_window_immutable", "narrowing_only_derivation", "restrict_do_end"]
}
```

A **kiera** (lowercase, the object) is distinct from **`%kiera`** (the
system method). A kiera is a kind of object that knows how to resolve
UNS addresses to their registered objects. `%kiera` is the system-method
handle through which user code gets a kiera object back.

**You can have any number of kieras.** "The kiera" is shorthand for
whatever kiera `%kiera` returns at the moment — usually the
engine-provided one. The model supports any number, and code that
constructs alternate kieras for specific purposes can do so.

### Structure: Getters and Faucets

A kiera **holds one or more getters**, each representing a logical
source for objects (e.g., the `foo.com/*` namespace, a corporate
internal registry, a local-only namespace). The kiera is the lookup
orchestrator; the getters are the per-source units.

Each getter may internally use one or more **faucets** to do the actual
fetching:

- A typical remote-namespace getter has a **download faucet** (HTTPS to
  the source) plus a **cache faucet** (local cache directory). First-time
  lookups go through download (and populate the cache); subsequent
  lookups hit the cache.
- A getter that talks to a local resource might have just one faucet.

```
Kiera
├── Getter for foo.com/*       (role: foo-com-getter)
│   ├── HTTPS download faucet
│   └── Cache faucet
├── Getter for bar.com/*       (role: bar-com-getter)
│   ├── HTTPS download faucet
│   └── Cache faucet
└── Getter for internal/*      (role: internal-getter)
    └── Internal-network faucet
```

### Roles: Per-Getter, Not Per-Faucet

**Each getter has its own role.** Objects served through a getter get
that getter's role. Different getters in the same kiera produce
differently-tagged objects, because they're genuinely different logical
sources.

**Faucets inside a getter share the getter's role.** This resolves the
download-vs-cache problem: KScript caches remote objects on demand —
first-time fetches go through download, subsequent fetches through
cache. Both are faucets inside the same getter, both produce objects
with the getter's role. The same UNS hands back identically-tagged
objects regardless of cache state.

### Version Window

```
vibecode: {
    "section": "kiera_version_window",
    "properties": ["upper", "lower"],
    "immutable_after_creation": true,
    "supersedes": "%chain.cutoff"
}
```

Each kiera carries a **version window** — two timestamps that bound
which versions of an object are eligible to be returned. The window
lives on the kiera object itself; the engine sets it when the kiera is
created. (This replaces the earlier `%chain.cutoff` design.)

```
%kiera.lower = 'may 3, 2018'      # versions must be on or after
%kiera.upper = 'may 3, 2028'      # versions must be on or before
```

- **`upper`** — the latest acceptable timestamp. The kiera returns the
  latest version of an object that is on or before `upper`. Without
  `upper`, the kiera returns the latest existing version, full stop.
- **`lower`** — the earliest acceptable timestamp. Versions older than
  `lower` are not returned. Without `lower`, the floor is effectively
  negative infinity.

**Both properties are immutable once the kiera exists.** The engine
sets them at creation time, and no API can change them afterward. This
turns the timespan from a configuration knob into a structural sandbox.

Lookup semantics:

- Default (no bounds set) — return the latest version that exists.
- `upper` only — return the latest version on or before `upper`.
- `lower` only — return the latest version on or after `lower`.
- Both set — return the latest version in `[lower, upper]`.
- If no version exists in the allowed span, lookup behaves as if the
  UNS isn't there (returns null-flavored `not_found`).

### Deriving a Narrower Kiera

A kiera can produce a **derived kiera with a narrower window**, but
never a broader one. The one-way ratchet:

- The derived kiera's `upper` must be ≤ parent's `upper`.
- The derived kiera's `lower` must be ≥ parent's `lower`.
- Equivalently: the derived kiera's window is a subset of the parent's
  window.

Same shape as the other "derived capabilities can only be more
restricted" patterns in the framework (file permissions, subdirjail
permissions, etc.).

**What this rule does NOT prevent:** code with access to a network
faucet (or any other faucet) can construct its own kiera from scratch,
not derived from the engine's kiera. That fresh kiera's timespan can be
whatever the constructor chooses. The framework's stance: don't pass a
faucet to code you don't trust to use it however it wants.

### `restrict do ... end`

`restrict` is the canonical way to scope `%kiera` to a narrower window
for a block of code:

```
%kiera                                  # outer kiera (no extra restriction)

%kiera.restrict(upper: 'may 3, 2023') do
    %kiera                              # narrower derived kiera, in effect inside the block
end

%kiera                                  # back to the outer kiera
```

`restrict` does two things at once:

1. **Derives** a narrower kiera from the current one (per the one-way
   ratchet — narrower or equal, never broader).
2. **Installs** the derived kiera as the active `%kiera` in `%chain` for
   the duration of the block.

Nested `restrict` calls compose. When each block returns, the prior
scope's kiera takes over. Same shape as `%chain.isolate do ... end` and
other scoped-block primitives.

### Lookup Mechanism

A kiera exposes a **lookup method** as its public API. (Working name
TBD — likely `.lookup($uns)`; the actual name will be settled when the
class is spec'd in detail. `%kiera[UNS]` is sugar for it.)

**Base implementation:** the kiera walks its getters, asking each one
for the latest version of the UNS that falls within the kiera's
`[lower, upper]` window. The kiera then returns the latest result
across all getters' responses. If no getter has any version of the UNS
within the window, lookup returns a null with the flavor
`kiera.uno/null/flavor/not_found`. Callers can inspect `flavor.code` to
tell the difference between "lookup didn't match" and "the registered
value is intentionally null."

Note: finding the latest requires consulting all getters, not
short-circuiting on first hit. Order matters only for tie-breaking when
multiple getters return versions with the same timestamp — pick the
first (same UNS at the same timestamp means the same object).

**The `explicit`-null rule for sources.** If a kiera faucet reaches a
UNS where the registered value is intentionally null, the source must
mark that null as `kiera.uno/null/flavor/explicit` (code 200).
Otherwise the kiera treats an unflavored null as "lookup didn't find
this UNS" and falls through to the next getter. At the kiera-lookup
layer, unflavored null means "no result"; `explicit` is how a source
positively affirms "yes, this UNS exists; the registered value is
null."

**Subclassable for fancier dispatch.** The base implementation is
intentionally simple. Engines or developers needing UNS-prefix matching,
regex routing, dispatch tables, or fallback policies can subclass kiera
and override the lookup method.

### Provenance Checking

Provenance is **per-faucet**, not per-kiera. Each faucet has its own
policy about how to sign off on provenance for the objects it serves. A
kiera may hold one strict-policy faucet (verifies signatures against a
blockchain attestation) alongside a permissive-policy faucet (trusts
the cache directory's self-asserted contents) — same kiera, different
per-faucet rules.

A faucet's responsibility is provenance — verifying that an object it
returns for a UNS actually came from the namespace authority that UNS
claims. Whether the code itself is safe to run is a separate concern
handled by the role model.

Typical cases:

- **Actual fetch from the URL.** TLS handles the certificate
  verification at the network layer; the response by construction came
  from the verified server.
- **Cache.** The cache holds objects placed there by an earlier
  download step. The runtime trusts the cache implicitly. Simple,
  matches how npm/pip/gem/Cargo work.
- **Cache plus signature verification.** Additionally verifies
  cryptographic signatures (e.g., against the
  [Kiera blockchain](../kscript/blockchain/blockchain.md)). This is the "two distant
  objects" pattern: local cache holds the artifact, distant
  verification mechanism holds proof.

### The Engine Decides the Policy

**The engine controls which kiera `%kiera` returns**, and that kiera's
configuration determines everything about provenance policy, getters,
faucets, version window, etc.

Different engines hand in different kieras. A strict, security-
sensitive deployment hands user code a kiera that requires signatures
and blockchain attestations. A relaxed developer playground hands user
code a kiera that just trusts the cache. The KScript code is the same;
the kiera differs.

User code typically doesn't reason about which kiera it got. It calls
`%kiera['some.com/uns']`, and whatever the engine set up determines
the result and the checks.

---

## `%kiera.call`

vibecode: {
	"section": "kiera_call",
	"role": "documents the %kiera.call method for explicit remote method invocation",
	"key_concepts": ["%kiera.call", "remote_method_call", "target_object", "method_symbol", "keyword_params", "%chain_forwarding"]
}

`%kiera.call` makes an explicit remote method call on a Kiera object:

```
%kiera.call($person, :save, name: 'Jean-Luc')
```

The three arguments are:
1. The target object
2. The method name (a symbol)
3. Any keyword parameters to pass

`%kiera.call` automatically forwards the current `%chain` context to the remote call —
the same chain the calling function is running under. `%role` is reserved for possible
future use and is not part of early versions.

---

## `remote function`

vibecode: {
	"section": "remote_function",
	"role": "documents the remote function syntactic sugar for delegating to %kiera.call",
	"key_concepts": ["remote_function", "syntactic_sugar", "%kiera.call_delegation", "interchangeable_forms"]
}

`remote function` is a shorthand for defining a method that delegates to `%kiera.call`.
Inside a class definition, this:

```
remote function &save(name:)
end
```

is equivalent to generating a wrapper that calls:

```
%kiera.call(self, :save, name: name)
```

It is purely syntactic sugar — there is no separate remote dispatch mechanism. The
explicit `%kiera.call` form and the `remote function` shorthand are interchangeable.

---

## `kiera.uno` Namespace

vibecode: {
	"section": "kiera_uno_namespace",
	"role": "catalogs all built-in classes in the kiera.uno namespace",
	"key_concepts": ["kiera.uno/null", "kiera.uno/true", "kiera.uno/false", "kiera.uno/mikobase", "kiera.uno/flag", "kiera.uno/record", "kiera.uno/reference", "kiera.uno/dbfile"]
}

### Language and Runtime

| Class | Description |
|---|---|
| `kiera.uno/null` | Null class; always falsey; subclassable |
| `kiera.uno/true` | True class; always truthy; subclassable |
| `kiera.uno/false` | False class; always falsey; subclassable |
| `kiera.uno/mikobase` | Abstract mikobase base class |
| `kiera.uno/mikobase/memory` | SQLite in-memory mikobase (`:memory:`) |
| `kiera.uno/mikobase/sqlite` | SQLite file-backed mikobase |
| `kiera.uno/mikobase/http` | HTTP server exposing a mikobase over the network |
| `kiera.uno/mikobase/server` | Managed mikobase server for fork-based coordination |
| `kiera.uno/helper` | Base helper class |
| `kiera.uno/loop` | Loop object |
| `kiera.uno/meta_hash` | Read-overlay-write hash backed by an array of hashes; cascading config primitive (see [meta-hash.md](../kscript/built-in-classes/meta-hash.md)) |
| `kiera.uno/flag` | Abstract root of the flag hierarchy |
| `kiera.uno/warning` | Observational, non-unwinding; emitted via `%chain.warn`, collected via `heed()` |
| `kiera.uno/exception` | Abstract parent of everything raised to redirect flow |
| `kiera.uno/exception` | Generic exception (user-catchable, unwinds, carries stack trace) |
| `kiera.uno/exception/error` | Semantic-marker subclass of exception — same behavior; the name signals "this is an error condition" |
| `kiera.uno/exception/error/timeout` | Caller-facing timeout error raised at the `%utils.timeout` boundary (user-catchable, unwinds) |
| `kiera.uno/exception/exit` | Graceful process exit (engine-caught, unwinds stack, runs GC) |
| `kiera.uno/exception/return` | Function return (caught at function boundary, unwinds) |
| `kiera.uno/exception/abort` | Violent termination (engine-caught, does not unwind) |
| `kiera.uno/exception/security` | Security violation (engine-caught, does not unwind) |
| `kiera.uno/exception/timeout_handle` | Internal abort fired *inside* a `%utils.timeout` block; bubbles to the block boundary, does not unwind, not user-catchable |

### Object Store

| Class | Description |
|---|---|
| `kiera.uno/record` | Base record class |
| `kiera.uno/record/class` | Class definitions |
| `kiera.uno/reference` | Record reference |
| `kiera.uno/dbfile` | File attachment |
