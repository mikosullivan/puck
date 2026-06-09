# Method resolution

~~~vibecode
{"vibecode": {
	"doc": "object_method_resolution",
	"role": "spec for how a method call on an object resolves down its stack; part of the universal object structure spec (see index.md)",
	"status": "active_design en route to settled spec",
	"audience": "Caspian implementers and security reviewers"
}}
~~~

Calling a method on an object walks its stack looking for a class that defines the method. This page describes the walk, with a worked example.

## A color object

~~~vibecode
{"vibecode": {
	"section": "color_object_example",
	"role": "concrete example used by the method-dispatch walkthrough — a color object with its hex value in the bucket and one non-shadow platter carrying class identity"
}}
~~~

A color object:

<a class="copy" href="#">copy</a>

```json
{
    "bucket": {"hex": "#abcdef"},
    "stack": {
        "shadow": {},
        "a": {"class": "puck.uno/color"}
    }
}
```

## Method dispatch

~~~vibecode
{"vibecode": {
	"section": "method_dispatch",
	"role": "describes how a method call resolves down the stack: top to bottom through platters that have a class, first match wins, method-not-found raises"
}}
~~~

Take the color object above and call `red` (which returns the decimal value of the red channel):

1. Start at the **top** of the stack — the shadow platter.
2. Look at the platter's `class`. If it defines `red`, dispatch lands there.
3. Otherwise, move to the next platter down.
4. **Skip any platter that has no `class` field at all.** Not every platter on the stack carries class identity; the walk only consults platters that have one.
5. Repeat until a class with a matching method is found.
6. If the walk completes without a match, raise a method-not-found exception.

In the color example, shadow's class is empty (`{}`), so no `red` method there. The next platter (`"a"`) has `class: "puck.uno/color"`, which defines `red`, so dispatch lands on it. The method returns `171` (decimal for `0xab`).
