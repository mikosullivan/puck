# Charlie

<a id="overview"></a>
## 1 Overview

~~~json
{"vibecode": {
	"section": "overview",
	"language": "Charlie",
	"runtime_format": "CharlieJSON",
	"influences": ["Ruby", "Perl"],
	"conventions": ["share_as_charlie_not_ksj", "formatter_enforces_style"],
	"example_universe": "Shakespeare"
}}
~~~

Charlie is the programming language of the Puck ecoverse. Programs are written in Charlie
and transpiled to CharlieJSON for execution. CharlieJSON is the canonical runtime format;
Charlie is the human-facing form.

Charlie's style is influenced by Ruby with some Perl and Bash mixed in.

---

<a id="formatting-standards-or-lack-thereof"></a>
## 2 Formatting standards, or lack thereof

~~~json
{"vibecode": {
	"doc": "charlie",
	"section": "community_formatting_standards",
	"role": "establishes the community norm for Charlie code formatting — write however you want, reformat code you receive; sidesteps tabs-vs-spaces debates",
	"key_concepts": ["vs_code_formatter_extension", "format_however_you_want",
		"reformat_on_receive", "no_house_style"]
}}
~~~

To avoid debates about tabs-vs-spaces and other bickering, a
Charlie VS Code extension is available (link here when it actually
exists). That extension allows you to format Charlie to your own
preference. The rule is simple:


- Submit code formatted however you want.
- Run downloaded code through your formatter.

That's it. No house style, no enforced repo-wide config, no formatting nits in code
review. Tabs-vs-spaces is a settings file each developer owns, not a debate.

---

<a id="transpilation"></a>
## 3 Transpilation

~~~json
{"vibecode": {
	"section": "transpilation",
	"target": "CharlieJSON",
	"notes": ["see_charliejson_md_for_format",
		"surface_syntax_separated_from_runtime_form_to_keep_alternate_syntaxes_architecturally_open"]
}}
~~~

Charlie compiles to CharlieJSON. See [charliejson.md](charliejson.md) for the CharlieJSON
format.

Charlie is the **canonical surface syntax** — the one users see and write today. The
language architecture deliberately separates the surface syntax from the canonical
runtime form ([CharlieJSON](charliejson.md)), preserving the possibility of alternate
grammars that also transpile to CharlieJSON. To, for example, if you want a
grammar that looks like Python, you could design it:

~~~text
if $foo
	&do_something
~~~

Then just write some code that transpilers your grammar to CharlieJSON.

I don't have any plans to develop alternate grammars, but the options is
there if the community wants to develop it.

---

<a id="strings"></a>
## 4 Strings

~~~json
{"vibecode": {
	"section": "strings",
	"quote_styles": ["single_not_interpolated", "double_interpolated", "heredoc"],
	"colon_shorthand": ":foo == 'foo'",
	"bare_word_keys": "equivalent_to_string_keys_in_hashes_and_kwargs",
	"interpolation_forms": ["$variable", "#{}"],
	"heredoc_strips_leading_whitespace": true
}}
~~~

<a id="default-to-single-quotes"></a>
### 4.1 Default to single quotes

Use single quotes unless interpolation is needed. All documentation examples follow this
convention.

<a id="single-quoted-strings"></a>
### 4.2 Single-quoted strings

Not interpolated. What you write is what you get:

```
'hello world'
```

<a id="colon-shorthand"></a>
### 4.3 Colon shorthand

`:foo` is shorthand for `'foo'`.  Charlie does not have a symbol type,
but sometimes it's handy to have something look symboly.

```
:foo     # same as 'foo'
:get     # same as 'get'
```

<a id="bare-word-keys"></a>
### 4.4 Bare word keys

Bare words used as hash keys or keyword argument names are also strings. All three forms
are identical:

```
{foo: 'bar'}
{'foo': 'bar'}
{:foo => 'bar'}
```

The same applies to keyword arguments in function calls:

```
&greet(name: 'Hamlet')      # name: is 'name'
```

Hash keys must be strings. Numbers, booleans, objects, and all other types are invalid as
hash keys — using one is an error.

<a id="double-quoted-strings"></a>
### 4.5 Double-quoted strings

Interpolated. Variables and expressions can be embedded:

```
"my name is $foo"
"my name is #{@name}"
"my name is #{&something}"
```

`$variable` interpolates directly. `#{}` interpolates any expression.

<a id="heredocs"></a>
### 4.6 Heredocs

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
own fault and they deserve it.

---

<a id="variables"></a>
## 5 Variables

~~~json
{"vibecode": {
	"section": "variables",
	"sigil": "$",
	"variable_object": "$$foo returns variable object not value",
	"notes": ["pass_by_reference_unsupported", "variable_object_does_not_expose_value"]
}}
~~~

Variables are prefixed with `$`, Perl-style:

~~~charlie
$role     = 'Prince'
$name     = 'Hamlet'
$greeting = $role + ' ' + $name
puts $greeting               # Prince Hamlet
~~~

Once a variable is set, the `$` form refers to the value:

~~~charlie
$prince  = 'Hamlet'
$soliloquy = 'To be or not to be'
puts $prince + ': ' + $soliloquy
~~~

`$$foo` returns the variable object itself. Variable objects can be passed around like any
other object, but deliberately do not expose their value. Pass-by-reference is an
intentionally unsupported pattern. Future use cases may prpmpt us to revisit this
decision.

See [no nanny code](../overview.md#no-nanny-code) for the broader principle that keeps
"intentionally unsupported" decisions like this open to revisit.

---

<a id="blocks"></a>
## 6 Blocks

~~~json
{"vibecode": {
	"section": "blocks",
	"closed_with": "end",
	"scope": "every_block_creates_new_inherited_scope",
	"applies_to": ["if", "else", "loop_bodies", "bare_blocks"]
}}
~~~

Blocks are closed with `end`, Ruby-style. Every block creates a new inherited scope.
This applies to all blocks without exception — `if`, `else`, loop bodies, and bare blocks.

~~~charlie
# `if` block
if $role == 'King'
    puts 'My liege.'
end

# `while` block
while $count > 0
    $count = $count - 1
end

# Bare block — just `do ... end` standing on its own
do
    $sealed_letter = 'For Polonius, in confidence'
    puts $sealed_letter
end
~~~

**Inherited scope.** Variables defined in the outer scope are visible inside
the block:

~~~charlie
$courtier = 'Polonius'

if $at_court
    puts 'At court: ' + $courtier   # $courtier inherited from the outer scope
end
~~~

**New scope.** Variables defined *inside* a block stay inside — they are not
visible after the `end`:

~~~charlie
$prince = 'Hamlet'

if $prince == 'Hamlet'
    $play = 'Hamlet'
end

puts $play     # error — $play was scoped to the `if` block
~~~

To make a variable survive the block, declare it outside first:

~~~charlie
$play = null

if $prince == 'Hamlet'
    $play = 'Hamlet'
end

puts $play     # 'Hamlet'
~~~

---

<a id="multi-section-blocks"></a>
## 7 Multi-section blocks

~~~json
{"vibecode": {
	"section": "multi_section_blocks",
	"principle": "multi_boundary_blocks_are_acceptable_when_each_boundary_marks_a_distinct_structural_phase_of_the_constructs_run; not_when_boundaries_mark_conditional_alternatives",
	"kind_1_phase_markers_acceptable": ["loop_before_between_after_noloop",
		"begin_ensure_end_or_equivalent"],
	"kind_2_conditional_alternatives_avoid": ["if_elsif_else"],
	"rationale": "phase_markers_have_no_clean_replacement_outside_the_construct; conditional_alternatives_have_clean_replacements_via_sequential_ifs_or_lookup_tables_or_polymorphism"
}}
~~~

Charlie has constructs whose syntax breaks into multiple labeled
sub-sections inside a single `end` — `if` / `elsif` / `else`, loops
with `before` / `between` / `after` / `noloop`, `begin` / `ensure` /
`end`, and so on. (`elsif` and `elseif` are accepted as synonyms;
they transpile to the same CharlieJSON.) Whether such a shape is
desirable depends on **what kind of boundary** each label represents:

- **Phase-marker boundaries** — each section runs at a *different
  time* in the construct's lifecycle. The sections are orthogonal
  events, not alternatives. **Acceptable.**
- **Branch boundaries** — each section is a mutually exclusive *path*;
  only one runs. The sections are alternatives. **Avoid.**

Examples:

| Construct | Boundary kind | Status |
|---|---|---|
| Loops with `before` / `between` / `after` / `noloop` | Phase markers | Keep |
| `begin` / `ensure` / `end` (or whatever try/finally settles as) | Phase markers | Keep |
| `if` / `elsif` / `else` | Branch boundaries | Avoid |

**Why phase markers are fine.** The loop's `before` block runs once
before the body, `between` runs between iterations, `after` runs after
the last iteration. Each is tied to a structural event the loop
already tracks internally. Pulling these out of the loop and replacing
them with hand-rolled state — a flag for "first iteration," a counter
to know when to print "between," etc. — is uglier than keeping them
inside the construct. The phase markers are sugar over state the loop
already tracks. There's no clean alternative.

**Why branch boundaries are worth avoiding.** `if` / `elsif` / `else`
is sugar over `else if`, which is sugar over nesting. An if-elsif
chain can always be flattened into something that doesn't need
multiple boundaries inside one `end`:

- Sequential `if` blocks when conditions are independent
- A lookup table when branches are simple value-based dispatch
- Method dispatch or polymorphism when branches type-test
- Pattern matching if Charlie adds it (TBD)

The branch-boundary shape isn't *wrong*; the alternatives are
generally clearer.

**Applying the rule to future constructs.** When a new construct
introduces labeled sub-sections — a `match` statement with `case`
clauses, a state-machine block with named states, an HTTP handler
with `before` / `process` / `after` phases, anything else — the
question to ask is: **is each sub-section a phase the construct
itself runs through, or is it an alternative path the developer
chose?** If the former, multi-boundary syntax is fine. If the latter,
prefer a form where each path stands on its own.

---

<a id="when-do-is-required"></a>
## 8 When `do` is Required

~~~json
{"vibecode": {
	"section": "do_keyword",
	"required_for": "block_passed_as_argument_to_function_call",
	"not_used_for": ["control_structures", "definitions"]
}}
~~~

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

catch('foo.com/error/network') do
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

<a id="statement-termination"></a>
## 9 Statement Termination

~~~json
{"vibecode": {
	"section": "statement_termination",
	"implicit_terminator": "newline",
	"explicit_terminator": "semicolon",
	"continuation_signals": ["trailing_comma", "trailing_binary_operator",
		"leading_dot", "leading_binary_operator"]
}}
~~~

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

<a id="the-__end__-marker"></a>
## 10 The `__END__` Marker

~~~json
{"vibecode": {
	"section": "end_marker",
	"marker": "__END__",
	"behavior": "everything_after_is_ignored",
	"must_be": "at_start_of_line_optionally_with_trailing_whitespace",
	"must_not_be_inside": ["string_literal", "heredoc_body", "comment"],
	"data_access": "not_supported; trailing_content_is_discarded_entirely",
	"status": "spec_requirement_not_yet_implemented",
	"borrowed_from": ["perl", "ruby"]
}}
~~~

A line containing only `__END__` (optionally followed by trailing whitespace)
terminates the script. Everything in the file after that line is ignored by
the parser.

```
$foo = 'hello'
puts $foo
__END__
this and everything else in the file is ignored
```

Borrowed from Perl and Ruby, both of which use the same marker for the same
purpose.

<a id="rules"></a>
### 10.1 Rules

- **Must be at the start of a line.** `foo __END__ bar` on a single line does
  not trigger; the marker only fires when `__END__` is the first non-whitespace
  content on a line.
- **Must not be inside a string literal, heredoc body, or comment.** Inside
  those, `__END__` is literal text. The lexer suppresses the marker check
  while in those states.
- **Trailing whitespace allowed** on the marker line; anything else is not
  treated as a marker line.

<a id="what-charlie-doesnt-do"></a>
### 10.2 What Charlie doesn't do

Perl exposes post-`__END__` content via the `DATA` filehandle; Ruby exposes
it via the `DATA` constant. **Charlie discards the trailing content
entirely.** A future `__DATA__` marker could surface it if a use case shows
up, but `__END__` alone means "throw the rest away."

<a id="status"></a>
### 10.3 Status

Spec requirement; **not yet implemented in the canonical Lua engine.** The
change is small — a ~10–15-line addition in `lexer.lua` that emits EOF on
a top-level `__END__` line and suppresses the check while in
heredoc/string/comment state. No parser, transpiler, or interpreter
changes.

<a id="compliant-engine-behavior-for-the-unimplemented-state"></a>
### 10.4 Compliant-engine behavior for the unimplemented state

Until an engine implements `__END__`, it treats the marker as ordinary
input — i.e., as a bare identifier on a line, which is a parse error in
most positions. This is the expected behavior of any Charlie-conforming
engine that hasn't yet shipped `__END__`: not silent acceptance, not a
custom error class, just whatever the parser would normally do with
`__END__` as an unrecognized identifier in that position.

When an engine implements the feature, it follows the rules above
(top-of-line, not inside strings/heredocs/comments, trailing whitespace
ok) and discards content after the marker per the "What Charlie doesn't
do" section.

---

<a id="functions"></a>
## 11 Functions

~~~json
{"vibecode": {
	"section": "functions",
	"callables": ["function", "closure"],
	"function_captures_scope": false,
	"closure_captures_scope": true,
	"sugar": "function &foo() == $foo = function()",
	"call_sigil": "&",
	"inline_do_blocks": "behave_like_closures",
	"remote_function": "delegates_to_%puck.call"
}}
~~~

<a id="definition"></a>
### 11.1 Definition

There are two kinds of stored callable: **functions** and **closures**. They differ in
whether they capture the lexical scope at the point of creation.

**Function** — does not capture outer scope:

```
$foo = function($a, $b)
    # body
end
```

**Closure** — captures the lexical scope where it is defined:

```
$bar = closure($a, $b)
    # body
end
```

No `do` between the parameter list and the body — definitions own their body
directly (per [When `do` is Required](#when-do-is-required)). The
parameters are the function's parameters; outside variables are invisible to
a function; a closure sees everything in scope at the point it was created.

`function &foo()` is syntactic sugar for `$foo = function()`. The sigil form
is used both at top level and inside class blocks for method definitions:

```
function &foo($a, $b)
    # body
end
```

After any of these forms, `$foo` refers to the function object and `&foo` calls it.

<a id="inline-do-blocks"></a>
### 11.2 Inline do blocks

Inline `do` blocks passed to method calls (`.each`, route handlers, etc.) behave like
closures — they capture the outer lexical scope:

```
$x = 'hello'

$items.each($item) do
    puts($x)    # $x is visible
end
```

<a id="scope-summary"></a>
### 11.3 Scope summary

| Form | Captures outer scope? |
|------|-----------------------|
| `$f = function(...) ... end` | No |
| `$f = closure(...) ... end` | Yes |
| `function &f(...) ... end` | No (sugar for function) |
| inline `do ... end` block | Yes |

<a id="calling"></a>
### 11.4 Calling

The `&` sigil calls a function. All of the following are equivalent call forms:

```
&foo(1, 2)    # with parens
&foo 1, 2     # without parens
&foo()        # explicit empty call
&foo          # bare call, no arguments
```

`$foo` refers to the function object. `&foo` runs it. This distinction is intentional —
it makes passing functions as objects unambiguous.

<a id="remote-functions"></a>
### 11.5 Remote functions

`remote function` declares a method that delegates to `%puck.call`. It is shorthand
for an explicit remote dispatch — the two forms are equivalent:

```
# shorthand
remote function &save(name:)
end

# equivalent explicit form
function &save(name:)
    %puck.call(self, :save, name: name)
end
```

`%chain` is forwarded automatically in both forms. See [puck.md](../puck/puck.md)
for the full `%puck.call` design.

---

<a id="classes"></a>
## 12 Classes

~~~json
{"vibecode": {
	"section": "classes",
	"definition_keyword": "class",
	"class_name_format": "UNS",
	"schema_declarations": ["inherits", "abstract", "field", "join"],
	"field_types": ["built_in_string_names", "UNS_addresses"],
	"property": "bucket_backed_accessor_not_in_json_schema",
	"helper": "lazily_initialized_namespaced_sub_object"
}}
~~~

<a id="definition-1"></a>
### 12.1 Definition

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

<a id="anonymous-bare-class"></a>
### 12.2 Anonymous (bare) class

The UNS name may be omitted. A bare `class ... end` block produces an
**anonymous class** — a class with no UNS identity of its own. The class
is just a value the surrounding code captures (typically by assignment,
return, or the host that loaded the file):

```
class
    inherits 'puck.uno/robinson/page'

    function &process($request)
        response.html(200, '<h1>Hello</h1>')
    end
end
```

Anonymous classes are used where a class's identity comes from its
*location* rather than its UNS — e.g., Robinson page files (identified
by their path in the directory tree) and Robinson per-directory
handlers. `inherits` and the other schema/method declarations work
the same way as in named classes.

If an anonymous class needs to refer to itself, capture it in a
variable:

```
$page_class = class
    inherits 'puck.uno/robinson/page'
    ...
end
```

<a id="schema-declarations"></a>
### 12.3 Schema declarations

Schema declarations define the class's structure. They map directly to the JSON class
definition stored in the mikobase.

| Declaration | Description |
|---|---|
| `inherits 'UNS'` | Inherit from a parent class |
| `abstract true` | Prevent direct instantiation |
| `field :name, ...` | Declare a field |
| `join :a, :b` | Required, unique-in-combination, immutable fields |

<a id="field"></a>
### 12.4 `field`

`field` declares a field with a name and keyword options. The options map directly to the
JSON field definition:

```
field :name,      class: :string, required: true, collapse: true
field :age,       class: :number, min: 0, integer_only: true
field :homeworld, class: 'puck.uno/reference', allowed_class: 'foo.com/planet'
```

Built-in type names are strings — `:string` and `'string'` are identical. UNS names use
the quoted form by convention since they contain dots and slashes.

<a id="property"></a>
### 12.5 `property`

`property` declares a `%bucket`-backed accessor — instance state that lives in the object,
not in the mikobase schema. It does not appear in the JSON class definition. The first
argument is the sigil-prefixed instance-variable name; subsequent arguments are accessor
flags (`:get`, `:set`). Mechanically, the flags create getter/setter methods that read
from and write to `%bucket['<name>']`.

```
property @nickname              # private, no external access
property @nickname, :get        # creates a getter: $obj.nickname
property @nickname, :set        # creates a setter: $obj.nickname=()
property @nickname, :get, :set  # creates both
```

<a id="abstract-classes"></a>
### 12.6 Abstract classes

`abstract true` prevents direct instantiation. Subclasses may still be instantiated:

```
class 'puck.uno/mikobase'
    abstract true
end
```

<a id="join-classes"></a>
### 12.7 Join classes

`join` marks the listed fields as required, unique in combination, and immutable after write:

```
class 'foo.com/appearance'
    field :person,  class: 'puck.uno/reference', allowed_class: 'foo.com/person'
    field :episode, class: 'puck.uno/reference', allowed_class: 'foo.com/episode'

    join :person, :episode
end
```

<a id="helpers"></a>
### 12.8 Helpers

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

<a id="loops"></a>
## 13 Loops

All loop forms — `while`, `.each`, and the numeric iteration helpers
(`.times`, `.upto`, `.downto`) — and everything about them (loop
object via `as`, control methods, structural `before` / `between` /
`after` / `noloop` blocks) live in [loops.md](loops.md).

---

<a id="the-as-keyword"></a>
## 14 The `as` Keyword

~~~json
{"vibecode": {
	"section": "as_keyword",
	"purpose": "bind_a_handle_to_the_block_invocation; api_surface_depends_on_caller",
	"syntax": "block_declaration as $name",
	"placement_rule": "as_immediately_follows_the_block_declaration_not_the_receiver",
	"handle_richness": {
		"plain_method_call": "thin_closure_or_call_like_handle",
		"loop": "rich_loop_object_with_count_active_return_break_next",
		"if_elsif_else": "branch_handle_with_explicit_return"
	},
	"unifying_principle": "same_syntax_caller_decides_api_surface"
}}
~~~

`as $name` binds a **handle to the block's invocation**. The handle's
API surface depends on **who is calling the block** — same syntax, same
meaning ("give me a handle on this block"), different richness based on
context.

<a id="placement"></a>
### 14.1 Placement

`as $name` **always immediately follows the block declaration** — never
the receiver. Examples:

```
if (foo) as $if              # if/elsif/else block
while ($foo) as $loop        # while body (opens implicitly)
$bar.each($foo) as $loop     # block opened by .each
5.times do($i) as $loop      # explicit do(...) block
$foo.action do($i) as $call  # plain method call with do(...)
```

In the last two, `as` follows `do(...)` — not `5.times` or
`$foo.action`. The block is what `as` names.

<a id="handle-api-by-caller"></a>
### 14.2 Handle API by caller

The handle's methods depend on who's invoking the block. Three common
shapes:

| Caller | Handle is | Why |
|---|---|---|
| `if` / `elsif` / `else` | branch handle with `.return` | The block runs once; explicit return-value control is the useful affordance. |
| Loops (`while`, `.each`, `.times`, etc.) | **loop object** with `.count`, `.active`, `.index`, `.next`, `.return`, `.break` | The block runs repeatedly; iteration state and per-iteration control are the useful affordances. |
| Plain method call (`$foo.action do(...) as $X`) | thin closure/call-like handle (basically `%call`) | The block runs once at the method's discretion; only the basics are exposed. |

Same `as $name` form in all three cases. The difference in API is
genuine information about what kind of context the block is running in —
not a contradiction.

<a id="if-elsif-else"></a>
### 14.3 `if` / `elsif` / `else`

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

`as` is declared on the opening `if`. The named handle is accessible
across all branches (`elsif`, `else`). If `$if.return` is not called,
the block returns the value of its last statement.

<a id="loops-1"></a>
### 14.4 Loops

```
while (&foo) as $loop
    $loop.count
end
```

The loop object exposes `.count`, `.active`, `.index`, `.next`,
`.return`, and `.break` — see [loops.md § Loop object methods](loops.md#loop-object-methods).
`$loop.return` and `$loop.break` are aliases.

For the prefix-free `break` / `break N` bwc form (no `$loop` reference
needed; supports multi-level exit), see [loops.md § break](loops.md#break).

<a id="plain-method-call"></a>
### 14.5 Plain method call

```
$foo.action do($i) as $call
    $call.return $i + 1   # exit the block early with a value
end
```

For a one-shot block passed to an ordinary method, the handle is just
what the method needs to invoke and (optionally) accept a return value.
It's the same shape as the engine's `%call` reference.

---

<a id="return-and-emit"></a>
## 15 Return and Emit

~~~json
{"vibecode": {
	"section": "return_and_emit",
	"return": "exits_current_function_propagates_through_closures",
	"call_return": "%call.return exits current call only closure or function",
	"distinction": "return=exits_calling_function, %call.return=exits_current_call"
}}
~~~

<a id="return"></a>
### 15.1 `return`

`return` exits the current function, raising `puck.uno/return`. Inside a
closure, `return` propagates through the closure boundary and exits the calling function.

```
$my_closure = closure() do
    return 'something'   # exits the calling function, not the closure
end
```

<a id="callreturn"></a>
### 15.2 `%call.return`

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

<a id="safe-navigation"></a>
## 16 Safe Navigation

~~~json
{"vibecode": {
	"section": "safe_navigation",
	"operator": "&.",
	"behavior": "short_circuits_to_null_if_receiver_is_null",
	"example": "$foo&.bar.gup"
}}
~~~

`&.` is the safe navigation operator. If the receiver is `null`, the entire chain
short-circuits to `null` rather than raising an error:

```
$foo&.bar.gup        # null if $foo is null
$foo.bar&.gup.bear   # null if $foo.bar is null
```

---

<a id="pipe-operator"></a>
## 17 Pipe Operator

~~~json
{"vibecode": {
	"section": "pipe_operator",
	"operator": "|",
	"null_safe_variant": "|&",
	"behavior": "passes_result_as_first_positional_arg_to_next_stage",
	"implementation": "syntactic_sugar_desugared_by_transpiler",
	"null_safe_note": "once_used_all_subsequent_stages_short_circuit_on_null"
}}
~~~

The `|` operator chains operations left-to-right. Each stage passes its result as the
first positional argument to the next. Pipes are syntactic sugar — the transpiler desugars
them into ordinary nested calls in CharlieJSON.

<a id="basic-pipe"></a>
### 17.1 Basic pipe

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

<a id="null-safe-pipe"></a>
### 17.2 Null-safe pipe (`|&`)

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

<a id="unicode-method-names"></a>
## 18 Unicode Method Names

~~~json
{"vibecode": {
	"section": "unicode_method_names",
	"feature": "any_valid_unicode_identifier_allowed_as_method_name",
	"example": "$foo.√ is alias for square_root",
	"requirement": "compliant_engine_must_accept_unicode_method_names"
}}
~~~

Charlie identifiers, including method names, may contain Unicode characters. This allows
methods to be named with mathematical or symbolic notation where it improves readability.

The canonical example is the square root operator on Number:

```
$foo = 16
$foo.√     -> 4
```

`√` is a valid method name and an alias for `square_root`. A compliant engine must accept
any valid Unicode identifier as a method name.

---

<a id="method-naming-conventions"></a>
## 19 Method Naming Conventions

~~~json
{"vibecode": {
	"section": "method_naming_conventions",
	"question_mark_suffix": "method returns truthy_or_falsey; truthy form is whatever's most useful",
	"examples": ["isa?", "null?", "defined?", "parse?", "timeout?"]
}}
~~~

<a id="the-suffix"></a>
### 19.1 The `?` suffix

The `?` suffix is a Puck convention, not a language-enforced
contract — the Charlie parser doesn't treat names ending in `?`
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

~~~json
{"vibecode": {
	"section": "what_is_not_yet_designed",
	"status": "partial_spec",
	"notes": ["document_captures_decisions_made_so_far"]
}}
~~~

Most of Charlie is not yet fully specified. The above captures decisions made so far.
Further design will be added as Charlie develops.
