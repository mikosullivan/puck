# References hash

~~~vibecode
{"vibecode": {"example": "references_hash",
	"shows": "drinian_state_with_populated_references_hash_demonstrating_variable_and_hash_element_reference_objects_pointing_at_user_data",
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
element, and `$alias` aliasing `$shared`. Every object AND every
non-shadow platter draws an ID from the same global sequence (see
[references.md § Object IDs](../references.md#object-ids)) — objects
`"1"`–`"7"` plus platters `"8"`–`"14"`, with `sequence: 15` recording
the next allocation. Shadow platters keep the literal key `"shadow"`
(the platter at position 1 is always named that); every other
platter's key is its sequence ID.

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
        "alias": "5",
        "count": "6"
      }
    }
  ],
  "sequence": 15,
  "references": {
    "1": "2",
    "5": "2",
    "6": "7",
    "3": "4"
  },
  "objects": {
    "1": {
      "bucket": {},
      "stack": {
        "shadow": {},
        "8": {"class": "puck.uno/variable", "bucket": {}}
      }
    },
    "2": {
      "bucket": {"name": "3"},
      "stack": {
        "shadow": {},
        "9": {"class": "puck.uno/hash"}
      }
    },
    "3": {
      "bucket": {},
      "stack": {
        "shadow": {},
        "10": {"class": "puck.uno/hash_element", "bucket": {"parent": "2", "key": "name"}}
      }
    },
    "4": {
      "bucket": {"value": "Picard"},
      "stack": {
        "shadow": {},
        "11": {"class": "puck.uno/string"}
      }
    },
    "5": {
      "bucket": {},
      "stack": {
        "shadow": {},
        "12": {"class": "puck.uno/variable", "bucket": {}}
      }
    },
    "6": {
      "bucket": {},
      "stack": {
        "shadow": {},
        "13": {"class": "puck.uno/variable", "bucket": {}}
      }
    },
    "7": {
      "bucket": {"value": 1},
      "stack": {
        "shadow": {},
        "14": {"class": "puck.uno/number"}
      }
    }
  },
  "pending_exceptions": [],
  "gc_errors": []
}
```

ID legend, to read the `objects` hash above:

| ID | What it is | Where to look |
|---|---|---|
| `"1"` | variable `$shared` (`puck.uno/variable`) | named via frame 0's `locals` key |
| `"2"` | the hash `{name: 'Picard'}` (`puck.uno/hash`) | top-level bucket maps key → hash_element ID |
| `"3"` | hash element for key `'name'` (`puck.uno/hash_element`) | the `element` platter's bucket carries parent + key |
| `"4"` | the string `'Picard'` (`puck.uno/string`) | top-level bucket carries the value |
| `"5"` | variable `$alias` (`puck.uno/variable`) | named via frame 0's `locals` key |
| `"6"` | variable `$count` (`puck.uno/variable`) | named via frame 0's `locals` key |
| `"7"` | the number `1` (`puck.uno/number`) | top-level bucket carries the value |

Both object IDs and non-shadow platter keys are sequential from the
same global sequencer. Within an object's `stack`, `shadow` is the
literal key for the shadow platter; every other platter's key is its
sequence ID.

The frame's `locals` doesn't store the bound objects directly — each
entry is a **reference object ID** (`"1"`, `"5"`, `"6"`); resolve it
through `objects` for the object's structure and through
`references` for what it points at. Same for hash internals: `"3"`
is the reference object representing the `name` key inside the
hash; it points at `"4"`, the `"Picard"` string object.

**The two top-level hashes work together.** `references` holds bare
pointers (id → id); `objects` holds the actual object records (id →
`{bucket, stack}`). Resolve a name like `$shared` by reading the
frame's local (`"1"`) → look up its target in `references` (`"2"`) →
look up the target's structure in `objects` (the hash record). Every
piece of state the program can see is reachable through these two
hashes plus the call stack.

Things to notice:

- **Aliasing is visible in `references`.** Both `"1"` and `"5"` map
  to the same `"2"`. The shared object has two incoming references;
  if one is severed, the other keeps it alive.
- **Hash internals are first-class reference objects.** `"3"` is
  the reference object inside the hash for the `name` key. When you
  write `$shared['name'] = 'Riker'`, the engine updates
  `references["3"]` to point at the new string object.
- **`uspace` is a class property.** `puck.uno/variable` declares
  `uspace: true`, so `"1"`, `"5"`, and `"6"` are GC roots.
  `puck.uno/hash_element` declares `uspace: false`, so `"3"` is not
  a root in its own right — it's only reachable because `"2"` is
  reachable from a uspace root that points at it.
- **The `references` hash holds bare pointers.** Just
  `{ref_id: object_id}` — the cheapest possible representation. All
  metadata lives on the reference objects themselves, not in the
  hash.

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

The `+` operator allocates a new number object — `"8"`. After the
rebinding:

```json
"references": {
  "1": "2",
  "5": "2",
  "6": "8",
  "3": "4"
}
```

`"6"` now points at `"8"` (the new number). The old `"7"` lost its
only incoming pointer — the engine fires a trace, finds no uspace
root reaches it, and collects it (along with its two platters). The
reference object `"6"` is unchanged; only its target in the
`references` hash moved.

Sever the alias instead:

~~~caspian
$shared = {name: 'Picard'}
$alias = $shared
$alias = null
# CAPTURED HERE
~~~

`null` allocates a fresh null instance — `"8"`. After:

```json
"references": {
  "1": "2",
  "5": "8",
  "6": "7",
  "3": "4"
}
```

`"5"` now points at the null instance. `"2"` is still reachable via
`"1"` (still uspace, still in the hash), so nothing collects.

<a id="inverse-index-engine-internal"></a>
## Engine-internal: the inverse index

For fast orphan checks, the engine maintains an **inverse index** —
a parallel mapping from object IDs to the set of references pointing
at them. This is engine bookkeeping, not part of the user-visible
state, and isn't exposed through any Caspian surface in V1.

Conceptually (engine-internal, illustrative only) for the original
snapshot:

```
inverse["2"] = {"1", "5"}
inverse["7"] = {"6"}
inverse["4"] = {"3"}
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
