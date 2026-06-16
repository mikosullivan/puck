# Class definitions

~~~vibecode
{"vibecode": {
	"doc": "class_definitions",
	"role": "canonical reference for how a class is declared on each of the surfaces in the ecoverse — Caspian DSL, CaspianJ (the engine's runtime format), and Mikobase JSON; every JSON example is shown inside the context of an entire worldlet, since a class definition's natural home is the classes section of a worldlet",
	"audience": "Caspian users and engine implementers (primary), Miko (secondary as a settled-decisions index)",
	"format": "construct_by_construct_side_by_side; each section shows the Caspian DSL form and the worldlet JSON; open questions surfaced inline rather than buried",
	"key_concepts": ["caspian_class_dsl_does_not_carry_uns",
		"uns_is_the_storage_location_not_an_intrinsic_class_property",
		"things_live_where_you_store_them",
		"caspianj_class_form", "mikobase_class_schema",
		"worldlet_envelope", "shared_class_definition_structure",
		"one_uns_one_class_for_published_artifacts"],
	"related": ["caspian/index.md#classes", "caspian/caspianj.md",
		"mikobase/class-definition.md", "ecoverse/worldlets/index.md",
		"ecoverse/standard-fields.md"]
}}
~~~

> **Classes don't declare their own UNS.** The Caspian DSL form is just `class ... end` — no UNS string in the declaration. A class is an object; UNS is the **address where you store it** for external discoverability, not a property the class itself carries. When a class is serialized into a worldlet record at a particular storage location, the `name` field on that record records the UNS — which is metadata about where the record lives, not about the class.

This doc shows how a class definition looks on each of the surfaces in the ecoverse. The goal is a single place where any Caspian DSL construct can be matched to its CaspianJ / Mikobase JSON equivalent.

## Two surfaces, one structure

A class definition has two valid surface forms:

- **Caspian DSL** — what a human writes in a `.casp` file
- **JSON** — the shared representation used both by the engine (CaspianJ, after transpilation) and stored in a Mikobase record's bucket. CaspianJ and the Mikobase JSON form are **identical** — one canonical shape that both consume; nothing distinguishes them other than where they happen to live at the moment.

The DSL is one surface, the JSON is the other. Anything one expresses, the other must too.

## The worldlet envelope

A class definition's natural home in JSON is as a **record inside a worldlet** — see [worldlets/worldlet.json](../../ecoverse/worldlets/worldlet.json) for the canonical example. Class definitions use the **whole-hash form** that `puck.uno/class` opts into: `class: "puck.uno/class"` at the record's top level alongside the definition's properties (`name`, `inherits`, `fields`, `methods`, etc.), rather than wrapping them in a `bucket`.

A worldlet wrapping one class:

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",
    "records": {
        "a": {
            "class": "puck.uno/class",
            "name": "foo.com/character"
        }
    }
}
```

Notes:

- Records live under a top-level `records` hash, keyed by arbitrary string. UUIDs are conventional; short letters like `"a"` work in worked examples.
- The `name` field on the record is the **UNS this class is published at** — the storage address. The class object itself doesn't carry a UNS; the field is a property of the record (where the class is stored), not the class (what it is). The record's storage key (`"a"` above) is unrelated to that UNS — opaque from the outside.
- Other class-definition properties — `description`, `inherits`, `fields`, `methods`, `uniques` — sit alongside `name` and `class` at the record top level. This is the **whole-hash form**: the class's content lives at the top level rather than under a `bucket` key.
- Whole-hash form is a class-level opt-in. Built-in classes like `puck.uno/class` use it because their content reads better flat. Most user classes do NOT opt in; their instances ride the regular `{bucket, stack}` shape from the [objects spec](../../ecoverse/objects/structure.md).

A full worldlet may also carry `files`, `file_chunks`, etc. — see [worldlets/index.md](../../ecoverse/worldlets/index.md) for the complete spec.

## A class at a glance

<a class="copy" href="#">copy</a>

~~~caspian
class
	inherits 'starfleet.com/person'
	field 'name',      class: :string, required: true, get: true, set: true
	field 'nickname',  class: :string, get: true, set: true
	field 'rank',      class: :string, required: true, get: true, set: true
	field 'serial',    class: :string, required: true, unique: true, get: true, set: true
	field 'starship',  class: 'puck.uno/reference', allowed: 'starfleet.com/ship', get: true, set: true

	method &greet($casual:{required:false})
		puts 'Hello, ' + if $casual and @nickname
			@nickname
		else
			#bucket['name']
		end
	end
end
~~~

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",
    "records": {
        "a": {
            "class": "puck.uno/class",
            "name": "starfleet.com/officer",
            "inherits": "starfleet.com/person",
            "fields": {
                "name": {"class": "string", "required": true,                   "get": true, "set": true},
                "nickname": {"class": "string",                                     "get": true, "set": true},
                "rank": {"class": "string", "required": true,                   "get": true, "set": true},
                "serial": {"class": "string", "required": true, "unique": true,   "get": true, "set": true},
                "starship": {"class": "puck.uno/reference", "allowed": "starfleet.com/ship", "get": true, "set": true}
            },
            "methods": {
                "greet": {
                    "params": {
                        "casual": {}
                    },
                    "body": "puts 'Hello, ' + (if $casual and @nickname; @nickname; else; #bucket['name']; end)"
                }
            }
        }
    }
}
```

The record uses the **whole-hash form** that `puck.uno/class` (the metaclass for class definitions) opts into: rather than wrapping the definition's properties in a `bucket`, they sit at the record's top level alongside `class`. It's a shorthand specifically for class-definition records — instance records of normal classes use the explicit `{bucket, stack}` shape from the [objects spec](../../ecoverse/objects/structure.md).

Field-by-field: `class` declares the field's type (string, a UNS reference, etc.); `required`, `unique`, `allowed` are constraints; `get` and `set` declare auto-generated getter/setter methods. Method-level: `params` is a hash of param names to option-hashes (empty options hash here just means "all defaults"); `body` carries the Caspian source string (or, for some classes, a CaspJ tree — both forms are valid).

## Constructs

What follows is the construct-by-construct catalog. Each section shows the Caspian DSL form and the worldlet JSON. Where the JSON shape is not yet settled, the DSL is shown alone with the gap called out.

### Class identity

<a class="copy" href="#">copy</a>

~~~caspian
class
	...
end
~~~

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",
    "records": {
        "a": {
            "class": "puck.uno/class",
            "name": "foo.com/character"
        }
    }
}
```

The Caspian DSL declaration is just `class ... end`. The class is an object; it doesn't carry its own UNS. **The UNS is the address where you put the class** — for external lookup via `%puck['https://foo.com/character']`, for fetching from a remote source, for naming an entry in a worldlet record.

In the JSON form, the `name` field on the class-definition record is the UNS this class is published at. That's a property of the **record** (where the class lives), not of the class itself. The record's own key in `records` (here `"a"`) is an arbitrary short identifier, separate from both the class's content and its publication UNS. See [worldlets/index.md](../../ecoverse/worldlets/index.md) for the worldlet envelope and [worldlet.json](../../ecoverse/worldlets/worldlet.json) for the canonical by-example reference.

The "things live where you store them" principle applies fully: a class declared as `$gup = class ... end` lives at `$gup`. A class published to a fetch-able URL lives at that URL — and the UNS for `%puck` lookup is that URL. A class returned from a method lives wherever the caller stores it. UNS is one specific storage location, not an intrinsic identity.

### Inheritance

<a class="copy" href="#">copy</a>

~~~caspian
class
	inherits 'foo.com/person'
end
~~~

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",
    "records": {
        "a": {
            "class": "puck.uno/class",
            "name": "foo.com/character",
            "inherits": "foo.com/person"
        }
    }
}
```

Single parent. Inheritance is always explicit; no path-implied inheritance.

### Abstract

<a class="copy" href="#">copy</a>

~~~caspian
class
	abstract true
end
~~~

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",
    "records": {
        "a": {
            "class": "puck.uno/class",
            "name": "puck.uno/mikobase",
            "abstract": true
        }
    }
}
```

Direct instantiation raises. Subclasses can be instantiated normally.

### Fields

<a class="copy" href="#">copy</a>

~~~caspian
class
	field :name,      class: :string, required: true, collapse: true
	field :age,       class: :number, min: 0, integer_only: true
	field :homeworld, class: 'puck.uno/reference', allowed_class: 'foo.com/planet'
end
~~~

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",
    "records": {
        "a": {
            "class": "puck.uno/class",
            "name": "foo.com/character",
            "fields": {
                "name": {"class": "string", "required": true, "collapse": true},
                "age": {"class": "number", "min": 0, "integer_only": true},
                "homeworld": {"class": "puck.uno/reference", "allowed_class": "foo.com/planet"}
            }
        }
    }
}
```

Built-in type names are bare strings — `:string` and `'string'` are equivalent in the DSL. UNS names use the quoted form. For the field-shape conventions and per-type constraint settings, see [worldlets/worldlet.json](../../ecoverse/worldlets/worldlet.json) — records `a`-`f` show fields with their constraints in use. A consolidated constraint catalog hasn't been written yet for the new spec; until it lands, the by-example reference is the source.

### Inline vs named field types

Inline field-type definitions (constraints written directly in the field declaration) are only valid for the basic types (`string`, `number`, `boolean`, `url`, `timestamp`, `hash`, `array`). UNS-named custom classes are referenced by name only — their structure lives in a separate class definition elsewhere in the worldlet.

The exception is `hash`, which can carry inline `fields`, an `of` element-type, and `default` field settings. See [worldlets/worldlet.json](../../ecoverse/worldlets/worldlet.json) record `a` for the canonical hash-with-fields example.

### Field settings

For the common, type-specific, reference, and array/hash settings, see [worldlets/worldlet.json](../../ecoverse/worldlets/worldlet.json) records `a`-`f`. The Caspian DSL accepts the same keys as keyword arguments to `field`:

<a class="copy" href="#">copy</a>

~~~caspian
class
	field :slug,    class: :string, required: true, unique: true, min_length: 1
	field :rating,  class: :number, gte: 0, lte: 10, integer_only: true
	field :tags,    class: :array,  of: :string, min_elements: 1
	field :avatar,  class: 'puck.uno/dbfile', required: true
end
~~~

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",
    "records": {
        "a": {
            "class": "puck.uno/class",
            "name": "foo.com/show",
            "fields": {
                "slug": {"class": "string", "required": true, "unique": true, "min_length": 1},
                "rating": {"class": "number", "gte": 0, "lte": 10, "integer_only": true},
                "tags": {"class": "array",  "of": "string", "min_elements": 1},
                "avatar": {"class": "puck.uno/dbfile", "required": true}
            }
        }
    }
}
```

### Reference fields

<a class="copy" href="#">copy</a>

~~~caspian
class
	field :homeworld, class: 'puck.uno/reference', allowed_class: 'foo.com/planet'
	field :stop,      class: 'puck.uno/reference',
	                  allowed_classes: ['foo.com/moon', 'foo.com/station']
end
~~~

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",
    "records": {
        "a": {
            "class": "puck.uno/class",
            "name": "foo.com/character",
            "fields": {
                "homeworld": {"class": "puck.uno/reference",
                              "allowed_class": "foo.com/planet"},
                "stop": {"class": "puck.uno/reference",
                              "allowed_classes": ["foo.com/moon", "foo.com/station"]}
            }
        }
    }
}
```

`allowed_class` and `allowed_classes` may be combined — they merge. Subclasses of the named classes are also valid.

### Single-field unique constraints

<a class="copy" href="#">copy</a>

~~~caspian
class
	field :serial, class: :string, required: true, unique: true
end
~~~

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",
    "records": {
        "a": {
            "class": "puck.uno/class",
            "name": "foo.com/officer",
            "fields": {
                "serial": {"class": "string", "required": true, "unique": true}
            }
        }
    }
}
```

Null values are excluded from the uniqueness check — two records may both have null for a unique field.

### Multi-field unique constraints

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",
    "records": {
        "a": {
            "class": "puck.uno/class",
            "name": "borg.com/appearance",
            "fields": {
                "person": {"class": "puck.uno/reference", "required": true},
                "episode": {"class": "puck.uno/reference", "required": true}
            },
            "uniques": [
                ["person", "episode"]
            ]
        }
    }
}
```

The shared JSON form is a class-level `uniques` array on the class definition. The Caspian DSL has no construct for multi-field unique today; see [Open questions](#open-questions) below.

### Joins

<a class="copy" href="#">copy</a>

~~~caspian
class
	field :person,  class: 'puck.uno/reference', allowed_class: 'foo.com/person'
	field :episode, class: 'puck.uno/reference', allowed_class: 'foo.com/episode'

	join :person, :episode
end
~~~

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",
    "records": {
        "a": {
            "class": "puck.uno/class",
            "name": "foo.com/appearance",
            "fields": {
                "person": {"class": "puck.uno/reference", "allowed_class": "foo.com/person"},
                "episode": {"class": "puck.uno/reference", "allowed_class": "foo.com/episode"}
            },
            "join": ["person", "episode"]
        }
    }
}
```

`join` is a class-level shorthand for "required + unique-in-combination + immutable" on each listed field.

### Methods

Methods live in a `methods` namespace, sibling to `fields` — not inside `fields`. Each entry is keyed by method name and carries the method's class (`"function"`) and body.

<a class="copy" href="#">copy</a>

~~~caspian
class
	function &greet(name:)
		'Hello, ' + $name
	end

	remote function &save(name:, rank:)
	end
end
~~~

<a class="copy" href="#">copy</a>

```json
{
    "format": "worldlet/1.0",
    "records": {
        "a": {
            "class": "puck.uno/class",
            "name": "foo.com/character",
            "methods": {
                "greet": {
                    "body": "'Hello, ' + $name"
                },
                "save": {
                    "remote": true,
                    "body": "some CaspJ code"
                }
            }
        }
    }
}
```

Methods live in a `methods` namespace at the class-record's top level, sibling to `fields`. Each entry is keyed by method name; the body lives under `body`. See [worldlet.json](../../ecoverse/worldlets/worldlet.json) records `b` and `c` for the canonical method-shape examples (including the nested-method namespace and `params` blocks).

The `remote function` body adds `remote: true` as a sibling flag on the method entry.

### Reserved pass-through fields

Six fields are reserved pass-throughs on every Puckverse object and require no declaration: `vibecode`, `comment`, `misc`, `corporate`, `class`, `bucket`. See [standard-fields.md](../../ecoverse/standard-fields.md).

These do not appear in class definitions on either surface — they are always present implicitly.

## Constructs not yet expressible in shared JSON

The following Caspian DSL constructs do not have a settled worldlet / shared JSON shape. They are shown in DSL form only. The gap is real and needs a decision.

### Field auto-getters and auto-setters

`field` accepts `:get` and `:set` flags that auto-generate reader and writer methods. The Caspian DSL form has this surface; the worldlet/Mikobase JSON shape for the flags is not yet pinned down. See [caspian/index.md § field](../index.md#field).

<a class="copy" href="#">copy</a>

~~~caspian
class
	field :nickname                    # private, no external access
	field :nickname, :get              # creates a getter
	field :nickname, :get, :set        # creates both getter and setter
end
~~~

(A previous `accessor` keyword filled this role; it has been removed and its functionality folded into `field`.)

No worldlet JSON shape exists today for the `:get` / `:set` flags. A natural fit would be additional keys inside each field's entry in the `fields` hash (`get: true`, `set: true`) alongside the existing `class`, `required`, etc. That is a proposal, not spec.

### Helpers

`helper` creates a lazily-initialized helper object namespaced off the parent. See [caspian/index.md § Helpers](../index.md#helpers).

<a class="copy" href="#">copy</a>

~~~caspian
class
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

## Classes without a UNS

Every Caspian class is "anonymous" in source — the declaration is `class ... end`, with no UNS embedded. A class only gets a UNS by being **stored at one**: published to a fetch-able URL, written into a worldlet record's `name` field, or otherwise placed at a discoverable address.

Common cases for classes that never get a UNS:

- **Local-only classes.** Defined inside a program for its own use, never published. Stored at a variable: `$gup = class ... end`. Reachable through that variable; nowhere else.
- **Nested classes built by another class.** An outer class may construct inner classes for its own use (helpers, factories, generated subclasses). The outer class holds the references; the inner classes live within it. No UNS needed because external code interacts with them through the outer class's API.
- **Classes returned from methods.** A method that constructs and returns a class hands the caller a reference; the caller stores it wherever it likes.
- **Identity-by-location.** Some systems use a non-UNS location as the discoverability address — e.g., Robinson page files identified by their path in the directory tree. The class is still anonymous in source; the path is what makes it findable.

<a class="copy" href="#">copy</a>

~~~caspian
class
	inherits 'puck.uno/robinson/page'

	function &process($request)
		...
	end
end
~~~

When a class without a UNS needs to ride along inside a worldlet record (for transport or storage), the worldlet still needs to identify the record somehow. The `name` field can be absent or null on the class-definition record — the receiver knows it as "the class living at the storage location implied by where this worldlet was fetched from" or as the value of whatever reference holds it post-load. See [Open questions](#open-questions) for the remaining shape decision.

## Open questions

These are the decisions that need to be made before the shared JSON form is fully settled. Each blocks at least one construct above.

### Reconciling the worldlet doc with the methods namespace

[worldlets/index.md § classes](../../ecoverse/worldlets/index.md#classes) currently shows methods stored *inside* `fields` with `"class": "function"`. That shape is wrong — methods belong in a separate `methods` namespace, sibling to `fields`. The worldlet doc needs to be updated to match, and its example classes (`starfleet.com/person`, `starfleet.com/officer`) need their methods moved out of `fields`.

### Body key naming: `"caspian"` vs `"caspj"`

The body key is named `"caspian"` (per worldlet doc) but the intended content is CaspianJ JSON — the engine's runtime format, not Caspian source text. Either the key name should change (`"caspj"` or `"body"`) to match the content, or the content should be Caspian source string (and the key name stays). Pick one — the current mismatch will confuse implementers.

### Remote functions in the methods shape

`remote function` is sketched above as `"remote": true` alongside `"class": "function"` in the methods entry. This has not been explicitly confirmed; needs a one-line sign-off.

### Field `:get` / `:set` JSON shape

The Caspian DSL's `:get` / `:set` flags on `field` (which auto-generate getter and setter methods) don't have a pinned-down worldlet JSON shape. The natural fit is additional keys inside each field's entry in the `fields` hash (`get: true`, `set: true`) alongside `class`, `required`, etc. Not yet confirmed.

### Helpers JSON shape

Helpers contain methods, so the shape depends on a decision about namespacing. The methods-as-fields pattern doesn't directly give helpers a home — they're sub-namespaces, not flat fields.

### Multi-field unique in the Caspian DSL

The worldlet JSON has `"uniques": [["a", "b"]]` for non-join multi-field uniqueness. The Caspian DSL has no equivalent — `join` is the only multi-field construct, and it implies extra semantics (required, immutable) that uniqueness alone shouldn't carry. A `unique :a, :b` statement would close the gap.

### Hooks in-class

`on_close` and `before_save` / `after_save` are external-only today. Whether they should also be declarable in-class — and if so, what the shape looks like — needs a call.

### Classes without a UNS in a worldlet

Since the DSL no longer carries a UNS, **every class is anonymous in source**. The UNS only appears when the class is being placed at a publication address (and that UNS becomes the record's `name` field). For a class-definition record that isn't being published — e.g., a transient class carried in a worldlet for transport — the `name` field can be omitted or null. The record's storage key (`"a"`, `"b"`, ...) is still required as the in-worldlet identifier; the lack of a `name` is what marks the class as not-published-anywhere.

Whether to keep `name` as optional/nullable (current direction) or to require it always (with some convention for "not for publication") is a small decision worth pinning down once the first round of un-published-class worldlets is in use.

## See also

- [implements?](implements.md) — class-level structural API conformance check (`$class.implements?($other_class)`). Runtime, structural, no separate interface concept. V1.0 in scope.

## What this doc is not

Not the field-constraint reference — that lives in [class-definition.md](../../mikobase/class-definition.md). Not the DSL grammar reference — that lives in [caspian/index.md § Classes](../index.md#classes). Not the worldlet spec — that lives in [worldlets/index.md](../../ecoverse/worldlets/index.md). This file is the bridge that shows how a single class definition looks across all of them.
