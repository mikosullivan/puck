# Class definitions

> **Worldlet-envelope examples below are stale.** Class definitions now live as records inside `records` (whole-hash form, `class: "puck.uno/class"` plus sibling `name`, `inherits`, `fields`, `methods`, `uniques`), not under a dict-keyed `classes` section of the worldlet envelope. See [worldlets/index.md § Class definitions](../../mikobase/worldlets/index.md#class-definitions) and [worldlets/worldlet.json](../../mikobase/worldlets/worldlet.json) for the current form. The Caspian DSL side of each section below is still current; only the JSON envelope shape has changed.

~~~json
{"vibecode": {
	"doc": "class_definitions",
	"role": "canonical reference for how a class is declared on each of the surfaces in the ecoverse — Caspian DSL, CaspianJ (the engine's runtime format), and Mikobase JSON; every JSON example is shown inside the context of an entire worldlet, since a class definition's natural home is the classes section of a worldlet",
	"status": "JSON envelope shape is stale; see banner at top of file. Caspian DSL forms still current.",
	"audience": "Caspian users and engine implementers (primary), Miko (secondary as a settled-decisions index)",
	"format": "construct_by_construct_side_by_side; each section shows the Caspian DSL form and the worldlet JSON; open questions surfaced inline rather than buried",
	"key_concepts": ["caspian_class_dsl", "caspianj_class_form", "mikobase_class_schema",
		"worldlet_envelope", "shared_class_definition_structure"],
	"related": ["caspian/index.md#classes", "caspian/caspianj.md",
		"mikobase/class-definition.md", "mikobase/worldlets/index.md",
		"ecoverse/standard-fields.md"]
}}
~~~

This doc shows how a class definition looks on each of the surfaces in the ecoverse. The goal is a single place where any Caspian DSL construct can be matched to its CaspianJ / Mikobase JSON equivalent.

## Three surfaces, one structure

A class definition has three valid surface forms:

- **Caspian DSL** — what a human writes in a `.casp` file
- **CaspianJ** — the JSON tree the engine consumes after transpilation
- **Mikobase JSON** — the schema stored in a Mikobase record's `bucket`

The CaspianJ form for a class definition is identical to the Mikobase JSON form. There is one canonical structure; the DSL is one surface, the shared JSON is the other. Anything one surface expresses, the other must too.

## The worldlet envelope

A class definition's natural home in JSON is the `classes` section of a **worldlet** — the portable serialization of a small mikobase. Every JSON example in this document is shown inside a worldlet envelope so the context is always explicit.

The minimal worldlet wrapping one class:

```json
{
    "format":         "worldlet",
    "format_version": "1.0",
    "classes": {
        "foo.com/character": {<class-definition>}
    }
}
```

`format` and `format_version` are conventional but optional. `classes` is a dict keyed by UNS class name; the value is the class definition. A full worldlet may also carry `meta`, `properties`, `records`, `files`, and `file_chunks` — see [worldlets/index.md](../../mikobase/worldlets/index.md) for the complete spec. The examples below show only the parts of the worldlet that are relevant to the construct being introduced.

## A class at a glance

~~~caspian
class 'starfleet.com/officer'
	inherits 'starfleet.com/person'

	field :name,     class: :string, required: true
	field :rank,     class: :string, required: true
	field :serial,   class: :string, required: true, unique: true
	field :starship, class: 'puck.uno/reference', allowed_class: 'starfleet.com/ship'

	accessor :nickname

	function &greet(name:)
		'Hello, ' + $name
	end
end
~~~

```json
{
    "format":         "worldlet",
    "format_version": "1.0",
    "classes": {
        "starfleet.com/officer": {
            "inherits": "starfleet.com/person",
            "fields": {
                "name":     {"class": "string", "required": true},
                "rank":     {"class": "string", "required": true},
                "serial":   {"class": "string", "required": true, "unique": true},
                "starship": {"class": "puck.uno/reference", "allowed_class": "starfleet.com/ship"}
            },

            "methods": {
                "greet": {
                    "class":   "function",
                    "caspian": "some CaspJ code"
                }
            }
        }
    }
}
```

The shared JSON above does not include `accessor :nickname` — accessors are off-schema instance state and do not yet have a settled JSON form. See [Open questions](#open-questions) below.

## Constructs

What follows is the construct-by-construct catalog. Each section shows the Caspian DSL form and the worldlet JSON. Where the JSON shape is not yet settled, the DSL is shown alone with the gap called out.

### Class identity

~~~caspian
class 'foo.com/character'
	...
end
~~~

```json
{
    "format":         "worldlet",
    "format_version": "1.0",
    "classes": {
        "foo.com/character": {<class-definition>}
    }
}
```

The class name is a UNS string. In the worldlet JSON, the name comes from the dict key in `classes` — never from a `name` field inside the class definition. If a `name` field is present, it is ignored. See [class-definition.md § Class Name](../../mikobase/class-definition.md#class-name).

### Inheritance

~~~caspian
class 'foo.com/character'
	inherits 'foo.com/person'
end
~~~

```json
{
    "format":         "worldlet",
    "format_version": "1.0",
    "classes": {
        "foo.com/character": {
            "inherits": "foo.com/person"
        }
    }
}
```

Single parent. Inheritance is always explicit; no path-implied inheritance.

### Abstract

~~~caspian
class 'puck.uno/mikobase'
	abstract true
end
~~~

```json
{
    "format":         "worldlet",
    "format_version": "1.0",
    "classes": {
        "puck.uno/mikobase": {
            "abstract": true
        }
    }
}
```

Direct instantiation raises. Subclasses can be instantiated normally.

### Fields

~~~caspian
class 'foo.com/character'
	field :name,      class: :string, required: true, collapse: true
	field :age,       class: :number, min: 0, integer_only: true
	field :homeworld, class: 'puck.uno/reference', allowed_class: 'foo.com/planet'
end
~~~

```json
{
    "format":         "worldlet",
    "format_version": "1.0",
    "classes": {
        "foo.com/character": {
            "fields": {
                "name":      {"class": "string", "required": true, "collapse": true},
                "age":       {"class": "number", "min": 0, "integer_only": true},
                "homeworld": {"class": "puck.uno/reference", "allowed_class": "foo.com/planet"}
            }
        }
    }
}
```

Built-in type names are bare strings — `:string` and `'string'` are equivalent in the DSL. UNS names use the quoted form. Field-name conventions and the full constraint catalog: [class-definition.md § Fields](../../mikobase/class-definition.md#fields) and the type-specific settings tables that follow it.

### Inline vs named field types

Inline field-type definitions (constraints written directly in the field declaration) are only valid for the basic types (`string`, `number`, `boolean`, `url`, `timestamp`, `hash`, `array`). UNS-named custom classes are referenced by name only — their structure lives in a separate class definition elsewhere in the worldlet.

The exception is `hash`, which can carry inline `fields`, an `of` element-type, and `default` field settings. Full rules: [class-definition.md § Inline vs. Named Field Types](../../mikobase/class-definition.md#inline-vs-named-field-types).

### Field settings

The full enumeration of common, type-specific, reference, and array/hash settings lives in [class-definition.md § Common Field Settings](../../mikobase/class-definition.md#common-field-settings) and the sections that follow. The Caspian DSL accepts the same keys as keyword arguments to `field`:

~~~caspian
class 'foo.com/show'
	field :slug,    class: :string, required: true, unique: true, min_length: 1
	field :rating,  class: :number, gte: 0, lte: 10, integer_only: true
	field :tags,    class: :array,  of: :string, min_elements: 1
	field :avatar,  class: 'puck.uno/dbfile', required: true
end
~~~

```json
{
    "format":         "worldlet",
    "format_version": "1.0",
    "classes": {
        "foo.com/show": {
            "fields": {
                "slug":   {"class": "string", "required": true, "unique": true, "min_length": 1},
                "rating": {"class": "number", "gte": 0, "lte": 10, "integer_only": true},
                "tags":   {"class": "array",  "of": "string", "min_elements": 1},
                "avatar": {"class": "puck.uno/dbfile", "required": true}
            }
        }
    }
}
```

### Reference fields

~~~caspian
class 'foo.com/character'
	field :homeworld, class: 'puck.uno/reference', allowed_class: 'foo.com/planet'
	field :stop,      class: 'puck.uno/reference',
	                  allowed_classes: ['foo.com/moon', 'foo.com/station']
end
~~~

```json
{
    "format":         "worldlet",
    "format_version": "1.0",
    "classes": {
        "foo.com/character": {
            "fields": {
                "homeworld": {"class": "puck.uno/reference",
                              "allowed_class": "foo.com/planet"},
                "stop":      {"class": "puck.uno/reference",
                              "allowed_classes": ["foo.com/moon", "foo.com/station"]}
            }
        }
    }
}
```

`allowed_class` and `allowed_classes` may be combined — they merge. Subclasses of the named classes are also valid.

### Single-field unique constraints

~~~caspian
class 'foo.com/officer'
	field :serial, class: :string, required: true, unique: true
end
~~~

```json
{
    "format":         "worldlet",
    "format_version": "1.0",
    "classes": {
        "foo.com/officer": {
            "fields": {
                "serial": {"class": "string", "required": true, "unique": true}
            }
        }
    }
}
```

Null values are excluded from the uniqueness check — two records may both have null for a unique field.

### Multi-field unique constraints

```json
{
    "format":         "worldlet",
    "format_version": "1.0",
    "classes": {
        "borg.com/appearance": {
            "fields": {
                "person":  {"class": "puck.uno/reference", "required": true},
                "episode": {"class": "puck.uno/reference", "required": true}
            },
            "uniques": [
                ["person", "episode"]
            ]
        }
    }
}
```

The shared JSON form is a class-level `uniques` array — see [class-definition.md § Unique Constraints](../../mikobase/class-definition.md#unique-constraints). The Caspian DSL has no construct for multi-field unique today; see [Open questions](#open-questions) below.

### Joins

~~~caspian
class 'foo.com/appearance'
	field :person,  class: 'puck.uno/reference', allowed_class: 'foo.com/person'
	field :episode, class: 'puck.uno/reference', allowed_class: 'foo.com/episode'

	join :person, :episode
end
~~~

```json
{
    "format":         "worldlet",
    "format_version": "1.0",
    "classes": {
        "foo.com/appearance": {
            "fields": {
                "person":  {"class": "puck.uno/reference", "allowed_class": "foo.com/person"},
                "episode": {"class": "puck.uno/reference", "allowed_class": "foo.com/episode"}
            },
            "join": ["person", "episode"]
        }
    }
}
```

`join` is a class-level shorthand for "required + unique-in-combination + immutable" on each listed field. See [class-definition.md § Joins](../../mikobase/class-definition.md#joins).

### Methods

Methods live in a `methods` namespace, sibling to `fields` — not inside `fields`. Each entry is keyed by method name and carries the method's class (`"function"`) and body.

~~~caspian
class 'foo.com/character'
	function &greet(name:)
		'Hello, ' + $name
	end

	remote function &save(name:, rank:)
	end
end
~~~

```json
{
    "format":         "worldlet",
    "format_version": "1.0",
    "classes": {
        "foo.com/character": {
            "methods": {
                "greet": {
                    "class":   "function",
                    "caspian": "some CaspJ code"
                },
                "save": {
                    "class":   "function",
                    "remote":  true,
                    "caspian": "some CaspJ code"
                }
            }
        }
    }
}
```

**Conflict to resolve.** The current [worldlets/index.md spec](../../mikobase/worldlets/index.md#classes) stores methods inside `fields` with `"class": "function"`, not in a separate `methods` namespace. That doc has drifted from the intent and needs updating to match this shape. Until it is updated, do not generate worldlets from the worldlet doc's example — it will produce invalid output.

**Two further details still to pin down:**

- The `remote function` body keeps the same `"class": "function"` and adds `"remote": true` as a sibling flag, as sketched above. This has not been explicitly confirmed.
- The body key is named `"caspian"`, but the value's intended content is CaspJ JSON — see [Open questions](#open-questions).

### Reserved pass-through fields

Six fields are reserved pass-throughs on every Puckverse object and require no declaration: `vibecode`, `comment`, `misc`, `corporate`, `class`, `bucket`. See [standard-fields.md](../../ecoverse/standard-fields.md).

These do not appear in class definitions on either surface — they are always present implicitly.

## Constructs not yet expressible in shared JSON

The following Caspian DSL constructs do not have a settled worldlet / shared JSON shape. They are shown in DSL form only. The gap is real and needs a decision.

### Accessors

`accessor` declares `%bucket`-backed instance state that lives on the object but is *not* part of the persisted schema. See [caspian/index.md § accessor](../index.md#accessor).

~~~caspian
class 'foo.com/character'
	accessor @nickname              # private, no external access
	accessor @nickname, :get        # creates a getter
	accessor @nickname, :get, :set  # creates both getter and setter
end
~~~

No worldlet JSON shape exists today. A natural fit would be a separate `accessors` namespace alongside `fields` and `methods` — keyed by accessor name, each entry carrying `:get` / `:set` flags. That is a proposal, not spec.

### Helpers

`helper` creates a lazily-initialized helper object namespaced off the parent. See [caspian/index.md § Helpers](../index.md#helpers).

~~~caspian
class 'foo.com/character'
	helper :stats
		function &average()
			...
		end
	end
end
~~~

No worldlet JSON shape exists today. Helpers contain methods, so any helpers shape will need to nest a `methods` namespace inside each helper entry.

### Lifecycle hooks

Caspian documents two hook systems for different events:

- `on_close` — engine GC hook, runs when an object is destroyed. See [garbage-collection.md](../garbage-collection.md).
- `before_save` / `after_save` — Mikobase transaction hooks, registered via `$mikobase.listen()`. See [mikobase/index.md § listeners](../../mikobase/index.md).

Neither is declared inside a class definition today — both are registered dynamically by external code. There is no worldlet JSON shape because there is no in-class declaration to serialize. Whether hooks should be declarable in-class is itself the open question; see [Open questions](#open-questions).

## Anonymous classes

~~~caspian
class
	inherits 'puck.uno/robinson/page'

	function &process($request)
		...
	end
end
~~~

Anonymous classes (no UNS) exist in Caspian for cases where identity comes from location rather than from a UNS — e.g., Robinson page files identified by their path in the directory tree.

In the worldlet JSON form, anonymous classes have no natural home: the dict-key-as-name convention means there is nowhere to put a class without a name. If anonymous classes need to round-trip through a worldlet, the shape needs a decision — see [Open questions](#open-questions).

## Open questions

These are the decisions that need to be made before the shared JSON form is fully settled. Each blocks at least one construct above.

### Reconciling the worldlet doc with the methods namespace

[worldlets/index.md § classes](../../mikobase/worldlets/index.md#classes) currently shows methods stored *inside* `fields` with `"class": "function"`. That shape is wrong — methods belong in a separate `methods` namespace, sibling to `fields`. The worldlet doc needs to be updated to match, and its example classes (`starfleet.com/person`, `starfleet.com/officer`) need their methods moved out of `fields`.

### Body key naming: `"caspian"` vs `"caspj"`

The body key is named `"caspian"` (per worldlet doc) but the intended content is CaspianJ JSON — the engine's runtime format, not Caspian source text. Either the key name should change (`"caspj"` or `"body"`) to match the content, or the content should be Caspian source string (and the key name stays). Pick one — the current mismatch will confuse implementers.

### Remote functions in the methods shape

`remote function` is sketched above as `"remote": true` alongside `"class": "function"` in the methods entry. This has not been explicitly confirmed; needs a one-line sign-off.

### Accessor JSON shape

Methods are fields with `"class": "function"`. Accessors might follow the same pattern with `"class": "accessor"` and getter/setter flags — but that has not been pinned down. Whatever shape lands, it should generalize cleanly from the methods pattern, not introduce a third convention.

### Helpers JSON shape

Helpers contain methods, so the shape depends on a decision about namespacing. The methods-as-fields pattern doesn't directly give helpers a home — they're sub-namespaces, not flat fields.

### Multi-field unique in the Caspian DSL

The worldlet JSON has `"uniques": [["a", "b"]]` for non-join multi-field uniqueness. The Caspian DSL has no equivalent — `join` is the only multi-field construct, and it implies extra semantics (required, immutable) that uniqueness alone shouldn't carry. A `unique :a, :b` statement would close the gap.

### Hooks in-class

`on_close` and `before_save` / `after_save` are external-only today. Whether they should also be declarable in-class — and if so, what the shape looks like — needs a call.

### Anonymous classes in a worldlet

If anonymous classes need to serialize, where do they live in the worldlet's `classes` dict? Synthesized UUID key? A separate `anonymous_classes` array?

### "Class stack" vs "platter stack" — pick a name

Three docs now use two terms for the same mechanism:

- [class-definition.md § Inheritance](../../mikobase/class-definition.md#inheritance) — "class stack"
- [worldlets/index.md § records](../../mikobase/worldlets/index.md#records) — "platter stack"
- [cheat-sheet.md § Object model](../../cheat-sheet.md#object-model) — "platter stack"

Two-to-one in favor of "platter stack" if that breaks the tie, but the call hasn't been made. One name should win and the other should be a redirect or be removed.

## What this doc is not

Not the field-constraint reference — that lives in [class-definition.md](../../mikobase/class-definition.md). Not the DSL grammar reference — that lives in [caspian/index.md § Classes](../index.md#classes). Not the worldlet spec — that lives in [worldlets/index.md](../../mikobase/worldlets/index.md). This file is the bridge that shows how a single class definition looks across all of them.
