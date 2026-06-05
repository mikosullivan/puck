# Mid-execution with nested frames

~~~json
{"vibecode": {"example": "mid_execution_nested_frames",
	"shows": "function_call_inside_if_inside_do_block_inside_method_call_inside_top_level_with_full_references_and_objects_tables",
	"shape": "five_frame_call_stack_with_cross_role_alternation_and_lexical_parent_divergence_and_canonical_reference_objects_representation",
	"slice_context": "v1_0_capable_program"}}
~~~

A program in mid-execution with a function call nested inside an
if-block inside a do-block inside a stdlib method call. Demonstrates
role alternation, `lexical_parent` divergence at the function call,
outer-scope variable mutation from inside an inner scope, and the
canonical `references` + `objects` representation that backs Caspian's
deterministic garbage collection (see
[references.md](https://puck.uno/documentation/requirements/caspian/drinian/references)
and [garbage-collection.md](https://puck.uno/documentation/requirements/caspian/garbage-collection)).

Caspian source:

~~~caspian
function &greet($who)
    $msg = 'hello, ' + $who
    # CAPTURED HERE
    return $msg
end

$names = ['Aslan', 'Bree']
$count = 0

$names.each($name) do
    if $name == 'Aslan'
        $count = $count + 1
        $title = 'Lord '
        puts $title + &greet($name)
    end
end
~~~

Paused inside `greet` on the first iteration, after `$msg` has been
computed but before `return` fires.

```json
{
  "srcs": {
    "a": {"file": "/home/miko/main.casp"}
  },
  "roles": {
    "user": {"bucket": {}},
    "stdlib": {"bucket": {}}
  },
  "sequence": 29,
  "references": {
    "1": "9",
    "2": "12",
    "3": "10",
    "4": "13",
    "5": "10",
    "6": "14",
    "7": "10",
    "8": "11"
  },
  "objects": {
    "1": {
      "role": "user",
      "bucket": {},
      "stack": {
        "shadow": {"sticky": true},
        "15": {
          "class": "puck.uno/variable",
          "bucket": {}
        }
      }
    },
    "2": {
      "role": "user",
      "bucket": {},
      "stack": {
        "shadow": {"sticky": true},
        "16": {
          "class": "puck.uno/variable",
          "bucket": {}
        }
      }
    },
    "3": {
      "role": "user",
      "bucket": {},
      "stack": {
        "shadow": {"sticky": true},
        "17": {
          "class": "puck.uno/variable",
          "bucket": {}
        }
      }
    },
    "4": {
      "role": "user",
      "bucket": {},
      "stack": {
        "shadow": {"sticky": true},
        "18": {
          "class": "puck.uno/variable",
          "bucket": {}
        }
      }
    },
    "5": {
      "role": "user",
      "bucket": {},
      "stack": {
        "shadow": {"sticky": true},
        "19": {
          "class": "puck.uno/variable",
          "bucket": {}
        }
      }
    },
    "6": {
      "role": "user",
      "bucket": {},
      "stack": {
        "shadow": {"sticky": true},
        "20": {
          "class": "puck.uno/variable",
          "bucket": {}
        }
      }
    },
    "7": {
      "role": "user",
      "bucket": {},
      "stack": {
        "shadow": {"sticky": true},
        "21": {
          "class": "puck.uno/hash_element",
          "bucket": {"parent": "9", "key": 0}
        }
      }
    },
    "8": {
      "role": "user",
      "bucket": {},
      "stack": {
        "shadow": {"sticky": true},
        "22": {
          "class": "puck.uno/hash_element",
          "bucket": {"parent": "9", "key": 1}
        }
      }
    },
    "9": {
      "role": "user",
      "src": ["a", 6],
      "bucket": {"0": "7", "1": "8"},
      "stack": {
        "shadow": {"sticky": true},
        "23": {"class": "puck.uno/array"}
      }
    },
    "10": {
      "role": "user",
      "src": ["a", 6],
      "bucket": {"value": "Aslan"},
      "stack": {
        "shadow": {"sticky": true},
        "24": {"class": "puck.uno/string"}
      }
    },
    "11": {
      "role": "user",
      "src": ["a", 6],
      "bucket": {"value": "Bree"},
      "stack": {
        "shadow": {"sticky": true},
        "25": {"class": "puck.uno/string"}
      }
    },
    "12": {
      "role": "user",
      "src": ["a", 11],
      "bucket": {"value": 1},
      "stack": {
        "shadow": {"sticky": true},
        "26": {"class": "puck.uno/number"}
      }
    },
    "13": {
      "role": "user",
      "src": ["a", 12],
      "bucket": {"value": "Lord "},
      "stack": {
        "shadow": {"sticky": true},
        "27": {"class": "puck.uno/string"}
      }
    },
    "14": {
      "role": "user",
      "src": ["a", 2],
      "bucket": {"value": "hello, Aslan"},
      "stack": {
        "shadow": {"sticky": true},
        "28": {"class": "puck.uno/string"}
      }
    }
  },
  "call_stack": [
    {
      "action": "top_level",
      "role": "user",
      "lexical_parent": null,
      "src": ["a", 9],
      "locals": {"names": "1", "count": "2"}
    },
    {
      "action": "method_call",
      "role": "stdlib",
      "receiver_type": "array",
      "method": "each",
      "iterator": {"position": 0, "of": 2},
      "lexical_parent": null,
      "src": null,
      "locals": {}
    },
    {
      "action": "block",
      "role": "user",
      "lexical_parent": 0,
      "src": ["a", 10],
      "locals": {"name": "3"}
    },
    {
      "action": "if_block",
      "role": "user",
      "lexical_parent": 2,
      "src": ["a", 13],
      "locals": {"title": "4"}
    },
    {
      "action": "function_call",
      "role": "user",
      "function": "greet",
      "lexical_parent": 0,
      "src": ["a", 3],
      "locals": {"who": "5", "msg": "6"}
    }
  ],
  "pending_exceptions": [],
  "gc_errors": []
}
```

ID legend:

| ID | What it is | Where to look |
|---|---|---|
| `"1"` | variable `$names` (`puck.uno/variable`) | named in frame 0's `locals` as `"names"` |
| `"2"` | variable `$count` (`puck.uno/variable`) | named in frame 0's `locals` as `"count"` |
| `"3"` | variable `$name` (`puck.uno/variable`) | named in frame 2's `locals` as `"name"` |
| `"4"` | variable `$title` (`puck.uno/variable`) | named in frame 3's `locals` as `"title"` |
| `"5"` | variable `$who` (`puck.uno/variable`) | named in frame 4's `locals` as `"who"` |
| `"6"` | variable `$msg` (`puck.uno/variable`) | named in frame 4's `locals` as `"msg"` |
| `"7"` | array element for index 0 (`puck.uno/hash_element`) | parent = `"9"`, key = `0` |
| `"8"` | array element for index 1 (`puck.uno/hash_element`) | parent = `"9"`, key = `1` |
| `"9"` | the array `['Aslan', 'Bree']` (`puck.uno/array`) | top-level bucket maps index → hash_element ID |
| `"10"` | string `'Aslan'` (`puck.uno/string`) | value in top-level bucket |
| `"11"` | string `'Bree'` (`puck.uno/string`) | value in top-level bucket |
| `"12"` | number `1` (`puck.uno/number`) — current `$count` | value in top-level bucket |
| `"13"` | string `'Lord '` (`puck.uno/string`) | value in top-level bucket |
| `"14"` | string `'hello, Aslan'` (`puck.uno/string`) | born line 2 (the `+` operator's location) |

To resolve a variable: read its name from a frame's `locals` to get a
reference ID → look up that ID in `references` to get a target object
ID → look up the target in `objects` to see what it is. For example:
`$msg` in frame 4's locals is `"6"`; `references["6"]` is `"14"`;
`objects["14"]` is the string `"hello, Aslan"` born on line 2.

What to notice:

- **`$count` reads 1, not 0**, and lives in the top_level frame — not
  in the if-block's locals. The assignment on line 11 walked the
  lexical chain from inside the if, found `$count` in the top_level
  frame, and rebound its reference (`"2"`) to point at a freshly-allocated
  number object (`"12"`, value `1`). The old number (the integer `0`
  from line 7) lost its incoming pointer and was collected — that's
  why it doesn't appear in the snapshot. Compare to `$title`, which is
  a fresh name and lives as a new variable (`"4"`) in the if-block
  frame.
- **Aliasing is visible in `references`.** The string `"Aslan"`
  (object `"10"`) has THREE incoming pointers: `$name`'s variable
  (`"3"`), `$who`'s variable (`"5"`), and the array's element-0
  reference (`"7"`). All three resolve to the same string object —
  the same `src: ["a", 6]` reflects birth at the array literal.
  Severing any one keeps the object alive through the others.
- **Hash elements are first-class reference objects.** The array's
  contents are reached through `puck.uno/hash_element` objects
  (`"7"` and `"8"`) whose buckets carry `parent` + `key`. The array
  object's bucket maps each key to the corresponding element ID, not
  directly to the target. That's what makes mutation uniform — assigning
  to `$names[0]` rebinds `references["7"]`; the same machinery as
  assigning to a hash key.
- **Role alternation:** user → stdlib → user → user → user. The
  stdlib frame is the cross-role hop into `array.each`.
- **`lexical_parent` diverges from the call stack at the
  `function_call` frame.** Frames 2 and 3 (block, if_block) have
  `lexical_parent` pointing to their immediate physical ancestor on
  the stack. Frame 4 (`greet`) has `lexical_parent: 0` — `greet` was
  defined at top level, not inside the if. From inside `greet`,
  `$name` and `$title` are NOT visible even though they're physically
  between `greet`'s frame and the top of the stack.
- **`src` values trace creation lines, not binding lines.** Object
  `"10"` (the string `"Aslan"`) carries `src: ["a", 6]` because it was
  born as a string literal on line 6, then passed through the array
  element ref (`"7"`), the `$name` variable (`"3"`, line 8 binding),
  and the `$who` variable (`"5"`, line 12 argument). Birth line follows
  the value because there's only one underlying object.
- **Object `"14"` (`$msg`'s value) carries `src: ["a", 2]`** because the `+`
  operator on line 2 produced the value. Operator location, not operand
  birth.
- **Uspace roots are the variable objects.** `puck.uno/variable`
  declares `uspace: true` (per
  [references.md § Uspace](https://puck.uno/documentation/requirements/caspian/drinian/references#uspace-class-property)),
  so objects `"1"`–`"6"` ground the program's reachability graph.
  `puck.uno/hash_element` declares `uspace: false`, so `"7"` and `"8"`
  aren't roots in their own right — they're reachable only because the
  array (`"9"`) is held by a variable root.
- **Every object record carries `role`** identifying the role that
  owns it. All 14 objects in this example are user-owned because
  user code created them. Cross-role allocations (e.g., a stdlib
  method returning a new object) would carry the allocating role.
- **`sequence` is `29`.** The global object-ID counter (see
  [references.md § Object IDs](https://puck.uno/documentation/requirements/caspian/drinian/references#object-ids))
  exposed at the top level so snapshots can resume allocation from
  the right place. A bare integer starting at `0` at boot and
  incremented for each object AND each non-shadow platter allocated.
  Fourteen objects exist (with IDs `"1"`–`"14"`) plus fourteen
  non-shadow platters (IDs `"15"`–`"28"`); the next allocation will
  take ID `"29"`.
- **Roles' buckets are empty here.** Elided for focus; see
  [bootstrap.md](https://puck.uno/documentation/requirements/caspian/drinian/examples/bootstrap)
  for the standard registry with engine/puck roles and stdin/stdout/stderr.
