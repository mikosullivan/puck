# Requirements

~~~vibecode
{"vibecode": {
	"doc": "requirements_root",
	"role": "root of the authoritative Caspian / Puck / Mikobase requirements tree. Single-source-of-truth: every concept has exactly one canonical doc here. Other docs (ideas, slice plans, implementation) may link in but may not redefine.",
	"status": "rebuilding — the prior tree at documentation/requirements-old/ is being migrated concept by concept, with revision as needed",
	"audience": "humans and AI looking up current Caspian behavior — start here; only consult requirements-old/ for concepts that haven't been migrated yet"
}}
~~~

These docs are **authoritative** for the Caspian language, the Puck protocol, the Mikobase object store, and the rest of the Puck ecoverse. Where this tree and any other doc disagree, this tree is correct.

## What lives here

- Canonical spec for every concept that has been committed to (or carried forward from prior thinking with revision).
- One doc per concept. Other docs in the project may link to a canonical doc here but may not redefine its content elsewhere.

## What does NOT live here

- **Brainstorm and pre-commitment material** — lives in [ideas/](../ideas/). Ideas may graduate into this tree once they're settled enough to commit. <!-- outbound-link-allowed -->
- **Slice-by-slice development plans** — describe how to implement the spec, not the spec itself. Will land under `development/` here once the slice docs migrate from the old tree.
- **Historical material from the prior tree** — sits at [requirements-old/](../requirements-old/). Not authoritative. Being migrated piece by piece. <!-- outbound-link-allowed -->

## How this tree is being built

The previous requirements tree accumulated structural problems (duplicate authority claims, contradictions, drift). Rather than audit-and-patch indefinitely, we're rebuilding from scratch:

1. Concepts migrate one at a time from `requirements-old/` to here, with revision and consolidation as needed.
2. When a concept lands here, anything in `requirements-old/` covering the same ground gets deleted (it's no longer needed; nothing in the old tree is authoritative).
3. Slice docs, ideas docs, and the implementation update their references to point at the new canonical home.
4. The migration is complete when `requirements-old/` is empty and can be removed.

## Discipline

The reason for the rebuild only sticks if the discipline holds:

- **One concept, one doc.** When introducing a new concept, pick its canonical home before writing about it elsewhere.
- **Other docs link, never redefine.** Cross-references are URL/path links into the canonical doc, not paraphrases of it.
- **Vibecode `role` fields name what each doc owns.** Reading the `role` line should answer "is this the canonical doc for X, or is it referencing X?"
- **Multiple authoritative claims for the same concept are a bug.** When found, surface and fix.

## Implementation notes

Generally, requirements docs say **what** the system does, not **how** to build it. Implementation belongs in the slice-by-slice development plans, not here.

The exception: some requirements, if implemented the obvious naïve way, are expensive enough that the cost would prohibitive. In those cases the requirement carries an **Implementation notes** section at the bottom of the doc that sketches an efficient approach — enough guidance that the implementer knows the feature is realistic and roughly how to get there.

Rules for **Implementation notes** sections when they appear:

- They live at the bottom of the doc, after the spec proper.
- They sketch a known-workable approach, not a binding mandate. An implementer free to find a better way still can.
- They are NOT a substitute for the development plan, which still owns the schedule and the slice-by-slice rollout.
- They are NOT a place to dump random implementation thoughts. If the naïve implementation is fine, no Implementation notes section is needed.

If you're authoring a new requirements doc and you find yourself wanting to add an Implementation notes section, ask first whether the requirement itself could be simplified to avoid the cost. If the cost is real and inherent, then the section earns its place.
