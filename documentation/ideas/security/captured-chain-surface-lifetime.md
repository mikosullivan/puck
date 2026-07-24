# Idea: Revisit captured chain surface lifetime after V1

~~~vibecode
{"vibecode": {
	"doc": "captured-chain-surface-lifetime",
	"role": "post-V1 revisit for the block-scoped grant model: whether captured chain surfaces should stay usable after the grant that made them reachable ends. The V1 rule says yes (holding-is-access wins); this doc records the security tradeoff that the V1 rule makes so future work can reconsider it.",
	"status": "brainstorm — revisit after V1",
	"origin": "resolved via puck#917 on 2026-07-01"
}}
~~~

## V1 rule

**A captured chain surface stays usable after the grant that made it reachable ends.** From [roles/object-access § Chain-reachable surfaces are first-class values](https://puck.uno/documentation/requirements/roles/object-access#chain-reachable-surfaces-are-first-class-values): the grant on `%chain.X` controls **permission to call methods on `%chain`**. Once the method has been called and returned an object, the object is a normal held reference — it's usable as long as anyone holds it, regardless of what the chain looks like later.

Concretely: a non-user object can capture `%chain.net` into an instance variable during a brief grant, and continue using that instance variable after the grant block ends.

## What the V1 rule costs

The block-scoped grant model doesn't produce block-scoped **capability lifetime** — it produces block-scoped **capability visibility**. A role that gets even a brief grant can capture the underlying surface into a variable and keep using it indefinitely. That's a real security consequence: "the chain grant expired" doesn't mean "the callee no longer has access," it means "the callee can no longer *look up* the surface via `%chain.X`."

For V1 this is acceptable — the walking-skeleton phase doesn't have real adversarial code running in downloaded objects, and the simpler model is easier to reason about. Post-V1, when downloaded objects from untrusted sources become common, this may need revisiting.

## What to revisit

Two candidate directions if the V1 rule stops fitting:

- **Block-scoped surfaces.** The engine gives each grant its own unique surface object; when the block ends, the engine invalidates the surface (any subsequent method call raises). Captured references live long enough to be useful *inside* the block but can't outlive it. Programs that need lifetime beyond the block have to re-capture on each grant.
- **Reference-provenance tags.** The engine tags each captured surface with the role that captured it and the grant that authorized it. On method dispatch, the engine checks that the capturing role still has the underlying capability. Captured references become "dead" when the grant expires but the reference object itself is still around (introspectable, but not callable).

Both are heavier than the V1 model. The right time to pick one (or invent a third option) is when there's a concrete threat model that the V1 rule fails against.

## What NOT to reconsider

The composition with holding-is-access and methods-run-as-object's-role is settled: those rules are load-bearing for the rest of the role system, and the V1 lifetime rule falls out of them naturally. The revisit is about whether the runtime should add a **separate** lifetime mechanism on top, not about revising the underlying object-access rules.

## Related

- puck#917 — where this decision was made.
- [roles/object-access](https://puck.uno/documentation/requirements/roles/object-access) — the V1 rules this decision composed from.
- The [chain grant model](https://puck.uno/documentation/requirements/chain/#grant-and-revoke) — the block-scoped grant mechanism whose lifetime story this idea revisits.
