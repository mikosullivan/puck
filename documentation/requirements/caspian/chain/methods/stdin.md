# `%stdin`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_stdin",
	"role": "spec for %stdin — the global form of %engine.stdin. Same underlying input channel, reachable from any role that's been granted the capability."
}}
~~~

**Default-granted across role boundaries:** no.  
**Shortcut:** `%stdin`.

`%stdin` is the global form of [`%engine.stdin`](../../engine/stdin) — the program's input channel. Whereas `%engine.stdin` is user-only (like the entire `%engine` surface), `%stdin` is reachable from any role the host has granted the capability to.

Why both surfaces exist: the user-only `%engine.stdin` is always available to the program itself; `%stdin` is what the user passes down the call chain when non-user code legitimately needs to consume input. Granting `%stdin` is opt-in by the user — non-user code doesn't get it ambiently.
