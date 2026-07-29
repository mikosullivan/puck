# Assignment-aware methods

~~~vibecode
{"vibecode": {
	"doc": "idea_assignment_aware_methods",
	"role": "design notes on `=`-prefixed methods — a class can define `=foo` alongside `foo`, and the engine dispatches to `=foo` when the call is on the RHS of an assignment, injecting the LHS's receiver as the first parameter; symmetric with Ruby's `foo=` setter convention, mirrored to the left",
	"status": "design under discussion; may land in V1",
	"motivating_use_case": "branch handles / fork_sub where the method needs to write to $$foo eventually",
	"key_concepts": ["=prefix_on_definition_marks_receiver_aware",
		"call_site_unchanged",
		"two_separate_methods_no_nanny",
		"context_sensitive_dispatch_with_fallback",
		"no_assignment_context_skips_=name_lookup",
		"per_class_prepend_eq_flag_for_perf"]
}}
~~~

A class can opt into participating in its own assignment by defining a method whose name starts with `=`. When the engine sees `$foo = $obj.method(...)`, it first looks for `=method` on `$obj`'s class. If found, the engine calls it with a `$receiver` (wrapping `$$foo`) as the first parameter. If not, the engine falls back to the plain `method`.

## The shape

A receiver-aware method is defined with `=` as a name prefix:

~~~caspian
class
	method =branch($receiver, $opts)
		# this method is called when its return value is being assigned
		$receiver.set 1
	end
end
~~~

The call site is unchanged — `=` lives only on the definition:

~~~caspian
$foo = $obj.branch(...)           # engine looks for =branch first
$obj.branch(...)                  # engine looks only for branch
~~~

So readers of call sites can't tell whether a given method is receiver-aware. The information is in the class definition. Whether that's desirable trade-off (clean call sites, hidden dispatch) is part of what's under discussion.

## Dispatch rule

The engine's behavior depends on whether the call is in an assignment context:

| Call shape | Lookup order |
|------------|--------------|
| `$foo = $obj.method(args)` | `=method` first, then `method` |
| `$obj.method(args)` (expression statement, function arg, etc.) | `method` only — `=method` is invisible |

Three resulting patterns the class author can express:

1. **Receiver-aware only** — define `=method`, not `method`. Calls outside an assignment context fail (method-not-found).
2. **Plain only** — define `method`, not `=method`. Assignment calls fall back to it; the receiver mechanism is never engaged.
3. **Both** — define both. The engine picks based on context. The two bodies can do whatever; the language doesn't enforce a relationship.

## No nanny

`=foo` and `foo` are two separate methods. The class author writes them independently. The engine does not check that they do related things, return compatible types, or share logic.

This mirrors the existing `foo=` setter convention (Ruby-style, also adopted by Caspian): `$obj.foo = bar` calls a method literally named `foo=`, whose body can do anything — assign to a field, raise, ignore, or compute. The setter's behavior is the author's contract with their callers, not a language guarantee.

Same here, mirrored to the left. `=foo` is the author's contract with assignment-context callers. If `=foo` and `foo` drift apart in confusing ways, that's a code-quality problem, not a language failure.

## The motivating use case

The driving example is the branch / fork_sub pattern. A user wants to launch several functions in parallel, do other work, then wait for all of them to finish — and have the eventual results land in named variables:

~~~caspian
$mgr = %utils.forks.manager.new

$foo = $mgr.branch() do
	something()
end

$bar = $mgr.branch() do
	otherthing()
end

$mgr.wait

$foo   # 1, the eventual return value
$bar   # 2
~~~

For this to work, `$mgr.branch` needs to capture `$$foo` so it can write the eventual result there when the work completes. That's exactly what an assignment-aware `=branch` enables:

~~~caspian
class # fork_manager
	method =branch($receiver, $block)
		@queue.push({receiver: $receiver, block: $block})
		# don't call $receiver.set yet — wait will do it
	end
end
~~~

`=branch` registers the receiver with the manager and returns immediately. When `$mgr.wait` resolves the work, it calls `$receiver.set(actual_result)` for each branch.

## Performance

The dispatch rule means every assignment whose RHS is a method call could in principle require two lookups (`=method` then `method`). That sounds expensive — assignment of a method-call result is a hot path. Two cheap mitigations bring the cost close to zero:

### Per-class `prepend_eq` flag

Each class carries a single boolean — `prepend_eq` — that's true when the class currently has at least one `=`-prefixed method. The flag lives in the engine's host language (Lua in the reference implementation), not in Caspian — it's engine plumbing, not user-visible.

Default value is false. The engine maintains it on every method-table mutation:

- **Add a method.** If the name starts with `=`, set `prepend_eq` to true. (Unconditional set — no branch needed; it might already be true.)
- **Delete a method.** If the name started with `=`, scan the remaining methods for any other `=`-prefixed name. If found, leave `prepend_eq` alone. If none, set it to false.

The hot path (assignment dispatch) does a single boolean check. No integer comparison, no counter math. Add is O(1). Delete is O(n) in the method table size — but only when the deleted method was `=`-prefixed (most deletes won't be), and method-table mutations are rare compared to dispatches.

Caspian is dynamic — a class might have a `=`-method at one point and not at another. `prepend_eq` flips with the class's state and stays correct without any cache to invalidate at the flag level.

On an assignment-with-method-call, the engine checks `prepend_eq` first; if false, skip the `=name` lookup entirely and go straight to plain `name`. Most classes will never define a `=`-method, so the flag stays false, and the hot path stays single-lookup.

### Inheritance

The flag is per-class. The engine checks each class along the inheritance chain during dispatch; ancestors with `=`-methods are picked up the same way ancestors with regular methods are.

The alternative — making the flag aggregate "this class OR any ancestor has `=`-methods" — would slightly cheapen dispatch (one check instead of one-per-ancestor) but would require invalidating descendants when a parent's method table changes. For a dynamic language where hierarchies can shift, per-class with a chain walk is the safer default.

### Cost picture

| Assignment shape | `prepend_eq` on receiver class | Extra cost |
|------------------|-------------------------------|------------|
| `$foo = 1` | irrelevant | none |
| `$foo = $bar.baz(...)` | false | one bit check, then normal |
| `$foo = $bar.baz(...)` | true | bit check + one extra lookup for `=baz` |

The feature is only paid for by classes that actually use it, at the call sites that actually use them. Classes that ignore it pay one bit per definition.

## Open design points

- **What `=foo` writes to the LHS.** The convention so far is that `=foo` explicitly calls `$receiver.set(value)` to write. The method's own return value is unused in assignment context (assignment context already has the receiver as the write surface). Should the engine enforce this (discard the return value), or pass it through somehow?
- **Behavior when `=foo` exists but `foo` doesn't, and the call is outside an assignment context.** Method-not-found is the current rule. Engine could optionally improve the error message — "method `foo` exists but only as `=foo`; requires assignment context" — but that means looking up the `=foo` it skipped, which costs a tiny bit of what the flag was saving. Acceptable trade for better errors, or not?
- **Variable-object integration.** The receiver `=foo` gets is conceptually the same as the receiver passed to `=` operator classes. The user-visible API is `$$foo.set(value)` / `$$foo.value = value`. Whether the receiver IS the variable object or a thin wrapper around it is an implementation detail.
- **Deferred-write semantics.** The branch case wants `$foo` to be "unresolved" between the call and `wait`. What does reading `$foo` return in that state — a placeholder that raises, null, the last value? The dispatch mechanism doesn't answer this; it just enables the manager to hold the receiver and defer the write. The placeholder-state semantics are a separate decision.
- **Naming.** `=foo` as a method name reads cleanly in the definition but is unusual in identifier conventions. Is the `=` prefix the right marker, or should there be a keyword (`assigned_method foo`, `lhs_aware method foo`, etc.)? The prefix is terser and parallels `foo=` setters, but a keyword would be more self-explanatory.

## Status

Under discussion. Might land in V1 depending on how the open points settle. The branch / fork_sub use case is a real V1 candidate that could justify it.

## Related

- [ideas/multicast.md](multicast.md) — separate engine-dispatch idea (deferred from V1).
- [syntax/assignment-operators.md](../requirements/syntax/assignment-operators.md) — the receiver object that `=foo` would receive is the same shape used by `=` and compound assignment operators.
- [classes/index.md](../requirements/classes/index.md) — class definition spec where `=foo` methods would live.
