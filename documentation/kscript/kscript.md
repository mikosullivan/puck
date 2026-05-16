# KScript

## Overview

```
vibecode: {
	"section": "overview",
	"language": "KScript",
	"runtime_format": "KScriptJSON",
	"influences": ["Ruby", "Perl"],
	"conventions": ["share_as_kscript_not_ksj", "formatter_enforces_style"]
}
```

KScript is the programming language of the Kiera ecoverse. Programs are written in KScript
and transpiled to KScriptJSON for execution. KScriptJSON is the canonical runtime format;
KScript is the human-facing form.

KScript's style is influenced by Ruby with some Perl mixed in.

By convention, code is shared as KScript, not as KScriptJSON. KScriptJSON is a runtime
artifact, not a source format.

Formatting conventions (tabs vs. spaces, etc.) are enforced by the KScript formatter. The
community norm is: run your code through the formatter before complaining about formatting.

---

## Transpilation

```
vibecode: {
	"section": "transpilation",
	"target": "KScriptJSON",
	"notes": ["see_kscriptjson_md_for_format"]
}
```

KScript compiles to KScriptJSON. See [kscriptjson.md](kscriptjson.md) for the KScriptJSON
format.

---

## Strings

```
vibecode: {
	"section": "strings",
	"quote_styles": ["single_not_interpolated", "double_interpolated", "heredoc"],
	"colon_shorthand": ":foo == 'foo'",
	"bare_word_keys": "equivalent_to_string_keys_in_hashes_and_kwargs",
	"interpolation_forms": ["$variable", "#{}"],
	"heredoc_strips_leading_whitespace": true
}
```

### Default to single quotes

Use single quotes unless interpolation is needed. All documentation examples follow this
convention.

### Single-quoted strings

Not interpolated. What you write is what you get:

```
'hello world'
```

### Colon shorthand

`:foo` is shorthand for `'foo'`. No symbol type — just a convenient way to write short
strings:

```
:foo     # same as 'foo'
:get     # same as 'get'
```

### Bare word keys

Bare words used as hash keys or keyword argument names are also strings. All three forms
are identical:

```
{foo: 'bar'}
{'foo': 'bar'}
{:foo => 'bar'}
```

The same applies to keyword arguments in function calls:

```
&greet(name: 'Jean-Luc')    # name: is 'name'
```

Hash keys must be strings. Numbers, booleans, objects, and all other types are invalid as
hash keys — using one is an error.

### Double-quoted strings

Interpolated. Variables and expressions can be embedded:

```
"my name is $foo"
"my name is #{@name}"
"my name is #{&something}"
```

`$variable` interpolates directly. `#{}` interpolates any expression.

### Heredocs

```
$string = <<'EOF'
    indented content
EOF

$string = <<EOF
    same thing, no interpolation
EOF

$string = <<"EOF"
    interpolated: $foo
EOF
```

Leading whitespace is stripped to the least-indented line. If a developer mixes tabs and
spaces then that's sloppy and I won't take the blame for it. Ugly results will be their
own damn fault and they deserve it.

---

## Variables

```
vibecode: {
	"section": "variables",
	"sigil": "$",
	"variable_object": "$$foo returns variable object not value",
	"notes": ["pass_by_reference_unsupported", "variable_object_does_not_expose_value"]
}
```

Variables are prefixed with `$`, Perl-style:

```
$foo
$loop
```

`$$foo` returns the variable object itself. Variable objects can be passed around like any
other object, but deliberately do not expose their value. Pass-by-reference is an
intentionally unsupported pattern. Future use cases will be designed around this.

---

## Blocks

```
vibecode: {
	"section": "blocks",
	"closed_with": "end",
	"scope": "every_block_creates_new_inherited_scope",
	"applies_to": ["if", "else", "loop_bodies", "bare_blocks"]
}
```

Blocks are closed with `end`, Ruby-style. Every block creates a new inherited scope.
This applies to all blocks without exception — `if`, `else`, loop bodies, and bare blocks.

---

## When `do` is Required

```
vibecode: {
	"section": "do_keyword",
	"required_for": "block_passed_as_argument_to_function_call",
	"not_used_for": ["control_structures", "definitions"]
}
```

The `do` keyword marks **a block being passed as an argument to a function
call**. That is its only role.

**No `do` for control structures.** Their body follows the head directly:

```
if $foo == 'bar'
    # body of the if
end

while $foo
    # body of the while
end

begin
    # body of the begin
ensure
    # cleanup
end
```

**No `do` for definitions.** Same reasoning — the body is part of the
definition:

```
function &foo(x)
    # body
end

class 'foo.com/widget'
    # body
end
```

**`do` required for blocks passed to function calls.** Without `do`, the
parser has no way to know there's a block argument coming:

```
$server.get('/path') do($request)
    # block argument to .get()
end

catch('foo.com/exception/network') do
    # block argument to catch()
end

%utils.tempdir do($jail)
    # block argument to %utils.tempdir
end
```

**The distinction:**

- Control structures and definitions **own their body** as part of their
  syntax. There's no question that a body follows; no marker needed.
- Function calls **don't own a body** — they take arguments, including
  possibly a block. `do` is the marker that says "this is a block argument."

Pick one form and stick with it. Do not write `while $foo do ... end` or
`if $foo do ... end`. Ruby allows it; we don't. Keeps the rule clean:
**`do` means block-as-argument, nowhere else.**

---

## Statement Termination

```
vibecode: {
	"section": "statement_termination",
	"implicit_terminator": "newline",
	"explicit_terminator": "semicolon",
	"continuation_signals": ["trailing_comma", "trailing_binary_operator",
		"leading_dot", "leading_binary_operator"]
}
```

A statement is terminated by a newline. To put multiple statements on one line,
separate them with semicolons:

```
$foo = 1; $bar = 2; $foo + $bar
```

A statement can also span multiple lines via continuation. Lines continue when:

- **The line ends with a comma.** Implies more parameters or items are coming on
  the next line:

  ```
  %chain.error 'connection_refused', {
      host: 'db1',
      port: 5432,
  }
  ```

- **The line ends with a binary operator** (`+`, `and`, `==`, etc.).
- **The next line starts with a leading dot** (method chain continuation):

  ```
  $obj.foo
      .bar
      .baz
  ```

- **The next line starts with a binary operator.**

Outside these continuation signals, a newline ends the statement. The parser
doesn't need cleverness beyond these rules — they're the same rules Ruby and
similar languages use.

---

## Functions

```
vibecode: {
	"section": "functions",
	"callables": ["function", "closure"],
	"function_captures_scope": false,
	"closure_captures_scope": true,
	"sugar": "function &foo() == $foo = function()",
	"call_sigil": "&",
	"inline_do_blocks": "behave_like_closures",
	"remote_function": "delegates_to_%kiera.call"
}
```

### Definition

There are two kinds of stored callable: **functions** and **closures**. They differ in
whether they capture the lexical scope at the point of creation.

**Function** — does not capture outer scope:

```
$foo = function($a, $b) do
end
end
```

**Closure** — captures the lexical scope where it is defined:

```
$bar = closure($a, $b) do
end
end
```

Both forms use a `do ... end` block for the body. The parameters are the block params.
Outside variables are invisible to a function; a closure sees everything in scope at the
point it was created.

`function &foo()` is syntactic sugar for `$foo = function()`:

```
function &foo($a, $b) do
end
end
```

After any of these forms, `$foo` refers to the function object and `&foo` calls it.

### Inline do blocks

Inline `do` blocks passed to method calls (`.each`, route handlers, etc.) behave like
closures — they capture the outer lexical scope:

```
$x = 'hello'

$items.each($item) do
    puts($x)    # $x is visible
end
```

### Scope summary

| Form | Captures outer scope? |
|------|-----------------------|
| `$f = function(...) do ... end` | No |
| `$f = closure(...) do ... end` | Yes |
| `function &f(...) do ... end` | No (sugar for function) |
| inline `do ... end` block | Yes |

### Calling

The `&` sigil calls a function. All of the following are equivalent call forms:

```
&foo(1, 2)    # with parens
&foo 1, 2     # without parens
&foo()        # explicit empty call
&foo          # bare call, no arguments
```

`$foo` refers to the function object. `&foo` runs it. This distinction is intentional —
it makes passing functions as objects unambiguous.

### Remote functions

`remote function` declares a method that delegates to `%kiera.call`. It is shorthand
for an explicit remote dispatch — the two forms are equivalent:

```
# shorthand
remote function &save(name:)
end

# equivalent explicit form
function &save(name:)
    %kiera.call(self, :save, name: name)
end
```

`%chain` is forwarded automatically in both forms. See [kiera.md](../kiera/kiera.md)
for the full `%kiera.call` design.

---

## Classes

```
vibecode: {
	"section": "classes",
	"definition_keyword": "class",
	"class_name_format": "UNS",
	"schema_declarations": ["inherits", "abstract", "field", "join"],
	"field_types": ["built_in_string_names", "UNS_addresses"],
	"property": "bucket_backed_accessor_not_in_json_schema",
	"helper": "lazily_initialized_namespaced_sub_object"
}
```

### Definition

A class is defined with the `class` keyword and a UNS name. The block contains schema
declarations and method definitions:

```
class 'foo.com/character'
    inherits 'foo.com/person'

    field :name, class: :string, required: true, collapse: true
    field :age,  class: :number, min: 0, integer_only: true

    property :nickname

    function &greet(name:)
        'Hello, ' + name
    end
end
```

### Schema declarations

Schema declarations define the class's structure. They map directly to the JSON class
definition stored in the mikobase.

| Declaration | Description |
|---|---|
| `inherits 'UNS'` | Inherit from a parent class |
| `abstract true` | Prevent direct instantiation |
| `field :name, ...` | Declare a field |
| `join :a, :b` | Required, unique-in-combination, immutable fields |

### `field`

`field` declares a field with a name and keyword options. The options map directly to the
JSON field definition:

```
field :name,      class: :string, required: true, collapse: true
field :age,       class: :number, min: 0, integer_only: true
field :homeworld, class: 'kiera.uno/reference', allowed_class: 'foo.com/planet'
```

Built-in type names are strings — `:string` and `'string'` are identical. UNS names use
the quoted form by convention since they contain dots and slashes.

### `property`

`property` declares a `%bucket`-backed accessor — instance state that lives in the object,
not in the mikobase schema. It does not appear in the JSON class definition:

```
property :nickname
```

### Abstract classes

`abstract true` prevents direct instantiation. Subclasses may still be instantiated:

```
class 'kiera.uno/mikobase'
    abstract true
end
```

### Join classes

`join` marks the listed fields as required, unique in combination, and immutable after write:

```
class 'foo.com/appearance'
    field :person,  class: 'kiera.uno/reference', allowed_class: 'foo.com/person'
    field :episode, class: 'kiera.uno/reference', allowed_class: 'foo.com/episode'

    join :person, :episode
end
```

### Helpers

`helper` creates a lazily initialized helper object namespaced off the parent:

```
class 'foo.com/character'
    helper :stats
        function &average()
        end
    end
end

$character.stats.average
```

---

## Loops

```
vibecode: {
	"section": "loops",
	"naming": "as $loop binds loop object",
	"loop_object_methods": ["break", "next", "count", "active", "index"],
	"structural_blocks": ["before", "between", "after", "noloop"],
	"notes": ["structural_blocks_have_no_access_to_iteration_variable"]
}
```

### Basic loop with named loop object

Loops can be named with `as`. The loop object is scoped to the loop block by default.
To retain it after the loop, pre-declare the variable in the outer scope.

```
$bar.each($foo) as $loop
    print $loop.count   # current iteration, 1-based
    print $loop.active  # true while loop is running
end

$loop.active            # false after loop ends
$loop.count             # total iterations
```

### Loop object methods

| Method | Description |
|---|---|
| `$loop.break` | Exit the loop |
| `$loop.next` | Skip to next iteration |
| `$loop.count` | Current iteration number (1-based); total count after loop ends |
| `$loop.active` | `true` while running, `false` after loop ends |
| `$loop.index` | Current iteration index (0-based) |

### Structural blocks

Loops support optional structural blocks. None of these have access to the iteration
variable.

```
bar.each($foo)
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
| `between` | Once between each iteration (not before first, not after last) |
| `after` | Once after the last iteration |
| `noloop` | Only when the collection is empty |

---

## The `as` Keyword

```
vibecode: {
	"section": "as_keyword",
	"purpose": "bind_block_object_for_explicit_return_value_control",
	"syntax": "if (foo) as $if",
	"scope": "named_object_accessible_across_all_branches",
	"return": "$if.return 'value' or implicit last_statement"
}
```

Any block can be named with `as`. The name binds to a block object that gives explicit
control over the block's return value.

```
$gup =
    if (foo) as $if
        $if.return 'foo'
    elsif (bar)
        $if.return 'bar'
    else
        $if.return null
    end
```

`as` is declared on the opening statement of the construct. The named object is accessible
across all branches (elsif, else).

If `$if.return` is not called, the block returns the value of the last statement evaluated.
The `as` form is most useful when you need explicit control over the return value.

The same pattern applies to any block:

```
while(&foo) as $loop
    $loop.count
end
```

`$loop.return` exits the loop and returns a value. `$loop.break` exits without a value.

---

## Return and Emit

```
vibecode: {
	"section": "return_and_emit",
	"return": "exits_current_function_propagates_through_closures",
	"call_return": "%call.return exits current call only closure or function",
	"distinction": "return=exits_calling_function, %call.return=exits_current_call"
}
```

### `return`

`return` exits the current function, raising `kiera.uno/exception/return`. Inside a
closure, `return` propagates through the closure boundary and exits the calling function.

```
$my_closure = closure() do
    return 'something'   # exits the calling function, not the closure
end
```

### `%call.return`

`%call.return` exits the current call — function or closure — and returns a value from
it. Inside a closure, it exits the closure without affecting the calling function.

```
function &foo()
    &bar() do
        %call.return 'gup'   # exits the closure
    end

    return 'bear'            # exits foo
end
```

The distinction:
- `return` — exits the calling function (propagates through closures)
- `%call.return` — exits the current call only (closure or function)

---

## Safe Navigation

```
vibecode: {
	"section": "safe_navigation",
	"operator": "&.",
	"behavior": "short_circuits_to_null_if_receiver_is_null",
	"example": "$foo&.bar.gup"
}
```

`&.` is the safe navigation operator. If the receiver is `null`, the entire chain
short-circuits to `null` rather than raising an error:

```
$foo&.bar.gup        # null if $foo is null
$foo.bar&.gup.bear   # null if $foo.bar is null
```

---

## Pipe Operator

```
vibecode: {
	"section": "pipe_operator",
	"operator": "|",
	"null_safe_variant": "|&",
	"behavior": "passes_result_as_first_positional_arg_to_next_stage",
	"implementation": "syntactic_sugar_desugared_by_transpiler",
	"null_safe_note": "once_used_all_subsequent_stages_short_circuit_on_null"
}
```

The `|` operator chains operations left-to-right. Each stage passes its result as the
first positional argument to the next. Pipes are syntactic sugar — the transpiler desugars
them into ordinary nested calls in KScriptJSON.

### Basic pipe

```
&baz |
&bear |
$bar.gup
```

Desugars to:

```
$bar.gup(&bear(&baz))
```

Pipes can appear on the same line or split across lines:

```
&baz | &bear | $bar.gup
```

Both forms are identical. The multi-line form is preferred for long chains.

### Null-safe pipe (`|&`)

`|&` activates null propagation for the remainder of the chain. Once used, every
subsequent stage short-circuits to `null` if its input is `null`:

```
&foo |&
&bar |
&gup
```

If `&foo` returns `null`, the chain stops and returns `null`. If `&bar` returns `null`,
same. The `|&` switch applies to all remaining stages — you do not need to repeat it.

| Operator | Meaning |
|---|---|
| `\|` | Pass result to next stage |
| `\|&` | Pass result to next stage; enable null propagation for the rest of the chain |

---

## Unicode Method Names

```
vibecode: {
	"section": "unicode_method_names",
	"feature": "any_valid_unicode_identifier_allowed_as_method_name",
	"example": "$foo.√ is alias for square_root",
	"requirement": "compliant_engine_must_accept_unicode_method_names"
}
```

KScript identifiers, including method names, may contain Unicode characters. This allows
methods to be named with mathematical or symbolic notation where it improves readability.

The canonical example is the square root operator on Number:

```
$foo = 16
$foo.√     -> 4
```

`√` is a valid method name and an alias for `square_root`. A compliant engine must accept
any valid Unicode identifier as a method name.

---

## Method Naming Conventions

```
vibecode: {
	"section": "method_naming_conventions",
	"question_mark_suffix": "method returns truthy_or_falsey; truthy form is whatever's most useful",
	"examples": ["isa?", "null?", "defined?", "parse?", "timeout?"]
}
```

### The `?` suffix

The `?` suffix is a Kiera convention, not a language-enforced
contract — the kscript parser doesn't treat names ending in `?`
specially. It's a hint to readers about how a method behaves,
not a hook with semantics baked in. The convention is still
settling through use; the patterns below describe how it's
currently used, not a rule about what it must always mean.

Current usage clusters around methods that return a
**truthy-or-falsey result**, where the truthy form is often the
object itself rather than a bare `true`. Callers can typically
treat the call as a predicate (`if x.foo?`) regardless of what
the truthy form actually is.

Examples spanning the spectrum:

- **Bare-boolean form**: `obj.isa?('foo')`, `obj.null?`,
  `obj.defined?` — always returns `true` or `false`. These are
  pure predicates; the truthy form carries no extra payload.
- **Object-returning form**: `%utils.json.parse?(string)` —
  truthy is the parsed value (hash, array, etc.); falsey
  (null) means parsing failed. Producing the answer required
  producing the object anyway.
- **Operation-with-result form**: `%utils.timeout?(5) do ... end` —
  falsey (null) means the block completed normally; truthy is
  the timeout flag describing the failure.

A common pattern in current code: `method?` doesn't throw on
the failure path it's named for. Reach for the `?` form when
you expect failure sometimes and want to handle it as a value;
use the plain method when failure indicates a bug and should
propagate. This is a guideline drawn from how the convention
gets used today, not a contract — the convention will evolve as
more methods get written.

A method may have both forms (`parse` strict + `parse?`
tolerant). When both exist, they typically produce the same
successful result; only their failure behavior differs.

```
vibecode: {
	"section": "what_is_not_yet_designed",
	"status": "partial_spec",
	"notes": ["document_captures_decisions_made_so_far"]
}
```

Most of KScript is not yet fully specified. The above captures decisions made so far.
Further design will be added as KScript develops.
