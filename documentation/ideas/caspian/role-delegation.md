# Role delegation

*A mechanism for one role to grant — or pass through — some of its permissions to code running under a different role. Driven by the [`$agent.yield`](../agent-yield.md) need but kept general so the mechanism isn't agent-specific.*

~~~json
{"vibecode": {
	"doc": "idea_role_delegation",
	"role": "design exploration for letting one Caspian role delegate or pass through permissions to code running in another role; scoped narrowly to support agent-yield without overdesigning the broader roles system",
	"status": "idea_scope_set_design_open",
	"forcing_function": "agent_yield_run_as_self_block_needs_a_way_for_caller_role_to_apply_to_agent_code",
	"design_principle": "narrow_not_agent_specific",
	"related": ["requirements/caspian/roles.md (settled roles spec)",
		"ideas/agent-yield.md (the forcing function)"]
}}
~~~

## What we want to accomplish

Two design principles, both equally load-bearing:

1. **Don't make a special case for `$agent.yield`.** The mechanism we add should be general — a property of the roles system, not a feature bolted onto the agent yield protocol. If two unrelated features ever need the same delegation behavior, they should use the same mechanism.
2. **Don't overdesign the roles system.** Add as narrow a concept as we can. The bar is "just enough to make `$agent.yield`'s `as_self` mode work." Speculative future delegation patterns can wait until they have their own forcing functions.

So the target is a single, general, minimum-viable delegation primitive. Not a delegation framework. Just the smallest thing that lets the `as_self` block in [`$agent.yield`](../agent-yield.md) cleanly inherit the caller's role for the agent's code.

## The forcing case

From the agent-yield protocol:

```
$agent.as_self do
    $agent.yield db: $db, foo: $bar
end
```

Inside the `as_self` block, the agent's returned function should execute under the caller's current role rather than under a freshly-created sandboxed role. That's the entire feature we need from delegation right now.

The block-level wrapping is intentional: the developer is marking a region where they're deliberately letting outside code run with their own privileges. It's a visible gesture, not an invisible default.

## Sketches

*(To be filled in.)*

## See also

- [`$agent.yield`](../agent-yield.md) — the forcing function for this idea.
- [Caspian roles spec](https://puck.uno/documentation/requirements/caspian/roles) — the settled roles system this would extend.
