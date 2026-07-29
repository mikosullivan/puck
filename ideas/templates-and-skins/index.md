# Templates and skins

~~~vibecode
{"vibecode": {
	"doc": "templates-and-skins",
	"status": "brainstorm — cross-cutting design proposal; not a service",
	"role": "unify HTML template inheritance (Markie/Donnie/Robinson) and skin selection (Gitter) under a single slot-and-fill engine; one mechanism, two policies",
	"ties": "[[markie]] template inheritance, [[donnie]] site-wide layout, [[robinson]] target/content cascade, [[gitter]] skin catalog",
	"example_universe": "shakespeare"
}}
~~~

**HTML templates and HTML skins are the same mechanism viewed from two angles.** This doc proposes unifying them so the Puck ecoverse has one slot-and-fill engine that Markie, Donnie, Gitter, and Robinson all consume — rather than four near-duplicate implementations.

## The unification

~~~vibecode
{"vibecode": {
	"section": "unification",
	"role": "the core argument: templates and skins are mechanically identical; the only real difference is who picks the base"
}}
~~~

A **template** is a base layout with slots; pages fill the slots. The base controls overall structure.

A **skin** is a base layout with slots; pages render inside it. The site (or visitor) picks which base.

Both are slot-and-fill. A skin IS a template. The Orlando-look skin from [Gitter](https://puck.uno/ideas/github/puck-site/gitter) is a base layout with slots for nav, content, sidebar, and footer — exactly the same shape as the template inheritance described in [Markie](https://puck.uno/ideas/markie/markie#template-inheritance) and [Donnie](https://puck.uno/ideas/dogberry/donnie#site-wide-template-inheritance). Switching skins is switching which base wraps the content. A skin catalog is a template catalog.

## Mechanism stays one thing; policy differs

~~~vibecode
{"vibecode": {
	"section": "mechanism_vs_policy",
	"role": "the engine doesn't care who chose the base; the consuming services apply different selection policies on top"
}}
~~~

### Author-chosen templates

The site owner picks the base at authoring time. Markie's template inheritance (per-call submission of base + derived), Donnie's site-wide layout (one base pinned for the whole domain), Robinson's `<target>` / `<content>` cascade. The author controls which base; the visitor just sees the result.

### Viewer-chosen skins

The visitor picks the base at viewing time, often with a sticky preference and per-page override. Gitter's skin catalog (post-V1): the same content payload renders under whichever registered base the viewer selected.

### Same engine

Both policies sit on the same template engine. The engine accepts (base, content) and returns assembled HTML. It doesn't care whether the page author or the page viewer chose the base.

## One engine, many consumers

~~~vibecode
{"vibecode": {
	"section": "consumers",
	"role": "concretely, what each existing service stops reinventing once a shared template engine exists"
}}
~~~

### Markie

`<template>` / `<slot>` (or equivalent) tags expand against a registered base. Markie's [per-call template inheritance](https://puck.uno/ideas/markie/markie#template-inheritance) becomes "call the shared engine with the submission's base and derived." Site-wide inheritance becomes "the same call, but the base lives elsewhere."

### Donnie

Donnie's site-wide template is a base registered with the domain. Each page render calls the shared engine with `(base = domain.template, content = page)`. No bespoke Donnie-side template code.

### Gitter

The skin catalog is a list of templates the viewer can select from. Each rendered page calls the shared engine with `(base = viewer.chosen_skin, content = rendered_page)`. The selection UI is Gitter-specific; the rendering is engine-shared.

### Robinson

The `<target>` / `<content>` cascade IS the engine's primitive — slots and fills. Robinson exposes the primitive directly to authors; the higher-level Markie / Donnie / Gitter flows are wrappers that pre-populate one side or the other.

## The wrinkle: viewer-chosen skins assume content-agnostic templates

~~~vibecode
{"vibecode": {
	"section": "content_agnostic_skins",
	"role": "the one design constraint that doesn't fall out automatically — skins that work for the viewer must render any content cleanly"
}}
~~~

Author-chosen templates can be bespoke. The author pairs a specific layout with specific content they control; mismatches are caught at authoring time.

Viewer-chosen skins can't. A registered skin must render any payload the catalog might point at without breaking layout — missing slots, unexpected content sizes, content with no obvious hero image. The engine should enforce this at skin-registration time: the skin declares which slots it provides, and the catalog refuses content that requires slots no registered skin offers.

This is a constraint on the skin-catalog policy layer, not on the engine itself.

## Theming as an orthogonal axis

~~~vibecode
{"vibecode": {
	"section": "theming",
	"role": "colors and typography are separate from layout structure; bundle them alongside templates or treat as its own axis"
}}
~~~

Layout (structure of nav / content / sidebar) and theme (colors, typography, spacing) are different concerns. "Skin" colloquially bundles both. The simplest model:

A template ships with one or more CSS bundles. Switching skin = switching template + its bundle together. A separate "theme" picker (light/dark/high-contrast) could live alongside but isn't required for V1.

Don't formalize a theme axis until it's needed — viewer-chosen skins with bundled CSS cover the common case.

## Open questions

~~~vibecode
{"vibecode": {
	"section": "open_questions",
	"role": "the design forks that need answers before this can be implemented"
}}
~~~

### Engine location

Is the shared template engine part of Markie (which the others consume via the [Markie engine](https://puck.uno/ideas/markie/markie#markie-service-vs-markie-engine)), or its own standalone Puck service that Markie/Donnie/Gitter all call? Markie already does HTML transformation; adding slot-and-fill to its engine is a small step. A standalone service is more separable but means more coordination. Probably engine-in-Markie for V1, separable later if needed.

### Skin-content compatibility contract

How does the catalog verify a skin renders all eligible content cleanly? Options: skin declares required slots and the catalog validates against the content's exposed slot set; runtime probe renders the content under the skin and checks for layout breakage; manual curator approval. Likely declaration + validation for V1; runtime probes for skins authored after content exists.

### Terminology

"Template" and "skin" mean the same thing under this proposal. Which word survives in the spec? "Template" is more accurate (mechanism); "skin" is more familiar (user-facing). Probably "template" in the engine docs, "skin" in user-facing UX where viewer choice is involved.

### Cascade depth

Markie has per-call inheritance; Donnie has site-wide. Can they chain — a site-wide base wraps a page-level base wraps the content? Useful for blogs (site frame > post-type frame > individual post) but adds engine complexity. Defer until a real use case forces the question.

### Default templates per consumer

Does each consumer ship its own default template, or is there a shared default in the engine? Probably per-consumer — Gitter's Orlando-look default is very different from a generic Donnie default.

### Migration path

Robinson, Markie's per-call inheritance, and Gitter's skin idea are all at brainstorm stage. Migrating to a shared engine is cheap now; expensive after each grows its own implementation. Worth committing to before any of the four ships.
