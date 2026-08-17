# `%amber`

~~~vibecode
{"vibecode": {
	"doc": "requirements_global_amber",
	"role": "spec for %amber — Caspian's ambient-hash surface. Named namespaces (keyed by domain / URL strings the author controls) initialized per-frame via %amber.init; visible to descendants in the same role; hidden across role boundaries unless explicitly granted per-hop. Built on the aggregate-hash primitive. Operations: .init (plain and block forms), subscript access %amber['name'], .clear (own-frame-and-down visibility clear, plain and block forms), .remove (single-namespace visibility clear), .grant (cross-role-boundary grant of a specific namespace with read/write permission arrays), .has_key? (pure query, never raises). Namespace names MUST be domain-shaped strings (Java-package / iOS-bundle-ID convention).",
	"audience": "Caspian programmers using ambient context; engine implementers building the runtime"
}}
~~~

`%amber` is a top-level global providing ambient key-value hash storage. Named namespaces (keyed by domain / URL strings the author controls) are initialized per-frame; descendants in the same role see the namespace as the same hash; role boundaries hide it unless explicitly granted. Built on the [aggregate-hash primitive](https://puck.uno/requirements/lua/aggregate-hash) — same primitive that powers scope resolution and other downward-inheriting state.

User-facing background: [documentation/amber](https://puck.uno/documentation/amber) motivates the concept, positions it against prior art in other languages (Common Lisp specials, Racket parameters, Python contextvars, etc.), and describes typical use cases.

## Aggregate-hash mechanics

Every operation on `%amber` translates directly to an aggregate-hash operation on the current frame's amber layer:

- **`.init(name)`** — adds a new namespace-slot entry to the current frame's amber layer.
- **`%amber['name']`** — walks the aggregate from the current frame back through ancestors, returns the hash reference from the first frame's-layer that has `name`. That reference is what reads and writes go through.
- **Writing `%amber['name']['key'] = val`** — mutates the resolved hash directly. Anyone with a reference to it (ancestors that init'd it, descendants that inherited it) sees the change. Bidirectional within the aggregate-walk range.
- **`%amber['name'].remove`** — adds a tombstone for `name` to the current frame's amber layer. The walk stops there for that name; ancestors' `name` is invisible until this frame exits.
- **`%amber.clear`** — adds a full-walk-stop marker to the current frame's amber layer. All names are invisible below this frame until it exits.
- **`%amber.has_key?('name')`** — walks the aggregate; returns true if some layer has `name` and no tombstone or walk-stop shadows it; false otherwise. Pure query — never raises.

Consistent with Caspian's "one primitive for many roles" principle — see [concepts § Primitive reuse](https://puck.uno/requirements/concepts#primitive-reuse).

## Named namespaces

### Namespace strings must be domain- or URL-shaped

Ambient namespaces are keyed by strings that must be **a domain or URL the author controls** — the same collision-prevention convention used by Java package names (`com.company.myapp`), iOS bundle IDs, npm scoped packages (`@company/pkg`), and Caspian's own class identifiers (`caspian.uno/csv`, `example.com/mylib`).

Legal:

- `'example.com/my-lib'` — a path under a domain the author owns.
- `'caspian.uno/timestamp'` — first-party Caspian stdlib.
- `'my-company.com'` — the whole domain as the namespace.

Not legal in idiomatic use (unqualified names):

- `'log'`, `'context'`, `'foo.bar'` — no domain root; any other library using the same word collides.

The convention is not enforced by the engine (any string is a valid namespace name from the engine's perspective); it's a discipline authors follow to prevent collisions. Same convention holds regardless of whether the namespace is used by first-party code (`caspian.uno/...`), user application code (`my-app.example.com/...`), or a downloaded library (`somelib.com/subsystem`). Consistent with how [class identifiers](https://puck.uno/documentation/cheat-sheets/core-classes) work throughout the language.

### Init and access

A namespace must be explicitly initialized before use:

~~~caspian
%amber.init('example.com/my-lib')
%amber['example.com/my-lib']['gup'] = 'zap'
~~~

- `%amber.init('example.com/my-lib')` creates the namespace on the current frame.
- `%amber['example.com/my-lib']` returns the hash reference. It is **always a hash** and **cannot be assigned to** — `%amber['example.com/my-lib'] = {}` raises. Only mutations INTO the hash are allowed.
- Any descendant frame within the same role sees `%amber['example.com/my-lib']` as the same hash. Reads and writes act on the shared hash bidirectionally — a value set deep in a nested call is visible to the caller after the call returns.
- When the frame that called `.init` exits, the namespace disappears. Its hash is gone; descendants that outlive it (via closures capturing state) don't retain a live reference.

### Block-form init

For finer-than-frame scoping, `.init` accepts a `do ... end` block that owns the namespace's lifetime:

~~~caspian
%amber.init('example.com/my-lib') do
	# 'example.com/my-lib' is visible here and to descendants called from here
end
# 'example.com/my-lib' is gone; subsequent reads raise (same rule as any access
# to a non-init'd namespace)
~~~

Same rules apply inside the block as for the plain-form init — mutable contents, immutable slot, bidirectional-within-role, doesn't cross role boundaries without a grant. The only difference is when the namespace disappears: block end for the block-form, frame exit for the plain form.

Symmetric with `.grant do ... end` — block-form is the norm for scoped resource acquisition in Caspian.

## Init rules

- **Duplicate init on a visible namespace raises.** If the namespace already exists and the current frame can see it (ancestor init'd it, no role boundary blocking), calling `.init` again raises.
- **Init on a non-visible name is legal.** If an ancestor init'd `'example.com/my-lib'` but a role boundary hides it from the current frame, the current frame sees nothing named `'example.com/my-lib'` — so `.init('example.com/my-lib')` in this frame creates its own namespace, no conflict.
- **Access to a non-init'd namespace raises.** `%amber['undeclared']` when nothing in scope has init'd `'undeclared'` — the read raises.
- **Init on a granted namespace raises.** A callee that received a grant for `'example.com/my-lib'` can see it; calling `.init('example.com/my-lib')` in the callee raises (same rule as duplicate init on a visible namespace — the grant makes the namespace visible).

## Clear with `.clear`

`.clear` clears all `%amber` visibility from this frame downward. Two forms — same shape as `.init`:

~~~caspian
%amber.clear                          # plain — cleared for the rest of this frame
%amber.clear do                       # block — cleared for the block only
	&run_in_isolation
end
~~~

**Clear of visibility, not of destruction.** Ancestors' namespaces still exist above the cleared frame — the current frame and its descendants just can't see them. When the frame (or block) that called `.clear` exits, control returns to the ancestor with its full view unchanged. Everything comes back.

**Wipes the current frame's own inits too.** If this frame called `%amber.init('example.com/foo')` before `.clear`, `.clear` wipes THAT too. For the plain form, that own-frame init is gone forever (frame-init's lifetime ends with the frame anyway). For the block form, own-frame init reappears after the block exits.

**Use cases:**

- **Sandboxing untrusted code.** `%amber.clear do &untrusted end` guarantees no ambient context bleeds through, regardless of what the caller set up. Same trust posture as running in a fresh role, without the role machinery.
- **Testing pure subroutines.** `%amber.clear do &foo end` verifies `&foo` doesn't secretly depend on ambient state.
- **Explicit boundaries in your own code.** Cutting off ambient propagation at a specific point where the code below shouldn't need any context from above.

## Removing a single namespace with `.remove`

`.remove` on a specific namespace hides it from THIS frame downward, without touching the ancestor's copy. When this frame exits, the parent frame gets its view back — the ancestor's namespace was never destroyed.

~~~caspian
%amber['example.com/foo'].remove             # hidden for the rest of this frame
%amber['example.com/foo'].remove do          # hidden for the block
	&code_that_shouldnt_see_it
end
~~~

Same clear-not-destruction semantics as [`.clear`](#clear-with-clear), scoped to a single namespace instead of the whole surface.

**Distinct from the Hash primitive's `.clear`.** Two different operations, deliberately named apart:

- `%amber['example.com/foo'].clear` — the Hash primitive; empties all keys in the shared hash. Bidirectional (ancestors see the emptied hash — it IS a write). Destructive to the contents.
- `%amber['example.com/foo'].remove` — the amber operation; clears visibility of the namespace for this frame down. Non-destructive; ancestors untouched; restored on frame exit.

Pick by intent: emptying values (`.clear`) vs isolating scope from the namespace's existence (`.remove`).

**Anyone with visibility can `.remove`.** No owner-only restriction. If a frame can see the namespace, it can `.remove` it — the operation is safe because it only hides the frame's own view (and descendants'). The ancestor that init'd the namespace is untouched.

**Trying to remove a non-visible namespace raises at the subscript, not the method.** `%amber['nothing_here'].remove` fails because `%amber['nothing_here']` — the subscript read — raises when `'nothing_here'` isn't visible in the current frame (never init'd, or hidden by a role boundary). Execution never reaches `.remove`. Same rule as any other access-to-non-visible-namespace case.

**Own-frame remove.** If the CURRENT frame is the one that init'd the namespace, `.remove` still hides it for descendants — but since the namespace's lifetime is tied to this frame anyway, "restored on frame exit" is moot (the namespace dies with the frame either way). The block-form `.remove do end` on an own-frame init IS useful: hides own inits from a specific sub-scope; visibility comes back after the block.

## Checking visibility with `.has_key?`

`%amber.has_key?('example.com/foo')` returns `true` if the namespace is visible in the current frame, `false` otherwise. Pure query — never raises, regardless of whether the namespace was never init'd, is hidden by a role boundary, was removed via `.remove` in this frame or an ancestor, or was cleared via `.clear`.

Matches the standard [Hash primitive's `.has_key?`](https://puck.uno/requirements/built-in-classes/primitives/hash/) convention — same name, same true/false return, same "safe to call, never raises on missing" semantic.

Typical use — check before doing something that would raise on a missing namespace:

~~~caspian
if %amber.has_key?('example.com/foo')
	$val = %amber['example.com/foo']['gup']
	# ...
end
~~~

## Role boundaries

By default, ambient namespaces do NOT cross role boundaries. A callee in a different role sees an empty `%amber` — none of the caller's namespaces are reachable.

To share a specific namespace across the boundary, the caller uses `.grant()` on the namespace itself, scoped to a `do ... end` block:

~~~caspian
%amber.init('example.com/my-lib')
%amber['example.com/my-lib'].grant(read: true, write: true) do
	&untrusted_thing
end
~~~

Inside the block, the callee sees `%amber['example.com/my-lib']` as the same hash the caller has. Read-only, write-only, or both — the keyword args are what the callee may do.

**Grants cross one boundary at a time.** If the callee itself calls further into yet another role and wants THAT role to see the namespace, it has to grant again:

~~~caspian
# In the callee's frame (having received a grant from its caller):
%amber['example.com/my-lib'].grant(read: true) do
	&yet_deeper_thing
end
~~~

No permanent grants; no cross-multiple-boundary grants. Each hop is explicit.

**Grants must be inside a `do ... end` block.** There is no persistent-grant form.

**Grant on a non-visible namespace raises.** `%amber['undeclared'].grant(...) do end` when the caller's frame can't see `'undeclared'` — same-shape rule as any read of a non-init'd namespace.

## What `%amber` is NOT

- **Not a top-level capability object.** `%amber` doesn't inherit from `core:capability` and doesn't participate in the grant/revoke/presence-check machinery of [`global-methods` § Capability objects](global-methods/#capability-objects). Its `.grant` mechanism is scoped to individual namespaces, not to the surface as a whole.
- **Not a place for global variables.** Values are scoped to the frame that init'd them; when the frame exits, the namespace disappears. Not a substitute for module-level state.
- **Not thread-safe by construction.** Caspian is single-threaded by default; forked children get their own `%amber`. Concurrent access is not a design consideration.
- **Not a secure store for credentials or secrets.** Values in `%amber` are readable by anyone in the same role. For actual credential storage, use [protected memory](https://puck.uno/requirements/protected/) — different mechanism, different guarantees.
- **Not a substitute for arguments.** If a value is central to what a function does, pass it as an argument. `%amber` is for the ambient stuff that many functions need but few actually care about.

## Testing

- **Raise on subscript-of-non-visible, not on chained method.** `%amber['nothing_here'].remove` — the raise fires at the subscript `%amber['nothing_here']` because `'nothing_here'` isn't visible; `.remove` never executes. Assertion: the raise message identifies the subscript access, not the method call. Same test for `%amber['nothing_here'].clear`, `%amber['nothing_here'].grant(...)`, `%amber['nothing_here']['key']`, and any other chain that starts with a non-visible subscript.
- **Duplicate init on a visible namespace raises.** `%amber.init('a.com/x'); %amber.init('a.com/x')` — second call raises.
- **Init on a name hidden by role boundary is legal.** Ancestor init'd `'a.com/x'`; callee in a different role calls `%amber.init('a.com/x')` — succeeds; the callee's frame has its own `'a.com/x'` distinct from the ancestor's.
- **Bidirectional writes.** Descendant writes `%amber['a.com/x']['count'] = 5`; ancestor reads `%amber['a.com/x']['count']` after descendant returns and sees `5`.
- **Ancestor doesn't see descendant's inits.** Descendant calls `%amber.init('a.com/y')`; after descendant returns, ancestor reading `%amber['a.com/y']` raises. Descendant's init lifetime ended with its frame.
- **Frame-init lifetime.** `%amber.init('a.com/x')` in a function; after the function returns, ancestor reading `%amber['a.com/x']` raises.
- **Block-init lifetime.** `%amber.init('a.com/x') do ... end`; inside the block `%amber['a.com/x']` works; outside the block (still in the same frame) reading it raises.
- **`.clear` restores on frame exit.** Ancestor init's `'a.com/x'`; descendant calls `%amber.clear`; back in the ancestor after descendant returns, `%amber['a.com/x']` works.
- **`.clear do end` restores on block exit.** Same test bounded by the do-block.
- **`.clear` wipes own inits (plain form).** Frame `.init`s then `.clear`s; the init is gone for good; subsequent read raises.
- **`.clear` wipes own inits (block form, restored).** Frame `.init`s then `.clear do end`s; inside the block the init is invisible; after the block the init is back.
- **`.remove` clears one namespace, leaves others.** Frame `.init`s two namespaces; `.remove` on one; the other is still visible.
- **Role boundary hides all namespaces by default.** Caller `.init`s a namespace; calls into a different role; callee reads that namespace — raises.
- **`.grant` crosses one role boundary.** Caller grants; callee sees the namespace; callee calls further into another role without granting again; that further callee doesn't see the namespace.
- **`.grant do end` scoping.** Grant is active inside the block; outside the block (same caller frame), a fresh cross-role call by the same caller doesn't grant.
- **`.grant(read: true, write: false)` blocks writes.** Callee reads OK, writes raise.
- **`.has_key?` on a visible namespace returns true.** After `.init('a.com/x')`, `%amber.has_key?('a.com/x')` returns `true`.
- **`.has_key?` on a never-init'd name returns false.** Doesn't raise.
- **`.has_key?` on a namespace hidden by role boundary returns false.** In the callee (no grant), returns `false` for the caller's namespace.
- **`.has_key?` on a namespace removed via `.remove` returns false.** Frame `.init`s, then `.remove`s; `.has_key?` returns `false` for that name until the frame exits (block-form: for the block's duration).
- **`.has_key?` under `.clear` returns false for everything.** Frame `.clear`s; `.has_key?` returns `false` for any name until `.clear` scope ends.
- **Namespace slot is not assignable.** `%amber['a.com/x'] = {}` raises (only mutations INTO the hash are allowed).
- **Aggregate-hash push and pop are O(1) per frame.** Frame push adds an empty amber layer; frame return pops it; both operations do not scan or copy the namespace set.
