# Truthy

~~~vibecode
{"vibecode": {
	"doc": "truthy",
	"role": "spec for Caspian's truthiness model — which values are truthy, which aren't, and how the engine enforces the rule",
	"status": "basic content; problem-mapping discussion pending",
	"related": ["requirements/ecoverse/objects/structure.md (the stack, platters)"]
}}
~~~

In Caspian, every value is either **truthy** or not. Conditionals (`if`, `unless`, the trailing-condition forms of loops, etc.) treat that as the question they're asking about a value.

## What's truthy

Almost everything. The complete list of values that are NOT truthy:

- An instance of `puck.uno/null`.
- An instance of `puck.uno/false`.

Everything else is truthy. Including some values that other languages treat as falsy:

- The empty string `""`
- The number `0`
- The empty array `[]`
- The empty hash `{}`
- Any instance of any user class, regardless of bucket contents

Caspian follows the Ruby model on this: emptiness and zero aren't the same thing as falsiness. If you want to check for empty or zero, use the explicit predicate (`.empty?`, `== 0` — there's also a `.zero?` method on numbers if you prefer that form); don't use the value in a boolean context and rely on it being false, because it won't be.

## How the rule is enforced

Truthiness is set at object creation and never changes. The mechanism rides on the object's [stack](../ecoverse/objects/structure.md#stack):

- A **truthy** value has no special truthiness marker in its stack. The shadow platter sits at the top; any other platters follow.
- A **`null`** instance has a platter directly under the shadow whose class is `puck.uno/null`.
- A **`false`** instance has a platter directly under the shadow whose class is `puck.uno/false`.

The whole `null` or `false` instance is frozen at creation (see [object.md § Immutable primitives](built-in-classes/object.md#immutable-primitives)). Because the instance is frozen, the null-or-false platter can't be removed, replaced, or shuffled away — no platter on a frozen object can be touched at all. This means:

- A value created as `null` stays `null` for its entire lifetime; same for `false`.
- A truthy value can never be made non-truthy at runtime. User code can't push a `puck.uno/null` or `puck.uno/false` platter onto a truthy value's stack: the engine refuses the mutation because it conflicts with the value's locked bool.

Once a value is decided truthy-or-not at creation time, that decision is permanent.

## The official process

The truthy-or-not decision is made at the moment of instantiation — when `$class.new(...)` runs. The engine dynamically traces the class's inheritance chain, checks for a `puck.uno/null` or `puck.uno/false` dependency, and sets the bool value permanently on the new object: if the chain implies non-truthy, the engine puts a `puck.uno/null` or `puck.uno/false` platter directly under the shadow and freezes the instance.

**The trace is done on every instantiation. No assumptions.** Classes are mutable in Caspian: a class's inheritance, its methods, even its own ancestors can change between two `.new(...)` calls. The engine cannot assume yesterday's answer for class X is still correct today; it has to trace X's chain as it currently stands at the moment each new object is born. The newly-created object then locks in whatever the chain implied right then (the truthiness platter plus the instance freeze) — and from that moment forward, that one object's truthiness is permanent regardless of how the class continues to evolve.

This is the spec. Every Caspian implementation must observably behave this way: the truthiness of a brand-new object reflects the class's inheritance at the moment of instantiation, not at some earlier or later moment.

The naive implementation literally walks the chain on each `.new(...)`. That's O(N) per instantiation where N is the inheritance depth — in practice small, typically one or two levels — and each step is a class lookup that may cross subsystem boundaries. For most workloads it's plenty fast.

**V1.0 uses the naive walk.** No caching, no precomputation, no invalidation machinery. The trace runs on every instantiation. The strategies below are a parking lot of ideas to revisit post-V1.0 if profiling shows the cost matters; nothing in this section is on the V1.0 build path.

## Implementation strategies for efficiency (post-V1.0)

An engine is free to optimize how it carries out the trace, **as long as the observable behavior is identical to the official process.** The constraint: any cached or precomputed truthiness answer for a class has to be invalidated before the next instantiation that depends on it, whenever the class is modified in a way that could change the answer (inherits-chain edits, ancestor's inherits-chain edits, etc.).

The strategies below are sketches for future consideration, kept on record so the design space is documented when the question comes back around. **Not for V1.0.** None is required by the spec; the naive walk is always a correct fallback and is what V1.0 will ship with.

### Per-class cached bit, invalidated on class change

Engine maintains an internal `_non_truthy: true | false | unknown` field on every class object. When the chain has been computed (and the class hasn't changed since), the field holds the answer; instantiations read it in O(1).

Invalidation: any operation that modifies a class's inherits chain (or the inherits chain of any of its ancestors) sets that class's `_non_truthy` back to `unknown`. Next instantiation that consults it re-traces and re-caches.

To make ancestor invalidation efficient, the engine maintains a back-reference from each class to its known subclasses — so when X is modified, it can walk X's subclass set and mark each as `unknown`. That set is itself a cache, populated as classes declare inherits and pruned when they change.

This is the highest-leverage optimization. Class modifications are rare relative to instantiations; the amortized cost approaches one field read per `.new(...)`.

### Propagate at class-definition time

A refinement of the cached-bit strategy: when class X declares `inherits Y`, the engine reads Y's cached bit. If Y is non-truthy, X is non-truthy. If Y is truthy, check the other parents (if multi-parent inheritance applies). This avoids the full chain walk entirely after the base cases (`puck.uno/null`, `puck.uno/false`) are known — each new class definition resolves its bit from already-cached parent bits in constant time per parent.

Combined with the cached-bit strategy, this collapses the cost of populating the cache to O(parents) per class definition, amortized across all future instantiations.

### Trivial fast path

The vast majority of classes are truthy. The engine can fast-path the common case: if the class doesn't explicitly inherit from `puck.uno/null` or `puck.uno/false` ANYWHERE in its declared chain, the answer is trivially "truthy" without further work. Recognize the two base UNSes by string match (cheap).

Combined with the cached-bit strategy, almost every instantiation hits the cache; the rare misses fall through the trivial-truthy fast path; the genuinely-non-truthy cases (rare) get the full walk.

### Persist across worldlet reloads

For classes loaded from a worldlet, the cached bit can be persisted alongside the class definition in Mikobase. Re-loading the class on a fresh engine startup skips the trace; the cached bit is current as long as the class definition hasn't been modified since persistence.

Same invalidation rule applies: any persisted bit on a class that has since been modified must be invalidated. Engines that don't track class-modification metadata persistently will fall back to re-tracing on first instantiation after each load.

### Combining strategies

The expected optimized implementation:

1. Per-class `_non_truthy` bit stored on each class object, computed lazily on first instantiation and cached.
2. The compute uses parent-bit propagation when possible, falling through to a full walk only when parents are also `unknown`.
3. Class modifications invalidate the class's own bit and (via the back-reference subclass set) the bits of all known subclasses.
4. Persisted bits in worldlets accelerate startup; modifications invalidate them too.

Net amortized cost at instantiation: one field read. Net cost at class modification: O(known subclasses) to invalidate. Net cost at class definition: O(parents) to populate via propagation, or O(N) for the rare fresh walk.

The observable contract stays identical to the naive walk. The optimizations are invisible to user code — the engine still produces the same truthiness answer it would produce under the literal trace-every-time implementation.

### What's NOT safe

A few things tempting from the outside that don't work cleanly given dynamic classes:

- **Caching the answer on the instance only** (e.g., "first truthiness check determines and caches on the object, subsequent checks read"). This contradicts the spec: the answer must be set at instantiation, not at first check. If an object exists for an hour before being tested, the test must reflect the class's inheritance at instantiation time, not at test time. Per-instance lazy caching would test against the wrong moment.
- **Caching globally without invalidation**. A registry of non-truthy class UNSes (without invalidation hooks tied to class modifications) goes stale as soon as any class changes. The savings aren't worth the correctness bugs.
- **Computing once at engine startup and treating as immutable**. Same problem — works for the built-in `puck.uno/null` / `puck.uno/false` base cases (which the engine controls and can guarantee stable), fails for any user class.

The thread connecting these mistakes: assuming the class graph is static when it isn't. The spec acknowledges dynamism and forces every implementation to handle it; the optimizations have to thread the same needle.
