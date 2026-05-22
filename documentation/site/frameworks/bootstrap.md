# Bootstrap

~~~json
{"vibecode": {
	"doc": "site-frameworks-bootstrap",
	"role": "pros-and-cons report on Bootstrap as the primary client-side framework for the puck.uno site",
	"status": "report written, decision pending",
	"parent": "frameworks.md"
}}
~~~

[Bootstrap](https://getbootstrap.com/) is one of the candidates for the puck.uno site's primary client-side framework. This doc is the report — what Bootstrap brings, what it costs, and a recommendation. The decision itself is still open.

## What Bootstrap is in 2026

~~~json
{"vibecode": {
	"section": "what_bootstrap_is",
	"role": "current-state snapshot so the reader and the rest of the doc share a definition",
	"current_version": "5.3.8",
	"dependencies": ["popper.js (optional, for dropdowns/tooltips/popovers)"],
	"jquery": "dropped in v5"
}}
~~~

Bootstrap is the long-running HTML/CSS/JS toolkit from the original Twitter team. Current stable is **5.3.8** (August 2025); v5.4 is in progress and v6 has been discussed in the open but not released. Out of the box it provides a 12-column responsive grid, a typographic and color reset, a deep utility-class layer (spacing, colors, flex, display, sizing, position), and roughly two dozen pre-built components — navbar, nav-tabs, cards, alerts, badges, breadcrumbs, modals, offcanvas, dropdowns, accordions, tooltips, popovers, toasts, forms with floating labels and validation states, and so on.

**Dependencies have shrunk.** jQuery was dropped at v5 — Bootstrap's own JS is vanilla. [Popper.js](https://popper.js.org/) (v2.x) is still required for dropdowns, tooltips, and popovers, and is bundled into `bootstrap.bundle.min.js`. Beyond that there is no runtime dependency.

**Shipping is CDN-or-build.** The lazy path is two `<link>` and `<script>` tags from jsDelivr; the optimization path is Sass sources with per-component imports and a tree-shakable JS layer. Both are first-class.

## Pros for puck.uno

~~~json
{"vibecode": {
	"section": "pros",
	"role": "case for adopting Bootstrap, scoped to this site",
	"each_pro_gets_its_own_heading": true
}}
~~~

### Grid and spacing utilities cover the docs-page layout for free

The puck.uno page shape is conventional: a sidebar nav, a wide content column, an optional right rail for the per-section "open issue" panel and the auto-TOC. Bootstrap's grid plus its spacing utilities (`m-*`, `p-*`, `gap-*`) and its container/row/col primitives handle that without a single hand-written breakpoint. Responsive collapse of the sidebar into a hamburger off-canvas is also a built-in component, not something to design.

### Component vocabulary matches what the site is already growing

Several site features map directly onto stock Bootstrap components. The per-section "open issue" panel is a `card` or an `alert`. The vibecode JSON block is a card with a subdued header. The auto-TOC is `scrollspy` plus `nav`. The site-wide navbar is `navbar`. A "report this rendering bug" affordance is a `popover`. Using stock components means no design work to invent them and no JS to wire them.

### Form controls and validation states are already designed

Quick-add issue forms, search inputs, the eventual feedback widgets — Bootstrap's forms layer (floating labels, input groups, validation classes) covers all of these. Forms are the part of a site most often hand-rolled badly, and Bootstrap's defaults are competent.

### Reader familiarity reduces friction

Most developers visiting puck.uno have used a Bootstrap site before. Conventions like `.btn`, `.alert`, dropdown chevrons, and the navbar hamburger are recognized on sight. For a docs site whose job is *not* to be a memorable visual experience, blending in is a feature.

### Render-path neutral

Bootstrap is HTML/CSS/JS at runtime. Orlando emits HTML today; Gitter will emit the same HTML tomorrow. The framework choice does not couple to the render pipeline — switching from Orlando to Gitter does not touch the framework layer. This is the key compatibility property: any framework that's "just CSS and JS on the rendered page" qualifies; Bootstrap happens to be the most furnished one in that category.

### Tree-shaking and per-component Sass are real

The full CDN bundle is heavy (see the corresponding con) but Bootstrap is genuinely modular. If only the grid, type, navbar, and card are used, a Sass build can drop everything else. The "Bootstrap is huge" objection has a real escape hatch as long as the team is willing to set up a build.

## Cons for puck.uno

~~~json
{"vibecode": {
	"section": "cons",
	"role": "case against adopting Bootstrap, scoped to this site",
	"each_con_gets_its_own_heading": true
}}
~~~

### Visual identity is recognizable and generic

A site styled with stock Bootstrap looks like a Bootstrap site — the navbar shape, the blue primary, the button rounding, the card chrome. For a project whose pitch is *designed from scratch, opinionated, distinct*, that visual signal works against the message. Theming via CSS variables and Sass overrides mitigates this, but a Bootstrap site that has been re-themed enough to escape the look-and-feel has also re-litigated most of Bootstrap's design decisions — at which point the framework's main benefit (don't design anything) has been spent.

### Bundle weight is large for a primarily-text site

The full CDN payload (CSS plus the JS bundle that includes Popper) is on the order of 240KB+ uncompressed CSS and 80KB+ uncompressed JS — much smaller after gzip, but still substantial for a docs site whose actual content is markdown and code. A Sass build trims this, but that means standing up a build pipeline that the rest of the site has so far been free of. (Orlando is a Lua HTTP server reading local files; Gitter pulls from GitHub. Neither is a webpack environment.)

### Opinionated defaults conflict with project conventions

Bootstrap chooses for you in places where the project already has its own answer. The default sans-serif stack, the default heading scale, the `border-radius`, the primary blue, the spacing rhythm — all baked in. Most of these are overrideable via Sass variables, but every override is paid work, and the docs site has not yet decided what its actual look is. Adopting Bootstrap means either (a) accepting its defaults as the project's identity by inertia, or (b) overriding enough of them that the framework is doing little more than the grid.

### JS components are overkill for a primarily-text site

The site's interactive surface is small: the sidebar collapse on mobile, the "open issue" panel, the per-section quick-add form. Most of Bootstrap's JS — carousels, offcanvas, scrollspy, toasts, modals, tooltips, popovers — will never run on a typical page. The bundle ships it anyway unless a build strips it.

### Integration with Orlando and Gitter is "drop in CSS" only

Both Orlando today and Gitter at V1 emit HTML from markdown. Neither has a templating layer that "knows about" Bootstrap class names. Using Bootstrap well means either:

- Hand-classing every element in the markdown renderer (Orlando/Gitter learns to emit `class="table table-striped"` on tables, `class="alert alert-info"` on callouts, etc.) — a feature both renderers don't have and would need to grow, with the markdown source picking up Bootstrap-flavored attribute syntax.
- Or relying on Bootstrap's bare-element styles (`reboot`, the typography layer) and ignoring its components. In which case most of what Bootstrap offers goes unused.

There's no good middle path. The richer the Bootstrap usage, the deeper the renderer has to know about it.

### Sass build introduces a step the project doesn't otherwise have

Orlando is Lua, Gitter is Charlie. There is no Node, no webpack, no bundler in the picture. The Bootstrap "use it like an adult" workflow (per-component Sass imports, custom theme, tree-shaken JS) needs that toolchain. Adopting Bootstrap honestly probably means adopting a build step honestly, which is its own architectural decision worth surfacing.

### Bootstrap's "no nanny" status is mixed

Bootstrap is opinionated in the *design* sense (it picks a look) but mostly hands-off in the *behavior* sense (you can override anything with utility classes or your own CSS). It is not actively paternalistic in the project's "no nanny code" sense, but the *gravity* of its defaults — the path of least resistance leads to a Bootstrap-shaped site — is its own subtle version of constraint. Worth noting; not disqualifying.

## Notable alternatives

~~~json
{"vibecode": {
	"section": "alternatives",
	"role": "place Bootstrap on a spectrum so the comparison is concrete",
	"alternatives_listed": ["jqmin", "custom_css", "no_framework"]
}}
~~~

### jqmin

[jqmin](https://puck.uno/documentation/site/frameworks/jqmin/) is Miko's in-house jQuery + CSS utility library — small, opinionated, behavior-focused (radio toggles, auto-submit forms, hide-on-submit, custom checkboxes, sticky headers, CSS-only tabs). Its scope is dramatically narrower than Bootstrap's: it does not provide a grid, a component vocabulary, or a visual identity. It is closer to "useful behaviors that vanilla HTML doesn't have" than to a framework. Pros: tiny, no design-identity baggage, already understood by the author. Cons: depends on jQuery, doesn't solve the layout-and-component problem at all — picking jqmin still leaves the question "and what gives the site its visual structure?" open.

### Custom CSS

Hand-written CSS targeted at the actual page shapes the site needs. Pros: zero bundle weight beyond what's used, total identity control, no framework tax. Cons: actual work — typography, spacing rhythm, color system, form styles, responsive breakpoints, dark mode, all have to be designed and maintained. The cost is paid in design hours, not download bytes.

### No framework

Bare browser defaults plus the minimum CSS to make markdown readable. Pros: trivially small, no maintenance, no decisions. Cons: the site looks like a `README.md` rendered by a 1996 browser. Defensible for very small sites; probably not the puck.uno destination.

## Recommendation

~~~json
{"vibecode": {
	"section": "recommendation",
	"role": "reasoned position with conditions, not equivocation",
	"summary": "lean against Bootstrap as primary framework; consider its reboot/typography layer in isolation"
}}
~~~

**Lean against Bootstrap as the primary client-side framework.** The reasoning, in order of weight:

1. **Identity mismatch.** The Puck pitch is "designed from scratch, opinionated, distinct." A stock-Bootstrap site reads as "generic Bootstrap site." Re-theming Bootstrap heavily enough to escape that look is comparable in cost to writing the targeted CSS in the first place, and the result is harder to understand because the Bootstrap layer is in the way.

2. **Component overhead the site does not need.** The puck.uno page shape is *one* layout (sidebar + content + optional rail), a handful of inline components (vibecode block, open-issue panel, code fence chrome, TOC), and one collapsible nav for mobile. That is a small enough surface that the framework's main asset — its component library — sits unused. Most of what Bootstrap brings would be dead weight on the page.

3. **Renderer impedance.** Neither Orlando nor Gitter has a template layer that knows Bootstrap class vocabulary. Getting Bootstrap to do useful work in the rendered page means either growing that layer in two renderers or restricting Bootstrap to its `reboot` / typography styles. The first is real engineering work for a marginal payoff; the second leaves Bootstrap underused.

**Conditions under which Bootstrap wins.** If the site grows substantial interactive surface — a real account/settings area, multi-step forms, dashboards over Mikobase contents, an admin panel for moderation — and that surface materially benefits from a furnished component library, Bootstrap becomes the pragmatic choice. The decision point is the moment a page needs three or more of {modal, dropdown, complex form, tabs, accordion, toasts} simultaneously. The current docs site is far from that.

**Suggested actual path.** Start with custom CSS scoped to the page shapes the site actually has, and pull in jqmin (or its successor) for the small set of JS behaviors that vanilla HTML lacks. Treat Bootstrap as a fallback to revisit if the interactive surface grows past the point where bespoke CSS is still cheaper than adopting a furnished framework. The decision is reversible — adopting Bootstrap later is easier than removing it after the fact.