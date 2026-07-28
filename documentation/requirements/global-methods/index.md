# Global methods
<!--index: 7 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_global_methods_root",
	"role": "index of every %X-prefixed global — the standalone system namespaces (%chain, %engine, %call, %self) and the bare-%X capability shortcuts (%now, %fetch, %random, %stderr, %stdin, %stdout). Each section points to the canonical doc and, for capability shortcuts, notes the user-only %engine slot the surface comes from. Bareword commands (documentation, vibecode, puts, print, field, method, etc.) are NOT global methods and are not indexed here.",
	"audience": "anyone looking up which globals exist"
}}
~~~

Ten global methods, in alphabetical order. Two categories:

- **Standalone system namespaces** (`%call`, `%chain`, `%engine`, `%self`) — each its own thing.
- **Bare-`%X` chain shortcuts** (`%now`, `%fetch`, `%random`, `%stderr`, `%stdin`, `%stdout`) — short forms for chain-mediated capabilities, also reachable as `%chain.X` (the form used for `.grant`/`.revoke`). Every chain capability is provisioned by the engine at startup and reachable as a user-only `%engine.X` slot too — the `%chain.X` form is what carries the surface across role boundaries.

`documentation` and `vibecode` are NOT global methods — they're bareword commands (bwcs), a separate parser category, and belong with the other bwc docs, not here.

## `%call`

The current call object. Owned by the caller's role. Inside any function or closure body, `%call` exposes the caller's role (`%call.role`), early-exit (`%call.return`), and the array of passed blocks as callable values (`%call.blocks`). Yielding is calling — `yield` is a bwc that desugars to `%call.blocks[0].call`. For configured calls (DSL wiring, reusable param setups), see [caller](tag:caller). See [`call/`](https://puck.uno/documentation/requirements/global-methods/call/) for the full surface.

## `%chain`

The ambient call-frame chain. Every chain-mediated capability lives on `%chain`; ambient context flows down the chain; inspection (current role, parent frame, depth) reads the chain.

Canonical: [`chain/`](https://puck.uno/documentation/requirements/chain/).

## `%engine`

The host-resource gateway. Reachable only from `user`-role code — every slot on `%engine` is a runtime error from any non-user role. Hosts populate `%engine` with the resources the program is allowed to touch; the user then either uses those slots directly or hands the chain-mediated form down to non-user code.

Canonical: [`engine/`](https://puck.uno/documentation/requirements/engine/).

## `%now`

Current timestamp from the engine-controlled clock. Default-granted across role boundaries.

Shortcut for `%chain.now`. Reaches the same clock as the user-only [`%engine.now`](https://puck.uno/documentation/requirements/engine/).

Canonical: [`chain/methods/now`](https://puck.uno/documentation/requirements/chain/methods/now).

## `%fetch`

Object download by URL. Each call returns a fresh object. `%(url)` is the further-shortened form. Default-granted across role boundaries.

Shortcut for `%chain.puck`. Reaches the same object-download surface as the user-only [`%engine.puck`](https://puck.uno/documentation/requirements/engine/).

Canonical: [`chain/methods/puck`](https://puck.uno/documentation/requirements/chain/methods/puck).

## `%random`

Random-value primitives (UUID, number, string). All draw from libsodium → OS CSPRNG. Default-granted across role boundaries.

Shortcut for `%chain.random`. Reaches the same RNG as the user-only [`%engine.random`](https://puck.uno/documentation/requirements/engine/).

Canonical: [`chain/methods/random`](https://puck.uno/documentation/requirements/chain/methods/random).

## `%self`

The current object instance inside a method body. Outside a method (free-standing function, closure, top-level code) `%self` is not available. The bare word `self` is shorthand for `%self`.

`%self.object.role` returns the instance's owning role; `%self.object.broadcast` (and other `%self.object.*` accessors) reach the standard object surface. Methods use `%self` to call into their own object's surface.

**`%self` is a reference, not an access token.** Calling a method through `%self` from inside the class body reaches every method the class carries, **including private methods** — see [functions/method § Calling sibling methods](https://puck.uno/documentation/requirements/functions/method#calling-sibling-methods). This works because the engine's private-method check consults [`%call.method_class`](https://puck.uno/documentation/requirements/global-methods/call/#call-method-class) — the class the currently-executing method was defined on — not the reference itself. From inside a sibling method, `%call.method_class` is the same class that carries the private method, so access is allowed.

Consequence: capturing `%self` inside a method and returning the reference does **not** grant private access to whoever holds the returned reference. Given `method &me() return %self end`, the caller of `.me` receives a reference to the same object; calling a private method through it raises because the caller's frame's `%call.method_class` is not that class. The reference is fine; the calling context isn't. Access is always checked at dispatch time against the current frame, never against the reference's provenance.

## `%stderr`

Diagnostic-output channel — warnings, traces, anything side-channel to the program's intended output. Not default-granted; granting `%stderr` to non-user roles is more common than granting `%stdout`.

Shortcut for `%chain.stderr`. Reaches the same stream as the user-only [`%engine.stderr`](https://puck.uno/documentation/requirements/engine/stdout-and-stderr).

Canonical: [`chain/methods/stdout-and-stderr`](https://puck.uno/documentation/requirements/chain/methods/stdout-and-stderr).

## `%stdin`

Input channel. Not default-granted; the user passes it down when non-user code legitimately needs to consume input.

Shortcut for `%chain.stdin`. Reaches the same channel as the user-only [`%engine.stdin`](https://puck.uno/documentation/requirements/engine/stdin).

Canonical: [`chain/methods/stdin`](https://puck.uno/documentation/requirements/chain/methods/stdin).

## `%stdout`

Primary output channel. Not default-granted — the user passes it down explicitly when non-user code legitimately needs to produce output.

Shortcut for `%chain.stdout`. Reaches the same stream as the user-only [`%engine.stdout`](https://puck.uno/documentation/requirements/engine/stdout-and-stderr).

Canonical: [`chain/methods/stdout-and-stderr`](https://puck.uno/documentation/requirements/chain/methods/stdout-and-stderr).

## Testing

- **`%call` reachable in every function body** — reading `%call` inside a bare function, closure, or method returns the call object without any grant.
- **`%chain` reachable in every function body** — same as `%call`; per-frame, always available.
- **`%engine` reachable only from user role** — in a user-role frame, `%engine` returns the engine surface; in a non-user role frame, referencing `%engine` (or any slot on it) raises.
- **`%engine.stdout` in user code returns the stream** — user code can write via `%engine.stdout.write 'x'` without needing a chain grant.
- **`%engine.stdout` in non-user code raises** — a faucet-role frame referencing `%engine.stdout` errors.
- **`%self` reachable inside method body** — a method body reading `%self` returns the receiver.
- **`%self` raises inside bare function body** — `function() %self end` invoked errors.
- **`%self` raises inside closure body with no enclosing method** — `closure() %self end` at top level errors.
- **`%self` reachable inside closure body with enclosing method** — a closure defined inside a method's body reads `%self` as the method's receiver.
- **Bare `self` shorthand equals `%self`** — inside a method body, `self` and `%self` produce the same reference.
- **`%now` default-granted to any role** — a non-user frame reading `%now` returns a timestamp without an explicit grant.
- **`%now` reaches the engine clock** — `%now` and `%engine.now` (in user code) return the same value.
- **`%fetch` default-granted** — a non-user frame calling `%fetch 'https://example.com/x'` produces the downloaded object without an explicit grant.
- **`%(url)` short form** — `%('x')` is equivalent to `%fetch 'x'`.
- **`%random` default-granted** — a non-user frame calling `%random.uuid` returns a UUID string without an explicit grant.
- **`%stdout` NOT default-granted** — a non-user frame reading `%stdout` with no grant raises.
- **`%stdout` after grant** — `%chain.grant :stdout` inside user code makes `%stdout` reachable from the called non-user frame.
- **`%stderr` NOT default-granted** — a non-user frame reading `%stderr` with no grant raises.
- **`%stdin` NOT default-granted** — a non-user frame reading `%stdin` with no grant raises.
- **Revoke removes surface** — after `%chain.revoke :stdout`, a non-user frame reading `%stdout` raises.
- **`%chain.now` equivalent to `%now`** — the two names read the same clock.
- **`%chain.puck` equivalent to `%fetch`** — same.
- **`%chain.random` equivalent to `%random`** — same.
- **Ten globals total** — no additional `%X` name resolves at the language level beyond the ten cataloged here.
