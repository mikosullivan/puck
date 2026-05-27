# Example 07: References hash

~~~json
{"vibecode": {"example": "references_hash",
	"shows": "skeletor_state_with_populated_references_hash_demonstrating_variable_and_hash_element_reference_objects_pointing_at_user_data",
	"shape": "three_variables_one_hash_object_one_shared_reference_and_one_inner_hash_element",
	"slice_context": "post_v1_0_demonstrates_the_refs_table_foundation_for_deterministic_gc"}}
~~~

A small program that exercises the `references` hash with three
variables, a shared object (two variables pointing at the same hash),
and a hash element (the inner key inside the shared hash).
Demonstrates how the `references` hash captures the program's
reference graph for deterministic GC.

Caspian source:

~~~caspian
$shared = {name: 'Picard'}
$alias = $shared
$count = 1
# CAPTURED HERE
~~~

Paused at the comment line. Three variables bound, one hash with one
element, and `$alias` aliasing `$shared`. IDs are integers-as-strings
drawn from the engine's **single global sequence** (see
[sequence.md § Engine use](../../built-in-classes/sequence.md#engine-use)
and [references.md § Object IDs](../references.md#object-ids)). Both
object IDs **and** platter IDs come from the same counter — there's
no separate per-object platter-ID namespace, just one unique-string
generator feeding everything.

So in a real allocation order, object IDs and platter IDs
interleave. Creating one object draws ~3 IDs from the counter: one
for the object itself, two for its initial platters (shadow + base
class). For the example below, the assumed allocation order is
`$shared` first, then the hash, then its hash_element, then the
string, then `$alias`, then `$count`, then the number — which
spreads object IDs across `1, 4, 7, 10, 13, 16, 19`.

```json
{
  "srcs": {
    "a": {"file": "/home/miko/main.casp"}
  },
  "roles": {
    "user": {},
    "stdlib": {}
  },
  "call_stack": [
    {
      "action": "top_level",
      "role": "user",
      "lexical_parent": null,
      "src": ["a", 4],
      "locals": {
        "shared": "1",
        "alias":  "13",
        "count":  "16"
      }
    }
  ],
  "references": {
    "1":  "4",
    "13": "4",
    "16": "19",
    "7":  "10"
  },
  "objects": {
    "1": {
      "classes": {
        "2": {"class": "puck.uno/class/shadow", "bucket": {}},
        "3": {"class": "puck.uno/variable",    "bucket": {"name": "shared", "frame": 0}, "sticky": true}
      },
      "bucket": {}
    },
    "4": {
      "classes": {
        "5": {"class": "puck.uno/class/shadow", "bucket": {}},
        "6": {"class": "puck.uno/hash",        "bucket": {}}
      },
      "bucket": {"name": "7"}
    },
    "7": {
      "classes": {
        "8": {"class": "puck.uno/class/shadow",   "bucket": {}},
        "9": {"class": "puck.uno/hash_element", "bucket": {"parent": "4", "key": "name"}, "sticky": true}
      },
      "bucket": {}
    },
    "10": {
      "classes": {
        "11": {"class": "puck.uno/class/shadow", "bucket": {}},
        "12": {"class": "puck.uno/string",      "bucket": {}}
      },
      "bucket": {"value": "Picard"}
    },
    "13": {
      "classes": {
        "14": {"class": "puck.uno/class/shadow", "bucket": {}},
        "15": {"class": "puck.uno/variable",    "bucket": {"name": "alias",  "frame": 0}, "sticky": true}
      },
      "bucket": {}
    },
    "16": {
      "classes": {
        "17": {"class": "puck.uno/class/shadow", "bucket": {}},
        "18": {"class": "puck.uno/variable",    "bucket": {"name": "count",  "frame": 0}, "sticky": true}
      },
      "bucket": {}
    },
    "19": {
      "classes": {
        "20": {"class": "puck.uno/class/shadow", "bucket": {}},
        "21": {"class": "puck.uno/number",      "bucket": {}}
      },
      "bucket": {"value": 1}
    }
  },
  "pending_exceptions": [],
  "gc_errors": []
}
```

ID legend, to read the `objects` hash above:

| ID | What it is | Where to look |
|---|---|---|
| `"1"` | variable `$shared` (`puck.uno/variable`) | platter `"3"`'s bucket carries name + frame |
| `"4"` | the hash `{name: 'Picard'}` (`puck.uno/hash`) | top-level bucket maps key → hash_element ID |
| `"7"` | hash element for key `'name'` (`puck.uno/hash_element`) | platter `"9"`'s bucket carries parent + key |
| `"10"` | the string `'Picard'` (`puck.uno/string`) | top-level bucket carries the value |
| `"13"` | variable `$alias` (`puck.uno/variable`) | platter `"15"`'s bucket carries name + frame |
| `"16"` | variable `$count` (`puck.uno/variable`) | platter `"18"`'s bucket carries name + frame |
| `"19"` | the number `1` (`puck.uno/number`) | top-level bucket carries the value |

The frame's `locals` doesn't store the bound objects directly — each
entry is a **reference object ID** (`"1"`, `"13"`, `"16"`); resolve
it through `objects` for the object's structure and through
`references` for what it points at. Same for hash internals: `"7"`
is the reference object representing the `name` key inside the
hash; it points at `"10"`, the `"Picard"` string object.

**The two top-level hashes work together.** `references` holds bare
pointers (id → id); `objects` holds the actual object records (id →
{classes, bucket}). Resolve a name like `$shared` by reading the
frame's local (`"1"`) → look up its target in `references` (`"4"`) →
look up the target's structure in `objects` (the hash record). Every
piece of state the program can see is reachable through these two
hashes plus the call stack.

**Every ID in the snapshot comes from the same global sequence.**
Object IDs (`"1"`, `"4"`, ...) and platter IDs (`"2"`, `"3"`,
`"5"`, `"6"`, ...) draw from the same counter. No two IDs in the
running program are ever equal regardless of what they identify —
which means a platter ID can never collide with an object ID and
context fully disambiguates them: platter IDs only appear as
keys inside an `objects` entry's `classes` field; object IDs
appear everywhere else.

Things to notice:

- **Aliasing is visible in `references`.** Both `"1"` and `"13"` map
  to the same `"4"`. The shared object has two incoming references;
  if one is severed, the other keeps it alive.
- **Hash internals are first-class reference objects.** `"7"` is
  the reference object inside the hash for the `name` key. When you
  write `$shared['name'] = 'Riker'`, the engine updates
  `references["7"]` to point at the new string object.
- **`uspace` is a class property.** `puck.uno/variable` declares
  `uspace: true`, so `"1"`, `"13"`, and `"16"` are GC roots.
  `puck.uno/hash_element` declares `uspace: false`, so `"7"` is not
  a root in its own right — it's only reachable because `"4"` is
  reachable from a uspace root that points at it.
- **The `references` hash holds bare pointers.** Just
  `{ref_id: object_id}` — the cheapest possible representation. All
  metadata lives on the reference objects themselves, not in the
  hash.
- **IDs are short even with platter IDs in the pool.** This
  seven-object program consumed 21 IDs total (one per object plus
  two per platter). Even at 10k objects with three platters each,
  IDs stay under 6 characters.

<a id="what-happens-on-mutation"></a>
## What happens on mutation

Add a line that rebinds `$count`:

~~~caspian
$shared = {name: 'Picard'}
$alias = $shared
$count = 1
$count = $count + 1
# CAPTURED HERE
~~~

The `+` operator allocates a new number object plus its two
platters (shadow + number) — three new IDs. Say the next free ID
is `"22"`, so the new number object becomes `"22"` with platters
`"23"` and `"24"`. After the rebinding:

```json
"references": {
  "1":  "4",
  "13": "4",
  "16": "22",
  "7":  "10"
}
```

`"16"` now points at `"22"` (the new number). The old `"19"` lost
its only incoming pointer — the engine fires a trace, finds no
uspace root reaches it, and collects it (along with its platters
`"20"` and `"21"`). The reference object `"16"` is unchanged; only
its target in the `references` hash moved.

Sever the alias instead:

~~~caspian
$shared = {name: 'Picard'}
$alias = $shared
$alias = null
# CAPTURED HERE
~~~

`null` allocates a fresh null instance — `"22"` with its platters
`"23"` and `"24"`. After:

```json
"references": {
  "1":  "4",
  "13": "22",
  "16": "19",
  "7":  "10"
}
```

`"13"` now points at the null instance. `"4"` is still reachable
via `"1"` (still uspace, still in the hash), so nothing collects.

<a id="inverse-index-engine-internal"></a>
## Engine-internal: the inverse index

For fast orphan checks, the engine maintains an **inverse index** —
a parallel mapping from object IDs to the set of references pointing
at them. This is engine bookkeeping, not part of the user-visible
state, and isn't exposed through any Caspian surface in V1.

Conceptually (engine-internal, illustrative only) for the original
snapshot:

```
inverse["4"]  = {"1", "13"}
inverse["19"] = {"16"}
inverse["10"] = {"7"}
```

Maintained automatically by hash-mutation hooks on the `references`
hash (`after_set`, `after_delete`). Every write to `references`
fires the hooks; the hooks update the inverse index. The mechanism
is the same `on_call = :all` multicast model that powers `on_close` —
nothing bespoke. The hooks live in an engine-pushed platter on the
`references` hash itself.

If a future Caspian version wants to expose
`<obj>.object.referrers` (or similar) at the language level, the
inverse index is already maintained and waiting. Until then, it
stays engine-internal — easy to walk back if the design needs to
change.

<a id="related-docs"></a>
## Related docs

- [references.md](../references.md) — the `references` hash spec,
  reference class hierarchy, uspace classification, object ID scheme.
- [garbage-collection.md](../../garbage-collection.md) — the GC model
  the `references` hash enables.
- [base-class-use.md § Unicast vs multicast](../../../ideas/base-class-use.md#unicast-vs-multicast) —
  the dispatch model that lets the engine attach hooks to the
  `references` hash for inverse-index maintenance.
