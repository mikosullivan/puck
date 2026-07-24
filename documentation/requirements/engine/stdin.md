# `%engine.stdin`
<!--index: 2 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_engine_stdin",
	"role": "spec for %engine.stdin — the program's input channel. Like every %engine slot, only user-role code can reach it (see the blanket gate on the %engine root)."
}}
~~~

`%engine.stdin` is the program's input channel — the place a Caspian program reads bytes the host has piped in. Reading from it is the only way to consume program input; there is no non-user-facing pipe equivalent.

If non-user code needs input, the user is the one who reaches into `%engine.stdin` and hands the data across. That keeps the boundary clean: the user controls what input flows into the program and where it ends up.

## Testing

- **`%engine.stdin.read` returns bytes piped to the process** — piping `'hello'` in on the shell gives `%engine.stdin.read` equal to `'hello'`.
- **A program with no piped input reads empty** — the read produces the empty string, not null.
- **`%engine.stdin` is user-only** — a non-user frame reading from it raises the blanket gate error.
- **A captured `$stdin = %engine.stdin` handed to a non-user frame is still callable** — method-runs-as-owner applies; the read happens under user's authority.
- **Values from `%engine.stdin` are role-tagged with the stdin faucet's role** — a string read has `.object.role` equal to that faucet role, not `user`.
- **Values from `%engine.stdin` include the stdin faucet role in `contributors`** — provenance is durable.
- **UTF-8 input produces a UTF-8 string** — piping unicode text yields a string with unicode intact.
- **Binary bytes round-trip** — piping non-UTF-8 bytes yields a string of exactly those bytes.
- **EOF terminates a full-read cleanly** — a read on a closed stream returns the accumulated bytes without raising.
- **Reading past EOF returns an empty string** — subsequent reads produce empty results, not raises.
- **Blocking read waits for input** — a read on an open, empty stream blocks until data arrives or EOF is signaled.
- **`%engine.stdin` cannot be reassigned** — `%engine.stdin = ...` raises.
- **Multiple reads consume the stream progressively** — already-consumed bytes don't reappear.
- **A single-consumer stream is shared across all readers** — two reads share the underlying buffer, not two copies.
- **Embedded host with no stdin concept behaves as EOF-immediate** — reads return empty; no raise.
- **A large-payload stdin (megabytes) reads correctly** — no truncation at engine-side buffer boundaries.
- **A stdin containing embedded null bytes preserves them** — `\0` bytes are part of the returned string.
- **Non-user role reading via bracket form `%engine['stdin']` raises** — the gate applies via either accessor.
