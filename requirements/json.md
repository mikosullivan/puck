# JSON

~~~vibecode
{"vibecode": {
	"doc": "requirements_json",
	"role": "spec for Caspian's built-in JSON support. Two layers: (1) an engine-internal Lua parser (LPeg-based, retires the current bespoke lib/lua/caspian/json.lua) that the engine uses at startup to parse CaspianJ — the engine's runtime format IS JSON, so JSON parsing has to be usable before Caspian code runs; (2) a user-facing Caspian class at caspian.uno/json.casp, loaded via %('caspian.uno/json.casp'), that user code calls for parse / emit operations. No %json global exists — the class-lookup form is the surface. Preserves hash insertion order across round-trips (CaspianJ requirement).",
	"status": "spec — Lua-side + LPeg-based decision settled; user-facing surface (%('caspian.uno/json.casp')) settled; API on the class (.parse, .emit) sketched; exception classes TBD at implementation",
	"audience": "engine implementers working on the JSON parser; Caspian developers using the JSON class from application code"
}}
~~~

Caspian parses and emits JSON out of the box. Two layers, one accessible from user code:

- **Engine layer** — a Lua-side, LPeg-based parser that the engine itself uses to load CaspianJ at startup. Not directly reachable from Caspian code.
- **User-facing layer** — a Caspian class at `caspian.uno/json.casp`, loaded and used via:

~~~caspian
$json = %('caspian.uno/json.casp')
$value = $json.parse '{"a": 1, "b": [true, null]}'
$serialized = $json.emit $value
~~~

There is no `%json` global. All access is through the class lookup.

## Where the parser lives — and why the engine layer has to be Lua

CaspianJ, the engine's runtime format, is JSON. The engine parses CaspianJ before any Caspian code runs — so the JSON parser has to be usable before Caspian is. This is a genuine bootstrapping constraint: the engine's parser can't be Caspian, because Caspian can't run until it exists.

Per [concepts § Caspian is written in Caspian](https://puck.uno/requirements/concepts#caspian-is-written-in-caspian), this is exactly the case that principle carves out — *"reach for the host language only for what genuinely can't exist above the primitive line."* The engine's JSON parser is one of those.

The user-facing `caspian.uno/json.casp` class IS Caspian. It delegates the actual parse / emit work to the engine primitive so the whole runtime shares one JSON implementation.

## Why LPeg-based

Two Lua strategies fit the engine-layer constraint. Caspian picks LPeg-based.

- **LPeg is already bundled.** It's compiled into the caspian binary (Executable tier — see [core/](https://puck.uno/requirements/core/)) for Caspian's own source parser and regex engine. In fact, adding JSON to the LPeg-consumer list is what tipped LPeg from Cache to Executable: CaspianJ (JSON) parses at engine startup, so LPeg is effectively always loaded and has no lazy-load benefit to gain from disk-tier placement.
- **Well-trodden.** Mature LPeg-based JSON grammars exist to copy from; number canonicalization, string-escape handling, and Unicode subtleties have already been worked out in the wild.
- **One grammar toolchain across the runtime.** Caspian's source parser and regex engine both go through LPeg; putting JSON on the same primitive means one PEG engine, one testing story, one performance-tuning target.
- **Retires the bespoke recursive-descent Lua.** `lib/lua/caspian/json.lua` is hand-written today. It works, but its correctness is what it is — an LPeg grammar is auditable against a formal statement of the syntax rules.

The current `json.lua` stays as the reference implementation until the LPeg-based parser lands, then retires.

## Ordered-hash round-tripping

Hashes in Caspian preserve insertion order. When JSON is parsed into a Caspian value and then re-emitted, each object's key order survives — round-trip fidelity is a hard requirement, not a nice-to-have. CaspianJ depends on it: the engine's runtime format uses ordered hashes throughout, and losing key order on a parse-emit cycle would silently corrupt the runtime state.

The current `json.lua` achieves this by carrying a `_keys` array on the ordered-hash metatable — the encoder walks that array instead of iterating `pairs()`. The LPeg-based parser must construct these ordered hashes as it parses objects, not plain unordered Lua tables. The encoder side is unchanged.

## The class API (sketch)

Details firm up during implementation. Rough surface on the `caspian.uno/json.casp` class:

~~~caspian
$json = %('caspian.uno/json.casp')

# parse — JSON string in, Caspian value out
$value = $json.parse '{"a": 1, "b": [true, null]}'

# emit — Caspian value in, JSON string out
$serialized = $json.emit $value

# emit with pretty-print
$pretty = $json.emit $value, pretty: true
~~~

Returned Caspian values: ordered hashes for JSON objects, arrays for JSON arrays, strings / numbers / booleans / null for scalars.

Exception classes for the common failure modes (unexpected token, invalid escape, invalid number, unterminated string, trailing content after the parsed value) are TBD — decided during implementation.

## Strict RFC 8259, always

`$json.parse` implements RFC 8259 strictly. Comments, trailing commas, unquoted keys, single-quoted strings, and other JSON5-style deviations all raise. There is no `lenient: true` flag on the class and none is coming.

The reason: only JSON is JSON. A class that quietly accepted a superset would silently redefine what the word means in a Caspian program — the developer wouldn't know they're producing something a strict parser downstream will reject until it fails in the field. That's a compatibility risk the class shouldn't bake into its default behavior.

A separate loose-parser class (JSON5, JSONC, or similar) may exist as a distinct design in the future. It won't ride on the `caspian.uno/json.casp` name.

## Related

- [core/](https://puck.uno/requirements/core/) — LPeg is bundled in the Executable tier; the engine JSON parser is one of its consumers.
- [concepts § Caspian is written in Caspian](https://puck.uno/requirements/concepts#caspian-is-written-in-caspian) — the design principle and its bootstrapping exception.
- [built-in-classes/primitives/hash](https://puck.uno/requirements/built-in-classes/primitives/hash/) — Caspian's ordered-hash type; the shape the parser constructs for JSON objects.
