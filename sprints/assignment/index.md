~~~vibecode
{"vibecode": {
	"doc": "sprint-index",
	"sprint": "assignment",
	"role": "Sprint index for the assignment sprint. Working through the end-to-end dispatch of `$x = 1` under the frames-as-objects design — the CaspM shape the normalizer produces, what receiver the assign method dispatches on, how the value atom is evaluated, what Lua-level method actually does the bind, and what the walker sees on the way back. Each subsection here captures a step in the conversation as we settle it.",
	"status": "in progress"
}}
~~~

# assignment

~~~caspian
$x = 1
~~~

## What the engine sees

To the engine, `$x = 1` looks like this pseudocode:

~~~caspian
engine.assign 'x', 1
~~~

An `assign` method call with two arguments — the target name `'x'` and the value `1`.

## Frame 0

The engine puts that method call into `frame 0`'s ast. Frame 0 is a row in the `objects` table with:

| column               | value                                                          |
|----------------------|----------------------------------------------------------------|
| `base`               | `o`                                                            |
| `control`            | `f`                                                            |
| `owner_role`         | *the user role*                                                |
| `frame_parent`       | *the cap frame*                                                |
| `frame_process_cap`  | null                                                           |
| `frame_stmt_idx`     | 0                                                              |
| `frame_gc`           | null                                                           |
| `frame_ast`          | `[[{"cmd":"mc"},{"fn":"=","rcvr":{"sys":"frame"},"args":["x",{"v":1}]}]]` |
| *rv*                 | *unset*                                                        |

The `frame_ast` column holds JSON — one statement. Decoded and pretty-printed:

~~~json
[
    [
        {"cmd": "mc"},
        {
            "fn": "=",
            "rcvr": {"sys": "frame"},
            "args": ["x", {"v": 1}]
        }
    ]
]
~~~

The outer array is the list of statements in the frame. This program has one — the `[HEAD, ENVELOPE]` method_call for the assign. The head atom `{cmd:"mc"}` identifies the row as a method_call; the envelope carries `fn`, `rcvr`, `args`.

## Frame 1: evaluating `{v:1}`

To dispatch the assign method_call, the engine needs to evaluate the receiver and every arg into a Lua value. For the assign's args, that's `"x"` (already a bareword — take as-is) and `{v:1}` — a value atom that needs evaluating.

**We evaluate `{v:1}` through a frame too.** Every value evaluation runs in its own frame. The frame's job is: produce the value, set it as the frame's `rv`, reap. The reap propagates `rv` up through `frames_child_delete_propagates_rv`, so the caller sees the value on its own rv slot.

For the `{v:1}` case, that's a very short-lived child frame under frame 0:

| column               | value                                                          |
|----------------------|----------------------------------------------------------------|
| `base`               | `o`                                                            |
| `control`            | `f`                                                            |
| `owner_role`         | *the user role*                                                |
| `frame_parent`       | *frame 0*                                                      |
| `frame_stmt_idx`     | 0                                                              |
| `frame_gc`           | null                                                           |
| `frame_ast`          | `[[{"v":1}]]`                                                  |
| *rv*                 | *unset*                                                        |

The evaluation of a scalar is a core method. The rv for the frame
is set to 1:

| column               | value                                                          |
|----------------------|----------------------------------------------------------------|
| `base`               | `o`                                                            |
| `control`            | `f`                                                            |
| `owner_role`         | *the user role*                                                |
| `frame_parent`       | *frame 0*                                                      |
| `frame_stmt_idx`     | 0                                                              |
| `frame_gc`           | null                                                           |
| `frame_ast`          | `[[{"v":1}]]`                                                  |
| *rv*                 | 1                                                        |

The frame is then deleted.

## Frame 0: after evaluation frame delete

The evaluation frame has done its work. Reaping it fires `frames_child_delete_propagates_rv`, which copies the child's `rv` (the number `1`) to frame 0's `rv` slot. The evaluation frame is gone.

Frame 0 now:

| column               | value                                                          |
|----------------------|----------------------------------------------------------------|
| `base`               | `o`                                                            |
| `control`            | `f`                                                            |
| `owner_role`         | *the user role*                                                |
| `frame_parent`       | *the cap frame*                                                |
| `frame_process_cap`  | null                                                           |
| `frame_stmt_idx`     | 1                                                              |
| `frame_gc`           | 1                                                              |
| `frame_ast`          | `[[{"cmd":"mc"},{"fn":"=","rcvr":{"sys":"frame"},"args":["x",{"v":1}]}]]` |
| *rv*                 | 1                                                              |

