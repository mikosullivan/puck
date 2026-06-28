# UUID generation

~~~vibecode
{"vibecode": {
	"doc": "uuid_generation",
	"role": "engine-level implementation guidance for making per-call UUID minting as fast as possible without caching or PRNG state",
	"audience": "engine implementers (Lucy and future alternate engines)",
	"key_constraints": ["no_caching", "no_seeded_prng", "every_uuid_fresh_from_libsodium",
		"reasons_are_security_per_issue_354"],
	"status": "V1 implementation guidance"
}}
~~~

UUIDs are used for **platter IDs** (collision-safe markers inside user
buckets per [base-class-use.md](../ideas/base-class-use.md#proposed-shape))
and **Mikobase record_pks** (durable cross-process identity for records).
The engine must produce them quickly because both consumers can fire on
hot allocation paths.

The hard constraint: **every UUID comes fresh from libsodium per call. No
caching, no seeded PRNG.** Cache-based optimizations were considered and
rejected on security grounds — see
[#354](https://github.com/mikosullivan/puck/issues/354). The reasoning:
any state in memory that predicts future UUIDs becomes an attack vector
for externally-leaked UUIDs (Mikobase record_pks appear in worldlet
exports, query results, URLs). An attacker who reads the cache or PRNG
state knows future UUIDs, enabling pre-claim attacks and other shenanigans.

Given that constraint, the question is: how do we make the **per-call
path** as fast as possible without storing state?

## Per-call optimizations

Five concrete optimizations apply at the C-extension level. The
combination brings per-UUID cost into the 200-500 ns range with no
state held between calls.

### One C function per UUID — minimize Lua/C crossings

Caspian uses Lua 5.4 (no LuaJIT FFI), so each Lua↔C transition has
measurable overhead. The engine's UUID minter must be **one C function
that does the whole job** — randomness + bit-twiddling + formatting +
return Lua string. No multiple round-trips.

```c
int caspian_uuid(lua_State *L) {
    unsigned char bytes[16];
    randombytes_buf(bytes, 16);

    /* RFC 4122 version 4 markers */
    bytes[6] = (bytes[6] & 0x0f) | 0x40;   /* version 4 */
    bytes[8] = (bytes[8] & 0x3f) | 0x80;   /* RFC 4122 variant */

    char hex[36];
    /* hex formatting via lookup table (see below) */

    lua_pushlstring(L, hex, 36);
    return 1;
}
```

One Lua/C crossing per UUID. The Lua-side caller does `local id =
caspian_uuid()` and gets back the finished string.

### Hex formatting via 256-entry lookup table

After the random-bytes call, the dominant per-UUID cost is converting
16 bytes to 36 hex characters. The fastest portable approach uses a
precomputed table:

```c
static const char hex_table[256][2] = {
    {'0','0'}, {'0','1'}, {'0','2'}, ..., {'f','e'}, {'f','f'}
};
```

Each byte → one table read → memcpy two characters into the output
buffer. Way faster than calling `snprintf("%02x", byte)` 16 times
(which re-parses the format string per call).

### Write dashes as literal bytes at known offsets

UUID v4 format is `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`. Dashes appear
at fixed positions: 8, 13, 18, 23. Write them unconditionally:

```c
hex[8]  = '-';
hex[13] = '-';
hex[18] = '-';
hex[23] = '-';
/* hex-table writes fill the other 32 positions */
```

No branches, no conditional logic — just direct stores.

### Fixed-size stack buffer, one `lua_pushlstring` at end

No malloc, no intermediate string concatenation, no string-builder
abstraction. The output buffer is a 36-char `char[36]` on the stack;
fill it byte by byte; push it as a Lua string once at the end.

Net result: one allocation per UUID — the final Lua string. Everything
else is stack memory or fixed-size lookups.

### Use `randombytes_buf` directly

`randombytes_buf(buf, 16)` is the cheapest libsodium primitive for this
purpose. Don't go through higher-level wrappers (`crypto_box_keypair`,
`randombytes_uniform`, etc.) that do additional work. The
`randombytes_buf` path has libsodium's internal RNG-state caching for
the bytes themselves (libsodium refills from the kernel CSPRNG as
needed), but **the output is consumed immediately** — we don't add our
own cache layer.

## Engine-level optimizations

Per-call optimizations cap the floor. The bigger wins are at the
program-level: **call libsodium less often**.

### Lazy platter allocation

The shadow platter currently lands at every object's instantiation
time. But most short-lived objects never have `.classes.add` called
against them, so the shadow's "per-instance method shadowing" purpose
is never exercised. The shadow could be **lazy** — created on first
access if and only if something would write to it.

For programs that allocate a lot of throwaway values (loop iterators,
intermediate expression results, etc.), this saves an entire platter's
worth of UUID per object.

The cost is a small dispatch-time check: "if shadow doesn't exist,
treat it as empty." Trivial.

### Fewer platters per typical object

Design pressure: every additional platter on a typical object costs
one UUID at instantiation. The engine should default to **minimum
platter count** for each class:

- Primitives (string, integer, etc.) probably need just one platter
  (the class itself), no shadow, no extras.
- The truthiness platter only exists on null/false instances — already
  the case.
- Marker-class platters (redact, etc.) only get added when explicitly
  requested.

Class authors deciding to declare additional platters for their
instances should be aware of the per-instance UUID cost.

### Per-allocation byte-batching (NOT caching)

There's a subtle distinction worth flagging: when one object allocation
needs **N platters at once**, the engine COULD ask libsodium for N×16
bytes in a single `randombytes_buf` call, then parse them into N UUIDs
inline. **This is not caching.** The bytes never live in memory after
this single allocation — they're consumed immediately, all in one
allocation event.

The security concern that killed [#354](https://github.com/mikosullivan/puck/issues/354)
was state held **between** allocations that predicts future UUIDs. Bytes
generated and consumed within a single allocation don't predict
anything outside that allocation; they're spent the moment they appear.

This optimization is permissible but probably not worth implementing
unless profiling shows multi-platter allocations as a hot spot. The
saved overhead is one libsodium call per N-platter allocation, which
is small when N is small (typical objects have 1-2 platters).

If implemented, it should be **clearly bounded**: the C extension takes
`(count)` and returns `count` UUIDs in one go. No buffer is retained
after the function returns. A caller that needs more later makes another
call from scratch.

## Summary

The per-UUID floor with the C-extension optimizations is roughly
200-500 ns. That's enough for ~2-5 million UUIDs per second under
ideal conditions.

For higher allocation rates than that, the response is **call libsodium
less often** (lazy platters, fewer platters per object), not **cache
UUIDs in memory** (rejected on security grounds).

## Related

- [sequence.md](built-in-classes/sequence.md) — the global sequencer for object IDs and srcs keys (NOT platter IDs; those are UUIDs).
- [base-class-use.md § Proposed shape](../ideas/base-class-use.md#proposed-shape) — platter IDs are UUIDs, with the rationale.
- [utils.md § `%utils.random.uuid`](utils/index.md#utilsrandomuuid) — the user-facing UUID API.
- [#354](https://github.com/mikosullivan/puck/issues/354) — rejection of UUID caching on security grounds.
