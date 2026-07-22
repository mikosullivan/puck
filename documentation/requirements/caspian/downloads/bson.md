# BSON

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_v1_downloads_bson",
	"role": "spec for the BSON class at `caspian.uno/bson.casp` — Ships: no, Day 1: TBD. BSON is the binary JSON superset used natively by MongoDB and adopted as a general-purpose wire format elsewhere. Adds typed extensions on top of JSON's data model (ObjectId, dates, binary blobs, decimal128).",
	"status": "stub — needs class-surface design",
	"audience": "developers talking to a BSON peer (MongoDB, msgpack-adjacent stacks); anyone writing the BSON class spec"
}}
~~~

Stub. First-party download at `caspian.uno/bson.casp` — BSON encode/decode.

## What BSON is

TBD.

## Method surface

TBD — likely mirrors the JSON class shape (`.parse` / `.emit`) with BSON-specific typed constructors (`ObjectId`, `Date`, `Binary`, `Decimal128`) for values JSON can't represent.

## Implementation: use `string.unpack`

Decode BSON with Lua 5.4's `string.unpack`. Its native format specifiers cover everything BSON needs — `<i4` (little-endian int32), `<i8` (int64), `<d` (IEEE 754 double), `z` (null-terminated cstring), `<s4` (length-prefixed string) — and position tracking is threaded through the return values, matching BSON's cursor-walk decode shape.

A recursive-descent BSON walker in `string.unpack` is small (rough estimate: ≈200–300 lines) and adds zero to the floppy budget — `string.unpack` is built into the Lua 5.4 interpreter that Caspian already ships.

Rejected alternative: bind a C BSON library. `luamongo` and `luabson` are both effectively unmaintained; a pure-Lua walker on `string.unpack` is a shorter path than reviving one.

## Testing

TBD.
