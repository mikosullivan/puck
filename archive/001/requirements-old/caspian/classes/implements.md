# `implements?`

*Class-level structural API conformance check.*

~~~vibecode
{"vibecode": {
	"doc": "implements_method",
	"role": "spec for the class-level implements? method — checks whether one class structurally has every method another class declares, with matching parameter signatures. Runtime, structural, no separate interface concept. V1.0 in scope.",
	"audience": ["Caspian programmers writing precise type checks at module boundaries, in tests, or for user-supplied classes",
		"implementers of the class metaclass"],
	"v1_0_scope": "in scope",
	"key_concepts": ["structural_typing_runtime_check",
		"no_separate_interface_concept_classes_serve_as_api_specs",
		"strict_parameter_signature_match",
		"optional_method_subset_for_narrow_checks",
		"raise_on_malformed_subset"]
}}
~~~

`implements?` is a class-level method that checks whether one class **structurally** has every method another class declares.

```
$class       = %['foo.bar/gup']
$other_class = %['pan.bruh/blah']
$class.implements?($other_class)    # true if $class has every method $other_class does, parameterized the same way
```

The check is **structural and runtime**: no compile-time declaration, no separate interface concept, no registry of which class implements which. Any class can serve as the API spec; the comparison happens on demand at the call site.

`$class` may have additional methods beyond what `$other_class` declares — only the methods present in `$other_class` are checked. The question `implements?` answers is *"can I call every one of `$other_class`'s methods on an instance of `$class`?"*

---

## Parameter matching

Every Caspian method declares the parameters it accepts. **Two methods match iff their parameter declarations are identical** — same names, no extras, no missing. Caspian's params are keyword-only ([per project convention](../index.md)), so order doesn't matter at the call site; the *set* of declared param names must be the same.

This is a strict rule. Looser variants (allow `$class` to add optional params, allow extra defaults, etc.) are possible but not chosen for V1.0 — strict match keeps the semantics unambiguous and the check fast. Looser rules can be added as a separate option if real use shows the strictness is painful.

---

## Subset form

When the caller only cares about specific methods, the check can be narrowed:

```
$class.implements?($other_class, methods: ['foo', 'bar'])
```

Only `foo` and `bar` are compared. Same machinery, just iterates the named subset instead of all of `$other_class`'s methods. Useful for "I just need this thing to `foo` and `bar`; don't care what else it does."

**If a method name in the subset doesn't exist in `$other_class`, raise.** The caller is asserting "these methods are in `$other_class` and `$class` should match them"; if `$other_class` doesn't have one, the assertion is malformed. Fail loudly so the bug surfaces. Return-false would mask the error.

---

## Philosophy: duck-typing is the default

In most code you don't need `implements?`. You use the object until it fails — duck-typing in the Caspian style. The `implements?` method is for the rare case where a precise pre-check is wanted before committing to a call sequence: validating user-supplied classes, sanity-checking that a stubbed test class still tracks the real one, asserting at a module boundary that an incoming object can serve the role you need.

Caspian doesn't push toward over-validation. `implements?` exists as a tool for the situations that warrant it, not as a standard discipline applied everywhere.

---

## How this compares to other languages

| Language | Interface concept | Declaration | Check |
|---|---|---|---|
| Java | Separate `interface` keyword | Class explicitly says `implements Bar` | Compile-time + runtime `instanceof Bar` |
| Go | Interface as a named type | Implicit / structural; no declaration | Compile-time structural |
| Python | ABCs and duck-typing | Explicit (ABC) or implicit (duck) | Mostly runtime, often deferred to use |
| Caspian | **None — any class is its own API spec** | **None** | **Runtime, on demand via `implements?`** |

One concept (class), one method (`implements?`). To define an API contract, you write (or find) a class with the methods you want and use it as the reference in `implements?` calls. The "interface" is just another class — typically one written for that purpose, but no syntactic distinction from a regular class.

---

## Implementation notes

- **No new data structures.** Class metadata holds method names and parameter declarations — the engine needs them for dispatch anyway. `implements?` reads what's already there.
- **One new method** on the class type. Single shared implementation, not per-class state.
- **Compute is small.** For each method in `$other_class` (or the subset): look up by name in `$class`, compare param declarations. O(M × P) where M is method count and P is params per method.
- **Cacheable.** Results between two specific classes are stable as long as the classes are; a `(class_A, class_B)` → bool cache makes repeat checks effectively free.
- **No GC or role-boundary interaction.** Pure read over existing metadata; doesn't change dispatch, param validation, or role semantics.
