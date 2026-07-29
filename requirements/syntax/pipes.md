# Pipes

<span class="tag">pipes</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_syntax_pipes",
	"role": "syntax spec for Caspian's pipe operators. Two operators: `|` (basic pipe) and `|&` (null-safe pipe — sticky through the rest of the chain). Two RHS forms: `&fn` / `$obj.method` (piped value fills first positional argument slot) and `.method()` (piped value BECOMES the receiver of a method call). Same shape as Elixir's `|>`, F#'s `|>`, R's `%>%` — but the `.method()` receiver form is Caspian-specific since Caspian keeps receiver-vs-first-arg distinct. Pipe precedence binds looser than every operator except the logical connectives (`||`, `&&`, `or`, `and`), which are looser still so a pipe chain can be the LHS of a fallback. All examples on this page show pipes as the RHS of an assignment so the useful outcome — the value the chain produces — has a name. Distinct from the plumbing runtime concept (faucets and sinks) and from shell pipes / bitwise-OR.",
	"status": "spec — basic `|` and null-safe `|&` operators settled with desugaring rules; both RHS forms (first-arg `&fn` / `$obj.method` and receiver `.method()`) spec'd including no-parens `.method` shorthand, chained `.method().first`, and null behavior",
	"audience": "developers writing Caspian; tooling authors (parsers, formatters, syntax highlighters, LSPs) implementing the pipe operators"
}}
~~~

Pipes let programs write data flow in **execution order** rather than nested call syntax. The pipe operator passes the result of one expression as the first positional argument to a call on the right.

Two forms:

- **`|`** — basic pipe.
- **`|&`** — null-safe pipe. Enables null-propagation mode for the rest of the chain.

Pipes here are distinct from three other concepts that share the `|` character or the word "pipe":

- **Not the plumbing concept.** [Plumbing](https://puck.uno/requirements/plumbing/) covers faucets (inbound) and sinks (outbound) — runtime edges of the Caspian process, not a syntactic operator.
- **Not the shell pipe.** Shell features aren't part of `.execute`; see [linux-support](https://puck.uno/requirements/linux-support/).
- **Not bitwise-OR.** Bitwise operations live on the [`.bitwise`](https://puck.uno/requirements/built-in-classes/primitives/number/bitwise) wrapper on numbers, precisely so `|` is free for pipe use here.

## What can appear on either side

The **left-hand side** is any expression that produces a value.

The **right-hand side of a pipe must be a call.** Two forms are allowed, and they route the piped value to different slots:

- **`&name` or `$obj.method`** — the piped value fills the **first positional argument** slot.
- **`.method()`** — the piped value BECOMES the receiver of a method call.

A bare variable can't be a pipe RHS; there'd be no argument slot to route the value into.

**A note on examples.** Every example on this page assigns the pipe expression to a variable — a pipe produces a value; if you don't capture it, you've just written a chain of function calls for side effects. Single-stage examples like `$text | &foo` are omitted deliberately: they're better written as `&foo $text`. Examples also start each pipe chain with a **function call**, not a bare variable — `&normalize($text) | $formatter.render` reads better than `$text | &normalize | $formatter.render`, though both forms are legal Caspian and both parse to the same tree.

## Basic pipe: `|`

~~~caspian
$value = &get_key | &normalize | &fetch
~~~

Reads left-to-right in the order it runs: call `&get_key`, pipe its result into `&normalize`, pipe that into `&fetch`, assign the final result to `$value`. So **`$value`** is whatever `&fetch` returned after being handed the normalized key.

Semantically equivalent to:

~~~caspian
$value = &fetch(&normalize(&get_key))
~~~

Both forms produce the same runtime value. Everywhere on this page that says "desugars to X," "equivalent to X," or "same as X" is about execution semantics, not CaspianJ representation — CaspianJ **preserves** the pipe as a distinct `{op: "|", left, right}` atom so tooling (formatters, syntax highlighters, LSPs) can tell that the source used `|` rather than nested calls. See [pipes at the CaspianJ level](#pipes-at-the-caspianj-level) below.

Each `|` passes the result of the left-hand expression as the **first positional argument** to the call on the right. Any additional arguments at the call site bind normally — the piped value takes the first positional slot, the rest bind as written:

~~~caspian
$top10 = &fetch_records() | &sort 'asc' | &take 10
~~~

`&sort` is called with the fetched records as its first arg and `'asc'` as its second; the result is piped into `&take` with `10` as its extra arg. **`$top10`** ends up as the first ten entries of the sorted list.

Same shape as Elixir's `|>`, F#'s `|>`, R's `%>%`.

## Multi-line pipes

Longer chains break across lines, with `|` at the end of each line to signal continuation:

~~~caspian
$result = &normalize $text |
	&trim |
	&upcase
~~~

Same desugaring as the single-line form — the pipes chain identically regardless of the line break:

~~~caspian
$result = &upcase(&trim(&normalize $text))
~~~

**`$result`** is the upcased, trimmed, normalized text.

## Method call on an external receiver: `$obj.method`

The right-hand side can be a method call on some other object. The piped value fills the first positional slot on that method:

~~~caspian
$html = &normalize($text) | $formatter.render
~~~

desugars to:

~~~caspian
$html = $formatter.render(&normalize($text))
~~~

Here `$formatter` is the receiver and the piped value is the first argument. **`$html`** is whatever `$formatter.render` returns after being handed the normalized text.

## Method call on the piped value: `.method()`

Sometimes what you want is to call a method **on the piped value itself** — the piped value BECOMES the receiver. Prefix the method name with `.` (no receiver written) and the pipe fills the receiver slot:

~~~caspian
$csv = &get_arr | .sort() | .join(', ')
~~~

desugars to:

~~~caspian
$csv = &get_arr.sort().join(', ')
~~~

Each `.method()` in the chain treats the previous stage's result as its receiver. **`$csv`** is a comma-separated string of the sorted array elements.

**Contrast with the `&fn` form.** Both forms accept the piped value, but they put it in different slots:

- `&get_arr | &sort` → `&sort(&get_arr)` — piped value goes into `&sort`'s first argument slot.
- `&get_arr | .sort()` → `&get_arr.sort()` — piped value IS the receiver; `.sort()` is a method on it.

Use `&fn` when you want to route the value through a top-level closure or an external object's method. Use `.method()` when you want to call the piped value's own method.

### No-parens shorthand: `.field`

`.method` without parens is a method call with no arguments — same as `.method()`. Ruby-style parens-optional rule:

~~~caspian
$name = &get_current_user | .profile | .name
~~~

desugars to:

~~~caspian
$name = &get_current_user.profile.name
~~~

**`$name`** is the current user's profile.name — three stages, each a no-parens method call on the previous value.

### Chaining after `.method()`

The result of `.method()` is a value like any other, so chaining more `.` calls after it works as ordinary Caspian method chaining. Method chaining and further pipe stages compose freely:

~~~caspian
$smallest = &get_records | .sort() | .first
~~~

desugars to:

~~~caspian
$smallest = &get_records.sort().first
~~~

**`$smallest`** is the first element of the sorted records — the smallest one.

### Behavior on null

Plain `|` gives no null-safety. If the piped value is null and the RHS is `.method()`:

~~~caspian
$value = &find_missing() | .sort()
~~~

Say `&find_missing()` returns `null`. **`$value` is never assigned** — the pipe raises a null-method-call error because `null` doesn't have a `.sort()` method. If you want the chain to short-circuit on null instead, use `|&`:

~~~caspian
$value = &find_missing() |& .sort() | .first
~~~

The null-safe pipe short-circuits before `.sort()` is invoked. **`$value` is `null`** — cleanly, no error.

## Design principle

Pipes express **data flow in execution order**, not call nesting. Each stage receives exactly one input: the result of the previous stage.

## Precedence

`|` binds **looser than every operator except the logical connectives** (`||`, `&&`, `or`, `and`). Arithmetic, comparison, and other operators evaluate first, and the pipe stages structure what happens at that level; the logical connectives sit even further out so a pipe chain can appear on the LHS of a fallback.

**Tighter than pipe** — evaluate inside a pipe stage:

~~~caspian
$result = $a + $b | &fn
~~~

evaluates as `$result = ($a + $b) | &fn` — arithmetic runs first, then the sum flows into `&fn`. **`$result`** is `&fn($a + $b)`.

**Looser than pipe** — the logical connectives:

~~~caspian
$result = &primary | &transform || &fallback
~~~

evaluates as `$result = (&primary | &transform) || &fallback` — the whole pipe expression is the LHS of `||`, and `&fallback` fires if the pipe result is falsy. This is the "pipe with fallback" pattern. Same shape as writing the parens explicitly: `($result = (&primary | &transform) || &fallback)`.

**Style: use explicit parens when a pipe stage contains tighter-binding operators or when a logical fallback follows a pipe.** Even though the precedence rules are unambiguous, an unparenthesized mix reads poorly at a glance. Prefer:

~~~caspian
$result = ($a + $b) | &fn
$result = (&primary | &transform) || &fallback
~~~

Same meaning as the paren-less forms, but the parens make the pipe boundary explicit and don't rely on the reader knowing the precedence table.

## Null-safe pipe: `|&`

Same shape as `|`, but the moment `|&` appears in a chain it enables **null-propagation mode** for every subsequent stage. Once on, the mode is sticky — the developer writes `|&` once, and the null-safety applies through the rest of the chain.

~~~caspian
$saved = &get_record 42 |&
	&validate |
	&transform |
	&save
~~~

**`$saved`** is either the value `&save` produced (in the success case) or `null` (if any stage in the chain returned null and short-circuited).

The sticky semantic: after `|&` at position N, positions N+1, N+2, … behave as if they were also `|&`. So the chain above is equivalent to:

~~~caspian
$saved = &get_record 42 |&
	&validate |&
	&transform |&
	&save
~~~

### What happens if a stage returns null

Take the chain above. Say `&validate` returns null:

1. `&get_record 42` runs and returns some value.
2. `&validate` gets that value, returns `null`.
3. **`&transform` is never called.** Null-safe mode short-circuits the moment any stage produces `null`.
4. `&save` is likewise skipped.
5. **`$saved`** ends up as `null`.

The same happens if `&transform` or `&save` returns `null` at their turn: the chain stops and `$saved` gets `null`.

### Execution model

The null-safe form short-circuits: any stage that produces `null` stops the chain and the whole pipe expression evaluates to `null`. Roughly, the chain above expands to:

~~~caspian
$x = &get_record 42

if $x == null
	return null
end

$y = &validate $x

if $y == null
	return null
end

$z = &transform $y

if $z == null
	return null
end

return &save $z
~~~

(Illustrative — the actual desugared form has to yield a value the outer assignment can bind, not literally use `return`. The point is the short-circuit shape: each stage checks the incoming value for null and skips the rest of the chain if it's null.)

## Summary

**Operators:**

| Operator | Meaning |
|---|---|
| <code>&#124;</code> | Pass result to next stage. |
| <code>&#124;&amp;</code> | Enable null-propagating pipe mode (sticky through the rest of the chain). |

**RHS forms:**

| Form | Where the piped value goes |
|---|---|
| <code>&#124; &fn</code> or <code>&#124; $obj.method</code> | First positional argument slot of the call. |
| <code>&#124; .method()</code> or <code>&#124; .field</code> | Receiver of the method call (the piped value IS the receiver). |

## Pipes at the CaspianJ level

CaspianJ **preserves** the pipe as a distinct atom rather than expanding it into a nested call — the source form stays visible after transpilation, so tooling (formatters, syntax highlighters, LSPs, source-map generators) can tell that the developer used `|` instead of writing the nested call form directly.

**Shape:**

~~~
{op: "|", left: LHS_atom, right: RHS_atom}
~~~

- **`left`** — the piped value; any expression atom.
- **`right`** — the call to invoke, shaped by the source RHS form (see the table below).

**RHS shape by source form:**

| Source | `right` shape | Runtime routing |
|---|---|---|
| `&fn` | `[{amp: "fn"}]` | LHS prepends as first positional. |
| `&fn(a, b)` | `[{amp: "fn"}, a_atom, b_atom]` | LHS prepends as first positional. |
| `$obj.method` | `[{var: "obj"}, "method"]` | LHS prepends as first positional. |
| `$obj.method(a)` | `[{var: "obj"}, "method", {args: [a_atom]}]` | LHS prepends into `envelope.args`. |
| `.method` | `{method: "method"}` | LHS becomes the receiver. |
| `.method(a)` | `{method: "method", args: [a_atom]}` | LHS becomes the receiver; envelope carries extras. |

The `.method` form uses a distinct `{method: name, ...}` atom shape (only valid inside a pipe RHS) so the runtime can tell the receiver-form pipes apart from the first-arg-form pipes purely from the shape.

**Chained pipes wrap outward:** `A | B | C` transpiles as `{op: "|", left: {op: "|", left: A, right: B}, right: C}` — left-to-right associativity, rightmost pipe outermost.

**Statement-leading pipes** (`| bwc` on the following line — see the [pipes syntax examples](#basic-pipe)) are a different shape entirely: `[{bwc: "modifier"}, prev_value_atom]`. Statement-leading pipes are a POST-STATEMENT modifier that rewrites the previous statement, not an expression-level operator; see the Section 17 tests in `parse.casp` for the shape.

## Related

- [operators](https://puck.uno/requirements/syntax/operators) — other operator syntax.
- [built-in-classes/primitives/number/bitwise](https://puck.uno/requirements/built-in-classes/primitives/number/bitwise) — why bitwise-OR uses the wrapper, freeing `|` for pipe.
