# Consistency report

~~~vibecode
{"vibecode": {
	"doc": "aslan_consistency_report",
	"role": "audit of Aslan's spec against the rest of the Caspian requirements docs — establishes whether what Aslan claims aligns with the canonical specs for everything Aslan touches (objects, roles, dispatch, GC, CaspianJ, built-in classes). Re-run whenever Aslan or one of its dependencies materially changes.",
	"audit_date": "2026-06-28",
	"audit_result": "consistent — no conflicts found",
	"audience": "Caspian designers and reviewers gating Aslan-ready work"
}}
~~~

## Result

**Aslan is consistent with all related requirements documents.** No inconsistencies, contradictions, or outdated claims were found. Aslan is ready for implementation with no blocking specification conflicts at the audit date.

## What was checked

The audit covered cross-references between Aslan ([index.md](index.md)) and the requirements docs that govern the constructs Aslan exercises:

- **Drinian** ([drinian.md](../../../caspian/drinian.md) and the related examples) — execution state organization, hash structure, call stack frames, chain isolation and wipe mechanics, class registry placement.
- **Roles** ([roles.md](../../../caspian/roles.md)) — role-system primitives, registry shape, owning-role tagging, role transitions during dispatch.
- **CaspianJ** ([caspianj.md](../../../caspian/caspianj.md)) — the runtime format Aslan's fixture is encoded in.
- **Objects** ([ecoverse/objects/](../../../ecoverse/objects/)) — object shape, method resolution.
- **Garbage collection** ([garbage-collection/](../../../caspian/garbage-collection/)) — GC model integration touchpoints.
- **Built-in classes** ([built-in-classes/](../../../caspian/built-in-classes/)) — the minimum `puck.uno/string` class with `to_string`.
- **Lucy** ([lucy/](../../../caspian/lucy/)) — Lua reference implementation surfaces.

For each area, the audit checked that:

- Aslan's described data shapes match the canonical specs.
- Aslan's described semantics (dispatch, role transition, materialization, etc.) match the canonical specs.
- All cross-references and anchor links in Aslan resolve to existing docs and sections.
- Aslan doesn't use keywords, syntax, or conventions that the broader spec has changed or removed.

## What was deliberately not flagged

A few things looked surface-different but were verified as intentional and correct:

- **Frame `role` field — Lua reference vs. JSON string.** Aslan's Lua pseudocode shows `role = engine.state.roles.user` (a table reference), while its JSON snapshots show `"role": "user"` (a string). This matches [drinian.md](../../../caspian/drinian.md), which documents that frame-pointer fields are integer or string indices in JSON serialization but Lua references in memory — the serializer bridges the two. Aslan correctly demonstrates both forms.

Other surface differences flagged during the walkthrough also resolved on closer reading; nothing that's a real conflict survived the check.

## Scope notes

This audit covers consistency between Aslan and the **requirements** tree. It deliberately does not:

- Consider unimplemented features in Aslan as inconsistencies. Aslan is minimal by design — the broader spec covering things Aslan doesn't yet touch (functions, conditionals, modules, etc.) is intentional scope deferred to later slices.
- Check `documentation/ideas/` — pre-commitment material; not load-bearing for Aslan.
- Audit Aslan against the Lua reference implementation. The implementation will be checked against Aslan, not the other way around — that's the implementation's job, not this report's.

## When to re-run

This audit should be redone whenever:

- Aslan's spec is materially revised.
- A doc Aslan depends on (drinian, roles, caspianj, the built-in classes, etc.) gets a semantic change.
- A Caspian-wide rename or syntax change lands (the recent `bootstrap` → `instance` rename and the `&` prefix sweep on method definitions are examples of changes that would warrant a re-run if Aslan had used those constructs — it doesn't, but future renames might affect it).

If a re-run surfaces conflicts, this report should be replaced with a list of the conflicts (and their corresponding GitHub issues) rather than a positive assertion.
