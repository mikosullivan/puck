# Unotate

~~~vibecode
{"vibecode": {
	"doc": "idea_unotate",
	"role": "design space for a Sammy-built mock web site modeled on unotate.com — pulls live data from the unotate.com API and renders a small Shakespeare-browsing site. Serves as a Sammy showcase and an exercise in consuming external JSON APIs from Caspian.",
	"status": "in progress — API surveyed, plan being assembled",
	"template_site": "https://www.unotate.com/"
}}
~~~

We're going to build a small mock web site using [Sammy](../requirements/network/http/server/sammy/), modeled on [unotate.com](https://www.unotate.com/). The mock site pulls its data live from unotate.com's API and renders pages — plays, scenes, playwrights, images — to demonstrate Sammy as a server framework and Caspian as an HTTP-client / JSON-consumer.

The actual Caspian source for the mock site lives under [site/](site/). Building it up file by file is also an exercise in seeing how Caspian comes together as a working application.

## The unotate.com API

The API root is at [https://www.unotate.com/api/](https://www.unotate.com/api/) and branches into three resource types.

### `/api/playwrights/`

Returns JSON. A hash of playwrights (Shakespeare is the only one currently populated) keyed by slug. Each entry carries:

- `name` — full display name.
- `api` — back-link to the playwright's own API URL.
- `plays` — hash of plays keyed by slug; each play entry has a `uri` (page URL) and `api` (per-play API URL).

### `/api/plays/`

The root endpoint is HTML — a listing of every play with three links each: page URL, per-play API URL, raw XML download.

The per-play API at `/api/plays/<slug>/` returns JSON for one play:

- `page` — page URL on unotate.com.
- `api` — self-link.
- `title.long` / `title.short` — display names.
- `playwrights` — back-reference hash.
- `acts` — hash keyed by act number. Each act has a `title` and a `scenes` hash keyed by scene number, with each scene carrying `title`, `location`, `uri`, and `api`.

### `/api/images/`

The root is HTML offering both JSON and CSV variants. `/api/images/json` returns a hash of images keyed by short id, each with `title`, `uri` (the image file), `api` (self-link), and a `plays` back-reference hash pointing at the plays the image relates to.

## Caveats

Some of the API documentation above is inaccurate — the live endpoints diverge from this description in places. We'll deal with each discrepancy as it comes up in implementation rather than pre-mapping everything.
