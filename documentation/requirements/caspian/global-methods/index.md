# Global methods
<!--index: 7 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_methods_root",
	"role": "index of every %X-prefixed global — the standalone system namespaces (%chain, %engine, %call, %self), the bare-%X capability shortcuts, and the always-allowed compile-time documentation methods (%documentation, %vibecode). Each section points to the canonical doc and, for capability shortcuts, notes the user-only %engine slot the surface comes from.",
	"audience": "anyone looking up which globals exist"
}}
~~~

Twelve global methods, in alphabetical order. Three categories:

- **Standalone system namespaces** (`%call`, `%chain`, `%engine`, `%self`) — each its own thing.
- **Bare-`%X` chain shortcuts** (`%now`, `%puck`, `%random`, `%stderr`, `%stdin`, `%stdout`) — short forms for chain-mediated capabilities, also reachable as `%chain.X` (the form used for `.grant`/`.revoke`). Every chain capability is provisioned by the engine at startup and reachable as a user-only `%engine.X` slot too — the `%chain.X` form is what carries the surface across role boundaries.
- **Compile-time documentation methods** (`%documentation`, `%vibecode`) — always allowed regardless of role or grant; recorded in CaspianJ at parse time but produce no runtime artifact the program can observe (pre-V1).

## `%call`

The current call object. Owned by the caller's role. Inside any function or closure body, `%call` exposes the caller's role (`%call.role`), early-exit (`%call.return`), block yielding (`%call.yield`), and the dispatcher for DSL-style block use. See [`call/`](https://puck.uno/documentation/requirements/caspian/global-methods/call/) for more details.

## `%chain`

The ambient call-frame chain. Every chain-mediated capability lives on `%chain`; ambient context flows down the chain; inspection (current role, parent frame, depth) reads the chain.

Canonical: [`chain/`](https://puck.uno/documentation/requirements/caspian/chain/).

## `%documentation`

Compile-time documentation annotation. Takes a heredoc argument tagged with a MIME type:

~~~caspian
%documentation('text/markdown') <<EOF
This routine looks up the current temperature at the given zip code.
EOF
~~~

Content types: `text/plain`, `text/markdown`, `text/vibecode`. Shorthand type names — `text`, `markdown`, `vibecode` — expand to the corresponding `text/*` form.

**Always allowed.** No role or grant governs `%documentation`; any code in any frame may write one. **Produces no runtime artifact the program can observe** (pre-V1) — the block is recorded in CaspianJ at parse time, but the script itself can't read it back at runtime and the engine doesn't act on it. It exists for tooling (documentation generators, syntax highlighters, AI readers, etc.), not for the running program.

## `%engine`

The host-resource gateway. Reachable only from `user`-role code — every slot on `%engine` is a runtime error from any non-user role. Hosts populate `%engine` with the resources the program is allowed to touch; the user then either uses those slots directly or hands the chain-mediated form down to non-user code.

Canonical: [`engine/`](https://puck.uno/documentation/requirements/caspian/engine/).

## `%now`

Current timestamp from the engine-controlled clock. Default-granted across role boundaries.

Shortcut for `%chain.now`. Reaches the same clock as the user-only [`%engine.now`](https://puck.uno/documentation/requirements/caspian/engine/).

Canonical: [`chain/methods/now`](https://puck.uno/documentation/requirements/caspian/chain/methods/now).

## `%puck`

Object download by URL. Each call returns a fresh object. `%[url]` is the further-shortened form. Default-granted across role boundaries.

Shortcut for `%chain.puck`. Reaches the same object-download surface as the user-only [`%engine.puck`](https://puck.uno/documentation/requirements/caspian/engine/).

Canonical: [`chain/methods/puck`](https://puck.uno/documentation/requirements/caspian/chain/methods/puck).

## `%random`

Random-value primitives (UUID, number, string). All draw from libsodium → OS CSPRNG. Default-granted across role boundaries.

Shortcut for `%chain.random`. Reaches the same RNG as the user-only [`%engine.random`](https://puck.uno/documentation/requirements/caspian/engine/).

Canonical: [`chain/methods/random`](https://puck.uno/documentation/requirements/caspian/chain/methods/random).

## `%self`

The current object instance inside a method body. Outside a method (free-standing function, closure, top-level code) `%self` is not available. The bare word `self` is shorthand for `%self`.

`%self.object.role` returns the instance's owning role; `%self.object.broadcast` (and other `%self.object.*` accessors) reach the standard object surface. Methods use `%self` to call into their own object's surface.

## `%stderr`

Diagnostic-output channel — warnings, traces, anything side-channel to the program's intended output. Not default-granted; granting `%stderr` to non-user roles is more common than granting `%stdout`.

Shortcut for `%chain.stderr`. Reaches the same stream as the user-only [`%engine.stderr`](https://puck.uno/documentation/requirements/caspian/engine/stdout-and-stderr).

Canonical: [`chain/methods/stdout-and-stderr`](https://puck.uno/documentation/requirements/caspian/chain/methods/stdout-and-stderr).

## `%stdin`

Input channel. Not default-granted; the user passes it down when non-user code legitimately needs to consume input.

Shortcut for `%chain.stdin`. Reaches the same channel as the user-only [`%engine.stdin`](https://puck.uno/documentation/requirements/caspian/engine/stdin).

Canonical: [`chain/methods/stdin`](https://puck.uno/documentation/requirements/caspian/chain/methods/stdin).

## `%stdout`

Primary output channel. Not default-granted — the user passes it down explicitly when non-user code legitimately needs to produce output.

Shortcut for `%chain.stdout`. Reaches the same stream as the user-only [`%engine.stdout`](https://puck.uno/documentation/requirements/caspian/engine/stdout-and-stderr).

Canonical: [`chain/methods/stdout-and-stderr`](https://puck.uno/documentation/requirements/caspian/chain/methods/stdout-and-stderr).

## `%vibecode`

Compile-time AI-readable-JSON documentation annotation. Shorthand for `%documentation('vibecode') <<EOF ... EOF`:

~~~caspian
%vibecode <<EOF
{
	"purpose": "Look up the current temperature at the given zip code",
	"returns": "number (degrees Fahrenheit) or null on lookup failure"
}
EOF
~~~

An optional `side` field inside the JSON indicates attachment intent — `"target"` for the left-hand side of an assignment, `"value"` for the right-hand side. Omit `side` for statements with no assignment. Consumer effect of `side` is TBD; the field is recorded in CaspianJ for future use but no current consumer reads it.

**Always allowed** and **produces no runtime artifact** — same rules as `%documentation`.
