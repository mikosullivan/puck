# KScript

## Overview

```
vibecode: {
	"section": "overview",
	"language": "KScript",
	"complements": "Q0",
	"q0_role": "query_and_filter",
	"kscript_role": "computation_and_control_flow",
	"development_history": "~20 years conceptual"
}
```

KScript is the programming language of the Kiera ecoverse. It handles computation and
control flow — the things Q0 deliberately does not do. Q0 is a query and filter language;
KScript is where actual programming lives.

KScript has been in development conceptually for approximately twenty years.

---

## Philosophy

```
vibecode: {
	"section": "philosophy",
	"core_principle": "everything_that_can_be_written_in_kscript_should_be",
	"lua_role": "interpreter_loop_memory_management_external_bindings_only",
	"exception": "move_to_lua_if_unwieldy_or_too_slow",
	"kernel_required": ["interpreter_loop", "gc", "core_bwcs",
		"primitive_types", "%object", "kiera.uno/helper",
		"system_methods_%call_%chain_%bucket"],
	"goal": "standard_library_written_in_kscript_visible_and_inspectable",
	"lua_reference_deps": ["SQLite", "libmicrohttpd"],
	"size_target": "500k_for_kscript_own_code_excluding_deps",
	"threading": "not_supported_single_threaded_by_design"
}
```

### KScript Written in KScript

Everything that can be written in KScript should be written in KScript. The Lua layer
exists for things that cannot be expressed in KScript at all — the interpreter loop,
memory management, external library bindings — not as a convenience for things that are
merely awkward to write in KScript.

The exception is pragmatic: if something could be in KScript but has become unwieldy or
too slow in practice, move it to Lua. Performance and maintainability are valid reasons
to drop down. But the default is always KScript first.

A compliant KScript engine must provide a minimal kernel:

- The interpreter loop
- Memory management and garbage collection
- Core bwcs: `if`, `while`, `and`, `or`, `not`
- Primitive types: string, number, boolean, null, array, hash
- `%object` — the root class, foundation of the object system
- `kiera.uno/helper` — the base helper class
- System methods: `%call`, `%chain`, `%bucket`

Everything built on top of these — `kiera.uno/loop`, exception classes, the standard
library, helper implementations — should be written in KScript where possible.

This makes much of the engine visible and inspectable. A developer who wants to understand
how a feature works can read KScript source rather than implementation source. Bugs in
the standard library are fixable without touching the host language.

#### Lua reference implementation

The Lua reference implementation provides the kernel above plus:

- Bindings to SQLite and libmicrohttpd
- Pattern matching via Lua's built-in pattern library

The KScript parser is a hand-written recursive descent parser written in KScript JSON
directly — this is the bootstrapping constraint. Once the parser is working, future
rewrites can use KScript.

### Dependencies (Lua reference implementation)

The Lua implementation requires Lua plus two C libraries:

- **SQLite** — used by the mikobase implementation; both `kiera.uno/mikobase/memory` (in-memory
  mode) and `kiera.uno/mikobase/sqlite` (file-backed mode) run on SQLite
- **libmicrohttpd** — embedded HTTP server powering `kiera.uno/mikobase/http` and
  `kiera.uno/mikobase/server`; handles concurrent connections at the C level

Performance concerns are addressed by optimizing the interpreter, not by abandoning
the principle.

### Error Messages

Sometimes complexity is unavoidable. When it is, the key to helping the developer is good
error messages. If something goes wrong, KScript should pinpoint the problem precisely and
explain the mistake clearly. A confusing error message is a bug.

---

## Design Principles

```
vibecode: {
	"section": "design_principles",
	"principles": ["lightweight_and_embeddable", "no_threading_or_forking",
		"timeouts_via_%timeout", "kscriptjson_as_runtime_format"],
	"embeddable_in": ["Python", "Ruby", "other_major_languages"],
	"sqlite_required": true,
	"timeout_mechanism": "debug.sethook_in_lua_fires_every_N_vm_instructions",
	"timeout_nested_budgeting": "min(requested, remaining_parent_budget)"
}
```

### Lightweight and Embeddable

The KScript interpreter must be embeddable in every major language (Python, Ruby, etc.)
as a library dependency. It ships with mikobase support built in, which means SQLite is a
required dependency. SQLite is ubiquitous — it is already present on virtually every
platform — so this barely counts as an external requirement.

KScript is not minimal in the way Lua is minimal, but it borrows Lua's discipline around
size. The target for KScript's own code is 500k, not counting external dependencies
(Lua, SQLite, libmicrohttpd). If the compiled size of KScript's own code exceeds 500k,
that is a red flag worth investigating. Every engine that runs KScript gets mikobase support,
the security model, and the full object system.

This matters because KScript will run inside engines — for dynamic firewall rules, trigger
records, and other engine-level logic. Every engine needs to run it.

### No Threading or Forking

KScript does not support threading, forking, or concurrency primitives. It is
single-threaded by design. The host language handles concurrency; KScript runs within a
single execution context.

This constraint keeps the interpreter small and predictable. Forking, mikobases, and the
threading model are features of KScript++ — see `ideas/plusplus/kscriptpp.md`.

### Timeouts

KScript does not use threads, but untrusted code must not be allowed to run indefinitely.
A function downloaded from a remote Kiera object — `%kiera['borg.com/riker']` — might
be an infinite loop or a crypto miner. The `%timeout` system method wraps a block with a
hard time limit:

```
%timeout(5) do
    &riker
end
```

If the block does not complete within the specified number of seconds, execution is
aborted. Whole-second granularity is used.

#### Spec: compliant engine requirements

A compliant engine must:

- Abort execution of the block if it does not complete within the specified number of
  seconds (whole-second granularity)
- Make the timeout undefeatable by KScript code — there must be no path from a KScript
  expression to the timeout mechanism
- Apply nested timeout budgeting: `effective_timeout = min(requested, remaining_parent_budget)`
- Handle blocking system calls — any system method that can block must implement its own
  timeout at the native level, since the interpreter-level timeout cannot fire during a
  native blocking call

#### Lua reference implementation

`%timeout` is implemented using `debug.sethook`. A hook is registered that fires every N
VM instructions and checks `os.time()` against the deadline. When the deadline is exceeded,
the hook raises an error that unwinds the block. After the block completes — whether
normally or via timeout — the hook is cleared. No threads are required.

KScript code cannot defeat this because `debug`, `load`, `os`, and the rest of Lua's
standard library are not reachable from KScript expressions. KScript is executed as
interpreted KScriptJSON — the runtime walks AST nodes through a controlled environment
with no path to arbitrary Lua functions.

### KScriptJSON as the Runtime Format

KScript programs are written in KScript and transpiled to KScriptJSON for execution.
KScriptJSON is easy to store, transmit, and parse in any language — which makes KScript
programs easy to ship around, embed in records, and process programmatically.

By convention, code is shared as KScript source. KScriptJSON is the runtime artifact,
not the distribution format.

Alternative syntaxes that transpile to KScriptJSON are possible but not encouraged. KScript
is the language; KScriptJSON is the wire format.

---

## Relationship to Other Systems

```
vibecode: {
	"section": "relationship_to_other_systems",
	"q0": "selects_and_filters_records_complementary_not_overlapping",
	"kiera": "kscript_is_programming_language_component_of_kiera_ecoverse",
	"kscriptjson": "runtime_format_kscript_compiles_to"
}
```

- **Q0** — KScript and Q0 are complementary. Q0 selects and filters records. KScript
  computes, controls flow, and implements behavior. They are not the same language and are
  not meant to overlap.
- **Kiera** — KScript is the programming language component of the Kiera ecoverse,
  alongside the Kiera object model and `kiera.uno/query`.
- **KScriptJSON** — The runtime format KScript compiles to. See [kscriptjson.md](kscriptjson.md).

---

## Primitives

```
vibecode: {
	"section": "primitives",
	"types": ["String", "Number", "Boolean", "Null", "Array", "Hash"],
	"strings": "utf8_immutable_encoded_at_engine_boundary",
	"hashes": "key_order_significant_equal_only_if_same_keys_values_and_order",
	"numbers": "no_int_float_distinction_single_number_type",
	"truthiness": "null_and_false_are_falsy_everything_else_truthy_including_0_and_empty_string",
	"null_true_false": "fully_instantiable_and_subclassable_classes",
	"null_flavors": "hl7_concept_subclass_kiera.uno/null_for_domain_specific_nulls"
}
```

### KScript as an Extension of JSON

Think of KScript as an extension of JSON. Primitives work like in JSON: strings, numbers,
booleans, null, arrays, and objects. KScript builds on these rather than introducing new
ones.

### Types

| Type | Examples |
|---|---|
| String | `'foo'`, `"foo"`, `:foo` |
| Number | `1`, `3.14`, `-7` |
| Boolean | `true`, `false` |
| Null | `null` |
| Array | `[1, 2, 3]` |
| Hash | `{key: 'value'}` |

### Strings

All strings in KScript are UTF-8. There is no other encoding. Strings are immutable —
operations on a string return a new string; the original is never modified.

Encoding is handled at the engine boundary, not in KScript code. A compliant KScript
engine must convert all incoming strings to UTF-8 before passing them to KScript.
The reference Lua implementation converts whatever encodings Lua natively supports.
Strings arriving in unsupported encodings should raise an error at the boundary.

### Hashes

Hash key order is significant. `{foo: true, bar: true}` and `{bar: true, foo: true}` are
distinct values. The order in which keys are written is the order in which they are stored
and iterated. Two hashes are equal only if they contain the same keys with the same values
in the same order.

This matters for serialization, comparison, and anywhere key order carries semantic weight
(e.g., field ordering in a record schema).

### Numbers

There is no distinction between integers and floats — there is only `number`. JSON makes
no such distinction, and neither does KScript. The interpreter handles numeric
representation internally, using integer or float arithmetic as appropriate for
efficiency.

### Truthiness

`null` and `false` are falsy. Everything else is truthy — including `0` and `''`.

### `null`, `true`, and `false` as Classes

In most languages, `null`, `true`, and `false` are global singletons whose underlying
classes cannot be instantiated. In KScript, the underlying classes are fully instantiable
and subclassable.

The bwcs `null`, `true`, and `false` always return a standard instance of their respective
classes. This behavior cannot be changed. But you can create instances directly:

```
$my_null = %kiera['null'].new
$my_null = %kiera['kiera.uno/null'].new   # same thing
```

**Truthiness is immutable.** Any instance of `kiera.uno/null` or its subclasses is always
falsey. Any instance of `kiera.uno/true` is always truthy. Any instance of `kiera.uno/false`
is always falsey. Subclassing or adding methods cannot change this.

### Null Flavors

The most compelling use case for subclassing `kiera.uno/null` is null flavors — a concept
from HL7, the healthcare data standard. In HL7, null values carry a reason: "unknown",
"not applicable", "masked for privacy", "not asked". Plain `null` loses this information;
null flavors preserve it.

In KScript, you can subclass `kiera.uno/null` to create domain-specific null types:

```
class 'myapp.com/null/unknown'
    inherits 'kiera.uno/null'
end

class 'myapp.com/null/not_applicable'
    inherits 'kiera.uno/null'
end
```

Instances of these classes are falsey in all conditionals, but carry type information
that code can inspect when needed:

```
$val = %kiera['myapp.com/null/unknown'].new

if($val)
    # never entered — $val is falsey
end
```

The same subclassing pattern applies to `kiera.uno/true` and `kiera.uno/false`, though
null flavors are the primary use case.

### Operators

The following operators are methods that any class can implement:

```
+  -  *  /  ==  !=  <  >  <=  >=
```

`1 + 2` is equivalent to `1.+(2)`. Classes can override these for custom types.

### Boolean Operators

`and`, `or`, and `not` are core bwcs implemented in Lua. They use short-circuit evaluation
and cannot be overridden. Symbol shortcuts:

| bwc | shortcut |
|---|---|
| `and` | `&&` |
| `or` | `\|\|` |
| `not` | `!` |

### Core bwcs

The following bwcs are implemented in Lua and cannot be overridden:

```
if    elsif (alias: elseif)    else    while
and   or    not
```

### `self`

`self` is a bwc shortcut for `%self`, which returns the current object instance.

---

## Variables

```
vibecode: {
	"section": "variables",
	"sigil": "$",
	"first_class": true,
	"variable_object": "$$foo returns variable object not value",
	"pass_by_reference": "intentionally_unsupported"
}
```

Variables are prefixed with `$`. They are first-class objects.

`$$foo` returns the variable object itself — distinct from `$foo`, which returns the value
the variable holds. Variable objects can be passed around like any other object. However,
the variable object deliberately does not expose its value. Pass-by-reference is an
intentionally unsupported pattern; the variable object's interface will be designed
around other use cases in the future.

---

## Exceptions and Warnings

```
vibecode: {
	"section": "exceptions_and_warnings",
	"hierarchy": ["kiera.uno/exception", "kiera.uno/exception/error",
		"kiera.uno/exception/return", "kiera.uno/exception/exit",
		"kiera.uno/exception/abort"],
	"return_implemented_as": "raising_kiera.uno/exception/return",
	"warnings": "propagate_without_unwinding_stack",
	"catch": "catch('class') block",
	"heed": "collects_warnings_heed('class') block",
	"abort": "capability_tied_to_scope_untrusted_code_cannot_abort_process"
}
```

### Exception Hierarchy

```
kiera.uno/exception
kiera.uno/exception/error
kiera.uno/exception/return
kiera.uno/exception/exit
kiera.uno/exception/abort
```

Exceptions and warnings share a common ancestor but are distinct mechanisms.

### Exceptions

Exceptions unwind the call stack until caught. Uncaught exceptions are fatal.

Returning from a function is implemented as raising `kiera.uno/exception/return`.
Function call boundaries automatically catch it and extract the return value. This means
early returns from nested blocks work naturally — no special non-local return machinery
needed, and the interpreter has one propagation mechanism for everything.

Exiting the program raises `kiera.uno/exception/exit`:

```
%process.exit
```

for which the shortcut is

```
exit
```

Exit is graceful — it unwinds the call stack, runs `close` on objects, and cleans up
before the process ends.

### Abort

Abort is a violent stop. The process terminates immediately. The call stack is not
unwound, `close` is not called on objects, and GC does not run.

```
%process.abort
```

Abort is a capability tied to the scope. The root scope has abort capability. Code
running inside `untrusted()` does not — calling `%process.abort` from untrusted code
raises `kiera.uno/exception/error` instead of terminating the process.

More precisely: `kiera.uno/exception/abort` propagates to scope boundaries. At a scope
boundary with abort capability, the process terminates. At a boundary without it — such
as an `untrusted()` boundary — the abort is caught and converted to an error. Execution
in the containing scope continues normally.

This means untrusted code can only abort itself, not the process that contains it.

### Catching Exceptions

To catch exceptions, use `catch()`.

```
$exception = catch('borg.com/exception/jolene', 'borg.com/exception/other')
    # code here
end
```

Catching everything:

```
$exception = catch()
    # code here
end
```

`$exception` is `null` if no exception is raised. If an exception is raised but doesn't
match, it continues bubbling up.


### Warnings

Warnings propagate up the call stack without unwinding it. Code continues executing
after a warning is raised. Warnings and exceptions are distinct — they share a common
ancestor class but do not share propagation behavior.

#### Heeding warnings

`heed` collects warnings raised in a block. By default, all `kiera.uno/warning`
subclasses are heeded and stop propagating once collected:

```
$warnings = heed()
    # code here
end
```

Heed specific warning classes:

```
$warnings = heed('borg.com/warning/validation')
    # code here
end
```

Allow warnings to continue propagating after being collected:

```
$warnings = heed(rewarn:true)
    # code here
end
```

Manually re-raise a collected warning:

```
$warning.warn
```

---

## Object Model

```
vibecode: {
	"section": "object_model",
	"two_properties": ["classes", "bucket"],
	"classes": "class_stack_array_resolved_top_down",
	"bucket": "%bucket hash shared by all classes in stack",
	"class_stack_order": ["shadow_class", "base_class", "additional_classes"],
	"object_helper": "reserved_built_in_cannot_be_overridden",
	"explicit_dispatch": "$class.object.call_with($foo, 'method', args)"
}
```

### Two-Property Objects

Every object has exactly two fundamental properties:

- **classes** — the class stack, an array of classes whose methods the object inherits
- **bucket** — a single shared hash where all the object's data lives

Everything else — methods, accessors, helpers — is behavior layered on top of these two
primitives. This maps directly to how mikobase records work: class + bucket. The mental
model is consistent across the language and the object store.

### `%bucket`

`%bucket` is a system method that returns the object's private data hash. All instance
data lives here.

```
%bucket['foo'] = 'bar'
%bucket['foo']          # 'bar'
```

`@foo` is shorthand for `%bucket['foo']`. The `property` declaration in a class creates
accessors that read and write from `%bucket`.

```
@foo = 'bar'             # same as %bucket['foo'] = 'bar'
```

All classes in the stack share the same `%bucket` hash. Key collision between classes
is the developer's responsibility.

Serialization is straightforward — `%bucket` is the object's data, so exporting it
exports the object's state.

### The Class Stack

Method calls are resolved top-down through the class stack:

1. **Shadow class** — a private class every object secretly inherits. Used to define
   methods on a single object without affecting the class. Always first in the stack.
2. **Base class** — the class the object was instantiated from.
3. **Additional classes** — any further classes added to the stack.

The first class in the stack that defines the method wins.

### The `object` Helper

Every object has a reserved helper called `object` that cannot be overridden. It exposes
meta information about the object:

```
$foo.object.classes      # the class stack array
```

More meta information will be added as needed.

### Explicit Class Dispatch

To call a method from a specific class in the stack, use `object.call_with`. The class
must be present in the object's class stack:

```
$class = $foo.object.classes.find(...)
$class.object.call_with($foo, 'greet', name: 'Jean-Luc')
```

This is a rare use case — normal method resolution handles the common case.

---

## Garbage Collection

```
vibecode: {
	"section": "garbage_collection",
	"model": "perfect_gc_immediate_collection_on_unreachable",
	"mechanism": "root_trace_not_reference_counting",
	"cycles": "handled_automatically",
	"close_method": "called_by_gc_not_user_code",
	"mikobase_objects": "not_subject_to_local_gc_mikobase_holds_them_alive",
	"two_rules": ["local_objects_die_when_unreachable", "mikobase_objects_live_while_mikobase_holds_them"]
}
```

### Perfect garbage collection

KScript uses what might be called perfect garbage collection: when an object becomes
unreachable, the runtime immediately collects it and calls a standard cleanup method on
it. There are no GC pauses, no periodic sweeps, and no tuning parameters. Collection
happens at a known, deterministic moment.

No weak references are needed. No special lifetime annotations. No manual memory
management.

### How it works

Objects live in object space. They do not know what references them — they simply exist
until nothing holds them.

When a reference to an object is severed, the runtime traces from roots to determine
whether the object is still reachable. If it is not reachable from any root, the runtime
calls the object's close method and collects it.

Because this is a root trace rather than reference counting, cycles are handled
automatically. Two objects that reference each other but are held by nothing else are
both unreachable from roots — both are collected.

### `$foo.object.close`

`close` is a standard method defined on every object. The runtime calls it when the
object is collected. User code cannot call it directly — it can only be invoked by the
garbage collector.

You can override `close` to do cleanup: release file handles, close network connections,
free external resources:

```
class 'myapp.com/connection'
    function &close()
        @socket.disconnect
    end
end
```

### Mikobase objects

Objects stored in a mikobase are not subject to local garbage collection. The mikobase holds them
alive — they exist for as long as the mikobase exists. This is the "objects are always alive"
guarantee of the mikobase model.

Garbage collection applies to mikobase objects in two cases:

1. **The mikobase itself goes out of scope.** The mikobase is collected, and `close` is called on
   each of its objects.
2. **An object is explicitly released from the mikobase.** The mikobase severs its reference to
   the object. If nothing else holds it, it is collected.

Dropping a local reference to a mikobase object does not affect the object. It remains alive
in the mikobase regardless of whether any local code is currently holding a reference to it.

### Why this simplifies the language

Most of the complexity in other GC systems comes from shared mutable state — objects that
are held by multiple things, passed around, and hard to reason about. In KScript, shared
state lives in the mikobase and has its own clear lifetime. Local objects are almost always
simple, short-lived, and unshared. The hard cases mostly do not arise.

The result is two rules that cover everything:

- **Local objects** die when they become unreachable from roots.
- **Mikobase objects** live as long as the mikobase holds them.

Every object in the system falls into one of those two cases.

---

## Helpers

```
vibecode: {
	"section": "helpers",
	"base_class": "kiera.uno/helper",
	"purpose": "namespace_methods_without_polluting_main_object_namespace",
	"access": "self.reference points back to parent object",
	"initialization": "lazy_not_created_until_first_accessed",
	"reserved_helper": "object built_in_present_on_every_object_cannot_be_overridden"
}
```

A helper is an instance of `kiera.uno/helper`. It provides a way to namespace methods
without polluting the main method namespace of an object.

The base helper class defines a single field: `@reference`, which points back to the
parent object. Inside a helper method, `self.reference` accesses the parent.

### Defining a helper

The `helper` bwc inside a class definition creates a lazily initialized helper:

```
$myclass = class
    helper foo
        function bar()
            return self.reference.gup
        end
    end
end

$myclass.foo.bar
```

This is shorthand for creating a helper class and a lazy getter that instantiates it
with `self` as the reference:

```
$myclass = class
    function foo()
        return @foo ||= $helper_class.new(self)
    end
end
```

The helper is not created until first accessed.

### `object` as a Reserved Helper

`object` is a built-in helper present on every object. It cannot be overridden. It is
the home for primitive introspection operations that are rarely needed day-to-day,
keeping them out of the main method namespace.

---

## Classes

```
vibecode: {
	"section": "classes",
	"identity": "from_reference_held_not_declared_name",
	"no_global_registry": true,
	"kiera_namespace": "%kiera[UNS] to access registered objects",
	"definition": "$myclass = %object.subclass do...end or class...end",
	"subclassing": "$new_class = $my_class.subclass do...end",
	"properties": "declared with property @foo :get :set default:",
	"abstract": "abstract true prevents direct instantiation",
	"initializer": "init method",
	"methods": "function name() inside class block"
}
```

Classes are objects. Like functions, they live wherever they are stored. There is no global
class registry and no namespacing system like `Foo::Bar`. A class's identity comes from the
reference held to it, not from a declared name. To use a class, you need a reference to it.

### `%kiera`

`%kiera` is a system method that provides access to the global Kiera object namespace.
`%kiera[UNS]` returns the object registered at that UNS address — which may be a class,
but is not limited to classes.

```
%kiera['kiera.uno/mikobase/memory'].new
%kiera['kiera.uno/mikobase/http'].new(mikobase: $mikobase, socket: '/var/run/myhive.sock', auth: :peer)
```

In the first version, `%kiera` only resolves a predefined set of built-in objects. When
and how remote objects can be retrieved via `%kiera` is a Kiera design question for later.

Class definition syntax is a DSL — it uses the same dispatcher/bwc mechanism as any
other DSL. There are no special parser rules for class definitions.

### Instantiation

```
$my_class.new(...)
```

### Defining a class

The official form subclasses `%object`, the root class:

```
$myclass = %object.subclass do
end
```

Shortcut for the same thing:

```
$myclass = class
end
```

Long-cut for those who prefer explicit inheritance syntax:

```
$myclass = class(inherit: %object)
end
```

### Subclassing

```
$new_class = $my_class.subclass do
end
```

This is the same pattern as subclassing `%object` — subclassing is always a method call
on the parent class object.

### Properties

Properties are private instance variables declared with `property`. They are not
accessible from outside the class unless accessors are declared.

```
property @foo                  # private, no external access
property @bar, :get            # creates a getter: bar()
property @gup, :set            # creates a setter: gup=()
property @baz, :get, :set      # creates both
property @foo, default: 'bar'  # with a default value
property @foo, :get, default: 'bar'  # accessor and default
```

`:get` and `'get'` are equivalent — `:foo` is shorthand for `'foo'` throughout KScript.

### Abstract Classes

A class declared `abstract true` cannot be directly instantiated. It must be subclassed.
Attempting to call `.new` on an abstract class raises an exception.

```
$myclass = class
    abstract true
end
```

### Initializer

`init` is the method called when a new instance is created. It is defined using
`function init(...)` inside the class block:

```
function init($name, $birthdate)
    @name = $name
    @birthdate = $birthdate
end
```

### Methods

Methods are defined inside the class block using `function name(...)`:

```
function greet()
    return "Hello, I am " + @name
end
```

### Full Example

```
$person = class
    property @name, :get
    property @birthdate, :get
    property @email, :get, :set
    property @active, default: false

    function init($name, $birthdate)
        @name = $name
        @birthdate = $birthdate
        @email = null
    end

    function greet()
        return "Hello, I am " + @name
    end
end

$p = $person.new(name: 'Jean-Luc', birthdate: '2305-07-13')
$p.greet   # "Hello, I am Jean-Luc"
```

### Subclass Example

```
$officer = $person.subclass do
    property @rank, :get

    function init($name, $birthdate, $rank)
        @rank = $rank
    end

    function greet()
        return @rank + " " + @name
    end
end
```

---

## Functions

```
vibecode: {
	"section": "functions",
	"first_class": true,
	"no_lambda_syntax": "all_functions_already_objects",
	"blocks": "do...end closure multiple_blocks_chained",
	"yielding": "$dispatcher.yield or yield shortcut",
	"bwc_resolution_order": ["reserved_bwcs", "dsl_entries", "scope_variables"],
	"dsl_receivers": "dispatcher.dsl maps bare words to objects in yielded block",
	"caller_objects": "$foo.caller reusable configurable pending call",
	"amp_method": "any_class_can_define_& to_make_instances_invokable"
}
```

Functions are first-class objects. They can be assigned to variables, passed as arguments,
and assigned to class methods. There is no concept of a named function — a function is just
an object stored somewhere. They live where they're stored.

There is no lambda syntax. In other languages, lambdas exist to create passable function
objects. In KScript, all functions are already objects.

See `kscript.md` for function definition and call syntax.

### Blocks and Yielding

A `do...end` block passed to a function call is a closure. Multiple blocks can be chained.
Inside the function, `%call.blocks` is an array of the passed blocks in order.

`do...end` is only intended for a short array of blocks. If you want to get fancy with
named blocks then pass them as named params.

The official way to call a block uses a dispatcher object:

```
$myfunc = function()
    $dispatcher = %call.dispatcher       # defaults to block at index 0
    $dispatcher = %call.dispatcher(1)    # explicit block index

    $dispatcher.yield 'gup', 'bear'
end

&myfunc do($a, $b)
    $a   # 'gup'
    $b   # 'bear'
end
```

`&dispatcher` is shorthand for `$dispatcher.yield`:

```
&dispatcher 'gup', 'bear'
```

`yield` is a top-level shortcut for `%call.dispatcher.yield`:

```
$myfunc = function()
    yield 'gup', 'bear'
end
```

Multiple blocks are chained with additional `do...end` after each `end`:

```
&myfunc do($a)
end do($b)
end
```

To yield to a specific block, use an explicit dispatcher index. `yield` always hits
block 0.

If you want named blocks, pass functions as named parameters instead.

### Bare Word Commands

A bare word command (bwc) is an unqualified word used as a method call. When the
interpreter encounters a bwc, it looks in `%scope` to find the correct association.

Resolution order:

1. **Reserved bwcs** — built-in keywords such as `if` and `while`. These cannot be
   overwritten under any circumstances.
2. **DSL entries** — set via `$dispatcher.dsl`. Evaluated before the incoming scope,
   so DSL mappings can override scope variables.
3. **Scope variables** — the normal lexical scope.

### DSL Receivers

The dispatcher object has a `dsl` hash. Entries map bare words inside the yielded block
to objects — a bwc resolves to a method call on the mapped object.

```
$myfunc = function()
    $dispatcher = %call.dispatcher
    $dispatcher.dsl['foo'] = $bar

    $dispatcher.yield
end

&myfunc do
    foo   # calls $bar.foo
    gup   # calls $bar.gup
end
```

DSL entries take priority over scope variables, making them suitable for overriding
default behavior inside a closure. Receivers are scoped to the closure call and do not
leak into the surrounding scope.

DSL settings do not propagate down the call stack. They apply only to the directly
yielded block — any nested function calls or blocks inside that block run without them.

---

## Scoping

```
vibecode: {
	"section": "scoping",
	"scope_per_block": true,
	"applies_to": ["if", "else", "loop_bodies", "bare_blocks"],
	"first_class_scopes": true,
	"closure_mechanism": "pass_scope_object_explicitly_to_function"
}
```

Every block creates a new scope that inherits from its parent. This applies to all blocks
without exception — `if`, `else`, loop bodies, and bare blocks all create new scopes.

Scopes are first-class objects. This is the mechanism by which closures are implemented:
a scope object can be passed explicitly to a function, making it act as a closure. There
is no special closure type — any function becomes a closure when passed a scope.

---

## System Methods

```
vibecode: {
	"section": "system_methods",
	"prefix": "%",
	"not": "global_variables",
	"behavior": "scope_aware_may_return_different_objects_in_different_scopes",
	"defined_by": "engine_at_boot_time_only",
	"key_methods": {
		"%chain": "ambient_context_carries_request_scoped_values",
		"%engine": "gateway_to_host_resources_top_level_only_non_capturable",
		"%call": "current_call_object_function_or_closure"
	}
}
```

KScript has a small number of system methods, prefixed with `%`. These are not global
variables — they are methods that return a scope-aware object. The same method call in
different scopes may return different objects.

System methods are defined only by the engine at boot time. User code cannot create new
`%`-prefixed methods.

### `%chain`

> **Use `%chain` sparingly.** It is ambient state that is invisible in function signatures
> and can carry security-sensitive information. Prefer explicit arguments when possible.
> The security implications of `%chain` are discussed separately.

`%chain` is the chain context object. It carries information down the call stack —
current user, request ID, locale, transaction context, security settings — without
requiring it to be threaded through every function signature.

`%chain` has two main components: `misc` for arbitrary values, and `stack` for the
call stack. It is scope-aware: values are inherited by child scopes and changes do not
propagate back up.

`%chain` is cleared when crossing a security boundary (untrusted execution, `%chain.clear`
blocks). stdout and stderr are **not** components of `%chain` — they are capabilities
injected by the host and passed explicitly, like any other resource.

#### Misc values

```
%chain.misc['foo'] = 'bar'
%chain.misc['foo']          # 'bar'
```

`%chain['foo']` is shorthand for `%chain.misc['foo']`.

#### Sandboxing

Each component can be cleared within a block, hiding it from code running inside:

```
# hide the call stack from untrusted code
%chain.stack.clear() do
    # %call does not have the full stack here
end

# hide misc values from untrusted code
%chain.misc.clear() do
    %chain['foo']   # null
end

# clear everything
%chain.clear() do
    # no stack, no misc values
end
```

After each block, the original values are restored. `%chain.clear()` will clear all
components, including any added in future.

#### Explicit scope block

`%chain.scope do...end` creates an explicit scope boundary:

```
%chain['foo'] = 'bar'

%chain.scope do
    %chain['foo']   # 'bar'
    %chain['foo'] = 'gup'
    %chain['foo']   # 'gup'
end

%chain['foo']       # 'bar'
```

#### Clean scope

`%chain.scope(inherit:false)` starts with an empty chain, inheriting nothing:

```
%chain['foo'] = 'bar'

%chain.scope(inherit:false) do
    %chain['foo']   # null
end

%chain['foo']       # 'bar'
```

---

### `%engine`

`%engine` is the gateway through which the top-level script accesses resources provided
by the host (capabilities, configuration, injected objects). It is only available in
top-level code — functions and closures cannot see it.

```
$db   = %engine['db']
$docs = %engine['docs']
```

The top-level script pulls what it needs from `%engine` and passes those resources down
to functions explicitly as parameters. This keeps inner functions isolated — they only
have access to what they are explicitly given.

**`%engine` is non-capturable.** The runtime will not allow it to be stored in a variable,
passed as an argument, or captured by a closure. Any attempt to do so raises an error.
This constraint will be revisited in the future.

---

### `%call`

`%call` returns the call object for the current function or closure. Inside a closure,
`%call` refers to the closure call. Inside a function, it refers to the function call.

```
function &foo()
    %call           # the call to foo

    &bar() do
        %call           # the call to the closure
        %call.return    # return from the closure
        return          # return from foo
    end

    %call.return    # return from foo
    return          # also return from foo
end
```

`%call.return` exits the current call (function or closure) and returns a value from it.
`return` always exits the calling function, propagating through closure boundaries.

`%call.blocks` is an array of `do...end` blocks passed to the current function, in order.

### Caller Objects

`$foo.caller` returns a caller object — a reusable, configurable pending call to `$foo`.
Parameters are set as properties, blocks are attached with `do`, and the call is executed
with `.call`.

```
$foo = function(gup)
end

$caller = $foo.caller
$caller.gup = 'bear'
$caller.call
```

Caller objects are first-class — they can be passed around, further configured, and
executed by whoever holds them. Setting a param before passing restricts what the receiver
needs to supply.

#### Setting params

```
$caller.gup = 'bear'
```

#### Attaching blocks

Official form:

```
$caller.foo = do
end
```

Shorthand (what The People will want):

```
$caller.foo do
end
```

Multiple anonymous blocks are available via `$caller.blocks`, which is an array. For
anything beyond simple cases, use named params instead.

#### Executing

```
$caller.call
```

Locking and freezing a caller before passing it around is deferred for later design.

---

### The `&` Method

Any class can define a `&` method to make its instances invokable with the `&` sigil.
`&` means "do the main thing on this object."

- Functions define `&` to call themselves
- Callers define `&` to execute their call
- Any other class can define `&` for its own main action

```
&my_function   # calls my_function.call
&my_caller     # calls my_caller.call
```

How to define a `&` method in a class definition is deferred until method definition
syntax is designed.

---

## Jail (Object Firewall)

```
vibecode: {
	"section": "jail",
	"concept": "capability_restricting_proxy_wraps_object_exposes_only_allowed_methods",
	"creation": "$foo.object.jail(:method1, :method2)",
	"storage": "prisoner and allowed in %bucket",
	"security_model": "object_capability",
	"callable_jail": "when prisoner is function jail with :call is callable"
}
```

A jail is a capability-restricting proxy object. It wraps another object and exposes only
a specified list of allowed methods. Calls to allowed methods are forwarded transparently
to the underlying object. Calls to any other method fail.

The underlying object is unaware that it is being called through a jail. However, a method
that explicitly inspects the call stack can see it.

Jail fits naturally with the object-capability security model: pass a jail instead of the
full object when the recipient only needs a subset of its capabilities.

### Internal structure

A jail stores the wrapped object in `%bucket`:

```
@prisoner   # the wrapped object
@allowed    # array of permitted method names
```

External code cannot reach `@prisoner` directly through the jail — that is the point.

### Creating a jail

```
$jail = $foo.object.jail(:greet, :save)

$jail.greet(name: 'Jean-Luc')   # forwarded to @prisoner
$jail.destroy                   # fails
```

When `@prisoner` is a function, the jail is callable:

```
$bar = $foo.object.jail(:call)
&bar   # forwards to @prisoner
```

---

## Freezing

```
vibecode: {
	"section": "freezing",
	"axes": ["classes", "bucket"],
	"operations": ["$foo.object.freeze", "$foo.object.classes.freeze",
		"$foo.object.bucket.freeze"],
	"permanent": "without_block_no_unfreeze",
	"temporary": "with_block_releases_when_block_exits",
	"classes_freeze_prevents": "class_stack_modification_shadow_method_definition",
	"bucket_freeze_prevents": "%bucket_writes",
	"object_bucket_returns": "jail_wrapping_%bucket_with_only_freeze_permitted"
}
```

Freezing locks an object against modification. KScript breaks this into two independent
axes — the class stack and bucket — rather than conflating them into a single freeze.

### The three freeze operations

```
$foo.object.freeze          # freeze both classes and bucket
$foo.object.classes.freeze  # freeze the class stack only
$foo.object.bucket.freeze  # freeze %bucket only
```

Any of these can be called by whoever holds a reference to the object — freezing is not
restricted to the object itself.

### Permanent vs. temporary

Without a block, a freeze is permanent. There is no `unfreeze` method. Once frozen, that
axis stays frozen for the lifetime of the object.

With a block, the freeze is temporary — it holds for the duration of the block and releases
when the block exits:

```
$foo.object.freeze do
    # both classes and bucket are frozen here
end

$foo.object.classes.freeze do
    # class stack is frozen here
end

$foo.object.bucket.freeze do
    # %bucket is frozen here
end
```

### What each freeze prevents

**Classes freeze** — the class stack cannot be modified. No classes can be added or
removed, and no shadow methods can be defined on the object. The methods the object has
at freeze time are the methods it will always have.

**Bucket freeze** — `%bucket` becomes read-only. Any attempt to write to `@foo` or
otherwise modify the bucket hash raises an error.

### `$foo.object.bucket`

`$foo.object.bucket` returns a jail wrapping `%bucket` with only `:freeze` permitted.
It gives external code the ability to freeze the object's bucket without exposing
the data itself:

```
$foo.object.bucket.freeze       # fine — one permitted operation
$foo.object.bucket['key']       # fails — not in the allowed method list
```

---

## Change Signals

```
vibecode: {
	"section": "change_signals",
	"trigger": "hash_key_assigned_new_object",
	"listener_api": "$foo.object.listen field: 'bar', :on_change do($change) end",
	"change_object_fields": ["field", "old_value", "new_value"],
	"propagation": "auto_up_through_every_object_holding_changed_object",
	"signal_stack": "central_one_at_a_time_in_single_threaded_model",
	"deduplication": "object_can_appear_on_stack_at_most_once",
	"lazy_check": "skip_signal_if_nothing_listens",
	"hot_records": "mechanism_behind_automatic_mikobase_saves_on_write"
}
```

### What a change is

A change is a hash key being assigned a new object:

```
$foo['bar'] = $something   # change event fires on $foo
```

Scalars do not change. Assigning `2` where `1` was does not change the number `1` — it
replaces a reference. Only hashes produce change events, because only hashes hold
references that can be reassigned.

### Listening to field changes

```
$foo.object.listen field: 'bar', :on_change do($change)
    # fires when $foo['bar'] is assigned a new object
end
```

The block receives a change object:

```
$change.field      # the key that changed ('bar')
$change.old_value  # the previous object
$change.new_value  # the newly assigned object
```

### Signal propagation

When a hash key is reassigned, the signal propagates automatically up through every
object that holds the changed object. Given:

```
$foo['bar']['gup']['baz']['bear'] = 1
```

1. `baz` changes → signals `gup` (which holds `baz`)
2. `gup` changes → signals `bar` (which holds `gup`)
3. `bar` changes → signals `foo` (which holds `bar`)
4. `foo`'s listener fires

Each object in the chain automatically re-signals its own listeners when it hears a
signal from an object it holds.

### The signal stack

Signals are processed through a central stack, one at a time, in order. In KScript's
single-threaded execution model, there is always either zero or one signal being
processed. This eliminates concurrent signal storms — a new signal is never processed
until the current one completes.

Three rules keep propagation tractable:

**Lazy check.** Before pushing a signal onto the stack, the system checks whether
anything listens to the changed object. If nothing is registered, the signal is skipped
entirely. Most objects have no listeners, so this makes the common case free.

**Deduplication.** An object can appear on the stack at most once. If a signal for an
object that is already on the stack is generated, it is dropped. This handles any
remaining cycle risk — a listener that reassigns a hash key can only trigger one
additional signal per object.

**Terminal listeners.** Most listeners do work and stop — they call `$foo.save`, write
to a log, update a counter. They do not reassign hash keys, so they generate no further
signals. Cycles only arise when a listener reassigns a hash key, which is the unusual
case.

### Underlying hot records

The change signal system is the mechanism that makes hot mikobase records work. When a hot
connection returns a record, the runtime automatically registers listeners up the
reference chain. A write anywhere in the chain triggers a save back to the mikobase without
the developer doing anything explicitly.

See [mikobase.md](../mikobase.md) for the hot record design.
