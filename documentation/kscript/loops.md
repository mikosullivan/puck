# Loops

```
vibecode: {
	"doc": "loops",
	"role": "all_loop_constructs_in_kscript_in_one_place",
	"loop_forms": ["while_block", "each_iteration_method", "numeric_helpers_times_upto_downto"],
	"loop_object_via": "as_loop",
	"loop_object_methods": ["next", "return", "count", "active", "index"],
	"structural_blocks": ["before", "between", "after", "noloop"],
	"notes": ["structural_blocks_have_no_access_to_iteration_variable",
		"as_keyword_is_a_general_block_mechanism_see_kscript_md_the_as_keyword_section"]
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
	"control_methods": ["next", "return"],
	"state_readers": ["count", "active", "index"]
}
```

| Method | Description |
|---|---|
| `$loop.return` | Exit the loop. Optional value: `$loop.return value` exits with that value; `$loop.return` with no argument exits with no value. |
| `$loop.next` | Skip to the next iteration |
| `$loop.count` | Current iteration number (1-based); total count after loop ends |
| `$loop.active` | `true` while the loop is running, `false` after it ends |
| `$loop.index` | Current iteration index (0-based) |

There is no `break` method. `$loop.return` (with no argument) is the
plain "exit this loop" form; `$loop.return value` is the "exit this
loop carrying a value" form. After either, `$loop.active` is `false`
and `$loop.count` is the number of iterations that actually ran.

**`return` (without `$loop.`) is a function exit, not a loop exit.**
A bare `return` inside a loop body returns from the enclosing
function. There's no special mechanism — `return` works the same
inside or outside a loop. Use `$loop.return` when you want to exit
just the loop; use `return` when you want to return from the
enclosing function.

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
