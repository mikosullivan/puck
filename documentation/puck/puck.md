# Puck (the Protocol)

~~~json
{"vibecode": {
	"doc": "puck",
	"role": "language-agnostic spec for the Puck remote-object protocol: UNS addressing, the puck resolver object, version windows, lookup mechanism, provenance, remote method invocation, and the puck.uno built-in namespace; usable from any language that can speak JSON over HTTP",
	"key_concepts": ["language_agnostic_protocol", "UNS_addresses",
		"puck_resolver_object", "getters_and_faucets", "version_window",
		"one_way_ratchet_narrowing", "lookup_mechanism", "provenance_per_faucet",
		"remote_method_invocation", "puck_uno_builtin_namespace"],
	"audience": ["developers_in_any_language", "puck_client_implementors",
		"puck_server_implementors", "charlie_users_who_want_the_underlying_model"],
	"example_universe": "Star Trek"
}}
~~~

Puck is a **language-agnostic protocol for working with remote objects**.
Look up an object by global address, call its methods, get back values
that look local. Any language that can speak JSON over HTTP can speak
Puck.

[Charlie](../charlie/charlie.md) ships first-class Puck integration —
`%puck`, `%puck.call`, `remote function`, `restrict` — and is the
primary client implementation today. But the protocol is independent
of Charlie. The examples below show the same lookup from Charlie,
Python, and a raw HTTP request.

For Charlie-specific syntax and integration, see
[charlie/puck.md](../charlie/puck.md).

---

<a id="contents"></a>
## 1 Contents

- [What it does](#what-it-does)
- [UNS — addresses](#uns--addresses)
- [Lookup: first contact](#lookup-first-contact)
- [The puck object](#the-puck-object)
  - [Structure: getters and faucets](#structure-getters-and-faucets)
  - [Roles: per-getter, not per-faucet](#roles-per-getter-not-per-faucet)
  - [Version window](#version-window)
  - [Deriving a narrower puck](#deriving-a-narrower-puck)
  - [Lookup mechanism](#lookup-mechanism)
  - [Provenance checking](#provenance-checking)
  - [The engine decides the policy](#the-engine-decides-the-policy)
- [Remote method invocation](#remote-method-invocation)
  - [Error catalog](#error-catalog)
- [`puck.uno` namespace](#puckuno-namespace)
- [Charlie integration](#charlie-integration)

---

<a id="what-it-does"></a>
## 2 What it does

A Puck **client**:

- Looks up an object by **UNS** (a global URL-shaped address).
- Calls a method on it remotely — request goes out, response comes back.
- Treats the result like a local value.

A Puck **server**:

- Registers objects under UNS addresses.
- Responds to lookup and method-call requests.
- Hands back signed or cached attestations as configured.

The wire format is JSON. There is no constraint on the language at
either end; client and server can be written in different languages
entirely.

---

<a id="uns-addresses"></a>
## 3 UNS — addresses

Every Puck object has a global URL-shaped address called a **UNS**
(Universal Namespace identifier). Examples:

- `puck.uno/mikobase/memory` — a built-in (the puck.uno namespace
  hosts the language- and runtime-level classes; see
  [`puck.uno` namespace](#puckuno-namespace) below).
- `starfleet.com/character` — owned by whoever controls `starfleet.com`.
- `acme.org/widget` — owned by whoever controls `acme.org`.

UNS is **naming and identity, not type hierarchy.**
`puck.uno/touchstone/error/x` is not a subclass of `puck.uno/error/x`
unless the class explicitly declares the inheritance. Full UNS spec:
[ecoverse/uns.md](../ecoverse/uns.md).

---

<a id="lookup-first-contact"></a>
## 4 Lookup: first contact

The minimum a client does: ask the puck for an object by UNS, then call
a method on it.

**In [Charlie](../charlie/charlie.md):**

~~~charlie
$officer = %puck['starfleet.com/character/picard']
$officer.greet(name: 'Number One')
~~~

**In Python (sketch — the client library isn't built yet):**

```python
import puck

p = puck.connect()                                       # get the local puck
officer = p.lookup('starfleet.com/character/picard')     # resolve UNS to object
officer.greet(name='Number One')                         # remote method call
```

**At the wire (any language that can POST JSON):**

```sh
# Look up the object's metadata
curl https://puck.example.com/lookup \
    -H 'Content-Type: application/json' \
    -d '{"uns": "starfleet.com/character/picard"}'

# Call a method on it
curl https://puck.example.com/call \
    -H 'Content-Type: application/json' \
    -d '{
        "uns": "starfleet.com/character/picard",
        "method": "greet",
        "params": {"name": "Number One"}
    }'
```

The Charlie and Python forms hide the JSON; the curl form exposes it.
All three are doing the same thing: ask the puck to resolve the UNS,
then ask it to dispatch a method.

---

<a id="the-puck-object"></a>
## 5 The puck object

A **puck** (lowercase, the object) is the client-side resolver. It
knows how to map a UNS to its registered object, applying whatever
policy the engine configured at creation time.

You can have any number of pucks; "the puck" is shorthand for whichever
one the current process uses by default. Client libraries typically
expose one default puck and allow constructing alternates.

<a id="structure-getters-and-faucets"></a>
### 5.1 Structure: getters and faucets

A puck **holds one or more getters**, each representing a logical
source for objects (a remote namespace, a corporate internal registry,
a local-only namespace).

Each getter may use one or more **faucets** to do the actual fetching:

- A typical remote-namespace getter has a **download faucet** (HTTPS to
  the source) plus a **cache faucet** (local cache). First-time lookups
  go through download; subsequent lookups hit the cache.
- A getter that talks to a local resource might have just one faucet.

```
Puck
├── Getter for starfleet.com/*    (role: starfleet-com-getter)
│   ├── HTTPS download faucet
│   └── Cache faucet
├── Getter for vulcan.org/*       (role: vulcan-org-getter)
│   ├── HTTPS download faucet
│   └── Cache faucet
└── Getter for internal/*         (role: internal-getter)
    └── Internal-network faucet
```

<a id="roles-per-getter-not-per-faucet"></a>
### 5.2 Roles: per-getter, not per-faucet

**Each getter has its own role.** Objects served through a getter
inherit that getter's role. Different getters in the same puck produce
differently-tagged objects, because they're genuinely different sources.

**Faucets inside a getter share the getter's role.** Charlie caches
remote objects on demand — first-time fetches go through download,
subsequent fetches through cache — but both faucets are inside the same
getter and both produce objects with the same role. The same UNS hands
back identically-tagged objects regardless of cache state.

<a id="version-window"></a>
### 5.3 Version window

Each puck carries a **version window** — two timestamps that bound
which versions of an object are eligible to be returned. The window
lives on the puck object itself; the engine sets it at creation time.

The window has two read-only properties:

- **`upper`** — the latest acceptable timestamp. The puck returns the
  latest version on or before `upper`. Without `upper`, the puck
  returns the latest existing version.
- **`lower`** — the earliest acceptable timestamp. Versions older than
  `lower` are not returned. Without `lower`, the floor is effectively
  negative infinity.

Both are **immutable once the puck exists.** The engine sets them at
creation; no API can change them afterward. To get a puck with a
narrower window, **derive** one (see
[Deriving a narrower puck](#deriving-a-narrower-puck)).

Lookup semantics:

- Default (no bounds) — return the latest version that exists.
- `upper` only — return the latest version on or before `upper`.
- `lower` only — return the latest version on or after `lower`.
- Both set — return the latest version in `[lower, upper]`.
- If no version exists in the allowed span, lookup behaves as if the
  UNS isn't there.

<a id="deriving-a-narrower-puck"></a>
### 5.4 Deriving a narrower puck

A puck can produce a **derived puck with a narrower window**, never
broader. The one-way ratchet:

- Derived `upper` ≤ parent's `upper`.
- Derived `lower` ≥ parent's `lower`.
- Equivalently: the derived window is a subset of the parent's window.

Same shape as the other "derived capabilities are only more
restricted" patterns in the framework (file permissions, subdirjail
permissions, etc.).

**What this rule does NOT prevent:** code with access to a network
faucet (or any other faucet) can construct its own puck from scratch,
not derived from the engine's puck. That fresh puck's window can be
whatever the constructor chooses. The framework's stance: don't pass a
faucet to code you don't trust to use it however it wants.

<a id="lookup-mechanism"></a>
### 5.5 Lookup mechanism

A puck exposes a **lookup method** as its public API. (The Charlie
sugar `%puck[UNS]` is shorthand for it; client libraries in other
languages will expose it under whatever idiomatic name fits.)

**Base implementation:** the puck walks its getters, asking each one
for the latest version of the UNS that falls within the puck's
`[lower, upper]` window. The puck then returns the latest result
across all getters' responses. If no getter has any version of the UNS
within the window, lookup returns a null with the flavor
`puck.uno/null/flavor/not_found`. Callers can inspect `flavor.code` to
tell the difference between "lookup didn't match" and "the registered
value is intentionally null."

Finding the latest requires consulting all getters, not short-circuiting
on first hit. Order matters only for tie-breaking when multiple getters
return versions with the same timestamp — pick the first.

**The `explicit`-null rule for sources.** If a faucet reaches a UNS
where the registered value is intentionally null, the source must mark
that null as `puck.uno/null/flavor/explicit`. Otherwise the puck treats
an unflavored null as "lookup didn't find this UNS" and falls through
to the next getter.

**Subclassable for fancier dispatch.** The base implementation is
intentionally simple. Engines or developers needing UNS-prefix
matching, regex routing, dispatch tables, or fallback policies can
subclass puck and override the lookup method.

<a id="provenance-checking"></a>
### 5.6 Provenance checking

Provenance is **per-faucet**, not per-puck. Each faucet has its own
policy for verifying that an object it serves actually came from the
namespace authority that UNS claims. A puck may hold one strict-policy
faucet (verifies signatures against a blockchain attestation) alongside
a permissive-policy faucet (trusts the cache directory's self-asserted
contents) — same puck, different per-faucet rules.

A faucet's responsibility is provenance. Whether the code itself is
safe to *run* is a separate concern handled by the role model.

Typical cases:

- **Actual fetch from the URL.** TLS handles the certificate
  verification at the network layer; the response by construction came
  from the verified server.
- **Cache.** The cache holds objects placed there by an earlier
  download step. The runtime trusts the cache implicitly. Matches how
  npm/pip/gem/Cargo work.
- **Cache plus signature verification.** Additionally verifies
  cryptographic signatures (e.g., against the
  [Puck blockchain](../blockchain.md)). Local cache holds the artifact,
  distant verification mechanism holds proof.

<a id="the-engine-decides-the-policy"></a>
### 5.7 The engine decides the policy

**The engine controls which puck is the default**, and that puck's
configuration determines everything about provenance policy, getters,
faucets, version window, etc.

Different engines hand in different pucks. A strict, security-sensitive
deployment hands user code a puck that requires signatures and
blockchain attestations. A relaxed developer playground hands user code
a puck that just trusts the cache. The client code is the same; the
puck differs.

User code typically doesn't reason about which puck it got. It calls
`lookup(some_uns)`, and whatever the engine configured determines the
result and the checks.

---

<a id="remote-method-invocation"></a>
## 6 Remote method invocation

A method call on a Puck object is a JSON request to the server hosting
the UNS. The protocol-level shape:

**Request:**

```json
{
    "uns":    "starfleet.com/character/picard",
    "method": "greet",
    "params": {"name": "Number One"},
    "chain":  { ...current-caller %chain context... }
}
```

**Response:**

```json
{
    "ok":     true,
    "result": "Hello, Number One."
}
```

The client wraps this in whatever idiomatic surface fits the language.
In Charlie:

~~~charlie
%puck.call($officer, :greet, name: 'Number One')
~~~

In a hypothetical Python client:

```python
officer.greet(name='Number One')
# or, explicit form:
puck.call(officer, 'greet', name='Number One')
```

The chain context is forwarded automatically; the caller doesn't have
to assemble it.

<a id="error-catalog"></a>
### 6.1 Error catalog

When a remote call fails, the response carries a typed error from the
catalog below. Client libraries raise these as language-native
exceptions (in Charlie, ordinary catchable exceptions under
`puck.uno/error/*`):

| UNS | Meaning |
|---|---|
| `puck.uno/error/not_found` | Target UNS doesn't resolve (unknown, withdrawn, outside the puck's version window). |
| `puck.uno/error/method_not_found` | Target exists but doesn't expose the named method. |
| `puck.uno/error/transport` | Network error, timeout, refused connection, etc. The underlying cause is in the error's bucket. |
| `puck.uno/error/auth` | Remote rejected the call (signature invalid, role not trusted, etc.). |
| (remote exception) | If the remote method itself raises, that exception propagates to the caller as if thrown locally, with the remote stack trace preserved. |

The shape of the error response is the same regardless of which client
language is calling — these are protocol-level errors.

---

<a id="puckuno-namespace"></a>
## 7 `puck.uno` Namespace

`puck.uno` is the namespace for **language- and runtime-level classes**
shipped as part of Puck itself. Implementations of these classes are
either built into the host engine or resolvable through the standard
puck.

<a id="language-and-runtime"></a>
### 7.1 Language and runtime

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
| `puck.uno/error/not_found` | Lookup target UNS doesn't resolve (see [Error catalog](#error-catalog)) |
| `puck.uno/error/method_not_found` | Target object doesn't expose the requested method |
| `puck.uno/error/transport` | Network / transport failure during a Puck call |
| `puck.uno/error/auth` | Authorization rejection from a remote call |
| `puck.uno/error/timeout` | Caller-facing timeout error raised at the `%utils.timeout` boundary |
| `puck.uno/exit` | Graceful process exit (engine-caught, unwinds stack, runs GC) |
| `puck.uno/return` | Function return (caught at function boundary, unwinds) |
| `puck.uno/abort` | Violent termination (engine-caught, does not unwind) |
| `puck.uno/security` | Security violation (engine-caught, does not unwind) |
| `puck.uno/timeout_handle` | Internal abort fired *inside* a `%utils.timeout` block; bubbles to the block boundary, does not unwind, not user-catchable |

<a id="object-store"></a>
### 7.2 Object store

| Class | Description |
|---|---|
| `puck.uno/record` | Base record class |
| `puck.uno/record/class` | Class definitions |
| `puck.uno/reference` | Record reference |
| `puck.uno/dbfile` | File attachment |

---

<a id="charlie-integration"></a>
## 8 Charlie integration

Charlie programs interact with Puck through dedicated system methods
and syntax: `%puck`, `%puck[UNS]`, `%puck.call`, `remote function`, and
`restrict do ... end`. Full Charlie-side spec lives in
[charlie/puck.md](../charlie/puck.md).

Client libraries in other languages will expose the same underlying
operations under language-idiomatic names. The protocol stays the same.
