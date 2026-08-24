~~~vibecode
{"doc": "sprint-design-note", "sprint": "expressions",
	"role": "How the CVM evaluates a Caspian command. `.` is the only binary operator; every command reduces to a tree of method_call invocations, mapped onto a chain of CVM frames. Every arg is (conceptually) a closure the walker wraps at the call site; the callee's parameter signature dictates which the engine auto-invokes before dispatch (eager) and which pass through unchanged as callables (lazy). Scope threading falls out from closure capture. Frame chain IS the evaluation state — no eval placeholders on the AST, no walker path pointer, no evals hash. Under walking-skeleton discipline, every sub-expression (including literals and var lookups) spawns its own frame; leaf-inline optimization is deferred until the uniform mechanism is proven."}
~~~

# Evaluation model

Every command in Caspian is a tree of method calls rooted in a single dispatch. Evaluation is that tree traversed by the CVM's frame chain: each method call becomes a frame, and the parent frame waits while the child runs.

## The single primitive

Every dispatch goes through one engine function — `method_call`. See [primitives/method-call](./primitives/method-call). One `fc` atom in CaspM → one `method_call` invocation → one CVM frame.

## Every arg is a closure

At each call site, the walker wraps every source-level arg expression in a closure. The closure captures the caller's scope; its body is the arg expression. This is the mechanism, uniform across every arg to every call.

`method_call` looks at the callee's signature and, per position, either:

- **Eager** — invokes the closure's `.call` immediately. This spawns a nested CVM frame that runs the closure body and returns a value. The value fills the arg slot. The callee receives values for its eager parameters.
- **Lazy** — passes the closure through unchanged. The callee body decides whether to invoke it (via `.call`) or not. Zero or more invocations, callee's discretion.

Same mechanism for both. The signature is what differentiates. Short-circuit operators, control flow, macro-like helpers all use lazy args.

## Scope threading via closure capture

The scope-attachment question is a non-issue under this model. Closures capture their enclosing scope; that's what they do. Since the walker wraps args as closures IN THE CALLER'S SCOPE, each closure carries the caller's scope through to the child frame automatically. When the closure's body runs (whether via engine auto-invocation for eager, or via `.call` from the callee for lazy), it runs against the captured scope chain.

Var lookups in the arg expression resolve against the caller's scope, not the callee's. That's the correct closure semantics.

## The frame chain IS the state

There is no auxiliary evaluation state — no evals hash, no path pointer, no plan structure. All state lives in:

- The frame chain (`frame_parent` links, per the CVM schema).
- Each frame's `rv` slot for its most-recently-completed child's return value.
- Each frame's scope hash for local bindings.
- The closure objects themselves for captured scope.

Every state of the frame chain is a valid resume point. Pause anywhere; the state describes what has happened and what will happen next.

## Walking-skeleton discipline — every sub-expression is a frame

Uniformity comes first, optimization second. Under the walking-skeleton mode:

- Literal materialization (`1`, `'foo'`, `true`) is a call: `Number.new(1)`, `String.new('foo')`, etc. — each spawns a frame.
- Variable references (`$foo`) are calls: `scope.lookup('foo')` — spawns a frame.
- Arithmetic ops (`1 + 2`) are calls: `.+` on the left operand — spawns a frame.
- User function calls, method dispatches — obviously frames.

Every sub-expression, no exceptions. A simple command like `$x = 1` produces a chain of five to seven frames under this discipline. Slow, but the mechanism is exercised at every level — every edge case has to work uniformly before optimizations mask them.

Leaf-inline optimization (skipping the frame for trivial cases where the engine can compute the value directly in the parent's walker Lua stack) is deferred until the uniform mechanism is proven.

## Frame lifecycle

Concrete flow for a single call:

1. Parent frame is at a call site. Walker sees an `fc` atom (dot binop in CaspJ, collapsed in CaspM).
2. Walker wraps each arg expression in a closure — captures the caller's scope, body is the arg expression.
3. Walker invokes `method_call(method, receiver, arg_closures)`.
4. `method_call` looks up the callable (either by name on the receiver's class stack, or directly if `method` is already a callable).
5. `method_call` consults the callable's parameter signature. For each eager position, invokes the arg-closure's `.call` (spawning a nested frame; parent pauses waiting). For each lazy position, passes the closure through.
6. Once all eager args are values and lazy args are closures, `method_call` dispatches the callable's body.
7. The callable's body runs (in a new frame, with its own scope chain and its own dispatches). Eventually returns a value.
8. The parent's `rv` slot gets the return value. Parent's walker resumes at the next thing.

For nested calls (`&foo(&bar())`), the recursion is the same: each call's arg-closure, when invoked, spawns its own frame; that frame does its own dispatch, which may spawn further frames.

## Trace — `$x = 1`

Compact — showing frames as they spawn and return. Under walking-skeleton discipline:

    P: method_call('assign', global, [<closure→'x'>, <closure→1>])
    │
    ├── Q: eager auto-invoke of the 'x' arg-closure
    │   └── R: method_call('new', String, [<closure→raw 'x'>])
    │        (materializes String('x'); returns)
    │
    ├── S: eager auto-invoke of the 1 arg-closure
    │   └── T: method_call('new', Number, [<closure→raw 1>])
    │        (materializes Number(1); returns)
    │
    └── (assign primitive runs; binds $x → Number(1) in caller's scope)

Five frames for `$x = 1` under strict discipline. Every path is exercised: closure invocation for the target-name arg, closure invocation for the value arg, materialization primitives for the two literals, assign primitive at the root.

Under future leaf-inline optimization, literal materialization skips the frame — the walker sees a bare literal and materializes it directly. That collapses the chain to just P and the assign primitive.

## What this model does not have

- **No eval placeholders on AST nodes.** `frame_ast` stays as the transpiler + normalizer produce it, immutable, no `eval` field annotations.
- **No walker path pointer.** The frame chain is the walker position; no `walker_at` bucket slot.
- **No evals hash.** Return values propagate via each frame's single `rv` slot, chain-by-chain up the parent link.
- **No plan or program counter.** The command's tree structure IS the plan; the walker traverses it via nested-frame spawning.
- **No control-flow atoms in CaspM.** No `if` atom, no `while` atom, no `or` / `and` atom in a special sense. Control flow is functions with lazy parameters.
- **No branch instructions.** Short-circuit and conditional branching happen inside the callee's body based on which lazy arg-closures it chooses to invoke.

## Related

- [eval-algorithm](./eval-algorithm) — the dispatch mechanism step by step.
- [primitives/method-call](./primitives/method-call) — the engine primitive that implements the dispatch.
- [primitives/assign](./primitives/assign), [or](./primitives/or), [and](./primitives/and), [if](./primitives/if) — Lua-implemented primitives for language-level constructs.
- [caspm-status](./caspm-status) — what the current transpiler + normalizer produce in the right shape and what still needs updating.
- [method-call sprint](https://puck.uno/sprints/method-call/) — the primitive dispatcher's own spec sprint.
- [lazy-params sprint](https://puck.uno/sprints/lazy-params/) — the `&` sigil for declaring lazy parameters.
