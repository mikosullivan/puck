# JSON

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_json",
	"role": "spec for Caspian's built-in JSON support: parser lives Lua-side because CaspianJ (the engine's runtime format) is JSON and has to parse before Caspian code runs, so JSON parsing can't be Caspian. Parser is LPeg-based — reuses the LPeg dependency already bundled for Caspian's own source parser and regex engine, retires the current bespoke lib/lua/caspian/json.lua. Caspian-facing surface is a %json global. Preserves hash insertion order across round-trips (CaspianJ requirement).",
	"status": "spec — Lua-side + LPeg-based decision settled; public API surface (%json.parse, %json.emit) sketched; exception classes and strictness modes (comments, trailing commas) TBD at implementation",
	"audience": "engine implementers working on the JSON parser; Caspian developers using %json from application code"
}}
~~~

Caspian parses and emits JSON out of the box. The parser is Lua-side and LPeg-based; the Caspian-facing surface is a `%json` global.

## Where the parser lives — and why it has to be Lua

CaspianJ, the engine's runtime format, is JSON. The engine parses CaspianJ before any Caspian code runs — so the JSON parser has to be usable before Caspian is. This is a genuine bootstrapping constraint: the parser can't be Caspian, because Caspian can't run until it exists.

Per [concepts § Caspian is written in Caspian](https://puck.uno/documentation/requirements/caspian/concepts#caspian-is-written-in-caspian), this is exactly the case that principle carves out — *"reach for the host language only for what genuinely can't exist above the primitive line."* The JSON parser is one of those: nothing above the JSON layer can exist until JSON parsing does.

The Caspian-facing surface (`%json.parse`, `%json.emit`) IS Caspian — a thin wrapper that hands strings to the Lua primitive and receives structured values back.

## Why LPeg-based

Two Lua strategies fit the constraint. Caspian picks LPeg-based.

- **LPeg is already bundled.** It's compiled into the caspian binary (Executable tier — see [core/](https://puck.uno/documentation/requirements/caspian/core/)) for Caspian's own source parser and regex engine. In fact, adding JSON to the LPeg-consumer list is what tipped LPeg from Cache to Executable: CaspianJ (JSON) parses at engine startup, so LPeg is effectively always loaded and has no lazy-load benefit to gain from disk-tier placement.
- **Well-trodden.** Mature LPeg-based JSON grammars exist to copy from; number canonicalization, string-escape handling, and Unicode subtleties have already been worked out in the wild.
- **One grammar toolchain across the runtime.** Caspian's source parser and regex engine both go through LPeg; putting JSON on the same primitive means one PEG engine, one testing story, one performance-tuning target.
- **Retires the bespoke recursive-descent Lua.** `lib/lua/caspian/json.lua` is hand-written today. It works, but its correctness is what it is — an LPeg grammar is auditable against a formal statement of the syntax rules.

The current `json.lua` stays as the reference implementation until the LPeg-based parser lands, then retires.

## Ordered-hash round-tripping

Hashes in Caspian preserve insertion order. When JSON is parsed into a Caspian value and then re-emitted, each object's key order survives — round-trip fidelity is a hard requirement, not a nice-to-have. CaspianJ depends on it: the engine's runtime format uses ordered hashes throughout, and losing key order on a parse-emit cycle would silently corrupt the runtime state.

The current `json.lua` achieves this by carrying a `_keys` array on the ordered-hash metatable — the encoder walks that array instead of iterating `pairs()`. The LPeg-based parser must construct these ordered hashes as it parses objects, not plain unordered Lua tables. The encoder side is unchanged.

## Public API (sketch)

Details firm up during implementation. Rough surface:

- **`%json.parse string`** — parse a JSON string, return a Caspian value. Ordered hashes for JSON objects, arrays for JSON arrays, strings / numbers / booleans / null for scalars.
- **`%json.emit value`** — encode a Caspian value to a JSON string.
- **`%json.emit value, pretty: true`** — pretty-print variant with indentation and newlines.

Exception classes for the common failure modes (unexpected token, invalid escape, invalid number, unterminated string, trailing content after the parsed value) are TBD — decided during implementation.

## Strict RFC 8259, always

`%json.parse` implements RFC 8259 strictly. Comments, trailing commas, unquoted keys, single-quoted strings, and other JSON5-style deviations all raise. There is no `lenient: true` flag on `%json` and none is coming.

The reason: only JSON is JSON. A `%json` class that quietly accepted a superset would silently redefine what the word means in a Caspian program — the developer wouldn't know they're producing something a strict parser downstream will reject until it fails in the field. That's a compatibility risk the class shouldn't bake into its default behavior.

A separate loose-parser class (JSON5, JSONC, or similar) may exist as a distinct design in the future. It won't ride on the `%json` name.

## Related

- [core/](https://puck.uno/documentation/requirements/caspian/core/) — LPeg is bundled in the Cache tier; the JSON parser is one of its consumers.
- [concepts § Caspian is written in Caspian](https://puck.uno/documentation/requirements/caspian/concepts#caspian-is-written-in-caspian) — the design principle and its bootstrapping exception.
- [built-in-classes/primitives/hash](https://puck.uno/documentation/requirements/caspian/built-in-classes/primitives/hash/) — Caspian's ordered-hash type; the shape the parser constructs for JSON objects.
