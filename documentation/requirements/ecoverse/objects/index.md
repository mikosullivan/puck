# Objects

~~~json
{"vibecode": {
	"doc": "objects",
	"role": "introduction to the universal object structure spec used across Mikobase, Caspian, Puck, and the rest of the ecoverse; orients the reader and points at the sub-pages that hold the details. Per issue #379, this is THE canonical reference once stable.",
	"status": "active_design en route to settled spec",
	"audience": "Caspian implementers and security reviewers"
}}
~~~

Every value in the Puck ecoverse — every record in Mikobase, every value handled by Caspian, every payload in a Puck protocol message — follows one universal object structure. This directory defines that structure.

The shape is intentionally minimal: two fields, one for data and one for identity. The `bucket` holds whatever the object actually contains (the hex value of a color, the name of an officer, the bytes of a session token). The `stack` carries the object's class identity and any other meta-information the engine needs — class membership, sticky position markers, lifecycle handlers, anything that travels with the value rather than its data.

This split is the design's anchor. Anywhere an object travels — across the network, into a database, into a fork, into a log — it carries the same two-field shape. Readers and writers never have to translate between formats; an object is the same kind of thing on every surface.

Method calls on an object are resolved by walking the stack: the engine searches top-down through the platters in the stack for a class that defines the method being called, with the first matching class winning. The mechanics are spelled out on the method-resolution page.

## Sub-pages

- [structure.md](structure.md) — the `bucket` field, the `stack` field, the platter hash that lives in the stack, and how stickiness governs which platters can be moved or removed.
- [method-resolution.md](method-resolution.md) — how a method call on an object resolves: top-down walk of the stack, skip platters with no class, first matching class wins, method-not-found raises if the walk completes without a hit.
