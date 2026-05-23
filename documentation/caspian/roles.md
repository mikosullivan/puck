# Roles

~~~json
{"vibecode": {
    "section": "overview",
    "role": "the official security model for Caspian: every object owned by a role, code runs as the owning role of the function-object executing it, security boundaries are cross-role calls, faucets are the only way to pull objects in, jails are the explicit narrowing mechanism",
    "key_concepts": ["one_role_per_executing_function", "objects_owned_by_role", "boundary_is_cross_role_call",
        "chain_wiped_at_boundaries", "alarms_fatal_no_unwinding", "faucets_only_inbound_path",
        "jails_explicit_narrowing", "no_method_level_gating"],
    "supersedes": ["binary_trust_model", "%chain.trust", "%chain.allow_abort_escalation",
        "%chain.allow_catch_security_exceptions"]
}}
~~~

The role model is Caspian's security model. **Every object is owned by a
role**: functions, data values, classes, instances, everything. Code itself
isn't owned; the code currently executing belongs to a function-object, and
that function-object's owning role is the current role. Trust is a directed
relationship between roles, not a global property of code or data.

---

<a id="motivation"></a>
## Motivation

This role design supersedes an earlier binary trust/untrust model.
That model was found to be insufficient fore security purposes.
The previous model classified every value and every running function as
either *trusted* or *untrusted*, based on its source. The model worked but
was too coarse:

- One binary tier meant everything either got the keys to the kingdom or
  none of them. Real systems have many sources with different risk
  profiles.
- "Trusted" as a global property didn't capture relationships between
  different sources.
- The escalation mechanism (`%chain.trust`) had to be invoked at every
  site where untrusted data flowed through a trusted sink.

The role model replaces binary trust with **roles** — a more granular
identity-and-authority system where each source of code or data is its
own role, and cross-role interaction is the security-relevant event.

---

<a id="core-concept"></a>
## Core Concept

~~~json
{"vibecode": {
    "section": "core_concept",
    "key_properties": ["code_runs_under_exactly_one_role", "all_other_roles_untrusted_by_default",
        "boundary_equals_cross_role_call", "no_global_trusted_tier"]
}}
~~~

Key properties:

- **Code runs under exactly one role at a time.** Not zero, not two — one.
  Switching to another role is a discrete operation (described in "Role
  Transitions" below).
- **All other roles are untrusted by the current role by default.** From
  inside role A, every other role B, C, D, ... is suspicious until A
  explicitly trusts them.
- **A "security boundary" is any call into code the current role doesn't
  own.** That call is where the framework's security model engages.

There is **no global "trusted" tier**. Trust is per-role-pair, decided by
each role on its own terms.

---

<a id="the-role-system-method"></a>
## The `%role` System Method

~~~json
{"vibecode": {
    "section": "role_system_method",
    "method": "%role",
    "returns": "current_role"
}}
~~~

`%role` returns the role the current code is running under. Same shape as
`%chain`, `%puck`, `%self` — a system method, always available, context
aware.

```
$current = %role    # the role currently in effect
```

---

<a id="engine-startup-initial-roles"></a>
## Engine Startup: Initial Roles

~~~json
{"vibecode": {
    "section": "engine_startup_roles",
    "minimum": ["user", "stdlib", "clock", "randomizer", "utils"],
    "engine_dependent": ["directory jails", "network_faucets", "stdin", "env_vars", "cli_args", "puck"]
}}
~~~

When the engine launches a Caspian instance, it wires up all the roles
necessary for the objects it's about to pass into the runtime. At minimum:

- **`user`** — the role the program's own code runs as. Bootstrap state:
  every Caspian program begins life here unless something explicitly
  transitions it elsewhere.
- **`stdlib`** — owns the built-in classes the engine ships (string, hash,
  array, number, etc.) and their methods. One role for the whole built-in
  type system, regardless of which specific class a value belongs to. When
  user code calls a method on a built-in value (`'hello'.to_string`,
  `[1,2,3].length`, `{a: 1}.keys`), the dispatcher transitions into
  `stdlib` for the duration of the method call. Same pattern as `utils`
  owning the `%utils` namespace.
- **`clock`** — owns the time-related objects the engine provides (e.g.,
  what `%now` returns). User code using a clock value crosses into the
  clock role for the duration of any method call on it.
- **`randomizer`** — owns the random-source objects the engine provides.
  Same shape as `clock`.
- **`utils`** — owns everything that comes out of `%utils`, the
  engine-granted convenience-utility capability (`%utils.now`,
  `%utils.rand.uuid`, etc.). One role for the whole `%utils` namespace,
  regardless of which specific method was called.

Engines will typically wire up more depending on what they're exposing:
roles for STDIN, env vars, CLI args, the puck, each directory jail, each
network faucet, etc. The minimum above is what every engine has; the rest
varies by engine configuration.

Role nicknames like `user`, `clock`, `randomizer` are informal. Formal
reference syntax is TBD.

---

<a id="role-transitions"></a>
## Role Transitions

~~~json
{"vibecode": {
    "section": "role_transitions",
    "rule": "functions_always_run_as_their_owner",
    "transition_is_implicit_on_call": true,
    "elevation_via_trickery_is_impossible": true,
    "chain_wiped_at_boundary": true
}}
~~~

**Functions always run as their owner.** When code running under role A
calls a function-object owned by role B, that function runs as B for the
duration of the call. When the function returns, control returns to A.

The transition is implicit in the call. There is no separate syntax or
system method for changing roles — calling a function owned by a
different role *is* the transition. `%role` inside the called function
returns B; back in the caller, it returns A.

This means a less-trusted role cannot "elevate" itself by trickery. The
only way for code to be running as role B is to be executing inside a
B-owned function-object. Calling into B's code doesn't make the *caller*
B; only the called function runs as B.

**`%chain` is wiped at role boundaries.** When code in role A calls into
role B, B starts with a clean `%chain` — A's chain entries are not
visible to B. Symmetric on the way back: B's chain writes don't reach A.
Closes the ambient-state side channel; roles communicate via **params**
if they need to pass anything across the boundary.

A's chain is preserved across the call from A's perspective — when B
returns and execution resumes in A, A's chain is exactly what it was
before the call. The wipe is bounded to the cross-role function's
lifetime; A doesn't lose state because it called B.

---

<a id="what-is-not-checked-at-a-boundary"></a>
## What Is NOT Checked at a Boundary

~~~json
{"vibecode": {
    "section": "no_method_level_gating",
    "rule": "anything_with_object_access_can_call_any_method",
    "narrowing_mechanism": "wrap_in_jail_before_passing"
}}
~~~

**Anything with access to an object can call any of its methods. Full
stop.** The role of the caller does not gate which methods can be
invoked. If A passes an object with a `delete_database` method into B's
function, B can call `delete_database`. The runtime won't stop it.

The boundary crossing wipes `%chain`, transitions execution, and passes
params — but it does **not** filter or gate operations on the objects
that flow across. Method calls on passed objects are unrestricted.

The developer's job:

- Decide what to expose by deciding what to pass.
- To give a callee a restricted view, **wrap the object in a jail** that
  exposes only the methods you want them to have.

This is why the framework provides a lightweight way to create a jail on
any object — `$foo.object.jail(:method, :method)`. Given the
"caller must decide what to expose" rule, narrowing has to be cheap or
developers won't do it. Example:

```
$foo = &some_fancy_object()
$jail = $foo.object.jail(:safe_method, :harmless_method)
&untrusted_function $jail   # callee can only call safe_method or harmless_method
```

`$foo` retains its full surface for the caller; `$jail` exposes only the
listed methods. The general "Jail (Object Firewall)" mechanism in
[caspian/caspian-runtime.md](lucy/lucy.md) covers this;
the directory jail rules below are one specialization. The same pattern applies
to any object the developer wants to restrict before handing it across a
role boundary.

This is consistent with the framework's "no nanny code" principle. The
runtime won't second-guess what you pass to another role; that choice is
yours, and the consequences are yours. The framework's job is to make
the narrowing easy.

---

<a id="chainisolate-do-end"></a>
## `%chain.isolate do ... end`

~~~json
{"vibecode": {
    "section": "chain_isolate",
    "method": "%chain.isolate",
    "form": "do_block",
    "creates": "fresh_ephemeral_role_for_block_duration",
    "wipes": "%chain"
}}
~~~

A voluntary, inline version of the cross-role chain wipe. Lets code drop
its own ambient context for a bounded block:

```
%chain.isolate do
    # %chain is wiped here
    # a fresh ephemeral role is in effect
    # %role returns the new role, not the outer role
end
# back to the outer role with its original %chain restored
```

Mechanics:

- **A fresh ephemeral role is created for the block's duration.** Inside,
  `%role` returns that fresh role. The role goes away when the block
  returns.
- **`%chain` is wiped inside the block.** No chain entries from the outer
  role are visible. The block writes to its own (initially empty) chain.
- **Outer scope is still captured.** The block is a closure, so
  outer-scope variables are still in scope. `%chain.isolate` isolates
  the *chain*, not the closure's captured locals.
- **System methods still work.** `%puck`, `%now`, etc. remain available.
  The isolation is chain-and-role, not full capability.
- **Original chain restored on return.** When the block ends, the outer
  role takes over again with its original `%chain` intact.

Use cases:

- Defensive coding around risky operations ("about to process untrusted
  input — drop my ambient context first").
- Bounded sandbox for a small piece of code without defining a separate
  function in another module.
- Reduced blast radius for unintended chain reads inside the block.

`%chain.isolate` is the inline-block version of what cross-role function
calls already provide naturally — calling B's function wipes the chain.
Use `isolate` when you want a clean slate without defining or calling
another function.

---

<a id="exceptions-and-alarms"></a>
## Exceptions and Alarms

~~~json
{"vibecode": {
    "section": "exceptions_and_alarms",
    "regular_exceptions": "travel_up_stack_catchable_normal_unwinding",
    "alarms": "fatal_no_unwinding_go_straight_to_engine"
}}
~~~

Two error categories with distinct behaviors:

**Regular exceptions** travel up the call stack via normal unwinding. Any
`catch` handler along the way can intercept. If uncaught, the exception
reaches the engine and becomes an uncaught-exception error (exact
engine-side handling TBD). Any code — including untrusted code — can
raise exceptions that travel all the way up; the chain unwinds gracefully
via `try/finally`-style cleanup along the way.

**Alarms** are always fatal. They go directly to the engine — **no
unwinding**, no `finally` blocks, no cleanup, no catch handlers from
Caspian code. The runtime bails to the engine immediately, and the engine
handles termination (logging, process exit, whatever the engine decides
— exact behavior TBD).

The model:

- Use regular exceptions for anything user code might want to recover
  from. Standard `try/catch` semantics with normal unwinding.
- Use alarms for situations where the program is in serious trouble and
  recovery isn't appropriate. Alarms are the engine's hard stop.

Things that raise alarms:

- A sink refused an operation due to role mismatch
- An engine-enforced limit was breached (e.g., `%utils.timeout`)
- Anything where the engine specifically wants to ensure no Caspian code
  — including cleanup code — can interfere with the failure

The "no unwinding" rule is what makes alarms different from exceptions in
kind. Untrusted code cannot gain control during the failure by hooking
into `finally` blocks or catch handlers. The engine takes over directly.

A more elaborate model where alarms can be caught at role boundaries was
considered and dropped — preserved in
[ideas/catchable-alarms.md](../ideas/catchable-alarms.md) for possible
revisitation.

---

<a id="how-objects-get-their-owning-role"></a>
## How Objects Get Their Owning Role

~~~json
{"vibecode": {
    "section": "object_ownership_assignment",
    "external_objects": "owned_by_faucets_role",
    "internal_objects": "owned_by_creating_role",
    "engine_builtins": "owned_by_engine_assigned_role"
}}
~~~

Three rules:

- **External objects** (pulled through faucets): owned by the faucet's
  role. The system assigns the role when introducing the object into the
  runtime.
- **Internally-created objects** (functions, classes, instances, hashes,
  anything made by running code): owned by the role of the code that
  created them — i.e., the role currently executing at the moment of
  creation. A function defined inside role A's code is owned by A. An
  instance from `$class.new(...)` called from A is owned by A.
- **Engine-supplied built-ins** (stdlib, `%puck`-resolved capabilities,
  etc.): assigned roles by the engine at startup, before any user code
  runs.

The engine itself has a role, but it stays under the hood — developers
don't reference it directly. Bootstrap layer, mostly invisible.

**Once assigned, an object's role is immutable.** Objects move between
roles (passing values into a different-role function, returning values
to a different-role caller) but the value's owning role follows the
value; it doesn't change because the value's location changed.

---

<a id="faucets"></a>
## Faucets

~~~json
{"vibecode": {
    "section": "faucets",
    "definition": "any_resource_through_which_objects_enter_the_runtime",
    "rule": "faucets_are_the_only_inbound_path",
    "examples": ["filesystem_directory_jail", "database_connection", "http_client", "stdin", "env_vars",
        "cli_args"]
}}
~~~

The Puck vocabulary for source-side resources is **faucet** — any
resource through which objects are pulled into the runtime. Examples: a
filesystem directory jail, a database connection, an HTTP client, a socket, an
IPC channel.

(Complement: a **sink** is an operation that consumes a value in a
security-sensitive way — filesystem write, eval, query send, network
output.)

**Faucets are the only way to pull objects into the runtime.** There are
no backdoors, no implicit injection paths, no FFI escapes — every
external value entering Caspian comes through some faucet, and the
faucet's role is what owns the value.

When Caspian pulls a value through a faucet, the runtime tags that value
with a role that *owns* it. The owning role is typically created on the
fly for the specific faucet rather than being pre-registered.

The `user` role pulling data from database D ends up holding values that
are owned by role-D — not by `user`. User-role code can *hold* the
values but doesn't *own* them.

<a id="filesystem-directory-jails"></a>
### Filesystem: directory jails

~~~json
{"vibecode": {
    "section": "directory_jails",
    "definition": "directory_object_that_hides_its_real_path",
    "rule": "directory_jails_are_only_filesystem_faucets",
    "subdirectory_jail_ownership": "deriver_owns_wrapper_objects_through_still_have_source_role"
}}
~~~

The filesystem-flavored jail is called a **directory jail** — to distinguish it
from the broader "jail" concept (a capability-restricting wrapper around
any object). Directory jails are jails specifically around directory objects.

The rules:

- **A directory jail is barely more than a directory object that won't tell you
  where it lives.** Same methods, same navigation, same permissions —
  just a hidden real path.
- **Directory jails are the only filesystem faucets.** No filesystem access in
  Caspian without a directory jail.
- **The engine creates and stamps the main directory jails with their own role —
  not `user`.** Each engine-introduced directory jail has its own owner role,
  distinct from `user`. User can choose to trust the directory jail's role but
  doesn't own the directory jail itself.
- **Files pulled through a directory jail are owned by the directory jail's owner
  role.** Includes directory objects, file contents, anything coming out
  of the directory jail.
- **Subdirectory jails (derived via `.jail()`) are themselves owned by the
  deriver** — the deriver created the wrapper object, so the deriver
  owns it. But **the objects coming through the subdirectory jail are still
  owned by the source role**, not the deriver.
- **Subdirectory jail authority can never exceed the parent's** — operations
  route through the parent, which is engine-bounded.

The key principle: **ownership is per-object, and one object owning a
wrapper doesn't transfer ownership of what flows through that wrapper**.
A user-owned subdirectory jail can hand back files that are still source-owned.
No laundering by derivation; provenance is preserved naturally.

This principle generalizes: **a container's role applies to the
container itself, not to what's inside it.** A hash created by `user`
code is user-owned, but a value owned by `main-fs` placed into that hash
retains its `main-fs` role. Reading the value out gives back a
`main-fs`-owned value, not a user-owned one. The hash is one identity;
its members are other identities, each with their own role.

(This mirrors the Fiona DBMS design Miko worked out years ago — see
[ideas/fiona.md](../ideas/fiona.md). In Fiona, the "object itself" lives
in `hsa` while "what it's connected to" lives in `relationships`. The
role model uses the same structural split.)

<a id="other-faucets"></a>
### Other faucets

The model extends naturally to other faucet kinds. The same baseline
rule applies: **engine-supplied, has its own distinct role, data pulled
through it inherits that role**.

- **STDIN faucet.** Engine-introduced STDIN object with its own role.
  Data read from STDIN is owned by that role.
  **STDIN is not ambient** — it does not live on `%chain` and is
  not a system method (no `%stdin`). The engine hands the script
  a STDIN object at bootstrap; functions that need it must
  receive it as an explicit parameter. A function not given the
  object has no way to read STDIN — there's no side channel to
  reach through. This is capability-style security: passing the
  object grants access, not passing it denies access.
- **Environment variables.** Env-vars faucet has its own role. Each
  value read from the environment is owned by that role.
- **Command-line arguments.** CLI-args faucet has its own role. Each
  value read from `argv` is owned by that role.
- **Network faucets.** Engine-granted, distinct role, responses pulled
  through are owned by the faucet's role. HTTP is the worked example so
  far; other protocols follow the same shape.
- **Puck.** See [puck.md](../puck/puck.md) for the full puck model;
  internally a puck holds getters, which hold faucets, with per-getter
  roles.

---

<a id="cross-role-trust"></a>
## Cross-Role Trust

~~~json
{"vibecode": {
    "section": "cross_role_trust",
    "directed": true,
    "per_pair": true,
    "optional": true,
    "details_tbd": true
}}
~~~

A role can choose to **trust other roles**. Trust is:

- **Directed.** A trusting B does not imply B trusts A.
- **Per-pair.** A trusting B implies nothing about A trusting C, B
  trusting C, etc.
- **Optional.** No defaults. Two unrelated roles have no trust
  relationship until one explicitly declares one.

The framework supplies the *mechanism* for declaring and querying trust;
the *content* of any role's trust web is up to that role.

Details TBD: syntax for declaring trust, what trust actually grants,
revocation, runtime adjustability.

---

<a id="open-questions"></a>
## Open Questions

The model is solid enough to adopt; these are refinements within an
established framework, not blockers.

<a id="cross-role-trust-mechanics"></a>
### Cross-role trust mechanics

- Syntax for declaring "role A trusts role B."
- Where the declaration lives — in the role's definition, in `%chain`,
  in some registry, in code at runtime.
- What "trust" grants — call permission, data-passing permission,
  resource access, all of the above.
- Transitivity — almost certainly not transitive (A→B→C doesn't imply
  A→C), but should be explicit.
- Revocation and scoping — can trust be temporary (block-scoped)?

<a id="owning-role-propagation"></a>
### Owning-role propagation

- When a value owned by role D is used to produce a derived value (a
  substring, a hash containing it, a function-of-it), does the derived
  value also get tagged as owned by D?
- This overlaps with
  [ideas/string-provenance.md](../ideas/security/string-provenance.md). Worth
  aligning rather than designing in parallel.

<a id="granularity-of-source-derived-roles"></a>
### Granularity of source-derived roles

- One role per database? Per connection? Per query? Per record?
- Same question for network sources, file sources, etc.
- Trade-off: fewer roles = simpler reasoning, less precision; more
  roles = better isolation, larger runtime namespace.

**Role consolidation pass (revisit later).** As the design has proceeded,
roles have proliferated — `user`, per-directory jail roles, per-network-faucet
roles, STDIN, env-vars, CLI-args, and counting. The current direction is
to keep proliferating; once the model has been used in practice, take a
deliberate pass to see which roles can be consolidated without losing
meaningful security properties. Candidate consolidations:

- All filesystem faucets → one `fs` role.
- All network faucets → one `net` role.
- STDIN + env-vars + CLI-args → one `system-input` role.
- Engine-supplied capabilities → one `puck` (or `engine`) role.

<a id="role-lifecycle"></a>
### Role lifecycle

- When a source becomes unreachable (db disconnected, endpoint deleted),
  what happens to its role?
- Garbage collection — when can the runtime drop a role?
- Persistence — does a role survive process restart? Probably not, but
  the values owned by such a role might be stored across restarts.

<a id="interaction-with-existing-mechanisms"></a>
### Interaction with existing mechanisms

- Jail permissions (filesystem read/write/execute) — roles cover the
  "who can do this" question; jails cover the "what bounded scope"
  question. Composition needs spec'ing.
- Engine firewall rules — adapted to operate on roles instead of trust
  tags.
- [ideas/trusted-database-filtering.md](../ideas/security/trusted-database-filtering.md)
  — the laundering-vector concern. Probably rephrased in role terms:
  writes from role A to a database whose owning role is B are gated by
  A's trust of B.

<a id="sink-side-security"></a>
### Sink-side security

The model so far focuses on what comes *in* through faucets (role-tagging
of pulled values, source-side semantics). The sink side — sending
information *out* — has its own implications:

- When code in role A sends a value through a sink, the runtime
  presumably checks the value's owning role against the sink's role.
  What's that check?
- Outbound HTTP requests with bodies, database INSERT/UPDATE writes,
  network sends, filesystem writes — each carries a value out the door.
- An HTTP faucet is also a sink (request bodies go out). Both directions
  need to play under the model.

To explore in a future round.

<a id="default-trust-setup-at-startup"></a>
### Default trust setup at startup

- Does the engine establish any default trust at boot — e.g., `user`
  trusts the stdlib's role, or trusts certain built-in capability
  sources?
- Or strict cold-start: no trust until the developer wires it themselves?

---

<a id="related-documents"></a>
## Related Documents

- [puck.md](../puck/puck.md) — the puck object model, which builds on role
  concepts (per-getter roles, version windows, etc.).
- [ideas/catchable-alarms.md](../ideas/catchable-alarms.md) — preserved
  alternate design where alarms could be caught at role boundaries.
- [ideas/plusplus/roles.md](../ideas/plusplus/roles.md) — earlier draft of
  `%role` as a chain-scoped identity/context store, explicitly *not* a
  permission system. The role model reuses the `%role` shape but
  promotes it to the security primitive.
- [ideas/string-provenance.md](../ideas/security/string-provenance.md) — deferred
  idea for fine-grained string provenance.
- [ideas/trusted-database-filtering.md](../ideas/security/trusted-database-filtering.md)
  — becomes more direct under per-source owning roles.
- [ideas/firewall.md](../ideas/security/firewall.md) — engine firewall rules will
  be rephrased in role terms.
- [ideas/fiona.md](../ideas/fiona.md) — the DBMS design that inspired the
  "container vs. contents" ownership principle.
