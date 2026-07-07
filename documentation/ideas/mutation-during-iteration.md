# How other languages handle mutation during iteration

~~~vibecode
{"vibecode": {
	"doc": "mutation_during_iteration",
	"role": "survey of how mainstream languages handle mutation of a collection while iterating over it (Python, Ruby, JavaScript, Java, C#, Rust, Go, Swift, and a note on functional languages), plus the settled Caspian rule: iterating methods (`.each`, `.map`, `.keep`, `.reject`, `.sum`, etc.) snapshot their input at loop start. Iteration walks a shallow clone; mutations to the source have no effect on the loop. The same rule applies to `.each` on an elements object. Implementable via copy-on-write so callers don't pay for the snapshot in the mutation-free case.",
	"status": "settled — snapshot-at-loop-start rule confirmed; ready to fold into requirements/",
	"references": ["https://puck.uno/documentation/requirements/caspian/built-in-classes/array/elements", "https://docs.python.org/3/reference/datamodel.html", "https://docs.oracle.com/javase/8/docs/api/java/util/ConcurrentModificationException.html"]
}}
~~~

Mutating a collection while iterating over it is a well-known trap. Different languages take different approaches, ranging from compile-time prevention to silent undefined behavior. This doc surveys the major approaches and pulls out patterns worth considering for Caspian.

The core problem: iteration typically walks a collection position-by-position. If the collection changes shape mid-walk (elements added, removed, moved, or the underlying storage relocated), the iterator's assumptions can break — it might skip elements, revisit them, index off the end, or in the worst case walk into freed memory.

## Python

**Lists:** modifying during iteration is undefined behavior — the runtime doesn't stop you, but the results are unpredictable.

~~~python
lst = [1, 2, 3, 4]
for x in lst:
	if x % 2 == 0:
		lst.remove(x)
# result: [1, 3, 4] — the element after '2' got skipped
~~~

**Dicts and sets:** the runtime detects size changes and raises.

~~~python
d = {'a': 1, 'b': 2}
for k in d:
	d['c'] = 3
# RuntimeError: dictionary changed size during iteration
~~~

**Idiomatic workarounds:**

- Iterate over a copy: `for x in lst[:]:` or `for k in list(d):`
- Build a new collection with a comprehension: `lst = [x for x in lst if condition]`
- Use `filter` / `map` for a new sequence

Python leans on the "iterate a snapshot" convention. There's no compile-time enforcement; you're expected to know the rule.

## Ruby

Ruby's Array is more forgiving than Python's — mutation during `each` doesn't raise, but the visited elements depend on how the underlying array shifts. Behavior is documented as "results are unspecified" for most cases but tends to be consistent within an implementation:

~~~ruby
arr = [1, 2, 3, 4]
arr.each { |x| arr.delete(x) if x.even? }
# result: arr is [1, 3] — element after '2' was skipped (matches Python's list behavior)
~~~

**Safer alternatives Ruby provides:**

- `arr.delete_if { |x| ... }` — filter in place, safe.
- `arr.reject! { |x| ... }` — inverse of `delete_if`.
- `arr.select! { |x| ... }` — keep matches.
- `arr.map! { |x| ... }` — replace each element in place.

The `!`-suffixed forms are Ruby's way of saying "this method is safe to use because it knows it's mutating the receiver." Callers who want to mutate during iteration are expected to reach for these rather than write `each` with mutation in the block.

Hashes: `Hash#each` during modification is officially undefined; some implementations raise, some don't. Same convention as Array — use `.delete_if`, `.select!`, etc.

## JavaScript

**Array#forEach** uses **visitor semantics**: the length is captured at the start of the iteration, and elements are visited in order up to that snapshot length. Elements added mid-iteration aren't visited; elements removed mid-iteration are skipped (and the corresponding position visits a now-different value).

~~~javascript
const arr = [1, 2, 3];
arr.forEach((x, i) => {
	arr.push(x * 10);
});
// arr is [1, 2, 3, 10, 20, 30]
// forEach visited 3 elements (the original length), didn't see the pushed values
~~~

**for-of loops** use the iterator protocol. For Array, this behaves like a live view — pushing during a for-of loop continues iterating into the new elements:

~~~javascript
const arr = [1, 2, 3];
for (const x of arr) {
	if (x < 100) arr.push(x * 10);
}
// This is an infinite loop or very-long loop depending on state.
~~~

`Map` and `Set` iterators are documented as reflecting current state — additions during iteration are visited if the added key hasn't been iterated past, deletions of not-yet-visited keys skip them, and re-adding a key during iteration visits it again at its new position. Well-defined, but callers still have to reason carefully.

**Idiomatic workaround:** iterate a spread copy — `for (const x of [...arr]) { ... }`.

## Java

Java's approach is **fail-fast iterators**: most collection iterators track a modification count on the underlying collection, and any structural modification made outside the iterator raises `ConcurrentModificationException` on the next iterator method call.

~~~java
List<Integer> list = new ArrayList<>(Arrays.asList(1, 2, 3));
for (Integer x : list) {
	if (x == 2) list.remove(x);  // throws ConcurrentModificationException
}
~~~

**The safe path:** the iterator itself carries a `remove()` method that removes the last-returned element without invalidating the iterator.

~~~java
Iterator<Integer> it = list.iterator();
while (it.hasNext()) {
	Integer x = it.next();
	if (x == 2) it.remove();  // safe
}
~~~

**Explicit escape hatches:** `CopyOnWriteArrayList`, `ConcurrentHashMap`, and other `java.util.concurrent` collections allow modification during iteration by design — each modification produces a fresh underlying array/table, so iterators see a stable snapshot.

Fail-fast is the strongest runtime protection — you find the bug immediately, not silently.

## C#

C# takes an approach very similar to Java. `foreach` over a standard collection throws `InvalidOperationException` if the collection is modified during iteration.

~~~csharp
var list = new List<int> { 1, 2, 3 };
foreach (var x in list) {
	if (x == 2) list.Remove(x);  // throws InvalidOperationException
}
~~~

**Idiomatic workarounds:**

- Iterate by index with a `for` loop: `for (int i = list.Count - 1; i >= 0; i--) { ... }` (iterating backwards for safe removal).
- Filter with `RemoveAll(predicate)`.
- Copy to a new list: `foreach (var x in list.ToList()) { ... }`.
- Use LINQ to project into a new sequence.

Same "fail fast at runtime" philosophy as Java. Also similar concurrent-collection escape hatches.

## Rust

Rust catches this at **compile time** via the borrow checker.

~~~rust
let mut v = vec![1, 2, 3];
for x in &v {
	v.push(*x * 10);  // compile error: cannot borrow `v` as mutable
					   // because it's also borrowed as immutable
}
~~~

Iterating with `&v` (or `v.iter()`) borrows `v` immutably; the borrow is held for the loop's duration; any mutable use of `v` in that scope is rejected. There is no runtime failure mode — the code doesn't compile.

**Idiomatic paths for mutating iteration:**

- `v.retain(|&x| condition)` — filter in place.
- `v.retain_mut(|x| { ... })` — like `retain` but with mutable access to each element.
- `v.drain(..)` — consuming iterator that drains elements out of the vec as you iterate.
- Iterate indices instead of borrowing: `for i in 0..v.len() { v[i] = ... }` — no borrow held.
- Collect a snapshot: `let snapshot: Vec<_> = v.iter().cloned().collect(); for x in snapshot { v.push(x); }`.

Rust's approach is the strongest but also the most restrictive — legitimate mutation patterns need to be expressed with a specific API.

## Go

Go's `for range` captures the iteration state at loop start for slices:

~~~go
s := []int{1, 2, 3}
for i, v := range s {
	s = append(s, v*10)
}
// i and v walk 0,1,2 — original length. The appends don't extend the loop.
~~~

For maps, iteration order is randomized AND modification during iteration is explicitly undefined:

~~~go
m := map[string]int{"a": 1, "b": 2}
for k, v := range m {
	m["c"] = 3  // undefined behavior — might or might not visit "c"
}
~~~

The language spec explicitly declines to define map-mutation-during-iteration behavior, giving implementations freedom to optimize map iteration.

Go's approach is: slices are safe-if-you-understand-the-semantics (visitor pattern), maps are user-beware.

## Swift

Swift leans on **copy-on-write**: standard collections are value types that share underlying storage until modified, at which point they duplicate. Modifying `arr` while iterating over it means the loop still sees the original (pre-modification) storage.

~~~swift
var arr = [1, 2, 3]
for x in arr {
	arr.append(x * 10)
}
// arr is [1, 2, 3, 10, 20, 30]
// the loop iterated the original 3 elements
~~~

The loop's iterator holds a reference to the pre-mutation storage; the append triggers COW so the mutation lands on new storage; the loop keeps walking the original. Silent snapshot semantics with no explicit action required from the programmer.

Similar behavior for `Dictionary` and `Set`.

**The downside:** allocation on first mutation during iteration. For hot loops that append-per-iteration, callers often reserve capacity or restructure the loop to avoid the COW copy.

## Functional languages (Haskell, Erlang, Elixir, Clojure)

Collections are immutable by construction. There is no "mutation during iteration" because there is no mutation. Any operation that would "modify" produces a new value; the value you're iterating over is fixed for the duration of the walk.

This is the strongest form of safety: the problem cannot arise. It requires the whole language to lean into immutability, which trades off against ergonomics for imperative-style loops.

## Patterns pulled out of the survey

Six approaches show up:

1. **Compile-time prevention.** Rust's borrow checker. Strongest safety; strong restrictions on legitimate patterns.
2. **Fail-fast at runtime.** Java's `ConcurrentModificationException`, C#'s `InvalidOperationException`, Python for dicts and sets. Bug surfaces immediately, no silent wrong result. Requires runtime bookkeeping (mod-count).
3. **Visitor semantics.** JavaScript `forEach`, Go slices. Well-defined: iteration captures length at start, walks that. Additions during iteration aren't visited; removals produce skipped/repeated slots. Simple to implement; still surprising for callers who don't know the rule.
4. **Undefined behavior.** Python lists, Ruby arrays, Go maps. Runtime doesn't stop you; results are consistent per-implementation but not spec'd. Bugs are silent.
5. **Copy-on-write snapshot.** Swift. Modification triggers a copy, the loop keeps walking the original. Silent correctness; allocation cost per mutation.
6. **Immutable by construction.** Functional languages. Problem doesn't exist; requires whole-language buy-in.

Orthogonal to those six, most languages provide **safe destructive methods** that know they're iterating and mutating together:

- Ruby's `arr.delete_if`, `arr.select!`, `arr.map!`, `arr.reject!`
- Rust's `Vec::retain`, `Vec::retain_mut`, `Vec::drain`
- Python's list comprehensions (`lst = [x for x in lst if ...]`)
- Java's `Iterator.remove()`
- Swift's `arr.removeAll(where: ...)`

The pattern: give callers a first-class way to say "iterate AND mutate together" and steer them to that path.

## Implications for Caspian

Caspian's spec'd model has one property that changes the calculus: the [elements-object surface](https://puck.uno/documentation/requirements/caspian/built-in-classes/array/elements) gives element handles that stay stable across mutations. A caller iterating `$arr.elements` and calling `.delete`, `.move_to_start`, or `.index = $n` on an element handle isn't fighting the iterator — the handles track their own positions.

That covers some cases cleanly. Open questions worth pinning down:

1. **What happens when the source array is `.each`'d and mutated via the array's own methods inside the block?** e.g., `$arr.each do ($x); $arr.push($x); end`. The iteration is over `$arr` directly, not `.elements`, so element-handle stability doesn't apply. Options: fail-fast (like Java), visitor semantics (like JavaScript `forEach`), or forbid at compile time (like Rust).
2. **What if a caller mutates via one path while another path iterates?** Two references to the same array, one iterating and one pushing. Same question at multi-holder scope.
3. **What's the story for hashes?** Hashes carry similar issues; the settled elements-object model may or may not extend to hash entries.
4. **Is there a Caspian equivalent of `.retain` / `.delete_if` for filter-in-place?** The array spec has `.keep!` / `.reject!` which take a block and mutate — these are the canonical safe-destructive path. Worth explicitly documenting them AS the answer for "how to filter while iterating" so callers don't reach for `.each` with an in-block mutation.

The elements-object model already picks a strong stance (stable handles, no invalidation on mutation-through-a-handle). Extending that to a general policy for `.each`-with-mutation is the follow-up decision.

## How Caspian handles it

**Iterating methods snapshot their input.**

When `.each` is called on an array (or on an elements object), the engine takes a shallow clone of the sequence at loop start. The loop walks the clone. Mutations to the original — pushes, pops, shifts, unshifts, deletes, moves, reorders — have no effect on the loop's view. The clone is immutable; the loop can't mutate it, and other code can't reach it.

The same rule applies to every method that walks the receiver and visits its elements: `.each`, `.map`, `.keep`, `.reject`, `.sum`, `.product`, `.min`, `.max`, `.min_by`, `.max_by`, `.any?`, and any other method that takes a block or produces a size-N result. Each of them snapshots at call time and walks the snapshot.

### Concrete behavior

Adding to the source during iteration doesn't extend the loop:

~~~caspian
$arr = [1, 2, 3]
$arr.each do ($x)
	$arr.push($x * 10)
end
# The loop visited exactly 1, 2, 3. Afterward $arr is [1, 2, 3, 10, 20, 30].
~~~

Removing from the source doesn't skip elements or invalidate the loop:

~~~caspian
$arr = ['a', 'b', 'c', 'd']
$arr.each do ($x)
	$arr.remove(0)
end
# The loop visited exactly 'a', 'b', 'c', 'd'. Afterward $arr is [].
~~~

The elements-object case works the same way. The elements object is a live view over the source array, but when you call `.each` on it the engine snapshots the sequence at that moment. Mutations to the elements object (or to the underlying array) during the loop don't affect what the loop visits:

~~~caspian
$arr = ['Lucy', 'Edmund', 'Susan']
$els = $arr.elements

$els.each do ($el)
	$el.delete
end
# The loop visited handles for all three original elements. $arr is now [].
~~~

### The clone is shallow

The clone captures the ordered sequence of references. The values referenced are the same objects the source array pointed to. If a caller iterates and one of the values is a Widget, `.each` yields the same Widget reference — mutations to that Widget still show through the yielded value, because it's the same object.

Only the **sequence** is snapshot: which references sit at which positions. What each reference points to is not copied.

### The clone is immutable

Nothing about the iteration can reach into the clone and modify it. The clone is engine-owned scratch state; the block sees only the yielded value (not the clone itself). There's no `.each` variant that hands the clone to the block, no reflection method that returns it, no way to alias it.

### Implementation via copy-on-write

The semantic is "each clones at loop start." The engine can implement it as **copy-on-write**: `.each` records a reference to the array's current storage; if nothing mutates the source during the loop, no allocation happens; if something mutates the source, the mutation triggers a fresh-storage split and the loop keeps walking the pre-split storage.

The observable behavior is identical either way — this is an implementation optimization, not a semantic. Callers write against the "iterates a snapshot" rule; the engine handles when the actual copy happens.

### What this composes with

- **Elements-object mutation via handles during a `.elements.each` loop.** The loop snapshots its sequence; the block can still call `.delete`, `.move_to_start`, `.index = $n`, `.value = $new` on the yielded handle. Those mutations affect the underlying array (which is what the caller wants); they don't affect the clone the loop is walking (which is what makes the loop well-defined).
- **`.keep!` / `.reject!` / `.map!` for filter-in-place.** These stay the canonical filter/transform-in-place API. They know they're mutating and iterating together, so they don't need the snapshot dance — but callers who reach for `.each` with an in-block mutation still get well-defined behavior via the snapshot rule.
- **Concurrent iterations on the same array.** Each `.each` call snapshots independently. Two loops running in parallel (from separate holders, cross-role passes, whatever) each walk their own clone; neither can invalidate the other, and mutations from either don't leak.

### Comparison to the surveyed approaches

This is closest to **Swift's copy-on-write model** but stated as a language guarantee rather than emerging from the type system. Iteration always sees a snapshot; the COW optimization means callers don't pay for the snapshot when nothing mutates.

Distinctive combinations:

- **Well-defined for every case**, like Rust — but at the semantic level, not through a borrow checker.
- **No fail-fast raise**, unlike Java and C# — mutations during iteration are legal and have predictable behavior.
- **No visitor semantics**, unlike JavaScript `forEach` — you don't see mutations that landed after loop start.
- **The safe-destructive-methods pattern** (`.keep!`, `.reject!`, `.map!`) is retained but no longer load-bearing for correctness — callers who don't reach for them still get well-defined behavior.
- **No undefined behavior**, unlike Python lists, Ruby arrays, or Go maps.

The elements-object model gives Caspian one thing no surveyed language has: an ergonomic mutation-during-iteration API (element handles) that composes cleanly with the snapshot rule. Callers who need to modify while iterating reach for `.elements.each`; the snapshot rule keeps the loop well-defined; the handles give them the mutations they need.

## Related

- [built-in-classes/array/elements](https://puck.uno/documentation/requirements/caspian/built-in-classes/array/elements) — the elements-object spec that motivated this survey.
- [built-in-classes/array](https://puck.uno/documentation/requirements/caspian/built-in-classes/array) — the parent array spec, including the settled `.keep!` / `.reject!` filter-in-place methods.
