# Method-as-closure (deferred)

~~~vibecode
{"vibecode": {
	"doc": "idea_method_as_closure",
	"role": "captures a design option we considered for singleton methods — attaching a closure as a method (so it acquires closure-captured scope IN ADDITION to method-call semantics) — and why we set it down. Singleton methods will use a real method definition form (`method $obj.name()`) instead. This file records the closure-flavored alternative in case it resurfaces later.",
	"status": "deferred — not in V1; the closure-as-method form was considered and rejected as too confusing",
	"audience": "Caspian designers who notice the deferred design space later"
}}
~~~

When designing how singleton methods get attached to one specific object, we considered passing the body as a closure:

~~~caspian
$alice.object.method(:salute) do
	'Captain ' + @name + ' reporting!'
end
~~~

Here the `do ... end` block is a closure. It would somehow be attached as a method on `$alice` — but the `@name` inside would have to mean "$alice's bucket," not "captured from surrounding scope." That meant the closure's `@` semantics got rebound at attach-time, which is exactly the kind of magic that breaks reasoning.

The discomfort: a closure is supposed to capture its surrounding scope and behave like a captured function. A method is supposed to dispatch on a receiver with `@` meaning that receiver's bucket. If we made the closure-form do both — capture surrounding scope AND rebind `@` to the receiver — we'd have an object that's neither cleanly a closure nor cleanly a method. Two models, smashed together, each weakened.

## The chosen alternative

Singleton methods are defined with a real method form that mirrors how class-body methods are written, but with an explicit receiver:

~~~caspian
method $alice.salute()
	'Captain ' + @name + ' reporting!'
end
~~~

`@name` means `$alice`'s bucket. No surrounding-scope capture. Dispatches normally. Identical to a class method in every respect except that it lives on one object instead of every instance of a class. See [built-in-classes/object § method](../requirements/built-in-classes/object.md#method).

## What was lost

The closure form had one real attraction: if a developer wanted method-shaped behavior with access to captured outer variables, they could do it in one expression. With the chosen design, that pattern requires storing a closure in a field and calling it through the field:

~~~caspian
$alice.handler = do($event)
	# capture-scope stuff
end

&($alice.handler)($event)   # call explicitly
~~~

That's two steps and the caller has to know they're invoking a closure rather than dispatching a method. The closure-as-method form would have hidden that difference behind dispatch syntax.

The trade we accepted: more honesty (you can see whether you're calling a method or invoking a stored closure) at the cost of more typing for the closure case.

## Possible reasons to reopen

A few situations where this might come back on the table:

- **The closure-attached-to-object pattern turns out to be common** and the two-step form starts feeling like ceremony. If real Caspian code routinely stores closures on objects and invokes them through `.handler` style fields, we may want a syntactic shortcut.
- **A reframing of `@`** that makes the rebinding less magical. If there's a way to express "this closure has its `@` bound to *this* receiver" that reads naturally instead of as engine magic, the closure-method form might become coherent.
- **A different attachment surface** — e.g., a separate `.object.handler` namespace for closure-shaped attachments, distinct from `.object.method` for real methods — that keeps the two models cleanly separated while still giving the closure case syntactic support.

For now, none of these has materialized. The chosen one-form design holds.
