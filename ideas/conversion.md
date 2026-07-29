# Idea: conversion

~~~vibecode
{"vibecode": {
	"doc": "conversion",
	"role": "brainstorm — a formal, universal object-conversion protocol for Caspian. Every class exposes `.to` on instances and `.from` on the class object. Named forms (`.to.number`, `.from.string`) are the ergonomic entry points; argument forms (`.to($class)`, `.from($instance)`) are the general mechanism. Two-step lookup — source first, target second — lets either party implement the conversion without needing to modify the other. Predicate forms `.to?` and `.from?` enable safe discovery.",
	"status": "brainstorm — shape is settled; specific registration syntax, subclass-target behavior, and both-sides-defined resolution are still to work out"
}}
~~~

Most languages leave object conversion **ad hoc**: each class invents its own conversion method names, and there's no protocol to discover or standardize the surface. Python has `__str__` / `__int__` / `__float__` (source-side only) alongside `str()` / `int()` / `float()` constructors (target-side, but not part of a discoverable protocol). Ruby has `to_s` / `to_str` / `to_i` with an unspoken "explicit vs implicit" distinction. Rust has `From` / `Into` with orphan rules that constrain who can define what. In every case, the language and library ecosystem end up with a **grab bag of conversion patterns** that a reader has to memorize per class.

Caspian's shape: **one universal conversion protocol**, symmetric on both sides.

## The two sides

- **On an instance**, `.to` is a helper that names conversions the instance knows how to perform. `$foo.to.number` reads as "give me a number representation of `$foo`."
- **On a class**, `.from` is a helper that names constructions the class knows how to accept. `Number.from.string` reads as "give me a way to build a Number from a string."

Since classes in Caspian are first-class objects, `.from` is a normal method on the class object, not a new "class method" concept.

## Named and argument forms

Each side has two forms — a **named form** for the common case, and an **argument form** for the general case.

**Named form** — the target class or source class is baked into the method name:

~~~caspian
$s = '1234'
$n = $s.to.number             # instance-side: "convert to number"

$s = '1234'
$n = Number.from.string($s)   # class-side: "build from a string"
~~~

**Argument form** — the class is passed as a runtime value:

~~~caspian
$my_target = Number
$n = $s.to($my_target)        # dynamic target

$my_source = $s
$n = Number.from($my_source)  # dynamic source
~~~

The named form is likely sugar for the argument form (`.to.number` desugars to `.to(Number)`); confirming that unification lands in the spec.

## Lookup protocol

When you call `$foo.to($some_class)`, Caspian runs a two-step lookup:

1. **Does the instance's class have a conversion method for `$some_class`?** If yes, run it, return the new object.
2. **Does `$some_class` have a `.from($foo)` method?** If yes, run it, return the new object.
3. If neither, raise.

The **source is checked first**. Rationale: the source often knows more about its own state than the target does about the source's shape. But the target-fallback is what makes the protocol usable — a library author adding a new class can implement `.from` for existing source types without needing to modify those source classes. That solves the "who owns the conversion?" problem that plagues most language ecosystems.

## Discovery via predicates

`.to?` and `.from?` are the safe-check predicates. They return `true` if the corresponding conversion is available, `false` otherwise. No exceptions.

~~~caspian
$foo.to?($some_class)          # true if $foo can be converted to $some_class
$some_class.from?($foo)        # true if $some_class can be built from $foo
~~~

Predicates are essential for generic code (serializers, coercion frameworks, DSLs) that wants to branch based on whether a conversion exists without wrapping every call in an exception handler.

The predicates also enable **discovery of the whole conversion graph**. `$foo.to.methods` (or `.to.classes`) lists everything this instance can be converted to; `Number.from.methods` lists everything Number can be built from. Together those two enumerations let a program walk the conversion graph in either direction.

## Worked example: string ↔ number

Two paths that produce the same value:

~~~caspian
$s = '1234'

# Source declares the conversion.
$n1 = $s.to.number             # asks String

# Target declares the construction.
$n2 = Number.from.string($s)   # asks Number

$n1 == $n2                     # true; both are Number(1234)
~~~

Either path works whether String has `.to.number` OR Number has `.from.string` implemented — the protocol's two-step lookup finds the one that exists.

## Comparison

| Language | Source-side | Target-side | Discoverable? | Notes |
|---|---|---|---|---|
| Python | `__str__`, `__int__`, `__float__` | `str()`, `int()`, `float()` (constructors) | Partially (via `dir()`) | No protocol linking the two sides. |
| Ruby | `to_s`, `to_str`, `to_i` | `String()`, `Integer()` (Kernel methods) | No | "Explicit" vs "implicit" convention is unwritten. |
| Rust | `From`, `Into` (trait impls) | Same traits | Yes, via traits | Orphan rules restrict who can implement. |
| Caspian | `.to` on instance | `.from` on class | Yes, via `.to?` / `.from?` and `.methods` | Either side can add the conversion; no orphan constraint. |

## Open questions

- **Registration syntax.** How does a class body declare that it provides `.to.number` or `.from.string`? Candidate shapes: a `method &to.number() ... end` block on the class, a separate `converts_to number ... end` declaration, or something else. TBD.
- **Both-sides-defined resolution.** If both `String.to.number` and `Number.from.string` are defined, the lookup protocol picks source-side. Silent behavior when they disagree may warrant a warning at class-load time.
- **Subclass targets.** When calling `$foo.to(Number)` and `Number` has subclasses (Binary, Octal, Hex, Decimal), does the returned instance default to Decimal, or does the source get to pick? Probably the source picks (since the source's method runs the conversion), but the rule wants to be explicit.
- **Argument shape on `.from`.** Named form `.from.string(...)` takes the source as an argument. Does argument form `.from($foo)` need a second argument for context? Or is the source-instance always the first argument?
- **Composition.** Whether `.to.X.to.Y` reads as "convert to X, then convert to Y" is trivially yes given the shape, but call sites that want a specific target-of-target may prefer `$foo.to(Y)` with an intermediate step handled by a `.from` that itself uses `.to`. Not urgent.
- **Whether the ergonomic `.to_dec`, `.to_bin`, etc. methods** already spec'd on Number and String coexist with `.to.decimal`, `.to.binary`, etc. under this protocol, or migrate to the new form entirely.
