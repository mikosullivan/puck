# CaspianJ

<a id="overview"></a>
## Overview

~~~json
{"vibecode": {
	"section": "overview",
	"format": "CaspianJ",
	"alias": "caspj",
	"purpose": "canonical_runtime_format_for_caspian_programs",
	"not": "bytecode",
	"convention": "share_as_caspian_source_cjs_is_runtime_artifact",
	"bootstrap_note": "parser_must_be_written_directly_in_cjs"
}}
~~~

CaspianJ (informally: caspj) is the canonical runtime format for Caspian programs. It is
not bytecode — it is a full representation of the program as a JSON data structure. Caspian
transpiles to CaspianJ for execution.

CaspianJ is a runtime artifact. By convention, code is shared as Caspian source, not
as CaspianJ.

CaspianJ also serves as a **canonical semantic intermediate** between source forms.
The current pipeline is Caspian source → CaspianJ → execution, but the architecture
permits multiple source syntaxes (different parsers fanning in to CaspianJ) and
multiple pretty-printers (different surface forms fanning out from CaspianJ). The
project shipped with a single canonical surface (Caspian), but the multi-syntax option
remains open — no spec change is required for an alternate-syntax parser to be added
later. No such alternates are planned for v1.

The bootstrap parser must be written directly in CaspianJ, since Caspian cannot parse
itself before the parser exists.

---

<a id="core-principle"></a>
## Core Principle

~~~json
{"vibecode": {
	"section": "core_principle",
	"value_receiver_form": "[receiver, method, arg1?, arg2?, ...]",
	"bwc_receiver_form": "[{bwc: name}, arg1?, arg2?, ...]",
	"receiver": "any_expression_variable_literal_sys_bwc_or_nested_call",
	"method": "string_naming_method_or_operator_required_for_value_receivers_omitted_for_bwc_receivers",
	"args": "zero_or_more_positional_expressions_spread_at_indices_3_plus; or_a_single_kwargs_hash_at_index_3_distinguishable_by_absence_of_expression_marker_key",
	"two_shapes": "value_receiver_shape_for_method_calls_operators_assignment; bwc_shape_for_built_in_commands_where_the_bwc_name_is_the_call"
}}
~~~

Every statement begins with a receiver. The receiver determines the shape:

- **Value receivers** (variables, literals, system methods, nested calls) take a
  **method name** next, then zero or more positional args spread directly
  across the array: `[receiver, method, arg1?, arg2?, ...]`. This covers method
  calls, operators, assignment.
- **Bwc receivers** (`{"bwc": "name"}`) don't take a method — the bwc name
  IS the call. Args spread the same way:
  `[{"bwc": name}, arg1?, arg2?, ...]`. This covers built-in commands like
  `puts`, `if`, `while`, `return`, `raise`.

**Positional arguments** are each their own slot in the array. Each
comma-separated expression in Caspian source becomes one slot in CaspianJ:

| Caspian | CaspianJ |
|---|---|
| `$foo.bar` | `[{"var": "foo"}, "bar"]` |
| `$foo.bar(a)` | `[{"var": "foo"}, "bar", a]` |
| `$foo.bar(a, b, c)` | `[{"var": "foo"}, "bar", a, b, c]` |
| `puts 'hi'` | `[{"bwc": "puts"}, {"value": "hi"}]` |

**Keyword arguments** are a single hash at index 3:

| Caspian | CaspianJ |
|---|---|
| `$foo.bar(name: 'X')` | `[{"var": "foo"}, "bar", {"name": {"value": "X"}}]` |
| `$foo.bar(name: 'X', age: 30)` | `[{"var": "foo"}, "bar", {"name": {"value": "X"}, "age": {"value": 30}}]` |

**Distinguishing single positional from kwargs.** When index 3 is a hash, the
dispatcher tells which kind it is by checking for an **expression-marker
key**: `value`, `var`, `bwc`, `array`, `hash`, `call`, `closure`, `sys`, etc.
A hash that carries one of those keys is a single positional expression
(e.g. a hash literal `{"hash": [...]}`); a hash without any expression-marker
key is kwargs.

| Caspian | CaspianJ | Interpretation |
|---|---|---|
| `$foo.bar({key: 'X'})` | `[{"var": "foo"}, "bar", {"hash": [...]}]` | Single positional, hash literal |
| `$foo.bar(key: 'X')` | `[{"var": "foo"}, "bar", {"key": {"value": "X"}}]` | Kwargs |

Positional args and kwargs don't mix in the same call (per Caspian's source-side
rule — kwargs are all-or-nothing in a single call site).

---

<a id="comments"></a>
## Comments

~~~json
{"vibecode": {
	"section": "comments",
	"form": "{\"comment\": \"...\"}",
	"behavior": "no_op_ignored_by_interpreter",
	"placement": "anywhere_in_statement_array"
}}
~~~

A `{"comment": "..."}` object anywhere in a statement array is a human-readable no-op.
It is ignored by the interpreter.

```json
[
    {"comment": "greet the user"},
    [{"var": "name"}, "=", {"value": "Jean-Luc"}]
]
```

---

<a id="expressions"></a>
## Expressions

~~~json
{"vibecode": {
	"section": "expressions",
	"forms": {
		"literal": "{\"value\": ...}",
		"variable": "{\"var\": \"foo\"}",
		"ivar": "{\"ivar\": \"foo\"}",
		"varobj": "{\"varobj\": \"foo\"}",
		"sys": "{\"sys\": \"name\"}",
		"bwc": "{\"bwc\": \"name\"}",
		"array": "{\"array\": [...]}",
		"hash": "{\"hash\": [[key, expr], ...]}",
		"function": "{\"function\": {\"params\": [...], \"body\": [...]}}",
		"closure": "{\"closure\": {\"params\": [...], \"body\": [...]}}"
	},
	"hash_note": "pairs_preserve_insertion_order"
}}
~~~

Expressions are JSON objects that produce a value.

<a id="literals"></a>
### Literals

```json
{"value": "hello"}
{"value": 42}
{"value": true}
{"value": null}
```

<a id="variables"></a>
### Variables

```json
{"var": "foo"}        // $foo
{"ivar": "foo"}       // @foo  (%bucket['foo'])
{"varobj": "foo"}     // $$foo
{"sys": "chain"}      // %chain
```

<a id="bare-word-commands"></a>
### Bare Word Commands

A `{"bwc": "name"}` defers lookup to the runtime. The interpreter resolves the name
through the scope dispatcher to find the associated object and method. It is syntactic
sugar — it does not expand in CaspianJ.

```json
{"bwc": "puts"}       // puts
{"bwc": "exit"}       // exit
```

<a id="array-literals"></a>
### Array Literals

```json
{"array": [{"value": 1}, {"value": 2}, {"value": 3}]}
```

Caspian equivalent: `[1, 2, 3]`

<a id="hash-literals"></a>
### Hash Literals

Hashes are represented as an array of `[key, expr]` pairs to preserve insertion order.

```json
{"hash": [["name", {"value": "Picard"}], ["rank", {"value": "Captain"}]]}
```

Caspian equivalent: `{name: 'Picard', rank: 'Captain'}`

<a id="functions-and-closures"></a>
### Functions and Closures

```json
{"function": {"params": ["a", "b"], "body": [stmt, ...]}}
{"closure":  {"params": ["a", "b"], "body": [stmt, ...]}}
```

A `function` does not capture the outer scope. A `closure` does.

---

<a id="statements"></a>
## Statements

~~~json
{"vibecode": {
	"section": "statements",
	"forms": ["assignment", "method_calls", "function_calls", "bwc_calls", "operators"],
	"assignment_form": "[{\"var\": \"foo\"}, \"=\", expr]",
	"method_call_form": "[receiver, \"method\", {kw_args}]",
	"function_call_form": "[{\"var\": \"foo\"}, \"call\", {kw_args}]",
	"operator_form": "[receiver, \"op\", operand]"
}}
~~~

<a id="assignment"></a>
### Assignment

Assignment is the `=` operator — same `[receiver, method, args]` shape as
every other method call. The dispatcher does **not** special-case `=`.

```json
[{"var": "foo"}, "=", {"value": "hello"}]
```

Caspian equivalent: `$foo = 'hello'`

```json
[{"var": "greeting"}, "=", [{"var": "foo"}, "+", {"value": " world"}]]
```

Caspian equivalent: `$greeting = $foo + ' world'`

**How the dispatcher handles it.** When `{"var": "foo"}` appears in receiver
position, it materializes to an **lvalue handle** — a runtime value whose
class has `=`, `+=`, `-=`, etc. as methods that write back to scope. In
expression position (`{"var": "foo"}` as an argument or sub-expression),
the same form materializes to the variable's current *value*.

Same JSON shape, two contexts: assignment target vs read. The dispatcher
already knows which from where the expression sits in the parent statement
(receiver at index 0 → handle; anywhere else → value). No special form,
no `setvar` keyword, no four-element statement shape. Pure
`[receiver, method, args?]` everywhere.

<a id="method-calls"></a>
### Method Calls

```json
[{"var": "foo"}, "save"]
```

Caspian equivalent: `$foo.save`

```json
[{"var": "foo"}, "greet", {"name": {"value": "Jean-Luc"}}]
```

Caspian equivalent: `$foo.greet(name: 'Jean-Luc')`

Chained calls — the receiver of the outer call is the result of the inner:

```json
[[{"var": "foo"}, "bar"], "gup"]
```

Caspian equivalent: `$foo.bar.gup`

<a id="function-calls"></a>
### Function Calls

`&foo` calls the function object in `$foo`. This is a `call` method on the variable:

```json
[{"var": "foo"}, "call"]
```

Caspian equivalent: `&foo`

```json
[{"var": "foo"}, "call", {"name": {"value": "Picard"}}]
```

Caspian equivalent: `&foo(name: 'Picard')`

<a id="bare-word-command-calls"></a>
### Bare Word Command Calls

```json
[{"bwc": "puts"}, {"value": "hello world"}]
```

Caspian equivalent: `puts 'hello world'`

```json
[{"bwc": "puts"}]
```

Caspian equivalent: `puts`

<a id="operators"></a>
### Operators

Operators are method calls. The left operand is the receiver, the operator is the method,
the right operand is the argument:

```json
[{"var": "foo"}, "==", {"value": "bar"}]
[{"var": "x"}, "+", {"value": 1}]
[{"var": "a"}, "&&", {"var": "b"}]
```

Caspian equivalents: `$foo == 'bar'`, `$x + 1`, `$a && $b`

---

<a id="control-flow"></a>
## Control Flow

~~~json
{"vibecode": {
	"section": "control_flow",
	"constructs": ["if_elsif_else", "while"],
	"if_form": "[{\"bwc\": \"if\"}, {\"branches\": [...], \"else\": [...]}]",
	"while_form": "[{\"bwc\": \"while\"}, {\"cond\": expr, \"body\": [...]}]",
	"notes": ["branches_and_else_are_optional"]
}}
~~~

<a id="if-elsif-else"></a>
### If / elsif / else

```json
[{"bwc": "if"}, {
    "comment": "branches evaluated top to bottom; first matching 'when' wins",
    "branches": [
        {"when": [{"var": "rank"}, "==", {"value": "Captain"}],
         "then":  [[{"bwc": "puts"}, {"value": "Aye, captain"}]]},
        {"when": [{"var": "rank"}, "==", {"value": "Commander"}],
         "then":  [[{"bwc": "puts"}, {"value": "Aye, commander"}]]}
    ],
    "else": [[{"bwc": "puts"}, {"value": "Aye"}]]
}]
```

Caspian equivalent:
```
if ($rank == 'Captain')
    puts 'Aye, captain'
elsif ($rank == 'Commander')
    puts 'Aye, commander'
else
    puts 'Aye'
end
```

`branches` and `else` are both optional. If both are absent or empty
(`[{"bwc": "if"}, {}]`), the `if` is a no-op — nothing runs and the
statement returns `null`. Not an error.

<a id="while"></a>
### While

```json
[{"bwc": "while"}, {
    "cond": [{"var": "i"}, "<", {"value": 10}],
    "body": [
        [{"var": "i"}, "=", [{"var": "i"}, "+", {"value": 1}]]
    ]
}]
```

Caspian equivalent:
```
while ($i < 10)
    $i = $i + 1
end
```

<a id="break"></a>
### Break

~~~json
{"vibecode": {
    "section": "break_bwc",
    "form": "[{\"bwc\": \"break\"}, level_expr?]",
    "level_expr": "optional_integer_expression_default_1",
    "function_boundary": "does_not_escape_user_defined_functions_or_closures",
    "block_boundary": "DOES_escape_through_do_end_blocks_passed_to_method_calls",
    "history": "added_post_soft_lock_2026-05-17_as_deliberate_v1_addition",
    "see": "documentation/caspian/loops.md#break"
}}
~~~

`break` exits the innermost enclosing loop. With an integer argument,
exits N enclosing loops. Does not escape user-defined function or
closure boundaries; does flow through `do ... end` blocks passed to
methods like `.each`.

```json
[{"bwc": "break"}]
```

Caspian equivalent: `break`

```json
[{"bwc": "break"}, {"value": 2}]
```

Caspian equivalent: `break 2`

The level argument is any expression that evaluates to a positive
integer — a literal, a variable, or a computed value:

```json
[{"bwc": "break"}, {"var": "depth"}]
```

Caspian equivalent: `break $depth`

See [loops.md § break](syntax/loops.md#break) for full semantics,
including interaction with structural blocks and the open question
about `break $named_loop` as a targeting alternative.

---

<a id="blocks"></a>
## Blocks

~~~json
{"vibecode": {
	"section": "blocks",
	"form": "block key in args object",
	"structure": "{\"block\": {\"params\": [...], \"body\": [...]}}",
	"caspian_equivalent": "$items.each($item) do...end"
}}
~~~

A block is a closure passed to a method call. It is attached to the call via a `block` key
in the args object:

```json
[{"var": "items"}, "each", {
    "block": {
        "params": ["item"],
        "body":   [[{"bwc": "puts"}, {"var": "item"}]]
    }
}]
```

Caspian equivalent:
```
$items.each($item) do
    puts $item
end
```

---

<a id="function-and-closure-definitions"></a>
## Function and Closure Definitions

~~~json
{"vibecode": {
	"section": "function_and_closure_definitions",
	"function_form": "{\"function\": {\"params\": [...], \"body\": [...]}}",
	"closure_form": "{\"closure\": {\"params\": [...], \"body\": [...]}}",
	"named_function_is": "assignment_of_function_to_var",
	"difference": "closure_captures_scope_function_does_not"
}}
~~~

Since `function &foo` is sugar for `$foo = function(...)`, a named function definition
is just an assignment:

```json
[{"var": "greet"}, "=", {
    "function": {
        "params": ["name", "rank"],
        "body": [
            [{"bwc": "return"}, [
                [{"var": "rank"}, "+", {"value": " "}], "+", {"var": "name"}
            ]]
        ]
    }
}]
```

Caspian equivalent:
```
function &greet($name, $rank) do
    return $rank + ' ' + $name
end
```

A closure is identical but uses `"closure"` instead of `"function"`:

```json
[{"var": "greeter"}, "=", {
    "closure": {
        "params": ["name"],
        "body":   [[{"bwc": "puts"}, [{"var": "prefix"}, "+", {"var": "name"}]]]
    }
}]
```

Caspian equivalent:
```
$greeter = closure($name) do
    puts $prefix + $name
end
```

---

<a id="return"></a>
## Return

~~~json
{"vibecode": {
	"section": "return",
	"form": "[{\"bwc\": \"return\"}, expr]",
	"no_value_form": "[{\"bwc\": \"return\"}]"
}}
~~~

```json
[{"bwc": "return"}, {"var": "result"}]
```

Caspian equivalent: `return $result`

Return with no value:

```json
[{"bwc": "return"}]
```

---

<a id="exception-handling"></a>
## Exception Handling

~~~json
{"vibecode": {
	"section": "exception_handling",
	"constructs": ["catch", "raise"],
	"catch_form": "[{\"var\": \"e\"}, \"=\", [{\"bwc\": \"catch\"}, {\"class\": ..., \"body\": [...]}]]",
	"raise_form": "[{\"bwc\": \"raise\"}, class_string_expr]"
}}
~~~

<a id="catch"></a>
### catch

```json
[{"var": "exception"}, "=", [{"bwc": "catch"}, {
    "class": {"value": "borg.com/exception/assimilation"},
    "body":  [[{"var": "foo"}, "call"]]
}]]
```

Caspian equivalent:
```
$exception = catch('borg.com/exception/assimilation')
    &foo
end
```

<a id="raise"></a>
### raise

```json
[{"bwc": "raise"}, {"value": "borg.com/exception/assimilation"}]
```

Caspian equivalent: `raise 'borg.com/exception/assimilation'`

---

<a id="system-methods"></a>
## System Methods

~~~json
{"vibecode": {
	"section": "system_methods",
	"expression_form": "{\"sys\": \"name\"}",
	"call_pattern": "[receiver, method, args?]",
	"example_chain_set": "[{\"sys\": \"chain\"}, \"set\", {\"key\": ..., \"value\": ...}]"
}}
~~~

System methods appear as expressions using `{"sys": "name"}` and follow the same
`[receiver, method, args?]` call pattern:

```json
[{"sys": "chain"}, "set", {"key": {"value": "user"}, "value": {"value": "picard"}}]
```

Caspian equivalent: `%chain['user'] = 'picard'`

```json
[{"sys": "chain"}, "get", {"key": {"value": "user"}}]
```

Caspian equivalent: `%chain['user']`

---

<a id="documentation-statements"></a>
## Documentation Statements

~~~json
{"vibecode": {
	"section": "documentation_statements",
	"types": ["%vibecode", "%documentation"],
	"forms": {
		"vibecode": "{\"vibecode\": {...}}",
		"documentation": "{\"documentation\": {\"type\": \"text/markdown\", \"content\": \"...\"}}"
	},
	"runtime_behavior": "no_op"
}}
~~~

`%vibecode`, `%comment`, and other `%documentation` statements are saved as statement objects
in the program array. They are no-ops at runtime.

```json
{"vibecode": {"purpose": "assign the active officer collection"}}
```

```json
{"documentation": {"type": "text/markdown", "content": "## Notes\nSee the design doc."}}
```

---

<a id="source-position-annotations"></a>
## Source Position Annotations

~~~json
{"vibecode": {
	"section": "source_position_annotations",
	"purpose": "preserve_caspian_source_line_numbers_through_transpilation_to_caspianj",
	"use_case": "include_line_numbers_in_jasmine_log_entries_and_error_messages",
	"shape": "optional_line_field_on_caspianj_nodes"
}}
~~~

When Caspian source is transpiled to CaspianJ, **line-number
information from the original source is preserved** so that downstream
consumers (Jasmine logging, error messages, debuggers) can refer back
to the source position of any executing code.

The mechanism: each CaspianJ node optionally carries a **`line`**
annotation indicating the source line it came from.

```json
{"line": 42, "var": "foo"}
{"line": 42, "value": 1}
[{"line": 42, "var": "greet"}, "=", {"line": 42, "function": {"params": ["name"], "body": [...]}}]
```

The transpiler populates `line` on every emitted node. The runtime
preserves the annotation as it dispatches and can expose the current
executing position via runtime introspection — used by Jasmine for
log frame `location` fields (see
[jasmine.md](packages/jasmine/jasmine.md)), by error messages for "this error
happened at line N," etc.

<a id="what-gets-annotated"></a>
### What gets annotated

Every node emitted from a Caspian-source transpile carries a `line`
field. Granularity is per-statement at minimum and per-expression
where reasonable — enough that any runtime position can resolve back
to a source line.

<a id="caspianj-only-origins"></a>
### CaspianJ-only origins

Code that originated as CaspianJ directly (no Caspian source) has
**no `line` field** — there's nothing to annotate. Tools that inspect
positions check whether `line` is present; if it isn't, the source
position is genuinely unknown.

<a id="open-questions"></a>
### Open questions

- **File identifier alongside line.** Line numbers alone aren't
  enough to locate code; you also need to know which file. Probably
  a `file` field at the top of the CaspianJ program, or inherited
  from the runtime invocation context.
- **Column numbers.** Probably nice-to-have; verbose. Could be a
  `col` field alongside `line`.
- **Range annotations** (start line + end line) for multi-line
  expressions. Probably more than needed for v1; single line is
  sufficient for most purposes.
- **Generated code** — code emitted by macros or DSLs may want to
  carry both an original-source position AND a generator-source
  position. Out of scope for v1.

---

<a id="known-gaps"></a>
## Known Gaps

~~~json
{"vibecode": {
	"section": "known_gaps",
	"gaps": ["hash_key_order", "class_definitions_not_yet_designed_in_ksj"],
	"hash_key_order": "significant_two_hashes_equal_only_if_same_keys_same_values_same_order"
}}
~~~

<a id="hash-key-order"></a>
### Hash key order

Caspian hashes have significant key order — `{foo: true, bar: true}` and
`{bar: true, foo: true}` are distinct values. A compliant engine must preserve key
insertion order through serialization and deserialization.

---

<a id="open-questions-1"></a>
## Open Questions

<a id="class-definitions"></a>
### Class definitions

Class definitions in CaspianJ follow the same `[receiver, method, args]` pattern as
everything else. The class body statements (`field`, `inherits`, `function`, etc.) are
regular CaspianJ statements. The structure mirrors both Caspian source syntax and the
Mikobase JSON class definition — no special format is needed.
