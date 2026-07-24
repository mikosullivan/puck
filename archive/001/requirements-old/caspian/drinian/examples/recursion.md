# Deep recursion through a tree walk

~~~vibecode
{"vibecode": {"example": "deep_recursion_tree_walk",
	"shows": "recursive_function_paused_at_innermost_call_with_repeated_method_each_frames_and_independent_iterator_state",
	"shape": "eight_frame_call_stack_with_repeated_function_call_frames_at_different_depths",
	"slice_context": "demonstrates_drinian_at_real_stack_depth"}}
~~~

A recursive `print_tree` function paused at the innermost level of a
three-level tree. Eight frames deep. Each recursive call has its own
`$node` and `$depth`; each `array.each` has its own iterator state.

Caspian source:

~~~caspian
function &print_tree($node, $depth)
    # CAPTURED HERE
    puts $node['name']
    $node['children'].each($child) do
        &print_tree($child, $depth + 1)
    end
end

$tree = {
    'name':     'root',
    'children': [{
        'name':     'mid',
        'children': [{
            'name':     'leaf',
            'children': []
        }]
    }]
}

&print_tree($tree, 0)
~~~

Paused inside the innermost `print_tree` call (for the `leaf` node),
at the `puts` line — about to dispatch but not into it yet.

```json
{
  "srcs": {
    "a": {"file": "/home/miko/tree.casp"}
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
      "src": ["a", 19],
      "locals": {
        "tree": {"hash": {
          "name": {"value": "root", "src": ["a", 9]},
          "children": {"array": [{"hash": {
            "name": {"value": "mid", "src": ["a", 11]},
            "children": {"array": [{"hash": {
              "name": {"value": "leaf", "src": ["a", 13]},
              "children": {"array": [], "src": ["a", 14]}
            }, "src": ["a", 12]}], "src": ["a", 11]}
          }, "src": ["a", 10]}], "src": ["a", 9]}
        }, "src": ["a", 8]}
      }
    },
    {
      "action": "function_call",
      "role": "user",
      "function": "print_tree",
      "lexical_parent": 0,
      "src": ["a", 3],
      "locals": {
        "node": "<ref to top-frame tree>",
        "depth": {"value": 0, "src": ["a", 19]}
      }
    },
    {
      "action": "method_call",
      "role": "stdlib",
      "receiver_type": "array",
      "method": "each",
      "iterator": {"position": 0, "of": 1},
      "lexical_parent": null,
      "src": null,
      "locals": {}
    },
    {
      "action": "block",
      "role": "user",
      "lexical_parent": 1,
      "src": ["a", 4],
      "locals": {"child": "<ref to mid node>"}
    },
    {
      "action": "function_call",
      "role": "user",
      "function": "print_tree",
      "lexical_parent": 0,
      "src": ["a", 3],
      "locals": {
        "node": "<ref to mid node>",
        "depth": {"value": 1, "src": ["a", 4]}
      }
    },
    {
      "action": "method_call",
      "role": "stdlib",
      "receiver_type": "array",
      "method": "each",
      "iterator": {"position": 0, "of": 1},
      "lexical_parent": null,
      "src": null,
      "locals": {}
    },
    {
      "action": "block",
      "role": "user",
      "lexical_parent": 4,
      "src": ["a", 4],
      "locals": {"child": "<ref to leaf node>"}
    },
    {
      "action": "function_call",
      "role": "user",
      "function": "print_tree",
      "lexical_parent": 0,
      "src": ["a", 2],
      "locals": {
        "node": "<ref to leaf node>",
        "depth": {"value": 2, "src": ["a", 4]}
      }
    }
  ]
}
```

What to notice:

- **Three `function_call` frames all named `print_tree`** — one per
  recursive call. Each has its own `$node` and `$depth` locals
  (values 0, 1, 2). Recursion is just frames; the engine doesn't
  model it specially.
- **All three `print_tree` frames have `lexical_parent: 0`** because
  `print_tree` was defined at top level. Each call's lexical chain
  is "own locals → frame 0" regardless of where on the stack it
  sits.
- **Two `array.each` frames** (frames 2 and 6), each with its own
  independent iterator state at `position: 0, of: 1`. When the
  innermost recursive call returns and unwinds, each `each` resumes
  its iteration independently.
- **`<ref to ...>` placeholders** for `node` show that values can
  be shared by reference across frames. In serialized form these
  would either be inline copies of the referenced hash or some
  object-id scheme; here they're abbreviated for readability.
- **Role alternation persists at depth.** user → user → stdlib →
  user → user → stdlib → user → user. Each `array.each` is a
  cross-role hop.
- **`depth` values carry `src: ["a", 4]`** for the recursive calls
  because they were produced by the `$depth + 1` expression on line 4
  (with the initial `depth: 0` carrying `src: ["a", 19]` from the
  call site).
