# Class Definition Format

<a id="overview"></a>
## 1 Overview

vibecode: {
	"section": "overview",
	"role": "explains how class definitions are stored in the mikobase",
	"key_concepts": ["records_history", "class_pk", "bucket", "puck.uno/record/class"]
}

A class definition is stored as a record in `records_history` with `class_pk` pointing to the
`puck.uno/record/class` record.

The class definition is stored in the `bucket` field.

<a id="universal-namespace"></a>
## 2 Universal Namespace

vibecode: {
	"section": "universal_namespace",
	"role": "defines the UNS naming convention for class names",
	"key_concepts": ["UNS", "domain-scoped_namespacing", "globally_unique_class_names"]
}

Class names use UNS — a URL without the `https://` protocol prefix. The domain provides a
globally unique namespace so developers using their own domains cannot accidentally collide.

Examples:

- `puck.uno/record`
- `puck.uno/reference`
- `foo.com/bar`
- `mycompany.com/character`

<a id="schema"></a>
## 3 Schema

vibecode: {
	"section": "schema",
	"role": "describes the top-level schema format and import rules",
	"key_concepts": ["classes_dict", "import_rules", "dependency_resolution", "parent-first_insertion"]
}

A full schema is a JSON object with a `classes` dict. Each key is the UNS class name and
each value is the class definition. The `name` field is not repeated inside the definition.

When a schema is imported, the class name is always taken from the dict key. Any `name` field
explicitly set inside a class definition is ignored and overwritten with the key value.

<a id="import-rules"></a>
### 3.1 Import Rules

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

<a id="class-name"></a>
## 4 Class Name

vibecode: {
	"section": "class_name",
	"role": "specifies the name field format and lists built-in seeded classes",
	"key_concepts": ["UNS_name_field", "built-in_classes", "puck.uno/record", "puck.uno/reference", "puck.uno/dbfile"]
}

Every class definition has a `name` field containing a UNS string.

```json
{
    "name": "foo.com/bar"
}
```

Built-in classes seeded as database records:

- `puck.uno/record` — base class for all records
- `puck.uno/record/class` — class for class definitions
- `puck.uno/reference` — reference to another record
- `puck.uno/dbfile` — file attachment

<a id="record-classes"></a>
## 5 Record Classes

vibecode: {
	"section": "record_classes",
	"role": "states that all schema-defined classes are record classes with no separate declaration",
	"key_concepts": ["record_class", "schema_classes", "assignable_to_records"]
}

All classes defined in the `classes` schema are record classes — they can be assigned to
records in `records_history`. There is no separate declaration required.

<a id="inheritance"></a>
## 6 Inheritance

vibecode: {
	"section": "inheritance",
	"role": "documents single-parent explicit inheritance via the inherits field",
	"key_concepts": ["inherits_field", "single_parent", "explicit_only", "no_path-implied_inheritance", "write-time_validation"]
}

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

<a id="fields"></a>
## 7 Fields

vibecode: {
	"section": "fields",
	"role": "defines field definition syntax and field name conventions",
	"key_concepts": ["fields_object", "field_definition", "snake_case", "class_constraint", "required", "collapse"]
}

A class definition may include a `fields` object. Each key is a field name, and each value is a
field definition object.

Field names are free-form, case-sensitive strings. Convention is `snake_case`.

```json
{
    "name": "foo.com/bar",
    "fields": {
        "surname": {"class": "string", "required": true, "collapse": true, "min_length": 1},
        "age":     {"class": "number", "integer_only": true, "min": 0}
    }
}
```

<a id="field-types"></a>
## 8 Field Types

vibecode: {
	"section": "field_types",
	"role": "enumerates all valid field type classes including primitives and UNS references",
	"key_concepts": ["string", "number", "boolean", "hash", "array", "puck.uno/reference", "puck.uno/dbfile", "UNS_class_reference"]
}

| Class | Description |
|---|---|
| `"string"` | Text value |
| `"number"` | Numeric value |
| `"boolean"` | True or false |
| `"url"` | URL string — validated as a well-formed URL |
| `"timestamp"` | ISO 8601 timestamp string with millisecond precision |
| `"hash"` | Anonymous nested object with its own inline field definitions |
| `"array"` | Untyped array |
| `"puck.uno/reference"` | Reference to another record |
| `"puck.uno/dbfile"` | File attachment |
| any UNS class name | Reference to a named class defined elsewhere in the schema |

<a id="inline-vs-named-field-types"></a>
## 9 Inline vs. Named Field Types

vibecode: {
	"section": "inline_vs_named_field_types",
	"role": "explains when constraints are inline vs. referenced by UNS name; hash of and default behavior",
	"key_concepts": ["inline_constraints", "UNS_reference", "hash_of", "hash_default", "anonymous_nested_objects"]
}

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

<a id="common-field-settings"></a>
## 10 Common Field Settings

vibecode: {
	"section": "common_field_settings",
	"role": "lists settings that apply to all or most field types",
	"key_concepts": ["required", "unique", "default", "instantiate"]
}

| Setting | Applies to | Description |
|---|---|---|
| `required` | all types | Field must be present and non-null |
| `unique` | all types | No two active records may share the same value for this field |
| `default` | all scalar types | Value to use when the field is absent on create |
| `instantiate` | `hash` only | If `true`, auto-create the nested object when absent, then apply sub-field defaults |

<a id="string-settings"></a>
## 11 String Settings

vibecode: {
	"section": "string_settings",
	"role": "lists constraints specific to string fields",
	"key_concepts": ["min_length", "max_length", "collapse"]
}

| Setting | Description |
|---|---|
| `min_length` | Minimum character length |
| `max_length` | Maximum character length |
| `collapse` | If `true`, trim leading/trailing whitespace and collapse internal whitespace runs to one space |

<a id="number-settings"></a>
## 12 Number Settings

vibecode: {
	"section": "number_settings",
	"role": "lists constraints specific to numeric fields",
	"key_concepts": ["min", "max", "gt", "lt", "gte", "lte", "integer_only", "multiple_of"]
}

| Setting | Description |
|---|---|
| `min` / `gte` | Value must be ≥ this (aliases) |
| `max` / `lte` | Value must be ≤ this (aliases) |
| `gt` | Value must be strictly > this |
| `lt` | Value must be strictly < this |
| `integer_only` | If `true`, reject fractional values |
| `multiple_of` | Value must be a multiple of this number |

<a id="array-and-hash-settings"></a>
## 13 Array and Hash Settings

vibecode: {
	"section": "array_and_hash_settings",
	"role": "lists element/key count constraints shared by array and hash types",
	"key_concepts": ["min_elements", "max_elements"]
}

| Setting | Description |
|---|---|
| `min_elements` | Minimum number of elements (array) or keys (hash) |
| `max_elements` | Maximum number of elements (array) or keys (hash) |

<a id="typed-arrays"></a>
## 14 Typed Arrays

vibecode: {
	"section": "typed_arrays",
	"role": "documents the of key for specifying element types in arrays",
	"key_concepts": ["array_of", "typed_array", "untyped_array", "inline_element_constraints"]
}

A typed array uses `"class": "array"` with an `"of"` key specifying the element type. `"of"` may be a plain class name string or a full inline field definition when element-level constraints are needed.

```json
{"class": "array", "of": "string"}
{"class": "array", "of": "borg.com/character"}
{"class": "array", "of": {"class": "string", "min_length": 1}}
```

An untyped array uses `"class": "array"` with no `"of"`.

<a id="reference-fields"></a>
## 15 Reference Fields

vibecode: {
	"section": "reference_fields",
	"role": "documents allowed_class and allowed_classes constraints on reference fields",
	"key_concepts": ["puck.uno/reference", "allowed_class", "allowed_classes", "subclass_valid"]
}

A `puck.uno/reference` field may optionally constrain which record classes it may point to
using `allowed_class` (single UNS name) and/or `allowed_classes` (array of UNS names). If both
are present they are merged. Any record of the specified class or a subclass is valid.

```json
{
    "class": "puck.uno/reference",
    "allowed_class": "foo.com/planet",
    "allowed_classes": ["foo.com/moon", "foo.com/station"]
}
```

<a id="object-representation"></a>
## 16 Object Representation

vibecode: {
	"section": "object_representation",
	"role": "defines hash form and shorthand form for object classes like reference and dbfile",
	"key_concepts": ["hash_form", "shorthand_form", "puck.uno/reference_shorthand", "puck.uno/dbfile_shorthand", "record_pk_string"]
}

Every object class can always be represented as a hash. Some object classes additionally
define a shorthand form for convenience. Both forms must always be accepted wherever that
class is expected.

For example, `puck.uno/reference` in hash form and shorthand form:

```json
{ "homeworld": {"pk": "92677339-df86-4f68-9397-999e40cf2c40"} }
```

```json
{ "homeworld": "92677339-df86-4f68-9397-999e40cf2c40" }
```

The shorthand for `puck.uno/reference` is a plain string containing the target `record_pk`.

`puck.uno/dbfile` follows the same pattern — hash form and shorthand form:

```json
{ "avatar": {"pk": "92677339-df86-4f68-9397-999e40cf2c40"} }
```

```json
{ "avatar": "92677339-df86-4f68-9397-999e40cf2c40" }
```

The shorthand for `puck.uno/dbfile` is a plain string containing the target `file_pk`.

<a id="file-fields"></a>
## 17 File Fields

vibecode: {
	"section": "file_fields",
	"role": "notes that dbfile fields only support the required constraint",
	"key_concepts": ["puck.uno/dbfile", "required_only", "no_other_constraints"]
}

`puck.uno/dbfile` fields support only `required`. No other constraints.

<a id="field-ordering"></a>
## 18 Field Ordering

vibecode: {
	"section": "field_ordering",
	"role": "specifies the canonical field order in query results",
	"key_concepts": ["ancestor_fields_first", "definition_order", "undefined_fields_last"]
}

Records returned from queries present fields in this order:

1. Fields defined in the parent class (recursively, outermost ancestor first)
2. Fields defined in the class itself, in definition order
3. Fields not defined in any class, in their stored order

<a id="unique-constraints"></a>
## 19 Unique Constraints

vibecode: {
	"section": "unique_constraints",
	"role": "documents single-field and multi-field unique constraints",
	"key_concepts": ["unique_true", "uniques_array", "multi-field_unique", "null_excluded", "write-time_error"]
}

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
        "person":  {"class": "puck.uno/reference", "required": true},
        "episode": {"class": "puck.uno/reference", "required": true}
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

<a id="joins"></a>
## 20 Joins

vibecode: {
	"section": "joins",
	"role": "documents the join shorthand that enforces required, unique, and immutable on a set of fields",
	"key_concepts": ["join_array", "required_fields", "unique_combined", "immutable_fields", "join_semantics"]
}

`join` is a class-level shorthand for defining join-style relationships between records. It
is an array of two or more field names.

```json
{
    "name": "borg.com/appearance",
    "fields": {
        "person":    {"class": "puck.uno/reference", "allowed_class": "borg.com/person"},
        "episode":   {"class": "puck.uno/reference", "allowed_class": "borg.com/episode"},
        "character": {"class": "puck.uno/reference", "allowed_class": "borg.com/character"}
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

<a id="unknown-fields"></a>
## 21 Unknown Fields

vibecode: {
	"section": "unknown_fields",
	"role": "states that undefined fields are stored as-is without validation",
	"key_concepts": ["unknown_fields", "no_validation", "stored_as-is", "open_schema"]
}

If a record's bucket contains a field not defined in its class, that field is stored as-is
without validation.
