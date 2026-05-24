# Caspian

<a id="overview"></a>
## Overview

~~~json
{"vibecode": {
	"section": "overview",
	"language": "Caspian",
	"complements": "Q0",
	"q0_role": "query_and_filter",
	"caspian_role": "computation_and_control_flow",
	"development_history": "~20 years conceptual"
}}
~~~

Caspian is the programming language of the Puck ecoverse. It handles computation and
control flow — the things Q0 deliberately does not do. Q0 is a query and filter language;
Caspian is where actual programming lives.

Caspian has been in development conceptually for approximately twenty years.

---

<a id="host-language-why-lua"></a>
## Host Language: Why Lua

~~~json
{"vibecode": {
	"section": "host_language_why_lua",
	"choice": "lua",
	"reasons": ["tiny_footprint_and_wide_install_base",
		"more_contributor_involvement_than_we_would_get_with_c",
		"cross_os_reliability_already_solved_by_lua",
		"python_too_monolithic_for_pucks_light_footprint_goal",
		"c_efficient_but_too_painful_to_debug"]
}}
~~~

The reference engine for Caspian is implemented in Lua 5.4. The
choice is deliberate; the reasoning:

- **Tiny and widely installed.** Lua's footprint is small enough
  that asking users to install it (if they don't already have it)
  is a minor ask, not a barrier.
- **More involvement than we'd get with C.** Lua isn't a barrier
  for contributors who want to patch the Puck libraries. We expect
  more involvement from a Lua codebase than from a C codebase.
- **Cross-OS portability is already solved.** Lua works on essentially
  every operating system that runs anything. Puck inherits that
  portability without doing the work itself: if a system can run
  Lua, it can run Puck.

<a id="why-not-python"></a>
### Why not Python

Python is also a solid candidate — installed everywhere, possibly
the biggest software community of any language. But **Python is
monolithic.** It's a much larger system than Lua, and pulling in
its full footprint conflicts with the design goal of keeping Puck
light. A small, reliable cross-OS footprint matters more than a
larger ecosystem.

<a id="why-not-c"></a>
### Why not C

C is the "obvious" choice in the sense that you *can* write very
efficient systems in it. But C's syntax is complicated and the
debugging cost is too high — running into low-level C bugs every
time something subtle goes wrong is not a tax worth paying. Lua
gets us most of the way without it.

---

<a id="philosophy"></a>
## Philosophy

~~~json
{"vibecode": {
	"section": "philosophy",
	"core_principle": "everything_that_can_be_written_in_caspian_should_be",
	"lua_role": "interpreter_loop_memory_management_external_bindings_only",
	"exception": "move_to_lua_if_unwieldy_or_too_slow",
	"kernel_required": ["interpreter_loop", "gc", "core_bwcs",
		"primitive_types", "puck.uno/object", "puck.uno/helper",
		"system_methods_%call_%chain_%bucket"],
	"goal": "standard_library_written_in_caspian_visible_and_inspectable",
	"lua_reference_deps": ["SQLite", "libmicrohttpd", "libsodium"],
	"size_target": "500k_for_caspian_own_code_excluding_deps",
	"threading": "not_supported_single_threaded_by_design"
}}
~~~

<a id="caspian-written-in-caspian"></a>
### Caspian Written in Caspian

Everything that can be written in Caspian should be written in Caspian. The Lua layer
exists for things that cannot be expressed in Caspian at all — the interpreter loop,
memory management, external library bindings — not as a convenience for things that are
merely awkward to write in Caspian.

The exception is pragmatic: if something could be in Caspian but has become unwieldy or
too slow in practice, move it to Lua. Performance and maintainability are valid reasons
to drop down. But the default is always Caspian first.

A compliant Caspian engine must provide a minimal kernel:

- The interpreter loop
- Memory management and garbage collection
- Core bwcs: `if`, `while`, `and`, `or`, `not`
- Primitive types: string, number, boolean, null, array, hash
- `puck.uno/object` — the root class, foundation of the object system
- `puck.uno/helper` — the base helper class
- System methods: `%call`, `%chain`, `%bucket`

Everything built on top of these — `puck.uno/loop`, exception classes, the standard
library, helper implementations — should be written in Caspian where possible.

This makes much of the engine visible and inspectable. A developer who wants to understand
how a feature works can read Caspian source rather than implementation source. Bugs in
the standard library are fixable without touching the host language.

<a id="lua-reference-implementation"></a>
#### Lua reference implementation

The Lua reference implementation provides the kernel above plus:

- Bindings to SQLite and libmicrohttpd
- Pattern matching via Lua's built-in pattern library

The Caspian parser is a hand-written recursive descent parser written in Caspian JSON
directly — this is the bootstrapping constraint. Once the parser is working, future
rewrites can use Caspian.

<a id="dependencies-lua-reference-implementation"></a>
### Dependencies (Lua reference implementation)

The Lua implementation requires Lua plus three C libraries:

- **SQLite** — used by the mikobase implementation; both `puck.uno/mikobase/memory` (in-memory
  mode) and `puck.uno/mikobase/sqlite` (file-backed mode) run on SQLite
- **libmicrohttpd** — embedded HTTP server powering `puck.uno/mikobase/http`;
  handles concurrent connections at the C level
- **libsodium** — all cryptographic needs: `%utils.random.uuid` (CSPRNG-backed
  UUIDs, see [utils.md](../utils/utils.md#utilsrandomuuid)), Ed25519 signing for the
  Puck blockchain (see [blockchain.md](../blockchain/.md)). One audited
  security-focused library covers both, on every platform Lua runs on

Performance concerns are addressed by optimizing the interpreter, not by abandoning
the principle.

<a id="error-messages"></a>
### Error Messages

Sometimes complexity is unavoidable. When it is, the key to helping the developer is good
error messages. If something goes wrong, Caspian should pinpoint the problem precisely and
explain the mistake clearly. A confusing error message is a bug.

---

<a id="design-principles"></a>
## Design Principles

~~~json
{"vibecode": {
	"section": "design_principles",
	"principles": ["lightweight_and_embeddable", "no_threading_or_forking",
		"timeouts_via_%utils.timeout", "caspianj_as_runtime_format"],
	"embeddable_in": ["Python", "Ruby", "other_major_languages"],
	"sqlite_required": true,
	"timeout_mechanism": "debug.sethook_in_lua_fires_every_N_vm_instructions",
	"timeout_nested_budgeting": "min(requested, remaining_parent_budget)"
}}
~~~

<a id="lightweight-and-embeddable"></a>
### Lightweight and Embeddable

The Caspian interpreter must be embeddable in every major language (Python, Ruby, etc.)
as a library dependency. It ships with mikobase support built in, which means SQLite is a
required dependency. SQLite is ubiquitous — it is already present on virtually every
platform — so this barely counts as an external requirement.

Caspian is not minimal in the way Lua is minimal, but it borrows Lua's discipline around
size. The target for Caspian's own code is 500k, not counting external dependencies
(Lua, SQLite, libmicrohttpd). If the compiled size of Caspian's own code exceeds 500k,
that is a red flag worth investigating. Every engine that runs Caspian gets mikobase support,
the security model, and the full object system.

This matters because Caspian will run inside engines — for dynamic firewall rules, trigger
records, and other engine-level logic. Every engine needs to run it.

<a id="no-threading-or-forking"></a>
### No Threading or Forking

Caspian does not support threading, forking, or concurrency primitives. It is
single-threaded by design. The host language handles concurrency; Caspian runs within a
single execution context.

This constraint keeps the interpreter small and predictable. Forking, fork-shared
mikobases, and the multi-process coordination model are opt-in Caspian features the
engine grants on request (off by default) — see
[ideas/plusplus/threads.md](../../ideas/plusplus/threads.md).

<a id="timeouts"></a>
### Timeouts

Caspian does not use threads, but untrusted code must not be allowed to run indefinitely.
A function downloaded from a remote Puck object — `%puck['borg.com/riker']` — might
be an infinite loop or a crypto miner. The `%utils.timeout` method wraps a block with a
hard time limit:

```
%utils.timeout(5) do
    &riker
end
```

If the block does not complete within the specified number of seconds, the
timeout fires a **two-stage** flag sequence:

1. **Inside the block:** `puck.uno/timeout_handle` is raised.
   This is not an exception — it does not unwind. `begin`/`ensure` blocks inside
   the timeout do not run, no Caspian-level cleanup is attempted inside. The
   `timeout_handle` bubbles straight up to the timeout block's boundary,
   ignoring all user-level `catch` and `ensure` along the way.
2. **At the timeout block's boundary:** the timeout mechanism intercepts the
   `timeout_handle` and re-raises a `puck.uno/error/timeout`
   in the caller's scope. This is a normal catchable error — the caller can
   `catch('puck.uno/error/timeout')` (or any ancestor
   like `exception` or `error`) and handle it cleanly. If the caller doesn't
   catch, the timeout error propagates up the stack like any other.

```
catch('puck.uno/error/timeout')
    %utils.timeout(5) do
        &slow_thing
    end
end
```

Whole-second granularity is used.

The reason `timeout_handle` doesn't unwind: a runaway block (infinite loop,
crypto miner) can also write infinite-loop cleanup code. Letting `ensure` run
inside the timeout block during a timeout would let the developer extend their
budget by an arbitrary amount. The two-stage model denies that path entirely
while still giving the *caller* a normal catchable error.

When running untrusted code, the engine is responsible for wrapping execution in
`%utils.timeout` (or an equivalent native-level bound) from the embedding side.
Caspian code inside cannot extend or escape that outer timeout.

<a id="the-unwind-option"></a>
#### The `unwind:` option

For *cooperative* code that wants a polite "time's up, clean up and exit"
signal — not the security-boundary form — pass `unwind: true`:

```
%utils.timeout(3600, unwind: true) do
    # run for an hour, then exit gracefully
end
```

With `unwind: true`, the two-stage mechanism collapses to one: when the
deadline fires, a `puck.uno/error/timeout` is raised **directly
inside the block** (no `timeout_handle`), unwinds the stack like any normal
exception, runs `begin`/`ensure`, and propagates outward.

**This is not a security boundary.** Code inside the block can
`catch('puck.uno/error/timeout')` and keep running. That's the
point — cooperative code is trusted to honor the timeout. Use `unwind: true`
when you control the code inside the block and want cleanup; use the default
when you don't.

The `unwind:` kwarg is per-block. **The stricter parent always wins** at the
moment its deadline fires. If an outer `unwind: false` deadline fires while
execution is inside an inner `unwind: true` block, the outer's `timeout_handle`
bubbles up uncatchably and bypasses the inner's `begin`/`ensure`. The inner's
mode applies only when the inner's own deadline fires.

<a id="the-form-utilstimeout"></a>
#### The `?` form: `%utils.timeout?`

`%utils.timeout?` (with the `?` suffix) is the **tolerant form** that returns
the timeout flag as a value instead of raising it at the boundary:

```
$timeout = %utils.timeout?(5) do
    &slow_thing
end

if $timeout
    # timed out — $timeout is the flag object
else
    # block completed normally
end
```

On normal completion, `%utils.timeout?` returns `null`. The block's own
return value is not preserved through `%utils.timeout?` — if the caller
needs it, assign it to a variable inside the block.

The `?` form follows the language-wide
[`?` suffix convention](../caspian.md#the-suffix): falsey on the happy path,
truthy (the flag itself) on the failure path. It's sugar for what would
otherwise be `catch('error/timeout')` wrapping around
`%utils.timeout` — the common "try for N seconds, move on if not" pattern,
compressed into the method name.

<a id="the-form-combines-with-unwind"></a>
#### The `?` form combines with `unwind:`

`unwind:` controls *what fires inside the block* when the deadline hits;
the `?` form controls *what happens at the boundary* when a timeout flag
escapes the block. They combine cleanly:

| Form | `unwind:` | Behavior |
|---|---|---|
| `%utils.timeout(N)` | (omitted) | `timeout_handle` inside (no `ensure`); `error/timeout` raised in caller scope |
| `%utils.timeout(N, unwind: true)` | `true` | `error/timeout` inside (catchable, `ensure` runs); propagates out of the block normally |
| `%utils.timeout?(N)` | (omitted) | `timeout_handle` inside (no `ensure`); boundary catches and **returns** the timeout flag |
| `%utils.timeout?(N, unwind: true)` | `true` | `error/timeout` inside (catchable, `ensure` runs); if it escapes the block, boundary catches and **returns** it |

In the `%utils.timeout?(N, unwind: true)` case: if the block itself catches
the timeout, `%utils.timeout?` returns `null` (nothing escaped). If the
block doesn't catch, the `?` form converts the escaping timeout to a return
value.

<a id="spec-compliant-engine-requirements"></a>
#### Spec: compliant engine requirements

A compliant engine must:

- Abort execution of the block (default mode) or raise an unwinding
  `error/timeout` inside the block (`unwind: true` mode) if it does
  not complete within the specified number of seconds (whole-second granularity)
- Make each default-mode `%utils.timeout` call undefeatable by Caspian code —
  there must be no path from a Caspian expression to suppress a `timeout_handle`
- Allow `unwind: true` timeouts to be caught and suppressed from Caspian code
  (the cooperative-timeout contract)
- Provide a `%utils.timeout?` form that catches the timeout flag at the
  `%utils.timeout?` boundary and returns it as the call's value instead of
  raising it. Returns `null` on normal completion.
- Apply nested timeout budgeting: `effective_timeout = min(requested, remaining_parent_budget)`.
  An inner `%utils.timeout(20)` inside an outer `%utils.timeout(5)` is bound by the
  outer's remaining 5 seconds. The stricter parent's mode wins when its deadline fires.
- Handle blocking system calls — any system method that can block must implement its own
  timeout at the native level, since the interpreter-level timeout cannot fire during a
  native blocking call

<a id="lua-reference-implementation-1"></a>
#### Lua reference implementation

`%utils.timeout` is implemented using `debug.sethook`. A hook is registered that
fires every N VM instructions and checks `os.time()` against the deadline. When
the deadline is exceeded, the hook raises a Lua error whose tag depends on the
block's mode:

- **Default mode:** the error is tagged as `timeout_handle`. Caspian's
  `begin`/`ensure` compiles to a `pcall` variant that explicitly re-raises
  `timeout_handle`-tagged errors instead of catching them, so the error
  propagates through Caspian-level frames without running any `ensure` blocks
  until it reaches the `%utils.timeout` boundary. There, the timeout's wrapping
  code intercepts the `timeout_handle` and translates it into a
  `puck.uno/error/timeout` raised normally in the caller's scope.
- **`unwind: true` mode:** the error is untagged (or tagged as a normal
  exception). It's caught by ordinary `pcall`, runs `ensure`, and is exposed
  to user `catch` as a `puck.uno/error/timeout` directly inside
  the block. No boundary translation needed.

The hook is cleared after the block completes (whether normally or via timeout).
No threads are required.

Caspian code cannot defeat the default-mode timeout because `debug`, `load`,
`os`, and the rest of Lua's standard library are not reachable from Caspian
expressions, and `begin`/`ensure` re-raises `timeout_handle`-tagged errors.
`unwind: true` mode is deliberately suppressible by user code — that's the
cooperative-timeout contract.

<a id="caspianj-as-the-runtime-format"></a>
### CaspianJ as the Runtime Format

Caspian programs are written in Caspian and transpiled to CaspianJ for execution.
CaspianJ is easy to store, transmit, and parse in any language — which makes Caspian
programs easy to ship around, embed in records, and process programmatically.

By convention, code is shared as Caspian source. CaspianJ is the runtime artifact,
not the distribution format.

Alternative syntaxes that transpile to CaspianJ are possible but not encouraged. Caspian
is the language; CaspianJ is the wire format.

---

<a id="relationship-to-other-systems"></a>
## Relationship to Other Systems

~~~json
{"vibecode": {
	"section": "relationship_to_other_systems",
	"q0": "selects_and_filters_records_complementary_not_overlapping",
	"puck": "caspian_is_programming_language_component_of_puck_ecoverse",
	"caspianj": "runtime_format_caspian_compiles_to"
}}
~~~

- **Q0** — Caspian and Q0 are complementary. Q0 selects and filters records. Caspian
  computes, controls flow, and implements behavior. They are not the same language and are
  not meant to overlap.
- **Puck** — Caspian is the programming language component of the Puck ecoverse,
  alongside the Puck object model and `puck.uno/query`.
- **CaspianJ** — The runtime format Caspian compiles to. See [caspianj.md](../caspianj.md).

---

<a id="primitives"></a>
## Primitives

~~~json
{"vibecode": {
	"section": "primitives",
	"types": ["String", "Number", "Boolean", "Null", "Array", "Hash"],
	"strings": "utf8_immutable_encoded_at_engine_boundary",
	"hashes": "key_order_significant_equal_only_if_same_keys_values_and_order",
	"numbers": "no_int_float_distinction_single_number_type",
	"truthiness": "null_and_false_are_falsy_everything_else_truthy_including_0_and_empty_string",
	"null_true_false": "fully_instantiable_and_subclassable_classes",
	"null_flavors": "hl7_concept_subclass_puck.uno/null_for_domain_specific_nulls"
}}
~~~

<a id="caspian-as-an-extension-of-json"></a>
### Caspian as an Extension of JSON

Think of Caspian as an extension of JSON. Primitives work like in JSON: strings, numbers,
booleans, null, arrays, and objects. Caspian builds on these rather than introducing new
ones.

<a id="types"></a>
### Types

| Type | Examples |
|---|---|
| String | `'foo'`, `"foo"`, `:foo` |
| Number | `1`, `3.14`, `-7` |
| Boolean | `true`, `false` |
| Null | `null` |
| Array | `[1, 2, 3]` |
| Hash | `{key: 'value'}` |

<a id="strings"></a>
### Strings

All strings in Caspian are UTF-8. There is no other encoding. Strings are immutable —
operations on a string return a new string; the original is never modified.

Encoding is handled at the engine boundary, not in Caspian code. A compliant Caspian
engine must convert all incoming strings to UTF-8 before passing them to Caspian.
The reference Lua implementation converts whatever encodings Lua natively supports.
Strings arriving in unsupported encodings should raise an error at the boundary.

<a id="hashes"></a>
### Hashes

Hash key order is significant. `{foo: true, bar: true}` and `{bar: true, foo: true}` are
distinct values. The order in which keys are written is the order in which they are stored
and iterated. Two hashes are equal only if they contain the same keys with the same values
in the same order.

This matters for serialization, comparison, and anywhere key order carries semantic weight
(e.g., field ordering in a record schema).

<a id="numbers"></a>
### Numbers

There is no distinction between integers and floats — there is only `number`. JSON makes
no such distinction, and neither does Caspian. The interpreter handles numeric
representation internally, using integer or float arithmetic as appropriate for
efficiency.

<a id="truthiness"></a>
### Truthiness

`null` and `false` are falsy. Everything else is truthy — including `0` and `''`.

<a id="null-true-and-false-as-classes"></a>
### `null`, `true`, and `false` as Classes

In most languages, `null`, `true`, and `false` are global singletons whose underlying
classes cannot be instantiated. In Caspian, the underlying classes are fully instantiable
and subclassable.

The bwcs `null`, `true`, and `false` always return a standard instance of their respective
classes. This behavior cannot be changed. But you can create instances directly:

```
$my_null = %puck['null'].new
$my_null = %puck['puck.uno/null'].new   # same thing
```

**Truthiness is immutable.** Any instance of `puck.uno/null` or its subclasses is always
falsey. Any instance of `puck.uno/true` is always truthy. Any instance of `puck.uno/false`
is always falsey. Subclassing or adding methods cannot change this.

<a id="null-flavors"></a>
### Null Flavors

The most compelling use case for subclassing `puck.uno/null` is null flavors — a concept
from HL7, the healthcare data standard. In HL7, null values carry a reason: "unknown",
"not applicable", "masked for privacy", "not asked". Plain `null` loses this information;
null flavors preserve it.

In Caspian, you can subclass `puck.uno/null` to create domain-specific null types:

```
class 'myapp.com/null/unknown'
    inherits 'puck.uno/null'
end

class 'myapp.com/null/not_applicable'
    inherits 'puck.uno/null'
end
```

Instances of these classes are falsey in all conditionals, but carry type information
that code can inspect when needed:

```
$val = %puck['myapp.com/null/unknown'].new

if($val)
    # never entered — $val is falsey
end
```

The same subclassing pattern applies to `puck.uno/true` and `puck.uno/false`, though
null flavors are the primary use case.

<a id="operators"></a>
### Operators

The following operators are methods that any class can implement:

```
+  -  *  /  ==  !=  <  >  <=  >=
```

`1 + 2` is equivalent to `1.+(2)`. Classes can override these for custom types.

<a id="boolean-operators"></a>
### Boolean Operators

`and`, `or`, and `not` are core bwcs implemented in Lua. They use short-circuit evaluation
and cannot be overridden. Symbol shortcuts:

| bwc | shortcut |
|---|---|
| `and` | `&&` |
| `or` | `\|\|` |
| `not` | `!` |

<a id="core-bwcs"></a>
### Core bwcs

The following bwcs are implemented in Lua and cannot be overridden:

```
if    elsif (alias: elseif)    else    while
and   or    not
begin ensure
```

See [Cleanup with `begin` / `ensure`](#cleanup-with-begin-ensure) for the
begin/ensure pair.

**Loop-scoped section markers.** The keywords `before`, `between`, `after`,
and `noloop` are also reserved and engine-implemented, but they are
**not general bwcs** — they may only appear as section markers inside
loop bodies (per [loops.md § Structural blocks](../syntax/loops.md#structural-blocks)),
not as standalone statements. The lexer/parser recognizes them as
keywords; the loop runner consumes them. Outside a loop body their
appearance is a parse error.

<a id="self"></a>
### `self`

`self` is a bwc shortcut for `%self`, which returns the current object instance.

---

<a id="variables"></a>
## Variables

~~~json
{"vibecode": {
	"section": "variables",
	"sigil": "$",
	"first_class": true,
	"variable_object": "$$foo returns variable object not value",
	"pass_by_reference": "intentionally_unsupported"
}}
~~~

Variables are prefixed with `$`. They are first-class objects.

`$$foo` returns the variable object itself — distinct from `$foo`, which returns the value
the variable holds. Variable objects can be passed around like any other object. However,
the variable object deliberately does not expose its value. Pass-by-reference is an
intentionally unsupported pattern; the variable object's interface will be designed
around other use cases in the future.

---

<a id="exceptions-and-warnings"></a>
## Exceptions and Warnings

~~~json
{"vibecode": {
	"section": "exceptions_and_warnings",
	"shared_shape": ["class", "id", "bucket"],
	"raise_methods": ["%chain.warn", "%chain.throw", "%chain.error",
		"%chain.exit", "%chain.abort"],
	"top_level_classes": ["puck.uno/warning", "puck.uno/exception"],
	"exception_subclasses": ["error", "error/timeout",
		"exit", "return", "abort",
		"security", "timeout_handle"],
	"per_class_properties": ["catcher", "unwinds"],
	"default_profile": "catcher=user, unwinds=yes",
	"overrides_required_for": ["exit", "return", "abort", "security",
		"timeout_handle"],
	"catch": "catch() matches by class AND filters by catcher=user",
	"heed": "heed() matches warnings (non-unwinding)",
	"abort_capability": "tied_to_scope_untrusted_code_cannot_abort_process"
}}
~~~

The framework's flow-modifying events come in two top-level classes:
**warnings** (observational, non-unwinding, never user-catchable via `catch`)
and **exceptions** (raised to redirect flow). All flags share a single object
shape (class, id, bucket) and a single set of `%chain` raising methods.

`exception` is the umbrella class for everything raised — including aborts,
exits, security violations, and so on. By default an `exception` subclass
unwinds and is catchable in user code; subclasses that need different
behavior (abort, security, timeout_handle, exit, return) explicitly override
either or both properties. The word "exception" is doing double duty here as
the umbrella *and* the default-behavior class; in practice no one talks about
the umbrella, so the ambiguity stays out of the way.

<a id="shared-shape"></a>
### Shared shape

Every flag is a Caspian object with:

- **A class** — the formal type, used by `catch()` and `heed()` to match.
- **An id** — a string nickname for the specific case. Free-form, author-chosen
  (e.g., `'connection_refused'`, `'redundant_fields'`). The id is a human-readable
  label; matching is by class.
- **A bucket** — a hash holding details/payload. Accessed openly via `[]`:

```
$e = catch('foo.com/error/network')
    # ... something that throws
end

if $e
	$e.id            # 'connection_refused' — the nickname
	$e['host']       # 'db1' — direct bucket access
	$e['port']       # 5432
end
```

This matches the universal Caspian object model (class stack + bucket). Exceptions,
errors, and warnings are regular objects following that model — no special accessors.

<a id="the-two-top-level-classes"></a>
### The two top-level classes

| Class | Propagation |
|---|---|
| **Warning** | Up through the stack without unwinding; collected via `heed()` |
| **Exception** | Raised to redirect flow; each concrete subclass has its own (catcher, unwinds) profile |

Under `exception`, every concrete class is independently declared. The default
profile is `catcher=user, unwinds=yes` (the familiar "throw and catch" model).
Subclasses override one or both properties as needed:

- **`error`** — same default profile. Semantic marker for "this is
  an error situation" — behaviorally identical to plain `exception`. See
  [error vs exception](#error-vs-exception) below.
- **`error/timeout`** — same default profile; the user-catchable
  timeout raised at the boundary of a `%utils.timeout` block.
- **`exit`** — unwinds, but caught by the engine for orderly
  shutdown rather than user `catch`.
- **`return`** — unwinds, caught at function-call boundary.
- **`abort`** — does *not* unwind; engine takes over, no `ensure`.
- **`security`** — does *not* unwind; engine catches.
- **`timeout_handle`** — does *not* unwind; bubbles to the
  `%utils.timeout` block boundary, where the timeout mechanism translates
  it into a user-facing `error/timeout` (see
  [Timeouts](#timeouts)).

<a id="error-vs-exception"></a>
### Error vs exception

`puck.uno/error` is a **semantic marker**, not a behavioral
distinction. Both `exception` and `error` carry stack traces, both unwind,
both are user-catchable. The class names exist to convey developer intent:

- **`exception`** — generic flow-control raise. Used for redirects, custom
  signals, control transfer, anything that's "this code path is taking a
  turn."
- **`error`** — "something went wrong." A subclass of exception; the name
  signals to readers that this is a failure condition, not a routine
  flow-control event.

`catch('puck.uno/exception')` catches both (error is-a exception).
`catch('puck.uno/error')` catches only errors and their subclasses.

**All exceptions carry a stack trace.** Trace capture cost is small in
practice and the debug value of having a trace on every exception (especially
when one propagates farther than its raiser anticipated) outweighs the cost.

**Minimum stack-trace shape (v1):** the trace is accessed via `$e.stack`
as an array of frame objects, root frame first, current frame last. Each
frame is a hash with at minimum:

| Field | Type | Description |
|---|---|---|
| `class` | string (UNS) | The owning role / class of the function-object whose call frame this is. For top-level scripts, the engine fills in a synthetic UNS (e.g., `puck.uno/script/<name>`). |
| `method` | string | The method or function name (e.g., `greet`, `init`, or `<top-level>`). |
| `line` | integer | The source line number within the function (1-based). Null for engine-internal frames. |

Engines may add fields (column, file path, role at-time-of-call, etc.) as
needed; consumers should treat unknown fields as additive and not reject
the trace because of them. Serialization for Jasmine flattens each frame
to the same hash; serialization for the wire format used by
[versioning.md](../versioning.md) follows the same shape (with field
trimming as the doc describes).

<a id="raising-standard-flags"></a>
### Raising standard flags

Each of the standard flag classes has a shortcut method on `%chain`. All take an
id and a bucket; the class is implied by the method:

```
%chain.warn 'redundant_fields', {fields: ['sort', 'sorts']}
    # class: puck.uno/warning
    # does not unwind

%chain.throw 'cache_miss', {key: 'user:42'}
    # class: puck.uno/exception
    # unwinds, carries stack trace

%chain.error 'connection_refused', {host: 'db1', port: 5432}
    # class: puck.uno/error
    # unwinds, carries stack trace
    # the "error" subclass is a semantic marker — same behavior as throw,
    # just a name indicating "this is an error" for readers

%chain.exit 'normal', {code: 0}
    # class: puck.uno/exit
    # unwinds (graceful shutdown), runs ensure and close

%chain.abort 'unrecoverable', {reason: 'bad_state'}
    # class: puck.uno/abort
    # does NOT unwind — engine terminates, no ensure runs
```

These are convenience shortcuts for the **standard flag classes**. They cover most
real use — custom flag subclasses exist (see below) but are less common in practice
than you might expect.

Why these live on `%chain`: raising any flag is a chain-flow event — exceptions
unwind the chain, warnings travel up it, aborts terminate it. The chain owns the
flow-control surface.

<a id="raising-custom-flags"></a>
### Raising custom flags

For custom flag classes (a specific exception subclass, a Sammy redirect, a
custom warning, etc.), use the standard object-instantiation pattern:

```
$f = %['puck.uno/sammy/redirect/302'].new('temporary')
$f['whatever'] = 'dude'
$f.raise
```

- **Construct** the flag with `.new(id)` — the id positional arg is the nickname.
- **Populate** the bucket via `[]`.
- **Raise** with the universal `.raise` method on the flag object.

`.raise` is the primitive that initiates propagation. The `%chain` shortcuts above
internally do this — they construct a flag of the default class, populate it, and
call `.raise`.

This pattern is uniform with how every other object is created in Caspian: `.new`,
configure, use. Nothing special.

<a id="class-hierarchy"></a>
### Class hierarchy

```
puck.uno/warning
puck.uno/exception
    puck.uno/error
        puck.uno/error/timeout
        # other built-in and developer-defined errors live here
    puck.uno/exit
    puck.uno/return
    puck.uno/abort
    puck.uno/security
    puck.uno/timeout_handle
```

| Class | Catcher | Unwinds |
|---|---|---|
| `warning` | user (`heed`) | no |
| `exception` | user (`catch`) | yes |
| `error` | user (`catch`) | yes |
| `error/timeout` | user (`catch`) | yes |
| `exit` | engine | yes |
| `return` | function boundary | yes |
| `abort` | engine | no |
| `security` | engine | no |
| `timeout_handle` | timeout block boundary | no |

- `puck.uno/warning` is observational. Emitted via `%chain.warn`, collected
  via `heed()`, never user-catchable through `catch()`.
- `puck.uno/exception` is the umbrella for everything raised. By default,
  exceptions are user-catchable and they unwind; the subclasses listed above
  override one or both of those properties.
- `error` is a subclass of `exception` — same default profile, but carries a
  stack trace. `catch('exception')` catches both.
- **`timeout` and `timeout_handle` are completely different classes** doing
  different jobs. `timeout` is the user-catchable error that surfaces in
  caller scope when a timeout block runs out. `timeout_handle` is the
  internal abort that fires *inside* the timeout block and bubbles to the
  block's boundary — see the [Timeouts section](#timeouts) for how they
  interact.

Custom flag classes can extend any concrete class — `foo.com/error/network`,
`foo.com/warning/validation`, etc. A custom class inherits its parent's
profile unless it overrides.

<a id="return-exit-abort"></a>
### `return`, `exit`, `abort`

These are Caspian flow primitives:

- **`return`** raises `puck.uno/return`. Function call boundaries
  automatically catch it and extract the return value. Early returns from nested
  blocks work naturally — no special non-local-return machinery needed; the
  interpreter uses the same unwind mechanism for all flow that unwinds.
- **`exit`** raises `puck.uno/exit`. Graceful: unwinds the stack,
  runs `begin`/`ensure` blocks, runs `close` on objects (see
  [Garbage Collection](#garbage-collection)), and cleans up before the process
  ends. Equivalent to `%chain.exit` or `%process.exit`.
- **`abort`** raises `puck.uno/abort`. **Violent**: the engine
  terminates the execution unit immediately. The stack is not unwound,
  `begin`/`ensure` does not run, `close` is not called, GC does not run.
  Equivalent to `%chain.abort` or `%process.abort`.

`%chain.exit` and `%chain.abort` exist for symmetry with `%chain.error`,
`%chain.warn`, and `%chain.throw` — all flag-raising lives on `%chain`. The
bareword shortcuts (`exit`, `abort`) and the `%process.*` forms remain
available for the developer who prefers them.

**Unwinding rule:**

| Method | Class | Unwinds? |
|---|---|---|
| `%chain.warn` | `warning` | No — propagates up without unwinding |
| `%chain.throw` | `exception` | Yes — runs `ensure`, runs `close`, unwinds frames |
| `%chain.error` | `error` | Yes — runs `ensure`, runs `close`, unwinds frames |
| `%chain.exit` | `exit` | Yes — graceful unwind, runs `ensure`, `close`, GC |
| `%chain.abort` | `abort` | No — engine takes over, no `ensure`, no `close`, no GC |

Two methods don't unwind, for two different reasons: warnings by design
(they're observations, not flow events), aborts by intent (immediate
termination, no Caspian-level code is trusted to run during cleanup).

Abort is a capability granted per role. The `user` role typically holds
it; roles the engine launches with restricted surfaces may not.
`puck.uno/abort` propagates to role boundaries:

- At a boundary into a role **with** abort capability, the process
  terminates.
- At a boundary into a role **without** it, the abort is caught and
  converted to an error. Execution in the role on the other side
  continues normally.

This means code running under a role without abort capability can only
abort itself, not the process that contains it.

<a id="catching-exceptions"></a>
### Catching exceptions

`catch()` matches **user-territory exceptions** — classes whose `catcher`
property is "user." That's `puck.uno/exception`, `puck.uno/error`,
`puck.uno/error/timeout`, and any developer-defined class with
`catcher: user`. Engine-territory subclasses (`exit`, `return`, `abort`,
`security`, `timeout_handle`) are not catchable from user code; the
engine catches them before user catch handlers see them, even though
they are declared subclasses of `exception`.

```
$e = catch('foo.com/error/network')
    # ... code that may throw a network exception ...
end

$e             # null if no matching exception, otherwise the exception object
$e.id          # the id nickname
$e['host']     # bucket access
```

Multiple classes:

```
$e = catch('foo.com/error/network',
           'foo.com/error/timeout')
    # ...
end
```

Catch all user-territory exceptions:

```
$e = catch()
    # ...
end
```

A no-args `catch()` matches anything whose `catcher` is "user" — both the
built-in `exception` and `error` classes, plus any developer-defined classes
that declared themselves user-catchable. This is the idiomatic "catch
whatever the user might throw" form.

**Note on the hierarchy.** `catch()` is filtered by both class match *and*
the `catcher` property. So `catch('puck.uno/exception')` matches `exception`,
`error`, and `error/timeout` (all `catcher: user`), but **not** `exit`,
`abort`, `security`, `return`, or `timeout_handle` — those are declared
subclasses of `exception` but have engine-or-other catchers, and `catch`
never sees them. The engine catches engine-territory subclasses before user
catch handlers run. Custom subclasses match their declared parent:
`catch('puck.uno/error')` matches `foo.com/error/network`
because the latter is declared as a subclass of error.

**UNS naming is flat; inheritance is declared.** The class names above
(`puck.uno/error`, `puck.uno/exit`, `puck.uno/abort`, etc.) all live
at the top of the `puck.uno/` namespace — there is no `puck.uno/exception/`
prefix in the UNS. Their relationship to `puck.uno/exception` is by
**declared inheritance**, not by UNS path. Catch behavior, subclass
matching, and the abstract-vs-concrete distinction all follow declared
inheritance — not UNS-prefix matching. (See
[ecoverse/uns.md](../../ecoverse/uns.md) for the general rule that UNS
does not imply inheritance, with xemes as one of the few exceptions.)

If an exception doesn't match any class given to `catch()`, it continues
unwinding up the stack until something does match (or nothing does and it
propagates to the engine top).

<a id="heeding-warnings"></a>
### Heeding warnings

`heed()` matches **non-unwinding events** — warnings:

```
$warnings = heed('foo.com/warning/validation')
    # ... code that may emit validation warnings ...
end

$warnings      # array of warning objects collected during the block
```

Heed all warnings:

```
$warnings = heed()
    # ...
end
```

By default, heeding a warning **collects it and stops its propagation**. To collect
but let it keep traveling up the stack:

```
$warnings = heed(rewarn:true)
    # ...
end
```

A collected warning can be manually re-raised later:

```
$warning.warn         # short form, on the warning object
# or
%chain.warn $warning  # equivalent — pass the object instead of (id, bucket)
```

<a id="auto-recording-into-jasmine"></a>
### Auto-recording into Jasmine

Anything that propagates *out of* a function call — error, exception, or warning
that wasn't heeded — is **automatically recorded into that function's `%chain.log`
entry** before the entry is attached or flushed. Errors include their stack trace;
plain exceptions don't. See
[jasmine/caspian.md § Automatic exception recording](../packages/jasmine/caspian.md#automatic-exception-recording).

<a id="cleanup-with-begin-ensure"></a>
### Cleanup with `begin` / `ensure`

The `begin` bwc creates a scoped variable region. Variables declared inside the
begin block aren't visible outside it:

```
begin
    $var = 'foo'
    # $var is in scope here
end
# $var not available here
```

A `begin` block can have an `ensure` clause that runs on scope exit — normally,
via a raised flag, via `return`, via `exit`, anything that unwinds the scope:

```
begin
    $var = 'foo'
    # main work
ensure
    # always runs (except on abort)
    # $var not available here — the begin block's scope has already exited
end
```

**Ensure guarantees:**

- Runs after the main block, regardless of how it exited (normal completion,
  raised error/exception, `return`, `exit`).
- Does **not** run on `abort` — abort is violent, no unwinding, no GC, no ensure.
- A flag raised inside `ensure` itself propagates normally, overriding any
  in-flight flag that was being unwound (same as Ruby).
- Scope variables from the begin block are **not in scope** in the ensure
  clause — the begin block's scope has already exited by the time `ensure`
  runs. If the cleanup needs a resource, declare it before the `begin` (or
  pass through some other mechanism).

**Composes naturally with `catch`:**

```
$e = catch('foo.com/error/network')
    begin
        $conn = $db.connect
        $conn.query(...)
    ensure
        $db.release_connection
    end
end
```

`ensure` handles cleanup; `catch` handles whether a flag was raised. Each does
one thing.

**Naming note:** `begin` follows Ruby's `begin`/`ensure`/`end` shape for
familiarity. Developers coming from Ruby (and similar shapes in Python's
`try`/`finally`, Java's `try`/`finally`, etc.) will reach for this structure
intuitively.

**Design note (architectural objection):** the `begin ... ensure ... end`
shape introduces a **multi-clause nested structure**, which is unusual for
Caspian. The only other multi-clause structure is `if`/`elsif`/`else`/`end`,
and even that has occasionally been criticized for going against the language's
"primitives are function calls" pattern. An alternative was considered —
**`defer`-style registration** (à la Go/Swift/Zig), where cleanups are
registered as flat statements: `defer do; $conn.close; end`. The defer pattern
avoids the multi-clause structure and puts cleanup near the resource it cleans
up, but the Ruby-flavored `begin`/`ensure` won on familiarity: it's the shape
most developers coming from Ruby, Python, Java, etc. will reach for, and it
reads more naturally to most readers. The architectural concern is noted; the
familiarity argument carried the day.

---

<a id="structured-non-local-control-flow"></a>
## Structured Non-Local Control Flow

~~~json
{"vibecode": {
	"section": "structured_non_local_control_flow",
	"principle": "every_named_non_local_exit_is_a_typed_exception_unwinding_until_a_registered_handler_matches",
	"unifies": ["loop_next", "loop_return",
		"block_return_via_as", "function_return", "raise_catch"],
	"runtime_artifact": "single_control_type_single_throw_single_unwinder",
	"user_facing_surface_unchanged": true,
	"new_exception_subclasses": ["loop/next",
		"loop/return", "block/return",
		"error/stale_handler"],
	"working_names": true,
	"open_questions": ["cross_role_boundary_propagation_policy"]
}}
~~~

Caspian's loop controls (`$loop.next`, `$loop.return`), function
returns (plain `return`), block returns (`$if.return value` on an
`as $if` block), and the exception system (`raise`, `catch`,
`ensure`) are **one mechanism** at the runtime level. Every named
non-local exit is a typed value that unwinds the call stack until a
registered handler matches it. The shape reuses the exception system
described in [Exceptions and Warnings](#exceptions-and-warnings);
loop and block controls are additional subclasses of
`puck.uno/exception`.

This is a runtime-architecture statement, not a new feature spec. The
user-facing surface — next, return, raise, catch, ensure, `as`
— stays exactly as the language docs describe it. The point here is
to name the underlying mechanism so implementations don't grow N
parallel control-flow machineries.

<a id="the-exception-family-extended"></a>
### The exception family, extended

The [exception class hierarchy](#exceptions-and-warnings)
already covers function returns and exits as exception subclasses
(`return`, `exit`). The same model extends to
loop and block controls:

| Class | Raised by | Carries |
|---|---|---|
| `puck.uno/error` | `raise` (default) | message + bucket |
| `puck.uno/return` | plain `return value` | the return value |
| `puck.uno/exit` | `%chain.exit` | the exit code |
| `puck.uno/abort` | `%chain.abort` | engine-fatal; not unwinding via user code |
| `puck.uno/security` | role violation | engine-tagged |
| `puck.uno/timeout_handle` | timeout | engine-tagged |
| `puck.uno/loop/next` | `$loop.next` | target loop id |
| `puck.uno/loop/return` | `$loop.return` (optionally with a value) | target loop id + optional value |
| `puck.uno/block/return` | `$if.return value` (and any `as $name` block) | target block id + value |

All inherit the standard exception shape: class, id, bucket. The
[`catcher` and `unwinds` properties](#exceptions-and-warnings)
from the parent exception class apply.

For loop and block controls, both properties are settled by the
mechanism above:

- **`catcher=engine`** — a user `catch(...)` block cannot intercept
  `$loop.return`, `$loop.next`, `$if.return`, etc. Allowing user
  code to swallow these would hijack the construct's exit semantics;
  only the construct's runner is supposed to consume them. (The name
  `engine` is reused here from the existing convention for
  "user-uncatchable" exceptions. The loop runner isn't technically
  "the engine," but the property does what it says — user `catch`
  doesn't match it.)
- **`unwinds=yes`** — these controls unwind the stack until their
  handler is reached. Ordinary stack-unwinding behavior; `ensure`
  blocks run on the way through.

The class names (`loop/return`, `block/return`, etc.) are working names.
They live at the top of the `puck.uno/` namespace (`puck.uno/loop/return`,
`puck.uno/block/return`) and are declared subclasses of
`puck.uno/exception` — UNS placement and inheritance are independent.
Names may rearrange when the spec gets a unifying pass; what matters at
the architecture level is that they are declared subclasses of
`puck.uno/exception` and participate in the same machinery.

<a id="handler-registration-via-as"></a>
### Handler registration via `as`

`as $name` is the **handler-registration syntax**. When a construct
opens a block with `as`, the runtime registers a handler on its
internal stack tagged with the block's id. The construct's runner
matches incoming controls against the classes it cares about and its
own id.

| Construct with `as` | Handles classes | Tagged with |
|---|---|---|
| `while(...) as $loop` | `loop/next`, `loop/return` | the loop's runtime id |
| `$bar.each($foo) as $loop` | same | same |
| `5.times as $loop do(...)` | same | same |
| `if(...) as $if` | `block/return` | the if-block's runtime id |
| Any block with `as $name` | `block/return` | the block's runtime id |
| `function &foo()` | `return` | the function's call frame |

Plain `return` inside any function uses the enclosing function's
handler regardless of how many blocks or loops are nested between.
A bare `return` does **not** target intermediate `as $if` / `as $loop`
handlers — it unwinds straight through them to the function's
handler.

<a id="target-matching"></a>
### Target matching

A control value carries a `target` field — the id of the handler
it's meant for. The unwinder walks the handler stack from innermost
out:

1. Each handler checks `(value.class, value.target)` against its
   registered class set and its own id.
2. **Match**: the handler consumes the control and resumes whatever
   the construct's resume rule says (loop return exits the loop with
   the optional value; loop next jumps to the top of the next
   iteration; block return exits the block with the carried value;
   function return exits the function).
3. **No match**: the handler passes; the control keeps unwinding.

Nested-loop semantics fall out for free:

```
$outer.each($a) as $loop_a
    $inner.each($b) as $loop_b
        if condition
            $loop_a.return   # targets $loop_a, not $loop_b
        end
    end
end
```

The return value carries `target = $loop_a.id`. The inner loop's
handler doesn't match (its id is `$loop_b.id`), so the control
re-propagates. The outer loop's handler matches; the outer loop
exits.

<a id="ensure-blocks"></a>
### `ensure` blocks

`ensure` blocks register **pass-through** handlers: they run on any
control that crosses them, then re-propagate the original control.
This is why an `ensure` block runs on a loop return the same way it
runs on a function return, an `exit`, or a regular `raise`. One
mechanism, one rule: ensure always runs, then the control continues.

The only exception is `abort` (engine-fatal) — its
`unwinds=no` property bypasses ensure entirely. This is the
intentional asymmetry that keeps untrusted code from using `ensure`
to delay an engine kill.

<a id="stale-handlers"></a>
### Stale handlers

A loop object (or any `as $name` block object) captured in a closure
and called after its construct has exited is **stale** — its handler
is no longer on the runtime's stack. Calling
`.next`/`.return` on a stale handler raises
`puck.uno/error/stale_handler` instead of the control it
would have raised.

```
$stored = null
[1, 2, 3].each($x) as $loop
    $stored = $loop
end

$stored.return   # raises error/stale_handler
```

The stale-handler raise is a normal catchable error (default
`catcher=user`, `unwinds=yes`), so user code can decide what to do
with it.

<a id="cross-role-boundaries-open"></a>
### Cross-role boundaries — open

~~~json
{"vibecode": {
	"section": "cross_role_boundaries",
	"status": "open_question_to_settle_when_role_boundary_semantics_solidify",
	"the_question": "what_happens_when_a_loop_or_block_or_function_control_would_propagate_from_one_role_into_another",
	"plausible_answers": ["block_at_the_boundary_and_convert_to_a_catchable_error_in_the_outer_role",
		"silently_propagate_across_the_boundary_using_the_outer_roles_handler_stack",
		"a_third_option_that_falls_out_of_role_boundary_design_later"]
}}
~~~

A control raised inside one role can in principle propagate across
a role boundary (per [roles.md](../roles.md)) and look for a handler in
the outer role's stack. Whether the runtime allows this — and if
not, what happens at the boundary — is **not yet decided**.

A few plausible shapes:

- **Block at the boundary; convert to a catchable error in the
  outer role.** A loop runner in role B can't be the handler for a
  `$loop.return` raised by code that ran into role A; the propagation
  stops at the boundary, becomes a catchable error in B's caller
  (with the original class + target preserved in the bucket), and
  the caller decides.
- **Silently propagate.** The control walks across the boundary the
  same way it walks across normal frames, using whatever handler
  stack the outer role exposes.
- **Something else** — falls out of the broader role-boundary design
  when that work happens.

Worth settling when the role-boundary mechanics in roles.md get
their next pass. The implementation can keep the choice in one
place (the unwinder's boundary check) once it's made.

<a id="what-this-buys-the-implementation"></a>
### What this buys the implementation

~~~json
{"vibecode": {
	"implementation_payoff": ["single_Control_type",
		"single_throw_function", "single_stack_walking_unwinder",
		"loop_runner_about_twenty_lua_lines",
		"ensure_is_one_pcall_plus_re_raise",
		"cross_role_boundary_check_lives_in_one_place_once_policy_settles"]
}}
~~~

- **One Control type, one throw function, one unwinder.** Not
  separate machinery for next vs. return vs. catch.
- **The loop runner becomes ~20 Lua lines.** Register handler; run
  `before` if first; run body in `pcall`; classify result (loop
  control I own → swallow & continue or exit; other control →
  re-raise; normal return → continue iteration); run `between`
  between iterations; run `after` once at the end (or `noloop` if
  zero iterations); propagate any unrecognized control out.
- **`ensure` is one `pcall` + re-raise** in any host language.
- **Cross-role boundary policy** (once the
  [open question](#cross-role-boundaries-open) settles) **lives in
  one place** — the unwinder — not in N construct-specific paths.
- **New constructs cost almost nothing.** A future `match` statement
  with `as $match` registers a handler for `block/return`; that's
  the whole control-flow integration.

Implementors building Caspian on a host language should build the
Control type and the unwinder first; every construct that exits or
absorbs control then becomes a thin layer over the same primitive.

---

<a id="conditional-constructs-share-one-primitive"></a>
## Conditional Constructs Share One Primitive

~~~json
{"vibecode": {
	"section": "conditional_constructs_share_one_primitive",
	"principle": "if_and_while_share_one_condition_body_primitive_at_runtime; they_differ_only_in_orchestration",
	"shared_primitive_name": "cond_run_once",
	"if_orchestration": "call_sequentially_through_elsif_branches_stop_on_first_match",
	"while_orchestration": "call_in_a_loop_until_false",
	"extensible_to": ["unless", "until", "do_while", "pattern_match_case_clauses"]
}}
~~~

`if` and `while` are kindred constructs at the runtime level. Both
take a condition expression and a body, evaluate the condition for
truthiness, and decide what to do with the body. They differ only in
**what happens after a body runs (or doesn't)**:

- `if` evaluates its condition once. If true, body runs and the
  construct is done. If false, fall through to the next `elsif` or
  the `else`.
- `while` evaluates its condition repeatedly. If true, body runs and
  the loop continues. If false, the construct is done.

A single shared primitive handles the inner mechanic; `if` and
`while` differ only in how they orchestrate calls to it.

<a id="the-shared-primitive"></a>
### The shared primitive

```
function cond_run_once(cond_expr, body)
    if truthy(eval(cond_expr)) then
        execute_body(body)
        return true     -- condition matched, body ran
    end
    return false        -- condition didn't match
end
```

`cond_run_once` is the atom: evaluate one condition, optionally run
one body, report whether it matched. Both `if` and `while` are built
on top.

<a id="if-as-one-shape"></a>
### `if` as one shape

`if` calls `cond_run_once` sequentially against each branch's
condition, stopping at the first match. If no branch matches and an
`else` body exists, it runs unconditionally.

```
function if_runner(branches, else_body, handler_id)
    -- register block/return handler tagged with handler_id (per
    -- the Structured Non-Local Control Flow section)
    for branch in branches do
        if cond_run_once(branch.cond, branch.body) then return end
    end
    if else_body then execute_body(else_body) end
end
```

`branches` is the list of `if`/`elsif` clauses; each has a `cond`
and `body`.

<a id="while-as-another-shape"></a>
### `while` as another shape

`while` calls `cond_run_once` repeatedly until it returns false. The
body lives inside `cond_run_once`'s `execute_body` call, so it runs
in the same handler scope as the loop itself.

```
function while_runner(cond, body, handler_id)
    -- register loop/next + loop/return handlers tagged with handler_id
    while cond_run_once(cond, body) do
        -- intentionally empty; cond_run_once does the work
    end
end
```

The empty Lua `while`-body is intentional: `cond_run_once` handles
both the test and the action; the loop wrapper just calls it until
it reports done.

<a id="what-this-buys-the-implementation-1"></a>
### What this buys the implementation

~~~json
{"vibecode": {
	"sharing_payoff": ["one_condition_evaluation_path",
		"one_body_execution_path",
		"constructs_differ_only_in_orchestration_a_one_liner_each",
		"new_conditional_shapes_layer_on_for_free"]
}}
~~~

- **One condition-evaluation path.** `eval(cond_expr)` plus
  `truthy(value)` lives in one place. Both constructs reuse it.
- **One body-execution path.** `execute_body(body)` plus the
  control-handler registration mechanism (per
  [Structured Non-Local Control Flow](#structured-non-local-control-flow))
  lives in one place.
- **Constructs differ only in orchestration.** `if` is "call once,
  fall through on no match." `while` is "call in a loop, stop on no
  match." Each is a one-liner over the shared primitive.

Combined with the control-flow section above, **the distinct code
for `if` and `while` is small**: about a dozen lines each for the
orchestration logic. Condition evaluation, body execution, control
flow, handler registration, role transitions on cross-boundary
calls — all shared.

<a id="extensibility"></a>
### Extensibility

The same primitive lines up for several construct shapes that may
or may not land in Caspian:

- **`unless cond ... end`** — `cond_run_once` with the condition
  negated; otherwise identical to single-branch `if`.
- **`until cond ... end`** — same as `while` with the condition
  negated.
- **`do ... while cond end`** — call `execute_body` first, then
  `cond_run_once` in a loop. Body runs at least once.
- **Pattern matching (`match value ... case ... case ... end`)** — if
  Caspian ever adds pattern matching, each `case` clause is a
  pattern-matching variant of `cond_run_once` (match-or-not instead
  of truthy-or-not), orchestrated the same way as `if`/`elsif`.

The shared primitive isn't being designed to anticipate any of
these; it just naturally accommodates them because the core
insight — "evaluate one condition, optionally run one body, report
the outcome" — is the same shape.

<a id="what-this-does-not-cover"></a>
### What this does NOT cover

`.each` and the numeric iteration helpers (`.times`, `.upto`,
`.downto`) are **not** built on `cond_run_once`. They have no
condition — the loop runs N times for N elements (or N steps in the
numeric range). They're driven by whichever class implements `.each`,
which typically calls `execute_body` once per element via the
control-flow machinery directly.

So the shared primitive covers `if` / `while` and their
condition-driven cousins; iteration over collections and numeric
ranges is a different family that shares the **control-flow**
mechanism but not the **condition-evaluation** mechanism.

---

<a id="block-parameter-binding"></a>
## Block Parameter Binding

~~~json
{"vibecode": {
	"section": "block_parameter_binding",
	"principle": "every_construct_that_takes_a_block_with_parameters_binds_names_to_values_via_one_shared_primitive",
	"shared_primitive": "bind_params",
	"unifies": ["function_definition_params", "closure_params",
		"do_block_params", "catch_binding", "as_binding"],
	"differences_between_constructs": "the_caller_supplies_a_different_arg_list; the_primitive_is_the_same"
}}
~~~

Every construct that opens a block with named parameters does the
same thing before running the body: pair the parameter list with
the argument list and populate the new scope. The mechanic is one
primitive; the constructs differ only in where their params and
args come from.

<a id="the-shared-primitive-1"></a>
### The shared primitive

```
function bind_params(param_specs, arg_values, scope)
    -- Walk param_specs in parallel with arg_values.
    -- For each spec:
    --   - if a corresponding arg exists, bind name → arg in scope
    --   - else if the spec has a default, bind name → default
    --   - else raise a typed exception (missing required param)
    -- Handle extra args according to the param list's variadic rules.
end
```

`bind_params` is the atom: take a parameter spec list and an arg
value list, populate the target scope. Default values, missing-arg
errors, type checks (if any), and variadic handling all live here
— in one place — instead of in every construct that takes a block.

<a id="constructs"></a>
### Constructs

| Construct | What it binds |
|---|---|
| `function &foo($a, $b)` | call-site args bound to `$a`, `$b` in the function's new scope |
| `function($x) do` (closure form) | same — closure's args bound to its declared params |
| `each($item) do` | each iteration's element bound to `$item` |
| `do($index, $element)` (block params on a do-block) | block params bound from whatever the calling method passes |
| `catch(error) do($e)` | the caught exception bound to `$e` |
| `as $name` (single-name binding) | the construct's runtime object bound to `$name` |

`as $name` is the degenerate case: one parameter, no default, the
"argument" is the construct's runtime object (loop, if-block, etc.)
that the runtime creates before invoking the block.

<a id="what-this-buys-the-implementation-2"></a>
### What this buys the implementation

- **One parameter-binding path.** Default values, missing-arg
  errors, type messages all live in one place; updating any of
  them is a single-site change.
- **New block-taking constructs cost almost nothing.** A future
  `match value ... case ... do($matched) ... end` just calls
  `bind_params` with the matched value as the arg list.
- **The full parameters spec** (positional, named, `*args`, `**opts`,
  splat expansion, etc.) per [parameters.md](../syntax/parameters.md) lives
  behind the same primitive — that doc describes the surface;
  `bind_params` is the runtime implementation.

<a id="open"></a>
### Open

- **Two parameter spec docs exist** — `parameters.md` and `params.md`.
  These cover overlapping ground (one focuses on metadata and lazy
  params; the other on call-site mechanics). Reconciling them is a
  separate task; `bind_params` works against whichever shape settles.
- **`as $name` is currently described in [caspian.md § The `as`
  Keyword](../caspian.md#the-as-keyword) as its own
  concept.** Recognizing it as a one-param `bind_params` call is a
  runtime-implementation observation, not a re-spec.

---

<a id="unified-name-resolution"></a>
## Unified Name Resolution

~~~json
{"vibecode": {
	"section": "unified_name_resolution",
	"principle": "every_named_reference_resolves_through_one_lookup_primitive_parameterized_by_namespace_chain",
	"shared_primitive": "lookup",
	"unifies": ["lexical_variables", "instance_vars", "sys_methods",
		"puck_uns_lookups", "chain_entries", "method_dispatch",
		"bucket_lookups"]
}}
~~~

Every named reference in Caspian — `$foo`, `@foo`, `%foo`,
`puck.uno/foo` via `%puck[...]`, `%chain.foo`, `$obj.foo` for
method dispatch, `bucket.foo` — is a lookup: given a name and a
namespace (or a chain of namespaces tried in order), return the
value or null. The sigil determines which namespace chain to
consult; the lookup mechanism itself is one function.

<a id="the-shared-primitive-2"></a>
### The shared primitive

```
function lookup(name, namespace_chain)
    for ns in namespace_chain
        if ns has name
            return ns[name]
        end
    end
    return null
end
```

`lookup` is the atom: one name, an ordered list of namespaces, the
first hit wins. Cross-namespace fallback (lexical scope walking, MRO
for method dispatch) is just a longer chain.

<a id="constructs-1"></a>
### Constructs

| Reference shape | Namespace chain |
|---|---|
| `$foo` | current lexical scope, then enclosing scope, then enclosing's enclosing, etc. up to the function's top |
| `@foo` | the current instance's bucket |
| `%foo` | the engine's sys-method table |
| `puck.uno/foo` via `%puck[...]` | the current puck's getter table (single namespace) |
| `%chain.foo` | the current frame's `%chain` entries |
| `$obj.foo` (method dispatch) | `obj`'s class's methods, then the class hierarchy walked outward |
| bucket key access | a single bucket (no chain) |

<a id="what-this-buys-the-implementation-3"></a>
### What this buys the implementation

- **One name-resolution path.** Sigil parsing produces a namespace
  chain; the chain goes into `lookup`; the value (or null) comes
  out. The same code serves every sigil.
- **Adding a new sigil costs almost nothing.** Define what namespace
  chain it consults; the lookup mechanism handles the rest.
- **Cross-namespace fallback is explicit.** Each construct's chain
  is visible at the call site; there's no implicit "if not in
  scope, try the class" magic hidden in the interpreter.
- **Method dispatch is a special case of lookup.** Instead of
  separate "resolve method on this class" logic, method dispatch is
  `lookup(method_name, class_method_chain)`.

<a id="open-1"></a>
### Open

- **Whether `lookup` is exposed to user code or kept internal.** A
  user-facing `%puck.lookup` (or similar) might be useful for
  introspection; might be unwanted as engine internal. TBD.
- **Stop conditions for upward scope walks.** Lexical scope walking
  stops at the function boundary; method dispatch stops at the root
  class. These are namespace-chain construction details, not lookup
  itself.

---

<a id="typed-structured-events"></a>
## Typed Structured Events

~~~json
{"vibecode": {
	"section": "typed_structured_events",
	"principle": "exceptions_warnings_change_signals_and_log_entries_share_one_shape_and_one_emission_primitive_differing_only_in_runtime_behavior",
	"shared_shape": ["class", "id", "bucket"],
	"shared_primitive": "emit_event",
	"behaviors": ["unwinding", "heedable", "signal", "log"],
	"largest_restructuring_of_the_three": true,
	"status": "candidate_for_future_unifying_pass"
}}
~~~

Four subsystems in Caspian emit typed structured events:
**exceptions**, **warnings**, **change signals**, and **Jasmine log
entries**. They already share the same outer shape — `class`, `id`,
`bucket` — and most of them are emitted through `%chain` methods.
They differ only in **what the runtime does** with each emission.
A single emission primitive parameterized by a behavior could
underlie all four.

This is the **most invasive** of the three tightening candidates:
it touches the existing exception/warning spec, change signals, and
Jasmine. The other two (block params, name resolution) are
implementation tightenings without spec impact. This one would
involve a unifying pass through several docs to align terminology
and emission paths. Filed as an architecture direction rather than
an immediate-action item.

<a id="the-shared-shape"></a>
### The shared shape

Every event is `{class, id, bucket}` plus the same emission path
through `%chain` (or its equivalent). Already true today for
exceptions and warnings per
[Exceptions and Warnings](#exceptions-and-warnings);
extends to change signals and log entries with no schema change.

<a id="behaviors"></a>
### Behaviors

| Behavior | What the runtime does | Used by |
|---|---|---|
| **unwinding** | Propagate up the stack until a registered handler matches; `ensure` runs on the way through; if uncaught, reaches the engine | Exceptions (`error`, `return`, `exit`, `loop/return`, `block/return`, `abort`, `security`, `timeout_handle`) |
| **heedable** | Run any observers attached via `heed()`; no unwinding; engine continues | Warnings |
| **signal** | Run any registered observers; no unwinding; observers are typically not user-facing | Change signals (mutation observation) |
| **log** | Write to the configured log sink (Jasmine); no observers, no unwinding | Jasmine entries |

The behavior is a property of the event's class — set at class-
definition time, not at the emission site. `%chain.error` raises
something with `behavior=unwinding`; `%chain.warn` raises something
with `behavior=heedable`; the engine emits change signals with
`behavior=signal`; Jasmine entries are `behavior=log`.

<a id="the-shared-primitive-3"></a>
### The shared primitive

```
function emit_event(event)
    -- event has class, id, bucket; the class declares its behavior.
    -- Dispatch on the class's behavior:
    --   unwinding → throw it; the unwinder propagates per the
    --     Structured Non-Local Control Flow section
    --   heedable  → invoke registered heeders; if none, no-op
    --   signal    → invoke registered observers; if none, no-op
    --   log       → write to the log sink
end
```

One emission function; the runtime path is selected from the
event's class metadata, not from which `%chain.X` method was called.

<a id="what-this-buys-the-implementation-4"></a>
### What this buys the implementation

- **One emission path.** No separate functions for raising vs.
  warning vs. signaling vs. logging.
- **One observer-registration mechanism.** `catch`, `heed`, change-
  signal observers, and Jasmine sink registration all configure
  the same dispatch table, just for different behaviors.
- **Shared shape across four subsystems.** Class, id, bucket;
  catcher/unwinds/observer-set; all in one place.
- **Adding a new event kind = adding a new behavior.** No new
  emission machinery, no new dispatch path.

<a id="open-2"></a>
### Open

~~~json
{"vibecode": {
	"events_open": [
		"unifying_terminology_event_vs_signal_vs_flag",
		"reconciling_the_emission_apis_chain_error_chain_warn_etc_under_one_emit_function",
		"whether_jasmine_log_sink_registration_fits_the_observer_pattern_or_needs_its_own_path",
		"whether_change_signal_observers_are_the_same_objects_as_heeders_or_different"]
}}
~~~

- **Terminology.** Current docs call the family "flags" in places,
  "events" and "signals" elsewhere. A unifying pass would pick one
  term and propagate it.
- **Emission APIs.** `%chain.error`, `%chain.warn`, `%chain.throw`,
  change-signal emission, `%jasmine.X` — could all reduce to one
  `%chain.emit(event)` or similar, with sugar where helpful. The
  current per-behavior method names are user-friendly; collapsing
  them risks losing that clarity. Worth weighing.
- **Observer registration.** Whether `catch`, `heed`, change-signal
  observers, and Jasmine sinks are facets of one registration
  mechanism or four different things that happen to feed the same
  dispatch — TBD.
- **Whether to do this pass at all.** The other two unifications
  (block params, name resolution) are pure wins; this one has real
  cost (the unifying-pass work). Worth doing if the runtime payoff
  is large; possibly defer if the existing four subsystems are
  already clean enough in isolation.

---

<a id="object-model"></a>
## Object Model

~~~json
{"vibecode": {
	"section": "object_model",
	"two_properties": ["classes", "bucket"],
	"classes": "class_stack_array_resolved_top_down",
	"bucket": "%bucket hash shared by all classes in stack",
	"object_classes_order": ["base_class", "additional_classes"],
	"shadow_class": "implicit_always_first_in_resolution_not_in_object_classes",
	"object_helper": "reserved_built_in_cannot_be_overridden",
	"explicit_dispatch": "$class.object.call_with($foo, 'method', args)"
}}
~~~

<a id="two-property-objects"></a>
### Two-Property Objects

Every object has exactly two fundamental properties:

- **classes** — the class stack, an array of classes whose methods the object inherits
- **bucket** — a single shared hash where all the object's data lives

Everything else — methods, accessors, helpers — is behavior layered on top of these two
primitives. This maps directly to how mikobase records work: class + bucket. The mental
model is consistent across the language and the object store.

<a id="bucket"></a>
### `%bucket`

`%bucket` is a system method that returns the object's private data hash. All instance
data lives here.

```
%bucket['foo'] = 'bar'
%bucket['foo']          # 'bar'
```

`@foo` is shorthand for `%bucket['foo']`. The `accessor` declaration in a class creates
getters/setters that read and write from `%bucket`.

```
@foo = 'bar'             # same as %bucket['foo'] = 'bar'
```

All classes in the stack share the same `%bucket` hash. Key collision between classes
is the developer's responsibility.

Serialization is straightforward — `%bucket` is the object's data, so exporting it
exports the object's state.

**Buckets are not Puck hashes.** The global Puck hash-key standard (snake_case
names, JSON-shaped data) does not apply to object buckets. Buckets are internal
storage with their own conventions; class designers pick whatever keys make sense
for their state.

**The `uns` bucket-key convention.** A Puck-wide convention reserves the bucket
key `uns` for a sub-hash organized by UNS strings. When a bucket has an `uns`
key, the value is understood as a hash of "things keyed by UNS" — each entry's
key is a class UNS and its value is whatever state that UNS-keyed entity wants
to store.

```
%bucket = {
    foo: 'bar',           # host class's own state
    baz: 42,
    uns: {
        'puck.uno/trivet/node': {parent: ..., children: ..., id: ...},
        'puck.uno/uma/text':    {...},
    }
}
```

The primary use case is **classes that get added to arbitrary host objects as
mix-ins** — Trivet's node class is the canonical example. The mix-in stores its
state under `uns.<its-UNS>` rather than at the top level of the bucket, so it
doesn't collide with whatever the host class is already using.

Host classes that don't use mix-ins can ignore the convention entirely. Classes
that *are* mix-ins should namespace their state into the `uns` slot; host
classes leave `uns` alone.

This is a convention, not enforcement. The runtime treats the bucket as a flat
hash; `uns` is just a reserved key by community agreement.

<a id="the-class-stack"></a>
### The Class Stack

Method calls are resolved top-down through the class stack:

1. **Shadow class** — always consulted first. Implicit — not returned by `object.classes`.
   Used to define methods on a single object without affecting the class.
2. **Base class** — the class the object was instantiated from.
3. **Additional classes** — any further classes added to the stack.

The first class in the resolution order that defines the method wins.

To add methods to an object's shadow class, use `object.define`:

```
$foo.object.define do
    function &bar
        ...
    end
end
```

`object.define` is shorthand for `$foo.object.shadow.define`. Both open the shadow class
as a definition context for the block. Inside a class body, `self` refers to the class
object itself, so class-level methods are defined the same way:

```
class 'color'
    self.object.define do
        function &blue
            return color.new(hex: '#0000ff')
        end
    end
end
```

<a id="the-object-helper"></a>
### The `object` Helper

Every object has a reserved helper called `object` that cannot be overridden. It exposes
meta information about the object:

```
$foo.object.classes      # the explicit class stack (base class + any additional classes)
                         # does not include the shadow class

$foo.object.isa? 'puck.uno/color'    # true if 'puck.uno/color' is in the class stack
                                       # (the object's class or any superclass)
```

The `isa?` predicate walks the object's class stack and returns true if the given UNS
matches any class in the stack. Use it to check class membership without caring about
the exact resolution path:

```
if $foo.object.isa? 'puck.uno/error'
    # $foo is an error of some kind
end
```

The trailing `?` is the Caspian convention for predicate methods (boolean-returning).

More meta information will be added as needed.

<a id="explicit-class-dispatch"></a>
### Explicit Class Dispatch

To call a method from a specific class in the stack, use `object.call_with`. The class
must be present in the object's class stack:

```
$class = $foo.object.classes.find(...)
$class.object.call_with($foo, 'greet', name: 'Jean-Luc')
```

This is a rare use case — normal method resolution handles the common case.

---

<a id="helpers"></a>
## Helpers

~~~json
{"vibecode": {
	"section": "helpers",
	"base_class": "puck.uno/helper",
	"purpose": "namespace_methods_without_polluting_main_object_namespace",
	"access": "self.reference points back to parent object",
	"initialization": "lazy_not_created_until_first_accessed",
	"reserved_helper": "object built_in_present_on_every_object_cannot_be_overridden"
}}
~~~

A helper is an instance of `puck.uno/helper`. It provides a way to namespace methods
without polluting the main method namespace of an object.

The base helper class defines a single field: `@reference`, which points back to the
parent object. Inside a helper method, `self.reference` accesses the parent.

<a id="defining-a-helper"></a>
### Defining a helper

The `helper` bwc inside a class definition creates a lazily initialized helper:

```
$myclass = class
    helper foo
        function &bar()
            return self.reference.gup
        end
    end
end

$myclass.foo.bar
```

This is shorthand for creating a helper class and a lazy getter that instantiates it
with `self` as the reference:

```
$myclass = class
    function &foo()
        return @foo ||= $helper_class.new(self)
    end
end
```

The helper is not created until first accessed.

<a id="object-as-a-reserved-helper"></a>
### `object` as a Reserved Helper

`object` is a built-in helper present on every object. It cannot be overridden. It is
the home for primitive introspection operations that are rarely needed day-to-day,
keeping them out of the main method namespace.

---

<a id="classes"></a>
## Classes

~~~json
{"vibecode": {
	"section": "classes",
	"identity": "from_reference_held_not_declared_name",
	"no_global_registry": true,
	"puck_namespace": "%puck[UNS] to access registered objects",
	"definition": "$myclass = class...end or %puck['puck.uno/object'].subclass do...end",
	"subclassing": "$new_class = $my_class.subclass do...end",
	"accessors": "declared with accessor @foo :get :set default:",
	"abstract": "abstract true prevents direct instantiation",
	"initializer": "init method",
	"methods": "function &name() inside class block"
}}
~~~

Classes are objects. Like functions, they live wherever they are stored. There is no global
class registry and no namespacing system like `Foo::Bar`. A class's identity comes from the
reference held to it, not from a declared name. To use a class, you need a reference to it.

<a id="puck"></a>
### `%puck`

`%puck` is a system method that provides access to the global Puck object namespace.
`%puck[UNS]` returns the object registered at that UNS address — which may be a class,
but is not limited to classes.

```
%puck['puck.uno/mikobase/memory'].new
%puck['puck.uno/mikobase/http'].new(mikobase: $mikobase, socket: '/var/run/myhive.sock', auth: :peer)
```

In the first version, `%puck` only resolves a predefined set of built-in objects. When
and how remote objects can be retrieved via `%puck` is a Puck design question for later.

Class definition syntax is a DSL — it uses the same dispatcher/bwc mechanism as any
other DSL. There are no special parser rules for class definitions.

<a id="instantiation"></a>
### Instantiation

```
$my_class.new(...)
```

<a id="defining-a-class"></a>
### Defining a class

The standard form:

```
$myclass = class
end
```

For developers who need explicit access to the root class:

```
$myclass = %puck['puck.uno/object'].subclass do
end
```

<a id="subclassing"></a>
### Subclassing

```
$new_class = $my_class.subclass do
end
```

Subclassing is always a method call on the parent class object.

<a id="accessors"></a>
### Accessors

Accessors are private instance variables declared with `accessor`. They are not
accessible from outside the class unless `:get` / `:set` flags are declared.

```
accessor @foo                  # private, no external access
accessor @bar, :get            # creates a getter: bar()
accessor @gup, :set            # creates a setter: gup=()
accessor @baz, :get, :set      # creates both
```

Mechanically, the getter/setter read from and write to `%bucket['<name>']` —
accessors are just typed sugar over bucket access.

`:get` and `'get'` are equivalent — `:foo` is shorthand for `'foo'` throughout Caspian.

A `default:` option is reserved for a future revision; not in v1.

<a id="abstract-classes"></a>
### Abstract Classes

A class declared `abstract true` cannot be directly instantiated. It must be subclassed.
Attempting to call `.new` on an abstract class raises an exception.

```
$myclass = class
    abstract true
end
```

<a id="initializer"></a>
### Initializer

`init` is the method called when a new instance is created. It is defined using
`function &init(...)` inside the class block:

```
function &init($name, $birthdate)
    @name = $name
    @birthdate = $birthdate
end
```

<a id="methods"></a>
### Methods

Methods are defined inside the class block using `function &name(...)`:

```
function &greet()
    return "Hello, I am " + @name
end
```

<a id="full-example"></a>
### Full Example

```
$person = class
    accessor @name, :get
    accessor @birthdate, :get
    accessor @email, :get, :set
    accessor @active, default: false

    function &init($name, $birthdate)
        @name = $name
        @birthdate = $birthdate
        @email = null
    end

    function &greet()
        return "Hello, I am " + @name
    end
end

$p = $person.new(name: 'Jean-Luc', birthdate: '2305-07-13')
$p.greet   # "Hello, I am Jean-Luc"
```

<a id="subclass-example"></a>
### Subclass Example

```
$officer = $person.subclass do
    accessor @rank, :get

    function &init($name, $birthdate, $rank)
        @rank = $rank
    end

    function &greet()
        return @rank + " " + @name
    end
end
```

---

<a id="functions"></a>
## Functions

~~~json
{"vibecode": {
	"section": "functions",
	"first_class": true,
	"no_lambda_syntax": "all_functions_already_objects",
	"blocks": "do...end closure multiple_blocks_chained",
	"yielding": "$dispatcher.yield or yield shortcut",
	"bwc_resolution_order": ["reserved_bwcs", "dsl_entries", "scope_variables"],
	"dsl_receivers": "dispatcher.dsl maps bare words to objects in yielded block",
	"caller_objects": "$foo.caller reusable configurable pending call",
	"amp_method": "any_class_can_define_& to_make_instances_invokable"
}}
~~~

Functions are first-class objects. They can be assigned to variables, passed as arguments,
and assigned to class methods. There is no concept of a named function — a function is just
an object stored somewhere. They live where they're stored.

There is no lambda syntax. In other languages, lambdas exist to create passable function
objects. In Caspian, all functions are already objects.

See `caspian.md` for function definition and call syntax.

<a id="blocks-and-yielding"></a>
### Blocks and Yielding

A `do...end` block passed to a function call is a closure. Multiple blocks can be chained.
Inside the function, `%call.blocks` is an array of the passed blocks in order.

`do...end` is only intended for a short array of blocks. If you want to get fancy with
named blocks then pass them as named params.

The official way to call a block uses a dispatcher object:

```
$myfunc = function()
    $dispatcher = %call.dispatcher       # defaults to block at index 0
    $dispatcher = %call.dispatcher(1)    # explicit block index

    $dispatcher.yield 'gup', 'bear'
end

&myfunc do($a, $b)
    $a   # 'gup'
    $b   # 'bear'
end
```

`&dispatcher` is shorthand for `$dispatcher.yield`:

```
&dispatcher 'gup', 'bear'
```

`yield` is a top-level shortcut for `%call.dispatcher.yield`:

```
$myfunc = function()
    yield 'gup', 'bear'
end
```

Multiple blocks are chained with additional `do...end` after each `end`:

```
&myfunc do($a)
end do($b)
end
```

To yield to a specific block, use an explicit dispatcher index. `yield` always hits
block 0.

If you want named blocks, pass functions as named parameters instead.

<a id="bare-word-commands"></a>
### Bare Word Commands

A bare word command (bwc) is an unqualified word used as a method call. When the
interpreter encounters a bwc, it looks in `%scope` to find the correct association.

This section documents the underlying dispatcher mechanism. For Caspian's language-wide
commitment to using DSLs (the four-tier model, function-property convention, loop and
class DSLs, the cheat clause), see [dsl.md](../dsl.md).

Resolution order:

1. **Reserved bwcs** — built-in keywords such as `if` and `while`. These cannot be
   overwritten under any circumstances.
2. **DSL entries** — set via `$dispatcher.dsl`. Evaluated before the incoming scope,
   so DSL mappings can override scope variables.
3. **Scope variables** — the normal lexical scope.

<a id="dsl-receivers"></a>
### DSL Receivers

The dispatcher object has a `dsl` hash. Entries map bare words inside the yielded block
to objects — a bwc resolves to a method call on the mapped object.

```
$myfunc = function()
    $dispatcher = %call.dispatcher
    $dispatcher.dsl['foo'] = $bar

    $dispatcher.yield
end

&myfunc do
    foo   # calls $bar.foo
    gup   # calls $bar.gup
end
```

DSL entries take priority over scope variables, making them suitable for overriding
default behavior inside a closure. Receivers are scoped to the closure call and do not
leak into the surrounding scope.

DSL settings do not propagate down the call stack. They apply only to the directly
yielded block — any nested function calls or blocks inside that block run without them.

---

<a id="scoping"></a>
## Scoping

~~~json
{"vibecode": {
	"section": "scoping",
	"scope_per_block": true,
	"applies_to": ["if", "else", "loop_bodies", "bare_blocks"],
	"first_class_scopes": true,
	"closure_mechanism": "pass_scope_object_explicitly_to_function"
}}
~~~

Every block creates a new scope that inherits from its parent. This applies to all blocks
without exception — `if`, `else`, loop bodies, and bare blocks all create new scopes.

Scopes are first-class objects. This is the mechanism by which closures are implemented:
a scope object can be passed explicitly to a function, making it act as a closure. There
is no special closure type — any function becomes a closure when passed a scope.

---

<a id="system-methods"></a>
## System Methods

~~~json
{"vibecode": {
	"section": "system_methods",
	"prefix": "%",
	"not": "global_variables",
	"behavior": "scope_aware_may_return_different_objects_in_different_scopes",
	"defined_by": "engine_at_boot_time_only",
	"key_methods": {
		"%chain": "ambient_context_carries_request_scoped_values",
		"%engine": "gateway_to_host_resources_top_level_only_non_capturable",
		"%call": "current_call_object_function_or_closure"
	}
}}
~~~

Caspian has a small number of system methods, prefixed with `%`. These are not global
variables — they are methods that return a scope-aware object. The same method call in
different scopes may return different objects.

System methods are defined only by the engine at boot time. User code cannot create new
`%`-prefixed methods.

<a id="chain"></a>
### `%chain`

> **Use `%chain` sparingly.** It is ambient state that is invisible in function signatures
> and can carry security-sensitive information. Prefer explicit arguments when possible.
> The security implications of `%chain` are discussed separately.

`%chain` is the chain context object. It carries information down the call stack —
current user, request ID, locale, transaction context, security settings — without
requiring it to be threaded through every function signature.

`%chain` has two main components: `misc` for arbitrary values, and `stack` for the
call stack.

<a id="block-vs-function-isolation"></a>
#### Block vs function isolation

`%chain` does **not** isolate at block boundaries. A write to `%chain['foo']` inside an
`if`, loop, or bare block persists after the block ends — chain flows freely through
blocks within the same function. This is unlike `%scope`, where every block creates a new
inherited scope.

Isolation happens at **function call boundaries**. When a function is called, it gets its
own chain that inherits from the caller's, but writes inside the callee do not propagate
back up. The caller's chain is unchanged after the call returns.

If you want block-level isolation, use `%chain.scope do...end` to create an explicit
boundary inside the same function.

`%chain` is cleared at role boundaries and inside `%chain.clear` blocks.

`%stdout` and `%stderr` **do** live in `%chain`. The system methods `%stdout` / `%stderr`
read from chain; the engine places them at bootstrap, always as a real handle —
either pointing at a real destination (terminal, capture buffer, etc.) or as a
dev/null handle that discards writes (with a nanny warning, silenceable via
`no_writers_ok`). They are **never null**, so writes can be sprinkled in without
guards. This is also why `%stdout.capture do ... end` works without special primitives —
it creates an inherited chain scope where `%stdout` is the capture buffer, runs the
block, and the parent's `%stdout` is restored on exit. Same mechanism as function-call
chain isolation, applied to a single ambient handle.

STDIN is different: it's **not** in `%chain`. The engine hands the script a STDIN object
at bootstrap, and functions that need it must receive it as an explicit parameter. The
asymmetry: incoming data needs role labeling (so the object travels explicitly with its
role), while outgoing handles can be ambient (writes don't carry a role label, so the
chain-replacement pattern works cleanly).

<a id="misc-values"></a>
#### Misc values

```
%chain.misc['foo'] = 'bar'
%chain.misc['foo']          # 'bar'
```

`%chain['foo']` is shorthand for `%chain.misc['foo']`.

<a id="sandboxing"></a>
#### Sandboxing

Each component can be cleared within a block, hiding it from code running inside:

```
# hide the call stack from untrusted code
%chain.stack.clear() do
    # %call does not have the full stack here
end

# hide misc values from untrusted code
%chain.misc.clear() do
    %chain['foo']   # null
end

# clear everything
%chain.clear() do
    # no stack, no misc values
end
```

After each block, the original values are restored. `%chain.clear()` will clear all
components, including any added in future.

<a id="explicit-scope-block"></a>
#### Explicit scope block

`%chain.scope do...end` creates an explicit scope boundary:

```
%chain['foo'] = 'bar'

%chain.scope do
    %chain['foo']   # 'bar'
    %chain['foo'] = 'gup'
    %chain['foo']   # 'gup'
end

%chain['foo']       # 'bar'
```

<a id="clean-scope"></a>
#### Clean scope

`%chain.scope(inherit:false)` starts with an empty chain, inheriting nothing:

```
%chain['foo'] = 'bar'

%chain.scope(inherit:false) do
    %chain['foo']   # null
end

%chain['foo']       # 'bar'
```

---

<a id="engine"></a>
### `%engine`

`%engine` is a method that returns the engine object — the gateway through which the
top-level script accesses resources provided by the host (capabilities, configuration,
injected objects).

Two distinct properties make it secure:

**The method is scope-restricted.** `%engine` only exists in the outermost script scope.
**Functions** do not have it in their scope — they don't capture outer scope at all, so
`%engine` is simply absent inside any function. **Closures** defined at the outermost
scope *do* see `%engine`, because closures capture their lexical scope by design and the
outermost scope is part of what they capture. A closure defined inside a function doesn't
see `%engine` either (the function it was defined inside doesn't have it).

This matches the language's own promise about closures: they capture what's in their
defining scope. Forcing closures to omit `%engine` specifically would be a special-case
exception that goes against the model. The developer chose `closure` over `function`
precisely to opt in to scope capture; the runtime honors that choice.

**The engine object is non-storable.** Even in the outermost scope (or inside a closure
that captured the outermost scope), the object returned by `%engine` cannot be assigned
to a variable. This is enforced by the runtime:

```
$db   = %engine['db']    # fine — using the object directly
$docs = %engine['docs']  # fine

$e = %engine             # raises — engine object is non-storable
```

The non-storable rule is the load-bearing security guarantee: `%engine` itself can't be
extracted into a variable that can be passed around. Specific resources pulled out of it
can be passed around freely.

The bootstrap pattern: the top-level script calls methods on `%engine` directly to pull
out what it needs, then passes those resources down to functions explicitly as parameters.
Closures defined at the top level can reference `%engine` directly if useful — their
auto-capture lets them. Functions need things passed explicitly.

<a id="function-and-closure-opacity"></a>
### Function and closure opacity

**Once a function or closure is defined, it exposes nothing about its internals to its
caller.** This is a general default that applies to every callable in the language. A
caller can *call* a function or closure and receive its return value. That's all.

Specifically, none of the following is accessible to a caller:

- The function's or closure's body code.
- A closure's captured scope (variables, references, anything pulled in by the lexical
  capture).
- A closure's captured `%engine` reference, if any.
- Internal stack frames during or after the call.
- Parameter defaults set at definition time.
- Equality or identity comparisons that would reveal contents (beyond "is this the same
  callable object?").

There is no opt-out at definition time, and no API a caller can use to peer inside.
Opacity is enforced uniformly — by language rule, not by per-callable configuration.

**Testing requirement.** This opacity guarantee is load-bearing for the security model
(especially for closures capturing `%engine`, but more broadly for any function or
closure carrying captured resources). It needs an extensive test suite verifying it holds
against every introspection surface:

- Direct access (`$fn.scope`, `$fn.body`, `$fn.captures`, etc.) — must not exist or
  refuse.
- Indirect access via exception traces, stack inspection, or call metadata — must not
  leak captured values.
- Finished closures (after they've returned) — must not be inspectable for their
  captured state.
- Closure / function equality — must not reveal contents.

If any introspection path leaks, the language has a security regression that needs to be
fixed before the leak is exploited.

**Possible future feature:** an opt-in inspection capability granted at definition time
for debugging or REPL use cases — `function .introspectable &foo() ... end` or similar.
Not in v1; flagged if a real debugging story needs it.

---

<a id="call"></a>
### `%call`

`%call` returns the call object for the current function or closure. Inside a closure,
`%call` refers to the closure call. Inside a function, it refers to the function call.

```
function &foo()
    %call           # the call to foo

    &bar() do
        %call           # the call to the closure
        %call.return    # return from the closure
        return          # return from foo
    end

    %call.return    # return from foo
    return          # also return from foo
end
```

`%call.return` exits the current call (function or closure) and returns a value from it.
`return` always exits the calling function, propagating through closure boundaries.

`%call.blocks` is an array of `do...end` blocks passed to the current function, in order.

<a id="caller-objects"></a>
### Caller Objects

`$foo.caller` returns a caller object — a reusable, configurable pending call to `$foo`.
Parameters are set as properties, blocks are attached with `do`, and the call is executed
with `.call`.

```
$foo = function(gup)
end

$caller = $foo.caller
$caller.gup = 'bear'
$caller.call
```

Caller objects are first-class — they can be passed around, further configured, and
executed by whoever holds them. Setting a param before passing restricts what the receiver
needs to supply.

<a id="setting-params"></a>
#### Setting params

```
$caller.gup = 'bear'
```

<a id="attaching-blocks"></a>
#### Attaching blocks

Official form:

```
$caller.foo = do
end
```

Shorthand (what The People will want):

```
$caller.foo do
end
```

Multiple anonymous blocks are available via `$caller.blocks`, which is an array. For
anything beyond simple cases, use named params instead.

<a id="executing"></a>
#### Executing

```
$caller.call
```

Locking and freezing a caller before passing it around is deferred for later design.

---

<a id="the-method"></a>
### The `&` Method

Any class can define a `&` method to make its instances invokable with the `&` sigil.
`&` means "do the main thing on this object."

- Functions define `&` to call themselves
- Callers define `&` to execute their call
- Any other class can define `&` for its own main action

```
&my_function   # calls my_function.call
&my_caller     # calls my_caller.call
```

How to define a `&` method in a class definition is deferred until method definition
syntax is designed.

---

<a id="jail"></a>
## Jail

~~~json
{"vibecode": {
	"section": "jail",
	"concept": "capability_restricting_proxy_wraps_object_exposes_only_allowed_methods",
	"creation": "$foo.object.jail(:method1, :method2)",
	"storage": "prisoner and allowed in %bucket",
	"security_model": "object_capability",
	"callable_jail": "when prisoner is function jail with :call is callable"
}}
~~~

A jail is a capability-restricting proxy object. It wraps another object and exposes only
a specified list of allowed methods. Calls to allowed methods are forwarded transparently
to the underlying object. Calls to any other method fail.

The underlying object is unaware that it is being called through a jail. However, a method
that explicitly inspects the call stack can see it.

Jail fits naturally with the object-capability security model: pass a jail instead of the
full object when the recipient only needs a subset of its capabilities.

<a id="internal-structure"></a>
### Internal structure

A jail stores the wrapped object in `%bucket`:

```
@prisoner   # the wrapped object
@allowed    # array of permitted method names
```

External code cannot reach `@prisoner` directly through the jail — that is the point.

<a id="creating-a-jail"></a>
### Creating a jail

```
$jail = $foo.object.jail(:greet, :save)

$jail.greet(name: 'Jean-Luc')   # forwarded to @prisoner
$jail.destroy                   # fails
```

When `@prisoner` is a function, the jail is callable:

```
$bar = $foo.object.jail(:call)
&bar   # forwards to @prisoner
```

---

<a id="freezing"></a>
## Freezing

~~~json
{"vibecode": {
	"section": "freezing",
	"axes": ["classes", "bucket"],
	"operations": ["$foo.object.freeze", "$foo.object.classes.freeze",
		"$foo.object.bucket.freeze"],
	"permanent": "without_block_no_unfreeze",
	"temporary": "with_block_releases_when_block_exits",
	"classes_freeze_prevents": "class_stack_modification_object_define_blocked",
	"bucket_freeze_prevents": "%bucket_writes",
	"object_bucket_returns": "jail_wrapping_%bucket_with_only_freeze_permitted"
}}
~~~

Freezing locks an object against modification. Caspian breaks this into two independent
axes — the class stack and bucket — rather than conflating them into a single freeze.

<a id="the-three-freeze-operations"></a>
### The three freeze operations

```
$foo.object.freeze          # freeze both classes and bucket
$foo.object.classes.freeze  # freeze the class stack only
$foo.object.bucket.freeze  # freeze %bucket only
```

Any of these can be called by whoever holds a reference to the object — freezing is not
restricted to the object itself.

<a id="permanent-vs-temporary"></a>
### Permanent vs. temporary

Without a block, a freeze is permanent. There is no `unfreeze` method. Once frozen, that
axis stays frozen for the lifetime of the object.

With a block, the freeze is temporary — it holds for the duration of the block and releases
when the block exits:

```
$foo.object.freeze do
    # both classes and bucket are frozen here
end

$foo.object.classes.freeze do
    # class stack is frozen here
end

$foo.object.bucket.freeze do
    # %bucket is frozen here
end
```

<a id="what-each-freeze-prevents"></a>
### What each freeze prevents

**Classes freeze** — the class stack cannot be modified. No classes can be added or
removed, and `object.define` is blocked. The methods the object has
at freeze time are the methods it will always have.

**Bucket freeze** — `%bucket` becomes read-only. Any attempt to write to `@foo` or
otherwise modify the bucket hash raises an error.

<a id="fooobjectbucket"></a>
### `$foo.object.bucket`

`$foo.object.bucket` returns a jail wrapping `%bucket` with only `:freeze` permitted.
It gives external code the ability to freeze the object's bucket without exposing
the data itself:

```
$foo.object.bucket.freeze       # fine — one permitted operation
$foo.object.bucket['key']       # fails — not in the allowed method list
```

---

<a id="change-signals"></a>
## Change Signals

~~~json
{"vibecode": {
	"section": "change_signals",
	"trigger": "hash_key_assigned_new_object",
	"listener_api": "$foo.object.listen field: 'bar', :on_change do($change) end",
	"change_object_fields": ["field", "old_value", "new_value"],
	"propagation": "auto_up_through_every_object_holding_changed_object",
	"signal_stack": "central_one_at_a_time_in_single_threaded_model",
	"deduplication": "object_can_appear_on_stack_at_most_once",
	"lazy_check": "skip_signal_if_nothing_listens",
	"hot_records": "mechanism_behind_automatic_mikobase_saves_on_write"
}}
~~~

<a id="what-a-change-is"></a>
### What a change is

A change is a hash key being assigned a new object:

```
$foo['bar'] = $something   # change event fires on $foo
```

Scalars do not change. Assigning `2` where `1` was does not change the number `1` — it
replaces a reference. Only hashes produce change events, because only hashes hold
references that can be reassigned.

<a id="listening-to-field-changes"></a>
### Listening to field changes

```
$foo.object.listen field: 'bar', :on_change do($change)
    # fires when $foo['bar'] is assigned a new object
end
```

The block receives a change object:

```
$change.field      # the key that changed ('bar')
$change.old_value  # the previous object
$change.new_value  # the newly assigned object
```

<a id="signal-propagation"></a>
### Signal propagation

When a hash key is reassigned, the signal propagates automatically up through every
object that holds the changed object. Given:

```
$foo['bar']['gup']['baz']['bear'] = 1
```

1. `baz` changes → signals `gup` (which holds `baz`)
2. `gup` changes → signals `bar` (which holds `gup`)
3. `bar` changes → signals `foo` (which holds `bar`)
4. `foo`'s listener fires

Each object in the chain automatically re-signals its own listeners when it hears a
signal from an object it holds.

<a id="the-signal-stack"></a>
### The signal stack

Signals are processed through a central stack, one at a time, in order. In Caspian's
single-threaded execution model, there is always either zero or one signal being
processed. This eliminates concurrent signal storms — a new signal is never processed
until the current one completes.

Three rules keep propagation tractable:

**Lazy check.** Before pushing a signal onto the stack, the system checks whether
anything listens to the changed object. If nothing is registered, the signal is skipped
entirely. Most objects have no listeners, so this makes the common case free.

**Deduplication.** An object can appear on the stack at most once. If a signal for an
object that is already on the stack is generated, it is dropped. This handles any
remaining cycle risk — a listener that reassigns a hash key can only trigger one
additional signal per object.

**Terminal listeners.** Most listeners do work and stop — they call `$foo.save`, write
to a log, update a counter. They do not reassign hash keys, so they generate no further
signals. Cycles only arise when a listener reassigns a hash key, which is the unusual
case.

<a id="underlying-hot-records"></a>
### Underlying hot records

The change signal system is the mechanism that makes hot mikobase records work. When a hot
connection returns a record, the runtime automatically registers listeners up the
reference chain. A write anywhere in the chain triggers a save back to the mikobase without
the developer doing anything explicitly.

See [mikobase.md](../../mikobase/mikobase.md) for the hot record design.
