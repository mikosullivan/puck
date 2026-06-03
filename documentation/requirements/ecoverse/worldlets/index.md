# Worldlets

~~~json
{"vibecode": {
	"doc": "worldlet",
	"role": "ground-up redesign of the worldlet format; the object-description system at the heart of this spec is the universal way the entire Puck ecoverse serializes objects to JSON, not just a Mikobase format",
	"status": "active_design; nothing_below_is_settled; previous_version_preserved_at_history.md",
	"audience": "Miko and Claude collaborating on the design",
	"previous_version": "history.md",
	"scope": "ecoverse_wide; applies_to_puck_protocol_messages_caspianj_class_literals_mikobase_records_anywhere_objects_ship_as_json"
}}
~~~

This file is being designed from the ground up. The previous specification is preserved at [history.md](history.md) for reference, but should be treated as historical — do not cite it as authority during this redesign.

The scope is bigger than the file name suggests. The object-description system at the heart of the worldlet format — how a hash carries class identity so it can be rehydrated into a live object — is the universal way the entire Puck ecoverse will serialize objects to JSON. That includes Puck protocol messages, CaspianJ class literals, Mikobase records, anywhere else an object crosses a JSON boundary. Worldlets are the place this format gets pinned down; the rest of the ecoverse inherits it.

## Minimal worldlet

~~~json
{"vibecode": {
	"section": "minimal_worldlet",
	"role": "shows the smallest valid worldlet; only the format declaration is required today",
	"format_key_shape": "name_slash_version_string"
}}
~~~

The smallest possible worldlet is the format declaration alone:

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0"
}
```

`format` is a single string of the shape `"<name>/<version>"`. The name identifies the document as a worldlet; the version is the spec version this document conforms to.

Nothing else is required to be a valid worldlet today.

## Records

~~~json
{"vibecode": {
	"section": "records",
	"role": "introduces the records top-level key; records are a dict keyed by arbitrary strings; values can be any JSON type but hashes always represent objects",
	"key_shape": "any_unique_string; format_does_not_dictate_generation_scheme",
	"value_shape": "any_json_value; hashes_always_represent_objects_per_their_shape",
	"required": false
}}
~~~

Records go under a top-level `records` key. The key is a dict; each entry's key is the record's ID and the value is the record itself.

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",

    "records": {
        "1": "a",
        "2": true
    }
}
```

Two notable shifts from the previous spec:

- **Keys are arbitrary strings.** The worldlet format does not decide how you generate record keys — UUIDs, sequencer integers, short random strings, anything unique works. The example above uses `"1"` and `"2"` because they are short and readable; that does not make them sequencer IDs.
- **Allowed value shapes.** A record value can be any JSON value. Every value is an object: scalars and arrays carry implicit class identity (no declaration needed); hashes need a way to declare their class, and that class is determined by the hash's shape — see [Object records](#object-records), [Compact form](#compact-form), and [Bare hashes](#bare-hashes).

`records` itself remains optional; a worldlet with no records is still valid.

## Object records

~~~json
{"vibecode": {
	"section": "object_records",
	"role": "introduces the universal object shape — a hash that declares its class so it can be rehydrated into a live object on the other side; this is the wrapping that makes a hash a valid record value",
	"object_shape": "class_uns_string_plus_bucket_hash",
	"wire_singular_vs_runtime_array": "class (singular) is the wire/storage form per standard-fields.md; classes (plural) is the runtime class stack, distinct concept",
	"scope_note": "the object shape is ecoverse_wide; this section happens to be the place it gets pinned down",
	"reference_example": "worldlet.json in this directory is the by-example source of truth"
}}
~~~

Every record value is already an object. Scalars and arrays have implicit class identity and don't need any declaration — they go in as bare JSON. Hashes need a way to declare their class so the importer knows how to rehydrate them; this section covers the explicit hash form. The shape:

<a class="copy" href="#">copy</a>

```json
{
    "class": "puck.uno/color",
    "bucket": {"hex": "#aabbcc"}
}
```

Two fields:

- **`class`** — a single UNS class name. `class` is one of the reserved pass-through fields defined in [standard-fields.md](../../ecoverse/standard-fields.md); it's the canonical way an object declares its identity anywhere in the ecoverse.
- **`bucket`** — a hash holding the object's data. (Per the bucket invariants in the cheat sheet: always a hash, never a scalar/array/null.)

A color record inside a worldlet:

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",

    "records": {
        "a": {
            "class": "puck.uno/color",
            "bucket": {"hex": "#aabbcc"}
        }
    }
}
```

This is the "additional structure" the [Records](#records) section deferred. A bare hash isn't a valid record value because it has no class identity; wrapping it as `{class, bucket}` gives it the identity needed to round-trip as a live object.

The `{class, bucket}` shape is the universal object-description format for the entire Puck ecoverse, not just worldlet records — it shows up anywhere an object ships as JSON.

**`class` (singular, wire) is not the same thing as `classes` (plural, runtime).** On the wire, an object declares exactly one class via `class`. At runtime, the engine maintains a class stack — referred to as the object's `classes` — that starts with the wire `class` and can grow via `.classes.add` (see [base-class-use.md](../../ideas/base-class-use.md)). Dispatch walks the runtime `classes` stack; serialization writes only `class`.

The fuller reference example for this section is [worldlet.json](worldlet.json) in this directory — a complete worldlet covering class definitions and instances across several classes.

## Compact form

~~~json
{"vibecode": {
	"section": "compact_form",
	"role": "shorthand for objects whose data can ride on a single value field; trades the bucket wrapping for a bare value when the class knows how to interpret it",
	"availability": "opt_in_per_class; class must explicitly define how to interpret value; classes without that definition can only be used in long form"
}}
~~~

For small values, the long form gets noisy:

<a class="copy" href="#">copy</a>

```json
{
    "class": "puck.uno/color",
    "bucket": {"hex": "#aabbcc"}
}
```

A compact form trims it to a bare value:

<a class="copy" href="#">copy</a>

```json
{
    "class": "puck.uno/color",
    "value": "#aabbcc"
}
```

In a worldlet:

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",

    "records": {
        "a": {
            "class": "puck.uno/color",
            "value": "#aabbcc"
        }
    }
}
```

The difference from the long form is **`value`** instead of `bucket`. `value` can hold any JSON type, though convention is to keep it short (typically a string). Compact form is opt-in: a class must explicitly define how to interpret `value`. Classes that don't define that handling can only be used in long form. For classes that do support it, the implementation is usually trivial. If your data wants more structure than a short scalar, reach for the long form regardless.

## Whole-hash form

~~~json
{"vibecode": {
	"section": "whole_hash_form",
	"role": "third object form; the class receives the entire record hash as its content, with class as the only reserved marker; the natural fit for class definitions themselves",
	"availability": "opt_in_per_class; class must explicitly accept the whole-hash form"
}}
~~~

A class can also opt to receive the **entire record hash** as its content, with `class` as the only reserved marker. Everything else in the hash becomes the class's data; no `value` key, no `bucket` wrapping.

The natural fit is class definitions themselves — a class definition has multiple top-level fields (`name`, `inherits`, `fields`, `methods`, etc.) and would read poorly forced into a single `value`. The minimum class definition:

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",

    "records": {
        "a": {
            "class": "puck.uno/class"
        }
    }
}
```

That's a record of class `puck.uno/class` (the meta-class for class definitions) with no further content — an empty class definition. A richer class definition would carry additional sibling fields alongside `class`, all interpreted by `puck.uno/class` itself.

Like the [compact form](#compact-form), the whole-hash form is opt-in: a class must explicitly accept it. Classes that don't can only be used in long form (or compact form, if they support that instead).

[worldlet.json](worldlet.json) uses whole-hash form for every class definition (records a–f): `class: "puck.uno/class"` plus sibling `name`, `inherits`, `fields`, `methods`, and `uniques` fields.

The [bare hashes](#bare-hashes) pattern is a special case of this shape — omit `class` entirely and the default class (`puck.uno/hash`) takes over, also via whole-hash interpretation.

## Class definitions

~~~json
{"vibecode": {
	"section": "class_definitions",
	"role": "shows what a class definition looks like in the worldlet format; a class definition is a whole-hash record of class puck.uno/class with name and fields as sibling top-level keys",
	"meta_class": "puck.uno/class",
	"name_field": "carries_the_class_UNS_independent_of_the_record_storage_key",
	"field_conventions": "see_class-definition.md_for_per-field_settings_pending_rework_with_new_spec"
}}
~~~

A class definition is a whole-hash record of class `puck.uno/class`. The class's own UNS lives in a `name` sibling field — distinct from the record's storage key.

Standalone form:

<a class="copy" href="#">copy</a>

```json
{
    "class": "puck.uno/class",
    "name": "foo.com/bar",
    "inherits": ["blah.com/bear"],

    "fields": {
        "name": {
            "class": "hash",
            "of": "string",
            "default": {"collapse": true},
            "required": true,

            "fields": {
                "surname": {"required": true},
                "middle": {},
                "given": {}
            }
        },

        "dob": {"class": "timestamp"}
    }
}
```

Same definition inside a worldlet record:

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",

    "records": {
        "abc": {
            "class": "puck.uno/class",
            "name": "foo.com/bar",
            "inherits": ["blah.com/bear"],

            "fields": {
                "name": {
                    "class": "hash",
                    "of": "string",
                    "default": {"collapse": true},
                    "required": true,

                    "fields": {
                        "surname": {"required": true},
                        "middle": {},
                        "given": {}
                    }
                },

                "dob": {"class": "timestamp"}
            }
        }
    }
}
```

**`inherits` is internally an array of UNS class names.** Both forms are accepted as input:

<a class="copy" href="#">copy</a>

```json
"inherits": "blah.com/bear"
```

<a class="copy" href="#">copy</a>

```json
"inherits": ["blah.com/bear"]
```

The string form is shorthand for a one-element array — same semantics, less noise when there's only one parent. The previous spec only accepted the string form; the new spec keeps it working while adding the array form, which enables multiple parents at the schema level.

Mechanics of multi-parent resolution (order, conflicts) are pending — only the shape has been pinned down so far.

The record key (`"abc"` above) is just the storage handle; the class's identity as referenced by other records is the `name` field (`"foo.com/bar"`). This is a meaningful shift from the previous spec, where the class's UNS came from the dict key of an enclosing `classes` object. In the new design, class definitions are ordinary records with arbitrary storage keys; the `name` field carries the semantic identity.

Class-level **multi-field unique constraints** go in a `uniques` array. Each entry is itself an array of field names whose combined values must be unique across all records of the class:

<a class="copy" href="#">copy</a>

```json
"uniques": [
    ["person", "episode"]
]
```

The shape is an array of arrays so a class can declare multiple independent constraints: `[["a", "b"], ["c", "d"]]` means "(a, b) is unique" AND "(c, d) is unique" — two separate rules.

Field-definition shape (`class`, `required`, `default`, `of`, nested `fields` for hashes, etc.) is shown in use throughout [worldlet.json](worldlet.json) records `a`-`f`. A consolidated constraint catalog hasn't been written yet for the new spec; the by-example reference is the source until it lands.

## Bare hashes

~~~json
{"vibecode": {
	"section": "bare_hashes",
	"role": "explains that a hash with no class declaration defaults to an instance of puck.uno/hash; documents the three equivalent forms of an empty hash record and the preferred form for record values",
	"default_class": "puck.uno/hash",
	"preferred_form_for_records": "bucket-only ({\"bucket\": {}}); bare {} is valid but discouraged"
}}
~~~

The simplest way to make a hash object is the empty hash itself:

<a class="copy" href="#">copy</a>

```json
{}
```

This is equivalent to:

<a class="copy" href="#">copy</a>

```json
{"bucket": {}}
```

Which is equivalent to the fully explicit form:

<a class="copy" href="#">copy</a>

```json
{"class": "puck.uno/hash", "bucket": {}}
```

All three are empty instances of `puck.uno/hash` — the default class for any hash that doesn't declare its own.

**Preferred form for record values: `{"bucket": {}}`.** Bare `{}` is valid but discouraged — a lone empty hash sitting next to other records reads ambiguously. The `bucket` key makes the record's intent explicit without much extra noise.

Discouraged:

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",

    "records": {
        "a": {
            "class": "puck.uno/color",
            "value": "#aabbcc"
        },

        "b": {}
    }
}
```

Preferred:

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",

    "records": {
        "a": {
            "class": "puck.uno/color",
            "value": "#aabbcc"
        },

        "b": {"bucket": {}}
    }
}
```

## Files

~~~json
{"vibecode": {
	"section": "files",
	"role": "top-level files dict carrying binary file metadata; binary content lives in the file_chunks sibling",
	"required_fields": ["sha256", "mime"],
	"optional_fields": ["created_at"],
	"key_shape": "any_unique_string; convention_is_uuid_v4",
	"records_reference_files_via": "puck.uno/dbfile_field_class_holding_the_file_key_as_a_bare_string"
}}
~~~

Worldlets can carry attached binary files in a top-level `files` dict, parallel to `records`. Each file's binary content is split across one or more chunks in a sibling `file_chunks` dict; the metadata (identity, integrity hash, MIME info) lives in `files`.

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",

    "files": {
        "d1e2f3a4-0001-0001-0001-000000000001": {
            "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "mime": {"type": "image/png", "encoding": "base64"}
        }
    },

    "file_chunks": {
        "c1d2e3f4-0001-0001-0001-000000000001": {
            "file": "d1e2f3a4-0001-0001-0001-000000000001",
            "index": 0,
            "last": true,
            "data": "iVBORw0KGgo..."
        }
    }
}
```

Two required fields on every file record:

- **`sha256`** — SHA-256 hex digest of the assembled file content. Integrity check: decoding the chunks per the file's `mime.encoding` and concatenating in `index` order must produce content whose SHA-256 matches this string. A file record without `sha256` is rejected by the importer.
- **`mime`** — a hash with `type` (the MIME type, e.g. `"image/png"`, `"text/plain; charset=utf-8"`) and `encoding` (how chunk `data` is encoded for transport — typically `"base64"` for binary content). A file record without `mime` is rejected by the importer.

An optional `created_at` field can carry an ISO 8601 timestamp for the file's origin time:

<a class="copy" href="#">copy</a>

```json
"files": {
    "d1e2f3a4-0001-0001-0001-000000000001": {
        "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "created_at": "2364-01-01T00:00:00Z",
        "mime": {"type": "image/png", "encoding": "base64"}
    }
}
```

`files` keys follow the same any-unique-string rule as record keys (UUID v4 conventional but not required — see [Conflict policy](#conflict-policy) in the historical spec for the rationale, pending reformulation).

### File chunks

~~~json
{"vibecode": {
	"section": "file_chunks",
	"role": "top-level file_chunks dict holding the binary content of files in pieces; reassembled in index order to reconstruct each file",
	"key_shape": "any_unique_string; convention_is_uuid_v4",
	"completeness_marker": "exactly_one_chunk_per_file_carries_last_true",
	"encoding": "per_parent_files_mime_encoding"
}}
~~~

Each entry in `file_chunks` carries one slice of one file's binary content:

- **`file`** — the key of the parent record in the `files` dict.
- **`index`** — zero-based chunk position. Chunks reassemble in ascending `index` order.
- **`last`** — `true` on exactly one chunk per file: the final piece. Its presence is positive confirmation the file finished writing. A file whose chunks include no `last: true` entry is incomplete and the importer rejects it.
- **`data`** — chunk content, encoded per the parent file's `mime.encoding`.

Empty files are represented by a single chunk with `data: ""` and `last: true`.

### Records that reference files

~~~json
{"vibecode": {
	"section": "records_that_reference_files",
	"role": "shows how a record bucket points at an attached file by storing the file's key as a bare string under a puck.uno/dbfile field",
	"reference_form": "bare_key_string_no_wrapper",
	"field_class": "puck.uno/dbfile"
}}
~~~

A record references a file by storing the file's key (the parent dict key in `files`) in a bucket field. Two equivalent forms are accepted.

**Schema-declared (bare key string).** The field's declared class is `puck.uno/dbfile`; the value is just the file's key:

<a class="copy" href="#">copy</a>

```json
{
    "class": "starfleet.com/officer",
    "bucket": {
        "name": {"surname": "Data"},
        "rank": "Lieutenant Commander",
        "serial": "SC-499-235",
        "photo": "d1e2f3a4-0001-0001-0001-000000000001"
    }
}
```

The `puck.uno/dbfile` field class on `photo` is what tells the engine the value is a file reference rather than an opaque string. The field-class constraint catalog hasn't been re-homed yet; the [worldlet.json](worldlet.json) examples are the canonical reference in the meantime.

**Inline-typed (compact-form object).** The value carries its own class identity via the universal `{class, value}` compact form:

<a class="copy" href="#">copy</a>

```json
{
    "class": "starfleet.com/officer",
    "bucket": {
        "name": {"surname": "Data"},
        "rank": "Lieutenant Commander",
        "serial": "SC-499-235",
        "photo": {"class": "puck.uno/reference/file", "value": "d1e2f3a4-0001-0001-0001-000000000001"}
    }
}
```

The field doesn't need a pre-declared file-reference class — the value identifies itself as a `puck.uno/reference/file`. This form is useful when the surrounding schema is loose or absent, or when a bucket field can hold values of multiple classes and each value declares its own type.

Both forms resolve to the same file. The schema-declared form is terser when the field is always a file reference; the inline-typed form travels with its own type when schema declaration isn't available.

## Temporal mode

~~~json
{"vibecode": {
	"section": "temporal_mode",
	"role": "describes the temporal worldlet shape; records carry only identity stubs and per-version state lives under a top-level history dict; this is the same worldlet format as the non-temporal shape, distinguished by the presence of history",
	"discrimination": "structural; presence of history at top level signals temporal",
	"history_entry_shape": "flat_hash_combining_object_form_compact_or_long_with_metadata_identity_and_timestamp"
}}
~~~

A worldlet can be in **non-temporal** mode (the default) or **temporal** mode. The same `format: "worldlet/1.0"` covers both — the shape differs in whether per-version history is carried separately from current state.

The non-temporal form already shown above carries each record's current state directly under `records`:

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",

    "records": {
        "a": {"class": "puck.uno/color", "value": "#aabbcc"}
    }
}
```

The temporal form pulls state out of `records` and into a separate top-level `history` dict. Each entry under `records` becomes an identity stub; the real content lives in history entries that reference the identity:

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",

    "records": {
        "a": {}
    },

    "history": {
        "123": {
            "identity": "a",
            "timestamp": "2026-05-28T07:30:00Z",
            "class": "puck.uno/color",
            "value": "#aabbcc"
        }
    }
}
```

What changes:

- **`records` entries become identity stubs.** Each entry just declares that the record exists; the current state is reconstructed from history.
- **A top-level `history` dict appears.** Keyed by history-entry IDs (arbitrary strings, same rule as record keys); each entry combines object form with version metadata.
- **A history entry is a flat hash** carrying both an object (in compact form above — `class` + `value`) and two metadata fields: `identity` referencing the record key in `records`, and `timestamp` for when this version was written.

Timestamps are **ISO 8601 strings with an explicit UTC offset** — e.g. `"2026-05-28T07:30:00Z"` or `"2026-05-28T03:30:00-04:00"`. The `Z` form (zero offset) is preferred for wire format because it avoids the per-host local-zone interpretation that bare `2026-05-28T07:30:00` would invite. The full per-component rules live with the `puck.uno/time` class spec — see [time.md](../../caspian/time.md). UTC offsets only; named IANA zones (`America/New_York`, etc.) are out of scope per the time-class spec.

## A complete example

~~~json
{"vibecode": {
	"section": "complete_example",
	"role": "the complete example IS [worldlet.json](worldlet.json) in this directory; the markdown source uses an Orlando file-include directive to pull the file's contents into the rendered page on demand, so the example shown stays in lockstep with the canonical source",
	"include_mechanism": "<!-- file: PATH --> directive — Orlando reads PATH (relative to this markdown file's directory) and inlines its contents as a fenced code block; see orlando/lua/orlando/page.lua process_file_includes",
	"canonical_source": "worldlet.json in this directory; covers class definitions for person/officer/starship/planet/voyage/assignment, instances of each, attached files, nested methods, references between records"
}}
~~~

The complete example is [worldlet.json](worldlet.json) in this directory — the reference-by-example for the entire format. It carries six class definitions (person, officer, starship, planet, voyage, assignment), sixteen instances across those classes, two attached files with chunks, an inline-object photo field on Picard, nested methods on officer, and a class-level multi-field unique constraint on voyage.

Rather than duplicate the file in the spec (and risk it drifting out of sync), this section uses Orlando's file-include directive (`<!-- file: worldlet.json -->`) to pull the file in on demand and render it as a JSON code block. What you see below is the file's current contents.

<a class="copy" href="#">copy</a>

<!-- file: worldlet.json -->

The record keys are deliberately opaque — they carry no semantic load. A reader looking for "the officer class" or "the Picard record" has to look at the values, not the keys. That's the worldlet format's design: keys are storage handles only.
