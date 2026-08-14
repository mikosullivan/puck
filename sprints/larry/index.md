~~~vibecode
{"doc": "sprint-index", "sprint": "larry",
	"role": "Larry is a subclass of the Engine, intended for use in testing.",
	"status": "active"}
~~~

# larry

Larry is a subclass of the [engine](https://puck.uno/src/engine/engine.lua), intended for use in testing.

## Landed

### Public API for the row-handler chain (issue [#1622](https://github.com/mikosullivan/puck/issues/1622))

Prototyped on Larry, then promoted into the base Engine class. `add_handler`, `prepend_handler`, `remove_handler`, `clear_handlers`, `handlers` all live on [src/engine/engine.lua](https://puck.uno/src/engine/engine.lua) now; Larry inherits them for free. Tests migrated to [tests/main/lua/engine/test_row_handlers.lua](https://puck.uno/tests/main/lua/engine/test_row_handlers.lua).
