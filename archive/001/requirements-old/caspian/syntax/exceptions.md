# Exceptions

~~~vibecode
{"vibecode": {
	"doc": "exceptions",
	"role": "canonical_user_facing_spec_for_caspian_exception_handling_constructs_raise_and_catch",
	"constructs": ["raise", "catch"],
	"catch_form": "catch('uns/class') ... end (with optional $exception = prefix to bind the caught exception)",
	"raise_form": "raise 'uns/class' (with optional second arg for message)",
	"class_matching": "by_declared_inheritance_walk; catch_matches_named_class_or_any_subclass_declaring_it_as_parent; uns_naming_alone_does_not_imply_inheritance",
	"multi_exception_model": "stacked_on_call_stack_newer_unwinds_first_older_resumes_after",
	"engine_ignores_uncaught": "propagates_out_of_program_after_top_level_pops",
	"call_stack_representation_see": "drinian/examples/exception",
	"engine_wrapping_catches_see": "garbage-collection#on-close-catch-anything",
	"cross_role_semantics_see": "roles"
}}
~~~

Caspian's exception model uses two constructs — `raise` to throw and `catch` to handle — and represents in-flight exceptions as elements of the [Drinian](../drinian/) `call_stack`. This doc is the canonical user-facing spec for both constructs.

Exceptions are a general control-flow mechanism in Caspian, not just an error channel. Some exceptions report failure; others signal expected conditions that callers route around. The runtime treats them uniformly.

---

## `raise`

~~~vibecode
{"vibecode": {
	"section": "raise",
	"role": "construct_that_throws_an_exception_appending_an_exception_element_to_call_stack",
	"forms": ["raise 'uns/class'", "raise 'uns/class', 'message'"],
	"argument_kind": ["class_uns_string_required", "message_string_optional"],
	"effect": "appends_action_exception_element_to_call_stack_then_starts_unwind"
}}
~~~

Throws an exception. The argument is a URL string identifying the exception's class; an optional second argument supplies a human-readable message.

```caspian
raise 'puck.uno/error/runtime'
raise 'puck.uno/error/runtime', 'name cannot be empty'
raise 'foo.com/error/payment_declined', 'insufficient funds'
```

At the moment `raise` executes, the engine appends an element to the top of `call_stack` with `action: "exception"`, carrying the class, message, source location, and the role the raise happened in. See [drinian/examples/exception.md](../drinian/examples/exception) for the structural representation.

After the append, the engine begins **unwinding**: frames below the exception are popped one by one, with each one checked for a matching `catch` (see below). If a catch matches, control resumes inside the handler. If no catch ever matches, the exception leaves the program entirely.

---

## `catch`

~~~vibecode
{"vibecode": {
	"section": "catch",
	"role": "construct_that_handles_an_exception_whose_class_matches_the_argument",
	"forms": ["catch('uns/class') body end", "$caught = catch('uns/class') body end"],
	"binding": "with_assignment_caught_exception_object_becomes_the_value_otherwise_caught_silently",
	"matching_rule": "matches_named_class_or_any_subclass_that_declares_it_as_a_parent; inheritance_is_explicit_uns_naming_alone_does_not_imply_it",
	"body_execution": "runs_the_body; if_body_throws_a_matching_exception_catch_pops_the_exception_and_returns",
	"return_value_without_assignment": "the_bodys_normal_return_value_or_null_if_caught"
}}
~~~

Establishes a handler for exceptions matching the given class. The body runs normally; if execution inside the body (or any function it calls) raises a matching exception, the handler **catches** it and the catch construct returns.

```caspian
catch('puck.uno/error/runtime')
    $name = $names.first
    puts $name
end
```

The two forms:

- **`catch('class') body end`** — runs the body. If a matching exception fires, it's caught and discarded. The catch returns `null` in that case; otherwise the body's normal return value.
- **`$caught = catch('class') body end`** — same as above, but `$caught` binds to the caught exception object (if one fired) or `null` (if the body ran to completion without raising).

```caspian
$result = catch('puck.uno/error/runtime')
    risky_operation()
end

if $result.object.isa 'puck.uno/error/runtime'
    # an exception was caught; $result IS the exception
    puts $result.message
else
    # no exception; $result is whatever risky_operation() returned
    use_result($result)
end
```

A catch matches exceptions whose class is the argument **OR any subclass that explicitly declares it as a parent**. Catching by a base class is the standard pattern for handling a family of related exceptions.

```caspian
catch('puck.uno/error')
    # catches puck.uno/error AND any class that inherits from it,
    # including puck.uno/error/runtime, puck.uno/error/io, etc.
    risky_operation()
end
```

The walk is driven by **declared inheritance**, not by URL naming. Caspian's [URL does not imply inheritance](../../caspian/index.md) — the fact that `puck.uno/error/runtime` looks like a "sub-path" of `puck.uno/error` doesn't make it a subclass. The runtime class either declares `puck.uno/error` as a parent (then catch by parent matches) or doesn't (then it doesn't). Naming is convention; inheritance is explicit class declaration.

To catch every possible exception regardless of class, use the universal root: `catch('puck.uno/error')` (assuming the project follows the convention of rooting exception classes there). For finer-grained handling, catch the specific class or a narrower base.

---

## Multiple in-flight exceptions

~~~vibecode
{"vibecode": {
	"section": "multiple_in_flight_exceptions",
	"role": "design_for_the_case_when_a_handler_or_unwind_step_raises_while_another_exception_is_already_unwinding",
	"model": "stack_them_in_call_stack_newer_on_top",
	"catch_semantics": "catch_matches_topmost_exception_only_older_stays_pending",
	"resume_rule": "after_catch_handler_completes_normally_older_exception_resumes_unwind_from_current_state",
	"loud_at_exit": "uncaught_program_exit_reports_all_in_flight_exceptions_in_order",
	"no_silent_loss": "structurally_visible_in_call_stack_throughout"
}}
~~~

A `try`-style catch handler can itself raise. So can other code that runs during an exception's unwind (lifecycle hooks the engine doesn't already intercept). When that happens, **both exceptions live in `call_stack` at the same time** — newer on top of older, both with `action: "exception"`.

This is intentional. Exceptions aren't always errors; nesting them is legitimate. The runtime keeps both visible rather than silently dropping one.

**Catch semantics with multiple in-flight exceptions:**

1. A `catch` matches the **topmost** in-flight exception only. Older exceptions stay in the stack, unchanged.
2. When the catch handler completes normally, the topmost exception has been removed (caught). The next-older exception then **resumes unwinding** from the current point in the program — the catch handler doesn't shield the older exception from continuing.
3. If a handler wants to suppress the older exception too, it has to catch it explicitly (inspect `call_stack`, identify the older exception, catch its class in its own catch block).

**At program exit with uncaught exceptions:** the runtime reports **all** in-flight exceptions, in order from newest to oldest. Standard format:

```
Uncaught: puck.uno/error/io: tempfile cleanup failed: permission denied
    at /home/miko/script.casp:25
During handling of: puck.uno/error/runtime: name cannot be empty
    at /home/miko/script.casp:3
    ...
```

The "During handling of:" header makes the nesting explicit so the developer sees both exceptions and the order they fired in.

**No upper limit on stack depth.** If a program legitimately nests many exceptions, the runtime tracks them all. The reporting at exit shows everything. Per Caspian's no-nanny-code stance, the runtime doesn't impose a paternalistic limit; a runaway-exception loop reports loudly when the program exits.

**The engine-level `on_close` catch is separate.** Per [garbage-collection.md § Engine wraps the handler](../garbage-collection#on-close-catch-anything), every `on_close` hook runs inside an engine-level try/catch that prevents on_close-raised exceptions from escaping into the user's exception stream. Those go into `state.gc_errors` instead. So the most common case where "two user exceptions could stack" — an `on_close` hook raising during an unwind — doesn't actually happen at the user level; the engine catches the on_close exception first.

Other cases that can produce multiple in-flight user exceptions:

- A `catch` handler's body itself raises.
- A `defer`-style cleanup mechanism (if Caspian adds one post-V1) raising during unwind.
- A lifecycle hook the engine doesn't already intercept raising during unwind.

In all of these, the stacked-exceptions model handles things uniformly: both exceptions are visible, catch sees the topmost, older resumes after.

---

## Cross-role catch

~~~vibecode
{"vibecode": {
	"section": "cross_role_catch",
	"role": "how_catch_interacts_with_role_boundaries_when_an_exception_crosses_a_cross_role_call",
	"rule": "catch_runs_in_the_role_of_the_frame_that_owns_the_catch_block_not_the_role_that_raised",
	"unwinding_passes_through_role_boundaries_transparently": true,
	"see_also": "roles"
}}
~~~

An exception raised in role A can propagate through frames running as role B and be caught in a frame back in role A (or any other role). Unwinding passes through role boundaries transparently — the exception doesn't get blocked or transformed at a cross-role call site.

The catch handler runs in the role of the frame that owns the catch block, not the role the exception was raised in. The exception object itself records `raised_in_role` so the handler can see where it originated.

See [roles.md](../roles) for the broader role model.

---

## CaspianJ representation

The CaspianJ IR for `catch` and `raise` is documented in [caspianj.md § Exception Handling](../caspianj#exception-handling). User code authors write the Caspian source forms above; the transpiler produces the IR.

---

## See also

- [drinian/examples/exception.md](../drinian/examples/exception) — concrete Drinian snapshot showing what an in-flight exception looks like in `call_stack`.
- [garbage-collection.md § Errors during on_close](../garbage-collection#on-close-errors) — how engine-caught on_close exceptions route to `state.gc_errors` rather than the user's exception stream.
- [roles.md](../roles) — cross-role semantics, including how unwinding crosses role boundaries.
- [caspianj.md § Exception Handling](../caspianj#exception-handling) — IR encoding.
- [built-in-classes/nulls.md § Null flavors](../built-in-classes/nulls#null-flavors) — alternative to exceptions for the "expected-condition" use case; flavored nulls let callers branch without try/catch noise.
