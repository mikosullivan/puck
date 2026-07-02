# `%engine.stdout` and `%engine.stderr`
<!--index: 3 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_engine_stdout_stderr",
	"role": "spec for %engine.stdout and %engine.stderr — the program's two output channels. Like every %engine slot, only user-role code can reach them (see the blanket gate on the %engine root). The split between stdout and stderr is semantic — what the channel carries, not who can write to it."
}}
~~~

`%engine.stdout` and `%engine.stderr` are the program's two output channels — where bytes go when the program wants to be heard. They map to the host's standard-output and standard-error streams when the host is a CLI runner; embedded hosts route them wherever they want.

## `%engine.stdout`

The program's primary output channel. The same underlying channel is reachable via the global `%stdout`; the host may grant `%stdout` to non-user roles when it wants non-user code to be able to write there. Whether non-user code can produce output is a host policy decision exposed through `%stdout` — but `%engine.stdout` itself is user-only (like every `%engine` slot), so the channel via this path stays unambiguously the user's.

## `%engine.stderr`

The program's diagnostic-output channel. Distinct from `%engine.stdout` in semantics: stdout carries the program's intended output; stderr carries notices, warnings, error traces, and other side-channel diagnostics. Hosts route the two streams independently — under a CLI runner, stdout might be piped while stderr stays on the terminal.

Like `%engine.stdout`, only `user`-role code can reach `%engine.stderr` directly. If the host wants non-user code to write diagnostics it grants the global `%stderr` to it — but the `%engine`-prefixed access stays user-only.
