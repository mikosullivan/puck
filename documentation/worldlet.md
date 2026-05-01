# Worldlet Format

## Overview

```
vibecode: {
	"section": "overview",
	"topic": "worldlet_format"
}
```

A worldlet is a complete mikobase — classes, records, version history, and files — packaged
as a single JSON object. It is the standard format for sharing and distributing mikobases.

A worldlet is imported into a running mikobase. The importer creates the classes, inserts
the records and history, and stores any file attachments. PKs are preserved exactly as
exported, so references between records remain valid after import.

---

## Top-Level Structure

```
vibecode: {
	"section": "top_level_structure",
	"topic": "worldlet_format"
}
```

```json
{
    "meta":        { ... },
    "allow":       [ ... ],
    "classes":     { ... },
    "records":     { ... },
    "history":     { ... },
    "files":       { ... },
    "file_chunks": { ... }
}
```

---

## `meta`

```
vibecode: {
	"section": "meta",
	"fields": ["name", "author", "version"],
	"purpose": "descriptive_metadata_about_the_worldlet"
}
```

Descriptive information about the worldlet.

```json
"meta": {
    "name":    "Starfleet Personnel",
    "author":  "starfleet.com",
    "version": "1.0.0"
}
```

| Field     | Description |
|-----------|-------------|
| `name`    | Human-readable name |
| `author`  | UNS domain of the publisher |
| `version` | Semver string |

---

## `allow`

```
vibecode: {
	"section": "allow",
	"type": "array",
	"purpose": "external_resources_requiring_host_approval_before_import"
}
```

An array of external resources the worldlet requires access to. The host presents these to
the user for approval before importing. Nothing is granted silently.

```json
"allow": ["api.starfleet.com"]
```

The format and full capability vocabulary are not yet fully designed.

---

## `classes`

```
vibecode: {
	"section": "classes",
	"format": "dict_keyed_by_uns_class_name",
	"methods_as": "fields_with_class_function_and_kscript_key",
	"see": "class-definition.md"
}
```

The schema, using the standard class definition format. Each key is a UNS class name; each
value is the class definition. All classes defined here are record classes.

Methods are defined as fields with `"class": "function"` and a `"kscript"` key containing
KScript source. Multiline strings use literal newlines; leading indentation is stripped by
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
                "kscript": "
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
            "photo":  {"class": "kiera.uno/dbfile"},

            "summary": {
                "class": "function",
                "kscript": "
                    function &summary
                        @rank + ' ' + @name + ' (' + @serial + ')'
                    end
                "
            },

            "promote": {
                "class": "function",
                "kscript": "
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

See [class-definition.md](class-definition.md) for the full class definition format.

---

## `records`

```
vibecode: {
	"section": "records",
	"format": "dict_keyed_by_uuid",
	"value": "empty_hash",
	"note": "content_lives_in_history_not_here"
}
```

A dict of record identity objects, keyed by record UUID. In most cases the value is an
empty hash `{}`. The content of each record lives in `history`, not here.

```json
"records": {
    "e1b2c3d4-0001-0001-0001-000000000001": {},
    "e1b2c3d4-0002-0002-0002-000000000002": {},
    "e1b2c3d4-0003-0003-0003-000000000003": {},
    "e1b2c3d4-0004-0004-0004-000000000004": {}
}
```

---

## `history`

```
vibecode: {
	"section": "history",
	"format": "dict_keyed_by_history_uuid",
	"fields": ["record", "class", "created_at", "bucket"],
	"note": "multiple_entries_per_record_uuid_latest_created_at_is_current"
}
```

A dict of history entries, keyed by history UUID. Each entry is one version of a record.
Multiple entries may point to the same record UUID — this is the version history. The
current state of a record is the entry with the latest `created_at`.

```json
"history": {
    "f1a2b3c4-0001-0001-0001-000000000001": {
        "record":     "e1b2c3d4-0001-0001-0001-000000000001",
        "class":      "starfleet.com/officer",
        "created_at": "2364-01-01T00:00:00.000Z",
        "bucket":     {"name": "Picard, Jean-Luc", "rank": "Captain", "serial": "SP-937-215"}
    }
}
```

| Field        | Description |
|--------------|-------------|
| `record`     | UUID of the record this version belongs to |
| `class`      | UNS class name at the time of this write |
| `created_at` | ISO 8601 timestamp with millisecond precision |
| `bucket`     | The record's field values at this version |

---

## `files`

```
vibecode: {
	"section": "files",
	"format": "dict_keyed_by_file_uuid",
	"fields": ["sha256", "created_at", "mime.type", "mime.encoding"]
}
```

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

## `file_chunks`

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

## Complete Example

```json
{
    "meta": {
        "name":    "Starfleet Personnel",
        "author":  "starfleet.com",
        "version": "1.0.0"
    },

    "allow": ["api.starfleet.com"],

    "classes": {
        "starfleet.com/person": {
            "fields": {
                "name":      {"class": "string", "required": true, "collapse": true},
                "birthdate": {"class": "string"},
                "species":   {"class": "string", "default": "Human"},

                "greet": {
                    "class": "function",
                    "kscript": "
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
                "photo":  {"class": "kiera.uno/dbfile"},

                "summary": {
                    "class": "function",
                    "kscript": "
                        function &summary
                            @rank + ' ' + @name + ' (' + @serial + ')'
                        end
                    "
                },

                "promote": {
                    "class": "function",
                    "kscript": "
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
        "e1b2c3d4-0001-0001-0001-000000000001": {},
        "e1b2c3d4-0002-0002-0002-000000000002": {},
        "e1b2c3d4-0003-0003-0003-000000000003": {},
        "e1b2c3d4-0004-0004-0004-000000000004": {}
    },

    "history": {
        "f1a2b3c4-0001-0001-0001-000000000001": {
            "record":     "e1b2c3d4-0001-0001-0001-000000000001",
            "class":      "starfleet.com/officer",
            "created_at": "2364-01-01T00:00:00.000Z",
            "bucket":     {"name": "Picard, Jean-Luc", "rank": "Captain", "serial": "SP-937-215"}
        },

        "f1a2b3c4-0002-0002-0002-000000000002": {
            "record":     "e1b2c3d4-0002-0002-0002-000000000002",
            "class":      "starfleet.com/officer",
            "created_at": "2364-01-01T00:00:00.000Z",
            "bucket":     {"name": "Riker, William", "rank": "Commander", "serial": "SC-231-427"}
        },

        "f1a2b3c4-0003-0003-0003-000000000003": {
            "record":     "e1b2c3d4-0002-0002-0002-000000000002",
            "class":      "starfleet.com/officer",
            "created_at": "2366-03-15T09:22:00.000Z",
            "bucket":     {"name": "Riker, William", "rank": "Captain", "serial": "SC-231-427"}
        },

        "f1a2b3c4-0004-0004-0004-000000000004": {
            "record":     "e1b2c3d4-0003-0003-0003-000000000003",
            "class":      "starfleet.com/ship",
            "created_at": "2364-01-01T00:00:00.000Z",
            "bucket":     {"name": "USS Enterprise", "registry": "NCC-1701-D", "ship_class": "Galaxy"}
        },

        "f1a2b3c4-0005-0005-0005-000000000005": {
            "record":     "e1b2c3d4-0004-0004-0004-000000000004",
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
