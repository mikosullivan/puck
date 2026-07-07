# Object
<!--index: 0-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_built_in_object",
	"role": "spec for Caspian's Object class — the root of the class hierarchy. Every value in the language is an instance of a class that ultimately extends Object. Object contributes the `object` method namespace: cross-cutting methods that apply to any value regardless of its specific class (identity, class-hierarchy queries, jail-wrapping for narrowed handoffs). By pushing cross-cutting methods into this namespace rather than the top-level surface, the language keeps class-specific method tables uncluttered. Also covers how to construct a bare Object instance via `%['puck.uno/object'].new()` — the primitive used by factories and other cases where the object's shape is computed at runtime.",
	"status": "stub — namespace design settled (methods run as normal methods on the receiver with full instance access); starter method surface (truthy?, isa?, jail) documented under methods/; more methods to come",
	"audience": "developers writing Caspian; engine implementers; class authors who want the top-level surface of their class to reflect what makes it specific rather than every cross-cutting utility"
}}
~~~

The **Object class** is the root of the Caspian class hierarchy. Every value in the language — every primitive, every user-defined instance — has Object implicitly at the bottom of its inheritance chain: the specific class sits on top, its parent below, and so on down to Object as the foundation.

## Constructing a bare object

A **bare object** is a fresh instance of Object with nothing else on top — no inherited classes beyond Object itself, no methods beyond the built-in [`object`](#the-object-method-namespace) namespace, and an empty bucket. Get one through the Puck-lookup form:

~~~caspian
$my_object = %['puck.uno/object'].new()
~~~

`%['puck.uno/object']` resolves to the Object class as a first-class class value; `.new()` constructs an instance. Object is just another class — the mechanism is the same one any class instantiation uses.

Primarily useful in factory functions and any other place where the caller wants to build the object up programmatically:

- **Add classes to the stack** with `$my_object.object.classes.add($some_class)`.
- **Add singleton methods** with `method $my_object.name() ... end`.
- **Set bucket state** directly (`$my_object['key'] = 'value'`).
- **Return** the finished object.

The alternative — `instance ... end` — is the right tool when the shape is known at declaration time and can be spelled out inline. `%['puck.uno/object'].new()` is the escape hatch for factories and other cases where the shape is genuinely computed at runtime.

**On brevity.** The lookup form is deliberately explicit. If the community finds itself reaching for this pattern often, a shorter form can be added later — a keyword like `bare` or `void`, or a sigiled shorthand. For now, the spelled-out form makes the mechanism transparent.

## The `object` method namespace

Object contributes a single method namespace, `object`, that carries the cross-cutting methods applicable to any value. Callers reach these methods through a dotted path:

~~~caspian
$foo.object.truthy?
$foo.object.isa?($class)
$foo.object.jail(:name, :count)
~~~

The namespace is a [nested method namespace](https://puck.uno/documentation/requirements/caspian/classes/nested) inherited by every subclass automatically — user classes don't need to declare `nested :object` themselves. Nothing about the namespace's semantics differs from a nested namespace on a user class:

- **The methods are normal methods on the receiver.** `%self` inside `object.truthy?` is `$foo`, not a helper object. Bucket access, class methods, ambient surfaces — all behave exactly as they would in a class-defined method.
- **The namespace is a naming convention, not an isolation boundary.** The dispatch path `$foo.object.method` runs on `$foo` with full instance access; `object` isn't a proxy or a wrapper.

## Why the namespace exists

Cross-cutting methods don't belong at the top level of every class's method surface. A class definition should read as a description of what makes the class specific.

Putting `.truthy?`, `.isa?`, `.jail`, and future object-wide utilities behind `object.` keeps the top-level surface (the methods the class author actually defined) uncluttered — a `Widget` class exposes `Widget`-specific behavior at `$widget.method_name`, and everything object-wide lives one level down at `$widget.object.method_name`.

Class authors who want a method surface at `$foo.X` still put it there. The `object` namespace is for the built-in cross-cutting layer, not the class-specific one.

## Full method catalog

The methods in the `object` namespace live on their own page: [Object methods](methods/).

## Related

- [Object methods](methods/) — the full method catalog for the `object` namespace.
- [nested methods](https://puck.uno/documentation/requirements/caspian/classes/nested) — the general spec for nested method namespaces, which `object` follows.
