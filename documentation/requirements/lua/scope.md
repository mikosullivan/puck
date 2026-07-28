# scope

<span class="tag">scope</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_lua_scope",
	"role": "spec for the scope runtime — the engine-internal Lua machinery that tracks Caspian variable bindings across nested blocks, function calls, and closure captures. A scope is an instance of the aggregate-hash primitive whose elements are per-frame hashes and whose walk-order is end-to-start (innermost frame wins). The scope runtime layers walk-then-write semantics on top of aggs' read-only interface: variable assignment walks the chain to find the owning element and mutates in place; the not-found policy (create new local, raise, or require declaration) is open. Multiple scopes coexist naturally — one per active call frame, plus any scopes captured by live closures. NOT a Caspian-facing class; developers do not construct %('core:scope').",
	"status": "brainstorm — model settled at the concept level (scope IS an agg, scope elements are its hashes, closures capture the current agg at declaration, walk-then-write for assignment, split responsibility keeps aggs read-only); open items: which constructs push a new scope element, unbound-name assignment policy, explicit-local-declaration syntax, tombstone-on-write behavior, function-call scope isolation details",
	"audience": "Caspian engine implementers writing the scope runtime and the parser sites that call it (variable read, variable write, block entry, block exit, closure declaration, function / method call, closure invocation)"
}}
~~~

A **scope** is a runtime object that tracks the variable bindings visible to currently-executing Caspian code. It is an instance of the [aggregate-hash primitive](https://puck.uno/documentation/requirements/lua/aggregate-hash), used in the variable-resolution role. Each **scope element** is one hash in the agg's `.hashes` array. The end-to-start walk means the innermost element (most recent frame) wins on lookup, with fallback to outer elements.

**Not a Caspian-facing class.** Developers do not construct `%('core:scope')`; the scope runtime is engine-internal machinery.

## Multiple scopes coexist

The engine can have many live scopes at any moment. Each active call frame owns a scope; closures hold references to scopes they captured at declaration time, keeping those scopes alive after the code that created them has returned. There is no single "the scope" object — "the current scope" is always relative to whatever code is currently executing.

## Scope elements

A scope element is a hash — specifically, a hash with `.note_deleted = true` set at creation, so the scope runtime can distinguish "this variable was never bound in this element" from "this variable was explicitly deleted in this element" during walks. See [Hash § Noting deleted keys](https://puck.uno/documentation/requirements/built-in-classes/primitives/hash#noting-deleted-keys) for the mechanism.

Which Caspian constructs push a new scope element is [open](#open-items). Candidates include `begin`, `if`, `while`, `for`, function bodies, and closure invocations. The worked example below treats `begin ... end` as pushing its own element.

## Assignment walks the scope agg

Reading a variable uses aggs' read semantics unchanged: walk end-to-start, return the first element's value at that key.

Writing a variable is `current_scope_agg.set(name, value)` — see [aggregate-hash § Writing via .set](https://puck.uno/documentation/requirements/lua/aggregate-hash#writing-via-setkey-value). The aggregate's `.set` handles the walk-then-write:

1. Call `.defined_in(name)` on the scope agg to find the owning element.
2. If found, write to that element (outer bindings mutate in place).
3. If not found in any element, write to `.hashes[last]` — the innermost scope element (create-new-local semantic; Ruby-like).

~~~caspian
$foo = 'bar'

begin
	$foo = 'zap' # scope.set('foo', 'zap') — .defined_in finds $foo in the outer element, mutates there
end

$foo # 'zap'
~~~

**Unbound-name assignment creates a new local in the innermost element.** When `$foo = value` walks the chain and doesn't find `$foo` anywhere, a new slot is created in the innermost scope element (the current block / function / closure frame). This is the create-in-innermost policy (Ruby-like default) — no explicit declaration required.

**One primitive, one behavior.** The scope runtime doesn't reimplement walk-then-write logic; it just calls `.set` on the current scope agg. Same primitive `%chain` and other agg consumers use for write-through semantics. Frozen-slot enforcement inherits from the underlying hash's `.freeze_field`.

## Closures capture the current scope

A closure is a function object with an extra property: a reference to the scope agg that was current at the moment the closure was declared. When the closure is later invoked, its body runs against the captured agg — reads walk the captured chain; writes walk-then-write as with any scope.

Each invocation of the closure pushes its own scope element for locals, so recursive or re-entrant invocations don't collide with each other's locals.

Because aggs hold hash references (not copies), mutations to variables in outer captured elements propagate live to the closure's view — assigning to `$counter` in the outer code is immediately visible to a closure that captured that scope, and the reverse.

**Scope elements captured by a closure persist until the closure is unreachable.** The captured scope agg holds references to the individual scope elements; those elements stay alive as long as the closure holds the agg reference. The consequence for developers is that objects bound in captured scope elements — database handles, file descriptors, protected-memory allocations, sockets — don't fall out of scope on the enclosing block's `end`; they stay alive until the closure is dropped, which delays deterministic cleanup for `on_close`-style semantics. See [functions/closure § Captured scope keeps resources alive](https://puck.uno/documentation/requirements/functions/closure#captured-scope-keeps-resources-alive) for the developer-facing explanation and mitigation patterns.

## Consumers

The scope runtime is consulted at several parser-driven sites:

- **Variable read** (`$foo` in an expression position) — routes through the current scope agg's read semantics.
- **Variable write** (`$foo = value`) — routes through the walk-then-write logic.
- **Block entry** (constructs that push a scope element) — pushes a new element onto the current agg.
- **Block exit** — pops the pushed element.
- **Closure declaration** (`closure() ... end`) — attaches the current scope agg reference to the closure object.
- **Closure invocation** — engages the closure's captured agg as the current scope, plus a fresh local element for the invocation.
- **Function / method call** — establishes a new scope agg for the callee that is NOT the caller's scope. Function bodies don't see the caller's locals; this is the opaque-function-scope model.

## Implementation latitude

The conceptual model above uses "push an element onto the current agg" as the operation for entering a new scope frame. The Lua implementation is free to organize this however makes sense — a single agg with mutable `.hashes`, a stack of aggs with prefix sharing, a linked list of elements with agg views over slices, etc. — as long as observable behavior matches (walk order, walk-then-write mutation of the owning element, closure capture of the correct chain, correct isolation of locals across recursive invocations).

## Open items

- **Which constructs push a scope element.** `begin`, `if`, `while`, `for`, function body, closure invocation — all of them, some of them? The worked example above treats `begin ... end` as pushing an element; the rest are undecided.
- **Tombstone-on-write.** During walk-then-write, if the walker hits a tombstoned name in an inner element before finding a live binding in an outer element, does the write treat the tombstone as "not here, keep looking" or as "explicitly gone here, stop and create a fresh local in the innermost element"? Settled via aggregate-hash's `.set` behavior once we resolve how `.defined_in` reports tombstoned elements.
- **Function-call scope isolation details.** Function bodies don't see the caller's locals — but `%self`, `%bucket`, and other receiver-globals are available when the callable is invoked as a method. Whether those live as scope-agg contents on distinct elements, as separate globals threaded through the runtime, or something else, needs pinning in coordination with the [callables idea](https://puck.uno/documentation/ideas/callables).

## Testing

- **Closure reads the outer variable at invocation time, not definition time.** After `$foo = 'bar'; $cl = closure() puts $foo end; &cl` outputs `'bar'`; then `$foo = 'zap'; &cl` outputs `'zap'` — the closure reads the current value at invocation, not a captured-at-definition value.
- **Closure sees a mutation performed inside a further nested scope.** After `$foo = 'bar'; $cl = closure() puts $foo end; &cl` outputs `'bar'`; then `begin $foo = 'zap' end; &cl` outputs `'zap'` — walk-then-write inside the `begin` block mutated the outer scope element where `$foo` lives (rather than shadowing in a new inner local), and the closure's captured chain sees the mutation live.

## Related

- [aggregate-hash](https://puck.uno/documentation/requirements/lua/aggregate-hash) — the underlying primitive; scope is an aggregate-hash in the variable-resolution role.
- [Hash § Noting deleted keys](https://puck.uno/documentation/requirements/built-in-classes/primitives/hash#noting-deleted-keys) — scope elements are note-deleted hashes so the walker can distinguish "never bound here" from "explicitly deleted here."
- [functions/closure](https://puck.uno/documentation/requirements/functions/closure) — closure semantics from the language surface; this page covers the underlying scope-capture mechanics.
- [functions/bare](https://puck.uno/documentation/requirements/functions/bare) — bare-function semantics from the language surface; opaque-function-scope model.
