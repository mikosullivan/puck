# Frameworks

~~~json
{"vibecode": {
	"doc": "site-frameworks",
	"role": "landing page for the web frameworks the puck.uno site uses or is considering",
	"status": "survey populated; no commitments yet",
	"parent": "../site.md"
}}
~~~

Web frameworks the puck.uno site uses, considers, or has chosen to avoid. Decisions about *how the site is built* — UI patterns, styling baseline, client-side helpers — live here. Decisions about *what the site shows* live in the broader `documentation/` tree.

Nothing here is committed yet. The site renders fine with Orlando's plain HTML today; framework choices come in as the surface grows beyond static docs.

## Selection preference

~~~json
{"vibecode": {
	"section": "selection_preference",
	"role": "state the criteria the survey is filtered against, so the verdicts are legible",
	"preference": "HTML-class-driven, includes JavaScript out of the box, declarative not imperative",
	"disqualifies": ["component-code frameworks (React, Vue, Svelte)"],
	"partial_match": ["CSS-only frameworks with no JS"]
}}
~~~

The preference: a framework where adding element classes (or attributes) does the work, with JavaScript behavior bundled in. The site team should not be writing custom JavaScript except for very specific needs.

That filter rules out the component-code frameworks — React, Vue, Svelte, Solid, and the rest. Each requires writing components in their own dialect; the markup of the page is no longer the source of truth. Those frameworks are not surveyed here.

It also flags CSS-only frameworks (Bulma, Tailwind by itself, Pico) as **partial matches**: they style what you class but ship nothing to handle dropdowns, modals, tabs, or any other JS-driven behavior. Each entry below calls out where it sits on this spectrum.

The render-path neutrality requirement carries forward from the Bootstrap report: Orlando today and Gitter tomorrow both emit plain HTML, so the framework must work as `<link>` and `<script>` tags on a finished page, with no build step assumed.

## Candidates

~~~json
{"vibecode": {
	"section": "candidates",
	"role": "one heading per framework so each can be commented on independently",
	"ordering": "rough fit-to-preference, strongest matches first within each grouping"
}}
~~~

### Bootstrap

[Bootstrap](https://getbootstrap.com/) is the long-running HTML/CSS/JS toolkit from the original Twitter team; current stable is 5.3.8. It is the canonical "add a class, get behavior" framework — `.btn`, `.alert`, `.navbar`, `.modal`, `.dropdown` all wire themselves up once the bundle script is on the page, with no per-component initialization. jQuery was dropped at v5; the remaining runtime dependency is Popper.js for floating UI, bundled into `bootstrap.bundle.min.js`.

Bootstrap fits the preference squarely. The tradeoff is identity and weight: a stock-Bootstrap site reads as a stock-Bootstrap site, and the bundle is on the heavy side for a docs site whose content is mostly markdown. The full report — pros, cons, and a recommendation — is at [bootstrap.md](https://puck.uno/documentation/site/frameworks/bootstrap).

### Foundation

[Foundation](https://get.foundation/) is Bootstrap's longtime competitor, originally from ZURB and now community-maintained since 2019. Current release is in the 6.7.x / 6.9.x line. It offers a similar surface — responsive grid, typography reset, components (top-bar, callouts, reveal modal, accordions, tabs, dropdowns, off-canvas) — with a heavier emphasis on accessibility and email-template variants. JavaScript behavior is attribute-driven (`data-toggle`, `data-open`, etc.) and ships in the bundle.

Fits the preference. The risk is the maintenance signal: development is volunteer-driven and slower than Bootstrap's; the project is alive but not vibrant. For a site whose framework choice should age well, Foundation in 2026 is harder to recommend than it was a decade ago.

### UIkit

[UIkit](https://getuikit.com/) is YOOtheme's open-source front-end framework; current release is 3.24. Of all the candidates it is the most aggressively attribute-driven — components are activated by `uk-*` attributes (`uk-grid`, `uk-navbar`, `uk-modal`, `uk-toggle`) rather than class-based init, and the JS observes the DOM and wires behavior automatically. The component vocabulary is broad: navbar, off-canvas, modal, accordion, tab, slider, sortable, parallax, scrollspy, lightbox.

UIkit is the strongest mechanical match for the preference — markup-driven, no per-page JS, behavior follows the attributes. It is actively maintained because YOOtheme uses it as the foundation of its commercial page builder. Tradeoff: smaller community than Bootstrap, less stack-overflow gravity, and the visual identity is more distinctive (and harder to de-brand) than Bootstrap's.

### Bulma

[Bulma](https://bulma.io/) is a Flexbox-based CSS framework by Jeremy Thomas; v1.0 was a Dart Sass rewrite and the project ships a single `bulma.css` file. The class vocabulary is pleasant — `.button is-primary`, `.notification is-warning`, `.columns` / `.column is-half` — and the visual defaults are cleaner than Bootstrap's out of the box.

**Partial match.** Bulma deliberately ships no JavaScript. Modals, tabs, navbar burger, dropdowns — every interactive component documents the markup but leaves the wiring to the user. For a "no custom JS" preference this is disqualifying as a standalone choice; Bulma only works in this slot if paired with a separate behavior layer (Alpine.js or similar). It is a strong CSS layer with a JS-shaped hole.

### Tailwind CSS

[Tailwind CSS](https://tailwindcss.com/) is the utility-first framework from Tailwind Labs; current release is in the v4.2 / v4.3 line. v4 moved to CSS-first configuration (`@theme` directive) and a Rust-backed engine. The vocabulary is atomic — `flex pt-4 text-center rotate-90` composed in markup — rather than componentized.

**Partial match, and a philosophical mismatch.** Tailwind ships no JavaScript at all, and the utility-first model is the opposite of "add a class to a navbar and get a navbar" — you compose every element from scratch out of primitives. Adopting Tailwind for puck.uno would mean either writing the JS behavior layer separately *and* designing the components from primitives every time, or pulling in a component layer on top. The two prominent component layers are [DaisyUI](https://daisyui.com/) (semantic class names like `.btn`, `.card`, `.modal` on top of Tailwind; v5 is the current release, framework-agnostic, still ships no JS for behaviors that need it) and [Flowbite](https://flowbite.com/) (400+ components, vanilla-JS behavior layer plus React/Vue/Svelte wrappers). Flowbite is the closest a Tailwind-stack solution gets to the preference; DaisyUI restores the class vocabulary but not the JS.

### Materialize

[Materialize](https://materializecss.com/) is a CSS framework implementing Google's Material Design as HTML classes. The original `Dogfalo/materialize` repo went dormant; a community fork at `@materializecss/materialize` is the active line, with v2.3.x as the current release. Components — navbar, sidenav, modal, dropdown, tabs, parallax, toasts, datepicker — are class-driven and the bundled JS auto-initializes most of them.

Fits the preference mechanically. Two concerns: the visual identity is *very* Material (Roboto, ink ripples, FAB shapes), which is recognizable in a way that may or may not be wanted; and Google's own [Material Design Lite](https://getmdl.io/) is officially discontinued, so the Material-class-framework lineage rests entirely on the community-maintained Materialize fork. Lower bus-factor than Bootstrap or UIkit.

### Fomantic UI

[Fomantic UI](https://fomantic-ui.com/) is the community fork of Semantic UI, which itself stalled around 2018. Current release is 2.9.4; v3 is in long-running development. Its pitch is class names that read like English sentences — `<div class="ui primary button">`, `<div class="ui three column grid">`, `<div class="ui labeled icon menu">`. Components are class-driven and JS-backed (modal, dropdown, popup, sticky, accordion, tab, sidebar, calendar).

Fits the preference, with a footnote on momentum. Fomantic is alive — the repo saw commits this month — but the v3 effort has been "soon" for years and the npm release cadence has slowed. The class-as-English-sentence vocabulary is the most distinctive selling point and the most divisive: it is either delightful or verbose depending on the reader.

### Alpine.js

[Alpine.js](https://alpinejs.dev/) is Caleb Porzio's declarative JS layer — 7.1 KB, no build step, single script tag. Behavior is attached via `x-data`, `x-on:click`, `x-show`, `x-if`, `x-model`, `x-for` directly on elements. It is "jQuery for the modern web" in the project's own framing: a small reactive primitive that lives in HTML attributes.

Alpine is not a CSS framework — it ships no styling at all — so it does not stand alone as the site's framework choice. It does fit the preference exactly in spirit: behavior expressed in markup, no separate JS file to maintain. The natural use is to pair it with a CSS-only layer (Bulma, Tailwind, Pico) and let Alpine cover the modal / dropdown / collapse interactions that the CSS layer leaves open. Worth considering as the JS half of a two-piece stack.

### HTMX

[HTMX](https://htmx.org/) is the hypermedia framework from Big Sky Software; current stable is 2.0.x. Interactivity is declared via `hx-get`, `hx-post`, `hx-target`, `hx-swap`, `hx-trigger` attributes — clicking a button can fire a request, drop the HTML response into a target element, and run a CSS transition, all without a line of custom JavaScript. The paradigm is server-driven: the server returns HTML fragments, HTMX swaps them into the page.

**Different paradigm.** HTMX is not a styling framework and not a client-side state framework; it is a way to make a server-rendered site interactive without leaving HTML. For puck.uno specifically the fit is partial: the site is mostly static markdown today, and HTMX shines when there's a server willing to return HTML fragments (search results, expanded panels, inline edits). Worth keeping on the radar for the moment Orlando or Gitter starts serving dynamic affordances — quick-add issue forms, per-section comment threads, search-as-you-type — but it does not solve the layout-and-component problem on its own.

### Pico CSS

[Pico CSS](https://picocss.com/) is a minimalist classless-first framework — under 10 classes in the whole library — that styles semantic HTML elements directly. `<button>` looks like a button without a class; `<article>` becomes a card; `<nav>` styles inline. A small set of opt-in classes (`.container`, `.grid`, `.outline`) handles the rare case where semantics aren't enough.

**Partial match, but worth noting.** Pico ships no JavaScript and has no component vocabulary beyond what HTML5 already provides. For a docs-heavy site whose markdown renderer emits semantic HTML, Pico might be the *least-work* baseline: drop in one stylesheet and the page already looks coherent. It does not replace a component framework — it replaces "we haven't styled anything yet." Reasonable as a starting layer that a fuller framework could supersede later, or as the answer if the site stays primarily-text indefinitely.

### Web Awesome (formerly Shoelace)

[Web Awesome](https://webawesome.com/) is the rebrand of Shoelace, the framework-agnostic web-components library from Cory LaViska; v3 is the Web Awesome release following a successful 2024 Kickstarter ($737K). Components are real custom elements — `<wa-button>`, `<wa-dialog>`, `<wa-tab-group>` — that work in any framework or none. Behavior is built into the components; styling is exposed via CSS custom properties and `::part` selectors.

A different shape of "add a tag, get behavior" — the markup is custom elements rather than classes, but the no-custom-JS property holds. Tradeoff: custom elements have real (if minor) browser-compat and SEO considerations; the library is younger and smaller than Bootstrap or UIkit; and Web Awesome's commercial/Pro split is still settling. Worth a look as a forward-leaning option, especially as the web-components ecosystem matures.

## Recommendation

~~~json
{"vibecode": {
	"section": "recommendation",
	"role": "narrow the field to 2-3 candidates worth a deeper bake-off, not pick a winner",
	"strongest_matches": ["UIkit", "Bootstrap", "Bulma + Alpine.js"],
	"deeper_report_exists": ["bootstrap"]
}}
~~~

Two to three candidates earn a deeper bake-off, following the Bootstrap report's shape.

### UIkit

The strongest mechanical match for "add classes/attributes, get behavior." Attribute-driven activation means the markup *is* the configuration, with no per-page JS to wire up. The component vocabulary covers the site's needs and more. Worth its own report — particularly to evaluate how the visual identity reads next to Puck's "designed from scratch" pitch, and how the Pro/commercial side affects the open-source roadmap.

### Bootstrap

Already reported on at [bootstrap.md](https://puck.uno/documentation/site/frameworks/bootstrap). That report leans against; it stays on this shortlist because it is the safest bet on community gravity, reader familiarity, and longevity.

### Bulma plus Alpine.js (two-piece stack)

The deliberate-composition option: Bulma supplies a clean, restrained CSS layer with a friendly class vocabulary, and Alpine.js handles the small set of interactive needs (sidenav collapse, modal, dropdown, copy-to-clipboard) with attribute-driven directives. Total surface stays small, no build step is required, and each half can be swapped independently if it stops fitting. Tradeoff: two libraries to track instead of one, and the team owns the integration points.

### Worth watching, not yet shortlisted

Web Awesome is the most interesting longer-shot candidate — if the web-components approach matures into the obvious default, the calculus changes. Pico is a credible *baseline* if the site decides it wants to stay primarily-text. HTMX moves onto the shortlist the moment Orlando or Gitter grows a "return HTML fragments" affordance.