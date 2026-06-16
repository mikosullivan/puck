# Method resolution

~~~vibecode
{"vibecode": {
	"doc": "object_method_resolution",
	"role": "spec for how a method call on an object resolves down its stack; the stack is an ordered array of platters and dispatch walks top to bottom (index 0 → end), consulting each platter that has a class; part of the universal object structure spec (see index.md)",
	"status": "active_design en route to settled spec",
	"audience": "Caspian implementers and security reviewers"
}}
~~~

Calling a method on an object walks its stack looking for a class that defines the method. This page describes the walk, with a worked example.

## A color object

~~~vibecode
{"vibecode": {
	"section": "color_object_example",
	"role": "concrete example used by the method-dispatch walkthrough — a color object with its hex value in the bucket and a single class platter"
}}
~~~

A color object:

<a class="copy" href="#">copy</a>

```json
{
    "bucket": {"hex": "#abcdef"},
    "stack": [
        {"class": "https://puck.uno/color/"}
    ]
}
```

One field of data, one class platter. No shadow (nothing to put on one).

## Method dispatch

~~~vibecode
{"vibecode": {
	"section": "method_dispatch",
	"role": "describes how a method call resolves down the stack: walk the array top to bottom, consult each platter that has a class, first match wins, method-not-found raises"
}}
~~~

Take the color object above and call `red` (which returns the decimal value of the red channel):

1. Start at the **top** of the stack — the platter at index 0.
2. Look at the platter's `class`. If it defines `red`, dispatch lands there.
3. Otherwise, move to the next platter down (the next array element).
4. **Skip any platter that has no `class` field at all.** Not every platter on the stack carries class identity — warning-only platters, nested-link platters, vibecode-only annotations, etc. The walk only consults platters that have a class.
5. Repeat until a class with a matching method is found.
6. If the walk completes without a match, raise a method-not-found exception.

In the color example, the only platter has `class: "https://puck.uno/color/"`, which defines `red`, so dispatch lands on it. The method returns `171` (decimal for `0xab`).

## Dispatch on a composite object

The walk works the same way on any stack, including one with a shadow, multiple class platters, and non-class platters interleaved:

```json
{
    "bucket": {"content": "Hello"},
    "stack": [
        {"shadow": true, "class": {}},
        {"class": "https://foo.bar/gup/"},
        {"warning": "content unverified"},
        {"class": "https://puck.uno/upper"}
    ]
}
```

Calling `shout` on this object dispatches like so:

1. **Shadow at index 0** — class is `{}`, no methods, walk moves on.
2. **`https://foo.bar/gup/` at index 1** — if `gup` defines `shout`, dispatch lands here. If not, walk moves on.
3. **Warning-only platter at index 2** — no `class` field; walk skips past.
4. **`https://puck.uno/upper` at index 3** — if `upper` defines `shout`, dispatch lands here.
5. If neither class defined `shout`, the walk completes and raises method-not-found.

The shadow on top intercepts everything when it has a matching singleton method; that's the point of the lazy-shadow / top-of-stack placement rule. The non-class platters (warnings, nested-links, vibecode-only) sit in the stack without affecting dispatch — they're metadata that rides along.
