# `misc` and `corporate` utility classes
<!--index: 9-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_built_in_misc_and_corporate",
	"role": "spec for six built-in utility classes that expose the reserved pass-through bucket entries `misc` and `corporate` — one full-access class (Misc, Corporate), one read-only variant (MiscReader, CorporateReader), and one write-only variant (MiscWriter, CorporateWriter) for each field. Each contributes a same-named method (`.misc`, `.corporate`) with the capability shape the class declares. The hash is lazily created on write; any existing non-hash value at the target key raises.",
	"status": "draft — six classes named with canonical URLs and their contributed methods; the write-only capability shape is spec'd but should be reviewed once concrete use lands",
	"audience": "developers writing Caspian classes; anyone reasoning about the reserved pass-through fields `misc` and `corporate`"
}}
~~~

Six utility classes come in a matched pair of three, one triple for the `misc` bucket entry and one for `corporate`. They contribute a same-named accessor method (`.misc` or `.corporate`) that reaches directly into `%bucket['misc']` or `%bucket['corporate']` respectively.

The two triples exist because the [pass-through fields spec](https://puck.uno/requirements/built-in-classes/object/structure/) distinguishes `misc` (ungoverned free-rider) from `corporate` (governed by declared conventions); the mechanics are identical but the two triples exist so a class author can grant capability to whichever field matches the governance posture they're declaring.

Within each triple:

| Class | Read | Write |
|---|---|---|
| `Misc` / `Corporate` | yes | yes |
| `MiscReader` / `CorporateReader` | yes | no |
| `MiscWriter` / `CorporateWriter` | no | yes |

## Common behavior

All six classes share three rules that apply to their respective bucket entry (`misc` or `corporate`):

- **The hash is lazily created on write.** If the target entry doesn't exist and a write happens through this class's methods, the runtime creates an empty hash at that key and applies the write to it. Callers don't need to construct the hash first.
- **A non-hash existing value raises.** If the target entry exists but its value isn't a hash (e.g., someone assigned a string there earlier), any access through these classes raises. The classes require a hash-shaped entry to work at all.
- **Read against a missing hash returns `null`.** For read-only and full-access classes, calling the accessor when the target entry doesn't exist yet returns `null` — no error, just "there's nothing there yet."

## Misc

Canonical URL: **`https://puck.uno/misc/`**. Working class name: `Misc`.

Adds the **`.misc`** method — a full read/write accessor for `%bucket['misc']`:

~~~caspian
$obj.misc                              # returns the hash at %bucket['misc'], or null if not set
$obj.misc[:internal_tracking_id]       # reads a specific key from the misc hash
$obj.misc[:internal_tracking_id] = 'abc-123'   # writes; lazily creates the hash if missing
~~~

Both reads and writes go through `.misc`; the returned hash is a live reference to the entry itself.

## MiscReader

Canonical URL: **`https://puck.uno/miscreader/`**. Working class name: `MiscReader`.

Adds a read-only variant of `.misc`. The returned hash (when present) supports read operations only; write operations raise. When the misc hash doesn't exist, `.misc` returns `null` — no lazy creation, no error, just a "there's nothing there" signal.

Useful when the class author wants external code to inspect `misc` without granting mutation capability.

## MiscWriter

Canonical URL: **`https://puck.uno/miscwriter/`**. Working class name: `MiscWriter`.

Adds a write-only variant of `.misc`. The accessor supports write operations (which lazily create the hash on first write) but read operations raise. Useful for observer / collector / one-way telemetry patterns where the caller can contribute annotations without inspecting what's already there.

## Corporate

Canonical URL: **`https://puck.uno/corporate/`**. Working class name: `Corporate`.

Same shape as `Misc`, applied to `%bucket['corporate']` instead of `%bucket['misc']`. Adds the **`.corporate`** method — full read/write accessor:

~~~caspian
$obj.corporate['acme.com/audit']       # reads the acme.com/audit entry inside corporate
$obj.corporate['acme.com/audit'] = {created_by: 'picard', approved_by: 'riker'}
~~~

## CorporateReader

Canonical URL: **`https://puck.uno/corporatereader/`**. Working class name: `CorporateReader`.

Read-only variant of `.corporate`. Same rules as `MiscReader` applied to the `corporate` entry: `.corporate` returns `null` if the hash doesn't exist; the returned hash refuses writes.

## CorporateWriter

Canonical URL: **`https://puck.uno/corporatewriter/`**. Working class name: `CorporateWriter`.

Write-only variant of `.corporate`. Same rules as `MiscWriter` applied to the `corporate` entry.

## Testing

### All six classes are resolvable at startup

- **Misc, MiscReader, MiscWriter, Corporate, CorporateReader, CorporateWriter** — each of `%('puck.uno/misc/')`, `%('puck.uno/miscreader/')`, `%('puck.uno/miscwriter/')`, `%('puck.uno/corporate/')`, `%('puck.uno/corporatereader/')`, `%('puck.uno/corporatewriter/')` returns a class value in a fresh runtime.

### Misc

- **`.misc` returns null when `%bucket['misc']` is absent** — a fresh instance carrying Misc has `$obj.misc` equal to null.
- **First write lazily creates the misc hash** — after `$obj.misc[:key] = 'v'` on a fresh instance, `$obj.misc` is a hash containing `{key: 'v'}`.
- **Read after write returns the same value** — after `$obj.misc[:tracking_id] = 'abc'`, `$obj.misc[:tracking_id]` is `'abc'`.
- **`.misc` returns the live reference** — modifying the returned hash through subsequent operations affects `%bucket['misc']` directly.
- **Non-hash existing value raises** — after `%bucket['misc'] = 'not a hash'`, calling `$obj.misc` (any operation) raises.
- **Multiple writes accumulate into the same hash** — `$obj.misc[:a] = 1; $obj.misc[:b] = 2` results in `$obj.misc` equal to `{a: 1, b: 2}`.
- **misc bucket entry is pass-through** — a value serialized with a misc entry round-trips through JSON with the misc entry intact and not validated.

### MiscReader

- **`.misc` returns null when missing** — same as Misc's read behavior.
- **Read of existing entry returns the hash** — after `%bucket['misc'] = {a: 1}` (via class-internal method), `$obj.misc[:a]` returns `1`.
- **Write via `.misc` raises** — `$obj.misc[:new] = 'v'` raises when the class carries only MiscReader.
- **Non-hash existing value raises on read** — same rule as Misc; a non-hash misc entry causes a read to raise.

### MiscWriter

- **Write succeeds and lazily creates the hash** — after `$obj.misc[:key] = 'v'` on a fresh instance with only MiscWriter, `%bucket['misc']` is `{key: 'v'}` (verifiable from class-internal code).
- **Read via `.misc` raises** — reading `$obj.misc` raises when the class carries only MiscWriter.
- **Non-hash existing value raises on write** — same rule as Misc; a non-hash misc entry causes a write to raise.

### Corporate

- **Same shape as Misc, applied to `%bucket['corporate']`** — every behavior spec'd for Misc applies to Corporate with the target key changed. Concrete tests: null on missing; lazy hash creation on first write; live-reference return on read; non-hash existing value raises; multiple writes accumulate; corporate entry is pass-through through JSON.

### CorporateReader

- **Same shape as MiscReader, applied to `%bucket['corporate']`** — read returns null when missing; read of existing entry returns the hash; write via `.corporate` raises; non-hash existing value raises on read.

### CorporateWriter

- **Same shape as MiscWriter, applied to `%bucket['corporate']`** — write succeeds and lazily creates the hash; read via `.corporate` raises; non-hash existing value raises on write.

### Pass-through preservation

- **misc entry is not stripped on serialization** — an object with `%bucket['misc'] = {key: 'v'}` (populated via any path) serializes to JSON with the misc entry present.
- **corporate entry is not stripped on serialization** — same for corporate.
- **misc entry is not validated** — arbitrary shapes inside `%bucket['misc']` round-trip without error (subject only to the top-level "must be a hash" invariant checked by these classes' methods).
- **corporate entry is not validated** — same for corporate.
- **misc and corporate are independent** — writing to one does not affect the other; both can carry hashes simultaneously.

### Composition

- **Adding a Reader + Writer duplicates the full class's surface** — a class stacking MiscReader and MiscWriter behaves like one stacking Misc alone.
- **Runtime add-then-use** — after `$obj.object.classes.ensure(Misc); $obj.misc[:k] = 'v'`, `$obj.misc[:k]` returns `'v'`.
- **Block-scope add releases the surface** — inside `$obj.object.classes.ensure(Misc) do ... end`, `.misc` works; after the block exits (assuming Misc was not already stacked), `.misc` raises.

## Related

- [bucket-access](https://puck.uno/requirements/built-in-classes/bucket-access) — the parallel utility classes for the whole bucket via `[]` / `[]=`.
- [object/structure § Bucket](https://puck.uno/requirements/built-in-classes/object/structure/#bucket) — what the bucket is and how the pass-through fields fit into the object structure.
