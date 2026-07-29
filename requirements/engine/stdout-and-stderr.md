# `%engine.stdout` and `%engine.stderr`
<!--index: 3 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_engine_stdout_stderr",
	"role": "spec for %engine.stdout and %engine.stderr — the program's two output channels. Like every %engine slot, only user-role code can reach them (see the blanket gate on the %engine root). The split between stdout and stderr is semantic — what the channel carries, not who can write to it."
}}
~~~

`%engine.stdout` and `%engine.stderr` are the program's two output channels — where bytes go when the program wants to be heard. They map to the host's standard-output and standard-error streams when the host is a CLI runner; embedded hosts route them wherever they want.

## `%engine.stdout`

The program's primary output channel. The same underlying channel is reachable via the global `%stdout`; the host may grant `%stdout` to non-user roles when it wants non-user code to be able to write there. Whether non-user code can produce output is a host policy decision exposed through `%stdout` — but `%engine.stdout` itself is user-only (like every `%engine` slot), so the channel via this path stays unambiguously the user's.

## `%engine.stderr`

The program's diagnostic-output channel. Distinct from `%engine.stdout` in semantics: stdout carries the program's intended output; stderr carries notices, warnings, error traces, and other side-channel diagnostics. Hosts route the two streams independently — under a CLI runner, stdout might be piped while stderr stays on the terminal.

Like `%engine.stdout`, only `user`-role code can reach `%engine.stderr` directly. If the host wants non-user code to write diagnostics it grants the global `%stderr` to it — but the `%engine`-prefixed access stays user-only.

## Bare-word `puts` and `print`

`puts` and `print` are **bareword commands** (bwcs). They stay as bwc atoms through both CaspJ and CaspM — the transpiler does NOT rewrite them at parse time. The engine's `puts` / `print` handlers decide where the output goes at runtime.

<!-- STALE: %chain.X syntax being reworked — the "chain slot" framing here predates the permission-only %chain model. -->
In V1, both handlers route through `%chain.stdout` (or whatever the current chain frame has installed there). Future situations might route `puts` to `%chain.stderr` or elsewhere based on runtime context — leaving the resolution at the engine level rather than pinning it at parse time keeps that flexibility.

Both take the same argument shape as an explicit `%stdout.puts` / `%stdout.print` method call (one or more expressions, comma-separated).

- **Not rebindable.** `$puts = &something_else` does NOT affect subsequent `puts` calls — `puts` is a bwc, not a variable lookup at runtime. To pass the writer around as a value, use `%stdout` or capture `$out = %stdout` and pass `$out`.
- **Redirection lives at `%chain.stdout`.** The sanctioned V1 way to redirect where `puts` output goes is to rebind `%chain.stdout` for a scope. The engine's `puts` handler resolves through the current chain slot at call time.
- **Role gate applies identically.** `puts` and `%stdout.puts` face the same role check on `%stdout` — the bwc resolution is orthogonal to access control.

No corresponding `eputs` / `eprint` sugar for `%stderr`. Diagnostic writes are explicit: `%stderr.puts 'warning'`. The asymmetry is deliberate — diagnostics should read as diagnostics at the call site.

## Testing

- **`%engine.stdout.puts('hello')` writes `'hello\n'` to the host's stdout stream** — CLI runner observes those bytes on stdout.
- **`%engine.stdout.print('hello')` writes without a trailing newline** — no `\n` appended.
- **Bare `puts 'hello'` writes `'hello\n'` to the current `%chain.stdout`** — same observable output as `%stdout.puts 'hello'` when no chain redirection is in effect. `puts` stays as a bwc in the CaspJ / CaspM tree; the engine's puts handler routes at runtime.
- **Bare `print 'hello'` writes without a trailing newline** — same runtime routing as `puts`.
- **`$puts = &something_else` does NOT redirect subsequent `puts` calls** — `puts` is a bwc, not a variable lookup at runtime.
- **`%engine.stderr.puts('warn')` writes to the host's stderr stream** — separate from stdout.
- **`%engine.stdout` and `%engine.stderr` are independent streams** — bytes written to one don't appear on the other.
- **A host piping stdout leaves stderr on the terminal** — routing is independent per host policy.
- **UTF-8 output is written as UTF-8** — writing `'Zoë'` produces the correct multi-byte encoding, not `?`, not Windows-1252.
- **No charset header manipulation** — Caspian never sets `charset=` anywhere; output is UTF-8 by guarantee.
- **Writing an empty string via `.print('')` writes zero bytes** — no-op.
- **Writing an empty string via `.puts('')` writes `'\n'`** — the newline is the `puts` contribution.
- **Bytes written via `%engine.stdout` are role-attributed to `user`** — attribution names `user`.
- **Bytes written via `%chain.stdout` from a non-user frame are attributed to that non-user role** — attribution follows the writing frame.
- **`%engine.stdout` is user-only** — a non-user frame reaching `%engine.stdout` directly raises the blanket gate error.
- **`%chain.stdout` may be granted to non-user roles by the host** — the sanctioned way to let non-user code write.
- **`%engine.stdout` cannot be reassigned** — `%engine.stdout = ...` raises.
- **`%engine.stderr` cannot be reassigned** — `%engine.stderr = ...` raises.
- **Writing a string with embedded newlines writes them verbatim** — `'a\nb'` produces three bytes: `a`, newline, `b`.
- **Writing a string with embedded null bytes preserves them** — `\0` bytes appear on the output stream.
- **A jail on `%engine.stdout` restricts methods** — `%engine.stdout.object.jail(:puts)` exposes only `.puts`; calling `.print` on the jail raises.
- **A jail on `%engine.stderr` restricts methods** — same mechanism.
- **A captured `$out = %engine.stdout` passed to a non-user frame is callable** — method-runs-as-owner semantics; writes attributed to user.
- **Writing binary data (non-UTF-8 bytes) preserves the bytes verbatim** — no re-encoding.
- **Bytes are visible to the host promptly or at process exit** — the host observes output either per-call or, at latest, before `engine.run()` returns.
- **`%engine.stdout` is a sink object** — subject to the sink model (see `plumbing/sinks`).
- **`%engine.stderr` is a sink object** — same model.
- **Concurrent writes from within a program interleave deterministically** — Caspian is single-threaded; write ordering matches program order.
- **Writing a multi-contributor string is not blocked for stdout in V1** — stdout is not in the string-contributors blocked-operations set (V1); this may change post-V1.
- **A raise-at-write on the host-side sink (e.g., broken pipe) propagates as an error** — the write call raises rather than silently succeeding.
