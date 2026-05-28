# Peaseblossom

~~~json
{"vibecode": {
	"doc": "site-frameworks-peaseblossom",
	"role": "Peaseblossom is the client-side library for puck.uno — site-specific CSS, JavaScript, and HTML patterns used by the site itself, not published as a general-purpose library",
	"status": "early — content lands as concrete tools get specced",
	"parent": "../frameworks.md",
	"sibling": "../jqmin/index.md",
	"name_origin": "Shakespeare fairy from A Midsummer Night's Dream; fits the project's name tradition (Puck, Mikobase) — code name, may change"
}}
~~~

**Peaseblossom is the client-side library for puck.uno.** Site-specific CSS, JavaScript, and HTML patterns the site itself uses — distinct from the general-purpose patterns in [jqmin/](../jqmin/index.md) that the world could use. Things land in Peaseblossom because they only make sense in the context of *this* site; things land in jqmin because they could plausibly be useful to someone building a different site.

## How Peaseblossom and jqmin divide

The split is judgment-based:

### Generally useful → jqmin

If a small client-side helper or pattern could plausibly be useful to someone building a site that isn't puck.uno, it belongs in [jqmin/](../jqmin/index.md). Examples in jqmin today: toggleable radios, auto-submit forms, custom checkboxes, CSS-only tab activators. None of these are tied to anything specific about puck.uno.

### Site-specific → Peaseblossom

If a helper or pattern only makes sense in the context of *this* site — the open-issues panel, the per-section quick-add panels, vibecode-block rendering, the specific sidebar nav shape — it belongs here. Site identity, site conventions, and site-specific affordances live in Peaseblossom.

### Promotion path

A piece that starts in Peaseblossom can graduate to jqmin if it turns out to have broader applicability. There's no rule that triggers the move; it's a judgment call made when the broader fit becomes obvious. The reverse migration (jqmin → Peaseblossom) is unusual but not forbidden.

### Layering

Peaseblossom can depend on jqmin. The reverse is not allowed — jqmin is the more publishable surface and shouldn't reach for site-specific behavior.

## Files

[peaseblossom.css](peaseblossom.css) holds the stylesheet, [peaseblossom.js](peaseblossom.js) the script, [peaseblossom.html](peaseblossom.html) demonstrates each declared style and pattern in isolation.

## Contents

Specific styles and patterns live in the [peaseblossom.css](peaseblossom.css) and [peaseblossom.js](peaseblossom.js) sources; the demonstration page is [peaseblossom.html](peaseblossom.html).

### `table.std`

A simple, clean table style. Apply to `<table class="table std">`. Renders `<thead>` and every `<th>` in gray; every cell carries a solid 1px black border. Defined in `peaseblossom.css`; demonstrated in `peaseblossom.html`.
