# Puck

Puck is a foreign object API — a protocol for working with remote objects across different
languages and systems. It is the umbrella that holds the mikobase, Charlie, and Q0 together.
See [overview.md](../overview.md) for the full picture.

Class names in Puck use UNS strings (URLs without the `https://` prefix), providing a
globally unique namespace. For example: `puck.uno/mikobase`, `foo.com/character`.

The mikobase, Q0, and the object model are all Puck components under the `puck.uno` namespace.

See [ideas/marina.md](../ideas/marina.md) for a prior design exploration.

---

<a id="puck"></a>
## 1 `%puck`

~~~json
{"vibecode": {
	"section": "puck_system_method",
	"role": "documents the %puck system method for accessing the global Puck object namespace",
	"key_concepts": ["%puck", "UNS_lookup", "built-in_objects", "puck.uno_default_namespace", "bare_name_shorthand"]
}}
~~~

`%puck` is a Charlie system method that returns a **puck object** — see
"The Puck Object" below for the full model. `%puck[UNS]` is a shorthand that
returns the object registered at that UNS address (the puck's lookup method
in convenience form).

In the first version, only a predefined set of built-in objects are available. When
remote object retrieval lands, libraries will be resolved on demand — the engine pulls
from a configurable chain of providers (typically a local cache first, then remote
sources), with no install step. See [overview.md — Libraries Are Cached, Not Installed](../overview.md#libraries-are-cached-not-installed).

`%puck` is scoped via `%chain` (the current puck lives in the chain).
Because `%chain` is wiped at role boundaries (see [roles.md](../charlie/roles.md)),
the current puck does not propagate across role boundaries; each role gets
its own world. When there is no puck in the chain, `%puck` returns plain
null.

**The engine decides what puck (if any) populates each role boundary.**
The engine may install a puck for a new role on entry — typically a
restricted/derived puck per the role's trust profile — or it may leave
`%puck` null for that role. The "engine controls policy" framing in
[The Engine Decides the Policy](#the-engine-decides-the-policy) applies
per role boundary, not globally. The two statements are consistent: the
engine's per-role policy is what determines whether crossing into role B
yields a puck or null.

<a id="shorthand-for-built-in-classes"></a>
### 1.1 Shorthand for built-in classes

Bare names in `%puck[...]` — any key without a domain — resolve to `puck.uno/...`:

```
%puck['null']         # same as %puck['puck.uno/null']
%puck['true']         # same as %puck['puck.uno/true']
%puck['mikobase/memory']  # same as %puck['puck.uno/mikobase/memory']
```

`puck.uno` is the default namespace for `%puck` lookups.

---

---

<a id="the-puck-object"></a>
## 2 The Puck Object

~~~json
{"vibecode": {
    "section": "puck_object",
    "role": "documents the puck object — what %puck returns — including its structure (getters + faucets), version window, lookup mechanism, and per-getter roles",
    "key_concepts": ["puck_holds_getters", "getters_hold_faucets", "per_getter_role",
        "version_window_immutable", "narrowing_only_derivation", "restrict_do_end"]
}}
~~~

A **puck** (lowercase, the object) is distinct from **`%puck`** (the
system method). A puck is a kind of object that knows how to resolve
UNS addresses to their registered objects. `%puck` is the system-method
handle through which user code gets a puck object back.

**You can have any number of pucks.** "The puck" is shorthand for
whatever puck `%puck` returns at the moment — usually the
engine-provided one. The model supports any number, and code that
constructs alternate pucks for specific purposes can do so.

<a id="structure-getters-and-faucets"></a>
### 2.1 Structure: Getters and Faucets

A puck **holds one or more getters**, each representing a logical
source for objects (e.g., the `foo.com/*` namespace, a corporate
internal registry, a local-only namespace). The puck is the lookup
orchestrator; the getters are the per-source units.

Each getter may internally use one or more **faucets** to do the actual
fetching:

- A typical remote-namespace getter has a **download faucet** (HTTPS to
  the source) plus a **cache faucet** (local cache directory). First-time
  lookups go through download (and populate the cache); subsequent
  lookups hit the cache.
- A getter that talks to a local resource might have just one faucet.

```
Puck
├── Getter for foo.com/*       (role: foo-com-getter)
│   ├── HTTPS download faucet
│   └── Cache faucet
├── Getter for bar.com/*       (role: bar-com-getter)
│   ├── HTTPS download faucet
│   └── Cache faucet
└── Getter for internal/*      (role: internal-getter)
    └── Internal-network faucet
```

<a id="roles-per-getter-not-per-faucet"></a>
### 2.2 Roles: Per-Getter, Not Per-Faucet

**Each getter has its own role.** Objects served through a getter get
that getter's role. Different getters in the same puck produce
differently-tagged objects, because they're genuinely different logical
sources.

**Faucets inside a getter share the getter's role.** This resolves the
download-vs-cache problem: Charlie caches remote objects on demand —
first-time fetches go through download, subsequent fetches through
cache. Both are faucets inside the same getter, both produce objects
with the getter's role. The same UNS hands back identically-tagged
objects regardless of cache state.

<a id="version-window"></a>
### 2.3 Version Window

~~~json
{"vibecode": {
    "section": "puck_version_window",
    "properties": ["upper", "lower"],
    "immutable_after_creation": true,
    "supersedes": "%chain.cutoff"
}}
~~~

Each puck carries a **version window** — two timestamps that bound
which versions of an object are eligible to be returned. The window
lives on the puck object itself; the engine sets it when the puck is
created. (This replaces the earlier `%chain.cutoff` design.)

The window has two read-only properties:

- **`upper`** — the latest acceptable timestamp. The puck returns the
  latest version of an object that is on or before `upper`. Without
  `upper`, the puck returns the latest existing version, full stop.
- **`lower`** — the earliest acceptable timestamp. Versions older than
  `lower` are not returned. Without `lower`, the floor is effectively
  negative infinity.

Both can be read:

```
$bound = %puck.upper             # read the upper bound
```

But **both are immutable once the puck exists.** The engine sets them
at creation time, and no API can change them afterward — `%puck.upper = ...`
and `%puck.lower = ...` are not valid; the assignment raises. This turns
the timespan from a configuration knob into a structural sandbox. To get
a puck with a narrower window, **derive** one (see
[Deriving a Narrower Puck](#deriving-a-narrower-puck)) or use
[`restrict do ... end`](#restrict-do--end) for block-scoped narrowing.

Lookup semantics:

- Default (no bounds set) — return the latest version that exists.
- `upper` only — return the latest version on or before `upper`.
- `lower` only — return the latest version on or after `lower`.
- Both set — return the latest version in `[lower, upper]`.
- If no version exists in the allowed span, lookup behaves as if the
  UNS isn't there (returns null-flavored `not_found`).

<a id="deriving-a-narrower-puck"></a>
### 2.4 Deriving a Narrower Puck

A puck can produce a **derived puck with a narrower window**, but
never a broader one. The one-way ratchet:

- The derived puck's `upper` must be ≤ parent's `upper`.
- The derived puck's `lower` must be ≥ parent's `lower`.
- Equivalently: the derived puck's window is a subset of the parent's
  window.

Same shape as the other "derived capabilities can only be more
restricted" patterns in the framework (file permissions, subdirjail
permissions, etc.).

**What this rule does NOT prevent:** code with access to a network
faucet (or any other faucet) can construct its own puck from scratch,
not derived from the engine's puck. That fresh puck's timespan can be
whatever the constructor chooses. The framework's stance: don't pass a
faucet to code you don't trust to use it however it wants.

<a id="restrict-do-end"></a>
### 2.5 `restrict do ... end`

`restrict` is the canonical way to scope `%puck` to a narrower window
for a block of code:

```
%puck                                  # outer puck (no extra restriction)

%puck.restrict(upper: 'may 3, 2023') do
    %puck                              # narrower derived puck, in effect inside the block
end

%puck                                  # back to the outer puck
```

`restrict` does two things at once:

1. **Derives** a narrower puck from the current one (per the one-way
   ratchet — narrower or equal, never broader).
2. **Installs** the derived puck as the active `%puck` in `%chain` for
   the duration of the block.

Nested `restrict` calls compose. When each block returns, the prior
scope's puck takes over. Same shape as `%chain.isolate do ... end` and
other scoped-block primitives.

<a id="lookup-mechanism"></a>
### 2.6 Lookup Mechanism

A puck exposes a **lookup method** as its public API. (Working name
TBD — likely `.lookup($uns)`; the actual name will be settled when the
class is spec'd in detail. `%puck[UNS]` is sugar for it.)

**Base implementation:** the puck walks its getters, asking each one
for the latest version of the UNS that falls within the puck's
`[lower, upper]` window. The puck then returns the latest result
across all getters' responses. If no getter has any version of the UNS
within the window, lookup returns a null with the flavor
`puck.uno/null/flavor/not_found`. Callers can inspect `flavor.code` to
tell the difference between "lookup didn't match" and "the registered
value is intentionally null."

Note: finding the latest requires consulting all getters, not
short-circuiting on first hit. Order matters only for tie-breaking when
multiple getters return versions with the same timestamp — pick the
first (same UNS at the same timestamp means the same object).

**The `explicit`-null rule for sources.** If a puck faucet reaches a
UNS where the registered value is intentionally null, the source must
mark that null as `puck.uno/null/flavor/explicit` (code 200).
Otherwise the puck treats an unflavored null as "lookup didn't find
this UNS" and falls through to the next getter. At the puck-lookup
layer, unflavored null means "no result"; `explicit` is how a source
positively affirms "yes, this UNS exists; the registered value is
null."

**Subclassable for fancier dispatch.** The base implementation is
intentionally simple. Engines or developers needing UNS-prefix matching,
regex routing, dispatch tables, or fallback policies can subclass puck
and override the lookup method.

<a id="provenance-checking"></a>
### 2.7 Provenance Checking

Provenance is **per-faucet**, not per-puck. Each faucet has its own
policy about how to sign off on provenance for the objects it serves. A
puck may hold one strict-policy faucet (verifies signatures against a
blockchain attestation) alongside a permissive-policy faucet (trusts
the cache directory's self-asserted contents) — same puck, different
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
  [Puck blockchain](../blockchain.md)). This is the "two distant
  objects" pattern: local cache holds the artifact, distant
  verification mechanism holds proof.

<a id="the-engine-decides-the-policy"></a>
### 2.8 The Engine Decides the Policy

**The engine controls which puck `%puck` returns**, and that puck's
configuration determines everything about provenance policy, getters,
faucets, version window, etc.

Different engines hand in different pucks. A strict, security-
sensitive deployment hands user code a puck that requires signatures
and blockchain attestations. A relaxed developer playground hands user
code a puck that just trusts the cache. The Charlie code is the same;
the puck differs.

User code typically doesn't reason about which puck it got. It calls
`%puck['some.com/uns']`, and whatever the engine set up determines
the result and the checks.

---

<a id="puckcall"></a>
## 3 `%puck.call`

~~~json
{"vibecode": {
	"section": "puck_call",
	"role": "documents the %puck.call method for explicit remote method invocation",
	"key_concepts": ["%puck.call", "remote_method_call", "target_object", "method_symbol", "keyword_params", "%chain_forwarding"]
}}
~~~

`%puck.call` makes an explicit remote method call on a Puck object:

```
%puck.call($person, :save, name: 'Jean-Luc')
```

The three arguments are:
1. The target object
2. The method name (a symbol)
3. Any keyword parameters to pass

`%puck.call` automatically forwards the current `%chain` context to the remote call —
the same chain the calling function is running under. `%role` is reserved for possible
future use and is not part of early versions.

<a id="return-value-and-error-model"></a>
### 3.1 Return value and error model

- **Return**: the remote method's return value, marshaled back as a Puck object
  reference (or a primitive value, if the remote method returned one). The caller
  doesn't see "this was remote" — the value comes back like any local call.
- **Target lookup failure**: if the target object can't be resolved (UNS unknown,
  withdrawn, outside the current puck's version window), `%puck.call` raises
  `puck.uno/error/not_found`.
- **Method not found**: if the target exists but doesn't expose the named method,
  raises `puck.uno/error/method_not_found`.
- **Transport failure**: network errors, timeout, refused connections, etc., raise
  `puck.uno/error/transport` with the underlying cause in the bucket.
- **Remote exception**: if the remote method itself raises, that exception
  propagates to the caller as if it were thrown locally. The remote stack trace is
  preserved (per the stack-trace shape in
  [charlie-runtime.md](../charlie/charlie-runtime.md#all-exceptions-carry-a-stack-trace)).
  Caller handles with `catch` as usual.
- **Authorization failure**: if the remote rejects the call (signature invalid,
  role not trusted, etc.), raises `puck.uno/error/auth`.

---

<a id="remote-function"></a>
## 4 `remote function`

~~~json
{"vibecode": {
	"section": "remote_function",
	"role": "documents the remote function syntactic sugar for delegating to %puck.call",
	"key_concepts": ["remote_function", "syntactic_sugar", "%puck.call_delegation", "interchangeable_forms"]
}}
~~~

`remote function` is a shorthand for defining a method that delegates to `%puck.call`.
Inside a class definition, this:

```
remote function &save(name:)
end
```

is equivalent to generating a wrapper that calls:

```
%puck.call(self, :save, name: name)
```

It is purely syntactic sugar — there is no separate remote dispatch mechanism. The
explicit `%puck.call` form and the `remote function` shorthand are interchangeable.

---

<a id="puckuno-namespace"></a>
## 5 `puck.uno` Namespace

~~~json
{"vibecode": {
	"section": "puck_uno_namespace",
	"role": "catalogs all built-in classes in the puck.uno namespace",
	"key_concepts": ["puck.uno/null", "puck.uno/true", "puck.uno/false", "puck.uno/mikobase", "puck.uno/flag", "puck.uno/record", "puck.uno/reference", "puck.uno/dbfile"]
}}
~~~

<a id="language-and-runtime"></a>
### 5.1 Language and Runtime

| Class | Description |
|---|---|
| `puck.uno/null` | Null class; always falsey; subclassable |
| `puck.uno/true` | True class; always truthy; subclassable |
| `puck.uno/false` | False class; always falsey; subclassable |
| `puck.uno/mikobase` | Abstract mikobase base class |
| `puck.uno/mikobase/memory` | SQLite in-memory mikobase (`:memory:`) |
| `puck.uno/mikobase/sqlite` | SQLite file-backed mikobase |
| `puck.uno/mikobase/http` | HTTP server exposing a mikobase over the network |
| `puck.uno/mikobase/server` | Managed mikobase server for fork-based coordination |
| `puck.uno/helper` | Base helper class |
| `puck.uno/loop` | Loop object |
| `puck.uno/meta_hash` | Read-overlay-write hash backed by an array of hashes; cascading config primitive (see [meta-hash.md](../charlie/built-in-classes/meta-hash.md)) |
| `puck.uno/flag` | Abstract root of the flag hierarchy |
| `puck.uno/warning` | Observational, non-unwinding; emitted via `%chain.warn`, collected via `heed()` |
| `puck.uno/exception` | Umbrella for everything raised. Also itself a concrete user-catchable class (unwinds; carries stack trace). All other classes in this block are declared subclasses; UNS naming is flat, inheritance is declared (see [charlie-runtime.md § Catching exceptions](../charlie/charlie-runtime.md#catching-exceptions)). |
| `puck.uno/error` | Semantic-marker subclass of exception — same behavior; the name signals "this is an error condition" |
| `puck.uno/error/timeout` | Caller-facing timeout error raised at the `%utils.timeout` boundary (user-catchable, unwinds) |
| `puck.uno/exit` | Graceful process exit (engine-caught, unwinds stack, runs GC) |
| `puck.uno/return` | Function return (caught at function boundary, unwinds) |
| `puck.uno/abort` | Violent termination (engine-caught, does not unwind) |
| `puck.uno/security` | Security violation (engine-caught, does not unwind) |
| `puck.uno/timeout_handle` | Internal abort fired *inside* a `%utils.timeout` block; bubbles to the block boundary, does not unwind, not user-catchable |

<a id="object-store"></a>
### 5.2 Object Store

| Class | Description |
|---|---|
| `puck.uno/record` | Base record class |
| `puck.uno/record/class` | Class definitions |
| `puck.uno/reference` | Record reference |
| `puck.uno/dbfile` | File attachment |
