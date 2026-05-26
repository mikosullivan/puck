# Example 04: Exception at the top of the stack

~~~json
{"vibecode": {"example": "exception_at_top_of_stack",
	"shows": "snapshot_taken_at_raise_time_with_exception_as_topmost_call_stack_element",
	"shape": "five_frame_call_stack_with_exception_as_action_at_top",
	"design_note": "no_separate_pending_exceptions_field; exception_is_just_a_call_stack_element_with_action_exception"}}
~~~

A function raises during iteration. The snapshot is taken at the
moment `throw` fires, before any unwinding. The exception sits at the
top of `call_stack` as a regular element with `action: "exception"`.
The frames beneath it are exactly the frames that were active at
raise time.

Caspian source (the second iteration raises):

~~~caspian
function &greet($who)
    if $who == ''
        throw 'name cannot be empty'    # CAPTURED HERE
    end
    return 'hello, ' + $who
end

$names = ['Aslan', '']

$names.each($name) do
    puts &greet($name)
end
~~~

First iteration prints `hello, Aslan`. Second iteration calls
`&greet('')`, the `if` test succeeds on line 2, and `throw` fires on
line 3. Snapshot taken at the throw, before any frames are popped.

```json
{
  "srcs": {
    "a": {"file": "/home/miko/greet.casp"}
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
      "src": ["a", 10],
      "locals": {
        "names": {"array": [
          {"value": "Aslan", "src": ["a", 8]},
          {"value": "", "src": ["a", 8]}
        ], "src": ["a", 8]}
      }
    },
    {
      "action": "method_call",
      "role": "stdlib",
      "receiver_type": "array",
      "method": "each",
      "iterator": {"position": 1, "of": 2},
      "lexical_parent": null,
      "src": null,
      "locals": {}
    },
    {
      "action": "block",
      "role": "user",
      "lexical_parent": 0,
      "src": ["a", 11],
      "locals": {"name": {"value": "", "src": ["a", 8]}}
    },
    {
      "action": "function_call",
      "role": "user",
      "function": "greet",
      "lexical_parent": 0,
      "src": ["a", 3],
      "locals": {"who": {"value": "", "src": ["a", 8]}}
    },
    {
      "action": "if_block",
      "role": "user",
      "lexical_parent": 3,
      "src": ["a", 3],
      "locals": {}
    },
    {
      "action": "exception",
      "class": "puck.uno/error/runtime",
      "message": "name cannot be empty",
      "raised_in_role": "user",
      "src": ["a", 3]
    }
  ]
}
```

What to notice:

- **The exception is the last element of `call_stack`.** No separate
  `pending_exceptions` top-level field. The exception's `action` is
  `"exception"` — a distinct kind of stack element from frames.
- **The frames beneath the exception are intact.** Nothing has
  unwound yet — this is the snapshot at raise time. The five frames
  that were active when `throw` fired are all still there.
- **`captured_stack` isn't needed as a field on the exception.**
  The "captured stack" IS the rest of `call_stack` — the frames
  below the exception in the same array. The exception sits where
  the throw happened, and everything below is the context that led
  to it.
- **The exception's `src` is the throw line** (line 3). It's the
  source location of the raise, parallel to how a frame's `src` is
  the source location of where the frame is currently executing.
- **`iterator.position: 1`** on the `array.each` frame — second
  iteration, the one with the empty string that triggered the
  throw.
- **For an inspector / debugger:** the formatted stack trace is just
  "walk `call_stack` bottom-up, render frames as call-sites, render
  exception elements as the actual error message." The deepest
  context that led to the error is naturally preserved.

**Multi-exception case** (an `on_close` hook throws during the
unwinding of the original): two `exception` elements end up on the
stack, the newer one above the older. The engine resolves them
LIFO — when the newer one is caught, it pops; the engine resumes
unwinding the older.

```json
"call_stack": [
  {"action": "top_level", "role": "user", "lexical_parent": null, "src": ["a", 1], "locals": {}},
  {"action": "exception", "class": "puck.uno/error/runtime", "message": "name cannot be empty", "raised_in_role": "user", "src": ["a", 3]},
  {"action": "exception", "class": "puck.uno/error/io", "message": "tempfile cleanup failed: permission denied", "raised_in_role": "user", "src": ["a", 25]}
]
```

A formatter renders this as:

```
Uncaught: puck.uno/error/io: tempfile cleanup failed: permission denied
  at /home/miko/greet.casp:25
During handling of: puck.uno/error/runtime: name cannot be empty
  at /home/miko/greet.casp:3
  ...
```
