# Class Definition Format

## Overview

A class definition is stored as a record in `records_history` with `class_pk` pointing to the
`mikobase.com/record/class` record.

The class definition is stored in the `bucket` field.

## Universal Namespace (UNS)

Class names use UNS — a URL without the `https://` protocol prefix. The domain provides a
globally unique namespace so developers using their own domains cannot accidentally collide.

Examples:

- `mikobase.com/record`
- `mikobase.com/reference`
- `foo.com/bar`
- `mycompany.com/character`

## Schema

A full schema is a JSON object with a `classes` dict. Each key is the UNS class name and
each value is the class definition. The `name` field is not repeated inside the definition.

When a schema is imported, the class name is always taken from the dict key. Any `name` field
explicitly set inside a class definition is ignored and overwritten with the key value.

### Import Rules

- Importing a class that does not yet exist creates a new record.
- Importing a class that already exists appends a new `records_history` row with the updated
  definition.
- Importing a schema does not delete classes that are absent from the schema.
- Before any records are written, the engine validates that every class referenced via
  `inherits` is either already in the database or defined within the same schema. If any
  referenced class is missing, the entire import fails and nothing is written.
- Classes within the schema do not need to be ordered. The engine resolves dependencies and
  inserts classes parent-first.

```json
{
    "classes": {
        "foo.com/name": {
            "fields": {
                "surname": {"class": "string"},
                "given":   {"class": "string"}
            }
        },
        "foo.com/gup": {
            "fields": {
                "name": {"class": "foo.com/name"}
            }
        }
    }
}
```

## Class Name

Every class definition has a `name` field containing a UNS string.

```json
{
    "name": "foo.com/bar"
}
```

Built-in classes seeded as database records:

- `mikobase.com/record` — base class for all records
- `mikobase.com/record/class` — class for class definitions
- `mikobase.com/reference` — reference to another record
- `mikobase.com/dbfile` — file attachment

## Record Classes vs. Object Classes

A class is either a **record class** (can be assigned to records in `records_history`) or an
**object class** (used only for embedded objects via `custom_classes`).

A class must explicitly declare itself as a record class. A class with no such declaration is an
object class only and cannot be used as a record class.

Two equivalent ways to declare a record class:

```json
{ "name": "foo.com/bar", "record_class": true }
```

```json
{ "name": "foo.com/bar", "inherits": "mikobase.com/record" }
```

`"record_class": true` is shorthand for `"inherits": "mikobase.com/record"`.

If both `record_class: true` and `inherits` are present, the `inherits` target must be
`mikobase.com/record` or a descendant of it — otherwise it is an error.

A class that inherits from a record class is itself a record class without needing an explicit
declaration.

## Inheritance

A class inherits all field definitions from its parent class. Subclasses may override or extend
inherited fields.

Inheritance is always explicit via the `inherits` field. There is no path-implied inheritance.

```json
{
    "name": "mycompany.com/character",
    "inherits": "othercompany.com/person"
}
```

Only one parent is allowed.

Validation of a record always uses the latest active version of its class definition at the time
of the write. Previously written records are not retroactively invalidated by class changes.

## Fields

A class definition may include a `fields` object. Each key is a field name, and each value is a
field definition object.

Field names are free-form, case-sensitive strings. Convention is `snake_case`.

```json
{
    "name": "foo.com/bar",
    "record_class": true,
    "fields": {
        "surname": {"class": "string", "required": true, "collapse": true, "min_length": 1},
        "age":     {"class": "number", "integer_only": true, "min": 0}
    }
}
```

## Field Types

| Class | Description |
|---|---|
| `"string"` | Text value |
| `"number"` | Numeric value |
| `"boolean"` | True or false |
| `"url"` | URL string — validated as a well-formed URL |
| `"timestamp"` | ISO 8601 timestamp string with millisecond precision |
| `"hash"` | Anonymous nested object with its own inline field definitions |
| `"array"` | Untyped array |
| `"mikobase.com/reference"` | Reference to another record |
| `"mikobase.com/dbfile"` | File attachment |
| any UNS class name | Reference to a named class defined elsewhere in the schema |

## Inline vs. Named Field Types

Only basic types (`string`, `number`, `boolean`, `url`, `timestamp`, `hash`, `array`) may
have constraints defined inline in the field definition.

Custom classes (e.g. `"foo.com/name"`) are referenced by UNS name only. Their structure is
defined in a separate class definition in the schema. No inline `fields` or constraints are
added to a field that uses a custom class.

The exception is `hash`, which may define `fields` inline for anonymous nested objects.

A hash may also specify `"of"` to set the type of all its fields. When `"of"` is present,
explicit field definitions in `"fields"` may omit `"class"` — it is inherited from `"of"`.
Fields not listed in `"fields"` are also validated against the `"of"` type.

A hash may specify `"default"` to provide settings that apply to all fields. Explicit field
definitions in `"fields"` extend or override these defaults.

These two definitions are equivalent:

```json
"name": {
    "class": "hash",
    "of": "string",
    "fields": {
        "surname": {"class": "string", "required": true, "collapse": true},
        "middle":  {"class": "string", "collapse": true},
        "given":   {"class": "string", "collapse": true}
    }
}
```

```json
"name": {
    "class": "hash",
    "of": "string",
    "default": {"collapse": true},
    "fields": {
        "surname": {"required": true},
        "middle":  {},
        "given":   {}
    }
}
```

In the second form, `"of"` sets the type for all fields and `"default"` supplies `collapse:
true` to all of them. Explicit entries in `"fields"` only need to state what differs —
`surname` adds `required: true`; `middle` and `given` have nothing further to add.

A hash with `"of"` and no `"fields"` is a fully open dict where all values must be of
that type:

```json
"labels": {"class": "hash", "of": "string"}
```

## Common Field Settings

| Setting | Applies to | Description |
|---|---|---|
| `required` | all types | Field must be present and non-null |
| `unique` | all types | No two active records may share the same value for this field |
| `default` | all scalar types | Value to use when the field is absent on create |
| `instantiate` | `hash` only | If `true`, auto-create the nested object when absent, then apply sub-field defaults |

## String Settings

| Setting | Description |
|---|---|
| `min_length` | Minimum character length |
| `max_length` | Maximum character length |
| `collapse` | If `true`, trim leading/trailing whitespace and collapse internal whitespace runs to one space |

## Number Settings

| Setting | Description |
|---|---|
| `min` / `gte` | Value must be ≥ this (aliases) |
| `max` / `lte` | Value must be ≤ this (aliases) |
| `gt` | Value must be strictly > this |
| `lt` | Value must be strictly < this |
| `integer_only` | If `true`, reject fractional values |
| `multiple_of` | Value must be a multiple of this number |

## Array and Hash Settings

| Setting | Description |
|---|---|
| `min_elements` | Minimum number of elements (array) or keys (hash) |
| `max_elements` | Maximum number of elements (array) or keys (hash) |

## Typed Arrays

A typed array uses `"class": "array"` with an `"of"` key specifying the element type. `"of"` may be a plain class name string or a full inline field definition when element-level constraints are needed.

```json
{"class": "array", "of": "string"}
{"class": "array", "of": "borg.com/character"}
{"class": "array", "of": {"class": "string", "min_length": 1}}
```

An untyped array uses `"class": "array"` with no `"of"`.

## Reference Fields

A `mikobase.com/reference` field may optionally constrain which record classes it may point to
using `allowed_class` (single UNS name) and/or `allowed_classes` (array of UNS names). If both
are present they are merged. Any record of the specified class or a subclass is valid.

```json
{
    "class": "mikobase.com/reference",
    "allowed_class": "foo.com/planet",
    "allowed_classes": ["foo.com/moon", "foo.com/station"]
}
```

## Object Representation

Every object class can always be represented as a hash. Some object classes additionally
define a shorthand form for convenience. Both forms must always be accepted wherever that
class is expected.

For example, `mikobase.com/reference` in hash form and shorthand form:

```json
{ "homeworld": {"pk": "92677339-df86-4f68-9397-999e40cf2c40"} }
```

```json
{ "homeworld": "92677339-df86-4f68-9397-999e40cf2c40" }
```

The shorthand for `mikobase.com/reference` is a plain string containing the target `record_pk`.

`mikobase.com/dbfile` follows the same pattern — hash form and shorthand form:

```json
{ "avatar": {"pk": "92677339-df86-4f68-9397-999e40cf2c40"} }
```

```json
{ "avatar": "92677339-df86-4f68-9397-999e40cf2c40" }
```

The shorthand for `mikobase.com/dbfile` is a plain string containing the target `file_pk`.

## File Fields

`mikobase.com/dbfile` fields support only `required`. No other constraints.

## Field Ordering

Records returned from queries present fields in this order:

1. Fields defined in the parent class (recursively, outermost ancestor first)
2. Fields defined in the class itself, in definition order
3. Fields not defined in any class, in their stored order

## Unique Constraints

A single field is made unique with `"unique": true` in the field definition:

```json
"slug": {"class": "string", "required": true, "unique": true}
```

`uniques` is a class-level array for multi-field unique constraints. Each inner array
defines a set of fields whose combined values must be unique among all active records of
that class:

```json
{
    "name": "borg.com/appearance",
    "fields": {
        "person":  {"class": "mikobase.com/reference", "required": true},
        "episode": {"class": "mikobase.com/reference", "required": true}
    },
    "uniques": [
        ["person", "episode"]
    ]
}
```

- Any field type may participate in a unique constraint.
- Fields with null values are excluded from uniqueness checks — two records may both have
  null for a field that is part of a unique set.
- A unique constraint violation on `create` or `update` is a write-time error.
- Multiple independent `uniques` constraints may be declared.

## Joins

`join` is a class-level shorthand for defining join-style relationships between records. It
is an array of two or more field names.

```json
{
    "name": "borg.com/appearance",
    "record_class": true,
    "fields": {
        "person":    {"class": "mikobase.com/reference", "allowed_class": "borg.com/person"},
        "episode":   {"class": "mikobase.com/reference", "allowed_class": "borg.com/episode"},
        "character": {"class": "mikobase.com/reference", "allowed_class": "borg.com/character"}
    },
    "join": ["person", "episode", "character"]
}
```

`join: ["person", "episode", "character"]` expands to:

- `required: true` on each listed field
- A unique constraint on the combined values of those fields (equivalent to adding
  `["person", "episode", "character"]` to `uniques`)
- Those fields are **immutable** — once written, they cannot be changed via `update`

Joins are directional by nature of named fields: field order in the array has no effect on
semantics — direction is determined by which field holds which reference.

Additional fields beyond those listed in `join` may be defined and updated normally.

## Unknown Fields

If a record's bucket contains a field not defined in its class, that field is stored as-is
without validation.
