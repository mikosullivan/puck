# `misc` and `corporate` utility classes
<!--index: 9-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_built_in_misc_and_corporate",
	"role": "spec for six built-in utility classes that expose the reserved pass-through bucket entries `misc` and `corporate` — one full-access class (Misc, Corporate), one read-only variant (MiscReader, CorporateReader), and one write-only variant (MiscWriter, CorporateWriter) for each field. Each contributes a same-named method (`.misc`, `.corporate`) with the capability shape the class declares. The hash is lazily created on write; any existing non-hash value at the target key raises.",
	"status": "draft — six classes named with canonical URLs and their contributed methods; the write-only capability shape is spec'd but should be reviewed once concrete use lands",
	"audience": "developers writing Caspian classes; anyone reasoning about the reserved pass-through fields `misc` and `corporate`"
}}
~~~

Six utility classes come in a matched pair of three, one triple for the `misc` bucket entry and one for `corporate`. They contribute a same-named accessor method (`.misc` or `.corporate`) that reaches directly into `%bucket['misc']` or `%bucket['corporate']` respectively.

The two triples exist because the [pass-through fields spec](https://puck.uno/documentation/requirements/caspian/built-in-classes/object/structure/) distinguishes `misc` (ungoverned free-rider) from `corporate` (governed by declared conventions); the mechanics are identical but the two triples exist so a class author can grant capability to whichever field matches the governance posture they're declaring.

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

## Related

- [bucket-access](https://puck.uno/documentation/requirements/caspian/built-in-classes/bucket-access) — the parallel utility classes for the whole bucket via `[]` / `[]=`.
- [object/structure § Bucket](https://puck.uno/documentation/requirements/caspian/built-in-classes/object/structure/#bucket) — what the bucket is and how the pass-through fields fit into the object structure.
