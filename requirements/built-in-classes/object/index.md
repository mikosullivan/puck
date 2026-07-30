# Object
<!--index: 0-->

<span class="tag">object-class</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_built_in_object",
	"role": "spec for Caspian's Object class — the root of the class hierarchy. Every value in the language is an instance of a class that ultimately extends Object. Covers how to construct a bare Object instance via `%('puck.uno/object').new()` — the primitive used by factories and other cases where the object's shape is computed at runtime. The cross-cutting method namespace Object contributes (`obj`) — how it works, why it exists, why it can't be overridden, and the full method catalog — lives at methods/.",
	"status": "spec — bare-object construction stable; the `obj` namespace concept and its full method catalog now live together at methods/",
	"audience": "developers writing Caspian; engine implementers; class authors who want the top-level surface of their class to reflect what makes it specific rather than every cross-cutting utility"
}}
~~~

The **Object class** is the root of the Caspian class hierarchy. Every value in the language — every primitive, every user-defined instance — has Object implicitly at the bottom of its inheritance chain: the specific class sits on top, its parent below, and so on down to Object as the foundation.

## Constructing a bare object

A **bare object** is a fresh instance of Object with nothing else on top — no inherited classes beyond Object itself, no methods beyond the built-in [`obj`](tag:obj-methods) namespace, and an empty bucket. Get one through the Puck-lookup form:

~~~caspian
$my_object = %('puck.uno/object').new()
~~~

`%('puck.uno/object')` resolves to the Object class as a first-class class value; `.new()` constructs an instance. Object is just another class — the mechanism is the same one any class instantiation uses.

Primarily useful in factory functions and any other place where the caller wants to build the object up programmatically:

- **Add classes to the stack** with `$my_object.obj.classes.add($some_class)`.
- **Add singleton methods** with `method $my_object.name() ... end`.
- **Set bucket state** directly (`$my_object['key'] = 'value'`).
- **Return** the finished object.

The alternative — `instance ... end` — is the right tool when the shape is known at declaration time and can be spelled out inline. `%('puck.uno/object').new()` is the escape hatch for factories and other cases where the shape is genuinely computed at runtime.

**On brevity.** The lookup form is deliberately explicit. If the community finds itself reaching for this pattern often, a shorter form can be added later — a keyword like `bare` or `void`, or a sigiled shorthand. For now, the spelled-out form makes the mechanism transparent.

## The `obj` method

Object contributes a single method, `obj`, that carries the cross-cutting methods applicable to any value (`$foo.obj.truthy?`, `$foo.obj.isa?($class)`, etc.). Every class inherits the namespace automatically. See [Object methods](tag:obj-methods) for how the namespace works and the full method catalog.

## Testing

- **Object is resolvable at startup** — `%('puck.uno/object')` returns a class value in a fresh runtime with no user code loaded.
- **`%('puck.uno/object').new()` returns an instance** — the returned value is an object; `.obj.isa?(Object)` on it is `true`.
- **Bare object has an empty bucket** — a fresh bare object's `%bucket` is an empty hash.
- **Bare object has only Object in its class stack** — `%('puck.uno/object').new().obj.classes` returns an array containing just the Object class.
- **Every value is an Object** — for each primitive literal (`42`, `'hi'`, `true`, `false`, `null`, `[]`, `{}`), `.obj.isa?(Object)` is `true`.
- **Bare object can accept added classes** — after `$o = %('puck.uno/object').new(); $o.obj.classes.ensure(Some_class)`, `$o.obj.isa?(Some_class)` is `true`.
- **Bare object can accept singleton methods** — after defining `method $o.name() 'x' end` on a bare object, `$o.name` returns `'x'`.
- **Bare object can accept direct bucket writes** — after `$o = %('puck.uno/object').new(); $o.@key = 'value'`, `$o.@key` is `'value'`.
- **Two `.new()` calls return distinct instances** — successive bare-object constructions have distinct identity; buckets are independent.

## Related

- [Object methods](tag:obj-methods) — how the `obj` nested namespace works and the full method catalog.
