# Sequence

~~~json
{"vibecode": {
	"doc": "sequence",
	"role": "built-in utility class that produces unique sequential string identifiers; engine uses one global instance to mint object IDs but the class is reusable for any application that needs monotonic ID generation",
	"key_concepts": ["string_stored_counter", "in_place_string_increment",
		"no_bigint_overflow", "engine_uses_one_global_for_object_ids",
		"user_can_instantiate_for_app_specific_sequences"]
}}
~~~

`puck.uno/sequence` is a tiny utility class that produces unique
sequential string identifiers. One instance maintains one counter;
calling `.next` returns the current value and advances the counter
by one.

The counter is stored **as a string**, not as an integer. Increment
is in-place string arithmetic: rightmost digit advances, carry
propagates left, sequence prepends a new digit when the leftmost
overflows. There's no integer-overflow limit — a sequence can run
as long as memory holds.

<a id="construction"></a>
## Construction

~~~json
{"vibecode": {
	"section": "construction",
	"default_start": "\"1\"",
	"custom_start_via_new_arg": "yes"
}}
~~~

<a id="new"></a>
### `.new`

Returns a fresh sequence starting at `"1"`. The first `.next` call
returns `"1"`.

~~~caspian
$counter = puck.uno/sequence.new
$counter.next   # "1"
$counter.next   # "2"
~~~

<a id="new-start"></a>
### `.new(start)`

Returns a fresh sequence starting at the given string value.

~~~caspian
$counter = puck.uno/sequence.new('1000')
$counter.next   # "1000"
$counter.next   # "1001"
~~~

`start` must be a non-empty string of digits. The engine validates
on construction and raises `puck.uno/error/invalid_argument` if
the input isn't a valid digit string.

<a id="methods"></a>
## Methods

<a id="next"></a>
### `.next`

Returns the next value in the sequence (as a string) and advances
the internal counter by one. Each call yields a value different
from every previous and every future call on the same instance.

~~~caspian
$counter = puck.uno/sequence.new
$counter.next   # "1"
$counter.next   # "2"
$counter.next   # "3"
~~~

<a id="peek"></a>
### `.peek`

Returns the value the next `.next` call would return, without
advancing the counter. Useful for inspecting state without
consuming an ID.

~~~caspian
$counter = puck.uno/sequence.new
$counter.peek   # "1"
$counter.peek   # "1" — no advance
$counter.next   # "1"
$counter.peek   # "2"
~~~

<a id="reset"></a>
### `.reset(value)`

Resets the counter to a specific value. The next `.next` returns
this value. Useful for tests, recovery scenarios, or aligning
multiple sequences.

~~~caspian
$counter = puck.uno/sequence.new
$counter.next   # "1"
$counter.reset('100')
$counter.next   # "100"
~~~

Same validation as `.new(start)` — `value` must be a non-empty
string of digits.

<a id="engine-use"></a>
## Engine use

The Caspian engine maintains one global counter that mints unique
strings for engine bookkeeping where collision safety against
user-controlled data isn't required. The current consumers:

- **Object IDs** — every allocated object draws an ID from this
  counter. See
  [references.md § Object IDs](../skeletor/references.md#object-ids).
- **srcs registry keys** — each source file (local or UNS-loaded)
  registered in `state.srcs` gets a key from this counter. See
  [skeletor.md § Source-location tagging](../skeletor/index.md#source-location-tagging).

Two strings drawn from the global counter are never equal,
regardless of what they identify — so an object ID can never
collide with a srcs key.

**What does NOT use this counter:** **platter IDs** are UUIDs
generated fresh per allocation from libsodium. The reason: platter
IDs appear as keys **inside user buckets** (per the
per-platter-marker mechanism in
[nulls.md § Serialization](nulls.md#serialization)) where they
need collision safety against arbitrary user-chosen field names.
An integer-string `"7"` could collide with a user bucket key; a
UUID's 128-bit address space can't, in practice.

**No UUID caching, no seeded PRNG.** Every UUID comes fresh from
libsodium per call. Cache-based optimizations (batching, fast-PRNG
seeded once) were considered and rejected — caches expose future
UUIDs, which is an attack vector for externally-leaked UUIDs like
Mikobase record_pks. See
[#354](https://github.com/mikosullivan/puck/issues/354).

**The engine's hot path bypasses the class entirely.** Object ID
minting is one of the highest-frequency operations in the whole
engine (one call per object allocation — variables, hash elements,
intermediate values, every allocation). To minimize per-call cost,
the engine's global minter is a **closed-over host-language local
with the increment routine inlined**, not an instance of
`puck.uno/sequence`. In Lucy that means a Lua function with a
captured counter string and direct in-place increment — no table
access, no method dispatch, no class-stack walk, no jail
allowlist check. Just `counter = increment(counter); return counter`.

This is a deliberate trade. The class still exists at the Caspian
level — defined in the host language, exposed as
`puck.uno/sequence` — for user code that wants a sequence object.
But the engine's own object-ID hot path does **not** go through
the class. The conceptual purity loss ("engine dogfoods its own
class") is repaid in raw allocator throughput.

**The global counter lives outside Skeletor** — it's engine-private
state, not part of the user-observable execution hash. Programs
can't read it, can't reset it, can't see its current value. Putting
it in Skeletor would imply it's program-observable state, which it
isn't. The counter exists in whatever internal scratch space the
engine maintains for its own bookkeeping (alongside the inverse
index, dispatch caches, etc.), separate from the user-visible
program state.

The engine reserves the global counter; user code instantiates
`puck.uno/sequence` for application-specific needs. User-
instantiated sequences are the full class — `.reset` is available —
because the developer who owns the sequence is also the developer
who'd be responsible for any consequences of resetting it.

<a id="user-jail-pattern"></a>
### When user code wants a jailed sequence

If user code needs to share a sequence with restricted access (give
a callee a `.next`/`.peek`-only view, for example), the
[jail mechanism](object.md#jail) applies as it does to any
Caspian object. The jail can be constructed inline starting from
the instantiation line:

~~~caspian
$shared_ids = %['puck.uno/sequence'].new.object.jail('next', 'peek')
&untrusted_function $shared_ids
~~~

The raw sequence never gets a name in the caller's scope — it's
instantiated, immediately wrapped, and only the jailed proxy is
retained. The callee can advance the counter but can't reset it
or fork its state.

<a id="user-instantiation"></a>
## User instantiation

The class is just a class. User code can instantiate its own
sequences for any monotonic-ID use case:

~~~caspian
$request_ids = puck.uno/sequence.new
$audit_ids   = puck.uno/sequence.new('1000000')   # start higher

function &handle_request($req)
    $req.id = $request_ids.next
    ...
end
~~~

Each instance has its own independent counter. There's no shared
state between instances — two sequences started with the same
value will produce identical streams, but they're separate
objects and don't coordinate.

<a id="implementation"></a>
## Implementation

~~~json
{"vibecode": {
	"section": "implementation",
	"internal_representation": "array_of_single_digit_strings_most_significant_first",
	"increment_mechanism": "hash_lookup_of_next_digit_no_arithmetic_no_string_parsing",
	"return_value_caching": "lazy_assembled_string_invalidated_on_mutation",
	"why_array_over_string": "in_place_mutation_is_O_1_per_digit_no_intermediate_string_allocations_during_carry_propagation"
}}
~~~

Internal representation: **an array of single-digit strings, most
significant first**, plus a hash mapping each digit to its
successor, plus a lazily-assembled string cache.

```lua
sequence = {
    digits      = {"1"},                      -- array, MSD first
    cached      = "1",                        -- nil when dirty
    transitions = {
        ["0"] = "1", ["1"] = "2", ["2"] = "3",
        ["3"] = "4", ["4"] = "5", ["5"] = "6",
        ["6"] = "7", ["7"] = "8", ["8"] = "9",
        ["9"] = "0",
    },
}
```

**Why this shape:**

- **Array of digits, not a string.** Lua strings are immutable;
  every "string mutation" allocates a new string. The array lets
  the engine mutate individual digits in place during carry
  propagation, with no intermediate allocations.
- **Hash lookup beats arithmetic.** `transitions[d]` is a single
  table read, faster in interpreted Lua than
  `string.char(string.byte(d) + 1)` with a `== "9"` branch. Also
  clearer: the table *is* the increment rule.
- **Lazy string cache.** Many call patterns read the same ID
  multiple times (mint, log, use elsewhere). Caching the assembled
  string skips repeated `table.concat` calls. The cache is
  invalidated on mutation; the next read repopulates it.

### Algorithm

`peek`: return `cached` if non-nil; otherwise compute
`table.concat(digits)`, store it in `cached`, return it.

`advance`:

```lua
function sequence:advance()
    self.cached = nil
    local i = #self.digits
    while i > 0 do
        local next_digit = self.transitions[self.digits[i]]
        self.digits[i] = next_digit
        if next_digit ~= "0" then return end   -- no carry, done
        i = i - 1
    end
    table.insert(self.digits, 1, "1")          -- carried off the top
end
```

`next`: capture peek's result, call advance, return the captured
value.

### Cost

- **Typical `.next` call (no carry):** one transition lookup, one
  table write, one nil-assignment. Constant time.
- **With carry (occasional, e.g., 9→10, 99→100):** one transition
  lookup + one table write per digit involved. Bounded by digit
  count, which grows logarithmically. The expected cost across
  many calls averages just over 1 lookup/write per call (the
  carry-propagation series sums to a small constant).
- **First read after a mutation:** one `table.concat` plus the
  costs above. After that, peek is a single field read until the
  next mutation.

No bigint library, no overflow check, no special cases beyond the
top-of-stack carry. The whole class fits in a small handful of
methods over the three-field structure.

**Engine-native.** Each Caspian engine implements the sequence
class in its host language (Lua in Lucy's case) rather than in
Caspian source, and exposes it as the Caspian class
`puck.uno/sequence`. The Caspian-level interface (`.new`, `.next`,
`.peek`, `.reset`) is the spec; the implementation language is per
engine. Object ID minting is one of the hottest paths in the
engine — skipping Caspian's method dispatch per call is real
savings — and the sequence is needed at startup before any
Caspian-level object can be allocated, which makes host-native a
natural fit on both axes.

<a id="future-pure-caspian-reference"></a>
## Future: pure-Caspian reference implementation

**Not V1.0.** If/when alternate Caspian engines are being
developed, having a pure-Caspian reference implementation of
`puck.uno/sequence` would lower the cost of getting a new engine
to a working state. Engine authors could use the Caspian-source
version as a slow-but-correct fallback, then replace it with a
host-native fast path as an optimization once the rest of their
engine is running.

The Lucy reference implementation will continue to be host-native
(Lua) for the reasons above — performance is load-bearing for the
allocator. The pure-Caspian version is a deferred convenience for
the alternate-engine ecosystem, not a replacement for the
host-native path.

Worth tracking as a small, low-priority writeup when the
alternate-engine conversation becomes concrete.

<a id="related-docs"></a>
## Related docs

- [references.md § Object IDs](../skeletor/references.md#object-ids) —
  the primary consumer of the global sequence counter.
