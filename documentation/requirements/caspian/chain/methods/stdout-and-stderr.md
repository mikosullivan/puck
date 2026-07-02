# `%chain.stdout` and `%chain.stderr`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_chain_stdout_stderr",
	"role": "thin grant-mediated wrapper for stdout/stderr; the streams themselves are owned by the engine slot doc."
}}
~~~

The grant-mediated forms of [`%engine.stdout`](../../engine/stdout-and-stderr) and [`%engine.stderr`](../../engine/stdout-and-stderr) — same underlying streams, reachable from any role the user has granted them to. For what these streams ARE (primary vs diagnostic, host routing), see the engine-slot doc.

**Default-granted across role boundaries:** no.  
**Shortcut globals:** `%stdout`, `%stderr`.

Granting `%stderr` to non-user roles is more common than granting `%stdout` — diagnostic output from non-user code is usually genuinely useful, whereas primary output should generally stay the user's voice.
