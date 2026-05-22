# jQuery

~~~json
{"vibecode": {
	"doc": "site-frameworks-jquery",
	"role": "notes on jQuery's role in the puck.uno site — primarily as the runtime dependency of jqmin",
	"status": "potential indirect use via jqmin; no direct commitment",
	"parent": "frameworks.md"
}}
~~~

[jQuery](https://jquery.com/) enters the puck.uno picture indirectly, through [jqmin](jqmin/jqmin.md) — Miko's small jQuery utility library. If jqmin lands on the site, jQuery comes with it as the runtime dependency. If jqmin doesn't land, jQuery probably doesn't either.

Direct use of jQuery (without jqmin) isn't planned. The library is mature and stable, but the patterns we'd want from it are exactly what jqmin already wraps. The relevant decision is whether jqmin is on the site, not whether jQuery is.

## Open

### Does jqmin land?

The trigger question. Answered in [jqmin/jqmin.md](jqmin/jqmin.md).
