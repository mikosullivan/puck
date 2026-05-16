# KScriptJSON

## Overview (Tora Klingon)

```
vibecode: {
	"section": "overview",
	"format": "KScriptJSON",
	"alias": "ksj",
	"purpose": "canonical_runtime_format_for_kscript_programs",
	"not": "bytecode",
	"convention": "share_as_kscript_source_ksj_is_runtime_artifact",
	"bootstrap_note": "parser_must_be_written_directly_in_ksj"
}
```

KScriptJSON (informally: ksj) is the canonical runtime format for KScript programs. It is
not bytecode — it is a full representation of the program as a JSON data structure. KScript
transpiles to KScriptJSON for execution.

KScriptJSON is a runtime artifact. By convention, code is shared as KScript source, not
as KScriptJSON.

The bootstrap parser must be written directly in KScriptJSON, since KScript cannot parse
itself before the parser exists.

---

## Core Principle (K'mtar)

```
vibecode: {
	"section": "core_principle",
	"statement_form": "[receiver, method, args?]",
	"receiver": "any_expression_variable_literal_sys_bwc_or_nested_call",
	"method": "string_naming_method_or_operator",
	"args": "optional_keyword_hash_or_single_positional_expression",
	"uniformity": "applies_to_method_calls_operators_assignment_and_bwc"
}
```

Every statement is an array: `[receiver, method, args?]`

- **receiver** — any expression: a variable, literal, system method, bwc, or nested call
- **method** — a string naming the method or operator
- **args** — optional; a hash of keyword arguments, or a single expression for positional calls

This applies uniformly to method calls, operators, assignment, and bwc calls.

---

## Comments (K'mtar Klingon)

```
vibecode: {
	"section": "comments",
	"form": "{\"comment\": \"...\"}",
	"behavior": "no_op_ignored_by_interpreter",
	"placement": "anywhere_in_statement_array"
}
```

A `{"comment": "..."}` object anywhere in a statement array is a human-readable no-op.
It is ignored by the interpreter.

```json
[
    {"comment": "greet the user"},
    [{"var": "name"}, "=", {"value": "Jean-Luc"}]
]
```

---

## Expressions (Drex II)

```
vibecode: {
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
}
```

Expressions are JSON objects that produce a value.

### Literals

```json
{"value": "hello"}
{"value": 42}
{"value": true}
{"value": null}
```

### Variables

```json
{"var": "foo"}        // $foo
{"ivar": "foo"}       // @foo  (%bucket['foo'])
{"varobj": "foo"}     // $$foo
{"sys": "chain"}      // %chain
```

### Bare Word Commands

A `{"bwc": "name"}` defers lookup to the runtime. The interpreter resolves the name
through the scope dispatcher to find the associated object and method. It is syntactic
sugar — it does not expand in KScriptJSON.

```json
{"bwc": "puts"}       // puts
{"bwc": "exit"}       // exit
```

### Array Literals

```json
{"array": [{"value": 1}, {"value": 2}, {"value": 3}]}
```

KScript equivalent: `[1, 2, 3]`

### Hash Literals

Hashes are represented as an array of `[key, expr]` pairs to preserve insertion order.

```json
{"hash": [["name", {"value": "Picard"}], ["rank", {"value": "Captain"}]]}
```

KScript equivalent: `{name: 'Picard', rank: 'Captain'}`

### Functions and Closures

```json
{"function": {"params": ["a", "b"], "body": [stmt, ...]}}
{"closure":  {"params": ["a", "b"], "body": [stmt, ...]}}
```

A `function` does not capture the outer scope. A `closure` does.

---

## Statements (Drex Mogh)

```
vibecode: {
	"section": "statements",
	"forms": ["assignment", "method_calls", "function_calls", "bwc_calls", "operators"],
	"assignment_form": "[{\"var\": \"foo\"}, \"=\", expr]",
	"method_call_form": "[receiver, \"method\", {kw_args}]",
	"function_call_form": "[{\"var\": \"foo\"}, \"call\", {kw_args}]",
	"operator_form": "[receiver, \"op\", operand]"
}
```

### Assignment

Assignment is the `=` operator — consistent with the `[receiver, method, args]` form.

```json
[{"var": "foo"}, "=", {"value": "hello"}]
```

KScript equivalent: `$foo = 'hello'`

```json
[{"var": "greeting"}, "=", [{"var": "foo"}, "+", {"value": " world"}]]
```

KScript equivalent: `$greeting = $foo + ' world'`

### Method Calls

```json
[{"var": "foo"}, "save"]
```

KScript equivalent: `$foo.save`

```json
[{"var": "foo"}, "greet", {"name": {"value": "Jean-Luc"}}]
```

KScript equivalent: `$foo.greet(name: 'Jean-Luc')`

Chained calls — the receiver of the outer call is the result of the inner:

```json
[[{"var": "foo"}, "bar"], "gup"]
```

KScript equivalent: `$foo.bar.gup`

### Function Calls

`&foo` calls the function object in `$foo`. This is a `call` method on the variable:

```json
[{"var": "foo"}, "call"]
```

KScript equivalent: `&foo`

```json
[{"var": "foo"}, "call", {"name": {"value": "Picard"}}]
```

KScript equivalent: `&foo(name: 'Picard')`

### Bare Word Command Calls

```json
[{"bwc": "puts"}, {"value": "hello world"}]
```

KScript equivalent: `puts 'hello world'`

```json
[{"bwc": "puts"}]
```

KScript equivalent: `puts`

### Operators

Operators are method calls. The left operand is the receiver, the operator is the method,
the right operand is the argument:

```json
[{"var": "foo"}, "==", {"value": "bar"}]
[{"var": "x"}, "+", {"value": 1}]
[{"var": "a"}, "&&", {"var": "b"}]
```

KScript equivalents: `$foo == 'bar'`, `$x + 1`, `$a && $b`

---

## Control Flow (Lukara)

```
vibecode: {
	"section": "control_flow",
	"constructs": ["if_elsif_else", "while"],
	"if_form": "[{\"bwc\": \"if\"}, {\"branches\": [...], \"else\": [...]}]",
	"while_form": "[{\"bwc\": \"while\"}, {\"cond\": expr, \"body\": [...]}]",
	"notes": ["branches_and_else_are_optional"]
}
```

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

KScript equivalent:
```
if ($rank == 'Captain')
    puts 'Aye, captain'
elsif ($rank == 'Commander')
    puts 'Aye, commander'
else
    puts 'Aye'
end
```

`branches` and `else` are both optional.

### While

```json
[{"bwc": "while"}, {
    "cond": [{"var": "i"}, "<", {"value": 10}],
    "body": [
        [{"var": "i"}, "=", [{"var": "i"}, "+", {"value": 1}]]
    ]
}]
```

KScript equivalent:
```
while ($i < 10)
    $i = $i + 1
end
```

---

## Blocks (Kahless I)

```
vibecode: {
	"section": "blocks",
	"form": "block key in args object",
	"structure": "{\"block\": {\"params\": [...], \"body\": [...]}}",
	"kscript_equivalent": "$items.each($item) do...end"
}
```

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

KScript equivalent:
```
$items.each($item) do
    puts $item
end
```

---

## Function and Closure Definitions (Mauk-to'Vor)

```
vibecode: {
	"section": "function_and_closure_definitions",
	"function_form": "{\"function\": {\"params\": [...], \"body\": [...]}}",
	"closure_form": "{\"closure\": {\"params\": [...], \"body\": [...]}}",
	"named_function_is": "assignment_of_function_to_var",
	"difference": "closure_captures_scope_function_does_not"
}
```

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

KScript equivalent:
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

KScript equivalent:
```
$greeter = closure($name) do
    puts $prefix + $name
end
```

---

## Return (Korath)

```
vibecode: {
	"section": "return",
	"form": "[{\"bwc\": \"return\"}, expr]",
	"no_value_form": "[{\"bwc\": \"return\"}]"
}
```

```json
[{"bwc": "return"}, {"var": "result"}]
```

KScript equivalent: `return $result`

Return with no value:

```json
[{"bwc": "return"}]
```

---

## Exception Handling (Korath Klingon)

```
vibecode: {
	"section": "exception_handling",
	"constructs": ["catch", "raise"],
	"catch_form": "[{\"var\": \"e\"}, \"=\", [{\"bwc\": \"catch\"}, {\"class\": ..., \"body\": [...]}]]",
	"raise_form": "[{\"bwc\": \"raise\"}, class_string_expr]"
}
```

### catch

```json
[{"var": "exception"}, "=", [{"bwc": "catch"}, {
    "class": {"value": "borg.com/exception/assimilation"},
    "body":  [[{"var": "foo"}, "call"]]
}]]
```

KScript equivalent:
```
$exception = catch('borg.com/exception/assimilation')
    &foo
end
```

### raise

```json
[{"bwc": "raise"}, {"value": "borg.com/exception/assimilation"}]
```

KScript equivalent: `raise 'borg.com/exception/assimilation'`

---

## System Methods (Drex Worf)

```
vibecode: {
	"section": "system_methods",
	"expression_form": "{\"sys\": \"name\"}",
	"call_pattern": "[receiver, method, args?]",
	"example_chain_set": "[{\"sys\": \"chain\"}, \"set\", {\"key\": ..., \"value\": ...}]"
}
```

System methods appear as expressions using `{"sys": "name"}` and follow the same
`[receiver, method, args?]` call pattern:

```json
[{"sys": "chain"}, "set", {"key": {"value": "user"}, "value": {"value": "picard"}}]
```

KScript equivalent: `%chain['user'] = 'picard'`

```json
[{"sys": "chain"}, "get", {"key": {"value": "user"}}]
```

KScript equivalent: `%chain['user']`

---

## Document Statements (Quvar)

```
vibecode: {
	"section": "document_statements",
	"types": ["%vibecode", "%document"],
	"forms": {
		"vibecode": "{\"vibecode\": {...}}",
		"document": "{\"document\": {\"type\": \"text/markdown\", \"content\": \"...\"}}"
	},
	"runtime_behavior": "no_op"
}
```

`%vibecode`, `%comment`, and other `%document` statements are saved as statement objects
in the program array. They are no-ops at runtime.

```json
{"vibecode": {"purpose": "assign the active officer collection"}}
```

```json
{"document": {"type": "text/markdown", "content": "## Notes\nSee the design doc."}}
```

---

## Source Position Annotations (Lurin)

```
vibecode: {
	"section": "source_position_annotations",
	"purpose": "preserve_kscript_source_line_numbers_through_transpilation_to_kscriptjson",
	"use_case": "include_line_numbers_in_jasmine_log_entries_and_error_messages",
	"shape": "optional_line_field_on_kscriptjson_nodes"
}
```

When KScript source is transpiled to KScriptJSON, **line-number
information from the original source is preserved** so that downstream
consumers (Jasmine logging, error messages, debuggers) can refer back
to the source position of any executing code.

The mechanism: each KScriptJSON node optionally carries a **`line`**
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
[jasmine.md](jasmine/jasmine.md)), by error messages for "this error
happened at line N," etc.

### What gets annotated

Every node emitted from a KScript-source transpile carries a `line`
field. Granularity is per-statement at minimum and per-expression
where reasonable — enough that any runtime position can resolve back
to a source line.

### KScriptJSON-only origins

Code that originated as KScriptJSON directly (no KScript source) has
**no `line` field** — there's nothing to annotate. Tools that inspect
positions check whether `line` is present; if it isn't, the source
position is genuinely unknown.

### Open questions

- **File identifier alongside line.** Line numbers alone aren't
  enough to locate code; you also need to know which file. Probably
  a `file` field at the top of the KScriptJSON program, or inherited
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

## Known Gaps (Pakled)

```
vibecode: {
	"section": "known_gaps",
	"gaps": ["hash_key_order", "class_definitions_not_yet_designed_in_ksj"],
	"hash_key_order": "significant_two_hashes_equal_only_if_same_keys_same_values_same_order"
}
```

### Hash key order

KScript hashes have significant key order — `{foo: true, bar: true}` and
`{bar: true, foo: true}` are distinct values. A compliant engine must preserve key
insertion order through serialization and deserialization.

---

## Open Questions (Lurin Pakled)

### Class definitions

Class definitions in KScriptJSON follow the same `[receiver, method, args]` pattern as
everything else. The class body statements (`field`, `inherits`, `function`, etc.) are
regular KScriptJSON statements. The structure mirrors both KScript source syntax and the
Mikobase JSON class definition — no special format is needed.
