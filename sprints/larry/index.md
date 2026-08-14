~~~vibecode
{"doc": "sprint-index", "sprint": "larry",
	"role": "Larry is a subclass of the Engine, intended for use in testing.",
	"status": "active"}
~~~

# larry

Larry is a subclass of the [engine](../../src/engine/engine.lua), intended for use in testing.

## In flight

### Public API for the row-handler chain (issue [#1622](https://github.com/mikosullivan/puck/issues/1622))

Prototype the handler-chain mutation API here (`larry:add_handler`, `larry:remove_handler`, etc.) before integrating into the base Engine class. Larry is the testbed; once the surface is proven, integration moves the methods down to Engine and drops the Larry-side shims.
