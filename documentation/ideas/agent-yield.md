# Agent yield

*Hand control of a running Caspian process over to an AI agent at an explicit point in the code. The agent inspects state, decides what to do, optionally acts, and returns control with a value.*

~~~vibecode
{"vibecode": {
	"doc": "idea_agent_yield",
	"role": "design sketch for a Caspian construct that pauses execution at an explicit call site and hands the running process to an AI agent for one decision or action before resuming",
	"status": "idea_design_sketched_not_yet_promoted_to_requirements",
	"basic_form": "$agent.yield",
	"concept": "in_process_handoff_not_inter_process_messaging",
	"distinct_from": ["puckai_worldlet_exchange_between_agents", "static_codegen_at_edit_time", "callout_to_oracle_service"],
	"related": ["requirements/ecoverse/puckai/ (worldlet format for inter-agent collaboration)",
		"ideas/puckai/skills/ (skill definitions)",
		"requirements/drinian/ (process introspection state the agent could read)"]
}}
~~~

## The idea

At any point in a running Caspian process, the program can pause and hand control to an AI agent. The agent receives the running scope (variables, call stack, source position, whatever the engine exposes), decides what to do, optionally takes action, and returns control to the program with a value.

```
$result = $agent.yield
```

The line above asks "agent, take over here — when you're done, give me back a value." The agent does whatever it does — reads the surrounding code, examines local variables, calls methods, makes Puck lookups, writes new code, queries an LLM internally, anything. When it returns, execution continues on the next line.

## Protocol

~~~vibecode
{"vibecode": {
	"section": "protocol",
	"transport": "acp",
	"connection_kind": "session_persists_until_outer_function_returns",
	"caller_blocks_during_session": true,
	"role_default": "agents_own_role_set_up_per_agent_no_yield_specific_sandbox_concept",
	"role_optional": "callers_permissions_extended_to_agents_role_via_role_delegate_to_block",
	"initial_handshake_payload": "worldlet_describing_process_state_contents_tbd",
	"caller_passes": "keyword_args_at_the_yield_site",
	"agent_returns": "caspian_function_in_caspj_first_param_is_agent_object_remaining_params_match_caller_kwargs",
	"recursion": "function_can_yield_back_for_more_code_within_same_session",
	"key_design_move": "function_as_payload_not_command_vocabulary"
}}
~~~

Under the hood, `$agent.yield` opens an [ACP](https://puck.uno/documentation/requirements/packages/acp/) connection to an agent. The connection is a session that lives for the duration of the yield call — possibly through several round-trips — and closes when the agent's outermost function returns. The caller's Caspian process blocks while the session is open.

### Connection setup and role

The agent object is owned by its own role — the same way every object in Caspian has an owning role. When yield is called, the function the agent returns runs in that role: the agent's role.

This isn't a yield-specific "sandboxed default" the protocol invents. It's just the standard Caspian role model. The agent's role's envelope (what it can read, what it can call, what capabilities it has) is set up by whoever configured the agent, the same way any role is configured. Different agents have different roles with different envelopes. The yield protocol just runs the agent's returned function as the agent's role, like any other cross-role call in Caspian.

The opt-in for wider access uses [`%role.delegate_to`](https://puck.uno/documentation/requirements/roles#role-delegate_to) — covered in [Delegating to the agent's role](#delegating-to-the-agents-role) below.

### Initial handshake

The client opens the connection by sending a worldlet containing the **skills** the agent needs to operate in this context — skills can be embedded inline or linked by URL, following the existing [Puckai skills design](https://puck.uno/documentation/ideas/puckai/skills/). Two categories of skill are typically present:

- **Protocol skills** — how the agent should respond, the function-as-payload model, how recursive callbacks work. Everything the agent needs to participate in the agent-yield protocol correctly. Usually linked (the agent can cache them across yield sites).
- **Task skills** — knowledge specific to what this yield is asking. The developer chooses what to attach based on the task at hand.

The worldlet ships skills, not raw process state. The agent doesn't automatically see locals, the call stack, or surrounding source — the developer explicitly passes data via keyword params (covered below) and grants relevant context via the attached skills. The privacy/utility tradeoff lives in the developer's hands at each call site, not in an engine-wide default.

The caller also passes **keyword params** at the yield site, and those params flow to the agent's function:

```
$result = $agent.yield(db: 'whatever', dir: $dirjail)
```

The developer at the yield site already knows roughly what the agent is being asked to do, and picks params accordingly. The caller is the contract author for what flows in — no magic capture of the surrounding scope.

### The agent's response

The agent replies with a Caspian function in [CaspJ](https://puck.uno/documentation/requirements/caspianj) form, whose parameter signature is **the agent itself as the first param, followed by the kwargs the caller supplied**. For the call above (`$agent.yield(db: $db, dir: $dirjail)`):

```
function agent:, db:, dir: do
    # agent-authored body — $agent is the agent object;
    # $agent.send(...) and $agent.yield(...) work for callbacks
end
```

The engine invokes that function in the agent's role, binding the agent object to `agent` and the caller-supplied values to their named params. Standard Caspian function-call semantics.

The agent-as-first-param convention is **protocol-internal**: this function is a private contract between agent and engine, never seen by user code, so the engine can rely on the fixed shape without worrying about name collisions with developer kwargs. The agent knows to emit this shape; the engine knows to bind itself to the first slot.

### Why function-as-payload

Most agent protocols define a vocabulary of commands ("now read X", "now call Y"). This protocol sidesteps that: the agent sends executable code, the client runs it. The function IS the command vocabulary. The engine already executes CaspJ — no new serialization, no new command grammar, no new dispatch mechanism. The agent just produces what the engine already knows how to run.

### Recursive callbacks

The agent's function can itself yield back to the agent — for more code, for a follow-up decision, for additional resources. Each callback is another round-trip over the same session. The session persists until the outermost function returns.

### Termination

When the outer function returns, the session closes. Its return value becomes the value of the original `$agent.yield` call in the caller's program, and execution continues on the next statement.

If the agent's function raises, the error propagates back through `$agent.yield` to the caller — same as any other Caspian call.

The same model covers protocol-level failures — network unreachable, timeout, rate-limited, agent refuses to produce a function, invalid CaspJ in the response, runtime cap exceeded. Anything that prevents the yield from completing normally raises an alarm. The caller catches it if they want to handle a specific failure mode.

## Delegating to the agent's role

By default the agent's code runs in the fresh sandboxed role created for the connection. The opt-in for wider access uses the [`%role.delegate_to`](https://puck.uno/documentation/requirements/roles#role-delegate_to) primitive: a block-scoped grant that temporarily extends the **caller's** permissions to the agent's role.

```
%role.delegate_to($agent.object.role) do
    $agent.yield db: $db, foo: $bar
end
```

Inside the `delegate_to` block, the agent's role gets every permission the caller's current role has. When the block exits, the grant lifts cleanly. The agent's role identity itself doesn't change — only its permissions are temporarily extended. Audit trails continue to attribute actions to the agent's role; the elevation is visible in source as the enclosing `delegate_to` block. (Full mechanism in the [roles spec](https://puck.uno/documentation/requirements/roles#role-delegate_to).)

What the agent can then do depends on the caller's role. If the caller is in user role, for example:

- Load libraries via `%puck`.
- **Build** new libraries — write code that becomes a callable Caspian module for the rest of the run (and possibly persisted via the engine's library cache, depending on how that lands).
- Redefine classes and functions in scope.
- Make Puck calls, mutate state, anything else the caller's role permits.

This opens **self-building program** territory: a small seed program states intent (a few specs, then a yield inside a `delegate_to` block), the agent constructs the rest at runtime. Live program shaping with the agent as the typist.

The trust surface is much wider in this mode. The whole arrangement rests on the developer's choice of which agent to delegate to. That's a deliberate ["no nanny code"](https://puck.uno/documentation/overview#no-nanny-code) stance — the framework allows it; the developer owns the consequences. The override is visible: it's literally a `%role.delegate_to` block in the source, not a hidden default.

Two operational properties to be honest about when delegating to the agent:

- **Reproducibility shifts.** Two runs of the same self-building program may produce different programs. Same input, different code path. That's both the feature (adaptive) and the burden (harder to debug, test, audit). Not a drop-in replacement for hand-written code — a different category.
- **Cost.** Each yield is a network round-trip to an LLM. A self-building program may make many. Cost scales with how much of the program gets built at runtime.

## What makes this different

- **From a Puckai worldlet exchange:** Puckai moves a structured object between agents over ACP. `$agent.yield` is in-process — same engine, same scope, same memory. No serialization, no network hop. The agent is operating inside the live program.
- **From edit-time AI:** an IDE plugin that completes code is acting on source text before it runs. `$agent.yield` is runtime — the agent sees actual values, actual state, actual execution context. It can make decisions a static tool can't.
- **From a one-shot LLM call:** calling out to an LLM API to "ask a question" is a value lookup. `$agent.yield` is a control transfer — the agent gets the keyboard, not just a return value channel.

## What it looks like

The basic call has no arguments:

```
$result = $agent.yield
```

This bare form is unlikely to do anything useful in practice — with no caller-supplied context, the agent has nothing specific to act on.

A more typical call passes in objects that the agent's function will need. The developer is the contract author for what flows in — the agent can't reach into the caller's scope on its own:

```
$strategy = $agent.yield err: $err
```

The agent receives those kwargs (names and values) in the initial handshake along with the worldlet, then replies with a Caspian function whose parameter signature matches:

```
function agent:, err: do
    # body the agent writes — examines err, returns some value
    # $agent is available for callbacks if the body needs to .send or re-yield
end
```

The engine invokes that function in the connection's role, binding `$err` to the `err` param. Whatever the function returns becomes the value of `$strategy`.

Three responsibilities, cleanly separated: the **developer** decides what the agent sees by choosing which kwargs to pass; the **agent** writes the function body based on the worldlet + kwargs; the **engine** glues them together.

The agent's function can only see its declared parameters. That's the language's general rule for `function` — functions are closed; they can't reach into the caller's scope. See [Functions](https://puck.uno/documentation/requirements/functions) for the full spec. It's why the developer's choice of kwargs is the *whole* contract: anything not passed in as a param is invisible to the agent's code.

## Why this might matter

- **Decision points where AI judgment beats hardcoded heuristics.** A retry policy, a fuzzy match, a content-moderation call, a "which library version is most likely safe to bump" question — anywhere the right answer depends on context too thick to encode as a flowchart.
- **Live debugging.** Pause execution in a misbehaving state and hand the keyboard to an agent that can examine the state and propose a fix or a workaround. Sort of an `irb` / `pdb` analog, but with the agent doing the typing.
- **AI-completed routines.** A function with `$agent.yield` standing in for a body section the developer hasn't written yet — the agent fills in at runtime based on what the surrounding context implies. Effectively making "TODO" callable.
- **Self-modifying behavior.** The agent could rewrite a routine in place if the engine allows. The trust model has to be there, but the capability is interesting.
- **Runtime security auditing.** Covered in depth below — strong enough use case to deserve its own section.

## Security testing

~~~vibecode
{"vibecode": {
	"section": "security_testing_use_case",
	"kind": "high_value_use_case",
	"core_capability": "live_process_introspection_by_ai_agent",
	"advantage_over_static_analysis": "agent_sees_actual_values_data_flow_role_assignments_not_just_source",
	"advantage_over_signature_scanning": "ai_judgment_catches_logic_errors_that_dont_pattern_match",
	"default_role": "sandboxed_read_only_inspection_only",
	"elevation_needed_only_if": "agent_attempts_active_probing_of_attack_paths",
	"slots_into": ["test_suites", "ci_security_gates", "runtime_monitoring", "post_mortem_replay"]
}}
~~~

Agent-yield is an unusually strong fit for **runtime security auditing**. An audit agent yielded into the live process sees what static analysis can't: actual values, actual data flow, actual role assignments, actual permission state — at a real point during execution.

### What the agent can examine

Via the worldlet handshake (and the agent's ability to call back for more):

- **The full call stack** (potentially all of [Drinian](https://puck.uno/documentation/requirements/drinian/)) — every frame, every owning role, every local variable, every cross-role transition.
- **The owning role of every reachable object** — lets the agent reason about which role boundaries were actually crossed and which weren't.
- **The faucet provenance of every value** — where each piece of data entered the process. Taint tracking at the language level, not at the type level.
- **The dirjail and capability state** — what file paths, network endpoints, and other constrained surfaces are currently reachable from this scope.

### What that enables

Things static tools and signature scanners can't do equivalently:

- **Real taint tracking.** Static analysis can speculate about whether a user-supplied string *might* reach a SQL sink. The audit agent can answer "did this specific value, from this specific faucet, actually reach a sink in this run?" with certainty.
- **Role-boundary verification.** Static rules say "untrusted code shouldn't call privileged operations." The agent verifies "for this run, with these objects flowing through, did the role boundaries actually hold?"
- **Logic-error detection.** Authentication bypasses, role-elevation paths, missing checks — issues that don't pattern-match against signatures. An LLM-based audit agent reasoning about code + live state may catch what fuzz testing and signature scanners miss.
- **Adaptive probing.** The agent decides what to look at next based on what it sees. Spots a suspicious value? Traces where it came from, where it's going. Conditional drill-down, not a fixed checklist.

### Default role fits naturally

The audit agent's default sandboxed role is sufficient for inspection: it gets read-only access to introspection surfaces (`%role.current`, Drinian snapshots, the manifest, faucet provenance). No write permissions, no Puck calls, no faucet access — just looking.

If the agent wants to **actively probe** attack paths (try to do something a real attacker would, to confirm whether it would succeed), that requires explicit [`%role.delegate_to`](https://puck.uno/documentation/requirements/roles#role-delegate_to). The developer has to opt in deliberately — active probing IS a real action against the running process, and the framework makes that an intentional choice.

### Where it slots in

- **Test suites.** A `before_assertion` hook (or equivalent) that yields to an audit agent. Agent examines state, returns findings; test fails on flagged findings.
- **CI security gates.** Run the program against a representative scenario; yield to an audit agent at the end; fail the build on findings.
- **Runtime monitoring.** Periodic yields during a long-running process; audit agent watches for drift in role/permission state.
- **Post-mortem replay.** Replay a crash trace with a yielded audit agent active in the suspect frame.

This is one of the strongest forcing functions for getting agent-yield's design right. Security auditing benefits enormously from "AI judgment on real runtime state" in a way that static analysis simply can't match — and the role model gives it the trust envelope it needs to be safe by default.

## Open questions

- **What is `$agent`?** Implicit globally-available object? Explicit, configured at engine startup (`%engine.agent = ...`)? Created on demand from a URL? Multiple agents named per program?
- **Trust envelope.** An agent yielded into the live process can in principle do anything the process can do — read state, write state, call out, mutate the codebase. Some Puckai-style `recruits` allowlist probably has to apply. What's the minimum-friction default that's still safe?
- **What does the agent see?** ~~Resolved~~: the agent sees the kwargs explicitly passed at the yield site plus the skills attached to the handshake worldlet. Raw process state (locals, call stack, surrounding source) is not automatic — it has to be explicitly handed in. See [Initial handshake](#initial-handshake).
- **How does the agent act?** Does it execute Caspian code via the engine? Construct a CaspianJ tree and have the engine eval it? Modify the program text on disk? Some combination?
- **Determinism story.** ~~Resolved~~: no special case. The step counter just counts — the yield itself is one step (one eval/exec_stmt call), and the agent's returned function adds steps as it runs in the caller's process, exactly like any other Caspian code. The deterministic-step-count property degrades to 'code without yield is deterministic'; code with yield isn't, which is the obvious reality and not a property to defend. AI operations are non-deterministic by nature.
- **Testability.** Code paths through `$agent.yield` are hard to unit-test. Agents-are-objects makes the basic shape clear (swap a real agent for a stub), but the mock-system conventions aren't designed — we expect them to emerge as we write tests for AI-using features. Placeholder thinking captured in [ideas/ai-testing.md](https://puck.uno/documentation/ideas/ai-testing).
- **Failure modes.** ~~Resolved~~: any failure raises an alarm — function-raises, network unreachable, timeout, rate-limited, refusal, invalid CaspJ, runtime cap exceeded. Same model across all cases. See [Termination](#termination).
- **Relationship to `$agent` as a recurring object.** ~~Resolved~~: state accumulates in the natural Caspian places, not in a new "session" concept the yield protocol invents. The agent service keeps whatever internal memory it wants (LLM conversation history, etc.); the caller's process holds whatever the agent's previous-yield function wrote into it (variables, mikobase records, files). Within a single yield, the ACP session is live for the duration. No special yield-protocol session mechanism is needed.
- **Sandbox boundary.** ~~Resolved~~: the engine ships only the handshake worldlet (skills + kwargs the developer chose). Nothing else flows out by default. The privacy question collapses into "what skills and kwargs did the developer attach?" — under the developer's direct control at each call site.

## See also

- [Puckai worldlet format](https://puck.uno/documentation/requirements/ecoverse/puckai/) — the persistent inter-agent record. `$agent.yield` is the in-process analog, not a replacement.
- [Puckai skills](https://puck.uno/documentation/ideas/puckai/skills/) — task-shaped instructions that a yielded agent could consult before acting.
- [Drinian](https://puck.uno/documentation/requirements/drinian/) — the process-state introspection format the agent would presumably read to understand the live context.
