# Record class resolution

~~~json
{"vibecode": {
	"doc": "record_class_resolution",
	"role": "specifies how the class of every value inside a record's bucket is determined; covers the coexisting mechanisms (default hash, schema-declared field class, reserved inline class key, custom_classes UUID marker) and the precedence rules when more than one signal is present",
	"status": "active_design; mechanisms_settled_individually; resolution_rules_when_they_overlap_pending",
	"audience": "Miko and Claude collaborating on the design",
	"related": ["ecoverse/worldlets/index.md", "ecoverse/standard-fields.md",
		"mikobase/class-definition.md"]
}}
~~~

This doc specifies how the class of every value inside a record's bucket gets determined. Several mechanisms coexist; this is where the interaction rules live. **Active design — the individual mechanisms are settled, the precedence rules when they overlap are not.**

The record's own class is trivially read from the record-level `class` field; this doc is about everything *inside* the bucket.

## The question

When the importer (or runtime) encounters a value inside a record's bucket, it has to decide: what class is this value an instance of? That answer determines method dispatch, validation, and how the value serializes back out.

Scalars and arrays answer themselves — they have implicit class identity (`puck.uno/string`, `puck.uno/number`, `puck.uno/array`, …) and need no declaration. **Hashes** are where the work happens, because a hash can mean many things.

## Mechanisms

Four ways a hash can declare (or default to) a class. They coexist within the same bucket — a worldlet author doesn't have to pick one in advance.

### Bare hash → `puck.uno/hash`

A hash with no class signal defaults to `puck.uno/hash`:

```json
"address": {"street": "1 Federation Way", "city": "Paris"}
```

The common case. No markers, no schema declaration needed.

### Schema-declared field class

The class definition declares a field with `class: "puck.uno/X"`. The bucket value is then the form that class accepts — usually a bare scalar or simple hash:

```json
// class def declares:  "photo": {"class": "puck.uno/dbfile"}
// bucket carries:
"photo": "f1a2b3c4-..."
```

The value carries no inline type signal — the schema tells the engine what kind of thing this is. The terse form is one such "shorthand the class accepts."

### Inline reserved `class` key

A hash with `class` as a sibling key declares its class inline, no schema declaration needed:

```json
"photo": {
    "class": "puck.uno/reference/file",
    "value": "f1a2b3c4-..."
}
```

This works anywhere a typed value is accepted. The reserved `class` field per [standard-fields.md](../ecoverse/standard-fields.md) makes the signal universally legible.

### Custom-class UUID marker

The hash carries a UUID-named marker key; a sibling `custom_classes` dict on the record maps that UUID to a UNS class name:

```json
{
    "class": "starfleet.com/officer",
    "bucket": {
        "photo": {
            "<uuid>": true,
            "value": "f1a2b3c4-..."
        }
    },
    "custom_classes": {
        "<uuid>": "puck.uno/reference/file"
    }
}
```

The marker key is a real UUID (shown as `<uuid>` for legibility). Functionally equivalent to the inline `class` form, but the value hash doesn't use the reserved `class` key — useful when the value's hash wants `class` as application data, or when the author prefers not to bring the reserved-key vocabulary into a bucket whose field isn't declared in the schema.

Notably this lets a class definition stay narrow (e.g. officer declares no `photo` field at all) while still allowing typed objects to live in any bucket entry. For most fields this is overkill — JSON primitives cover the common case — but it's the escape hatch when arbitrary typed values need to ride along.

## Resolution rules

**Settled.** Resolution is a two-step pass over the bucket. Custom-class markers take precedence; schema field definitions fill in the rest.

### Step 1: custom_classes pass

Recursively scan every hash inside the bucket. For any key that appears in the record's `custom_classes` dict, the **enclosing hash** is instantiated as the class named by that entry. The matching key is the type marker (its value is conventionally `true`); the rest of the hash is the typed object's data, interpreted per that class's normal rules (compact / long / whole-hash forms, etc.).

This pass runs first, before any schema field definitions are consulted. Recursion is unconditional: any hash anywhere inside the bucket gets scanned.

### Step 2: schema pass

For whatever Step 1 left untyped, the class's field definitions take over. Each field definition points to a specific location in the bucket and specifies what class to instantiate at that location, using whatever value sits there.

### Default for untyped hashes

A hash that neither pass typed defaults to `puck.uno/hash`. Scalars and arrays carry implicit class identity (`puck.uno/string`, `puck.uno/number`, `puck.uno/array`, …) and never need either pass.

### Precedence summary (class only)

1. **custom_classes UUID marker** wins everything.
2. **Schema-declared field class** types whatever the first pass left untyped.
3. **Default `puck.uno/hash`** for any hash both passes leave untyped.
4. **Implicit class** for scalars and arrays — always.

### Field metadata beyond class

A field definition carries more than just `class`. It can also carry `required`, normalizers, defaults, range constraints, and so on. **All of that metadata applies to the value at the field's location regardless of which step typed it.** The two-step algorithm above resolves *what class the value is an instance of*; the field's other constraints still apply on top, every time.

So a class can declare a field with no class at all — just constraints — and a `custom_classes`-typed object can sit there cleanly:

```json
// class:
"fields": {
    "photo": {"required": true}
}

// record bucket:
"photo": {
    "<uuid>": true,
    "url": "https://photo.bar/picard"
}
// + record-level "custom_classes": {"<uuid>": "puck.uno/url"}
```

The field says "something must be here" (required) without specifying what. The value is typed as `puck.uno/url` by Step 1. No conflict — the constraints (just `required`) are satisfied; the class came from the marker.

### Class conflicts: field declares class X, custom_classes assigns class Y

When the field's declared `class` AND a custom_classes marker BOTH apply to the same location and disagree:

- **At read time** (loading an existing record): the custom_classes class wins, but the engine emits a warning. The record loads.
- **At write time** (importing a new record, or updating one): the import is **rejected**. The record is not saved.

Reasoning: a field's declared class is a requirement, not a suggestion. Once a developer declared the field as class X, the system enforces that on every write. Existing records that predate the class change (or that were imported under a now-stale schema) still load — with a warning — so the data isn't lost, but no new conflict can enter the database.

This split keeps backward compatibility for already-stored records (no silent data loss) while enforcing the schema strictly going forward. Aligns with the ["no nanny code"](https://puck.uno/documentation/overview#no-nanny-code) principle for already-stored data (it loads, the developer chose to keep it) and "the slob" principle for visibility (warnings are issued, not silent).

### Scoping of custom_classes

`custom_classes` is record-scoped (sibling to `bucket`); no worldlet-level fallback. Each record's `custom_classes` applies to its own bucket only.

**Open: sub-record boundary.** If a bucket field's value is itself a full sub-record (its own `class`+`bucket` shape, optionally its own `custom_classes`), does the outer record's `custom_classes` reach into that sub-hash, or stop at the boundary? Tentative answer: stops at the boundary — a sub-record is its own scope and carries its own `custom_classes` if it needs typed children.

### Marker without entry

A UUID-shaped key in a bucket hash that does *not* appear in `custom_classes` is just data. The mechanism activates only when the key is listed in `custom_classes`; absence-from-the-dict means absence-of-marker. Closed by the wording of the Step 1 rule ("any UUID keys that are listed in custom_classes").

### Inline reserved `class` key

[standard-fields.md](../ecoverse/standard-fields.md) reserves `class` as a pass-through field anywhere in the Puckverse, and the worldlets spec uses `{class, value}` and `{class, bucket}` as the inline-typed object form. The Step-1 / Step-2 rule above doesn't mention this form. **Open: does the inline `class` key still type a hash inside a bucket, alongside custom_classes, or has custom_classes superseded it for in-bucket use?**

If both still apply, the precedence order needs a tie-break rule (e.g. inline `class` is the most-local signal so wins over `custom_classes`, OR `custom_classes` always wins because it's the record-level mechanism).

## Summary

**Settled:**

- Two-step resolution: custom_classes pass first, schema pass second.
- Step 1 recurses through all nested hashes in the bucket; matching UUID-key markers type the enclosing hash.
- Step 2 uses the class's field definitions to type whatever Step 1 left untyped.
- Field metadata beyond class (`required`, normalizers, etc.) always applies, regardless of which step typed the value. Fields can declare constraints with no `class`.
- Conflicts between a field's declared `class` and a custom_classes-assigned class: read time accepts with a warning (custom_classes wins); write time rejects the import. The schema is enforced strictly forward; existing records aren't broken retroactively.
- Bare hashes default to `puck.uno/hash`; scalars and arrays carry implicit class.
- `custom_classes` is record-scoped (sibling to `bucket`); no worldlet-level fallback.
- `custom_classes` keys are UUIDs.
- A UUID-shaped key not listed in `custom_classes` is just data, not a marker.

**Open:**

- Sub-record boundary: does the outer record's `custom_classes` reach into a hash that's itself a full sub-record, or stop at its boundary?
- Inline `class` key form: still a valid third typing signal alongside `custom_classes`, or superseded for in-bucket use? If still valid, the precedence between inline `class` and `custom_classes` needs a tie-break.
- Unused `custom_classes` entries: error, warn, or fine?

Resolve one at a time. Each decision feeds back into [worldlets/index.md](worldlets/index.md).
