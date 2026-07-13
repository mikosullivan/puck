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

## Testing

- **`%stdin` reachable from `user`** — from the top-level user role, `%stdin` is present and can be read from.
- **`%stdin.read_all` returns full input** — piping `'hello world'` on stdin and calling `%stdin.read_all` returns `'hello world'`.
- **`%stdin.read_line` returns one line** — piping `"line1\nline2\n"` and calling `%stdin.read_line` returns `'line1'` (without the trailing newline); the next `read_line` returns `'line2'`.
- **`%stdin.read_bytes(n)` returns n bytes** — with `'abcdefghij'` on stdin, `%stdin.read_bytes(5)` returns `'abcde'`; a subsequent `read_bytes(5)` returns `'fghij'`.
- **EOF on `read_all` returns empty string** — with no input, `%stdin.read_all` returns `''`.
- **EOF mid-stream** — after all bytes are consumed, further `read_line` or `read_bytes` returns `null` (or documented EOF sentinel), not a raise.
- **Closed stdin behaves like EOF** — stdin explicitly closed by the host produces EOF on next read, not a raise.
- **UTF-8 preserved** — piping `'héllo'` (UTF-8, 6 bytes) through `%stdin.read_all` returns the original characters intact.
- **`read_bytes` counts bytes not characters** — with UTF-8 `'héllo'` on stdin, `read_bytes(2)` returns the first two bytes (`h` + first byte of `é`), not the first two characters.
- **Empty stdin `read_line` returns null** — with truly empty input, `read_line` returns `null` (or documented EOF sentinel) immediately.
- **Default-denied across role boundaries** — a non-user role invoked without an explicit `%stdin` grant sees `%stdin` as absent / `null`.
- **Explicit grant lets non-user role read** — after the user explicitly grants `%stdin` to a non-user role, that role can call `%stdin.read_all`.
- **Grant does not transit further without opt-in** — a non-user role that received `%stdin` cannot pass it to a further-nested role without an explicit sub-grant.
- **Revoke ends access mid-run** — after `%stdin` is revoked from a role, that role's next `%stdin.read_all` raises capability-not-granted.
- **Read data carries the puck-faucet's role** — data returned from `%stdin` is owned by the `%stdin` faucet's role, not by the caller.
- **`%engine.stdin` and `%stdin` share underlying stream** — bytes consumed via `%engine.stdin` are not re-delivered via `%stdin` (they read from one channel).
- **`%stdin` is user-reachable without explicit grant** — the user always has access; the grant model applies only when passing it downward.
