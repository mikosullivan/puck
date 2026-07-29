# Role delegation mid-execution

~~~vibecode
{"vibecode": {
	"doc": "requirements_drinian_examples_role_delegation",
	"role": "worked Drinian snapshot: user is delegating to agent inside a %role.delegate_to block, the agent-authored function is running, and has called into an engine-role string method — showing that delegations live on the stack frame that established them, not on the roles registry",
	"status": "draft — frame-scoped delegations field on the delegate_to frame; role transitions user → agent → engine across the call stack"
}}
~~~

Drinian mid-execution at a moment when **user is delegating to agent**. The program entered a `%role.delegate_to($agent.object.role) do ... end` block, called `$agent.yield(...)`, the engine received the agent-authored function back, and is now invoking that function — which has itself made a string-method call on the connection-string passed in as a kwarg.

The Caspian source:

~~~caspian
$db = '[some database connection]'
$agent = %('agents.example.com/claude').new()

$result = %role.delegate_to($agent.object.role) do
	$agent.yield(prompt: 'find recent users', db: $db)
end
~~~

We're paused inside the agent's returned function, partway through a `$db.split(';')` call (the agent parsing the connection string). The Drinian hash:

~~~json
{
	"roles": {
		"user": {},
		"engine": {},
		"agent": {}
	},

	"call_stack": [
		{
			"comment": "Frame 0: the bootstrap frame — the program's outermost scope. $db was assigned on line 1 (a plain string), $agent was constructed on line 2. We're past line 4 — execution is inside the delegate_to block at this point, so this frame's src points at the line that initiated the block. The bootstrap frame has no `call` field; it wasn't invoked the way other frames were.",
			"action": "top_level",
			"role": "user",
			"src": ["a", 4],
			"locals": {
				"db": {"value": "[some database connection]", "src": ["a", 1]},
				"agent": {"ref": "obj_43"}
			}
		},
		{
			"comment": "Frame 1: the delegate_to block. The delegations field records that this frame grants the agent's role (obtained via $agent.object.role) the user role's permissions for the block's lifetime. The call field carries the call object — owned by user (the caller's role), accessible as %call from inside this frame.",
			"action": "delegate_to",
			"role": "user",
			"delegations": {"agent": {}},
			"src": ["a", 4],
			"locals": {},
			"call": {
				"role": "user",
				"dispatcher": "%role",
				"method": "delegate_to",
				"src": ["a", 4]
			}
		},
		{
			"comment": "Frame 2: the $agent.yield(...) call. The engine has already round-tripped to the agent over ACP, received the agent-authored function, and is now invoking it. Action is method_call from user's perspective; the actual function-invocation frame is Frame 3. The call's role is user — the caller — even though the dispatcher is the agent object.",
			"action": "method_call",
			"receiver_type": "agent",
			"method": "yield",
			"role": "user",
			"src": ["a", 5],
			"locals": {},
			"call": {
				"role": "user",
				"dispatcher": {"ref": "obj_43"},
				"method": "yield",
				"src": ["a", 5]
			}
		},
		{
			"comment": "Frame 3: the agent-authored function the engine is invoking. Cross-role into agent. Per the agent-yield protocol the function's first param is the agent object itself, followed by the kwargs the caller supplied (in the order they were given: prompt, then db). The agent's role has user's permissions because Frame 1's delegation is on the stack above this frame. The call's role is STILL user — the caller is user, even though the called code runs as agent.",
			"action": "function_invocation",
			"role": "agent",
			"src": null,
			"locals": {
				"agent": {"ref": "obj_43"},
				"prompt": {"value": "find recent users", "src": ["a", 5]},
				"db": {"value": "[some database connection]", "src": ["a", 1]}
			},
			"call": {
				"role": "user",
				"src": ["a", 5],
				"note": "Function-invocation entered via Frame 2's yield call. The call object stays owned by user (the original caller); the function code, running as agent, reads it via cross-role access."
			}
		},
		{
			"comment": "Frame 4: the agent's function called $db.split(';') to parse the connection string. Cross-role into engine, which owns string methods. Even though Frame 1 delegated user's permissions to agent, this frame is running AS engine — the engine walks the stack looking for delegations targeting engine, finds none (Frame 1 targets agent), and engine uses its own permissions. The call's role is agent because the agent's function (Frame 3) is the caller here.",
			"action": "method_call",
			"receiver_type": "string",
			"method": "split",
			"role": "engine",
			"src": null,
			"locals": {
				"separator": {"value": ";"}
			},
			"call": {
				"role": "agent",
				"dispatcher": {"value": "[some database connection]"},
				"method": "split",
				"src": null
			}
		}
	]
}
~~~

<!-- SPEC CONFLICT: archive uses "stdlib" as the role for the built-in string.split method_call; current spec has no stdlib role. Rewritten as "engine" throughout this file. Same conflict flagged elsewhere — needs one Miko decision that applies across all examples -->

<!-- SPEC CONFLICT: archive uses %puck['url'] for the agent construction; current spec uses %fetch(url) or %(url). Rewritten to %(...) -->

<!-- SPEC CONFLICT: this example relies on an "agent" role that isn't documented in current spec (roles/index.md lists V1 as user + engine + faucet roles, with request/agent identity roles explicitly deferred). The agent-yield protocol is referenced but the "agent" role's status is unclear — needs Miko decision on whether this example should demonstrate a faucet role instead, or whether the agent role is now in scope somewhere the roles index doesn't yet reflect -->

## What to notice

- **The `delegations` field sits on Frame 1.** That's the frame that established the delegation. Nothing outside that frame has any record of the grant; nothing inside the engine has to "remember" to lift it. When Frame 1 unwinds, the grant is gone.
- **Frame 3's role is `agent`, not `user`.** Identity is preserved per the [roles spec](https://puck.uno/requirements/roles/) — actions taken inside the agent's function are attributed to the agent, even though the agent has user's permissions for now. Auditing and ownership chains see the agent doing things; the elevation is visible in source as the enclosing `delegate_to` block (Frame 1).
- **Frame 4's role is `engine`, not `agent`.** The subtle security-relevant point: delegation extends the **named** role's permissions, not the call-chain's. The engine walks the stack looking for delegations whose target matches the role the checking code is running as. Frame 4 is running AS engine; the stack walk looks for delegations targeting engine, finds none (Frame 1 targets agent, not engine), and engine uses its own permissions. If `$db.split` ever called back into an agent-owned method, that new frame would be running AS agent again, and the same stack walk would find Frame 1's grant — the elevation would re-engage. The rule is per-role at each frame, not per-call-chain branch.
- **Stack-walking resolves permissions, not lookup tables.** When the engine needs to decide whether the current frame can do something, it walks the stack looking for delegations targeting the frame's role. Permission resolution and the call chain are the same data structure.
- **If an alarm raised inside Frame 4**, it would unwind up through Frame 3, then Frame 2, then Frame 1. As Frame 1 pops, the delegation is gone. Frame 0 catches it (or it propagates out), and at no point does any "lift delegation" handler need to fire — the stack unwinding IS the lifting.

If the same program had nested `delegate_to` blocks, additional `delegations`-bearing frames would stack up in the same way; permission resolution walks the stack and applies each in order; unwinding undoes each in reverse.

## See also

- [Roles spec](https://puck.uno/requirements/roles/) — the identity system that establishes the roles this example switches between.
- [Drinian § Role delegations](https://puck.uno/requirements/drinian/#role-delegations) — the conceptual explanation this example illustrates.
