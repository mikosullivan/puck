# Class definition drift: Caspian and Mikobase

~~~json
{"vibecode": {
	"doc": "class_definition_cleanup",
	"role": "audits how the class-definition specs in Caspian and Mikobase have drifted out of consistency; catalogs where they agree, where they diverge, and surfaces the open questions that need a decision before either side hardens further",
	"audience": "Miko (primary), Claude (secondary as a settled-decisions index once decisions are made)",
	"format": "agreements_then_divergences_then_open_questions; each divergence cites both sides",
	"explicitly_out_of_scope": ["mikobase_vs_skeletor_architecture"],
	"key_concepts": ["caspian_class_dsl", "mikobase_class_schema", "field_declaration",
		"accessor_helper", "instance_state_access", "lifecycle_hooks"]
}}
~~~

This file audits how class-definition specs have drifted between Caspian (the language) and Mikobase (the object store). Miko flagged the two as feeling inconsistent. This catalogs the divergences concretely so the next round of edits can either reconcile them or document a deliberate split.

## Scope and non-goals

In scope: user-facing class-definition surface on each side — how a class is declared, what fields/methods/hooks it can carry, what vocabulary each side uses.

Out of scope: the Mikobase-vs-Skeletor architectural question (engine-private vs program-visible state). The Mikobase-vs-Skeletor split is a separate decision that almost certainly will not happen; this audit assumes both Caspian and Mikobase coexist and asks only whether they agree on how a *user* declares a class.

The canonical docs consulted:

- [documentation/caspian/index.md](../index.md) — Caspian DSL, especially the Classes section
- [documentation/caspian/lucy/index.md](../lucy/index.md) — Lua reference impl, runtime class model
- [documentation/caspian/built-in-classes/object.md](../built-in-classes/object.md) — base class behavior
- [documentation/mikobase/class-definition.md](../../mikobase/class-definition.md) — Mikobase class schema
- [documentation/mikobase/index.md](../../mikobase/index.md) — Mikobase overview
- [documentation/ecoverse/standard-fields.md](../../ecoverse/standard-fields.md) — shared reserved fields

## Where the specs agree

Class identity uses UNS strings on both sides — `class 'foo.com/character'` in Caspian, `"foo.com/character"` as the dict key in Mikobase. No drift.

The `inherits` keyword for single-parent inheritance is identical: Caspian uses `inherits 'parent.uns/x'` as a statement inside the class body; Mikobase uses `"inherits": "parent.uns/x"` as a field on the class definition object. Same word, same semantics.

Field-constraint vocabulary is identical down to keyword names: `class`, `required`, `default`, `unique`, `min`, `max`, `integer_only`, `collapse`. A Caspian `field :name, class: :string, required: true, collapse: true` and a worldlet record entry `"name": {"class": "string", "required": true, "collapse": true}` (sitting inside that class's `fields` namespace) are the same declaration in two surface forms.

The six reserved pass-through fields (`vibecode`, `comment`, `misc`, `corporate`, plus `class` and `bucket`) are defined at the ecoverse level and apply to both sides identically — see [standard-fields.md](../../ecoverse/standard-fields.md).

## Where the specs diverge

### Syntax form: DSL block vs JSON dict

Caspian uses an executable DSL inside `class 'foo.com/x' ... end` blocks. The worldlet/Mikobase form is a declarative JSON record: each class definition is its own entry in the worldlet's top-level `records` dict, using the whole-hash form — `class: "puck.uno/class"` plus sibling `name`/`inherits`/`fields`/`methods`/etc. — see [worldlet.json](../../ecoverse/worldlets/worldlet.json) records `a`-`f`. This is by design — the two sides serve different consumers — but the dual-surface arrangement has consequences elsewhere on this list (notably methods and accessors, which only one surface supports).

The question worth pinning down: is Mikobase's JSON form intended to be a serialization of what Caspian's DSL produces, or are they two independent surfaces? If the first, the field set must be a strict subset on the JSON side. If the second, drift is intentional and we should stop framing it as drift.

### Methods inside class definitions

**Resolved.** Both surfaces now express methods. Caspian permits `function &name` and `remote function &name` inside the class body. Class records in worldlets carry a `methods` namespace at the record top level, sibling to `fields` — keyed by method name, with each entry holding the method body (typically a Caspian source string under `body`) and optional flags like `remote: true`. See [worldlet.json](../../ecoverse/worldlets/worldlet.json) records `b` and `c` for canonical examples. Methods round-trip cleanly between the two surfaces.

### Accessor and helper concepts

Caspian has two concepts with no Mikobase equivalent:

- `accessor @foo` — declares `%bucket`-backed instance state that is *not* part of the schema. Used for non-persistent runtime state.
- `helper :foo` — declares a lazily-initialized namespaced sub-object hanging off the instance.

Mikobase has no analogue for either. All Mikobase state is schema-bound by definition. This means a Caspian class that uses `accessor` is mixing schema fields (which serialize) with accessor state (which doesn't), and the docs never call out the distinction in those terms.

### Instance state access: `@` sigil vs bucket field

Caspian programs access instance state with the `@foo` sigil (shorthand for `%bucket['foo']`). Worldlet/Mikobase records expose the same state through a top-level `bucket` JSON field on the record. Both refer to "the bucket" and they're the same bucket — the language sigil and the JSON field name are two surfaces on one concept. The canonical `{bucket, stack}` shape (see [ecoverse/objects/](../../ecoverse/objects/)) makes this explicit: the bucket is the object's data, accessible through `%bucket` in code and through the `bucket` field in JSON.

### Lifecycle hooks

Caspian documents `on_close` as a GC-time hook in [garbage-collection.md](../garbage-collection.md). Mikobase documents `before_save` and `after_save` as transaction-time hooks in [mikobase/index.md § listeners](../../mikobase/index.md). The two hook systems live in entirely separate docs, address different events, and neither is declared as part of a class definition — both are registered dynamically.

This isn't drift so much as siloing. A reader looking for "what hooks does my class get" has to know to read two unrelated doc sections. A unified hooks page (or at minimum cross-references between the two existing pages) would help.

### Listeners as a runtime feature

Both sides agree the listener API lives on the `$mikobase` instance, not in the class definition: `$mikobase.listen 'foo.com/x', :after_save do($change) ... end`. This is consistent — but it means the class definition is silent about its own observable events. A reader of either spec form (Caspian DSL or Mikobase JSON) has no in-place indication that the class is observable; they must read the listener docs separately.

### Join and uniqueness syntax

Caspian: `join :a, :b` as a statement inside the class body. Mikobase: `"join": ["a", "b"]` as a class-level array, plus `"uniques": [["a", "b"]]` for the unique-but-not-required-and-immutable case. The semantics match (`join` implies required + unique-in-combination + immutable on both sides), but Mikobase exposes a richer surface — the `uniques` array has no Caspian DSL counterpart.

Either Caspian needs a `unique :a, :b` companion statement, or Mikobase's `uniques` is a Mikobase-only feature that the docs should call out as such.

### Multi-class composition (the stack)

**Resolved.** Both surfaces now describe the same concept under the same name. An object's `stack` is an ordered hash of **platters**, each contributing a class to the object's identity. The canonical spec is [ecoverse/objects/](../../ecoverse/objects/); the same shape applies to Caspian's runtime objects, Mikobase records, and Puck wire objects. The old separate "class stack" and "platter stack" framings have collapsed into one model.

## Open questions

These are the decisions the report can't make on its own. Each affects how the next pass at either spec should read.

### Is the Mikobase JSON schema meant to be a serialization of the Caspian class DSL, or an independent surface?

If serialization: drift on methods/accessors/helpers must be closed (Mikobase needs slots for them). If independent: drift must be documented as deliberate, and each side's docs should stop implying the other.

### Should `bucket` be renamed on one side?

Two senses (language sigil vs JSON field) of the same word in adjacent specs is friction. Renaming Mikobase's JSON field to `state` or `data` would remove the ambiguity; leaving it as-is is also fine if a cross-reference note appears on each side.

### Does Caspian need a `unique :a, :b` statement to match Mikobase's `uniques`?

Today the asymmetry means a Mikobase class with non-`join` unique combinations can't be losslessly expressed in Caspian DSL.

### "Class stack" vs "platter stack" — pick one name?

Both terms appear in current docs for what looks like the same mechanism. A single name with a clear definition would close this.

### Should class definitions declare their own observable events?

Today the class is silent about whether it emits `after_save`, `on_close`, etc. — readers have to know to consult external listener docs. An optional `events:` slot in the class definition (declarative on both sides) would surface this without requiring listeners to be wired up.

## What this report is not

Not a fix plan — each open question above is a decision for Miko, not a recommendation. Not exhaustive: smaller drift (parameter ordering in field declarations, capitalization conventions in flag names, etc.) is omitted in favor of the structural divergences above. When the open questions are resolved, this file should either be updated to reflect the resolutions or deleted in favor of a forward-looking spec note.
