# Loops

```
vibecode: {
	"doc": "loops",
	"role": "all_loop_constructs_in_kscript_in_one_place",
	"loop_forms": ["while_block", "each_iteration_method", "numeric_helpers_times_upto_downto"],
	"loop_object_via": "as_loop",
	"loop_object_methods": ["next", "return", "break", "count", "active", "index"],
	"loop_exit_methods_aliased": ["return", "break"],
	"loop_exit_bwc": "break_optional_level_count",
	"structural_blocks": ["before", "between", "after", "noloop"],
	"notes": ["structural_blocks_have_no_access_to_iteration_variable",
		"as_keyword_is_a_general_block_mechanism_see_kscript_md_the_as_keyword_section",
		"break_bwc_added_post_soft_lock_2026-05-17_as_deliberate_v1_addition"]
}
```

KScript has three ways to loop:

- **`while`** — repeat a body while a condition is truthy
- **`.each`** — iterate over a collection's elements
- **Numeric helpers** — `.times`, `.upto`, `.downto` on numbers

Any of them can be named with `as $loop` to bind a loop object that
exposes iteration state and control methods. The general `as` keyword
mechanism (which applies to any block, not just loops) is covered in
[kscript.md § The `as` Keyword](kscript.md#the-as-keyword-kahless-clone);
this doc focuses on the loop-specific use.

---

## `while` (Worf)

```
vibecode: {
	"section": "while",
	"shape": "while_condition_body_end",
	"semantics": "evaluate_condition_before_each_iteration; loop_while_truthy"
}
```

`while` repeats its body while the condition expression is truthy. The
condition is re-evaluated before each iteration.

```
while $foo
    # body
end
```

No `do` keyword between the condition and the body — control
structures own their body directly. See
[kscript.md § When `do` is Required](kscript.md#when-do-is-required)
for the rule.

---

## `.each` (Ruon Tarka)

```
vibecode: {
	"section": "each",
	"shape": "collection.each(loop_var) do ... end",
	"semantics": "bind_loop_var_to_each_element_in_turn"
}
```

Collections provide `.each` to iterate over their elements:

```
$items.each($item) do
    # body — $item is bound to each element in turn
end
```

`.each` is a method call with a block argument, so it requires `do`.

---

## Numeric iteration helpers (Centaur)

```
vibecode: {
	"section": "numeric_helpers",
	"methods": ["times", "upto", "downto"],
	"returns": "nil",
	"index_base_for_times": "zero_based",
	"upto_downto_inclusive": true
}
```

Number values expose three iteration helpers. None of them return a
useful value; their job is the side effect of running the block.

| Method | Description |
|---|---|
| `times` | Execute the block `n` times. The block parameter is the 0-based index. `3.times do($i); ...; end` |
| `upto($n)` | Iterate from the current value up to `$n` inclusive. |
| `downto($n)` | Iterate from the current value down to `$n` inclusive. |

```
5.times do($i)
    print $i        # 0 1 2 3 4
end

1.upto(3) do($n)
    print $n        # 1 2 3
end
```

These are sugar over the underlying iteration machinery — internally
they behave the same as `.each` over the corresponding range and accept
`as $loop` the same way.

---

## Naming a loop with `as` (Quinn)

```
vibecode: {
	"section": "naming_with_as",
	"binds": "loop_object",
	"scope_default": "loop_block",
	"to_retain_after_loop": "pre_declare_variable_in_outer_scope"
}
```

Any of the three loop forms can be named with `as` to bind a **loop
object** for the duration of the loop:

```
$bar.each($foo) as $loop
    print $loop.count   # current iteration, 1-based
    print $loop.active  # true while loop is running
end

$loop.active            # false after loop ends
$loop.count             # total iterations
```

By default, the loop object is scoped to the loop block. To retain it
after the loop, pre-declare the variable in the outer scope.

The same form works on `while` and the numeric helpers:

```
while($foo) as $loop
    # $loop available inside the body
end

5.times as $loop do($i)
    # both $i (index from times) and $loop (loop object) available
end
```

---

## Loop object methods (Lady Q (TNG))

```
vibecode: {
	"section": "loop_object_methods",
	"control_methods": ["next", "return", "break"],
	"aliases": {"return": "break"},
	"state_readers": ["count", "active", "index"]
}
```

| Method | Description |
|---|---|
| `$loop.return` | Exit the loop. Optional value: `$loop.return value` exits with that value; `$loop.return` with no argument exits with no value. |
| `$loop.break` | Alias for `$loop.return`. Same behavior, same optional value form. |
| `$loop.next` | Skip to the next iteration |
| `$loop.count` | Current iteration number (1-based); total count after loop ends |
| `$loop.active` | `true` while the loop is running, `false` after it ends |
| `$loop.index` | Current iteration index (0-based) |

`$loop.return` and `$loop.break` are two names for the same operation
— exit this loop. Both accept the optional value form (`.return value`
or `.break value`); both leave `$loop.active` false and
`$loop.count` equal to the iterations that ran. Pick whichever name
reads better in context. For the prefix-free top-level form (no
`$loop` reference needed, multi-level exit), see [break](#break-riker).

**`return` (without `$loop.`) is a function exit, not a loop exit.**
A bare `return` inside a loop body returns from the enclosing
function. There's no special mechanism — `return` works the same
inside or outside a loop. Use `$loop.return` (or `$loop.break`) when
you want to exit just the loop; use `return` when you want to return
from the enclosing function.

---

## `break` (Riker)

```
vibecode: {
	"section": "break_bwc",
	"form": "bwc",
	"shape": "[{\"bwc\": \"break\"}, {\"value\": N}?]",
	"arg": "optional_positive_integer_level_count_default_1",
	"function_boundary": "does_not_escape_user_defined_functions_or_closures_named_via_dollar",
	"block_boundary": "DOES_escape_through_do_end_blocks_passed_to_method_calls_per_user_examples",
	"named_loop_targeting_form": "tbd_break_loop_var_as_alternative_to_level_count",
	"history": "added_post_soft_lock_2026-05-17_as_deliberate_v1_addition_per_scotty_section"
}
```

`break` exits a loop without a `$loop` reference. The plain form exits
the innermost enclosing loop; `break N` exits N enclosing loops.

```
$people.each do($person)
    break
end
```

`break 2` walks out of two loops at once:

```
$people.each do($person)
    $person.addresses.each do($address)
        break 2
    end
end
```

After `break N`, control resumes after the N-th enclosing loop. The
intervening loop objects' `$loop.active` becomes `false` and their
`$loop.count` reflects the iterations that actually ran.

### Function boundary

`break` does **not** escape function boundaries. If a function
definition encloses a loop and contains `break`, that `break` exits
the loop inside the function; it does not affect any loop in the
caller.

```
function &process_each($list) do
    $list.each do($item)
        break          # exits the .each inside process_each
    end
end

$outer.each do($x)
    &process_each($outer)   # break inside process_each does NOT
                            # exit this .each
end
```

`break` **does** flow through `do ... end` blocks passed as
arguments to methods like `.each`, `.times`, `.upto`. Those are
blocks, not function definitions — they execute in the caller's
lexical context. The first example above relies on this.

### Argument validation

- `break 1` is equivalent to bare `break`.
- `break 0` raises `kiera.uno/exception/error/invalid_argument` —
  break by zero levels is nonsense and almost always a bug.
- `break N` where N exceeds the number of enclosing loops raises
  `kiera.uno/exception/error/invalid_argument`. Use named-loop
  targeting (TBD, see open questions) when the depth might vary.
- The level argument is evaluated as a normal integer expression;
  `break $depth` works with a variable. If the runtime value is not a
  positive integer the same `invalid_argument` is raised.

### Interaction with structural blocks

If `break` (or `break N`) exits a loop, the loop's `after` structural
block does **not** run — `after` only runs after a complete iteration
sweep. The `between` block does not run on the iteration that
breaks. The `noloop` block remains a no-op (it only runs when the
loop body didn't run at all).

### Open question: named-loop targeting

Loops can be named with `as $name` (see
[Naming a loop with `as`](#naming-a-loop-with-as-quinn)). A natural
extension is `break $outer` to target a specific loop by name, which
survives refactoring that changes nesting depth. Whether to ship this
in V1 alongside `break N` is TBD. Both can coexist; the level-count
form covers the common case and is what was scoped in the
post-lock addition.

---

## Structural blocks (Q Continuum)

```
vibecode: {
	"section": "structural_blocks",
	"blocks": ["before", "between", "after", "noloop"],
	"access_to_iteration_variable": false,
	"notes": ["structural_blocks_are_optional;
		each_runs_at_a_defined_phase_of_the_loop"]
}
```

Loops support four optional structural blocks. None of them have
access to the iteration variable — they exist at the loop's structural
phases, not inside the iteration.

```
$bar.each($foo)
    print $foo.result
before
    print "--- START ------"
between
    print "----------------"
after
    print "--- END --------"
noloop
    print "--- NO RESULTS -"
end
```

| Block | When it runs |
|---|---|
| `before` | Once before the first iteration |
| `between` | Once between each iteration (not before the first, not after the last) |
| `after` | Once after the last iteration |
| `noloop` | Only when the collection is empty (no iterations ran) |

The `before` / `between` / `after` blocks run unconditionally whenever
the body would run at least once. `noloop` runs exactly when the loop
body would not run at all — useful for "nothing matched" messages
without an extra emptiness check around the loop.

---

## Not in KScript (Q DeLancie)

```
vibecode: {
	"not_in_kscript": ["for_in_form_iteration_is_each_only",
		"redo_retry_no_iteration_restart_construct",
		"outer_function_return_uses_plain_return_no_special_construct"]
}
```

These were considered and explicitly excluded:

- **`for X in Y` form.** KScript uses `.each` for iteration. No
  parallel `for ... in ...` block form.
- **`redo` / `retry`.** Ruby-style restart of the current iteration
  is not part of KScript.
- **A special "return from the enclosing function" inside a loop.**
  Not needed — plain `return` does exactly that. See the note in
  [Loop object methods](#loop-object-methods-lady-q-tng).
