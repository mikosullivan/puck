# Old requirements — NOT authoritative

~~~vibecode
{"vibecode": {
	"doc": "requirements_old_root",
	"role": "deprecation notice for the prior requirements tree. This tree is preserved verbatim from before the rebuild as a historical reference; nothing in it should be treated as current spec. The new authoritative requirements live at documentation/requirements/.",
	"status": "deprecated — not authoritative; do not treat anything here as current spec",
	"audience": "humans and AI looking up Caspian behavior — STOP and go to requirements/ first; only consult here if the concept hasn't been migrated yet"
}}
~~~

⚠ **This tree is no longer authoritative.** The Caspian / Puck / Mikobase requirements are being rebuilt from scratch in [documentation/requirements/](../requirements/). Material is being migrated concept by concept, with revision as needed. Until a concept's canonical doc exists in the new tree, this old tree is the only place it's described — but with the expectation that the new authoring will probably change things.

## Why this exists

Over time the previous requirements tree accumulated:

- Concepts described in multiple places with subtly (or directly) contradictory statements.
- Tables of the same thing maintained separately and drifting (the engine-slots inventory was the clearest example).
- Docs that started as brainstorm material in `ideas/` ending up cited as authoritative spec without ever being formally promoted.
- Renames and refactors that landed in some referencing docs and not others.

Rather than continue audit-and-patch on accumulated drift, the rebuild starts from a clean tree with a single-source-of-truth discipline: every concept has exactly one canonical home; other docs may link to it but may not redefine it.

## How to use this tree

- **For current authoritative spec**, go to [documentation/requirements/](../requirements/). If the concept you want has been migrated, it lives there.
- **If the concept hasn't been migrated yet**, this tree may have the historical description. Treat it as a starting point for re-authoring, not as a source of truth.
- **Inbound links to this tree from `ideas/`, slice docs, the implementation, etc., may still exist** during the migration. They'll be updated as their target concepts migrate to the new tree.

## When this tree goes away

When all material from `requirements-old/` has either been migrated to `requirements/` or formally retired, this tree gets deleted. There's no plan to keep it around indefinitely.
