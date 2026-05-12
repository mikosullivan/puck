# Roles (brainstorm — superseded by official doc)

> **Status: this brainstorm is now superseded by the official
> [documentation/roles.md](../roles.md).** The role model is the
> official security model for KScript. This file is preserved as a
> historical record of how the design developed; the canonical content
> lives in the top-level [roles.md](../roles.md).
>
> For the current spec, read [documentation/roles.md](../roles.md).
> For the design conversation that produced it, this file remains.

---

**(Original status:)** brainstorming. The current binary-trust security
model ([trust.md](../trust.md)) isn't satisfying yet. This doc sketches
a role-based alternative. Nothing here is committed — it's a draft to
react to.

---

## Motivation

The existing model classifies every value and every running function
as either *trusted* or *untrusted*, based on its source. The model
works but feels too coarse:

- One binary tier means everything either gets the keys to the kingdom
  or none of them. Real systems have many sources with different risk
  profiles.
- "Trusted" as a global property doesn't capture relationships between
  different sources.
- The escalation mechanism (`%chain.trust`) is the only granular tool,
  and it has to be invoked at every site where untrusted data flows
  through a trusted sink. That's a lot of friction.

This brainstorm explores replacing binary trust with **roles**.

---

## Core Concept

The security model centers on **roles**. **Every object is owned by a
role** — functions, data values, classes, instances, everything. Code
itself isn't owned; the code that's currently executing belongs to a
function-object, and that function-object's owning role *is* the
current role. Trust is a directed relationship between roles, not a
global property of code or data.

Key properties:

- **Code runs under exactly one role at a time.** Not zero, not two —
  one. Switching to another role is a discrete operation (mechanics
  TBD).
- **All other roles are untrusted by the current role by default.**
  From inside role A, every other role B, C, D, ... is suspicious
  until A explicitly trusts them.
- **A "security boundary" is now any call into code the current role
  doesn't own.** The framework's checks happen at that boundary, based
  on the current role's trust relationships.

There is **no global "trusted" tier**. Trust is per-role-pair, decided
by each role on its own terms.

### Role transitions

**Functions always run as their owner.** When code running under role
A calls a function-object owned by role B, that function runs as B
for the duration of the call. When the function returns, control
returns to A.

The transition is implicit in the call. There is no separate syntax
or system method for changing roles — calling a function owned by a
different role *is* the transition. `%role` inside the called
function returns B; back in the caller, it returns A.

This means a less-trusted role cannot "elevate" itself by trickery.
The only way for code to be running as role B is to be executing
inside a B-owned function-object. Calling into B's code doesn't make
the *caller* B; only the called function runs as B.

**`%chain` is wiped at role boundaries.** When code in role A calls
into role B, B starts with a clean `%chain` — A's chain entries are
not visible to B. Symmetric on the way back: B's chain writes don't
reach A. Closes the ambient-state side channel; roles communicate via
**params** if they need to pass anything across the boundary.

A's chain is preserved across the call from A's perspective — when B
returns and execution resumes in A, A's chain is exactly what it was
before the call. The wipe is bounded to the cross-role function's
lifetime; A doesn't lose state because it called B.

### What is NOT checked at a boundary

**Anything with access to an object can call any of its methods. Full
stop.** The role of the caller does not gate which methods can be
invoked. If A passes an object with a `delete_database` method into
B's function, B can call `delete_database`. The runtime won't stop it.

The boundary crossing wipes `%chain`, transitions execution, and
passes params — but it does **not** filter or gate operations on the
objects that flow across. Method calls on passed objects are
unrestricted.

The developer's job:

- Decide what to expose by deciding what to pass.
- To give a callee a restricted view, **wrap the object in a jail**
  that exposes only the methods you want them to have.

This is why the framework provides a lightweight way to create a
jail on any object — `$foo.object.jail(:method, :method)`. Given the
"caller must decide what to expose" rule, narrowing has to be cheap
or developers won't do it. Example:

```
$foo = &some_fancy_object()
$jail = $foo.object.jail(:safe_method, :harmless_method)
&untrusted_function $jail   # callee can only call safe_method or harmless_method
```

`$foo` retains its full surface for the caller; `$jail` exposes only
the listed methods. The general "Jail (Object Firewall)" mechanism in
[kscript-runtime.md](../kscript/kscript-runtime.md) covers this; the
dirjail-specific rules above are one specialization. The same pattern
applies to any object the developer wants to restrict before handing
it across a role boundary.

This is consistent with the framework's "no nanny code" principle.
The runtime won't second-guess what you pass to another role; that
choice is yours, and the consequences are yours. The framework's job
is to make the narrowing easy — `.object.jail(...)` is one
expression. Wrap with care.

### `%chain.isolate do ... end`

A voluntary, inline version of the cross-role chain wipe. Lets code
drop its own ambient context for a bounded block:

```
%chain.isolate do
    # %chain is wiped here
    # a fresh ephemeral role is in effect
    # %role returns the new role, not the outer role
end
# back to the outer role with its original %chain restored
```

Mechanics:

- **A fresh ephemeral role is created for the block's duration.**
  Inside, `%role` returns that fresh role. The role goes away when the
  block returns. (Per the broader "proliferate roles now, consolidate
  later" stance, this is a unique role per call. A shared `sandbox`
  role is a possible consolidation later.)
- **`%chain` is wiped inside the block.** No chain entries from the
  outer role are visible. The block writes to its own (initially
  empty) chain.
- **Outer scope is still captured.** The block is a closure, so
  outer-scope variables are still in scope. `%chain.isolate` isolates
  the *chain*, not the closure's captured locals. To prevent
  variable access too, the developer would have to deliberately pass
  values in or out rather than relying on closure capture.
- **System methods still work.** `%kiera`, `%now`, etc. remain
  available. The isolation is chain-and-role, not full capability.
- **Original chain restored on return.** When the block ends, the
  outer role takes over again with its original `%chain` intact.

Use cases:

- Defensive coding around risky operations ("about to process
  untrusted input — drop my ambient context first").
- Bounded sandbox for a small piece of code without defining a
  separate function in another module.
- Reduced blast radius for unintended chain reads inside the block.

Worth noting: cross-role function calls already provide this
naturally — calling B's function wipes the chain. `%chain.isolate`
is the version where you don't need to define or call another
function; you just want a clean slate inline.

### Exceptions and alarms

Two error categories with distinct behaviors:

**Regular exceptions** travel up the call stack via normal unwinding.
Any `catch` handler along the way can intercept. If uncaught, the
exception reaches the engine and becomes an uncaught-exception error
(exact engine-side handling TBD). Any code — including untrusted
code — can raise exceptions that travel all the way up; the chain
unwinds gracefully via `try/finally`-style cleanup along the way.

**Alarms** are always fatal. They go directly to the engine — **no
unwinding**, no `finally` blocks, no cleanup, no catch handlers from
KScript code. The runtime bails to the engine immediately, and the
engine handles termination (logging, process exit, whatever the engine
decides — exact behavior TBD).

The model:

- Use regular exceptions for anything user code might want to recover
  from. Standard `try/catch` semantics with normal unwinding.
- Use alarms for situations where the program is in serious trouble
  and recovery isn't appropriate. Alarms are the engine's hard stop.

Things that raise alarms:

- A sink refused an operation due to role mismatch
- An engine-enforced limit was breached (e.g., `%timeout`)
- Anything where the engine specifically wants to ensure no KScript
  code — including cleanup code — can interfere with the failure

The "no unwinding" rule is what makes alarms different from
exceptions in kind. Untrusted code cannot gain control during the
failure by hooking into `finally` blocks or catch handlers. The
engine takes over directly.

A more elaborate model where alarms can be caught at role boundaries
(via `%chain`-installed catchers that convert them to regular
exceptions) was considered and dropped from current production. The
deferred design is preserved in
[catchable-alarms.md](catchable-alarms.md) in case it's worth
revisiting later.

---

## The `%role` System Method

`%role` returns the role the current code is running under. Same shape
as `%chain`, `%kiera`, `%self` — a system method, always available,
and context aware.

```
$current = %role    # the role currently in effect
```

`%role` was sketched earlier as a chain-scoped identity/context store
in [plusplus/roles.md](plusplus/roles.md). In this brainstorm `%role`
is promoted from "identity" to *the security primitive itself*.

---

## Engine Startup: Initial Roles

When the engine launches a KScript instance, it wires up all the roles
necessary for the objects it's about to pass into the runtime. At
minimum:

- **`user`** — the role the program's own code runs as. Bootstrap
  state: every KScript program begins life here unless something
  explicitly transitions it elsewhere.
- **`clock`** — owns the time-related objects the engine provides
  (e.g., what `%now` returns). User code using a clock value crosses
  into the clock role for the duration of any method call on it.
- **`randomizer`** — owns the random-source objects the engine
  provides. Same shape as `clock`.
- **`utils`** — owns everything that comes out of `%utils`, the
  engine-granted convenience-utility capability (`%utils.now`,
  `%utils.rand.uuid`, etc.). One role for the whole `%utils`
  namespace, regardless of which specific method was called.

Engines will typically wire up more depending on what they're
exposing: roles for STDIN, env vars, CLI args, the kiera, each
dirjail, network faucets, etc. The minimum above is what every
engine has; the rest varies by engine configuration.

Role nicknames like `user`, `clock`, `randomizer` are informal.
Formal reference syntax is TBD.

---

## External Data Has an Owning Role

The Kiera vocabulary for source-side resources is **faucet** — any
resource through which objects are pulled into the runtime. Examples:
a filesystem API/jail, a database connection, an HTTP client, a
socket, an IPC channel. (Complement: a **sink** is an operation that
consumes a value in a security-sensitive way — filesystem write, eval,
query send, network output.)

**Faucets are the only way to pull objects into the runtime.** There
are no backdoors, no implicit injection paths, no FFI escapes — every
external value entering KScript comes through some faucet, and the
faucet's role is what owns the value.

When KScript pulls a value through a faucet — a database row, a
network response, a file's contents, a remote-fetched function — the
runtime tags that value with a role that *owns* it. The owning role is
typically **created on the fly** for the specific faucet rather than
being pre-registered.

Examples (sketched):

- Query against database `D` → returned values are owned by a role for
  `D`.
- HTTP fetch from a remote endpoint → returned values are owned by a
  role for that endpoint.
- File read through a jail rooted at some directory → contents are
  owned by a role for that source.

The `user` role pulling data from database D ends up holding values
that are owned by role-D — not by `user`. User-role code can *hold* the
values but doesn't *own* them. Any operation that crosses a security
boundary (passing to a sink, calling a method, sending elsewhere) is
governed by `user`'s trust relationship to role-D.

This generalizes the existing source-tag mechanism: instead of a string
source-tag plus an engine-mapped trust level, the source itself IS a
role, and the role carries the security semantics directly.

### Filesystem-specific rules (concrete instance)

The filesystem is the worked-out example of the faucet model. The
filesystem-flavored jail is called a **dirjail** — to distinguish it
from the broader "jail" concept (a capability-restricting wrapper
around any object; see kscript-runtime.md's "Jail (Object Firewall)"
section). Dirjails are jails specifically around directory objects.

The rules:

- **A dirjail is barely more than a directory object that won't tell
  you where it lives.** Same methods, same navigation, same
  permissions — just a hidden real path. The role machinery is really
  about directory objects in general; "dirjail" marks the directory
  the engine introduces as a faucet boundary.
- **Dirjails are the only filesystem faucets.** No filesystem access
  in KScript without a dirjail.
- **The engine creates and stamps the main dirjails with their own
  role — not `user`.** When the engine hands a dirjail to running
  code, it assigns the dirjail a distinct owner role (typically
  created for that specific dirjail). The dirjail is never owned by
  `user` (or by whatever role the receiving code is running under).
  If it were, every file pulled through the dirjail would be
  automatically owned by `user` and the faucet boundary would
  dissolve. User can choose to trust the dirjail's role (so it can
  do things with the data), but doesn't own the dirjail itself.
- **Files pulled through a dirjail are owned by the dirjail's owner
  role** (the engine's role for the source — `main-fs` or similar).
  Includes directory objects, file contents, anything coming out of
  the dirjail.
- **Subdirjails (derived via `.jail()`) are themselves owned by the
  deriver** — the deriver created the wrapper object, so the deriver
  owns it. But **the objects coming through the subdirjail are still
  owned by the source role**, not the deriver.
- **Subdirjail authority can never exceed the parent's** — operations
  route through the parent, which is engine-bounded.

The key principle: **ownership is per-object, and one object owning a
wrapper doesn't transfer ownership of what flows through that
wrapper**. `user` can hold a subdirjail object and pass it around as a
narrowed capability, but the files pulled through it retain their
source role. No laundering by derivation; provenance is preserved
naturally.

This principle generalizes beyond wrappers. **A container's role
applies to the container itself, not to what's inside it.** A hash
created by `user` code is user-owned, but a value owned by `main-fs`
placed into that hash retains its `main-fs` role. Reading the value
out gives back a `main-fs`-owned value, not a user-owned one. The
hash is one identity; its members are other identities, each with
their own role.

(This mirrors the Fiona DBMS design Miko worked out years ago — see
[fiona.md](fiona.md). In Fiona, the "object itself" lives in `hsa`
while "what it's connected to" lives in `relationships`. The role
model uses the same structural split: an object's role tags the
object's identity; the things it connects to have their own roles.)

To "claim" data into a different role would require an explicit
operation — TBD if that's even useful. Most code that wraps a faucet
just wants a narrower capability to hand to a callee, not to take
authority over the data.

The same principle extends to other faucet kinds. A derived
sub-faucet on a network connection, a derived database scope, etc. —
all the same shape: the wrapper is owned by whoever made it; the data
flowing through retains the source's role.

### Other faucets (sketch)

The model extends naturally to other faucet kinds. The same baseline
rule applies: **engine-supplied, has its own distinct role, data
pulled through it inherits that role**. Details for each specific
faucet kind are spec'd as the design progresses.

- **STDIN faucet.** When the engine introduces a STDIN object, the
  object has its own role (not `user`). Data read from STDIN is owned
  by the STDIN faucet's role.
- **Environment variables.** The env-vars faucet has its own role.
  Each value read from the environment is owned by that role.
- **Command-line arguments.** The CLI-args faucet has its own role.
  Each value read from `argv` (or whatever the engine names it) is
  owned by that role.
- **Network faucets.** Engine-granted, distinct role, responses
  pulled through are owned by the faucet's role. HTTP is the worked
  example so far; other protocols follow the same shape.
- **Other candidates** (not yet spec'd in role terms): subprocess
  output / pipes, `%kiera[UNS]` lookups, `%now` and PRNG sources,
  cross-role function arguments.

---

## Cross-Role Trust

A role can choose to **trust other roles**. Trust is:

- **Directed.** A trusting B does not imply B trusts A.
- **Per-pair.** A trusting B implies nothing about A trusting C, B
  trusting C, etc.
- **Optional.** No defaults. Two unrelated roles have no trust
  relationship until one explicitly declares one.

The framework supplies the *mechanism* for declaring and querying
trust; the *content* of any role's trust web is up to that role.

Details TBD: syntax for declaring trust, what trust actually grants
(call permission? data-passing permission? both?), revocation, runtime
adjustability.

---

## Open Questions

This section will drive the next round of design. Each item is genuinely
unsettled, not just hand-waving.

### How objects get their owning role

**Resolved.** Three rules:

- **External objects** (pulled through faucets): owned by the
  faucet's role. The system assigns the role when introducing the
  object into the runtime.
- **Internally-created objects** (functions, classes, instances,
  hashes, anything made by running code): owned by the role of the
  code that created them — i.e., the role currently executing at the
  moment of creation. A function defined inside role A's code is
  owned by A. An instance from `$class.new(...)` called from A is
  owned by A.
- **Engine-supplied built-ins** (stdlib, `%kiera`-resolved
  capabilities, etc.): assigned roles by the engine at startup,
  before any user code runs.

The engine itself has a role, but it stays under the hood — developers
don't reference it directly. It exists in the model the way the engine
exists in the runtime: bootstrap layer, mostly invisible.

Once assigned, an object's role is immutable. Objects move between
roles (passing values into a different-role function, returning
values to a different-role caller) but the value's owning role
follows the value; it doesn't change because the value's location
changed.

### Role transitions

**Resolved** — see "Role transitions" in the main body. Functions
always run as their owner; the transition is implicit on the call.
No explicit syntax needed; less-privileged code cannot elevate
itself.

### Cross-role trust mechanics

- Syntax for declaring "role A trusts role B."
- Where the declaration lives — in the role's definition, in `%chain`,
  in some registry, in code at runtime.
- What "trust" grants — call permission, data-passing permission,
  resource access, all of the above.
- Transitivity — almost certainly not transitive (A→B→C doesn't imply
  A→C), but should be explicit.
- Revocation and scoping — can trust be temporary (block-scoped)?

### Owning-role propagation

- When a value owned by role D is used to produce a derived value (a
  substring, a hash containing it, a function-of-it), does the derived
  value also get tagged as owned by D? Multiple owning roles?
  Something else?
- This overlaps with [string-provenance.md](string-provenance.md).
  Worth aligning rather than designing in parallel.

### Granularity of source-derived roles

- One role per database? Per connection? Per query? Per record?
- Same question for network sources, file sources, etc.
- Trade-off: fewer roles = simpler reasoning, less precision; more
  roles = better isolation, larger runtime namespace.

**Role consolidation pass (revisit later).** As the design has
proceeded, roles have proliferated quickly — `user`, per-dirjail roles,
per-network-faucet roles, STDIN, env-vars, CLI-args, and counting. The
current direction is to keep proliferating and see how it shakes out.
Once the model is mostly worked out, take a deliberate pass to see
which roles can be **consolidated** without losing meaningful security
properties. Candidate consolidations:

- All filesystem faucets → one `fs` role.
- All network faucets → one `net` role.
- STDIN + env-vars + CLI-args → one `system-input` role.
- Engine-supplied capabilities → one `kiera` (or `engine`) role.

The goal of the consolidation pass: make the typical-program role
count tractable (maybe 4–8 instead of 15+) while preserving precision
where it actually matters. Granular per-source roles remain available
when a developer specifically wants them.

**For network faucets specifically**: the current default — "incoming
information is assigned to the role of the network faucet" — is
expected to suffice for most situations. A future idea worth exploring:
roles assigned based on the **UNS of the remote object** rather than
just the faucet. E.g., pulling from `https://example.com/api/users/123`
would yield values owned by a UNS-specific role rather than just the
faucet's role. Finer-grained, but adds runtime namespace pressure and
trust-web complexity. Bring up later — not for v1.

### Role lifecycle

- When a source becomes unreachable (db disconnected, endpoint deleted),
  what happens to its role?
- Garbage collection — when can the runtime drop a role?
- Persistence — does a role survive process restart? Probably not, but
  the values owned by such a role might be stored across restarts.

### Interaction with existing mechanisms

- `%chain.trust` — **removed.** The runtime override mechanism from
  the binary-trust model is gone. `%chain.isolate` exists for a
  different purpose (voluntary chain wipe + fresh role) rather than
  as a replacement.
- Jail permissions (filesystem read/write/execute) — how do these
  compose with roles? Likely roles cover the "who can do this"
  question; jails cover the "what bounded scope" question. But
  the composition needs spec'ing.
- Engine firewall rules — adapted to operate on roles instead of trust
  tags?
- [trusted-database-filtering.md](trusted-database-filtering.md) — the
  laundering-vector concern. Probably rephrased: writes from role A
  to a database whose owning role is B are gated by A's trust of B (or
  the other direction).

### Security-boundary semantics

- What does the runtime *do* when crossing a boundary the current role
  doesn't trust?
  - Refuse the operation outright (hard block)?
  - Provide a `use_path`-style explicit override (negotiable
    roadblock)?
  - Sanitize / filter values automatically (unlikely; too magical)?

### Sink-side security

The discussion so far has focused on what comes *in* through faucets
(role-tagging of pulled values, source-side checks). The sink side —
sending information *out* — has its own security implications that
haven't been explored yet:

- When code in role A sends a value through a sink, the runtime
  presumably checks the value's owning role against the sink's role
  (and the role of whoever owns the sink object). What's that check?
- Outbound HTTP requests with bodies, database INSERT/UPDATE writes,
  network sends, filesystem writes — each carries a value out the
  door. Who's responsible if the wrong role's data ends up
  somewhere it shouldn't?
- The [trusted-database-filtering.md](trusted-database-filtering.md)
  idea is a specific instance: writes to a trusted database from
  untrusted code. Generalizes to "writes to any sink from any role"
  in the role model.
- An HTTP faucet is also a sink (request bodies go out). Both
  directions need to play under the model — pulling in is one set of
  checks, pushing out is another.

To explore in a future round.
- Same question, different framing: is it an exception, a return-null,
  a forced developer choice?

### Default trust setup at startup

- Does the engine establish any default trust at boot — e.g., `user`
  trusts the stdlib's role, or trusts certain built-in capability
  sources?
- Or strict cold-start: no trust until the developer wires it
  themselves?
- Probably some defaults are necessary or the program can't function;
  the question is which.

---

## Related Existing Notes

- [trust.md](../trust.md) — the current binary-trust model that this
  brainstorm aims to replace.
- [plusplus/roles.md](plusplus/roles.md) — earlier draft of `%role` as
  a chain-scoped identity/context store, explicitly *not* a permission
  system. This brainstorm reuses the `%role` shape but promotes it to
  the security primitive.
- [string-provenance.md](string-provenance.md) — deferred idea for
  fine-grained string provenance. The role model would subsume or
  complement this.
- [trusted-database-filtering.md](trusted-database-filtering.md) —
  becomes more direct under per-source owning roles.
- [firewall.md](firewall.md) — engine firewall rules will likely be
  rephrased in role terms.
