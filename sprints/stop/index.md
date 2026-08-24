~~~vibecode
{"doc": "sprint-index", "sprint": "stop",
	"role": "Fill out the spec for `%process.stop`.",
	"status": "stub"}
~~~

# stop

~~~caspian
$x = %process.stop
~~~

Under the hood, the engine creates a frame for the stop method.
That frame has an empty ast, so it is in terminal state.

The engine then simply stops the process and returns (something)
back to the engine.

To restart the process, the engine does the following.
First, it sets the stop frame's rv to any string, presumably
something fed into the process restart. Then the engine deletes
the stop frame. That automatically copies the return value to the
parent frame, which then assigns that value to $x.