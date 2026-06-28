# Collection order

~~~vibecode
{"vibecode": {
	"doc": "garbage_collection_order",
	"role": "report on the order in which objects (and the objects they hold) are collected during a single GC pass — the deepest-first rule, what 'deepest' means in graph terms, what each cleanup handler can rely on about what's already gone, how cycles are handled, and how multiple unrelated objects collecting in the same pass interleave",
	"audience": "Caspian programmers writing on_close handlers that depend on order; engine implementers",
	"status": "active spec — order rule settled",
	"parent_doc": "index.md"
}}
~~~

When one Caspian object goes out of scope, the engine often has to collect a whole **graph** of objects, not just the one that became unreachable. For example, a connection pool holds connections, each connection holds a socket, each socket holds a buffer. When the pool goes, the whole tree comes with it. This report covers the rules for the order those collections happen in.

The short version of the rule is laid out in [§ Cleanup order: deepest first](index.md#on-close-deepest-first-order) on the main GC page. This doc digs in: what "deepest" means in graph terms, what an `on_close` handler can rely on about what's already been collected, how cycles work, and how multiple roots interleave.

---

## The rule

**Deepest-first.** Objects further from the GC roots in the reachability graph have their `on_close` fired before objects closer to the roots. Equivalently: inner objects close before the containers that held them.

Two ways to phrase the same thing:

- **Reachability framing.** From any root, walk outward through references. The objects you reach last (deepest in the walk) close first.
- **Construction framing.** Cleanup runs in the reverse order construction would naturally run. If you'd build the inner object first (because the outer needed it as a constructor argument), the inner cleans up first too.

The construction framing usually matches the developer's mental model: things you set up early get torn down late.

---

## What "deepest" means in graph terms

Consider the object graph at the moment a GC pass starts:

~~~
         (root variable $pool)
                  │
                  ▼
              ┌────────┐
              │  pool  │
              └────┬───┘
                   │
       ┌───────────┼───────────┐
       ▼           ▼           ▼
   ┌────────┐ ┌────────┐ ┌────────┐
   │ conn-1 │ │ conn-2 │ │ conn-3 │
   └───┬────┘ └───┬────┘ └───┬────┘
       │          │          │
       ▼          ▼          ▼
   ┌────────┐ ┌────────┐ ┌────────┐
   │ buf-1  │ │ buf-2  │ │ buf-3  │
   └────────┘ └────────┘ └────────┘
~~~

When `$pool` goes out of scope, every object in this graph becomes unreachable. The `on_close` order is:

1. `buf-1`, `buf-2`, `buf-3` (depth 3 — deepest)
2. `conn-1`, `conn-2`, `conn-3` (depth 2)
3. `pool` (depth 1)

Same-depth objects fire in some deterministic order (typically `object_id`), but their relative order is arbitrary in semantic terms — if it matters, you have a design problem at the cleanup layer.

**Depth is per-pass, not global.** The engine measures depth from the roots that became unreachable in *this* GC pass. If a separate `$logger` is also collecting in the same pass, its depth is measured from its own former-root, independently of the pool tree.

---

## What an `on_close` handler can rely on

Because cleanup runs deepest-first, by the time any handler fires, **every object the receiver pointed at (directly or transitively) is already gone**.

Concretely, inside the pool's `on_close`:

- The pool's bucket still has the keys it had before — Caspian preserves keys through collection.
- Values at those keys that pointed at already-collected objects now hold plain `null`. The bucket entry survived; the value transformed.

~~~caspian
class # pool
	method on_close($call)
		# At this point every conn-N has already been reaped.
		# Their slots in @connections now hold null.
		@connections.each do($key, $value)
			# $value is null for every collected connection
		end
		# Pool-level cleanup runs here — no need to walk and close each
		# connection; that already happened.
		@stats_recorder.flush
	end
end
~~~

This is the load-bearing property: a parent's `on_close` does NOT need to iterate its children and close them. The engine handled that already. The parent only has to do parent-specific work.

---

## Why the keys survive

When the inner object collects, the outer's bucket slot doesn't get *deleted*; it gets *transformed* — the reference becomes plain `null`. The reason is uniformity.

Inside the outer's `on_close`, `@bucket.has?('bear')` should return `true` whether or not the inner has been collected yet — the structure the developer set up is still readable. If the slot vanished, the outer's handler would face an inconsistent picture of its own state that depends on cleanup ordering.

~~~caspian
# Outer's bucket before any collection:
%bucket = {bear: <ref to inner>}

# After inner's on_close completes:
%bucket = {bear: null}

# Inside outer's on_close — both still true:
%bucket.has?('bear')   # true
%bucket['bear']        # null (no flavor — uniform null, not "was-here null")
~~~

Plain null was chosen over a flavored null (`puck.uno/null/collected` or similar) for the same uniformity reason: the value at a bucket slot has one possible null type, regardless of why it's null. Code reading the bucket doesn't have to handle "this null means collected vs. this null means never set vs. this null means explicitly cleared."

---

## Multiple unrelated roots collecting in one pass

When more than one independent root goes out of scope in the same pass — say a function returns and several locals all go at once — each root's subtree collects deepest-first internally, but the subtrees themselves interleave by `object_id` order.

~~~
$pool went out of scope     $logger went out of scope
        │                           │
        ▼                           ▼
    pool tree                   logger tree
    (depth 3 → 1)               (depth 2 → 1)
~~~

The engine picks a global cleanup order that:

- Respects each subtree's internal deepest-first ordering.
- Has no relationship between the timings of the two subtrees, except that within the same pass they all complete before control returns to the calling function.

A handler in the pool tree shouldn't assume anything about whether the logger tree has been processed yet. They're independent.

---

## Cycles

If two objects reference each other and both become unreachable together, there's no "deeper" between them — neither dominates the other in the reachability graph. The engine breaks the tie deterministically (typically `object_id` order) but the resolved order is essentially arbitrary in semantic terms.

~~~caspian
# A pair of objects that reference each other and nothing else holds them:
$a.partner = $b
$b.partner = $a
# When both refs from outside drop, $a and $b form an unreachable cycle.
~~~

Within the cycle:

- Each object's bucket key that pointed at the other becomes `null` by the time its `on_close` runs (same rule as for non-cyclic outer-to-inner refs — the partner is being collected in this pass).
- Whichever one fires second sees its slot already nulled by the engine.
- Neither handler should depend on the other being alive.

**Practical advice:** if you find yourself writing cycle-participants whose `on_close` handlers want to coordinate, that's a structural problem — the coordination should happen explicitly before either object becomes unreachable, not inside cleanup.

---

## Edge cases worth flagging

**Diamond.** An inner object held by two paths from the same root, both becoming unreachable.

~~~
       root
        │
   ┌────┴────┐
   ▼         ▼
  A          B
   \        /
    \      /
     ▼    ▼
      inner
~~~

`inner`'s depth from the root is 2 (via either A or B). It fires before A and B. After it fires, both A and B have their pointers to `inner` nulled. Their relative order is `object_id`-determined but doesn't matter — neither can observe the difference.

**Resurrection attempts during `on_close`.** A handler trying to reinsert the receiver into a still-reachable structure raises immediately ([§ No resurrection](index.md#on-close-no-resurrection)). This means the order rule's invariant — "everything I pointed at is already gone" — can't be subverted by clever handler code.

**Handler that holds a reference itself.** If a closure captured inside an `on_close` body holds a reference to another unreachable object, that's still part of the same collection pass — it doesn't extend lifetime. The engine knows the closure is collection-internal and doesn't treat closure captures as new roots during the pass.

---

## What you can't rely on

Order rules are about **depth**, not about anything else:

- **Construction order.** If three siblings were constructed in order A, B, C, their cleanup order isn't necessarily C, B, A. They're at the same depth; their relative order is `object_id`-determined.
- **Bucket-key order.** If a parent's bucket has children in a particular insertion order, that order doesn't influence cleanup order for those children.
- **Reference-discovery order.** The walk the engine uses internally to find unreachable objects isn't observable; don't write handlers that assume a specific walk.

If a cleanup sequence needs a specific order beyond depth, encode it explicitly — either by structuring the object graph so the ordering is reflected in depth, or by doing the ordered work outside `on_close` before the objects become unreachable.

---

## Related

- [Garbage collection § Cleanup order: deepest first](index.md#on-close-deepest-first-order) — the brief version of this rule in the GC index.
- [Garbage collection § on_close](index.md#on-close) — the handler itself: strictness rules, the 2 ms cap, the engine-wrapping catch.
- [Garbage collection § No resurrection](index.md#on-close-no-resurrection) — why an `on_close` can't extend an object's life and thereby change cleanup ordering.
