# Controllers

<span class="tag">controllers</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_controllers",
	"role": "spec for controllers — the general concept of an object bound to a call's `as $name` slot. A controller is any object that lives in `%call['controller']` for a given call; being a controller is purely structural (no required interface, no methods, no shared class). Iterators are one specific kind of controller — the kind primitive loops produce, carrying loop-control methods like `.break` and `.next`. This doc owns the structural definition; specialized controller types like iterators are spec'd separately.",
	"status": "starting — the structural definition is the core spec; expands as specific controller uses land",
	"audience": "developers writing callables that expose an `as $name` binding; anyone reading Caspian code involving `as $name`; implementers of the caller mechanism"
}}
~~~

A **controller** is any object that lives in the `%call['controller']` slot for a given call — whatever the closure or block's `as $name` binding evaluates to at invocation time.

## What "being a controller" means

Nothing structural. There is no `Controller` class, no interface, no required methods, no lifecycle hook a controller must implement. Being a controller means being what's in `%call['controller']` for the current call. That's the entire definition.

Any object can be a controller. What the caller of a callable puts in that slot is a design choice for the API — it might be a purpose-built object with methods (like an iterator), a plain hash, a reference to any other object the callable's implementation happens to hold, or `null` when no controller is wired.

## How a controller gets bound

A closure or block declares its intent to receive a controller by writing `as $name` in its declaration:

~~~caspian
$fiddle.play() do() as $control
	$control.something
end
~~~

The `as $control` on the block tells the parser: whatever the caller puts in this call's `.controller` slot, bind it to `$control` for the duration of the block's execution. The value comes from the caller — see [caller](tag:caller) for how a caller sets the `.controller` slot at invocation time.

Not every callable declares `as $name`. Callables that don't declare one don't receive a controller, and setting `.controller` on a caller whose target didn't declare `as $name` raises (see [caller](tag:caller)).

## Iterators as a kind of controller

Primitive loop constructs (`while`, `until`, `.each`, `.times`, `.upto`, `.downto`, `begin ... while`, `begin ... until`) produce a specific kind of controller called an **iterator** — a controller with loop-control methods (`.break`, `.next`, and whatever else the loop chooses to expose). See [iterators](https://www.puck.uno/ideas/controllers/iterators) for the iterator surface and the sugar bwcs (`iterate`, `break`, `next`) that layer on top of it. The iterator spec is currently in `ideas/` and will move to `requirements/` alongside a canonical tag.

Other kinds of controllers may exist as new callables invent uses for the `as` slot. The doc for each specific controller type describes what methods it carries and how it's meant to be used.

## Related

- [caller](tag:caller) — the mechanism that places objects into the `.controller` slot at invocation time.
- [iterators](https://www.puck.uno/ideas/controllers/iterators) — the iterator specialization.
