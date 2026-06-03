# Mikobase record-shape migration log

~~~json
{"vibecode": {
	"doc": "mikobase_migration",
	"role": "one-time log of the record-shape migration from single-class to multi-platter; informs future maintainers reading old example files that pre-date the change",
	"status": "historical — captures a 2026-05-27 spec change",
	"key_concepts": ["single_class_to_classes_hash", "platter_model_alignment",
		"non_migrated_example_files", "field_annotations_unchanged"]
}}
~~~

## What changed

The record shape moved from **single-class** to the **multi-platter
model**, aligning Mikobase records with the universal Caspian object
shape described in
[base-class-use.md](../ideas/base-class-use.md#per-platter-buckets).

## Before

```json
"e1b2c3d4-...": {
    "class": "starfleet.com/officer",
    "created_at": "2364-01-01T00:00:00.000Z",
    "bucket": {"name": "Picard, Jean-Luc", "rank": "Captain", "serial": "SP-937-215"}
}
```

The record had one `class` field naming a single UNS class.

## After

```json
"e1b2c3d4-...": {
    "classes": {
        "p1a2b3c4-...": {
            "class": "starfleet.com/officer",
            "bucket": {}
        }
    },
    "created_at": "2364-01-01T00:00:00.000Z",
    "bucket": {"name": "Picard, Jean-Luc", "rank": "Captain", "serial": "SP-937-215"}
}
```

The record has a `classes` hash keyed by platter ID. Each platter is
`{class, bucket}` per the platter model. A record can carry multiple
platters (mix-ins, cross-cutting markers, etc.); a record with a single
class still has one platter.

## Where field values live

For ordinary records, **user-facing field values (those declared by the
record's class definitions) live in the top-level `bucket`**. The
platter's own `bucket` is for class-internal state (mix-in bookkeeping,
cross-cutting markers, sticky state). For most simple records, the
platter's bucket is empty.

Class-definition records are the exception: their `puck.uno/record/class`
platter's bucket holds the definition itself (name, fields, inherits).
See [class-definition.md](class-definition.md).

## What was migrated

| File | Status |
|---|---|
| [worldlets/index.md](worldlets/index.md) | Migrated — records section, validation rules, minimal example, complete example |
| [Puckai conversation](../ecoverse/puckai/conversation/) | Migrated — records example |
| [q0.md](q0.md) | No change needed — `create` action keeps its single-`class` API shorthand; engine wraps in a platter automatically |
| [mikobase.md](index.md) | No change needed — its `{class: ...}` references were field-type annotations, not record-shape |
| [class-definition.md](class-definition.md) | No change needed — already migrated earlier |
| [requirements.md](requirements.md) | No change needed — already migrated earlier |
| [sqlite-schema.md](sqlite-schema.md), [sqlite.sql](sqlite.sql) | No change needed — the `class` column was dropped earlier in favor of a `classes` JSON column |

## What was NOT migrated

The Puckai example JSON files under
[puckai/conversation/examples/](../ecoverse/puckai/conversation/examples/) still use the pre-migration single-class shape.
These are example data files, not spec — they can be regenerated or
hand-migrated when Puckai is next actively exercised.

Field-type annotations like `{"class": "string"}` inside class
definitions describe field TYPES and are unrelated to the record-shape
change. They look similar to the old single-class record form but mean
something different. They were not migrated.

## How to tell old shape from new at a glance

| Sign | Likely meaning |
|---|---|
| Top-level keys `class` + `bucket` directly on a record | Old single-class shape |
| Top-level keys `classes` (plural, a hash) + `bucket` | New platter shape |
| `{"class": "string"}` inside a class definition's `fields` block | Field-type annotation (unchanged by the migration) |

## Why this happened

The platter model unified how Caspian objects, Mikobase records, and
class definitions structure their classification. Skeletor's
`objects` hash and Mikobase's `records` hash converged on the same
`{classes, bucket}` shape (see
[#160](https://github.com/mikosullivan/puck/issues/160)). Mikobase's
single-class records were drift from that uniform model; this migration
brings them into line.
