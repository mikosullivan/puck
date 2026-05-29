# Class definitions

~~~json
{"vibecode": {
	"doc": "class_definitions",
	"role": "canonical shape of a class definition in CaspJ — what fields a class carries, how its methods are written, and the options that go on each field and each method parameter",
	"scope": "ecoverse_wide; same shape applies wherever a class is defined — worldlet records, Mikobase, CaspianJ literals, Puck protocol messages",
	"meta_class": "puck.uno/class",
	"sibling_example_file": "class.json"
}}
~~~

A class definition is a record whose class is `puck.uno/class` — the meta-class. It uses the [whole-hash form](../../mikobase/worldlets/index.md#whole-hash-form) (class as the only reserved marker; everything else is data), so its content sits directly under the record alongside `class`, not wrapped in a `bucket`.

Same shape applies anywhere a class is defined: a worldlet record, a Mikobase row, a CaspianJ literal in source, a Puck protocol message — none of them re-invent the format.

The full shape is on display below. Each piece of it is then explained, section by section, in the rest of the doc. The same example also lives in sibling file [class.json](class.json) for quick copy/paste.

## Complete example

~~~json
{"vibecode": {
	"section": "complete_example",
	"role": "self_contained_class_definition_using_every_option_described_in_this_doc; intended_as_the_reading_anchor_for_the_sections_below",
	"example_universe": "Star Trek"
}}
~~~

The example below is a worldlet carrying six class definitions. Each class demonstrates a different facet of the spec:

- `starfleet.com/person` — base class holding the shared `name` field, used as a parent by `officer`.
- `starfleet.com/officer` — inherits from `person`, adds officer-specific fields, and demonstrates the full params vocabulary on its `salute` method.
- `starfleet.com/starship` — a second, simpler method (`hail`) and another use of `one_of` on a param.
- `federation.com/planet` — a method whose body reads the receiver's instance variables (`{"ivar": ...}`), and a field-level `one_of` enum constraint.
- `starfleet.com/voyage` — multi-field [`uniques`](#uniques) on plain top-level fields.
- `starfleet.com/assignment` — typed pointers to other records via the `puck.uno/reference` class, and multi-field uniques across those references.

The literal source lives in the sibling [class.json](class.json) file and is reproduced verbatim below.

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",

    "records": {
        "a": {
            "class":       "puck.uno/class",
            "name":        "starfleet.com/person",
            "description": "A person.",

            "fields": {
                "name": {
                    "class":       "hash",
                    "of":          "string",
                    "required":    true,
                    "default":     {"collapse": true},
                    "description": "Surname + given + optional middle name.",
                    "fields": {
                        "surname": {"required": true},
                        "given":   {},
                        "middle":  {}
                    }
                }
            }
        },

        "b": {
            "class":       "puck.uno/class",
            "name":        "starfleet.com/officer",
            "inherits":    ["starfleet.com/person"],
            "description": "A commissioned Starfleet officer.",

            "fields": {
                "rank":   {"class": "string",  "required": true},
                "serial": {"class": "string",  "required": true, "unique": true},
                "active": {"class": "boolean", "default":  true},
                "dob":    {"class": "timestamp"}
            },

            "methods": {
                "salute": {
                    "description": "Render a verbal salute from this officer toward someone of a given rank.",

                    "params": {
                        "name":      {"class": "string",  "required": true, "description": "Name of the person being saluted."},
                        "rank":      {"class": "string",  "required": true, "description": "Rank of the person being saluted."},
                        "attention": {"class": "boolean", "default":  false, "description": "Call attention before the salute."},
                        "style":     {"class": "string",  "one_of":   ["formal", "casual"], "default": "formal"},
                        "props":     {"splat": true, "description": "Any extra context the renderer may use."}
                    },

                    "returns": {"class": "string", "description": "The rendered salute line."},

                    "body": "
						puts $rank + ' ' + $name + ', sir!'
					"
                }
            }
        },

        "c": {
            "class":       "puck.uno/class",
            "name":        "starfleet.com/starship",
            "description": "A Starfleet starship.",

            "fields": {
                "registry":       {"class": "string",    "required": true, "unique": true, "description": "Hull registry (e.g. NCC-1701)."},
                "name":           {"class": "string",    "required": true, "description": "Display name (Enterprise, Defiant)."},
                "classification": {"class": "string",    "required": true, "description": "Spaceframe class (Constitution, Galaxy, Sovereign)."},
                "launched":       {"class": "timestamp", "description": "Commissioning date."},
                "active":         {"class": "boolean",   "default": true, "description": "Currently in service."}
            },

            "methods": {
                "hail": {
                    "description": "Open a channel to the target.",

                    "params": {
                        "target":   {"class": "string", "required": true, "description": "Target UNS (ship, station, or planet)."},
                        "priority": {"class": "string", "one_of": ["routine", "priority", "emergency"], "default": "routine"},
                        "subject":  {"class": "string", "description": "Optional subject line for the hail."}
                    },

                    "returns": {"class": "boolean", "description": "True iff the channel opened."},

                    "body": [
                        [{"bwc": "puts"}, [{"value": "Hailing "}, "+", {"var": "target"}]]
                    ]
                }
            }
        },

        "d": {
            "class":       "puck.uno/class",
            "name":        "federation.com/planet",
            "description": "A planet recognized by the Federation cartographic registry.",

            "fields": {
                "name":              {"class": "string",  "required": true, "description": "Common name (Earth, Vulcan, Risa)."},
                "designation":       {"class": "string",  "required": true, "unique": true, "description": "Astronomical designation (Sol III, 40 Eridani A II)."},
                "system":            {"class": "string",  "required": true, "description": "Parent star system."},
                "classification":    {"class": "string",  "one_of": ["M", "L", "K", "Y", "D", "J", "T"], "description": "Habitability class."},
                "federation_member": {"class": "boolean", "default": false, "description": "Member of the United Federation of Planets."}
            },

            "methods": {
                "describe": {
                    "description": "Return a one-line summary of the planet.",
                    "params":      {},
                    "returns":     {"class": "string"},

                    "body": [
                        [{"bwc": "puts"}, [
                            {"ivar": "name"}, "+",
                            [{"value": " ("}, "+", [{"ivar": "designation"}, "+", {"value": ")"}]]
                        ]]
                    ]
                }
            }
        },

        "e": {
            "class":       "puck.uno/class",
            "name":        "starfleet.com/voyage",
            "description": "A discrete deployment of a Starfleet ship.",

            "fields": {
                "ship":          {"class": "string",    "required": true, "description": "Registry of the ship on this voyage."},
                "voyage_number": {"class": "number",    "required": true, "description": "Sequential number within the ship's history."},
                "start_date":    {"class": "timestamp", "required": true},
                "end_date":      {"class": "timestamp", "description": "Absent while the voyage is still under way."},
                "mission_type":  {"class": "string",    "one_of": ["exploration", "diplomatic", "patrol", "rescue", "combat"], "default": "exploration"}
            },

            "uniques": [
                ["ship", "voyage_number"]
            ]
        },

        "f": {
            "class": "puck.uno/class",
            "name": "starfleet.com/assignment",

            "unqiues":[
                ["person", "starship"]
            ],

            "fields": {
                "person": {
                    "class": "puck.uno/reference",
                    "target": "starfleet.com/person",
                    "required": true
                },
                "starship": {
                    "class": "puck.uno/reference",
                    "target": "starfleet.com/starship",
                    "required": true
                },
                "status": {
                    "class": "string",
                    "required": true
                }
            }
        }
    }
}
```

Reading order, roughly:

1. **Worldlet envelope** ([format + records](../../mikobase/worldlets/index.md)) — `format` declares the carrier; `records` holds entries by storage key. Storage keys (`"a"`–`"f"`) are opaque handles; each class's semantic identity lives in its `name` field.
2. **Identity** ([`class`](#basic-shape), [`name`](#class-identity), [`inherits`](#inheritance)) — `class: "puck.uno/class"` marks every record above as a class definition; `name` gives each new class its UNS; `inherits` (used by `officer`) declares the parent chain. `person` owns the shared `name` field; `officer` inherits it and adds rank, serial, active, and dob on top.
3. **Fields** ([`fields`](#fields)) — each entry is `name → options-hash` with insertion order preserved. The `person` class shows a nested-hash field (`name`) with its own sub-`fields`; the others show flat fields with various option combinations (`required`, `unique`, `default`, `class`, `one_of`, `description`). The `assignment` class shows fields whose `class` is `puck.uno/reference` — typed pointers to other records, with the pointed-at class named in `target`.
4. **Methods** ([`methods`](#methods)) — `salute` shows the full method-definition shape with its body written as Caspian source text (`"puts $rank + ' ' + $name + ', sir!'"`); `hail` and `describe` show the CaspJ tree form for comparison, where `hail` reads its `target` param via `{"var": ...}` and `describe` reads the receiver's instance variables via `{"ivar": ...}`. Both source-text and tree forms are accepted as the body value.
5. **Uniques** ([`uniques`](#uniques)) — `voyage` shows the natural use on plain fields: a ship's voyages are numbered 1, 2, 3…; the combination `(ship, voyage_number)` must be unique even though neither field is unique alone. The `assignment` record carries the same idea on top of references — one person can hold one assignment per ship at a time.

The class-definition shape inside each record is identical regardless of carrier — a Mikobase row, a CaspianJ literal in source, or a Puck protocol message all wrap a class definition the same way. The worldlet envelope (`format` + `records`) is what makes this example self-contained on disk.

## Basic shape

~~~json
{"vibecode": {
	"section": "basic_shape",
	"required_keys": ["class"],
	"common_keys": ["name", "inherits", "fields", "methods", "uniques", "description"]
}}
~~~

The minimum:

<a class="copy" href="#">copy</a>

```json
{
    "class": "puck.uno/class"
}
```

That's a valid (if empty) class definition. The `class` marker is the only required field; everything else accretes as the class grows.

A more typical shape:

<a class="copy" href="#">copy</a>

```json
{
    "class":    "puck.uno/class",
    "name":     "starfleet.com/officer",
    "inherits": ["starfleet.com/person"],
    "fields":   { ... },
    "methods":  { ... }
}
```

Five common top-level keys: `class` (always), `name`, `inherits`, `fields`, `methods`. A class can have any subset.

## Class identity

~~~json
{"vibecode": {
	"section": "class_identity",
	"name_field": "carries_the_class_UNS_independent_of_the_storage_key",
	"format": "uns_string"
}}
~~~

The class's UNS lives in the `name` field. It's a UNS string — a URL without the `https://` prefix:

<a class="copy" href="#">copy</a>

```json
"name": "starfleet.com/officer"
```

This is the identity other records use when they reference the class (e.g. `{"classes": ["starfleet.com/officer"], "bucket": ...}`). It is **independent of the record's storage key** — a class can live under any storage key in a worldlet; the storage key is just a handle, the `name` is the semantic identity. See [worldlets § Class definitions](../../mikobase/worldlets/index.md#class-definitions) for the details.

## Inheritance

~~~json
{"vibecode": {
	"section": "inheritance",
	"shape": "array_of_uns_strings_internally; string_shorthand_for_single_parent",
	"multi_parent_status": "shape_settled; resolution_order_pending"
}}
~~~

The `inherits` field is an array of UNS class names:

<a class="copy" href="#">copy</a>

```json
"inherits": ["starfleet.com/person"]
```

For convenience, a single parent can be written as a bare string and is treated as a one-element array:

<a class="copy" href="#">copy</a>

```json
"inherits": "starfleet.com/person"
```

Both forms are accepted on input; the canonical internal form is always the array. Multi-parent inheritance is permitted at the schema level (more than one entry in the array); the **resolution order rules** — which parent wins on a method-name collision, for instance — are still being worked out.

## Fields

~~~json
{"vibecode": {
	"section": "fields",
	"shape": "insertion_ordered_hash_of_name_to_options_hash",
	"vocabulary_shared_with": "function_params; same_option_names_same_semantics_where_both_apply"
}}
~~~

`fields` is a hash from field name to an options hash:

<a class="copy" href="#">copy</a>

```json
"fields": {
    "rank":   {"class": "string",  "required": true},
    "serial": {"class": "string",  "required": true, "unique": true},
    "active": {"class": "boolean", "default":  true},
    "dob":    {"class": "timestamp"}
}
```

Empty `{}` is the no-options form (any class, optional, no default).

### Field options

| Option | Type | Meaning |
|---|---|---|
| `class` | UNS string | Type constraint. The field value must be an instance of this class (or a subclass when inheritance lands). |
| `required` | boolean | Field must be present on instances. Mutually exclusive with `default`. |
| `default` | any | Value used when the field is absent. Mutually exclusive with `required: true`. |
| `unique` | boolean | Field value must be unique across all records of the class. (Multi-field uniqueness uses the class-level [`uniques`](#uniques) array.) |
| `of` | UNS string | For collection-typed fields (`hash`, `array`), the element class. |
| `description` | string | One-line prose for tooling / IDE hover / generated docs. |
| `fields` | hash | For hash-typed fields, the per-key sub-definitions (a nested fields block). |

Compound example combining several options:

<a class="copy" href="#">copy</a>

```json
"name": {
    "class":       "hash",
    "of":          "string",
    "required":    true,
    "default":     {"collapse": true},
    "description": "Surname + given + optional middle name, stored as a hash.",
    "fields": {
        "surname": {"required": true},
        "given":   {"required": true},
        "middle":  {}
    }
}
```

## Methods

~~~json
{"vibecode": {
	"section": "methods",
	"shape": "insertion_ordered_hash_of_name_to_method_definition_hash",
	"no_function_wrapper": "inside_methods_the_function_or_closure_wrapper_is_omitted; methods_are_always_functions_with_self_bound_by_the_dispatcher"
}}
~~~

`methods` is a hash from method name to a method definition. Each definition is a hash with at least `params` and `body`:

<a class="copy" href="#">copy</a>

```json
"methods": {
    "salute": {
        "params": { ... },
        "body":   [ ... ]
    }
}
```

Two notes on the shape:

- **No `function` / `closure` wrapper.** Standalone function literals (assigned to a variable) carry `{"function": ...}` or `{"closure": ...}` to distinguish the two. Inside `methods` that's redundant — every entry is a method, methods are always functions (with `self` bound by the dispatcher), and there's no other choice to disambiguate.
- **`params` is an insertion-ordered hash**, not an array. Every param can carry its own options without restructuring; insertion order in the hash determines positional order at call sites.

### Method-definition options

Beyond `params` and `body`, a method definition can carry:

| Option | Type | Meaning |
|---|---|---|
| `description` | string | One-line prose for tooling / IDE hover / generated docs. |
| `returns` | hash | Declared return type / shape, using the same option vocabulary as a single param (e.g. `{"class": "string"}`). Optional — when present, callers and IDEs can rely on it. |

### Params: shape and options

The `params` hash uses the same option vocabulary as class fields for everything the two share (`class`, `required`, `default`, `of`, `description`), plus a few options that only make sense for function calls.

| Option | Type | Meaning |
|---|---|---|
| `required` | boolean | Caller must provide this param. Mutually exclusive with `default`. |
| `default` | any | Value used when the caller omits the param. Mutually exclusive with `required: true`. |
| `class` | UNS string | Type constraint. Value must be an instance of this class. |
| `of` | UNS string | For collection-typed params, the element class. |
| `description` | string | One-line prose for tooling / IDE hover / generated docs. |
| `one_of` | array | Restrict to a literal set of allowed values — enum constraint. `{"one_of": ["small", "medium", "large"]}`. |
| `aliases` | array of strings | Other names callers may use for this param. Useful for spec evolution. |
| `splat` | boolean | Variadic param: collects any extra kwargs the caller passed that no other param consumed. At most one splat per function. |
| `block` | boolean | Captures the trailing `do … end` block as a callable value bound to this param. At most one. (Open question — block may end up as a sibling `block:` field on the method definition rather than as a regular param, given its distinct calling convention.) |

Empty `{}` is the no-options form. A param that exists but specifies nothing further:

<a class="copy" href="#">copy</a>

```json
"attention": {}
```

means "this param is recognised, has no type constraint, is optional, has no default."

Two principles to hold to:

- **Reuse over invention.** Anything class-field definitions already cover (`required`, `default`, `class`, `of`, `description`) keeps the same name and semantics.
- **No silent magic options.** Anything that affects dispatch (`splat`, `block`) is opt-in via a named field, never inferred from naming or position.

## Uniques

~~~json
{"vibecode": {
	"section": "uniques",
	"shape": "array_of_arrays_of_field_names",
	"each_inner_array_is_one_constraint": true
}}
~~~

Class-level multi-field uniqueness constraints go in a `uniques` array. Each inner array is one constraint — the combined values of those fields must be unique across all records of the class:

<a class="copy" href="#">copy</a>

```json
"uniques": [
    ["person", "episode"]
]
```

Two independent constraints look like:

<a class="copy" href="#">copy</a>

```json
"uniques": [
    ["person", "episode"],
    ["serial", "year"]
]
```

— meaning `(person, episode)` is unique AND `(serial, year)` is unique, as two separate rules. Single-field uniqueness uses `unique: true` on the field itself; `uniques` is reserved for the multi-field case.

## See also

- **[worldlets/index.md § Class definitions](../../mikobase/worldlets/index.md#class-definitions)** — how class definitions sit inside a worldlet record, and the relationship between the storage key and the `name` field.
- **[caspianj.md § Function and Closure Definitions](../../caspian/caspianj.md#function-and-closure-definitions)** — the standalone function and closure shapes used outside of class methods.
- **[class.json](class.json)** — sibling file carrying the same example for quick copy/paste.
