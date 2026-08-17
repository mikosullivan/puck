# Classes
<!--index: 8-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_classes",
	"role": "cover page for the classes subtree — the requirements-tree home for how Caspian classes are defined, how ad-hoc methods attach at the call site, how methods can be grouped into nested namespaces, and the `instance` one-off construct. Sub-pages own their surface; this page is the entry point.",
	"status": "draft — cover page listing the current sub-pages; grows as more class-level concepts migrate in",
	"audience": "developers writing Caspian classes; anyone looking for the class-related specs"
}}
~~~

Classes are the sole method-carrier in Caspian ([concepts § Classes are the only method-carrier](https://puck.uno/requirements/concepts#classes-are-the-only-method-carrier)) — every method reachable on a value is declared through a class. Sub-pages own the pieces of that model:

- [definition/](https://puck.uno/requirements/classes/definition/) — the `class ... end` DSL for defining a class: fields, methods, inheritance, engine-invoked hooks, and the `amend` construct.
- [inheritance](tag:class-inheritance) — the runtime `.inherited` accessor on class values, mutation methods (`.push`, `.ensure` bare and block forms), immediate visibility to method resolution. Complements the static `inherits` clause in the class body.
- [downloaded-methods](https://puck.uno/requirements/classes/downloaded-methods) — ad-hoc method application via `$obj.$fn`: treating a first-class function value as a method on the receiver, with `%self` bound and full bucket access.
- [method-resolution](tag:method-resolution) — how method calls are dispatched at runtime: platter-stack walk, depth-first inheritance-graph search with per-dispatch seen-set, and how `super()` walks the class's inherits array.
- [has-method](tag:has-method) — `.has_method?(name)` predicate on class objects; returns whether the class's method-resolution graph would find a method with the given name. Useful for delegation-code generation and other runtime class introspection.
- [nested](https://puck.uno/requirements/classes/nested) — the `nested :name ... end` construct for grouping methods under named sub-namespaces reachable via dotted paths.
- [instance](https://puck.uno/requirements/classes/instance) — the `instance ... end` keyword for building a single object directly, using the same body shape as a class definition.
