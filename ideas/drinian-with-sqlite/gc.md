# GC

~~~vibecode
{"vibecode": {
	"doc": "ideas_drinian_with_sqlite_gc",
	"role": "explanation of Drinian's garbage collection — how the mark/trace/sweep drain works against the objects table's needs_trace and in_trace scratch columns, driven by the Lua host, wrapped in a transaction. Content lands as the design gets written out.",
	"status": "stub — to be filled in"
}}
~~~

Stub. Content lands here as the GC design gets written out.

## Deterministic garbage collection

Caspian's garbage collection is **deterministic**: when an object becomes unreachable, cleanup runs right then — not at some unspecified later moment. The engine's `on_close` hook fires synchronously as part of the operation that dropped the last live path to the object. There is no unpredictable pause where the runtime "decides" to run a GC pass; there is no delay between "this resource is now unowned" and "the code that releases it runs."

The practical consequence: `on_close` is a reliable moment. A file handle released, a lock dropped, a socket closed — the developer knows this happens at the point in source where the object goes out of scope, and can reason about program state accordingly.

### `on_close`

When an instance becomes unreachable, its "on_close" methos if fired if it has one.

~~~caspian
class
	methos &on_close do($call)
        # clean up the native resource
		@socket.close
	end
end
~~~

**When it fires.** Synchronously, as part of whatever operation dropped the last live path to the object. Reassigning a variable, popping a frame that held the last local, replacing a hash element — whichever act removed the final path, `on_close` runs inside that step. Not later, not on the next tick, not at some future GC pause.

**What it's for.** Releasing state that lives outside the object graph — file descriptors, sockets, native memory, external locks, subprocess handles. The engine collects pure-Caspian state on its own; `on_close` is for the escape-hatch resources the engine can't see into.

### New objects during GC

New objects and references can be created freely during the GC process — the engine imposes no restriction on allocation while `on_close` handlers or GC-invoked code run. When the GC pass completes, if any live reference to a collected object still exists, an error is raised.

## Implementation

See [implementation](gc/implementation/) — schema-level mark triggers plus the Lua-side tracer routine.
