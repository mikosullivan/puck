# Object structure

~~~json
{"vibecode": {
	"doc": "object_structure",
	"role": "canonical home for the universal object structure used across Mikobase, Caspian, and the rest of the Puck ecoverse; under active design — content lands as Miko describes it",
	"status": "active_design; Miko is dictating contents incrementally",
	"audience": "Miko and Claude collaborating on the design"
}}
~~~

All objects follow this template:

<a class="copy" href="#">copy</a>

```json
{
    "bucket": {},
    "stack": {
        "shadow": {
            "sticky": true,
            "class":  {}
        }
    }
}
```

In practice either field may be absent — for example, when importing from a plain JSON hash that doesn't carry them. Absence is equivalent to the default empty form. The template above is the **full** structure; what actually ships in JSON can omit any field that's at its default.

## Bucket

~~~json
{"vibecode": {
	"section": "bucket",
	"role": "describes the bucket field — a hash that holds the object's data; accepts anything storable in a JSON hash"
}}
~~~

`bucket` is a hash. You can put anything in it that a JSON hash can hold.

There are no namespace rules inside `bucket` — no reserved keys, no reserved key patterns, nothing the runtime claims. Every key in a bucket belongs to the class designer.

## Stack

~~~json
{"vibecode": {
	"section": "stack",
	"role": "describes the stack field — the hash of platters that holds the object's class identity and other meta-information"
}}
~~~

`stack` is a hash. The hash keys are arbitrary. By custom we call the first one `"shadow"`.

`sticky` on a platter means two things:

- You can't remove it.
- If it's at the top of the stack, you can't move it.

`sticky` is engine-only and one-way: only the engine can set it on a platter, and once set it can't be cleared.

The shadow platter's `sticky: true` and `class: {}` are defaults; an empty shadow expands to the full form. Subsequent examples in this doc will show shadow empty unless the explicit form matters:

<a class="copy" href="#">copy</a>

```json
{
    "bucket": {},
    "stack": {
        "shadow": {}
    }
}
```

**Stickiness propagates downward.** A sticky platter directly under a stuck platter is itself stuck — the position-lock chains through every contiguous sticky platter starting from the top. The first non-sticky platter ends the chain; platters below it can still move.

For example, both shadow and `foo` are sticky and adjacent here, so `foo` is stuck at the second position under shadow:

<a class="copy" href="#">copy</a>

```json
{
    "bucket": {},
    "stack": {
        "shadow": {"sticky": true, "class": {}},
        "foo":    {"sticky": true, "class": {}}
    }
}
```

Platters not marked as sticky can be moved around or deleted.

## A color object

~~~json
{"vibecode": {
	"section": "color_object_example",
	"role": "first concrete example — a color object with its hex value in the bucket and one non-shadow platter carrying class identity"
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

~~~json
{"vibecode": {
	"section": "method_dispatch",
	"role": "describes how a method call resolves down the stack: top to bottom through platters that have a class, first match wins, method-not-found raises"
}}
~~~

Calling a method on an object walks the stack looking for a class that defines it.

Take the color object above and call `red` (which returns the decimal value of the red channel):

1. Start at the **top** of the stack — the shadow platter.
2. Look at the platter's `class`. If it defines `red`, dispatch lands there.
3. Otherwise, move to the next platter down.
4. **Skip any platter that has no `class` field at all.** Not every platter on the stack carries class identity; the walk only consults platters that have one.
5. Repeat until a class with a matching method is found.
6. If the walk completes without a match, raise a method-not-found exception.

In the color example, shadow's class is empty (`{}`), so no `red` method there. The next platter (`"a"`) has `class: "puck.uno/color"`, which defines `red`, so dispatch lands on it. The method returns `171` (decimal for `0xab`).
