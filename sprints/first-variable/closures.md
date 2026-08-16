~~~vibecode
{"doc": "sprint-note", "sprint": "first-variable",
	"role": "Design note: the closure model, and the `scopes` mechanism that falls out of it. A closure is a plain object carrying an ordered list of captured scope hashes via its bucket. Every frame — plain or closure-invoked — has the same `scopes` array shape at `bucket['scopes']`. Sprint scope: this changes how variables are stored, so it lands here.",
	"status": "in sprint scope; drives the variable-storage design"}
~~~

# Closures

Design conversation from 2026-08-16. Was originally captured as a brainstorm for later, but the `scopes` mechanism directly determines how variables are stored — so it's in scope for this sprint after all.

## The example that surfaced it

~~~caspian
function &foo()
	$x = 1

	$rv = closure()
		$x = 2
	end

	$x = 3

	return rv
end

$bar = &foo
~~~

The `$x = 3` after closure creation is the load-bearing detail — it forces the capture semantics:

- **Snapshot capture** (closure grabs values at creation): foo's later `$x = 3` doesn't touch the closure. Closure runs with its own private `x = 1`, rebinds to 2 in its own copy.
- **Reference capture** (closure holds foo's locals hash): foo's `$x = 3` mutates the hash. Closure hasn't run yet; when it does it looks up `$x` in that hash, finds 3, rebinds to 2. Foo ends, foo's frame goes away, hash lives because closure holds a ref.

Reference capture is the one that matches "closure brings its parent scope along for the ride."

## The insight

**A closure is just an object.** When it's created, its bucket gets a ref to the enclosing frame's captured scopes. That's the whole mechanism.

- No new machinery — the existing bucket + refs system does exactly this.
- Captured hashes stay reachable via the object graph: closure → bucket → scopes → hashes.
- When foo's frame drops, its own bucket cascade-deletes; the scope hashes have incoming refs from the closure's bucket, so GC leaves them alive.
- When the closure is called later, its frame accesses `$x` through the captured scopes.

## The mechanism

Instead of a bucket having a single `locals` key pointing at one hash, **every frame's bucket has a `scopes` key pointing at an ordered ArrayPrimitive of scope hashes.** The frame's own scope is one entry in that list; enclosing/captured scopes are the others. Position convention (which end is "innermost") is a design detail still to pin down.

- **Plain function call.** New frame's `scopes` holds one entry, the frame's own vars. Matches the "function has no outer scope" rule.
- **Closure call.** New frame's `scopes` combines its own new locals with the closure's captured scope list.
- **Closure creation.** The closure snapshots the CURRENT frame's `scopes` list — list ordering is fixed at capture time; the hashes themselves are shared references (matches reference-capture semantics from the example above).
- **Variable lookup.** Walk `scopes` from innermost outward; first match wins.

Nested closures fall out for free. Closure B defined inside closure A which is inside function outer: B captures A's `scopes` list, which already contains A's own locals AND outer's locals. B's captured list is `[A_own_locals, outer_own_locals]`. When B is called, its frame's scopes = `[B_own_locals, A_own_locals, outer_own_locals]`. No special machinery for depth.

## What falls out

`parent_frame` becomes unmotivated for scope resolution — the scope chain is the `scopes` array the closure holds, not a chain through frames.

For plain nested calls (foo calls bar, no closure involved), "return to caller" still has to live somewhere — likely a stack on the process side, push on call, pop on return. Sub-frame markers ride the same stack.

Three concerns split cleanly:

- **Execution unit** — the frame; self-contained.
- **Ordering / call chain** — the process (stack).
- **Scoping** — the object graph (refs from the closure's bucket).

