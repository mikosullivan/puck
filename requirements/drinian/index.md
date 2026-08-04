# Drinian

~~~vibecode
{"vibecode": {
	"doc": "requirements_drinian",
	"role": "spec for Caspian's runtime state organization: all execution state lives in a single hash, and the interpreter accesses runtime state only through that hash's interface. V1.0 ships the in-memory hash discipline (no export API, no snapshot/revive, no HTTP promise); the longer-term goal is to serialize the hash for snapshot-and-revive so a Caspian process can pause across a remote call, release the host, and revive transparently when the response arrives. Drinian is also the foundation for deterministic GC — the trace that determines reachability starts from uspace roots (see references.md) and walks the references hash.",
	"status": "V1.0 objective — narrow scope; broader capabilities deferred. In-memory state hash + interpreter discipline settled; snapshot/revive machinery and the HTTP promise() surface are post-V1.0 targets.",
	"audience": "Caspian engine implementers building the runtime; tooling authors (debuggers, inspectors, snapshot readers) that consume Drinian shapes"
}}
~~~

**Drinian** is the code name for Caspian's process-state organization: all execution state lives in a single hash, and the interpreter accesses runtime state only through that hash's interface. The longer-term goal is to serialize that hash for snapshot-and-revive — letting a Caspian process pause across a remote call, release the host process during the wait, and revive transparently when the response arrives. The foundation (the hash) ships in V1.0; the snapshot/revive machinery is deferred.

**Drinian is also the foundation for deterministic GC.** The trace that determines what's reachable starts from the **uspace roots** — reference objects whose class declares `uspace: true` (variables in live frames are the canonical example). The `references` hash inside Drinian (see [references](https://puck.uno/requirements/drinian/references)) maps every reference object to the object it points at; the engine walks from the uspace roots through this hash to determine reachability without reference counting.

<!-- SPEC CONFLICT: archive cross-references garbage-collection.md heavily; no such doc exists in current requirements/. Multiple sections below reference it; each is flagged individually. Needs Miko decision on where the GC spec should live and how deep it should go before this doc's cross-refs can be tightened -->

## V1.0 scope

V1.0 of Drinian ships **only the in-memory hash** and the structural commitment that the interpreter goes through it for all execution state:

- The runtime creates a plain in-memory hash on startup (Lua-table-backed in Lucy).
- All execution state — objects, references, call stack frames (with their locals, src, iterator positions, role, and chain), pending exceptions — lives in the hash.
- Working state (intermediate expression results, arguments being marshaled, return values being prepared) stays outside the hash.
- The interpreter never bypasses the hash interface. One rule, enforced in code review, opens every door that follows.

**Not in V1.0:**

- **No export API.** The hash cannot be serialized to JSON or any other format.
- **No snapshot/revive.** Without export, processes cannot be paused-and-resumed.
- **No HTTP `promise()`** — the user-facing feature described later in this doc depends on snapshot/revive, so it does not ship in V1.0.
- **No engine-provided hash.** The runtime creates and owns its hash; engine overrides (SQLite, distributed, etc.) are a deferred extension point.

Why ship the foundation without the feature? Because the discipline matters even without the export. The hash organization makes deterministic GC clean, makes the reference graph natural, makes the runtime inspectable, and makes every future serialization/persistence/snapshot story a contained addition rather than a runtime overhaul. V1.0 ships the foundation; V1.x lands the export and the features that depend on it.

## Cross-boundary references

Drinian's rule is about **what lives inside the hash**, not about **what everything references**. All state Drinian owns lives inside the hash. But ordinary Lua references can cross the boundary in both directions, and that's expected.

**Drinian → outside.** A Drinian object holds a reference to something the host engine owns — an open file descriptor, a live TCP socket, a running coroutine, a C-side userdata, an arbitrary handle to a non-representable resource. That's fine, and it's necessary: not everything a Caspian program needs is representable inside the state hash. The Drinian object holds the handle; the referent lives outside Drinian's scope.

**Outside → Drinian.** Some engine-side or Lua-side code (an inspector, a debugger, an FFI shim, an expression evaluator) holds a reference to an object inside Drinian. That's fine too. Ordinary Lua reference; the outside code uses it during a run.

Neither direction violates the single-hash discipline. The rule is about **state ownership** — Drinian's state is inside the hash — not about what can point at what.

## The AST lives in Drinian

The parsed AST of the running program — the CaspM the interpreter walks to execute code — is part of runtime state. It lives inside the Drinian hash, alongside everything else.

Concretely: function bodies, closure bodies, method bodies, class-definition bodies, top-level program body, loaded-library bodies — the CaspM trees for all of them — live under some top-level field (name TBD; a natural companion to the existing `srcs` registry that maps short keys to source paths).

## Worked example: Drinian mid-execution

**Note on representation.** The JSON snippets in this doc use a **simplified inline-value shorthand** for readability — locals carry their values directly as `{"value": "Aslan", "src": ["a", 6]}` rather than as references into separate `references` and `objects` tables. The full canonical form (with per-object `role` field, sequence-keyed platters in an `objects` table, `references` mapping ref-IDs to target-IDs, top-level `sequence` counter, etc.) lives in [examples/mid-execution](https://puck.uno/requirements/drinian/examples/mid-execution). The `objects` table's shape — per-object fields, ID scheme, class / variable / hash-element records — is spec'd at [objects](https://puck.uno/requirements/drinian/objects). Treat that example as authoritative for representation; this doc focuses on the structural concepts and uses lighter snippets to keep the prose moving.

V1 ships the minimum Drinian footprint — a single-field hash, `call_stack`, holding one `top_level` frame whose `role` and `chain` are the program's starting role and an empty chain. Later slices grow the hash (deeper stacks, iterator state, pending exceptions, etc.) without changing the shape. This section illustrates what a fuller hash looks like for a realistic nested execution moment.

Consider this Caspian program:

~~~caspian
function &greet($who)
	$msg = 'hello, ' + $who
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

`$count` is set at top level (line 7) and **modified from inside the `if` block** (line 11). That's the case worth tracing: variable defined in an outer scope, mutated in an inner one. Assignment to an existing name walks the lexical chain to find where the variable lives and updates it there — it does NOT create a new shadowed local in the inner scope. Compare to `$title`, which is a *fresh* name in the if-block scope and lives in that frame's locals.

Trace the execution to a specific paused moment: the engine is **on the first iteration**, inside the `do` block, the `if` test succeeded (`$name == 'Aslan'`), `$count` has been incremented to 1, `$title` has been bound, and `&greet` has been called with `$who = 'Aslan'`. The local variable `$msg` inside `greet` has been computed but not yet returned. We freeze the state right there.

The Drinian hash at that moment. The `comment` fields throughout are explanatory annotations for this walkthrough — real Drinian snapshots won't carry them.

~~~json
{
	"comment": "Drinian mid-execution, paused inside greet on the first iteration. Note count's value: it was set to 0 at line 7 and incremented to 1 from inside the if (line 11) — the updated value lives in frame 0's locals, not in the if-block's, because that's where count was defined. See Source-location tagging below for the file/src scheme.",
	"srcs": {
		"a": {"file": "/path/to/greetings.casp"}
	},
	"roles": {
		"user": {},
		"engine": {}
	},
	"call_stack": [
		{
			"comment": "Frame 0: the program's outermost frame. names and count were assigned at lines 6-7. count now reads 1, not 0 — the assignment on line 11 walked the lexical chain from the if-block, found count here, and updated it in place.",
			"action": "top_level",
			"role": "user",
			"lexical_parent": null,
			"src": ["a", 9],
			"locals": {
				"names": {"array": [
					{"value": "Aslan", "src": ["a", 6]},
					{"value": "Bree",  "src": ["a", 6]}
				], "src": ["a", 6]},
				"count": {"value": 1, "src": ["a", 11]}
			}
		},
		{
			"comment": "Frame 1: built-in array.each called by user code on line 9. Cross-role into engine; new frame's chain is reset per the role-boundary rule (see chain/index.md). lexical_parent is null because built-in code has no Caspian-level enclosing scope; src is null because engine internals have no source line.",
			"action": "method_call",
			"role": "engine",
			"receiver_type": "array",
			"method": "each",
			"iterator": {"position": 0, "of": 2},
			"lexical_parent": null,
			"src": null,
			"locals": {}
		},
		{
			"comment": "Frame 2: the do/end block at lines 9-15. Called back by array.each (which is why it's above the engine frame on the call stack), but lexical_parent jumps to frame 0 because the block was DEFINED at top level in user code. name = 'Aslan' for this iteration — value carries src ['a', 6] because it was born as a string literal on line 6.",
			"action": "block",
			"role": "user",
			"lexical_parent": 0,
			"src": ["a", 10],
			"locals": {"name": {"value": "Aslan", "src": ["a", 6]}}
		},
		{
			"comment": "Frame 3: the if's lexical scope, pushed because the test on line 10 was true. lexical_parent is the enclosing do-block (frame 2). title is local to this if and disappears when the engine reaches `end` on line 14. Notice count is NOT here — its assignment on line 11 modified frame 0, not this frame, because that's where count was defined.",
			"action": "if_block",
			"role": "user",
			"lexical_parent": 2,
			"src": ["a", 13],
			"locals": {"title": {"value": "Lord ", "src": ["a", 12]}}
		},
		{
			"comment": "Frame 4: the greet call. greet was DEFINED at top level (line 1), so lexical_parent jumps PAST frames 1, 2, 3 back to frame 0. who carries src ['a', 6] (its value was the same string literal that became name on line 6 — bindings move, the value's birth line doesn't). msg was computed on line 2 by the + operator, so its src is ['a', 2].",
			"action": "function_call",
			"role": "user",
			"function": "greet",
			"lexical_parent": 0,
			"src": ["a", 3],
			"locals": {
				"who": {"value": "Aslan",        "src": ["a", 6]},
				"msg": {"value": "hello, Aslan", "src": ["a", 2]}
			}
		}
	],
	"gc_errors": []
}
~~~

<!-- SPEC CONFLICT: archive uses "stdlib" for the array.each method_call frame. Current spec (roles/index.md) has no stdlib role — V1 has user + engine + one role per engine-provided faucet. Rewritten as "engine" throughout the examples. Needs Miko decision on which role owns built-in method dispatch, applied consistently across drinian and its examples -->

Walkthrough, frame by frame:

- **Frame 0 — top-level.** `$names` and `$count` are bound in this frame's locals — there are no globals in Caspian; top-level assignments are just locals in the top-level frame. `$count` reads `1`, not `0`: the assignment on line 11 walked the lexical chain from inside the if-block, found `$count` here, and updated it in place. src sits at line 9 where `$names.each(...)` was called.
- **Frame 1 — `array.each` running in `engine`.** This is a cross-role call: user code called into engine-owned built-in code. The frame records its iterator state (`{position: 0, of: 2}`), and carries its own `chain` (per [chain § Role boundaries reset everything](https://puck.uno/archive/003/misc/chain-old/#role-boundaries-reset-everything) — role boundaries reset the ambient chain slot). `role: engine`.
- **Frame 2 — the do-block.** Cross-role back to `user` (the block is a closure created in user code). Its local `$name` is bound to `'Aslan'` for this iteration. src is line 10, the `if` statement that's currently being executed.
- **Frame 3 — the if-block.** Same-role lexical scope inside the do block. `$title` is local to this scope and disappears when the `if` exits. src is line 13, where `puts $title + &greet($name)` is in the middle of evaluating its expression. `lexical_parent` is 2 (the enclosing do-block); variable lookup walks that chain: own locals → frame 2 (`$name`) → frame 0 (`$names`, `$count`). **`$count` is NOT in this frame's locals** even though it was assigned from inside the if — assignment to an existing name modifies the frame where the name lives, not the frame where the assignment is written. Only fresh names (`$title`) land in the inner frame.
- **Frame 4 — `greet` function.** Still `user` (functions run as their owner; `greet` is user-defined). `$who` is the argument; `$msg` is a local that's been computed but not yet returned. src is line 3. **`lexical_parent` is 0, not 3** — `greet` was DEFINED at top level, not inside the if. Its lexical chain is own locals → frame 0. `$name` and `$title` are physically between greet's frame and the top on the call stack, but they're not in greet's lexical chain and aren't visible from inside greet.

The "current role" and "current chain" are just the top frame's `role` and `chain`. There are no separate top-level `current_role` or `chain` fields — they'd be redundant with what the top frame already carries. Whatever helpers the runtime exposes (`%role`, `%chain`) read from the top of the stack.

Things to notice:

- **Role names are bare strings; the top-level `roles` registry holds per-role metadata.** Each frame's `role` field is a string that must resolve in `state.roles`. The engine validates this on every push — an unregistered name is a hard error, not a silent misdispatch. The registry's per-role entries are empty hashes in this example because V1-era roles have no metadata yet; later slices fill in trust webs, introspection state, etc.
- **Role keys are opaque identifiers.** `"user"`, `"engine"`, `markdown.uno/render` — these are convenient labels for human readability, but the engine treats them as **opaque identifiers**. Code should not parse role keys, derive meaning from them, or assume any particular naming scheme. They're just unique strings within the registry. Two loaded libraries could in principle use arbitrary-looking keys (`"r0"`, `"r1"`) and the runtime would work identically; readable keys are a convention, not a contract.
- **Roles alternate down the stack.** user → engine → user → user → user. Each cross-role transition leaves a frame with its own reset `chain`.
- **`if`/`for`/`while`/`do` are all frames.** Any new lexical scope pushes a frame with `action` indicating which kind of block. Cheap — no role transition, no method dispatch — but it makes variable lifetimes explicit (`$title` evaporates on the if's `end`) and keeps the model uniform with function and method calls.
- **`lexical_parent` is the scope chain; the call stack isn't.** Variable lookup follows `lexical_parent`, not "the frame below me." For block / if_block / for_block / while_block, those happen to match — the lexical parent is the frame immediately below. For function_call (and any closure), they DIVERGE: the function carries its definition environment, so `lexical_parent` points to whatever frame was on top when the function was defined. In the snapshot, greet (frame 4) was defined at top level, so its `lexical_parent` is 0 — past three intervening call frames.
- **Indices vs references.** `lexical_parent`, `origin_frame`, and any other "this frame points to that frame" field are integer indices in the JSON serialization but Lua table references in memory. The index is scoped to whichever array it appears in: a `lexical_parent: 0` on a frame in `call_stack` means position 0 of `call_stack`; the same field on a frame in `captured_stack` means position 0 of *that* captured_stack. The serializer is what converts the in-memory reference to the appropriate index for the array being emitted.
- **Closures that outlive their defining scope: deferred.** When a function escapes the scope where it was defined (returned as a value, stored in a container, called later), the captured environment can't live on the call stack — that scope has unwound. Handled in most languages by giving each closure a captured-environment object that outlives the call stack. For Drinian that'd be a sibling field like `captured_envs: [{locals, lexical_parent}, ...]`, with `lexical_parent` on a function_call frame pointing either into `call_stack` (still-live defining scope) or into `captured_envs` (defining scope has unwound). V1.0 may not need this if closures don't escape; left for later.
- **Chain is per-frame, with inheritance and role-boundary resets.** Per [chain § Frame inheritance](https://puck.uno/archive/003/misc/chain-old/#frame-inheritance), each frame gets its own chain; changes propagate DOWNWARD only (descendants see the changes, the parent sees its chain exactly as it was before the call). Role boundaries reset the chain: default-deny capabilities drop, the ambient hash slot empties, the callee starts with only default-granted surfaces. <!-- SPEC CONFLICT: archive says every frame gets a fresh chain on push regardless of role — no cascade, no aliasing, caller's values never visible to callee. Current chain spec (chain/index.md) says the OPPOSITE: chain inherits DOWNWARD within a role (descendants see ancestor values) and only resets at role boundaries. Rewritten to the current-spec model. Needs Miko decision if the archive's fresh-per-frame model was the intended one — the two are incompatible and change the shape of what `chain` looks like on the frame -->
- **All values carry their CaspJ expression shape.** `$msg` isn't the bare string `"hello, Aslan"`; it's `{"value": "hello, Aslan"}` — the same shape the dispatcher consumes. That uniformity means the hash is directly inspectable by the engine without re-marshaling. <!-- Note: archive says "CaspianJ" here; the format is now split into CaspJ (source fidelity) and CaspM (the AST) per requirements/caspianj.md. Kept as "CaspJ expression shape" — Drinian values track the CaspM/dispatcher shape -->
- **Iterator state is just data.** `{"position": 0, "of": 2}` — enough for the engine to resume iteration from where it left off. No special "iterator object" type, no opaque handle. (Compare to Python generators, which hide iteration state inside an opaque frame.)
- **In-flight exceptions live as elements of `call_stack`, not in a separate field.** When a `throw` fires, the engine appends an element with `action: "exception"` to the top of `call_stack`. As the exception unwinds, frames pop from beneath it; the exception itself sits at the top throughout. When it's caught (or escapes the program), the exception element pops too. No separate `pending_exceptions` top-level field — the call_stack array uniformly holds frames AND in-flight exceptions, distinguished by the `action` value. See [Exceptions and the captured stack](#exceptions-and-the-captured-stack) below for the per-exception shape, the optional `captured_stack` field, and how nested exceptions stack.
- **`gc_errors` is an engine-maintained list of on_close failures.** Stays empty when no GC handler has raised. When one does, the runtime catches the error (so one bad handler doesn't break GC for other objects), appends a record `{class, message, src}` to this list, and continues. Inspectable from any snapshot — a long list is a smell. Programs can read `%state.gc_errors` if they want to check for cleanup failures at shutdown. NOT the per-frame `chain` mechanism; that's frame-scoped ambient context, this is process-wide engine state. <!-- SPEC CONFLICT: %state is not a documented global; global-methods/index.md lists eight globals and %state is not among them. Needs Miko decision on the accessor: %state.gc_errors, %engine.gc_errors, an on-demand fetch, or something else -->

This is what V1.0 Drinian is **shaped like** — not what it ships in V1. V1's hash is the bottom slice of this (the `roles` registry populated with `user` + `engine`, and a `call_stack` with one `top_level` frame); subsequent slices fill in the other fields as the engine grows to need them.

### Role delegations

When user code enters a `%role.delegate_to(X) do ... end` block, the engine pushes a frame whose `delegations` field records which role is being granted permissions in this block's scope. The delegation lives on the frame; when the frame is popped (normal exit, alarm unwind, anything else), the delegation goes with it. See [roles](https://puck.uno/requirements/roles/) for the identity system that establishes what a role is and what a delegation targets.

Permission resolution walks the stack looking for delegations whose **target role matches the role the checking code is running as**. So a frame running AS the agent role finds an `{"agent": {}}` grant on a parent frame and uses the elevation; a frame running AS engine looks for delegations targeting engine, finds none, and uses engine's normal permissions. Role transitions don't "consume" the delegation — they just take execution into a role the delegation doesn't target, and re-entering the targeted role re-engages the elevation by the same mechanism.

A role-level convenience view ("what delegations are currently extending the agent role's permissions?") is **derivable** by walking the call stack and unioning all active grants for that role. It is not stored as separate state — the canonical record is the stack itself.

#### Full example: user delegating to agent, mid-execution

Consider this Caspian program:

~~~caspian
$db = %('dirjail')['./data'].new()
$agent = %('agents.example.com/claude').new()

$result = %role.delegate_to($agent.obj.role) do
	$agent.yield(db: $db, prompt: 'find recent users')
end
~~~

At line 4, the program enters a `delegate_to` block extending the user role's permissions to the agent's role. Inside the block, `$agent.yield` round-trips to the remote agent; the agent returns a Caspian function; the engine invokes that function in the agent's role. The agent's function is now running and is itself making a method call on the dirjail object that was passed in as `db`.

Capturing Drinian mid-execution at the moment of the agent's `db.find()` call:

~~~json
{
	"roles": {
		"user": {},
		"engine": {},
		"agent": {}
	},

	"call_stack": [
		{
			"comment": "Frame 0: the program's outermost frame. $db and $agent were constructed on lines 1-2. We're past line 4 — execution is inside the delegate_to block at this point, so the parent frame's src points at the line that initiated the block.",
			"action": "top_level",
			"role": "user",
			"src": ["a", 4],
			"locals": {
				"db": {"ref": "obj_42"},
				"agent": {"ref": "obj_43"}
			}
		},
		{
			"comment": "Frame 1: the delegate_to block. The delegations field records that this frame grants the agent role the user role's permissions for the block's lifetime. When this frame pops (block exit, alarm, anything), the grant goes with it — no separate cleanup step.",
			"action": "delegate_to",
			"role": "user",
			"delegations": {"agent": {}},
			"src": ["a", 4],
			"locals": {}
		},
		{
			"comment": "Frame 2: the $agent.yield(...) call. The engine has already round-tripped to the agent over ACP, received the agent-authored function, and is now invoking it. Action is method_call from user's perspective; the actual function-invocation frame is Frame 3.",
			"action": "method_call",
			"receiver_type": "agent",
			"method": "yield",
			"role": "user",
			"src": ["a", 5],
			"locals": {}
		},
		{
			"comment": "Frame 3: the agent-authored function the engine is invoking. Cross-role into agent. Per the agent-yield protocol the function's first param is the agent object itself, followed by the kwargs the caller supplied (db, prompt). The agent's role has user's permissions because Frame 1's delegation is on the stack above this frame.",
			"action": "function_invocation",
			"role": "agent",
			"src": null,
			"locals": {
				"agent": {"ref": "obj_43"},
				"db": {"ref": "obj_42"},
				"prompt": {"value": "find recent users", "src": ["a", 5]}
			}
		},
		{
			"comment": "Frame 4: the agent's function called db.find('user:recent'). Cross-role into engine (which owns dirjail methods here). Note that even though Frame 1 delegated user's permissions to agent, this call is now executing as engine — delegations follow the FRAME of the delegation, not the chain of frames that descended from it. agent's elevated permissions don't transfer onto engine just because engine was called from within the delegated scope.",
			"action": "method_call",
			"receiver_type": "dirjail",
			"method": "find",
			"role": "engine",
			"src": null,
			"locals": {
				"query": {"value": "user:recent"}
			}
		}
	]
}
~~~

<!-- SPEC CONFLICT: this example relies on an "agent" role that current roles/index.md lists as deferred post-V1 (agent identity roles). Needs Miko decision on whether this example demonstrates a faucet role instead, or whether the agent role is now in scope -->

A few things to notice in this snapshot:

- **The `delegations` field sits on Frame 1.** That's the frame that established the delegation. Nothing outside that frame has any record of the grant; nothing inside the engine has to "remember" to lift it. When Frame 1 unwinds, the grant is gone.
- **Frame 3's role is `agent`, not `user`.** Identity is preserved per the roles spec — actions taken inside the agent's function are attributed to the agent, even though the agent has user's permissions for now. Auditing and ownership chains see the agent doing things; the elevation is visible in source as the enclosing `delegate_to` block (Frame 1).
- **Frame 4's role is `engine`, not `agent`.** This is the subtle security-relevant point: delegation extends the **named** role's permissions, not the call-chain's. When the agent's function called `db.find()`, the call crossed into `engine` (the role that owns dirjail methods here), and `engine` has its own permissions — it does NOT inherit anything from the active delegation. Frame 1's grant applies to permission checks made AS the agent role; once execution crosses into `engine`, the agent's elevation isn't relevant.
- **Stack-walking resolves permissions, not lookup tables.** When the engine needs to decide whether some agent-role operation is permitted, it walks the stack and finds Frame 1's delegation. Permission resolution and the call chain are the same data structure.
- **If an alarm raised inside Frame 4**, it would unwind up through Frame 3, then Frame 2, then Frame 1. As Frame 1 pops, the delegation is gone. Frame 0 catches it (or it propagates out), and at no point does any "lift delegation" handler need to fire — the stack unwinding IS the lifting.

If the same program had nested `delegate_to` blocks, additional `delegations`-bearing frames would stack up in the same way; permission resolution walks the stack and applies each in order; unwinding undoes each in reverse.

### Object ownership

Every entry in `state.objects` (see [objects](https://puck.uno/requirements/drinian/objects) for the hash's per-object shape and ID scheme) carries a top-level `role` field naming the role that owns the object. The value is one of the strings in `state.roles` — `"user"`, `"engine"`, `"agent"`, or whatever roles the program has.

~~~json
"objects": {
	"10": {
		"role": "user",
		"src": ["a", 6],
		"bucket": {"value": "Aslan"},
		"stack": [
			{"class": "core:string"}
		]
	}
}
~~~

The `role` field's value is determined at object creation per [roles § Objects also have roles](https://puck.uno/requirements/roles/#objects-also-have-roles) — short version: an object's role is the role of the code that *conceptually* creates it (the expression-evaluator), not necessarily the runtime frame doing the underlying work. A string produced by user code's `'a' + 'b'` is `role: "user"` even though the `+` method internally runs in an engine frame.

**Frame role and object role answer different questions.** A frame's `role` (in `call_stack` entries) tells you whose code is executing in that frame right now. An object's `role` (in `objects` entries) tells you who owns the value. They coincide in most cases — a user-frame's locals usually hold user-owned values — but they're independent fields tracking independent things. In particular, engine frames routinely create values that user code conceptually owns (returned across the role boundary on the way out of the call).

Once set at allocation, the field is immutable — values can move between roles (be passed into a different-role function, returned to a different-role caller) but the ownership recorded in `state.objects` follows the value, not the value's current location.

### Classes are in Drinian

In Caspian, classes are objects like anything else. Every class — built-ins (`string`, `array`, `hash`, `integer`, etc.), runtime-registered classes (via `Class.new`), library-defined classes when a library loads — lives inside Drinian as an object, alongside frames, roles, and every other object. Class method bodies are the CaspM AST that also lives in Drinian; see [The AST lives in Drinian](#the-ast-lives-in-drinian).

There is no engine-private class registry. The dispatcher resolves `foo.bar()` by looking up the class object in Drinian and walking its methods. Class references inside Drinian (e.g., `receiver_type` on a `method_call` frame, or `class_ref` on a value) point at the class object through the normal reference mechanism — same shape as any other object reference.

Symmetric with **roles**, which also live in Drinian (`state.roles`). Both are program-visible objects the running program can inspect; both persist across whatever future export the runtime grows.

### Source-location tagging

Every value in Drinian — locals, chain entries, frame `src` — can carry a back-pointer to where it came from in source. The infrastructure: a top-level `srcs` registry interning paths to short keys, plus a 2-element `src` tuple `[src_key, line]` on each tagged thing.

**The registry** sits at the top of the hash, alongside `roles`:

~~~json
"srcs": {
	"1": {"file": "/path/to/greetings.casp"},
	"8": {"file": "/path/to/lib/io.casp"}
}
~~~

Each entry is a tagged object — the entry's value declares what kind of source it refers to. Local files use `{"file": "..."}`; URL sources use `{"uns": "..."}`. **For multi-file URL-loaded libraries, each source file gets its own registry entry** with the file name in the URL path (e.g., `{"uns": "markdown.uno/render/render.casp"}`). Future kinds can be added (`{"url": ...}`, `{"git": ...}`, etc.) without changing the registry shape.

**Keys come from the global sequencer** — the same counter that mints object IDs and platter IDs. They're integer-strings drawn from the shared pool, interleaved with object/platter IDs. Keys are stable within a single program execution but not across runs — the registry is in the snapshot, so anything reading it can resolve. Typical program has 1-50 src entries; the registry itself is tiny.

**The `src` tuple** appears wherever a thing has a source origin:

~~~json
{"value": "Aslan", "src": ["a", 6]}    // value created on line 6 of file a
{"value": 1,       "src": ["a", 11]}   // result of "$count + 1" computed on line 11
~~~

**The `src` field on frames** uses the same tuple shape, since src is just "current source position" of a frame:

~~~json
"src": ["a", 9]      // currently at line 9 of file a
"src": null          // engine internal — no source line
~~~

**Cost.** O(1) extra per value (one small array). Snapshot growth ≈5-10% in the verbose case; less in compact serializations. Memory per value: tens of bytes vs. the kilobytes you'd pay without interning. The transpiler already populates `line` on every CaspJ node (per [caspianj § Line annotations](https://puck.uno/requirements/caspianj)), so propagation through Drinian is "copy the line during materialization" — one helper, applied everywhere a value is born.

**Semantics of `src` on a value:**

- The value's *birth* line, not the binding's. `$x = $y` doesn't change `$y`'s value's `src` — the binding moved, the value didn't. So a string passed through five function calls retains the `src` of the literal that created it.
- A value produced by an operator (`+`, `==`, etc.) gets the operator's `src` — "this value came into existence here."
- A value from a method or function return gets the `src` of the `return` statement (or last-expression line for implicit return).

**Hand-written CaspM has no `line` annotations,** so its values have no `src`. The field is simply omitted. Inspectors render "(no source)" or skip the source-link column. Slice docs from the earliest Caspian-source slices show snapshots without `src` for this reason.

**Metaprogramming.** Most metaprogramming is handled naturally by function literals: a `function ... end` body carries a real `src` even when attached to a dynamically-created class at runtime. When `$obj.greet(...)` dispatches a method whose body came from a function literal on lines 12-14, the frame's `src` tracks those lines. No special case.

The only genuinely source-less case (a method body constructed from a string, via some future `eval`-like primitive) is handled by simply **omitting `src`**. The inspector renders "(no source)" and moves on. A richer scheme (e.g., a `meta_src` field pointing to the construction site) is a natural future extension, but V1.0 doesn't need it: Caspian's V1 metaprogramming surface (`Class.new`, `add_method(name, function_literal)`, dynamic dispatch) preserves source through function literals. If a string-to-code primitive lands later, the `src`-or-omitted structure leaves room to grow.

#### Decisions summary

- **Top-level field is `srcs`** (plural of `src`, matching the convention used for `roles`). Maps short keys to full paths.
- **Keys come from the global sequencer** — integer-strings drawn from the shared pool that also mints object IDs and platter IDs. Stable within a single program execution; not stable across runs.
- **Multi-file URL-loaded libraries get one srcs entry per file**, with the file name in the URL value (e.g., `{"uns": "markdown.uno/render/render.casp"}`).
- **The reference field is `src`** (chose this over `loc`, the named `{"file": "a", "line": 42}` split form, etc.). Holds a 2-element tuple `[src_key, line]`.
- **`src` tags values** in `locals`, in arrays/hashes, in chain entries, in pending exceptions — anything with a creation point in source.
- **`src` on frames uses the same `[src_key, line]` shape** since it's just "where this frame currently is in source." `null` when there's no source (engine internals, hand-written CaspM).
- **A value's `src` is its birth line, not its current binding's line.** Passing a value through assignments and calls doesn't change its `src`.
- **A value produced by an operator gets the operator's `src`.** `$msg = $a + $b` on line 7 gives the result `src: ["a", 7]` regardless of where `$a` and `$b` came from.
- **A value returned from a function/method gets the return statement's `src`** (or the last expression's `src` for implicit return).
- **`src` is omitted when unknown.** Hand-written CaspM and truly source-less metaprogramming output both produce values without `src`. Inspectors render "(no source)" and move on. No `null`, no sentinel — the field is simply absent.
- **Future extension stays open.** A `meta_src` field for construction-site provenance, or external debugger plugins, can fill in gaps later without changing the V1.0 structure.

**Multi-file libraries: one entry per file.** A URL-loaded library with multiple source files registers one `srcs` entry per file, with the file name baked into each entry's `uns` value (e.g., `{"uns": "foo.bar/baz/render.casp"}` vs `{"uns": "foo.bar/baz/parser.casp"}`). That keeps the src tuple uniform at 2 elements — `[src_key, line]` — everywhere, regardless of whether the source is a single file, a library file, or anything else added later. The alternative (one entry per library with file disambiguation inside the src tuple) was rejected because it makes every src consumer handle two tuple shapes; pushing the cost to one registry table instead of many readers is the better trade.

#### Examples

**Multi-file registry.** A program that uses `&greet` from `lib/io.casp` and the array-each block from `main.casp`:

~~~json
"srcs": {
	"a": {"file": "/path/to/main.casp"},
	"b": {"file": "/path/to/lib/io.casp"}
}
~~~

A value created by a literal in `lib/io.casp` line 4 carries `"src": ["b", 4]`; a value created in `main.casp` line 9 carries `"src": ["a", 9]`. The registry grows as new sources are encountered during loading — typically 1-50 entries even for substantial programs.

**Mixed local and remote.** A program that also loads a URL-fetched library:

~~~json
"srcs": {
	"a": {"file": "/path/to/main.casp"},
	"b": {"file": "/path/to/lib/io.casp"},
	"c": {"uns": "markdown.uno/render/render.casp"}
}
~~~

A value created inside the loaded library on line 17 carries `"src": ["c", 17]`. The `uns` key declares the source kind, so the value doesn't need a URL prefix — that's implicit.

**Birth line, not binding line.** Tracing where a value came from across multiple assignments:

~~~caspian
$first = 'Aslan'        # line 6 — string literal created here
$second = $first         # line 7 — rebinding, no new value
$third = $second         # line 8 — rebinding, no new value
~~~

After execution:

~~~json
"locals": {
	"first": {"value": "Aslan", "src": ["a", 6]},
	"second": {"value": "Aslan", "src": ["a", 6]},
	"third": {"value": "Aslan", "src": ["a", 6]}
}
~~~

All three bindings point at the same string value, which was born on line 6. The bindings moved across lines 7 and 8; the value didn't. (In memory, all three locals can even alias the same value record; the serializer shows the value inline for each.)

**Operator-produced value.** Arithmetic and string operations give their result the operator's `src`:

~~~caspian
$a = 2                   # line 10
$b = 3                   # line 11
$sum = $a + $b           # line 12 — operator on line 12
~~~

Result:

~~~json
"locals": {
	"a": {"value": 2, "src": ["a", 10]},
	"b": {"value": 3, "src": ["a", 11]},
	"sum": {"value": 5, "src": ["a", 12]}
}
~~~

`sum`'s value `5` came into existence on line 12, not 10 or 11 (its operand birth lines).

**Function return.** A value returned from a function gets the return statement's `src`:

~~~caspian
function &double($x)
	return $x * 2        # line 2 — return statement
end                      # line 3

$y = &double(7)          # line 5 — call site
~~~

Result:

~~~json
"locals": {
	"y": {"value": 14, "src": ["a", 2]}
}
~~~

`y`'s value `14` came into existence on line 2 (where the `return` executed), not line 5 (where it was bound to `y`). The call site is recoverable from the function_call frame's position when paused mid-call; the value's `src` records its birth, not where it landed.

**Chain entry tagging.** When user code writes to chain, the write line is recorded:

~~~caspian
$some_function_on_line_50()    # writes %chain['user_id'] = 'u42'
~~~

The chain entry:

~~~json
"chain": {
	"user_id": {"value": "u42", "src": ["a", 50]}
}
~~~

The src on the entry tracks the write line, which is the same as the value's birth line in this case (a literal string written via assignment).

<!-- SPEC CONFLICT: archive shows chain as nested {log: {}, misc: {user_id: ...}}. Current spec (chain/index.md) uses a flat hash: %chain['user_id']. Rewritten to the flat form throughout -->

**Source-less value.** A method body constructed dynamically without source:

~~~json
"locals": {
	"result": {"value": "computed", "src": ["a", 22]},
	"dynamic": {"value": "from_eval"}
}
~~~

`result` has its src; `dynamic` doesn't — `src` is simply absent. An inspector rendering this would show:

~~~
result   "computed"   main.casp:22
dynamic  "from_eval"  (no source)
~~~

**Inspector-rendered stack trace.** A formatter walking `call_stack` with the srcs registry resolved:

~~~
Stack trace:
  frame 4: greet     /path/to/lib/io.casp:3       (function_call, user)
  frame 3: <if>      /path/to/main.casp:13        (if_block, user)
  frame 2: <do>      /path/to/main.casp:10        (block, user)
  frame 1: each      (internal)                   (method_call, engine)
  frame 0: <top>     /path/to/main.casp:9         (top_level, user)
~~~

Frame 1's `src: null` renders as `(internal)`. All other frames resolve their `src: [src_key, line]` tuple against `srcs` to produce human-readable paths.

### Deeper stack: recursive tree walk

The previous example tops out at four frames. Real programs go much deeper — recursion, nested method calls, helper functions calling helper functions. This example walks a three-level tree to show what a meaningfully deeper Drinian looks like.

~~~caspian
function &print_tree($node, $depth)
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

Pause point: the innermost `&print_tree` call (for the `leaf` node) has just been entered. Execution sits at `puts $node['name']` — about to dispatch `puts`, not into it yet. Eight call-stack frames.

See [examples/recursion](https://puck.uno/requirements/drinian/examples/recursion) for the full snapshot.

What the deeper stack illustrates that the shorter one didn't:

- **Same function, different frames.** Three `function_call` frames all named `print_tree`, at src line 3, line 3, and line 2 — three different call sites, three different `$depth` values (0, 1, 2), three different `$node` bindings. Recursion is just stack frames; the engine doesn't model recursion specially.
- **Role alternation persists at depth.** user → user → **engine** → user → user → **engine** → user → user. Every `array.each` is a cross-role hop into engine; the body block hops back to user. Each engine frame carries its own reset `chain`.
- **Iterator state survives recursion.** Two distinct `array.each` frames, each at `position: 0, of: 1`. When `&print_tree(leaf, 2)` finishes and unwinds, the engine resumes the inner `each` from its saved position — independently of the outer `each`. No shared iterator state, no implicit nesting trick.
- **References, not value-copies.** `$node` in frames 1, 4, and 7 uses `"<ref to ...>"` placeholders in the recursion example, but in the actual hash each binding is a short object ID (see [references § Object IDs](https://puck.uno/requirements/drinian/references#object-ids)) whose target lives in the top-level `references` hash. The shared `$node` aliasing is recorded by multiple reference IDs pointing at the same target object — see [examples/references](https://puck.uno/requirements/drinian/examples/references) for what that looks like concretely. The placeholders in the recursion example are a notational shorthand for readability.
- **src granularity matters.** Frames 1 and 4 both sit at "line 3" (the `puts` statement), but they're at different points in their respective executions: frame 1 finished `puts 'root'` and is now inside `.each`; frame 4 finished `puts 'mid'` and is now inside *its* `.each`. src alone doesn't distinguish them — the frame's surrounding state does.

Production Drinian will need a richer src representation (likely adding a `statement_index` or `sub_position` alongside the existing `[src_key, line]` to disambiguate paused-mid-expression cases). V1.0 doesn't tackle that; it ships enough src fidelity to support resumption between statements, which is all a single-process in-memory hash needs.

### Exceptions and the captured stack

An in-flight exception lives as an **element of `call_stack` itself**, with `action: "exception"`. It sits at the top of the array while the exception is unwinding; it pops when the exception is caught (or escapes the program). There is no separate `pending_exceptions` top-level field — `call_stack` uniformly holds frames AND in-flight exceptions, distinguished by the `action` value. See [examples/exception](https://puck.uno/requirements/drinian/examples/exception) for the full structural shape.

When the engine reaches the exception element during normal "what should I do next" inspection, it knows: an exception is unwinding. The frames below the exception (in array index order) are the frames the exception is unwinding through. As unwinding proceeds, frames pop from beneath the exception one at a time, each one checked for a matching catch handler.

Caspian's exception model is single-flight per [exceptions](https://puck.uno/requirements/exceptions/) — the call_stack has at most one `action: "exception"` element at a time in user-visible programs. The rare exception-during-exception case (an `on_close` hook itself raising while a prior exception unwinds) is handled at the engine level: every `on_close` invocation runs inside an engine-level try/catch that prevents on_close-raised exceptions from escaping into the user's exception stream.

<!-- SPEC CONFLICT: archive links to garbage-collection.md § Engine wraps the handler for the on_close try/catch rule. No such doc exists in current requirements/. Needs the GC spec written or the rule inlined here -->

**The captured_stack problem.** When an exception is raised, the engine unwinds looking for a handler. By the time the exception reaches a debugger, an uncaught-error handler, or the host, the frames between the raise point and the catch point (or the top, for uncaught) have been popped. Without intervention, all you'd see by the time the program exits is the exception element on a near-empty call_stack — the context where it actually happened is gone.

So at raise time, the engine snapshots the frames below the exception into the exception's `captured_stack` field. **Capture is by reference, not by deep copy** — see [Capture-by-reference](#capture-by-reference-the-cost-model) below for the cost analysis.

Consider this Caspian program, with the second iteration raising:

~~~caspian
function &greet($who)
	if $who == ''
		throw 'name cannot be empty'
	end
	$msg = 'hello, ' + $who
	return $msg
end

$names = ['Aslan', '']

$names.each($name) do
	puts &greet($name)
end
~~~

First iteration prints `hello, Aslan`. Second iteration calls `&greet('')`, the `if` test succeeds, `throw` fires on line 3. No `try` catches it; unwinding proceeds all the way up.

**Snapshot at the moment `throw` fires** (before any unwinding):

~~~json
{
	"roles": {"user": {}, "engine": {}},
	"call_stack": [
		{"action": "top_level",     "role": "user",   "lexical_parent": null, "src": "line 11", "locals": {"names": "<...>"}},
		{"action": "method_call",   "role": "engine", "lexical_parent": null, "src": "internal", "method": "each", "iterator": {"position": 1, "of": 2}, "locals": {}},
		{"action": "block",         "role": "user",   "lexical_parent": 0,    "src": "line 12", "locals": {"name": {"value": ""}}},
		{"action": "function_call", "role": "user",   "lexical_parent": 0,    "src": "line 3",  "function": "greet", "locals": {"who": {"value": ""}}},
		{"action": "if_block",      "role": "user",   "lexical_parent": 3,    "src": "line 3",  "locals": {}},
		{
			"action": "exception",
			"class": "core:error/runtime",
			"message": "name cannot be empty",
			"src": "line 3",
			"captured_stack": "<five references — one per frame below, in order>"
		}
	]
}
~~~

The exception element is the last entry in `call_stack`. Its `captured_stack` field holds five references — one per frame below it. The references and the live `call_stack` point at the same five frame tables. No copy yet; just five pointers.

**Snapshot after full unwinding** (uncaught; engine is about to hand the exception to the host):

~~~json
{
	"roles": {"user": {}, "engine": {}},
	"call_stack": [
		{"action": "top_level", "role": "user", "lexical_parent": null, "src": "line 11", "locals": {"names": "<...>"}},
		{
			"action": "exception",
			"class": "core:error/runtime",
			"message": "name cannot be empty",
			"src": "line 3",
			"captured_stack": [
				{"action": "top_level", "role": "user", "lexical_parent": null, "src": "line 11", "locals": {"names": "<...>"}},
				{"action": "method_call", "role": "engine", "lexical_parent": null, "src": "internal", "method": "each", "iterator": {"position": 1, "of": 2}, "locals": {}},
				{"action": "block", "role": "user", "lexical_parent": 0, "src": "line 12", "locals": {"name": {"value": ""}}},
				{"action": "function_call", "role": "user", "lexical_parent": 0, "src": "line 3", "function": "greet", "locals": {"who": {"value": ""}}},
				{"action": "if_block", "role": "user", "lexical_parent": 3, "src": "line 3", "locals": {}}
			]
		}
	]
}
~~~

The live `call_stack` is short (only the top_level frame and the exception element remain — the method_call, block, function_call, and if_block frames have all been popped during unwinding). The `captured_stack` inside the exception still holds all five original frames — the popped frame tables weren't destroyed, just removed from `call_stack`. The exception's references kept them alive.

An uncaught-exception report formatted from `captured_stack` shows the program at line 3 inside `greet`, called via the do-block, called via `array.each`, called from line 11. That's the actually-useful debugging output. A report formatted from the live `call_stack` would just say "at line 11" — technically true and completely useless.

**Catch resolution.** When a catch handler matches and runs to completion, the engine pops the exception element from `call_stack`. Execution resumes inside the catching frame's handler body. The `captured_stack` references continue to keep the popped frames alive until the exception record itself becomes unreachable — useful if user code stashed the caught exception in a variable for later inspection.

### Capture-by-reference: the cost model

The naive read of "snapshot the stack at raise time" is "deep-copy everything reachable" — which would be expensive (potentially megabytes of state copied on every exception). That's not what happens.

**What actually happens:**

~~~lua
exception.captured_stack = {}
for i, frame in ipairs(engine.state.call_stack) do
	exception.captured_stack[i] = frame   -- reference, not copy
end
~~~

O(stack_depth) pointer storage. Typical depths are 5-50 frames, so 5-50 pointer-sized writes. Effectively free compared to the exception itself.

**Why references are stable:** the engine doesn't mutate a frame after popping it. `table.remove(call_stack, i)` removes the reference from the array; it doesn't touch the table itself. So a held reference to a popped frame is a true point-in-time view — frozen the moment the frame stopped being on the live stack.

**Memory implication:** frames in `captured_stack` (and everything reachable from their `locals` and `chain`) can't be garbage-collected until the exception resolves. Short-lived in practice (catch handlers run quickly, uncaught exceptions terminate the program). The pathological case is a long-lived caught exception that pins large locals — worth a note, not worth solving in V1.0.

**Caught-vs-uncaught nuance:** for uncaught exceptions, every referenced frame is popped → frozen. Perfect point-in-time snapshot. For caught exceptions, the catching frame survives unwinding and may continue mutating after capture (its src advances into the catch handler, new locals get bound). The `captured_stack` reference to that frame would reflect the live state, not the at-raise state. Two ways to handle this:

1. **Only capture the would-be-popped portion.** At catch time the engine knows which frames will pop; capture just those. The surviving frames can be inspected live.
2. **Capture the full stack but mark the catch boundary.** The captured_stack[catch_index] entry gets a flag saying "this frame is still live; don't trust its post-raise state."

V1.0 can defer this choice — exception machinery isn't in scope until later slices. For uncaught (the common debugging case), both designs give the same answer.

**Engine-only access:** `captured_stack` is engine-controlled, not exposed to user-code catch handlers. Two reasons:

- **Secrets in locals.** A function holding an API token in its locals throws → the catcher shouldn't be able to read the token via the exception. The engine offers a *formatted* stack trace (class names, function names, line numbers as strings) and the exception's own class/message, but not the raw frame tables.
- **Trust-web preservation.** If any frame could read any other frame's state by raising-and-catching, role boundaries would be defeated.

The user-visible API (sketch):

~~~caspian
catch ($e)
	puts $e.message          # OK — formatted
	puts $e.stack_trace      # OK — formatted strings
	puts $e.captured_stack   # error — engine-only
end
~~~

### Loaded remote library and the trust barrier

A program that loads a remote Caspian library via `%fetch` and calls a method on it — and along the way puts something into `%chain` that the library is NOT supposed to see:

~~~caspian
$markdown = %('markdown.uno/render')
%chain['api_token'] = 'sk-secret-abc123'
$html = $markdown.to_html('# Hello')
puts $html
~~~

Pause point: inside `to_html` in the loaded library, partway through. The library has tokenized the input and is building the output string. See [examples/remote-library](https://puck.uno/requirements/drinian/examples/remote-library) for the full snapshot.

Things to notice:

- **`roles` registry has three entries.** Two engine-bootstrap roles (`user`, `engine`) and one runtime-loaded one (`markdown.uno/render`). The library's role entry carries metadata: where it was loaded from (the URL), where in user code the load happened, and its trust web (empty — the library can't reach any other role from inside its own dispatch).
- **`srcs` registry mixes local and remote, with tagged kinds.** Entry `a` is `{"file": "..."}`. Entry `b` is `{"uns": "..."}`. The key in each entry declares the source kind, so consumers don't have to parse strings to tell file paths from URL references. Future kinds (`url`, `git`, etc.) slot in without disturbing the registry shape.
- **The library's role name IS its URL.** `markdown.uno/render` as a role name is fine — names are arbitrary strings, and URL gives a globally unique identifier with no risk of collision with other loaded libraries.
- **The library's class IS visible in the snapshot.** `Renderer` was registered when `%('markdown.uno/render')` executed — added to Drinian as a class object like any other object (see [Classes are in Drinian](#classes-are-in-drinian)). The dispatcher resolves `class_ref: "Renderer"` (on `markdown`) and `receiver_type: "Renderer"` (on the `method_call` frame) by looking up the class object inside Drinian. The name `"Renderer"` is the key; the class definition itself — method bodies as CaspM AST, class metadata, everything — lives in the hash.
- **The trust barrier is invisible in the snapshot, by design.** The user's frame has `chain: {"api_token": "sk-secret-abc123"}`. The library's frame has `chain: {}` — empty. The library's `to_html` cannot reach the token by reading `%chain['api_token']` — the chain is reset at the role boundary per [chain § Role boundaries reset everything](https://puck.uno/archive/003/misc/chain-old/#role-boundaries-reset-everything). Trust isolation is the role boundary's normal behavior, not a special "remote library" feature. Drinian needs no new field for this.
- **`lexical_parent: null` on the library's frame.** The library's `to_html` was defined in the library's own top-level scope — which ran once when the library was loaded, then unwound. Its captured environment isn't on the live `call_stack`. In a full implementation this would point into a sibling field like `captured_envs`. For V1.0 it shows as `null` because escaped-closure environments aren't built yet.
- **`input`'s `src` points at the user's file line**, not the library's — the value `'# Hello'` was born as a literal on the user's line, then passed across the role boundary. Birth-line travels with the value — the library can see where the input originated. Whether that's a *feature* or an *information leak* (the trust barrier arguably should hide caller-source detail from the callee) is an open question worth deciding before V1.0.
- **`tokens`'s `src` points to file `b`.** Values created inside the library carry the library's source location. No conflict with user-file lines because the file key disambiguates.

The takeaway: loading a remote library is **structurally identical** to anything else that introduces a role — adding an entry to `roles`, a possible entry to `srcs`, and pushing frames that reference it. The chain reset at role boundaries does all the trust isolation work. Drinian's job is just to make the role and file boundaries visible.

---

## Future: snapshot-and-revive (post-V1.0)

The original Drinian vision — transparent snapshot-and-revive across blocking remote calls — depends on adding an export API to the V1.0 hash. The sections below describe that target shape. None of it ships in V1.0; it's recorded here so the V1.0 work is done with the post-V1.0 capability in mind.

The post-V1.0 flow: a Caspian program makes what looks like a synchronous call; under the hood, the runtime serializes the entire process state, releases the host, dispatches the remote operation, and revives the process with the response value in hand when the operation completes. Code stays linear. Host resources go to zero during the wait. Crashes during the wait are transparent — the snapshot revives on whatever host picks it up next.

---

## Post-V1.0 API (deferred)

The only way to make a promise (in the post-V1.0 design) is via an HTTP request object:

~~~caspian
$http = %('http/request').new('https://foo.com?q=303')
$response = $http.promise()
~~~

<!-- SPEC CONFLICT: archive uses puck.uno/http/request as the class identifier. UNS is dropped; the current spec's http/request is at requirements/http/. Rewritten to a plain %(...) load — needs Miko decision on the exact identifier once http request class lands its final naming -->

From the developer's view, `promise()` is a blocking call that returns the HTTP response. Under the hood, the runtime may snapshot the entire process, free the host, dispatch the request through whatever HTTP infrastructure is available, and revive the process with the response value bound to `$response`.

Whether a particular call actually snapshots, or completes inline because the response is fast enough, is the runtime's decision — programs cannot distinguish between the two cases. That gives the runtime room to optimize (inline-fast, snapshot-slow) without changing program semantics.

---

## What happens under the hood

At the `promise()` call:

1. The runtime assigns the request a unique correlation ID.
2. The runtime serializes the entire process state — the Drinian hash: objects, references, call_stack, roles, srcs, roots, and any other top-level fields — tagged with the correlation ID. The snapshot includes everything needed to resume execution from the line after the `promise()` call.
3. The runtime hands `(correlation_id, request)` to an external dispatcher (a small daemon, a queue, or a network service — exact mechanism TBD per the host).
4. The Caspian host process exits. Memory is freed.
5. The dispatcher executes the HTTP request.
6. When the response arrives, the dispatcher locates the snapshot by correlation ID, revives it, and binds the response value as the return of `promise()`.
7. Execution continues from the line after the call as if nothing had happened.

No class-level hooks fire at snapshot or revive. The runtime serializes whatever's in Drinian; Drinian is everything. Anything that genuinely needs to live outside Drinian (an open TCP socket, a file descriptor) belongs to the host engine, not to user code — see [on_snapshot / on_revive class hooks](#on_snapshot--on_revive-class-hooks) below.

---

## Engine-granted permission

A Caspian program cannot make `promise()` calls unless the embedding engine has granted it permission. This matters because `promise()` involves the host process exiting — an engine that embeds Caspian inside a larger system needs to decide whether that's acceptable behavior. A web framework that runs Caspian per-request probably wants `promise()` allowed. A trigger-firing engine that expects every invocation to complete in milliseconds probably does not.

The mechanism for granting and revoking this permission is TBD. See [engine permission model](#engine-permission-model) below.

---

## Explicitly out of scope for V1

### A general `%utils.promise($anything)` primitive

V1 has no general "promise this arbitrary operation" entry point. The only thing that gets `promise()` is the HTTP request class. Other plausible primitives (`%fs.read_async`, `%db.query_async`, system-operation promises, etc.) are not in V1.

### Parallel / race / timeout combinators

No `promise_all([reqs])`, no `race([reqs])`, no `promise(req, timeout: 5.minutes)` in V1. The first version is one request, one wait, one response. Combinators are a natural V2 extension when real workloads ask for them.

### Cancellation

No external-cancel of an in-flight promise in V1. Once dispatched, the promise runs to completion or to whatever the underlying HTTP layer does on failure.

### Promise objects you can pass around

V1 `promise()` returns the resolved value directly, not a promise/future object. Promise-as-a-first-class-value (passing pending promises between functions, storing them in variables before awaiting) is a different design that would require changes to the language's evaluation model. Not in V1.

### `on_snapshot` / `on_revive` class hooks

No per-class hooks fire at snapshot or revive time **in V1**. The original aspiration was "never to need them" — Drinian is the single source of truth for runtime state, and external-resource management belongs in the engine, not in user code.

That position is softened by at least one concrete future use case: **redaction of sensitive fields before serialization.** If a snapshot is written to disk or over a network, sensitive fields (passwords, API tokens, session keys) would be exposed in the serialized form. The class needs a chance to sanitize itself before the snapshot is taken.

Sketch of the future API (NOT shipping in V1):

~~~caspian
class
	@username = null
	@password = null

	on_snapshot do($call)
		$call.receiver.@password = null    # redact; value lost forever
	end
end
~~~

`on_snapshot` fires for every reachable instance before the engine serializes Drinian. The handler can mutate `$call.receiver` to redact fields. The mutation is permanent — once `@password` is nulled, the original is gone from this snapshot. If the program continues running after the snapshot, it would need to re-acquire the password (re-prompt, re-fetch, etc.) to use it again.

Possible sugar for the common "just null out these fields" case:

~~~caspian
class
	redact_on_snapshot ['password', 'api_token']
end
~~~

Or a field-level annotation:

~~~caspian
class
	@password = null @redact
end
~~~

`on_revive` would be the companion hook firing after revival — useful for re-establishing redacted state from a secure source. Less urgent than `on_snapshot` (the program can do this lazily via normal code paths), but natural to design alongside.

Open design questions to resolve before implementing:

- **Order of `on_snapshot` calls** across reachable instances. Probably undefined like `on_close`, with the same "don't depend on order" rule.
- **What happens if `on_snapshot` itself raises?** Probably the same engine-level catch + `state.gc_errors`-style log + continue pattern. Same time/allocation/I/O constraints might apply. <!-- SPEC CONFLICT: archive cross-refs garbage-collection.md § Engine wraps the handler; no such doc in current requirements/ — GC spec needs writing -->
- **Mutation visibility to the live program.** If the program continues after the snapshot, do the redactions persist in the live Drinian hash? Probably yes — the redaction IS the mutation, and a program that snapshotted and continued would see the redacted state. (To preserve live state across a snapshot, the engine would need to copy-then-redact, doubling memory cost. Probably not worth it.)
- **Composition with non-redaction use cases.** If `on_snapshot` is the general "pre-serialize hook," other use cases might emerge (computed derivations, normalization, etc.). Worth scoping to "just redaction" for the initial implementation and resisting feature creep.

Until then, treat the absence of these hooks as deliberate for V1. **Programs that handle sensitive data should not snapshot in V1.** When the hooks land, revisit.

---

## Future possibilities

These are not commitments, just things worth noting as the V1 design rules in or rules out without saying so:

### Parallel-promise combinators

If real workloads need to fire N HTTP requests and wait for all/any of them, `promise_all([reqs])` and `race([reqs])` are the natural shape. The snapshot mechanism doesn't need to change — only the dispatcher's correlation-tracking does.

### Non-HTTP promise sources

Filesystem, database, message queue, system-process-completion, human approval — any operation that can be "fire and wait" is in principle a candidate. None known to be needed for V1. Each new source would need its own request class exposing `promise()`.

### Timeouts

The HTTP request class could grow a `timeout` parameter that bounds how long the wait can take before the promise raises a timeout exception. Same under-the-hood — just expires the correlation ID after a deadline.

### Snapshot-as-debugging-tool

The snapshot infrastructure built for Drinian is the same infrastructure needed for time-travel debugging. Once Drinian exists, "save the snapshot on uncaught error, let the developer revive locally" is a small layer on top.

### Debugger / inspector plugin interface

Caspian (or third-party libraries) could expose hook points into Drinian at well-defined moments — pre-dispatch, post-dispatch, frame push, frame pop, exception raise, on_close, etc. — letting an external library participate in the debugging story without being baked into the engine.

A plugin sees the Drinian hash at each hook, can read state, attach metadata (via the reserved `comment`/`misc` pass-through fields), and emit its own diagnostic output. Examples that fall out naturally:

- A profiler counting time per frame
- An invariant checker that asserts a property after every dispatch
- A logger that streams a structured trace of role transitions
- A `meta_src`-style provenance tracker that fills in source-location gaps for dynamically-generated code by observing creation sites
- A test-coverage instrumenter

This is well after V1.0 — needs Drinian to be stable, needs the hook interface to be designed (which hooks, what they can do, security model for what plugins can read or modify, what isolation looks like). Noted here so the V1.0 design doesn't preclude it.

---

## Open questions

### Engine permission model

How does the embedding engine grant a Caspian program permission to call `promise()`? Options sketched, none chosen:

- A capability passed at engine setup: `%engine.allow_promise(true)` or similar
- A role-based check: programs running in a certain role have it; others don't
- A method-missing-style runtime intercept: every `promise()` call asks the engine "is this allowed?"
- A static check at code load: program declares it uses promises; engine decides at load time

### Snapshot storage location

Where do snapshots live during the pause? Local disk on the host that wrote them? A shared object store? A network-accessible blob store so a different host can pick up the revive? Affects whether crash transparency works across host failures.

### Snapshot format versioning

A snapshot taken with Caspian V1.2 — can it be revived by Caspian V1.3? V2.0? If not, deployments mid-flight could leave un-revivable snapshots. Spec needs a compatibility rule.

### Snapshot TTL

A snapshot for a request whose response never arrives is a leak. How long does the runtime hold a snapshot before giving up? Per-request? Global default? On expiry, does the promise raise a timeout exception (requiring revive just to deliver the error) or just silently drop?

### Side effects during the pause

Between snapshot and revive, the outside world changes. Files get modified, database rows change, other Caspian processes mutate shared state. The revived program assumes its view of the world is current — it isn't. Same problem as restoring a backup. Worth a doc note; probably not solvable at the runtime level.

### Dispatcher implementation

The external dispatcher (the thing that holds the HTTP request and watches for the response) is its own component. Is it part of every Caspian engine? A sidecar daemon? A network service that engines talk to? Different choices have different operational costs.
