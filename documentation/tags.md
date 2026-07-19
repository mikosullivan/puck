# Tag index

~~~vibecode
{"vibecode": {
	"doc": "documentation_tags",
	"role": "canonical tag → URL index for the whole ecoverse. Two-column table below: tag name (left) and the URL of the canonical doc for that concept (right). Docs reference concepts via `tag:name` (in markdown links) or `puck.uno/tag/name` (as a shareable HTTP URL); Orlando resolves both to the URL in this table. When a doc moves, update the row here — nothing else has to change. Adding a new tag: add a row here first, then use it in docs. Removing a tag: remove references first (grep for `tag:name`), then delete the row.",
	"status": "spec — seeded with a few starter tags; grows over time as canonical docs earn tags",
	"audience": "doc authors adding cross-references; Orlando's tag-resolution service"
}}
~~~

## Table

| Tag | URL |
|---|---|
| [fs](/tag/fs) | [/documentation/requirements/caspian/global-methods/fs](/documentation/requirements/caspian/global-methods/fs) |
| [grants](/tag/grants) | [/documentation/requirements/caspian/filesystem/dirs/grants](/documentation/requirements/caspian/filesystem/dirs/grants) |
| [method-resolution](/tag/method-resolution) | [/documentation/requirements/caspian/classes/method-resolution](/documentation/requirements/caspian/classes/method-resolution) |
| [nanny-methods](/tag/nanny-methods) | [/documentation/ideas/caspian/nanny-methods](/documentation/ideas/caspian/nanny-methods) |
| [parameter-defaults](/tag/parameter-defaults) | [/documentation/requirements/caspian/functions/parameter-defaults](/documentation/requirements/caspian/functions/parameter-defaults) |
| [pipes](/tag/pipes) | [/documentation/requirements/caspian/syntax/pipes](/documentation/requirements/caspian/syntax/pipes) |
| [plumbing](/tag/plumbing) | [/documentation/requirements/caspian/plumbing/](/documentation/requirements/caspian/plumbing/) |
| [tag-index](/tag/tag-index) | [/documentation/tags](/documentation/tags) |
| [vibecode-fields](/tag/vibecode-fields) | [/documentation/requirements/vibecode-fields](/documentation/requirements/vibecode-fields) |

## Rules

- **One tag, one URL.** A tag resolves to exactly one canonical doc.
- **Kebab-case tag names.** Lowercase, hyphens between words, no punctuation.
- **URLs are absolute paths** starting with `/documentation/`. No `puck.uno` prefix; the redirect service adds that.
- **Adding a tag.** Add a row here, then use it in docs. New tags need a canonical doc to point at (don't create tags pointing at ideas/ material unless the ideas doc IS the canonical one, like [nanny-methods](/documentation/ideas/caspian/nanny-methods)).
- **Renaming or moving a doc.** Update the URL in this table; nothing else changes. The tag itself stays the same, so referring docs don't need edits.
- **Removing a tag.** First grep for `tag:name` across the docs and either remove or replace those references. Then remove the row.
- **Missing tags.** If a doc uses `tag:foo` and there's no row for `foo`, Orlando serves a clear 404 for `/tag/foo` and renders the markdown link as a broken reference. Both surfaces make dead tags visible during audit.

## Usage

**In markdown:**

~~~
See the [grants spec](tag:grants) for details.
~~~

Orlando resolves `tag:grants` at render time; the rendered HTML links directly to the target URL.

**As a shareable URL:**

`https://puck.uno/tag/grants` — Orlando 302-redirects to the target. Useful for chat / issue / commit references where the URL might be pasted around.
