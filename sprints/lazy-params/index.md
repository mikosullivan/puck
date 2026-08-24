~~~vibecode
{"doc": "sprint-index", "sprint": "lazy-params",
	"role": "Function parameters can be marked lazy. Eager parameters wear the `$` sigil (standard); lazy parameters wear `&`. A lazy parameter receives the unevaluated caller-supplied expression rather than its computed value; the callee triggers evaluation by calling `.call` on the parameter. Enables user-defined short-circuit operators, control flow, and macro-like functions without walker special cases.",
	"status": "brainstorm — seed concept captured"}
~~~

# lazy-params

Function parameters can be marked lazy. Eager parameters wear the `$` sigil; lazy parameters wear `&`. When a call passes an argument in a lazy position, the caller's expression is NOT evaluated before the call fires — the callee receives the unevaluated expression and triggers its evaluation on demand.

## Syntax

Declare a lazy parameter by using `&` where you'd normally write `$`:

~~~caspian
function($eager, &lazy)
	return &lazy.call
end
~~~

`$eager` is a regular parameter (evaluated before the call). `&lazy` is a lazy parameter (deferred until the callee triggers it).

## Invocation

Trigger the lazy parameter's evaluation by calling `.call`:

~~~caspian
&lazy.call
~~~

The caller-supplied expression runs in its original scope; the value returns to the callee.

## What this unlocks

- **User-defined short-circuit operators.** `or($a, &b)` — return `$a` if truthy, else `&b.call`. `||` becomes ordinary Caspian.
- **User-defined control flow.** `if($cond, &then, &else)` — dispatch based on `$cond`. `while`, `unless`, guards all fall out.
- **General deferred / macro-like functions.** Anything that wants to inspect an expression before deciding whether to run it.

## Relationship to the expressions sprint

The [expressions sprint](https://puck.uno/sprints/expressions/) needs a mechanism for lazy args so `||` and `&&` can short-circuit without walker special-casing. This sprint's `&` sigil is the language-surface for that mechanism. The two sprints share the underlying runtime — the expressions sprint's walker's `ready` predicate consults the callee's parameter signature to decide which arg slots must be populated before the call can fire.
