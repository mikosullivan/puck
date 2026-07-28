# aggregate hash

<span class="tag">aggregate-hash</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_lua_aggregate_hash",
	"role": "spec for the aggregate-hash primitive — the engine-internal Lua module that wraps an ordered array of hash references and presents a walked-view read interface. The primitive that %chain, scope frames, class-method resolution, and any 'lookup walks a chain of hashes' pattern build on. Nickname 'agg'. NOT a Caspian-facing class by default; developers do not routinely construct %('core:aggregate_hash') as part of writing Caspian. An optional Caspian-facing class surface is possible if a use case emerges.",
	"status": "spec — walk semantics, reference-not-copy constructor, read-only-through-agg constraint, and tombstone hookup to hash.note_deleted settled; open items: .keys / .each surface, post-construction mutation of .hashes, Caspian-facing class-shortname if the class surface is exposed",
	"audience": "Caspian engine implementers writing the aggregate-hash Lua module and its consumers (%chain runtime, scope-frame runtime, class-method resolution)"
}}
~~~

An **aggregate hash** (**agg** for short) wraps an ordered array of ordinary hashes and presents a hash-like read interface whose semantics walk the array. It is not a `Hash`; it is a distinct type that happens to expose a hash-like surface. **Not a Caspian-facing class by default.** The engine consumes it internally; developers do not routinely construct `%('core:aggregate_hash')` as part of writing Caspian.

The primitive fits any "chain of hashes with parent lookup" shape: [`%chain`](https://puck.uno/documentation/requirements/chain/), scope frames, class-method resolution, delegated environments. Same design economy as exceptions serving return / raise / exit — pick one well-chosen primitive, reuse it for every fitting shape, resist the temptation to build a specialized type per use case.

## Structure

Conceptually:

~~~
{
	hashes: [ hash_1, hash_2, ..., hash_N ]
}
~~~

An ordered array of hash references, plus whatever metadata the implementation needs. The **last** hash in the array is the innermost (most-specific, most-recent) frame; the **first** hash is the outermost (fallback, oldest) frame.

The agg is not itself a `Hash`. `$agg.class` reveals the aggregate class, not `Hash`.

## Construction and references

Build one with the (tentative) constructor:

~~~caspian
$hash_a = {'foo': 'bar', 'gup': 2}
$hash_b = {'gup': 'baz'}
$agg = %('core:aggregate_hash').new($hash_a, $hash_b)
~~~

The agg stores **references** to the passed hashes, not copies. Mutations to the underlying hashes are visible through the agg — it is a live view of the current state of those hashes.

~~~caspian
$hash_b['gup'] = 'quux'
$agg['gup'] # 'quux' — live view of $hash_b
~~~

## Reading walks end-to-start

`$agg[key]` walks the `.hashes` array from the last index toward the first. The first hash whose `.has_key?` returns `true` wins; the walk stops and its value is returned. If no hash has the key, `$agg[key]` returns `null` (same as a plain hash's missing-key behavior).

~~~caspian
$hash_a = {'foo': 'bar', 'gup': 2}
$hash_b = {'gup': 'baz'}
$agg = %('core:aggregate_hash').new($hash_a, $hash_b)

$agg['gup'] # 'baz' — hashes[1] has it, wins
$agg['foo'] # 'bar' — hashes[1] doesn't have it, walk falls to hashes[0]
$agg['missing'] # null — no hash has it
~~~

Matches the "stack of frames" mental model: pushing appends to the end (top of stack), lookup walks from the top down.

## Read-only through the aggregate

`$agg[key] = value` raises. Writes cannot happen through the aggregate interface — they must target a specific underlying hash directly.

~~~caspian
$agg['x'] = 5 # raises
$hash_b['x'] = 5 # ok — writes to the underlying hash
$agg['x'] # 5 — walked view now includes it
~~~

Rationale: no defensible answer to "which hash should the write go into." Refusing to guess sidesteps the ambiguity. The developer either writes to a specific frame they hold a reference to, or (more commonly) the runtime that built the agg knows which frame owns the mutation and writes to it directly.

## Tombstones via note-deleted hashes

Because the walk falls through to earlier hashes on a `.has_key?` miss, a plain `.delete` on an inner hash **un-shadows** the outer version. Sometimes that's what you want (turning off an override so the outer fallback reappears). Sometimes it isn't — the inner hash wants to say "this key is deliberately gone, don't fall through."

Aggs pick this up from the [`.note_deleted` opt-in on Hash](https://puck.uno/documentation/requirements/built-in-classes/primitives/hash#noting-deleted-keys). The walker checks `.has_key?` first; if false and the layer opted in with `.note_deleted = true`, it checks `.deleted?` — if that's true, the walker stops and returns `null` instead of falling through. Otherwise the walk continues.

Conceptually:

~~~caspian
$key = 'a'

%bucket.hashes.reverse.each do($hsh)
	if $hsh.has_key?($key)
		return $hsh[$key]
	elsif $hsh.note_deleted and $hsh.deleted?($key)
		return null
	end
end

return null
~~~

Conceptual only — the actual Lua walk can use a numeric-index loop, a precomputed reverse iterator, or whatever's efficient, as long as observable semantics match (end-to-start walk, first `.has_key?` hit wins, tombstone stops the walk, `.deleted?` consulted only on `.note_deleted = true` layers).

The agg itself does not assume that every underlying hash is note-deleted. Consumers that need tombstone semantics (`%chain`, scope frames) set `.note_deleted = true` on the frames they push. Hashes used for other purposes stay lean without paying for the feature.

## Consumers

The pattern fits several engine-internal use cases:

- **`%chain`.** Each scope frame that installs a chain override pushes a hash onto the agg. Lookup walks from the innermost override toward the bootstrap root. Setting a chain override in the current frame writes to the current-frame hash directly; reading walks the chain.
- **Scope frames.** Variable lookup walks the current scope, then the enclosing scope, then the parent scope, and so on. Each scope is a hash; the agg walks the chain.
- **Class-method resolution.** Walk from the object's own methods, through its class's methods, through inherited-class methods. Each layer is a hash-like map of name → method.
- **Delegated environments.** Any lookup pattern where "look here first, fall back to parent, fall back to grandparent" is the read model.

Each consumer decides per-frame whether to opt in to `.note_deleted` depending on whether "un-shadow" or "explicit-delete" is the correct semantic for frame-local removal.

## Implementation latitude

The above is the observable conceptual model. The engine's actual Lua implementation is free to organize however makes sense — userdata pointing at a C-side struct, closures capturing internal state, a plain Lua table with a metatable, whatever fits — as long as observable behavior matches. The shape is the contract; the Lua is free to be leaner.

## Open items

- **`.keys` / `.each` surface.** Should return / iterate the effective view — union of keys from all underlying hashes minus tombstoned keys, each key appearing once (innermost wins for duplicate keys). Ordering across the flattened view is undecided (innermost-first, outermost-first, or some insertion-order convention).
- **Post-construction mutation of `.hashes`.** The constructor takes the initial chain, but runtime consumers (`%chain`, scope) need to push new frames as the program enters a scope and pop them as it leaves. Push / pop / insert-at-index API is undecided. Whether direct mutation of the `.hashes` array is allowed, or all mutation goes through named methods, is a taste call.
- **Caspian-facing class name.** If aggs is exposed as a Caspian-facing class at some future point, the class-shortname (`Aggregate`, `AggregateHash`, `Aggs`) is undecided. The URL is `core:aggregate_hash` in current examples; the shortname may or may not track that exactly.

## Related

- [Hash § Noting deleted keys](https://puck.uno/documentation/requirements/built-in-classes/primitives/hash#noting-deleted-keys) — the opt-in tombstone feature that aggs' walker consults.
- [Hash](https://puck.uno/documentation/requirements/built-in-classes/primitives/hash) — the primitive being aggregated.
- [`%chain`](https://puck.uno/documentation/requirements/chain/) — the canonical layered-override surface; aggs is the primitive underneath.
