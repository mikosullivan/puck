# Inside an object's on_close handler

~~~vibecode
{"vibecode": {
	"doc": "requirements_drinian_examples_on_close",
	"role": "worked Drinian snapshot: the state during a GC-invoked on_close handler running against an object whose last reference was just dropped; the handler frame is a call_stack element pushed by the engine, not by user code",
	"status": "draft — action: on_close is a distinct frame action so an inspector can see the strict handler rules apply"
}}
~~~

User code drops the last reference to an object that has an `on_close` handler. The runtime traces, finds the object unreachable, and invokes the handler synchronously in the calling frame's stack. The snapshot is taken inside the handler.

Caspian source:

~~~caspian
class
	on_close do($call)
		@socket.close                            # CAPTURED HERE
	end
end

$conn = %('myapp.com/connection').new()
$conn = null
~~~

Pause point: line 3, inside the `on_close` handler, just after the handler frame was pushed by the GC and before `@socket.close` dispatches. The connection instance is still alive — `$call.receiver` holds it for the duration of the handler — but `$conn` (the only user-code reference) has been nulled.

~~~json
{
	"comment": "Drinian mid-on_close. The handler frame at the top was pushed by the engine (not by user code) when GC determined the connection instance was unreachable from any root. The handler runs in the dying object's class's role (here, user), with strict rules enforced.",
	"srcs": {
		"a": {"file": "/home/miko/conn.casp"}
	},
	"roles": {
		"user": {},
		"engine": {}
	},
	"objects": {
		"stdout": {"class": "stream", "owner": "engine"},
		"stderr": {"class": "stream", "owner": "engine"}
	},
	"call_stack": [
		{
			"comment": "Frame 0: top-level. $conn was set on line 7, then reassigned to null on line 8. The local still exists in locals as null. The class 'myapp.com/connection' was defined at top level, but the class registry itself lives in engine-private state, not in this frame.",
			"action": "top_level",
			"role": "user",
			"lexical_parent": null,
			"src": ["a", 8],
			"locals": {
				"conn": null
			}
		},
		{
			"comment": "Frame 1: the on_close handler. Pushed by the engine when GC fired during the line 8 null-assignment. action: 'on_close' tells the engine to enforce the strict rules (2ms cap, no I/O, no allocation, no resurrection, uncatchable timeout abort). lexical_parent is 0 because the class body and its handler were defined at top level. role is user because the class is user-owned.",
			"action": "on_close",
			"role": "user",
			"lexical_parent": 0,
			"src": ["a", 3],
			"locals": {
				"call": {"hash": {
					"receiver": {
						"instance": "myapp.com/connection",
						"fields": {
							"@socket": "<ref to socket instance>"
						},
						"src": ["a", 7]
					},
					"args": null,
					"opts": null,
					"block": null,
					"super": null
				}, "src": ["a", 2]}
			},
			"gc": {
				"deadline_ms_remaining": 1.74,
				"rules": ["no_allocation", "no_io", "no_resurrection", "no_catch_abort", "no_cleanup_order_dependency"]
			}
		}
	]
}
~~~

<!-- SPEC CONFLICT: archive references a garbage-collection.md doc for the on_close rules (2ms cap, no I/O, no allocation, no resurrection). No such doc exists in current requirements/ — closest current spec content is classes/definition/index.md § on_close (which says only "runs when the engine destroys the object (deterministic GC hook)"). The archive's detailed rule set has not been ported into current spec. Needs Miko decision on whether to write the GC spec, drop the rules table here, or leave both to be resolved together -->

What to notice:

- **`action: "on_close"` is a new frame action.** Distinct from `function_call` because the engine, not user code, pushed it. The engine recognizes this action and enforces the strict GC rules while it sits on top of the stack — no allocation, no I/O, no resurrection, 2ms hard cap, uncatchable timeout abort. A snapshot inspector seeing `action: "on_close"` knows the constraints.
- **The handler runs synchronously in the calling stack.** Frame 0 (top_level) is the user-visible frame that was executing when the last reference was dropped. Frame 1 was pushed by the engine; it pops when the handler completes (normal return) or when the 2ms cap aborts it. After Frame 1 pops, top_level resumes whatever it was doing — in this case, nothing further (the program ends).
- **`$call.receiver` is the dying object.** The object's instance data lives inline in the handler's locals via `call.receiver`. This is the ONLY reference keeping the object alive during the handler — when Frame 1 pops, `call` goes with it, and the instance becomes truly unreachable. The handler cannot attach the receiver to any reachable location; the engine rejects such writes at the call site.
- **`$call.args/opts/block/super` are all null.** The GC isn't passing arguments — it's invoking the handler with a synthetic `$call` whose only meaningful field is `receiver`.
- **`lexical_parent: 0`** because the `on_close` handler was defined inside the class body, which was defined at top level. The handler's lexical chain is "own locals → frame 0." It cannot see `$conn` (also in frame 0, technically reachable lexically) in any meaningful way — `$conn` is `null` now anyway, and the dying object isn't reached via `$conn` but via `$call.receiver`.
- **`gc.deadline_ms_remaining: 1.74`** is the engine's per-handler countdown. Started at 2.0ms when the handler was pushed; the small decrement reflects time spent reaching this snapshot point. When it hits zero, the engine aborts the handler with an uncatchable termination.
- **`gc.rules`** is a denormalized convenience for inspectors — the engine enforces these rules whenever `action: "on_close"`, but listing them on the frame makes the snapshot self-describing.
- **The class definition itself isn't in the snapshot.** Class registries are engine-private state, not part of Drinian — see [drinian § Classes are NOT in Drinian](https://puck.uno/requirements/drinian/#classes-are-not-in-drinian). `myapp.com/connection` was defined on lines 1-5; the dispatcher knows about it because the engine's registry knows about it, and knows where to find the `on_close` handler when an instance collects. Whether the class is per-scope-visible (defined inside a function vs. at top level) follows Caspian's class-scoping rules — the resolution happens engine-internally, the snapshot just shows the names being resolved.

Open question:

- **Object representation more generally** — how user-defined instances are stored in Drinian (inline in locals, in a separate object heap, with reference identity) is not yet fully spec'd. This example uses inline-with-`instance` shape as a placeholder. Whatever the answer, the on_close frame's `call.receiver` will hold or reference the dying instance the same way.
