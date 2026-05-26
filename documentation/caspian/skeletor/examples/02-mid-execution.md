# Example 02: Mid-execution with nested frames

~~~json
{"vibecode": {"example": "mid_execution_nested_frames",
	"shows": "function_call_inside_if_inside_do_block_inside_method_call_inside_top_level",
	"shape": "five_frame_call_stack_with_cross_role_alternation_and_lexical_parent_divergence",
	"slice_context": "v1_0_capable_program"}}
~~~

A program in mid-execution with a function call nested inside an
if-block inside a do-block inside a stdlib method call. Demonstrates
role alternation, `lexical_parent` divergence at the function call,
and outer-scope variable mutation from inside an inner scope.

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
    "user": {},
    "stdlib": {}
  },
  "call_stack": [
    {
      "action": "top_level",
      "role": "user",
      "lexical_parent": null,
      "src": ["a", 9],
      "locals": {
        "names": {"array": [
          {"value": "Aslan", "src": ["a", 6]},
          {"value": "Bree", "src": ["a", 6]}
        ], "src": ["a", 6]},
        "count": {"value": 1, "src": ["a", 11]}
      }
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
      "locals": {"name": {"value": "Aslan", "src": ["a", 6]}}
    },
    {
      "action": "if_block",
      "role": "user",
      "lexical_parent": 2,
      "src": ["a", 13],
      "locals": {"title": {"value": "Lord ", "src": ["a", 12]}}
    },
    {
      "action": "function_call",
      "role": "user",
      "function": "greet",
      "lexical_parent": 0,
      "src": ["a", 3],
      "locals": {
        "who": {"value": "Aslan", "src": ["a", 6]},
        "msg": {"value": "hello, Aslan", "src": ["a", 2]}
      }
    }
  ]
}
```

What to notice:

- **`count` reads 1, not 0**, and lives in the top_level frame — not
  in the if-block's locals. The assignment on line 11 walked the
  lexical chain from inside the if, found `count` in the top_level
  frame, and updated it there. Compare to `title`, which is a fresh
  name and lives in the if-block frame.
- **Role alternation:** user → stdlib → user → user → user. The
  stdlib frame is the cross-role hop into `array.each`.
- **`lexical_parent` diverges from the call stack at the
  `function_call` frame.** Frames 2 and 3 (block, if_block) have
  `lexical_parent` pointing to their immediate physical ancestor on
  the stack. Frame 4 (`greet`) has `lexical_parent: 0` — `greet` was
  defined at top level, not inside the if. From inside `greet`,
  `name` and `title` are NOT visible even though they're physically
  between `greet`'s frame and the top of the stack.
- **`src` values trace creation lines, not binding lines.** `who`'s
  value `"Aslan"` carries `src: ["a", 6]` because it was born as a
  string literal on line 6, then passed through `name` (line 8 binding)
  and `who` (line 12 argument). Birth line follows the value.
- **`msg` carries `src: ["a", 2]`** because the `+` operator on
  line 2 produced the value. Operator location, not operand birth.
