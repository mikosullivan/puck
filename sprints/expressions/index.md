~~~vibecode
{"doc": "sprint-index", "sprint": "expressions",
	"role": "Design for how Caspian evaluates expressions. The core decision: `.` is Caspian's only binary operator; every other apparent binary operator (`+`, `<`, `||`, `&&`, `?:`, etc.) is syntactic sugar over a method call via `.`. Every command reduces to one or more method_call invocations. Args are (conceptually) closures the walker wraps at the call site; a callee's parameter signature dictates which are auto-invoked (eager) and which pass through unchanged (lazy). Frame chain is the whole evaluation state; no eval placeholders, no walker path pointers, no evals hash. Related sprints [method-call](https://puck.uno/sprints/method-call/) and [lazy-params](https://puck.uno/sprints/lazy-params/) hold specific pieces.",
	"status": "brainstorm — the design has converged. Implementation is next; some normalizer / transpiler updates are needed before all sugar-shapes reduce cleanly (see [caspm-status](./caspm-status))."}
~~~

# Expressions

Design for how Caspian evaluates expressions. Every command reduces to a tree of method calls; every method call goes through one primitive dispatch (`method_call`); args are closures the walker wraps at the call site.

## Core decision — `.` is the only binary operator

`.` is Caspian's single genuine binary operator. Every other apparent binary operator is sugar over a method call via `.`. Which means: the engine's dispatch mechanism handles ONE thing (`method_call`), and every language surface reduces to it. See [primitives/method-call](./primitives/method-call) for the primitive.

The "everything is a method call" reduction lands in two shapes depending on the construct's semantics:

### Binary operators — `.obj.<name>` on the left operand

Operators that HAVE a natural primary operand — the left side — with a second operand that may or may not need evaluating. Left operand is eager (it's the receiver, evaluated as part of dispatch); second operand is eager or lazy per the op's semantics.

- **Arithmetic** — `1 + 2` is `1.+(2)`. `+` is a method on the left operand's class; second arg eager.
- **Comparison** — `$a < 10` is `$a.<(10)`. Same shape.
- **Short-circuit** — `$a || $b` is `$a.obj.or(&{$b})`. `.or` lives in the `.obj` namespace on Object (non-overridable); second operand is a lazy closure.
- **Short-circuit** — `$a && $b` is `$a.obj.and(&{$b})`. Same shape as `.obj.or`.

### Standalone commands — `engine.<name>` with all-lazy args

Constructs that DON'T have a natural primary operand — they're driven by the construct itself, not by any one value they operate on. All args are (usually) lazy; the engine primitive drives evaluation order.

- **`if`** — `if X do Y end` is `engine.if(&{X}, &{Y})`. `if X then A else B end` is `engine.if(&{X}, &{A}, &{B})`. `X ? A : B` reduces to the same primitive.
- **`while`, `until`, `for`, `unless`** — same shape as `if`; each is a standalone command with lazy args, dispatched via `engine.<name>`.
- **Assignment** — `$x = 5` is `assign('x', 5)`. Also a standalone command (though its target-name arg is eager, not lazy).

The distinction is receiver semantics: **binary ops have a first operand that's naturally "the thing"; standalone commands don't.** `1 + 2` is centered on `1`. `if X do Y end` isn't centered on `X` — it's a construct that CONSUMES both `X` and `Y`.

## Every command is a call

Under the walking-skeleton discipline (see [evaluation-model](./evaluation-model)):

- Every command reduces to at least one method_call at its root.
- Every sub-expression (arithmetic, comparison, var reference, literal materialization, function call, method dispatch) is also a call.
- Nested calls form a tree of method_call invocations, mapped directly onto a chain of CVM frames.
- Args are closures. The walker wraps every source-level arg in a closure at the call site (capturing the caller's scope). The callee's parameter signature dictates which closures the engine auto-invokes (eager) vs. passes through unchanged (lazy).

Short-circuit and control flow fall out from lazy parameters — no walker special cases, no branch atoms in CaspM.

## Sub-documents

- **[evaluation-model](./evaluation-model)** — how the walker dispatches, how frames chain, how return values propagate, how scope is threaded.
- **[eval-algorithm](./eval-algorithm)** — the single dispatch mechanism, step by step.
- **[caspm-status](./caspm-status)** — what the current transpiler + normalizer already produce in the new shape, and what still needs updating.

## Primitives

Language-level primitives implemented in Lua (not Caspian — Caspian source can't define these, they're the base cases the language rests on):

- **[method-call](./primitives/method-call)** — the dispatcher. Every fc atom in CaspM invokes this.
- **[assign](./primitives/assign)** — variable binding. `$x = 5` reduces to this.
- **[if](./primitives/if)** — ternary / if-else. `?:` and the `if` keyword both reduce here.
- **[or](./primitives/or)** — short-circuit or. `||` reduces here.
- **[and](./primitives/and)** — short-circuit and. `&&` reduces here.

## Related sprints

- **[method-call](https://puck.uno/sprints/method-call/)** — spec for the engine-primitive dispatcher itself. This sprint uses it; that sprint spec's it.
- **[lazy-params](https://puck.uno/sprints/lazy-params/)** — the `&` sigil for declaring lazy parameters in function signatures. The mechanism the walker consults for eager-vs-lazy per arg position.
