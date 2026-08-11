# Is Caspian Turing complete?

~~~vibecode
{"vibecode": {
	"doc": "turing-completeness",
	"role": "report on whether the Caspian language (as specified) is Turing complete; walks through each requirement and points at the spec features that satisfy it; notes the gap between the language spec and the current walking-skeleton engine",
	"status": "informational",
	"verdict": "yes_language_is_turing_complete_in_principle; current_engine_is_not_yet_because_conditionals_and_loops_have_not_landed_in_a_slice",
	"caveats": ["timeouts_enforced_at_engine_level_constrain_actual_halting_behavior",
		"capability_restricted_roles_can_be_deliberately_below_turing_complete"]
}}
~~~

Short answer: **yes, the Caspian language as designed is Turing complete.** Long answer below, with the caveat that the current walking-skeleton engine (Aslan through Edmund) does not yet implement enough of the language to be Turing complete in practice — that arrives once `if/elsif/else` and `while` (or recursive function calls) land in a slice.

## What "Turing complete" means here

~~~vibecode
{"vibecode": {
	"section": "definition",
	"working_definition": "able_to_simulate_an_arbitrary_turing_machine; equivalently_able_to_express_any_partial_recursive_function",
	"minimum_requirements": ["conditional_branching",
		"unbounded_iteration_or_recursion",
		"unbounded_state_storage"]
}}
~~~

The technical definition is "can simulate any Turing machine," but the practical test is shorter: a language is Turing complete if it has three things working together.

- **Conditional branching.** Some way to make a different choice based on a runtime value.
- **Unbounded iteration or recursion.** Some way to repeat work an arbitrary number of times. Either a loop construct with no fixed bound, or recursive function calls that the language doesn't artificially cap.
- **Unbounded state.** Some way to store an arbitrary amount of intermediate data — typically a heap, a stack, or both — without a hard ceiling on size.

Almost every general-purpose programming language has all three. Caspian is no exception.

## Caspian's three checkmarks

### Conditional branching

~~~vibecode
{"vibecode": {
	"section": "branching",
	"feature": "if_elsif_else",
	"spec_ref": "caspianj.md_control_flow_if_elsif_else"
}}
~~~

Caspian has `if`/`elsif`/`else`, documented in [caspianj.md § If / elsif / else](../requirements/caspianj.md#if-elsif-else). The same construct works as a statement and as an expression that returns a value. That is all that branching needs to satisfy this requirement.

Beyond `if`, the language also has `catch` and `heed` for exception-and-warning flow control. Those are not required for Turing completeness, but they exist and they branch.

### Unbounded iteration and recursion

~~~vibecode
{"vibecode": {
	"section": "iteration_and_recursion",
	"loop_construct": "while",
	"iteration_helper": "each_method_on_collections",
	"recursion": "functions_and_methods_can_call_themselves_no_depth_cap_imposed_by_the_language",
	"spec_ref": "caspianj.md_while_and_function_calls"
}}
~~~

Two ways in: loops and recursion. Caspian has both.

- **`while`.** A condition-driven loop, documented in [caspianj.md § While](../requirements/caspianj.md#while). The condition is re-evaluated each iteration; the loop runs until it goes falsy. The number of iterations is not bounded by the language.
- **`each`.** Collection iteration documented in [caspianj.md] and used throughout the standard examples. Less general than `while` (it has to terminate when the collection runs out) but useful and present.
- **Recursion.** Functions and methods can call themselves or each other. The dispatch model in [mvm.md](../requirements/cvm/index.md) imposes no fixed recursion depth — every call pushes a frame onto `engine.state.call_stack`, and the stack grows until something terminates the program (an exception, a `%timeout`, or running out of host process memory). That is exactly the unboundedness the requirement asks for.

`while` alone is enough; recursion is enough independently. Caspian has both, so this requirement is satisfied twice over.

### Unbounded state

~~~vibecode
{"vibecode": {
	"section": "state",
	"primary_carrier": "hashes_with_arbitrary_string_keys_and_value_types",
	"secondary_carriers": ["arrays", "instance_variables", "scope_locals"],
	"size_limit": "no_language_level_cap; bounded_only_by_host_memory"
}}
~~~

Caspian's hash class — [`puck.uno/hash`](../requirements/built-in-classes/index.md) — accepts any string key and any value, and is unbounded in the number of keys. That alone is enough: a single hash is sufficient state to implement a Turing machine's tape.

In addition, the language has:

- **Arrays.** Indexed sequences of arbitrary length.
- **Instance variables** (`@name`). Per-object mutable state.
- **Scope locals** (`$name`). Per-frame mutable state.
- **Nested data structures** — hashes of hashes, arrays of arrays, hashes of arrays of hashes, all the usual compositions.

None of these carry a language-level size cap. The only ceiling is the host process's memory.

### Putting them together

With branching, unbounded iteration (or recursion), and unbounded state, a language can simulate any Turing machine. Caspian has all three. The textbook argument is concrete: encode the tape as a hash from integer-string positions to symbol values, encode the head position and current state as locals, loop with `while` reading the current cell and dispatching the transition through `if/elsif/else`, write the new symbol back to the hash, update the head and state. Halting falls out naturally as the loop's exit condition.

A more idiomatic Caspian program for the same demonstration would use recursion rather than explicit looping, but the conclusion is the same.

## What the spec gives Caspian beyond the minimum

The bar for Turing completeness is low; calling a language "Turing complete" is a starting line, not a finishing line. Caspian has plenty above that line. None of these affect the Turing-complete result, but they affect what's *easy* to express:

- **Closures.** First-class anonymous functions that capture lexical scope. Lets functional patterns work without contortion.
- **Methods and classes.** Open dispatch, single inheritance for now, multi-inheritance schema-permitted but resolution-order-pending (see [the class-definitions spec](../requirements/ecoverse/worldlets/index.md#class-definitions)).
- **Exceptions and warnings.** Non-local control flow with `catch` (interrupts) and `heed` (accumulates).
- **Instance-level shadow classes.** Per-object method overrides without disturbing the class.
- **Rich primitives.** Strings, numbers, booleans, null, hashes, arrays — all with method surfaces.

These do not move the Turing-complete needle, but they shape what programs read like at the source level.

## Where the current engine sits

~~~vibecode
{"vibecode": {
	"section": "implementation_gap",
	"engine_slices_so_far": ["Aslan", "Bree", "Corin", "Digory", "Edmund"],
	"language_constructs_implemented": ["literal_evaluation_string_number_null_true_false_hash",
		"method_dispatch_with_method_missing",
		"bwc_dispatch_puts",
		"to_json_serialization",
		"sys_reference_for_argv",
		"role_transition_and_call_stack"],
	"missing_for_turing_completeness": ["if_elsif_else", "while_or_recursion"],
	"next_slice_addressing_this": "TBD; conditionals_and_loops_are_natural_post_Frank_targets"
}}
~~~

The walking-skeleton engine from Aslan through Edmund implements a real but narrow slice of the language. It can materialize literals, dispatch methods (including method_missing on hashes), call bwcs like `puts`, serialize to JSON, and read `%argv` — but it has no implementation yet for `if/elsif/else`, no `while`, and no user-defined functions that could recurse.

So a useful split:

- **Caspian-the-language** is Turing complete in principle. The spec describes all three ingredients.
- **Caspian-the-engine, as of Edmund**, is not — yet. Programs it can execute are bounded in branching and iteration, which means it cannot, today, simulate an arbitrary Turing machine.

This gap closes when the slice that introduces `if/elsif/else` and `while` (or recursive function calls) ships. Those are not difficult engine additions — they are well-understood constructs with established CaspianJ shapes — they simply have not been the next thing on the walking-skeleton priority list.

## Caveats worth naming

~~~vibecode
{"vibecode": {
	"section": "caveats",
	"items": ["engine_timeouts_constrain_actual_halting_behavior",
		"capability_restricted_roles_can_be_deliberately_below_turing_complete",
		"finite_memory_is_a_universal_caveat_not_caspian_specific"]
}}
~~~

A few things are worth being explicit about, since they sometimes confuse the conversation.

### Engine timeouts

Per [bootstrap.md § Timeouts](../requirements/bootstrap.md#timeouts), the engine enforces a wall-clock budget set by the host. A program that would otherwise run forever is killed by the timeout. This is a real constraint on what programs *complete* — but it does not make the language non-Turing-complete. Turing completeness is a property of what the language can *express*, not what the host chooses to allow to run.

### Capability-restricted roles can be deliberately below

A role with no access to anything mutable, no `while`, no recursion, no `%timeout` — say, an evaluator role that just resolves a small fixed expression and returns — is *deliberately* below Turing complete. That is a feature, not a bug; it gives the host a way to run untrusted snippets in a context where halting is guaranteed. The fact that Caspian-the-language is Turing complete does not force every Caspian *execution context* to be.

### Finite memory is universal

Every real-world machine has finite memory, so every real-world Turing-complete language is, strictly, only Turing complete in the limit. This is a universal caveat — it applies equally to Python, C, JavaScript, Lua, and anything else — and is not specific to Caspian.

## Conclusion

Caspian, as the spec describes it, is Turing complete. Conditional branching, unbounded iteration, unbounded recursion, and unbounded mutable state are all present. The current walking-skeleton engine does not yet implement all of those pieces, so today's *engine* is below the line — but the gap is clearly a roadmap item, not a design omission.
