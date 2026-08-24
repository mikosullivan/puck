~~~vibecode
{"doc": "requirements_expressions_index", "role": "Landing page for the expressions requirements section — how the CVM evaluates a Caspian command. Links to the model doc, the algorithm doc, the frame-advancement rules, and the primitive-command specs."}
~~~

# Expressions

How the CVM evaluates a Caspian command. `.` is the only binary operator; every command reduces to a tree of method calls dispatched through one engine primitive, mapped onto a chain of CVM frames. Each frame carries an `rv` slot; when a child frame reaps, its rv propagates to the parent, and so on up the chain to the process cap.

## Model

- [evaluation-model](./evaluation-model) — every arg is (conceptually) a closure the walker wraps at the call site; the callee's parameter signature dictates eager vs lazy; frame chain IS the state.
- [eval-algorithm](./eval-algorithm) — the mechanical algorithm the CVM walker follows to advance a frame chain from CaspM input to a settled cap rv.
- [frame-advancement](./frame-advancement) — three state variables per frame (stmt_idx, gc, has-child); four at-rest states; nine advancement rules.

## Primitive commands

Every non-`.` bareword command normalizes to one of these engine primitives. The primitive specs describe both the CaspM shape and the runtime semantics.

- [primitives/method-call](./primitives/method-call) — the single dispatch primitive; every call site becomes one `method_call` invocation → one CVM frame.
- [primitives/assign](./primitives/assign) — bind a value to a variable in the current frame's scope.
- [primitives/if](./primitives/if) — conditional dispatch; branches are lazy args.
- [primitives/while](./primitives/while) — bounded iteration; condition and body are lazy args.
- [primitives/or](./primitives/or) — short-circuit disjunction; right-hand side is lazy.
- [primitives/and](./primitives/and) — short-circuit conjunction; right-hand side is lazy.
