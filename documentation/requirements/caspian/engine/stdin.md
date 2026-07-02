# `%engine.stdin`
<!--index: 2 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_engine_stdin",
	"role": "spec for %engine.stdin — the program's input channel. Like every %engine slot, only user-role code can reach it (see the blanket gate on the %engine root)."
}}
~~~

`%engine.stdin` is the program's input channel — the place a Caspian program reads bytes the host has piped in. Reading from it is the only way to consume program input; there is no non-user-facing pipe equivalent.

If non-user code needs input, the user is the one who reaches into `%engine.stdin` and hands the data across. That keeps the boundary clean: the user controls what input flows into the program and where it ends up.
