~~~vibecode
{"doc": "requirements_expressions_eval_algorithm", "role": "How the engine evaluates a call. Every arg in every call is (conceptually) wrapped in a closure whose body is the arg expression. The engine invokes the callable, consults the callee's parameter signature, and for each eager arg auto-invokes the closure via `.call` (spawning a nested frame to run the closure body); lazy args are passed through as closure values that the callee can invoke — or not — with `.call`. Scope capture falls out for free (closures capture their enclosing scope, which is the caller's). No slot numbering, no walker path pointer, no evals hash — the frame chain IS the evaluation state. Under the walking-skeleton discipline, every sub-expression (including literals and var lookups) spawns a frame; leaf-inline optimization is deferred.",
	"status": "brainstorm — the mechanism the sprint has converged on. Concrete Lua sketch of method_call belongs in the [method-call sprint](https://puck.uno/sprints/method-call/); walker-loop sketch belongs here or in evaluation-model.md next."}
~~~

# Eval algorithm

The engine dispatches every call the same way. There's no separate mechanism for control flow, no separate mechanism for short-circuit, no separate mechanism for arithmetic vs user function calls. One dispatch shape covers everything.

## The single mechanism

Every arg to every call is (conceptually) a closure whose body is the arg expression. When the engine dispatches a call:

1. Look up the callable (the receiver's method by name — see [method-call](https://puck.uno/sprints/method-call/)).
2. Consult the callable's parameter signature to know which positions are eager and which are lazy.
3. For each **eager** position: invoke the arg-closure via `.call` — spawns a nested frame that runs the closure body, produces a value. The value fills the arg slot.
4. For each **lazy** position: pass the closure through unchanged. The callee body can invoke `.call` on it — or not — as it decides.
5. Once all eager args have values (and lazy args have their closures in place), dispatch the callable's body with the args in place.

**Step-1 failure aborts the dispatch.** If the receiver's class stack doesn't carry a method by that name, the engine raises immediately — steps 2-5 never happen, no arg-closure is invoked, no side effects fire from arg expressions. A caller can rely on "my args don't run unless the method was actually found." This matters for reasoning about ordering: any observable effect from an arg expression is proof that the method-lookup succeeded.

That's it. Same mechanism for `.+`, for `or`, for `if`, for user-defined functions, for engine primitives. Only the callee's signature differs.

## Args as closures

The wrapping of args as closures is what makes eager and lazy uniform. Both cases involve a closure; the difference is WHO invokes `.call`:

- **Eager**: the engine invokes `.call` before dispatching the callee's body. The callee sees the value.
- **Lazy**: the callee's body invokes `.call` when it wants the value (possibly never, possibly more than once).

Two important properties fall out from this:

- **Scope capture is automatic.** A closure captures the scope where it was created. Since the closure is created at the call site (in the caller's scope), the arg expression evaluates in the caller's scope — which is what closure semantics demand.
- **Lazy invocation is standard closure invocation.** A callee that gets `&lazy` as a param just holds a closure; `&lazy.call` is the same syntax it would use for any other closure. Lazy params aren't a new value type; they're closures, same as everywhere else.

`closure &foo end` is legal Caspian — a closure whose body is `&foo`, which when invoked calls foo. The engine's arg-wrapping is exactly this construct, applied automatically at every call site.

## Frame lifecycle under walking-skeleton mode

Under the discipline of "no leaf-inline yet," every sub-expression — literals, var lookups, arithmetic ops, user calls, all of them — spawns its own frame. That means:

- **Every call spawns N+1 frames**: one for the call itself, plus one per eager arg (to run its closure body). Lazy args don't spawn frames until invoked.
- **Every literal materialization is a frame**: `1` becomes `Number.new(1)`, which is a call, which is a frame.
- **Every var lookup is a frame**: `$foo` becomes `scope.lookup('foo')`, which is a call, which is a frame.

Lots of frames. That's the point — every path through the mechanism is exercised. Once the uniform version is solid, leaf-inline optimization can bypass the frame for cases where the engine sees a bare literal / var / built-in primitive and just computes directly.

## Trace

For `$x = 1`, the frame chain is:

    P: assign('x', 1)                          -- outer command
    ├── Q: closure for 'x' body                -- eager arg auto-invocation
    │   └── (materializes String("x"))
    └── R: closure for 1 body                  -- eager arg auto-invocation
        └── (materializes Number(1))

Three frames. P dispatches assign; assign's signature says both args eager; engine invokes each arg-closure (spawning Q and R); each returns its materialized value; P dispatches the primitive assign with (String("x"), Number(1)); local storage happens; P reaps.

For `$x = (&foo || &bar) + 'gup'`, the frame chain has many more nodes but the same shape: every call spawns arg-closures, each eager arg-closure spawns a frame to run its body, each body may itself be a call that spawns more arg-closure frames. The tree of frames mirrors the tree of the source expression.

Short-circuit works naturally: `$a || $b` is `$a.obj.or(&{$b})` — a method call on `$a` where `.or`'s signature is one lazy param `(&b)`. `%self` (which is `$a`) is the eager operand — already resolved before dispatch. method_call sees position 0 is lazy and passes the closure through. `.or`'s body: if `%self` truthy return `%self`; else `return &b.call` (which invokes the closure, spawning a frame to evaluate `$b`'s body). If `%self` is truthy, `$b`'s body never runs — no frame ever spawns for it.

## Scope threading

The scope-capture question from earlier turns disappears. Closures capture their enclosing scope; that's what they do. The engine wraps arg expressions as closures IN THE CALLER'S SCOPE, so those closures capture the caller's scope. When the closure body invokes (either via engine auto-invocation for eager, or via `&lazy.call` for lazy), the resulting frame runs with the captured scope chain in place. Var lookups against that chain resolve correctly.

For engine primitives — where the closure is being INVOKED from Lua code rather than from user Caspian code — the same rule applies: the closure carries its captured scope; the spawn-a-nested-frame Lua code attaches that scope chain to the new frame's `scopes` bucket key. Manual scope-passing for primitives (as spec'd in the prior turn) is exactly this — the engine reads the closure's captured scope and threads it into the child frame.

## What this doesn't need

- **No eval slot numbering.** No annotator pass, no `eval` fields on AST nodes; slots aren't consulted, aren't stored, aren't stamped.
- **No `walker_at` path pointer.** The frame chain IS the walker position. Each frame knows what it's doing because that's its own dispatch.
- **No `evals` hash.** Return values propagate up the frame chain via a single per-frame `rv` (or `pending_return`) slot; no accumulation of intermediates in a separate structure.
- **No `find_next` algorithm.** "What runs next" is defined by frame lifecycle: the top-of-stack frame dispatches; if it spawns a child, the child runs to completion; when it reaps, the parent resumes.
- **No control-flow atoms in CaspM.** No `if`, `while`, `or`, `and` atoms — they're all ordinary calls with signature-driven laziness.

## Related

- [evaluation-model](./evaluation-model) — the sprint's overall design, framing this dispatch mechanism within the whole frame lifecycle.
- [primitives/method-call](./primitives/method-call) — the Lua primitive that implements the dispatch step by step.
- [method-call sprint](https://puck.uno/sprints/method-call/) — the primitive dispatcher's own spec sprint.
- [lazy-params sprint](https://puck.uno/sprints/lazy-params/) — the `&` sigil for declaring lazy parameters; this doc's "signature says lazy" comes from that declaration.
