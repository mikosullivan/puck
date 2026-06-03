# Class definitions

~~~json
{"vibecode": {
	"doc": "class_definition",
	"role": "short summary of how classes are defined in Mikobase; full spec lives at ecoverse/worldlets/",
	"canonical_spec": "../ecoverse/worldlets/index.md",
	"canonical_by_example": "../ecoverse/worldlets/worldlet.json"
}}
~~~

A class definition lives in a Mikobase record. Records of class `puck.uno/class` use the **whole-hash form**: the definition's properties sit at the record's top level alongside `class: "puck.uno/class"`, rather than under a separate `bucket` and `stack`.

```json
{
    "class": "puck.uno/class",
    "name": "foo.com/character",
    "inherits": "foo.com/being",
    "fields": { ... },
    "methods": { ... }
}
```

The class's identity is `class: "puck.uno/class"`. Its name (the UNS being defined) is the `name` field. Inheritance, fields, and methods sit alongside as siblings.

For the full structural spec — the worldlet envelope, the whole-hash form vs. the `{bucket, stack}` form for instance records, field-by-field constraint settings, and the canonical examples — see:

- [ecoverse/worldlets/index.md](../ecoverse/worldlets/index.md) — the spec.
- [ecoverse/worldlets/worldlet.json](../ecoverse/worldlets/worldlet.json) — the by-example reference. Records `a`-`f` are class definitions; records `g`-`v` are instances.
