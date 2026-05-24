# jqmin

~~~json
{"vibecode": {
	"doc": "jqmin",
	"status": "brainstorm — port / adapt Miko's existing jqmin utility library into the Puck ecosystem",
	"upstream": "https://www.unotate.com/static-case/jqmin/version-2/dev/jqmin.js and jqmin.css",
	"role": "lightweight UI augmentation toolkit: small set of form-control and interaction patterns that don't warrant a full framework"
}}
~~~

Brainstorm landing page for bringing **jqmin** — Miko's existing small jQuery / CSS utility library at [unotate.com](https://www.unotate.com/static-case/jqmin/version-2/dev/) — into the Puck ecosystem.

## What jqmin is today

A small, opinionated jQuery + CSS utility library. The "min" suggests minimal. It's a personal toolkit of common UI augmentations that don't warrant a full framework — drop the script and stylesheet into any page and get a handful of useful patterns for free.

### JavaScript surface (jqmin.js)

#### `.can-uncheck`

Radio buttons that toggle on/off. Click an already-selected radio to deselect it (a behavior native HTML radios don't offer).

#### `.submit-on-set`

Controls that auto-submit their form when changed. Typical for filter dropdowns and "instant-apply" preference controls.

#### `.hide-on-submit`

Forms that hide themselves after submission. Useful for inline edit forms that should disappear once the user commits a change.

#### `.popup`

Links that open in a popup window instead of the same tab.

#### `[data-shadow]`

Controls that mirror another control's state without direct coupling. Set `data-shadow="other-id"` and this control's checked / value state follows the source's.

#### `[data-self-set]`

Images that swap their `src` on click — handy for toggle-style image buttons or expand-collapse indicators.

#### `submit_on_set(field)`

Public function. Triggers a form submission for the given field, equivalent to the `.submit-on-set` selector but callable from arbitrary code.

#### `set_shadows(src)`

Public function. Synchronizes any `[data-shadow]` controls pointing at the given source. Useful when source state changes outside the normal event path.

#### Outside-events plugin

Bundles Ben Alman's "outside events" plugin so other code can detect clicks and keydowns outside a given element (the building block for click-away dismissal, popover collapse, etc.).

### CSS surface (jqmin.css)

#### `.stickies`

Sticky header positioning — page headers that persist at the top of the viewport during scroll.

#### `.custom-checkbox`

Hidden native checkbox paired with custom visible display. Lets you style a check control however you want while preserving form submission semantics.

#### `.highlighting-checkbox`

Hidden checkbox input variant used as a state machine for CSS-driven highlighting effects.

#### `.tab-activator` / `.reverse-tab-activator`

CSS-only tab switching driven by hidden radio buttons. Switch tabs by clicking labels that toggle the underlying radios; the visible panel follows. No JavaScript required.

#### `.circle`

Quick circular shape via `border-radius`. One-liner for round avatars, dots, badges, etc.

#### `.noprint` / `.printonly`

Print-media visibility toggles. `.noprint` hides on paper; `.printonly` shows only on paper.

#### `.nowrap`

Prevents text wrapping. The usual single-line constraint.

#### `.highlight-next-element`

Yellow background highlight applied to the element following the styled one. Useful for "look here" callouts that don't disturb the highlighted target's own styling.

The CSS leans heavily on the "hidden checkbox / hidden radio" pattern for JavaScript-light interactivity — a classic minimal-JS technique.

## What jqmin in Puck might look like

<a id="policy-default-client-side-framework"></a>
### Policy: default client-side framework until close to launch

**Until V1 launch is near, jqmin is the client-side framework for the
puck.uno site.** Established alternatives (Bootstrap, Tailwind, others)
are not under active evaluation — settling that question is deferred
until closer to launch. This freezes the choice during the period when
the rest of the stack is moving rapidly, so we're not bikeshedding the
client framework while everything else is in flux. The question reopens
deliberately when launch approaches.

What this policy means concretely:

- Every new client-side interaction the site needs goes through jqmin
  (extending jqmin if the pattern isn't there yet)
- HTML class vocabulary for the site grows alongside jqmin's patterns —
  see [the standardization discussion](#standardizing-html-classes-around-jqmin)
  (TBD section)
- No parallel framework experiments; consolidate effort
- Pre-launch, the question "should we use a different framework?" is
  out of scope

### In-house only

jqmin is for the puck.uno site itself — not (yet) documented as a
public ecosystem API, not committed to long-term in its current shape.
Whether jqmin grows into a Puck-ecosystem-published library or stays
purely an internal tool is a post-launch decision.

### Uma integration (tabled)

An intriguing idea: add jqmin-style helpers to Uma so the same patterns
are reachable from Caspian code. Tabled — comes back into scope only if
both jqmin sticks (the policy above keeps it sticking through V1) and
Uma needs the surface.

The drop-in port is the obvious V0 path; the Caspian-native version is
the Puck-ecosystem-coherent endpoint.

## Patterns

~~~json
{"vibecode": {
	"section": "patterns",
	"role": "concrete component / interaction patterns jqmin specifies for puck.uno; the list grows as the site needs each one"
}}
~~~

Concrete patterns jqmin specifies. Each is described in terms of HTML structure, the CSS jqmin provides, and the JavaScript (if any) it adds.

### Dropdown

~~~json
{"vibecode": {
	"section": "dropdown",
	"role": "click-to-expand panel built on <details> / <summary>, with an optional link target plus a chevron toggle; supports unlimited nesting",
	"js_required": "no for click-to-toggle; yes for optional add-ons (outside-click close, single-open siblings, keyboard nav)"
}}
~~~

A click-to-expand panel that can nest. Built on `<details>` / `<summary>` so the toggle is native HTML — no JavaScript needed for open/close. Each level optionally pairs a navigation link with a separate chevron, so the same row can navigate or expand depending on where the user clicks.

#### Simple case

~~~html
<details class="dropdown">
	<summary>
		<a href="/products">Products</a>
		<span class="chevron"></span>
	</summary>

	<a href="/products/widgets">Widgets</a>
	<a href="/products/gadgets">Gadgets</a>
</details>
~~~

#### Nested case

~~~html
<details class="dropdown">
	<summary>
		<a href="/products">Products</a>
		<span class="chevron"></span>
	</summary>

	<a href="/products/widgets">Widgets</a>

	<details class="dropdown">
		<summary>
			<a href="/products/gadgets">Gadgets</a>
			<span class="chevron"></span>
		</summary>

		<a href="/products/gadgets/round">Round gadgets</a>
		<a href="/products/gadgets/square">Square gadgets</a>
	</details>
</details>
~~~

#### Click resolution

Clicking the **link text** navigates. The `<summary>`'s default toggle also fires, but the page is leaving anyway.

Clicking the **chevron** toggles open/close. The chevron is a `<span>` with no `href`, so no navigation happens.

Clicking **empty space in the summary** toggles. Standard `<details>` behavior.

#### CSS

CSS owns the entire visual: chevron rotation on open (`details[open] > summary .chevron { transform: rotate(90deg); }`), indent for nested levels, panel chrome, hover state, focus outline. The toggle state is in the DOM as the `open` attribute on `<details>`, so styling reacts directly without JS pulling strings.

#### JavaScript

Zero JavaScript needed for click-to-toggle. JS only enters for behaviors beyond the native:

##### Close on outside click

Collapse the dropdown when the user clicks anywhere outside it. Triggered by adding `dropdown-outside-close` to the `<details>`.

##### Single-open siblings

At most one sibling dropdown open at a time; opening one closes the others at the same level. Triggered by `dropdown-single-open` on the parent container.

##### Keyboard navigation

Arrow keys move through items; Escape closes the dropdown and returns focus to the summary. Triggered by `dropdown-keyboard` on the `<details>`.

These add-ons are opt-in per dropdown via class names, per jqmin's class-driven model. The base pattern works without any of them.

#### Tradeoff

Clicking the link text always navigates — there's no way to expand the dropdown without leaving the page. "Click anywhere on the row to expand; click only the link text to navigate" requires JS to intercept and selectively prevent default. The simpler tradeoff is the default; the chevron is the expand-only target.

### Custom checkbox

~~~json
{"vibecode": {
	"section": "custom-checkbox",
	"role": "checkbox that swaps between two visible inline elements based on :checked state; hidden native <input> drives, CSS shows whichever sibling matches; zero JavaScript",
	"js_required": false,
	"demo": "jqmin.html",
	"inherited_from": "unotate jqmin.css verbatim"
}}
~~~

A `<label class="custom-checkbox">` wraps a hidden native `<input type="checkbox">` and two visible sibling elements — the **checked-state element first**, the **unchecked-state element second**. CSS shows whichever matches the current state.

#### Markup

```html
<label class="custom-checkbox">
	<input type="checkbox">
	<span>✔</span>
	<span>❌</span>
</label>
```

Either visible sibling can be any inline element — a `<span>` with a glyph (as above), an `<img>`, an SVG, a styled `<span>` with text. The class name doesn't care what the visible elements are; the swap mechanic only depends on sibling position.

Optionally precede the input with a prompt element so the prompt is also a click target:

```html
<label class="custom-checkbox">
	<span class="prompt">Captain on the bridge:</span>
	<input type="checkbox">
	<span>✔</span>
	<span>❌</span>
</label>
```

The prompt can be a bare text node instead of a `<span>` — the `+` combinator ignores text nodes, so positions 1 and 2 are still the spans after the input. Bare text gives no CSS hook for styling the prompt but is one less element:

```html
<label class="custom-checkbox">
	Captain on the bridge.
	<input type="checkbox">
	<span>✔</span>
	<span>❌</span>
</label>
```

#### CSS

```css
.custom-checkbox > input { display: none }
.custom-checkbox > input:not(:checked) + * { display: none }
.custom-checkbox > input:checked + * + * { display: none }
```

Three rules, no custom properties, no `content` tricks, no inline styles. Verbatim from unotate's jqmin.css.

#### How it works

- The native `<input>` carries the real form state. `display: none` hides it; it still submits with the enclosing form.
- When the input is **not** checked, the immediate next sibling (position 1 — the checked-state element) is hidden via `display: none`. The second sibling (the unchecked-state element) stays visible.
- When the input **is** checked, the second sibling (the unchecked-state element) is hidden. The first sibling stays visible.
- Clicking anywhere inside the `<label>` toggles the input (label-to-input association is automatic when the input is nested).

#### Order matters

Position 1 (immediate sibling after `<input>`) = **checked-state** visible element. Position 2 = **unchecked-state** visible element. Reverse the order and the visible state inverts.

#### Demo

[jqmin.html](jqmin.html) shows a basic example and an embedded-prompt variation.

## Open questions

### Does jqmin keep its name in the Puck context?

The name is short and distinctive but jQuery-coupled. If we go jQuery-free or Caspian-native the "jq" prefix becomes misleading. New name worth considering when the port shape is settled.

### Which existing pieces survive into the Puck version?

Some current features may be obsoleted by what Sammy / Uma / Robinson already give us (sticky headers via standard CSS, tab UIs via Uma components, etc.). The survivors are the ones with no equivalent in the Puck web layer.

### Browser-extension version, or page-asset-only?

Some jqmin patterns (popups, outside-event detection) could also live as a browser extension that augments any page, not just Puck-served ones. Out of scope for V1 but worth knowing exists as an option.

## Reference

- Upstream JS: https://www.unotate.com/static-case/jqmin/version-2/dev/jqmin.js
- Upstream CSS: https://www.unotate.com/static-case/jqmin/version-2/dev/jqmin.css
