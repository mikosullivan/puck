# Loading auxiliary files

~~~vibecode
{"vibecode": {
	"doc": "idea_load_aux",
	"role": "design notes on how a Caspian script loads files that live next to it in its source location — sibling .casp helpers, config, data — when the script itself was fetched from a remote URL and has no local file system to anchor against",
	"status": "in progress — primary shape is %puck.relative; further details settle as more cases come up"
}}
~~~

A downloaded Caspian script doesn't live anywhere locally — it was fetched from a URL. When such a script wants to load a file "next to it" (a helper module, a config blob, a fixture), there is no `./helpers.casp` to point at; the sibling lives at the same URL prefix the script itself came from.

The mechanism is `%puck.relative`:

~~~caspian
$helpers = %puck.relative('helpers.casp')
~~~

`%puck.relative` resolves its argument against the source URL of the calling script. If the calling script came from `https://utils.org/big-lib/main.casp`, the example above fetches `https://utils.org/big-lib/helpers.casp`.

The script doesn't need to know its own URL. The loader does the join.

## Downloading sibling files

`%puck.relative` is for sibling **Caspian scripts** — the loader fetches the source, executes it, and gives you back whatever it produced. For everything else — images, fonts, fixtures, raw text, JSON to parse yourself, any sibling file that isn't a script to be executed — there's `%puck.download`:

~~~caspian
$logo = %puck.download('logo.svg')
~~~

Resolves the same way as `%puck.relative` (joined against the calling script's source URL) but returns the file's raw contents instead of executing it. The two are companions: same URL-resolution mechanic, different treatment of the result.

Use `.relative` when the sibling is a Caspian script you want to run; use `.download` when it's anything else.
