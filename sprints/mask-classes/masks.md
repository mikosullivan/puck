~~~vibecode
{"doc": "sprint-note", "sprint": "mask-classes",
	"role": "Draft spec text for the mask-class concept — how a Caspian-surface class implemented in Lua is stored in the CVM. Written in the shape it will take when promoted to requirements/ (probably requirements/classes/masks or a new page under requirements/cvm/). Single-section explainer."}
~~~

# Mask classes

A **mask class** is a class whose surface looks like an ordinary Caspian class but whose implementation lives in Lua. From a Caspian program's point of view, calling a method on a mask-class instance is indistinguishable from calling a method on any other object; the engine routes the call through a Lua implementation instead of walking a Caspian method body.

## Storage

A mask-class instance is a row in `objects` with the `ec` (engine class) column set. The value is a short string naming which engine (Lua) class this row is an instance of — `class`, and eventually `function`, `array`, and others as the engine adds them.

For example, `puck.uno/color` (a mask class from the surface) is stored as a single `objects` row with `ec = 'class'` — "this row is an instance of the engine's `class` implementation."

## Rules

- **`ec` is immutable.** Set at INSERT; never changes. A row IS a `class` at INSERT; there's no rebind. If a different engine class is wanted, insert a different row.
- **No value constraint.** The field accepts any string. A naming scheme lands later.
