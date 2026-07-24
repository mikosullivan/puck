# Engine-invoked methods

~~~vibecode
{"vibecode": {
	"doc": "engine_invoked_methods",
	"role": "cheat sheet listing every method the Caspian engine calls automatically (rather than user code calling it); one-line description per method with link to its canonical spec",
	"audience": "Caspian programmers writing class definitions who need to know which method names the engine reaches for",
	"status": "stub — enumeration only; per-method depth lives in the linked specs",
	"format": "table of method, trigger, link"
}}
~~~

The methods the Caspian engine reaches for by name. Define one on your class and the engine will call it at the right moment. Each row links to the canonical spec for that method.

| Method | Trigger | Spec |
|--------|---------|------|
| `init` | `.new(...)` after field args are validated | [lucy/ § Initializer](lucy/index.md#initializer) |
| `on_close` | object is destroyed (deterministic GC) | [garbage-collection § on_close](garbage-collection.md#on-close) |
| `to_string` | string representation is needed (`puts`, concatenation) | [to-primitives § The conversion chain](to-primitives.md#the-conversion-chain) |
| `to_json` | JSON encoding is needed | [to-primitives § The conversion chain](to-primitives.md#the-conversion-chain) |
| `to_primitives` | object must cross a process boundary, ship as JSON, or write to disk | [to-primitives](to-primitives.md) |
| `evaluate` | the class is registered as an operator and the operator fires | [syntax/operators](syntax/operators.md), [syntax/assignment-operators](syntax/assignment-operators.md) |

## How an engine-invoked method becomes one

The engine dispatches by name. Defining a method whose name is on the list above is the whole opt-in — no flag, no annotation, no registration step. The engine looks for the name when its event fires; if the method exists on the class, it's called.

Dispatch in V1 is unicast: the topmost matching method fires. Multicast (every matching method along the platter walk firing) was sketched and deferred — see [ideas/multicast.md](../../ideas/multicast.md).
