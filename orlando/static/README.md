# Static assets

This directory holds the static assets served by Orlando under the
`/static/` URL prefix.

- `/static/foo.css` → `orlando/static/foo.css`
- `/static/logo.svg` → `orlando/static/logo.svg`
- `/static/anything` → `orlando/static/anything`

These are files Orlando serves verbatim (no rendering): CSS, JavaScript,
images, icons, fonts, etc. Content-Type is chosen by extension via
[`orlando.content_type`](../lua/orlando/content_type.lua).

This is the only static root Orlando knows about. Other directories
are not exposed as static mounts; if a file needs to be servable, it
lives here.
