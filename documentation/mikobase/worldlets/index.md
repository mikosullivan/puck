# Worldlet Format

~~~json
{"vibecode": {
	"doc": "worldlet",
	"role": "spec for the worldlet JSON file format — the portable serialization of a small mikobase used for sharing, shipping, and exchanging databases that fit comfortably as a single JSON document. Covers the top-level structure, every section (meta / format / properties / classes / records / files), import rules, and complete worked examples.",
	"audience": ["humans designing worldlet producers and consumers",
		"AI agents reading or emitting worldlet JSON directly"],
	"size_scope": "small_mikobases_only; a_separate_export_format_for_large_mikobases_is_planned_but_not_yet_designed",
	"key_concepts": ["non_temporal_default_no_history_block",
		"records_keyed_by_uuid", "classes_section_for_schema",
		"files_with_file_chunks_subsection_for_binary",
		"import_overwrites_on_uuid_match",
		"validation_errors_abort_atomically",
		"app_owns_conflict_policy_not_the_primitive"],
	"see_also": {
		"AI2AI.md": "temporal worldlet shape used by AI2AI sessions",
		"mikobase.md": "full mikobase model, temporal vs non-temporal mode"
	},
	"example_universe": "Star Trek"
}}
~~~

A worldlet looks like this — three records, no classes, no history,
no files:

```json
{
    "format": "worldlet",
    "format_version": "1.0",
    "records": {
        "1a000000-0000-0000-0000-000000000001": {
            "bucket": {"name": "Picard, Jean-Luc", "rank": "Captain"}
        },
        "1a000000-0000-0000-0000-000000000002": {
            "bucket": {"name": "Riker, William", "rank": "Commander"}
        },
        "1a000000-0000-0000-0000-000000000003": {
            "bucket": {"name": "Data", "rank": "Lieutenant Commander"}
        }
    }
}
```

That's the whole format at its smallest. Everything below is optional
detail layered on top.

<a id="overview"></a>
## Overview

~~~json
{"vibecode": {
	"section": "overview",
	"what_a_worldlet_is": "a complete non_temporal_mikobase serialized as one JSON object",
	"contains": ["classes_definitions", "records_with_buckets",
		"optional_files_and_file_chunks", "optional_meta_and_properties"],
	"size_scope": "small_mikobases_only; large_mikobases_will_use_a_different_export_format_tbd",
	"primary_use_cases": ["snapshot_for_sharing",
		"scenario_or_scratch_space", "ai2ai_exchange_format_subset"],
	"import_target": "non_temporal_mikobase_only; importing_into_temporal_raises",
	"history_handling": "no_version_history_in_non_temporal_shape; see_AI2AI_md_for_temporal_shape"
}}
~~~

A worldlet is a complete mikobase — classes, records, and files — packaged as a single
JSON object. It is the standard format for sharing and distributing **small** mikobases.
A separate export format for large mikobases is planned but not yet designed; if a
mikobase is too big to ship comfortably as one JSON document, this is not the format
to reach for.

**This document describes the non-temporal worldlet shape** — each record
is stored as a single object with its current bucket; there is no version
history. Non-temporal is the worldlet default and matches most use cases
(snapshots of conversations, scenarios, scratch space). Temporal worldlets
exist for cases that need to preserve history; see
[AI2AI.md](../AI2AI.md) for that shape and
[mikobase.md](../index.md#temporal-vs-non-temporal-mode) for the full
mode rules.

A worldlet is imported into a running mikobase. The importer creates the classes, inserts
the records, and stores any file attachments. PKs are preserved exactly as exported, so
references between records remain valid after import. A non-temporal worldlet imports
into a non-temporal mikobase; importing into a temporal mikobase raises an exception.

---

<a id="top-level-structure"></a>
## Top-Level Structure

~~~json
{"vibecode": {
	"section": "top_level_structure",
	"required_keys": ["format", "format_version"],
	"optional_keys": ["meta", "properties", "classes", "records",
		"files", "file_chunks"],
	"key_order": "not_significant; order shown is conventional for human readability",
	"shape": "single_top_level_json_object"
}}
~~~

```json
{
    "format":         "worldlet",
    "format_version": "1.0",
    "meta":           { ... },
    "properties":     { ... },
    "classes":        { ... },
    "records":        { ... },
    "files":          { ... },
    "file_chunks":    { ... }
}
```

A worldlet plays two roles: a **serialized export** of an engine-backed
mikobase (SQLite in v1) and the **live storage** of the
`puck.uno/mikobase/worldlet` engine. See
[mikobase.md § Worldlets: Mikobase on a microscale](../index.md#worldlets-mikobase-on-a-microscale)
for the broader picture and the engine/format distinction.

A worldlet's required keys depend on its `temporal` flag (see
[mikobase.md § Temporal vs Non-temporal Mode](../index.md#temporal-vs-non-temporal-mode)):

- **Non-temporal worldlets** (the default — `temporal` key absent or
  `false`): `records` is required and carries each record's current
  bucket directly; `history` is not part of the format.
- **Temporal worldlets** (`"temporal": true` at the top level):
  `history` is required; `records` is optional (the engine infers
  identity stubs from history if absent).

All other top-level keys default to empty structures if absent.

This document describes the **non-temporal** worldlet shape — records carry
their current bucket directly. For the temporal shape with per-version history
entries, see
[AI2AI.md](../AI2AI.md).

---

<a id="meta"></a>
## `meta`

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
## `format` and `format_version`

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
## `properties`

~~~json
{"vibecode": {
	"section": "properties",
	"fields": ["temporal"],
	"purpose": "database_level_metadata_readable_by_any_client_or_agent"
}}
~~~

Database-level properties that describe the mikobase itself. Any client or agent
connecting to or importing the worldlet should read these before interacting with
the data.

```json
"properties": {
    "temporal": false
}
```

| Field      | Type    | Default | Description |
|------------|---------|---------|-------------|
| `temporal` | boolean | `false` | Whether the importer should save records into version history instead of writing them directly to current state. Worldlets are non-temporal by default; setting `true` instructs the importer to store each record as a history entry |

`temporal` tells the importer how to land each record. The default `false`
matches the worldlet format's non-temporal shape (each record carries its
current bucket directly, no history block). Set `true` when the worldlet
was exported from a temporal mikobase and the receiving mikobase should
preserve that history rather than collapse it into current state.

A small amount of forgiveness for mode mismatches is TBD — exact rules to
be filled in once the temporal/non-temporal import paths are settled. See
[mikobase.md](../index.md#temporal-vs-non-temporal-mode) for the full
mode rules.

---

<a id="classes"></a>
## `classes`

~~~json
{"vibecode": {
	"section": "classes",
	"format": "dict_keyed_by_uns_class_name",
	"methods_as": "fields_with_class_function_and_caspian_key",
	"see": "class-definition.md"
}}
~~~

The schema, using the standard class definition format. Each key is a UNS class name; each
value is the class definition. All classes defined here are record classes.

Methods are defined as fields with `"class": "function"` and a `"caspian"` key containing
Caspian source. Multiline strings use literal newlines; leading indentation is stripped by
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
                "caspian": "
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
                "caspian": "
                    function &summary
                        @rank + ' ' + @name + ' (' + @serial + ')'
                    end
                "
            },

            "promote": {
                "class": "function",
                "caspian": "
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

See [class-definition.md](../class-definition.md) for the full class definition format.

---

<a id="records"></a>
## `records`

~~~json
{"vibecode": {
	"section": "records",
	"format": "dict_keyed_by_uuid",
	"fields": ["classes", "created_at", "bucket"],
	"shape": "platter_model_classes_hash_keyed_by_platter_id"
}}
~~~

A dict of records, keyed by record UUID. Each entry carries the record's
classes (its platter stack), creation timestamp, and current bucket. The
non-temporal worldlet shape documented here has no separate history block
and no per-version entries; for the temporal shape with per-version
history, see [AI2AI.md](../AI2AI.md).

```json
"records": {
    "e1b2c3d4-0001-0001-0001-000000000001": {
        "classes": {
            "p1a2b3c4-0001-0001-0001-000000000001": {
                "class":  "starfleet.com/officer",
                "bucket": {}
            }
        },
        "created_at": "2364-01-01T00:00:00.000Z",
        "bucket":     {"name": "Picard, Jean-Luc", "rank": "Captain", "serial": "SP-937-215"}
    }
}
```

| Field        | Required | Description |
|--------------|----------|-------------|
| `classes`    | yes      | Platter stack: a hash keyed by platter ID, each value `{class, bucket}` per the [platter model](../../ideas/base-class-use.md). Every record has at least one platter. |
| `created_at` | no       | ISO 8601 timestamp with millisecond precision; record-level metadata, not bucket data. |
| `bucket`     | yes      | The record's user-facing field values (those declared by its class definitions). Free-form, no reserved keys. |

**Where do values live?** For a regular record with a single class platter,
the class's declared field values (e.g., `name`, `rank`, `serial` for an
officer) live in the **top-level `bucket`**. Per-platter buckets are for
class-internal state (mix-ins, cross-cutting concerns) — usually empty
for ordinary records. Class-definition records are a special case where
the platter's bucket holds the definition itself; see
[class-definition.md](../class-definition.md).

---

<a id="files"></a>
## `files`

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

<a id="file_chunks"></a>
### `file_chunks`

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
## Import Rules

~~~json
{"vibecode": {
	"section": "import_rules",
	"covers": ["uuid_constraints", "conflict_policy",
		"reference_encoding", "class_field", "validation",
		"atomicity"],
	"conflict_policy_summary": "incoming_record_with_existing_uuid_overwrites; stricter_policies_are_application_concerns",
	"atomicity_summary": "validation_errors_abort_entire_import; no_partial_writes",
	"validation_summary": "every_record_has_class_and_bucket; class_must_be_known_to_importer; created_at_iso_8601_millisecond_precision"
}}
~~~

<a id="uuid-constraints"></a>
### UUID constraints

Keys in `records`, `files`, and `file_chunks` are conventionally UUID v4
strings, but Mikobase requires only **uniqueness** — not a specific
format and not cryptographic soundness. UUIDs are used for collision
avoidance, not security. Any unique string is accepted today; the policy
may tighten later. See
[mikobase.md § Record identity](../index.md#record-identity).

Caspian code generating record IDs should use
[`%utils.random.uuid`](../../caspian/utils/index.md#utilsrandomuuid), which
returns a cryptographically secure UUID v4 sourced from the OS CSPRNG via libsodium.

<a id="conflict-policy"></a>
### Conflict policy

A worldlet is a non-temporal mikobase serialized to JSON. Importing
records is just writing them — when an incoming record has the same
UUID as one already in the target, the incoming record overwrites
the existing one. The same rule applies to `files` and
`file_chunks` entries.

Whether overwrites are *desirable* is an application concern, not
something the worldlet primitive should decide. Apps that want
stricter behavior (skip-on-conflict, abort-on-conflict, prompt for
review, etc.) can wrap import in their own check before calling.

<a id="reference-encoding"></a>
### Reference encoding

Reference fields in `bucket` are plain UUID strings. The class definition declares the
field type — a field with class `puck.uno/reference` or `puck.uno/dbfile` tells the
engine the value is a reference. No special wrapper syntax is used in the bucket itself.

<a id="the-class-field"></a>
### The `class` field inside platter records

In all Puck-compliant platter records, the `class` field identifies the
class for that platter. This applies to Q0 queries, record entries' class
definitions, and any other Puck-level objects.

Bucket objects (top-level or platter-internal) are not Puck-compliant.
The `class` key has no special meaning inside a bucket and may be used
freely as an application field.

<a id="validation"></a>
### Validation

The importer validates the following before writing anything:

- All record entries have a `classes` hash and a `bucket`.
- Every record's `classes` hash contains at least one platter entry.
- All `class` values inside platter records are either built-in classes,
  defined in this worldlet's `classes` section, or already present in
  the target mikobase.
- All `file` values in `file_chunks` reference a UUID present in `files`.
- The target mikobase is non-temporal.

<a id="atomicity"></a>
### Atomicity

Import is all-or-nothing. If any validation error or conflict error occurs, nothing is
written to the target mikobase. Partial imports do not happen.

---

<a id="minimal-valid-example"></a>
## Minimal Valid Example

~~~json
{"vibecode": {
	"section": "minimal_valid_example",
	"shows": "smallest_complete_worldlet_that_imports_without_error",
	"omits": ["meta", "properties", "classes", "files", "file_chunks"],
	"defaults_relied_on": {
		"record_classes": "single platter of class puck.uno/record (built_in) when classes is omitted",
		"classes_section": "not_needed_when_only_built_in_classes_used"
	}
}}
~~~

The smallest possible worldlet — one record, no schema, no files:

```json
{
    "format": "worldlet",
    "format_version": "1.0",
    "records": {
        "e1b2c3d4-0001-0001-0001-000000000001": {
            "bucket": {"note": "hello"}
        }
    }
}
```

The `classes` field on the record is omitted; the importer applies the
default — a single platter of class `puck.uno/record`, with an
engine-generated platter ID. The top-level worldlet `classes` section is
also omitted because `puck.uno/record` is a built-in class so no schema
is needed.

---

<a id="complete-example"></a>
## Complete Example

~~~json
{"vibecode": {
	"section": "complete_example",
	"shows": "every_top_level_section_with_realistic_starfleet_data",
	"includes": ["meta", "properties", "classes_with_one_class",
		"records_with_one_record", "files_with_one_file",
		"file_chunks_with_one_chunk"],
	"purpose": "reference_template_for_implementers_writing_producers_or_consumers"
}}
~~~

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
        "temporal": false
    },

    "classes": {
        "starfleet.com/person": {
            "fields": {
                "name":      {"class": "string", "required": true, "collapse": true},
                "birthdate": {"class": "string"},
                "species":   {"class": "string", "default": "Human"},

                "greet": {
                    "class": "function",
                    "caspian": "
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
                    "caspian": "
                        function &summary
                            @rank + ' ' + @name + ' (' + @serial + ')'
                        end
                    "
                },

                "promote": {
                    "class": "function",
                    "caspian": "
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
            "classes": {
                "p1a2b3c4-0001-0001-0001-000000000001": {"class": "starfleet.com/officer", "bucket": {}}
            },
            "created_at": "2364-01-01T00:00:00.000Z",
            "bucket":     {"name": "Picard, Jean-Luc", "rank": "Captain", "serial": "SP-937-215"}
        },

        "e1b2c3d4-0002-0002-0002-000000000002": {
            "classes": {
                "p1a2b3c4-0002-0002-0002-000000000002": {"class": "starfleet.com/officer", "bucket": {}}
            },
            "created_at": "2364-01-01T00:00:00.000Z",
            "bucket":     {"name": "Riker, William", "rank": "Captain", "serial": "SC-231-427"}
        },

        "e1b2c3d4-0003-0003-0003-000000000003": {
            "classes": {
                "p1a2b3c4-0003-0003-0003-000000000003": {"class": "starfleet.com/ship", "bucket": {}}
            },
            "created_at": "2364-01-01T00:00:00.000Z",
            "bucket":     {"name": "USS Enterprise", "registry": "NCC-1701-D", "ship_class": "Galaxy"}
        },

        "e1b2c3d4-0004-0004-0004-000000000004": {
            "classes": {
                "p1a2b3c4-0004-0004-0004-000000000004": {"class": "starfleet.com/officer", "bucket": {}}
            },
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
