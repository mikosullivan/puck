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
	"object_shape": "classes_array_of_uns_strings_plus_bucket_hash",
	"scope_note": "the object shape is ecoverse_wide; this section happens to be the place it gets pinned down"
}}
~~~

Every record value is already an object. Scalars and arrays have implicit class identity and don't need any declaration — they go in as bare JSON. Hashes need a way to declare their class so the importer knows how to rehydrate them; this section covers the explicit hash form. The shape:

```json
{
    "classes": ["puck.uno/color"],
    "bucket": {"hex": "#aabbcc"}
}
```

Two fields:

- **`classes`** — an ordered array of UNS class names.
- **`bucket`** — a hash holding the object's data. (Per the bucket invariants in the cheat sheet: always a hash, never a scalar/array/null.)

A color record inside a worldlet:

```json
{
    "format": "worldlet/1.0",

    "records": {
        "a": {
            "classes": ["puck.uno/color"],
            "bucket": {"hex": "#aabbcc"}
        }
    }
}
```

This is the "additional structure" the [Records](#records) section deferred. A bare hash isn't a valid record value because it has no class identity; wrapping it as `{classes, bucket}` gives it the identity needed to round-trip as a live object.

The `{classes, bucket}` shape is the universal object-description format for the entire Puck ecoverse, not just worldlet records — it shows up anywhere an object ships as JSON.

## Compact form

~~~json
{"vibecode": {
	"section": "compact_form",
	"role": "shorthand for single-class objects whose data can ride on a single value field; trades the classes/bucket wrapping for class/value when the class knows how to interpret a bare value",
	"availability": "opt_in_per_class; class must explicitly define how to interpret value; classes without that definition can only be used in long form",
	"limitations": "single_class_only; multi-class objects must use the long form"
}}
~~~

For small values, the long form gets noisy:

```json
{
    "classes": ["puck.uno/color"],
    "bucket": {"hex": "#aabbcc"}
}
```

A compact form trims it to a single class name and a bare value:

```json
{
    "class": "puck.uno/color",
    "value": "#aabbcc"
}
```

In a worldlet:

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

Two differences from the long form:

- **`class`** (singular) instead of `classes` (array) — the compact form supports only one class. Multi-class objects must use the long form.
- **`value`** instead of `bucket` — `value` can hold any JSON type, though convention is to keep it short (typically a string). Compact form is opt-in: a class must explicitly define how to interpret `value`. Classes that don't define that handling can only be used in long form. For classes that do support it, the implementation is usually trivial. If your data wants more structure than a short scalar, reach for the long form regardless.

## Whole-hash form

~~~json
{"vibecode": {
	"section": "whole_hash_form",
	"role": "third shorthand for single-class objects; the class receives the entire record hash as its content, with class as the only reserved marker; the natural fit for class definitions themselves",
	"availability": "opt_in_per_class; class must explicitly accept the whole-hash form",
	"limitations": "single_class_only; multi-class objects must use the long form"
}}
~~~

A class can also opt to receive the **entire record hash** as its content, with `class` as the only reserved marker. Everything else in the hash becomes the class's data; no `value` key, no `bucket` wrapping.

The natural fit is class definitions themselves — a class definition has multiple top-level fields (`name`, `inherits`, `fields`, `methods`, etc.) and would read poorly forced into a single `value`. The minimum class definition:

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

```json
{
    "class":    "puck.uno/class",
    "name":     "foo.com/bar",
    "inherits": ["blah.com/bear"],

    "fields": {
        "name": {
            "class":    "hash",
            "of":       "string",
            "default":  {"collapse": true},
            "required": true,

            "fields": {
                "surname": {"required": true},
                "middle":  {},
                "given":   {}
            }
        },

        "dob": {"class": "timestamp"}
    }
}
```

Same definition inside a worldlet record:

```json
{
    "format": "worldlet/1.0",

    "records": {
        "abc": {
            "class":    "puck.uno/class",
            "name":     "foo.com/bar",
            "inherits": ["blah.com/bear"],

            "fields": {
                "name": {
                    "class":    "hash",
                    "of":       "string",
                    "default":  {"collapse": true},
                    "required": true,

                    "fields": {
                        "surname": {"required": true},
                        "middle":  {},
                        "given":   {}
                    }
                },

                "dob": {"class": "timestamp"}
            }
        }
    }
}
```

**`inherits` is internally an array of UNS class names.** Both forms are accepted as input:

```json
"inherits": "blah.com/bear"
```

```json
"inherits": ["blah.com/bear"]
```

The string form is shorthand for a one-element array — same semantics, less noise when there's only one parent. The previous spec only accepted the string form; the new spec keeps it working while adding the array form, which enables multiple parents at the schema level.

Mechanics of multi-parent resolution (order, conflicts) are pending — only the shape has been pinned down so far.

The record key (`"abc"` above) is just the storage handle; the class's identity as referenced by other records is the `name` field (`"foo.com/bar"`). This is a meaningful shift from the previous spec, where the class's UNS came from the dict key of an enclosing `classes` object. In the new design, class definitions are ordinary records with arbitrary storage keys; the `name` field carries the semantic identity.

Class-level **multi-field unique constraints** go in a `uniques` array. Each entry is itself an array of field names whose combined values must be unique across all records of the class:

```json
"uniques": [
    ["person", "episode"]
]
```

The shape is an array of arrays so a class can declare multiple independent constraints: `[["a", "b"], ["c", "d"]]` means "(a, b) is unique" AND "(c, d) is unique" — two separate rules.

Field-definition shape (`class`, `required`, `default`, `of`, nested `fields` for hashes, etc.) follows the conventions in [class-definition.md § Fields](../class-definition.md#fields), pending rework of that doc with the new spec.

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

```json
{}
```

This is equivalent to:

```json
{"bucket": {}}
```

Which is equivalent to the fully explicit form:

```json
{"classes": ["puck.uno/hash"], "bucket": {}}
```

All three are empty instances of `puck.uno/hash` — the default class for any hash that doesn't declare its own.

**Preferred form for record values: `{"bucket": {}}`.** Bare `{}` is valid but discouraged — a lone empty hash sitting next to other records reads ambiguously. The `bucket` key makes the record's intent explicit without much extra noise.

Discouraged:

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

```json
{
    "format": "worldlet/1.0",

    "records": {
        "a": {"class": "puck.uno/color", "value": "#aabbcc"}
    }
}
```

The temporal form pulls state out of `records` and into a separate top-level `history` dict. Each entry under `records` becomes an identity stub; the real content lives in history entries that reference the identity:

```json
{
    "format": "worldlet/1.0",

    "records": {
        "a": {}
    },

    "history": {
        "123": {
            "identity":  "a",
            "timestamp": "2026-05-28T07:30:00Z",
            "class":     "puck.uno/color",
            "value":     "#aabbcc"
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
	"role": "ties together the spec pieces in one self-contained worldlet so a reader can see how the forms combine in practice",
	"covers": ["class_definition_using_whole_hash_form", "name_as_sibling", "inherits_as_array",
		"fields_with_nested_hash", "long_form_instance", "compact_form", "bare_hash_preferred",
		"scalar_record", "worldlet_level_vibecode"],
	"does_not_cover": ["temporal_mode", "multi_class_records", "string_form_of_inherits"]
}}
~~~

The worldlet below ties together the pieces of the spec in one self-contained example. It defines a `starfleet.com/officer` class (whole-hash form, inherits as array, fields with a nested-hash field), then carries an instance of that class in long form, a compact-form color, a bare hash in the preferred `{"bucket": {}}` form, and a plain scalar. It also demonstrates that the worldlet's top-level hash can carry its own `vibecode`.

```json
{
    "format": "worldlet/1.0",

    "vibecode": {
        "purpose": "demonstrates a class definition, an instance of that class, a compact-form object, a bare hash, and a scalar — all in one worldlet",
        "example_universe": "Star Trek"
    },

    "records": {

        "r2k4p": {
            "class":    "puck.uno/class",
            "name":     "starfleet.com/officer",
            "inherits": ["starfleet.com/person"],

            "fields": {
                "name": {
                    "class":    "hash",
                    "of":       "string",
                    "default":  {"collapse": true},
                    "required": true,

                    "fields": {
                        "surname": {"required": true},
                        "given":   {"required": true},
                        "middle":  {}
                    }
                },

                "rank":   {"class": "string",  "required": true},
                "serial": {"class": "string",  "required": true, "unique": true},
                "active": {"class": "boolean", "default":  true},
                "dob":    {"class": "timestamp"}
            }
        },

        "m9x3w": {
            "classes": ["starfleet.com/officer"],

            "bucket": {
                "name": {
                    "surname": "Picard",
                    "given":   "Jean-Luc"
                },
                "rank":   "Captain",
                "serial": "SP-937-215"
            }
        },

        "h6n8c": {
            "class": "puck.uno/color",
            "value": "#cc0000"
        },

        "t5j1z": {"bucket": {}},

        "v4b7e": "Make it so."
    }
}
```

The record keys are deliberately opaque — they carry no semantic load. A reader looking for "the officer class" or "the Picard record" has to look at the values, not the keys. That's the worldlet format's design: keys are storage handles only.
