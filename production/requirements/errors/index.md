# Errors

~~~vibecode
{"vibecode": {
	"doc": "requirements_errors_index",
	"role": "spec for Caspian's error-URL system. Every error the core engine raises carries a URL to a documentation page describing what the error means, common causes, and how to fix. The URL follows the puck.uno/errors/<slug> pattern. This page defines the contract (every core error MUST have a doc page), the URL format, the error-message shape, and the per-error page template. Individual error pages live as siblings under requirements/errors/ — one file per error, serving both the spec audience (engine implementers) and the developer audience (people hitting the error).",
	"status": "V1 objective — mechanism and contract settled; catalog of specific errors is populated as engine surfaces earn their errors",
	"audience": "engine implementers writing error-raising code; developers hitting Caspian errors; documentation authors writing per-error pages"
}}
~~~

Every error the core Caspian engine raises carries a **URL** to a documentation page describing what the error means, common causes, and how to fix. The URL appears in the error message; the page it points at exists in the repo under `requirements/errors/<slug>.md`.

The goal: **the moment a developer hits an unfamiliar error is exactly the moment they need help.** A URL right in the error message means one click away from complete context — instead of guessing at what "invalid receiver in dispatch" means, or searching for documentation that might or might not exist.

Well-precedented across the language ecosystem:

- **Rust** — E0001-style codes with dedicated docs pages.
- **TypeScript** — TS2304-style codes; IDE tooltips link to the docs page.
- **Elm** — famously friendly error messages, each with a URL to the compiler's docs.
- **Deno** — every runtime error links to a page on deno.com.
- **ESLint** — every rule violation links to the rule's docs page.

Caspian is doing the same thing, with the URL scheme aligned to `puck.uno`.

## URL format

Every error's URL follows the pattern:

~~~
https://puck.uno/errors/<slug>
~~~

Where `<slug>` is a short kebab-case identifier for the error. Examples:

- `https://puck.uno/errors/undefined-variable`
- `https://puck.uno/errors/capability-not-granted`
- `https://puck.uno/errors/unknown-global`
- `https://puck.uno/errors/private-method-access`

Slugs are chosen for readability. No numeric codes — the slug IS the identifier. Once assigned, a slug is stable forever; renames leave a redirect so old error messages in the wild still resolve.

## Error message shape

An error message includes:

1. **A human-readable summary** of what went wrong — the sentence a developer reads first.
2. **Source location** — file and line (already carried by every Caspian error via the `src` mechanism).
3. **The URL** on its own line at the end.

Example:

~~~
error: capability %stdout not granted in this frame
  at foo.casp line 42
  role: library-x
  see: https://puck.uno/errors/capability-not-granted
~~~

The URL is always the last line of the message. Developers, IDE plugins, and terminal emulators can rely on this position to extract the link cleanly. Copy-paste, click through in a URL-aware terminal, or use as a search term — all work.

## Per-error page template

Every error page lives at `requirements/errors/<slug>.md` and follows this shape:

~~~markdown
# <Error Name>

<vibecode block>

<one-paragraph summary of what the error means>

## When it raises

<precise conditions — the spec audience>

## Common causes

<the ways developers actually hit this — the developer audience>

## How to fix

<concrete actions — code examples where they help>

## Related

<links to relevant spec pages>
~~~

The page serves two audiences in one file:

- **Engine implementers** read the "When it raises" section as the authoritative spec of the raise condition.
- **Developers hitting the error** read the "Common causes" and "How to fix" sections as user-facing help.

Keeping both in one file means the two never drift out of sync — the spec IS the help, from a different angle.

## The contract

**No engine-emitted error may ship without its documentation page existing.**

Enforced in engine-code review: any commit that introduces a new error also introduces its page under `requirements/errors/<slug>.md`. Lint enforcement is a natural V1.x addition (walk the engine source for error-emission sites; check every URL resolves to an existing page in the repo).

Consequences:

- Every core error is discoverable — walk `requirements/errors/` to see every error the engine can produce.
- Documentation quality can't lag implementation, because the two are the same file.
- New engine features that raise new errors force the author to think through the developer experience at implementation time.

## Scope: core errors only

The contract applies to errors the **core Caspian engine** raises. User-defined errors (from application code, from downloaded libraries, from user-written classes) are the author's responsibility — if they want URLs on their errors, they carry them.

Errors from `%engine.*` surfaces, from language primitives (`dispatch`, `scope`, `assignment`, `type check`), from capability access (`.grant` failures, ungranted-capability access), from `%fetch` (network failures, URL resolution failures, top-level exceptions), from role transitions — all core; all must have doc pages.

Errors from `%('caspian.uno/somelib').do_a_thing()` that come from the library's own logic — not core; not covered by this contract.

## Rendering

The doc-server routing already supports `puck.uno/errors/<slug>` — Orlando serves any markdown under `requirements/` at the corresponding URL. No new routing needed.

For error pages, the standard doc chrome (nav sidebar, tags, edit form) applies. Discovery via the doc site's search picks up error pages the same way it picks up any other content — searching "capability not granted" surfaces the relevant page.

## Testing

- **Every core error's message ends with a URL line** — the URL is on its own line, starts with `see:`, and follows the pattern `https://puck.uno/errors/<slug>`.
- **Every referenced slug has a page** — walking every engine error-emission site and pulling every URL, every one must resolve to an existing `requirements/errors/<slug>.md` file.
- **Slug stability** — a slug assigned in one release does not change in a later release; renames leave a redirect so old error messages in the wild still resolve.
- **URL is always the last line** — no error message appends more text after the URL; parsers can rely on the position.
- **Human-readable summary comes first** — the first line is the summary, not the URL; developers who don't need the URL see meaningful text immediately.
- **Source location is included** — the error carries file / line via the standard `src` mechanism, alongside the URL.
