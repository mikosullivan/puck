# Nested methods

~~~json
{"vibecode": {
	"doc": "nested_methods",
	"role": "design notes on nested methods — methods grouped under a namespace path on a class. Replaces the older helper-as-sub-object model with namespaces-as-pure-organization. The .object namespace is the canonical example: it holds the universal-introspection methods so user classes don't inherit them into their top-level namespace.",
	"status": "active_design",
	"audience": "Miko and Claude collaborating on the design",
	"related": ["requirements/caspian/lucy/index.md (helpers — the older model this replaces)",
		"requirements/ecoverse/objects/index.md (object structure)",
		"requirements/ecoverse/worldlets/worldlet.json (records.b shows a 'beverage.nested.tea_earl_grey_hot' shape)"]
}}
~~~

## Core idea

A nested method is a method declared under a namespace path on its class. Calling `$foo.bar.gup()` dispatches `gup` from the `bar` namespace on `$foo`'s class. The namespace is **organizational only** — no sub-object is created, `self` inside `gup` is `$foo`, and `gup` has the same access to `$foo`'s bucket and other methods that a top-level method would.

This replaces the older helper-as-sub-object model documented in [caspian/lucy/index.md § Helpers](../requirements/caspian/lucy/index.md#helpers). Under that model, `$foo.bar` returned a separate object holding a backreference to `$foo`, and helper methods could only reach back into the parent through that backreference's public surface. The new model collapses that: `$foo.bar` is no longer an object, it's a name prefix.

## Why namespaces exist

~~~json
{"vibecode": {
	"section": "why_namespaces_exist",
	"role": "preserves the original motivation for the mechanism: keep base-class universal methods out of the way so user classes get a clean top-level namespace for their own methods"
}}
~~~

The original purpose of helpers — and now of namespaces — is **to keep the universal infrastructure methods out of the user's namespace.**

Every Caspian object derives from `puck.uno/object`, which provides a substantial set of universal operations: tri-value truthiness (`bool`, `truthy?`, `null?`, `defined?`), identity, role introspection, classes-stack inspection, the close-handler mechanism, and more. If those methods sat directly on every object, a trivial user class with one defined method:

~~~caspian
class 'myapp.com/connection'
    function &send($msg)
        ...
    end
end
~~~

would expose **fifteen-plus methods** at the top level — only one of which the user wrote. Auto-completion clutters; the namespace of "what this thing does" drowns in inherited infrastructure.

The fix: put all of the universal operations under a single namespace, conventionally `object`. So `$conn` exposes exactly two names at its top level — `.send` (what the user wrote) and `.object` (the universal-method namespace). The universal cloud is reachable but namespaced away.

This is the load-bearing reason the mechanism exists. Method-namespacing for user classes (like a `metrics` or `transport` cluster) is the same machinery applied to user-driven organization, but the original — and ongoing — purpose is keeping base-class methods from polluting every class's top-level surface.

## `.object` is a namespace

~~~caspian
$foo.object.bool          # tri-value truthiness
$foo.object.truthy?       # bool predicate
$foo.object.null?         # null predicate
$foo.object.classes       # the platter stack
$foo.object.role          # current role
$foo.object.on_close ...  # close-handler introspection
~~~

Under the new model, `$foo.object` is a name prefix into the `object` namespace. The dispatcher walks the path `object.<method>` and finds the method definition; the method runs with `self = $foo`. Identical to how any user-defined namespace would work.

## What's gained vs the helper-sub-object model

- **No boilerplate accessors.** Old model forced classes to expose getters/setters just so the helper could see state. Now a method inside any namespace reads `@bucket['x']` directly.
- **No fake encapsulation barrier between same-class methods.** Conventional across Ruby, Python, Java, etc.: methods of the same class see each other's state. The old helper model put an unusual sub-API barrier in the way for nested concerns. The new model aligns with the common mental model.
- **One identity, one bucket, one trust boundary** per object. The namespace path doesn't carve out a distinct identity for `$foo.object`; it's just a route through `$foo`'s method table.
- **Lazy instantiation goes away.** No sub-object means nothing to instantiate. The namespace exists in the class definition; method lookup is a path walk at dispatch time.

## What's given up

- **The old model offered encapsulation as a side effect.** If you wanted "nested methods that can only see the parent's public surface," that came for free. With namespaces, encapsulation is no longer automatic; you'd have to build a separate-class-with-a-reference pattern explicitly if you wanted that boundary.
- **`.object` as object-of-its-own goes away.** Previously, `$foo.object` was itself an object, with its own identity. Some patterns leaned on this — `$foo.object == $bar.object` for "same object" comparison, for example. Under the new model, `$foo.object` isn't a thing of its own anymore; it's a name prefix. Identity-equality comparisons need a different mechanism (a method that returns an engine-generated object-id value, or a `same_object?` operation).

## JSON shape

The class's `methods` block is a nested hash. The `"nested"` key on a hash value is the discriminator that distinguishes "namespace" from "method definition":

~~~json
"methods": {
    "send": {
        "description": "...",
        "params":      {...},
        "body":        "..."
    },
    "beverage": {
        "nested": {
            "tea_earl_grey_hot": {"description": "...", "params": {...}, "body": "..."},
            "coffee_black":      {"description": "...", "params": {...}, "body": "..."}
        }
    }
}
~~~

- A hash with `"params"` / `"body"` / etc. is a method definition.
- A hash with `"nested"` is a namespace; its `"nested"` value is itself a methods-block hash (recursive — namespaces can contain namespaces).

This is the shape already showing up in [worldlets/worldlet.json](../requirements/ecoverse/worldlets/worldlet.json) on the officer class.

## Dispatch mechanism

For a call like `$foo.bar.gup(args)`:

1. Walk `$foo`'s class stack (top-down, per the [method dispatch rule](../requirements/ecoverse/objects/method-resolution.md#method-dispatch)) looking for a class that has the path `bar.gup` defined.
2. Within each class, traverse `methods.bar.nested.gup`. If found, that's the method.
3. If a class has `bar` declared but it's a method (not a namespace), the path doesn't match — keep walking the class stack.
4. First class with a matching path wins. If the walk completes without a match, raise method-not-found.
5. Run the method with `self = $foo`. Full access to `@bucket`, `%bucket`, sibling methods, anything else `self` exposes.

The visited-set / inheritance-chain walking inside each platter applies as usual.

## Worked example

~~~json
{"vibecode": {
	"section": "worked_example",
	"role": "concrete reference — the officer class in worldlet.json uses both a namespaced method group (beverage) and a top-level method (salute); spells out the call shapes that result and what the example does not yet exercise",
	"source": "documentation/requirements/ecoverse/worldlets/worldlet.json record b"
}}
~~~

The `starfleet.com/officer` class definition in [worldlets/worldlet.json](../requirements/ecoverse/worldlets/worldlet.json) (record `b`) shows the shape in practice. Its `methods` block, simplified for readability:

~~~json
"methods": {
    "beverage": {
        "nested": {
            "tea_earl_grey_hot": {
                "params": {"variety": {...}, "temperature": {...}},
                "body":   "..."
            },
            "coffee_black": {
                "params": {"style": {...}, "temperature": {...}},
                "body":   "..."
            }
        }
    },

    "salute": {
        "params": {"name": {...}, "rank": {...}, "attention": {...}, "style": {...}, "props": {...}},
        "body":   "..."
    }
}
~~~

Two shapes side by side:

- **`beverage`** has only one key: `"nested"`. Its value is itself a methods-block — that's the discriminator marking `beverage` as a namespace.
- **`salute`** has `"params"`, `"body"`, etc. directly. No `"nested"` key — that's the discriminator marking `salute` as a method definition.

Resulting call shapes on an officer instance:

~~~caspian
$picard.salute(name: 'Riker', rank: 'Commander')
$picard.beverage.tea_earl_grey_hot(variety: 'earl_grey', temperature: 'hot')
$picard.beverage.coffee_black(style: 'black', temperature: 'hot')
~~~

Each call dispatches per the [Dispatch mechanism](#dispatch-mechanism) rule: walk the officer's class stack, look for the named path under `methods`, run with `self = $picard`.

What this example does NOT yet exercise, but the spec supports:

- A method inside a namespace calling another method (in the same namespace, a different namespace, or at the top level) on the same `self`.
- A namespace nested inside another namespace (`beverage.alcoholic.synthehol`).
- A subclass adding methods to a parent class's namespace.
- Namespace-level metadata sibling to the `"nested"` key (a `description`, a `vibecode`, etc.).

Adding any of those to worldlet.json would extend the example as the spec settles.

## Open questions

- **Inheritance with namespaces.** Can a subclass add methods to a namespace declared on its parent class? Most likely yes — a subclass's `bar.nested.foo` merges with the parent's `bar.nested` rather than shadowing the whole namespace. But the merge / override semantics need to be settled. Especially: what happens if both parent and subclass define `bar.gup`? Standard inheritance rules (subclass shadows parent) should apply at the method level, not the namespace level.
- **Nested namespaces — how deep?** `$foo.a.b.c.method()` works conceptually. Should there be a depth limit, or is unbounded fine? Likely unbounded for the spec; usage convention will keep it shallow.
- **Cross-namespace dispatch.** Inside `bar.gup`, can the method call `self.baz.qux` and reach another namespace's method on the same object? Yes — same object, dispatch walks the path from `self`. Just spell the path.
- **Identity replacement for the lost `$foo.object`-as-object.** What does `$foo.object_id` (or whatever the replacement spelling is) return, and how is "same object?" tested? Needs to settle before the `.object` namespace ships, since some existing patterns leaned on the helper-as-object property.
- **Namespace-level metadata.** Can a namespace itself carry a description / vibecode / other metadata, sibling to its `nested` key? E.g., `"beverage": {"description": "Replicator-related methods", "nested": {...}}`. Useful for documentation; harmless structurally.
