# Worldlet Format

<a id="overview"></a>
## 1 Overview

~~~json
{"vibecode": {
	"section": "overview",
	"topic": "worldlet_format"
}}
~~~

A worldlet is a complete mikobase — classes, records, and files — packaged as a single
JSON object. It is the standard format for sharing and distributing mikobases.

**Worldlets are non-temporal.** Each record is stored as a single object with its
current bucket; there is no version history. A worldlet represents a snapshot of a
conversation, scenario, or scratch space, not an audit log. See
[mikobase.md](../mikobase.md#temporal-vs-non-temporal-mode) for the full mode rules.

A worldlet is imported into a running mikobase. The importer creates the classes, inserts
the records, and stores any file attachments. PKs are preserved exactly as exported, so
references between records remain valid after import. The target mikobase must be
non-temporal — importing a worldlet into a temporal mikobase raises an exception.

---

<a id="top-level-structure"></a>
## 2 Top-Level Structure

~~~json
{"vibecode": {
	"section": "top_level_structure",
	"topic": "worldlet_format"
}}
~~~

```json
{
    "format":       "worldlet",
    "format_version": "1.0",
    "meta":         { ... },
    "properties":   { ... },
    "allow":        [ ... ],
    "extensions":   { ... },
    "classes":      { ... },
    "records":      { ... },
    "files":        { ... },
    "file_chunks":  { ... }
}
```

A worldlet is a **serialized export** of a mikobase, not a mikobase itself.
A live mikobase is always engine-backed (SQLite in v1); worldlets are pure
data on disk produced by an export and consumed by an import. See
[mikobase.md § Export formats](../mikobase.md#export-formats-akira) for
the broader export-format picture.

A worldlet's required keys depend on its `temporal` flag (see
[mikobase.md § Temporal vs Non-temporal Mode](../mikobase.md#temporal-vs-non-temporal-mode)):

- **Temporal worldlets** (the default): `history` is required; `records` is
  optional (the engine infers identity stubs from history if absent).
- **Non-temporal worldlets** (`"temporal": false` at the top level): `records`
  is required and carries each record's current bucket directly; `history` is
  not part of the format.

All other top-level keys default to empty structures if absent.

This document describes the **non-temporal** worldlet shape — records carry
their current bucket directly. For the temporal shape with per-version history
entries, see
[ai-conversation-format.md](../ai-conversation-format.md).

---

<a id="meta"></a>
## 3 `meta`

~~~json
{"vibecode": {
	"section": "meta",
	"fields": ["name", "author", "version"],
	"purpose": "descriptive_metadata_about_the_worldlet"
}}
~~~

Descriptive information about the worldlet.

```json
"meta": {
    "name":        "Starfleet Personnel",
    "author":      "starfleet.com",
    "version":     "1.0.0",
    "description": "Personnel records for Starfleet officers and ships.",
    "created_at":  "2364-01-01T00:00:00.000Z"
}
```

| Field         | Required | Description |
|---------------|----------|-------------|
| `name`        | no       | Human-readable name |
| `author`      | no       | UNS domain of the publisher |
| `version`     | no       | Semver string |
| `description` | no       | Free-text description of the worldlet's contents |
| `created_at`  | no       | ISO 8601 timestamp of when the worldlet was exported |

---

<a id="format-and-format_version"></a>
## 4 `format` and `format_version`

~~~json
{"vibecode": {
	"section": "format_and_format_version",
	"fields": ["format", "format_version"],
	"purpose": "format_identity_and_versioning"
}}
~~~

Two optional top-level strings that identify the document type and spec version.

```json
"format": "worldlet",
"format_version": "1.0"
```

| Field            | Required | Description |
|------------------|----------|-------------|
| `format`         | no       | Fixed string `"worldlet"`. Identifies this as a worldlet document. |
| `format_version` | no       | Semver string. Current version is `"1.0"`. |

Both are optional for backwards compatibility but should be included in all new worldlets.

**Engine behaviour on import:**

- Unknown `format_version` — warn and attempt import.
- Unknown `format` string — refuse import.
- Both absent — attempt import without warning.

---

<a id="properties"></a>
## 5 `properties`

~~~json
{"vibecode": {
	"section": "properties",
	"fields": ["executable", "temporal"],
	"purpose": "database_level_metadata_readable_by_any_client_or_agent"
}}
~~~

Database-level properties that describe the mikobase itself. Any client or agent
connecting to or importing the worldlet should read these before interacting with
the data.

```json
"properties": {
    "executable": true,
    "temporal":   false
}
```

| Field        | Type    | Default | Description |
|--------------|---------|---------|-------------|
| `executable` | boolean | `false` | Advisory: code in this mikobase may be executed. Default is non-executable; allowing execution requires a positive assertion |
| `temporal`   | boolean | `false` | Whether the imported mikobase keeps record version history. Worldlets are non-temporal by default; setting `true` requests a temporal target mikobase |

`executable` is an advisory, not an enforcement mechanism. The engine does not prevent
or permit execution on its own — the field communicates the publisher's intent. Clients
and agents are responsible for respecting it. The default of `false` means a worldlet
imported with no `properties` block (or with `properties: {}`) is treated as data-only.

`temporal` declares whether the worldlet expects to be imported into a temporal or
non-temporal mikobase. The default `false` matches the worldlet format's non-temporal
shape (each record carries its current bucket directly, no history block). See
[mikobase.md](../mikobase.md#temporal-vs-non-temporal-mode) for the full mode rules.

---

<a id="allow"></a>
## 6 `allow`

~~~json
{"vibecode": {
	"section": "allow",
	"type": "array",
	"purpose": "external_resources_requiring_host_approval_before_import"
}}
~~~

An array of external resources the worldlet requires access to. The host presents these to
the user for approval before importing. Nothing is granted silently.

```json
"allow": ["api.starfleet.com"]
```

The format and full capability vocabulary are not yet fully designed.

---

<a id="extensions"></a>
## 7 `extensions`

~~~json
{"vibecode": {
	"section": "extensions",
	"purpose": "reserved_for_future_security_and_registry_metadata",
	"status": "reserved"
}}
~~~

A reserved top-level object for future extension metadata — signatures, canonicalization
algorithm declarations, registry information, and similar. The structure of this object
is not defined in v1.

Engines must ignore any `extensions` value silently. Never refuse import because of an
unrecognised `extensions` key.

```json
"extensions": {}
```

---

<a id="classes"></a>
## 8 `classes`

~~~json
{"vibecode": {
	"section": "classes",
	"format": "dict_keyed_by_uns_class_name",
	"methods_as": "fields_with_class_function_and_charlie_key",
	"see": "class-definition.md"
}}
~~~

The schema, using the standard class definition format. Each key is a UNS class name; each
value is the class definition. All classes defined here are record classes.

Methods are defined as fields with `"class": "function"` and a `"charlie"` key containing
Charlie source. Multiline strings use literal newlines; leading indentation is stripped by
the importer.

```json
"classes": {
    "starfleet.com/person": {
        "fields": {
            "name":      {"class": "string", "required": true, "collapse": true},
            "birthdate": {"class": "string"},
            "species":   {"class": "string", "default": "Human"},

            "greet": {
                "class": "function",
                "charlie": "
                    function &greet
                        'Hello, I am ' + @name
                    end
                "
            }
        }
    },

    "starfleet.com/officer": {
        "inherits": "starfleet.com/person",
        "fields": {
            "rank":   {"class": "string",  "required": true},
            "serial": {"class": "string",  "required": true, "unique": true},
            "active": {"class": "boolean", "default": true},
            "photo":  {"class": "puck.uno/dbfile"},

            "summary": {
                "class": "function",
                "charlie": "
                    function &summary
                        @rank + ' ' + @name + ' (' + @serial + ')'
                    end
                "
            },

            "promote": {
                "class": "function",
                "charlie": "
                    function &promote(new_rank:)
                        @rank = new_rank
                        self
                    end
                "
            }
        }
    },

    "starfleet.com/ship": {
        "fields": {
            "name":       {"class": "string", "required": true, "unique": true},
            "registry":   {"class": "string", "required": true, "unique": true},
            "ship_class": {"class": "string"}
        },
        "join": ["name", "registry"]
    }
}
```

See [class-definition.md](../../charlie/class-definition.md) for the full class definition format.

---

<a id="records"></a>
## 9 `records`

~~~json
{"vibecode": {
	"section": "records",
	"format": "dict_keyed_by_uuid",
	"fields": ["class", "created_at", "bucket"]
}}
~~~

A dict of records, keyed by record UUID. Each entry carries the record's class, its
creation timestamp, and its current bucket directly. Worldlets are non-temporal — there
is no separate history block and no per-version entries.

```json
"records": {
    "e1b2c3d4-0001-0001-0001-000000000001": {
        "class":      "starfleet.com/officer",
        "created_at": "2364-01-01T00:00:00.000Z",
        "bucket":     {"name": "Picard, Jean-Luc", "rank": "Captain", "serial": "SP-937-215"}
    }
}
```

| Field        | Required | Description |
|--------------|----------|-------------|
| `class`      | yes      | UNS class name |
| `created_at` | no       | ISO 8601 timestamp with millisecond precision; record-level metadata, not bucket data |
| `bucket`     | yes      | The record's field values |

---

<a id="files"></a>
## 10 `files`

~~~json
{"vibecode": {
	"section": "files",
	"format": "dict_keyed_by_file_uuid",
	"fields": ["sha256", "created_at", "mime.type", "mime.encoding"]
}}
~~~

A dict of file records, keyed by file UUID. Describes each attached file — its integrity
hash, timestamp, and MIME type.

```json
"files": {
    "d1e2f3a4-0001-0001-0001-000000000001": {
        "sha256":     "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "created_at": "2364-01-01T00:00:00.000Z",
        "mime": {
            "type":     "image/png",
            "encoding": "base64"
        }
    }
}
```

| Field        | Description |
|--------------|-------------|
| `sha256`     | SHA-256 hash of the complete file content, for integrity verification |
| `created_at` | ISO 8601 timestamp |
| `mime.type`  | MIME type of the file |
| `mime.encoding` | Encoding used for chunk data (e.g. `"base64"`) |

---

<a id="file_chunks"></a>
## 11 `file_chunks`

A dict of file chunks, keyed by chunk UUID. A file's binary content is split across one
or more chunks. Chunks are assembled in `index` order to reconstruct the file.

```json
"file_chunks": {
    "c1d2e3f4-0001-0001-0001-000000000001": {
        "file":  "d1e2f3a4-0001-0001-0001-000000000001",
        "index": 0,
        "last":  true,
        "data":  "base64encodeddata..."
    }
}
```

| Field   | Description |
|---------|-------------|
| `file`  | UUID of the parent file record |
| `index` | Zero-based chunk position |
| `last`  | `true` on the final chunk — positive confirmation that the file was saved completely. A file with no chunk where `last` is `true` is incomplete. |
| `data`  | Chunk content, encoded per the file's `mime.encoding` |

---

<a id="import-rules"></a>
## 12 Import Rules

~~~json
{"vibecode": {
	"section": "import_rules",
	"purpose": "defines_uuid_constraints_conflict_policy_validation_and_atomicity"
}}
~~~

<a id="uuid-constraints"></a>
### 12.1 UUID constraints

All keys in `records`, `files`, and `file_chunks` must be UUID v4 strings. The importer
rejects any worldlet containing a malformed UUID.

<a id="conflict-policy"></a>
### 12.2 Conflict policy

When a record being imported has the same UUID as one already in the target mikobase:

- **Identical content** — skip silently. Import is idempotent.
- **Different content** — error. The import of the entire worldlet is aborted.

The same rule applies to `files` and `file_chunks` entries.

<a id="reference-encoding"></a>
### 12.3 Reference encoding

Reference fields in `bucket` are plain UUID strings. The class definition declares the
field type — a field with class `puck.uno/reference` or `puck.uno/dbfile` tells the
engine the value is a reference. No special wrapper syntax is used in the bucket itself.

<a id="the-class-field"></a>
### 12.4 The `class` field

In all Puck-compliant hashes, the `class` field is reserved to indicate the class or
classes the hash belongs to. This applies to Q0 queries, record entries, class
definitions, and any other Puck-level objects.

Bucket objects are not Puck-compliant. The `class` field has no special meaning inside
a bucket and may be used freely as an application field.

<a id="validation"></a>
### 12.5 Validation

The importer validates the following before writing anything:

- All record entries have a `class` and a `bucket`.
- All `class` values are either built-in classes or defined in `classes` or already
  present in the target mikobase.
- All `file` values in `file_chunks` reference a UUID present in `files`.
- The target mikobase is non-temporal.

<a id="atomicity"></a>
### 12.6 Atomicity

Import is all-or-nothing. If any validation error or conflict error occurs, nothing is
written to the target mikobase. Partial imports do not happen.

---

<a id="minimal-valid-example"></a>
## 13 Minimal Valid Example

The smallest possible worldlet — one record, no schema, no files:

```json
{
    "format": "worldlet",
    "format_version": "1.0",
    "records": {
        "e1b2c3d4-0001-0001-0001-000000000001": {
            "class":  "puck.uno/record",
            "bucket": {"note": "hello"}
        }
    }
}
```

`classes` is omitted — `puck.uno/record` is a built-in class.

---

<a id="complete-example"></a>
## 14 Complete Example

```json
{
    "format": "worldlet",
    "format_version": "1.0",

    "meta": {
        "name":        "Starfleet Personnel",
        "author":      "starfleet.com",
        "version":     "1.0.0",
        "description": "Personnel records for Starfleet officers and ships.",
        "created_at":  "2364-01-01T00:00:00.000Z"
    },

    "properties": {
        "executable": true,
        "temporal":   false
    },

    "allow": ["api.starfleet.com"],

    "extensions": {},

    "classes": {
        "starfleet.com/person": {
            "fields": {
                "name":      {"class": "string", "required": true, "collapse": true},
                "birthdate": {"class": "string"},
                "species":   {"class": "string", "default": "Human"},

                "greet": {
                    "class": "function",
                    "charlie": "
                        function &greet
                            'Hello, I am ' + @name
                        end
                    "
                }
            }
        },

        "starfleet.com/officer": {
            "inherits": "starfleet.com/person",
            "fields": {
                "rank":   {"class": "string",  "required": true},
                "serial": {"class": "string",  "required": true, "unique": true},
                "active": {"class": "boolean", "default": true},
                "photo":  {"class": "puck.uno/dbfile"},

                "summary": {
                    "class": "function",
                    "charlie": "
                        function &summary
                            @rank + ' ' + @name + ' (' + @serial + ')'
                        end
                    "
                },

                "promote": {
                    "class": "function",
                    "charlie": "
                        function &promote(new_rank:)
                            @rank = new_rank
                            self
                        end
                    "
                }
            }
        },

        "starfleet.com/ship": {
            "fields": {
                "name":       {"class": "string", "required": true, "unique": true},
                "registry":   {"class": "string", "required": true, "unique": true},
                "ship_class": {"class": "string"}
            },
            "join": ["name", "registry"]
        }
    },

    "records": {
        "e1b2c3d4-0001-0001-0001-000000000001": {
            "class":      "starfleet.com/officer",
            "created_at": "2364-01-01T00:00:00.000Z",
            "bucket":     {"name": "Picard, Jean-Luc", "rank": "Captain", "serial": "SP-937-215"}
        },

        "e1b2c3d4-0002-0002-0002-000000000002": {
            "class":      "starfleet.com/officer",
            "created_at": "2364-01-01T00:00:00.000Z",
            "bucket":     {"name": "Riker, William", "rank": "Captain", "serial": "SC-231-427"}
        },

        "e1b2c3d4-0003-0003-0003-000000000003": {
            "class":      "starfleet.com/ship",
            "created_at": "2364-01-01T00:00:00.000Z",
            "bucket":     {"name": "USS Enterprise", "registry": "NCC-1701-D", "ship_class": "Galaxy"}
        },

        "e1b2c3d4-0004-0004-0004-000000000004": {
            "class":      "starfleet.com/officer",
            "created_at": "2364-01-01T00:00:00.000Z",
            "bucket":     {"name": "Data", "rank": "Lieutenant Commander", "serial": "SA-789-012", "photo": "d1e2f3a4-0001-0001-0001-000000000001"}
        }
    },

    "files": {
        "d1e2f3a4-0001-0001-0001-000000000001": {
            "sha256":     "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "created_at": "2364-01-01T00:00:00.000Z",
            "mime": {
                "type":     "image/png",
                "encoding": "base64"
            }
        }
    },

    "file_chunks": {
        "c1d2e3f4-0001-0001-0001-000000000001": {
            "file":  "d1e2f3a4-0001-0001-0001-000000000001",
            "index": 0,
            "last":  true,
            "data":  "base64encodeddata..."
        }
    }
}
```
