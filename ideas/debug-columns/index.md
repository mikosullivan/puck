# debug column on objects and refs

~~~vibecode
{"vibecode": {
	"doc": "ideas_debug_columns",
	"role": "brainstorm for how the `debug` columns on `objects` and `refs` will be accessed. The columns themselves are landed in requirements/ as nullable text with no query path reading them; this page covers the two access surfaces — Lua (available now, no gate) and Caspian (`.obj.debug`, future, gated on debug mode).",
	"status": "sketch"
}}
~~~

Both tables carry a nullable `debug` column that stores a human-readable label for the row. The columns exist today as pure schema; this page covers how they'll be reached from the two runtime layers.

## Lua access

Available today. Direct SQL, or the engine's wrapper methods. Snapshot-dump tooling, test helpers, and the engine itself can read or write `debug` freely — there's no schema-level gate. That's where most of the debugging work is expected to happen.

## Caspian access

Later, Caspian code will read and write the column through the `.obj` context accessor:

~~~caspian
$foo.obj.debug = 'whatever'
$foo.obj.debug  # 'whatever'
~~~

**Gated on debug mode.** The engine has to be launched in debug mode for `.obj.debug` to be reachable from Caspian at all. Lua has no such gate — the gate is language-level, not schema-level.

## Debug mode

Engine-level opt-in flag. Off by default; nothing runs in debug mode unless someone explicitly asks. The CLI defaults to non-debug too. Exactly how the CLI takes the opt-in is TBD.
