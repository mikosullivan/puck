# `%chain.stdout` and `%chain.stderr`

**STALE — pending relocation.** `%chain` no longer carries methods. This file describes what used to live on `%chain.X` and awaits relocation to its correct home (typically a top-level global, a downloadable core object, or a permission-indicator stub). See [chain/index](https://puck.uno/requirements/chain/) for the current `%chain` scope.

~~~vibecode
{"vibecode": {
	"doc": "requirements_chain_stdout_stderr",
	"role": "thin grant-mediated wrapper for stdout/stderr; the streams themselves are owned by the engine slot doc."
}}
~~~

The grant-mediated forms of [`%engine.stdout`](../../engine/stdout-and-stderr) and [`%engine.stderr`](../../engine/stdout-and-stderr) — same underlying streams, reachable from any role the user has granted them to. For what these streams ARE (primary vs diagnostic, host routing), see the engine-slot doc.

**Default-granted across role boundaries:** no.  
**Shortcut globals:** `%stdout`, `%stderr`.

Granting `%stderr` to non-user roles is more common than granting `%stdout` — diagnostic output from non-user code is usually genuinely useful, whereas primary output should generally stay the user's voice.

## Testing

- **`%stdout.write` appears on stdout** — `%stdout.write 'hello'` from the user role writes `hello` to the process's stdout stream (verified by capturing the child process's stdout).
- **`%stderr.write` appears on stderr** — `%stderr.write 'oops'` from the user role writes `oops` to stderr (verified by capturing the child process's stderr).
- **Streams are independent** — writes to `%stdout` do not appear on stderr and vice versa; a run interleaving writes produces two matching-order streams.
- **Newline handling** — `%stdout.puts 'line'` (or the equivalent write-with-newline method) emits `'line\n'`; `%stdout.write 'line'` emits `'line'` with no newline.
- **UTF-8 output** — `%stdout.write 'héllo'` produces the correct UTF-8 byte sequence on stdout; no charset header, no re-encoding.
- **Multibyte characters not split across writes** — a single `%stdout.write` of a multibyte character emits the full byte sequence atomically.
- **Byte-level write** — writing a value that is byte data (not a string) writes the raw bytes without UTF-8 validation.
- **Flush semantics** — after `%stdout.write` returns, a subsequent read of the captured stdout from the parent test harness observes the bytes (or `%stdout.flush` is the mechanism when buffered).
- **Write during raise** — a `raise` following a `%stdout.write` does not roll back or suppress the write; the bytes are already on stdout when the exception propagates.
- **Default-denied across role boundaries** — a non-user role invoked without an explicit `%stdout` grant sees `%stdout` as absent / `null`.
- **`%stderr` also default-denied** — same as `%stdout`; non-user roles need an explicit `%stderr` grant.
- **Explicit `%stdout` grant works** — after the user grants `%stdout` to a non-user role, that role can call `%stdout.write`.
- **Independent grants** — granting `%stderr` to a role does NOT implicitly grant `%stdout` to the same role.
- **Revoke ends access** — after `%stdout` is revoked, the role's next `%stdout.write` raises capability-not-granted.
- **Written data attributed to writer's role** — output written by a non-user role is attributable to that role (host routing / provenance introspection reports the writer, not the ambient user).
- **`%engine.stdout` and `%stdout` share the underlying stream** — bytes written via `%engine.stdout` and via `%stdout` end up on the same host stream in write order.
- **Wrong-type arg raises** — `%stdout.write 42` (integer where string/bytes expected) raises a type error, or is documented to auto-stringify — whichever the spec resolves to; the test pins the behavior.
- **Empty write is a no-op** — `%stdout.write ''` writes zero bytes and does not raise.
