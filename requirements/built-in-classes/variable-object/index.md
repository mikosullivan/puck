# Variable object

<span class="tag">variable-object</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_built_in_variable_object",
	"role": "spec for the variable-object class — first-class objects representing the storage slot of a variable, distinct from the value the slot holds. Accessed via the double-dollar sigil `$$name`. Enables pass-by-reference: a function can take a variable-object as an argument and mutate the caller's variable in place. Reassigning the slot itself (`$$foo = ...`) raises — the varobj IS the slot; you can't replace the slot with a different slot. Bump operators (`++` / `--`) desugar to function calls on variable-objects; developers can write their own similar mutators (swap / clamp / etc.). Transpiler atom shape: `{varobj: NAME}`, parallel to `{var: NAME}` for the value form.",
	"status": "draft — the `$$name` syntax and reassign-raises rule are settled and implemented in the transpiler; the full method surface is still being spec'd; the class-name choice is open",
	"audience": "developers writing functions that mutate their caller's variables in place (increment / decrement / swap / clamp / etc.); engine implementers wiring the varobj class"
}}
~~~

A **variable object** (varobj) is a first-class object representing the storage slot of a variable. Every variable in Caspian has a corresponding variable-object; accessing it via `$$name` gives you a reference to the slot itself, distinct from `$name` which reads the value the slot currently holds.

~~~caspian
$foo = 1
$foo # 1 — the value in the slot
$$foo # the variable-object — a reference to the slot itself
~~~

**Why this matters.** Variable-objects enable **pass-by-reference**: a function can take a variable-object as an argument and mutate the caller's variable in place. This is the primitive that bumps (`++` and `--`) desugar to, and the same primitive is available for any user code that wants "modify this variable for me" semantics — no separate mechanism required.

## Syntax

- **`$$name`** — the variable-object of `name`. Distinct from `$name`, which reads the value.
- **`$$name = <expr>`** — **raises.** The variable-object IS the slot; there's no "replace the slot with a different variable-object" semantics. To reassign the value the slot holds, use `$name = <expr>` (or equivalently `$$name.value = <expr>` — see [method surface](#method-surface)).

## The value method

The core method — read or write the current value the slot holds.

~~~caspian
$foo = 1
$$foo.value # 1 — same as $foo
$$foo.value = 42
$foo # 42
~~~

Reading `$$foo.value` returns the current value; assigning to it mutates the slot. Same effect as `$foo` (read) and `$foo = ...` (write), just going through the variable-object.

## Method surface

Guaranteed methods:

- **`.value`** → read the current value the slot holds.
- **`.value= <new>`** → write a new value into the slot.
- **`.freeze`** → freeze the slot. After freezing, any attempt to assign a new value raises. See [Freezing](#freezing).
- **`.frozen?`** → predicate: returns `true` if `.freeze` has been called on this slot, `false` otherwise.

### Deferred beyond V1

Several obvious-sounding methods don't fit V1 and are deferred:

- **`.defined?`** — chicken-and-egg. Accessing `$$foo` requires the slot to exist; if `foo` isn't defined, `$$foo` itself raises before `.defined?` could run. Useful only with a "detached varobj" concept (returned for undefined names) that adds complexity. Revisit post-V1.
- **`.name`** — the variable-object doesn't carry a back-reference to its own name. Names live in the [scope runtime](https://puck.uno/requirements/lua/scope) as the key mapping to the varobj; the varobj itself is a lean object holding just the value and the `frozen` flag. Adding a name field is a per-varobj memory cost that's not clearly worth it for V1. Revisit post-V1.
- **`.delete`** — makes the variable undefined again (Ruby's `remove_instance_variable` shape). Rarely useful in practice — variable-slot lifecycles are usually scope-based, not explicitly managed; when you want a variable "gone," you either let its scope end or reassign it. Deferring both simplifies V1 and avoids designing the `.freeze` × `.delete` interaction prematurely. Revisit post-V1.

## Freezing

Once a variable is frozen, no further assignment is permitted — through either the plain-value sigil or the variable-object.

~~~caspian
$foo = 1
$foo # 1
$$foo # variable object

$$foo.value # 1
$$foo.value = 2
$foo # 2

$$foo.freeze          # cannot assign to $foo again

$foo = 3              # raises
$$foo.value = 3       # raises
~~~

Freezing is a one-way operation on the slot — there's no `.thaw`. If a slot needs mutability after freezing, use a different slot.

**Idempotent.** Calling `.freeze` on an already-frozen slot is a no-op. Same rule applies to every freeze method in Caspian — see [object/methods § freeze surface](https://puck.uno/requirements/built-in-classes/object/methods#freeze_bucket--freeze_stack--freeze) and [Hash § Freezing (whole-hash)](https://puck.uno/requirements/built-in-classes/primitives/hash#freezing-whole-hash).

**Freezing is how Caspian makes constants.** There is no separate `const` or `final` keyword — just assign the value, then freeze the slot. Any subsequent assignment attempt raises.

~~~caspian
$PI = 3.14159
$$PI.freeze           # $PI is now a constant

$PI = 3               # raises
~~~

Design win: one mechanism (variable-object freezing) covers both "make this variable read-only from now on" and "declare a constant" — no new grammar, no separate rule set. It also composes with "constant after some setup" naturally: initialize freely, freeze once the value is settled.

## Pass-by-reference

Functions can accept variable-objects and mutate the caller's variables in place. The `$$foo` syntax at the CALL site passes the variable-object; the function receives it and can call `.value` / `.value=` on it to read and write the underlying slot.

**Declaring a varobj parameter uses the ordinary typed-parameter surface** — no new syntax. The parameter's class annotation is `%(core:variable)`:

~~~caspian
$swap = function($a: {class: %(core:variable)}, $b: {class: %(core:variable)})
	$temp = $a.value
	$a.value = $b.value
	$b.value = $temp
end

$x = 1
$y = 2
&swap $$x, $$y
$x # 2
$y # 1
~~~

The `{class: %(core:variable)}` annotation enforces "caller must pass a variable-object" at the call boundary — passing a plain value (`&swap $x, $y`) raises the standard typed-param mismatch error, fail-loud at the boundary.

Design win: variable-objects are just another class in Caspian, not a special language construct. Any function that takes a varobj uses the standard typed-parameter surface — the same mechanism user-written mutators like `&clamp($$x, 0, 10)` or `&multiply_by($$x, 3)` use.

## Bump operators

The `++` and `--` operators are the ONLY Caspian-source way to bump a variable. They desugar in CaspM to direct dispatches on four **CaspM-only** bwcs (`suffix_increment`, `prefix_increment`, `suffix_decrement`, `prefix_decrement`) — those bwcs are not directly callable from Caspian source. See [caspianj § Bumps](https://puck.uno/requirements/caspianj#bumps) for the full desugaring.

| Source | CaspM bwc | Sets | Returns |
|---|---|---|---|
| `$foo++` | `suffix_increment` | new value | OLD value (before increment) |
| `++$foo` | `prefix_increment` | new value | NEW value (after increment) |
| `$foo--` | `suffix_decrement` | new value | OLD value (before decrement) |
| `--$foo` | `prefix_decrement` | new value | NEW value (after decrement) |

Mnemonic: **prefix does it first, suffix does it after.** Same convention as C, C++, Java, JavaScript.

**User-written mutators use the typed-parameter surface.** Developers wanting their own similar operations (`&clamp($$x, 0, 10)`, `&swap($$a, $$b)`, `&multiply_by($$x, 3)`) write ordinary functions with a `{class: %(core:variable)}` param annotation — the same mechanism spec'd in [§ Pass-by-reference](#pass-by-reference). Those calls go through `function_call` in CaspM like any other user function; only the built-in bumps get their own CaspM bwc as an internal optimization for the hottest operator sugar.

## Interaction with closures

Inside a closure body, `$$foo` follows the closure's captured scope-chain — the same walk as `$foo` would take. The varobj refers to the **captured slot** from the enclosing scope, NOT a fresh local inside the closure. Mutations through it — `.value=`, `.freeze`, passing to a mutating function, or applying an operator like `++` — reach the enclosing scope's variable.

~~~caspian
$counter = 0

$increment_it = closure()
	$counter++
end

&increment_it
$counter # 1 — the closure mutated the captured slot
~~~

Same behavior with the value-setter form:

~~~caspian
$foo = 1

$cl = closure()
	$$foo.value = 2
end

&cl
$foo # 2
~~~

Passing a captured varobj to a mutating helper works the same way:

~~~caspian
$a = 1
$b = 2

$swap_them = closure()
	&swap $$a, $$b
end

&swap_them
$a # 2
$b # 1
~~~

**Why this works.** Closures already capture their enclosing lexical scope by reference (see [functions/closure § Captured scope keeps resources alive](https://puck.uno/requirements/functions/closure#captured-scope-keeps-resources-alive)). The varobj follows the same reference-capture: `$$foo` inside the closure body walks the closure's captured scope-agg to find the slot, and returns the same varobj the enclosing scope would return. Mutating captured variables — counters, accumulators, cross-callback state — is a natural pattern that composes with the varobj primitive without needing a separate "outer binding" concept.

## Attribute chaining

Variable-object property access chains work like any other object:

~~~caspian
$$foo.value           # single access
$$foo.a.b.c           # multi-segment chain
~~~

## Class identifier

The variable-object class is identified as **`core:variable`**. Access the class (for typed-parameter annotations, `isa?` checks, and any other class-reference use) via `%('core:variable')`:

~~~caspian
$foo = 1
$$foo.object.isa? %('core:variable') # true
~~~

The URL is what typed parameters use to constrain their arguments:

~~~caspian
$fn = function($var: {class: %('core:variable')})
	# $var is a variable-object here
end
~~~

Same URL-style class-identifier convention Caspian uses throughout — no separate shortname at the language surface.

## CaspJ shape

`$$name` produces the atom `{varobj: NAME}` in full CaspJ, parallel to `{var: NAME}` for the value form. See [caspianj § Full](https://puck.uno/requirements/caspianj#full).

At norm level the atom stays as `{varobj: NAME}` — already primitive; no further desugaring.

The atom-key name `varobj` is a transpiler-internal shorthand; the Caspian-facing class URL is `core:variable`. Two different naming domains — the atom-key names the atom shape; the class URL identifies the class an instance belongs to.

## Open

_No open items — closure-capture behavior settled in [Interaction with closures](#interaction-with-closures); block-scope walk-then-write behavior spec'd via the scope runtime (see [lua/scope § Assignment walks the scope agg](https://puck.uno/requirements/lua/scope#assignment-walks-the-scope-agg))._

## Testing

- **`$$foo` returns a variable-object** — `$foo = 1; $$foo.object.isa? %('core:variable')` is `true`.
- **`.value` reads current value** — after `$foo = 42`, `$$foo.value` is `42`; same as `$foo`.
- **`.value=` writes new value** — after `$foo = 1; $$foo.value = 99`, `$foo` is `99`.
- **`$$foo = X` raises** — reassigning the varobj slot itself is not permitted; raises with a specific error pointing at `$foo = X` as the intended form.
- **`.freeze` is idempotent** — calling `.freeze` twice on the same slot does not raise on the second call.
- **`.frozen?` returns false before freeze** — after `$foo = 1`, `$$foo.frozen?` is `false`.
- **`.frozen?` returns true after freeze** — after `$foo = 1; $$foo.freeze`, `$$foo.frozen?` is `true`.
- **Frozen slot rejects value-sigil assignment** — after `$foo = 1; $$foo.freeze`, `$foo = 2` raises.
- **Frozen slot rejects varobj-value assignment** — after `$foo = 1; $$foo.freeze`, `$$foo.value = 2` raises.
- **Frozen slot still readable** — after `$foo = 1; $$foo.freeze`, `$foo` is `1` and `$$foo.value` is `1`.
- **Typed-param accepts a varobj** — a function with param class `%('core:variable')` accepts `&fn $$foo` without raising.
- **Typed-param rejects a value** — the same function called as `&fn $foo` raises with a class-mismatch error at the call boundary.
- **`$$foo` inside a closure refers to the captured slot** — after `$foo = 1; $cl = closure() $$foo.value = 2 end; &cl`, `$foo` is `2` (closure mutated the outer slot).
- **Bump inside a closure mutates the captured slot** — after `$counter = 0; $cl = closure() $counter++ end; &cl`, `$counter` is `1`.
- **Passing a captured varobj to a mutating helper reaches the outer variable** — after `$a = 1; $b = 2; $cl = closure() &swap $$a, $$b end; &cl`, `$a` is `2` and `$b` is `1`.
- **Bumping a frozen variable raises** — after `$foo = 1; $$foo.freeze`, `$foo++` raises (the underlying `.value=` is blocked by the freeze).

## Related

- [syntax/variables-and-assignment](https://puck.uno/requirements/syntax/variables-and-assignment) — variable declaration, value assignment, scoping rules.
- [syntax/sigils](https://puck.uno/requirements/syntax/sigils) — the sigil family (`$`, `$$`, `%`, `@`, `&`).
- [caspianj § Calls](https://puck.uno/requirements/caspianj#calls) — how variable-objects fit into the function_call primitive, especially for bump operators.
- [lua/scope](https://puck.uno/requirements/lua/scope) — the scope runtime that owns variable slots; interaction with `$$foo` still to be pinned.
