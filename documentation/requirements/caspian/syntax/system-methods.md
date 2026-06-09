# Caspian System Methods

System methods are global methods provided by the Caspian runtime. They are always
available without import or injection. All system methods use the `%` prefix.

User code cannot define new `%`-prefixed methods. The full list is fixed by the runtime.

---

<a id="reference"></a>
## Reference

~~~vibecode
{"vibecode": {
	"section": "reference",
	"prefix": "%",
	"availability": "always_available_without_import",
	"user_defined": false,
	"methods": ["%chain", "%engine", "%puck", "%call", "%bucket",
		"%self", "%process",
		"%documentation", "%vibecode", "%role", "%utils", "%stdout", "%stderr"]
}}
~~~

| Method | Description |
|--------|-------------|
| `%chain` | Ambient context — carries request-scoped values (user, request ID, locale, etc.) down the call stack. Isolation is at **function boundaries only**: a write to `%chain` inside a block (`if`, loop, bare block) persists after the block ends. The callee gets its own chain inherited from the caller; writes in the callee do not propagate back up. Use `%chain.scope do...end` for explicit block-level isolation. **Wiped at role boundaries** (see [roles.md](../roles.md)). Use `%chain.isolate do...end` for a voluntary inline wipe plus fresh ephemeral role. Engine-installed methods on `%chain` include flag-raising (`%chain.warn`, `%chain.throw`, `%chain.error`, `%chain.exit`, `%chain.abort` — see [caspian-runtime.md § Exceptions](../lucy/index.md#exceptions-and-warnings)) and logging (`%chain.log` — see [jasmine.md](../packages/jasmine/index.md)). |
| `%engine` | Returns the engine object — the gateway to host-injected resources (standard slots like `%stdout` plus arbitrary host-defined entries via `%engine['name']`). **Only the `user` role can call `%engine` at all** — any other role invoking it raises, by a dedicated check in the engine object itself rather than via the general role-access mechanism. See [engine/](../engine/) for the full spec. |
| `%puck` | Returns the current puck object (scoped via `%chain`). The puck resolves URLs through its configured fetchers. The bare form (`foo.com/bar`) is shorthand for `https://foo.com/bar`. `%puck['https://foo.com/bar']` is a shorthand for the puck's lookup method, and `%['foo.com/bar']` is a further shorthand for that (see Shorthands below). Returns plain null if no puck is in the chain. See [puck.md](../puck.md) for the full puck-object model. |
| `%call` | The current call object — function or closure. Provides access to dispatcher, blocks, return, and call metadata. **Owned by the caller's role, not the function's owner** — `%call.return` hands control back to whoever made the call. |
| `%bucket` | The current object's private data hash. `@foo` is shorthand for `%bucket['foo']`. Instance variables live here. |
| `%self` | The current object instance. `self` (bare word) is shorthand. |
| `%process` | Process control. `%process.exit` is graceful (unwinds stack); `%process.abort` raises a `puck.uno/abort` immediately (no unwind, engine terminates). Under the role model, abort behavior is governed by the alarm rules in [roles.md](../roles.md). |
| `%documentation` | Saves a documentation block as a statement in the CaspianJ command array. Format: `%documentation <<EOF('text/markdown') ... EOF` — heredoc with the MIME type as a parenthetical argument. Common types: `text/plain`, `text/markdown`, `text/vibecode`. Shorthand type names: `text`, `markdown`, `vibecode`. **Pre-V1.0: not available to the running script** — the documentation block is recorded in CaspianJ at parse time but the script itself can't read it back at runtime, and the engine doesn't act on it. All documentation rules (storage, `side` field, attachment TBD) apply regardless of type. |
| `%vibecode` | Shorthand for `%documentation <<EOF('vibecode') ... EOF`, which is shorthand for `%documentation <<EOF('text/vibecode') ... EOF`. Saves an AI-readable JSON documentation block. An optional `side` field indicates attachment intent: `"target"` for the left-hand side of an assignment, `"value"` for the right-hand side. Omit `side` for statements with no assignment. **Consumer effect of `side` is TBD** — the field is recorded in CaspianJ for future use; no current consumer reads it. Reserved for tooling that wants to know which half of an assignment a vibecode block describes. |
| `%role` | Returns the role currently in effect — the owning role of the function-object currently executing. See [roles.md](../roles.md) for the role model. |
| `%utils` | Engine-granted convenience-utility capability. Provides forks ([`%utils.forks`](../forking/)), event broadcasting ([`%utils.broadcast`/`%utils.register`](../events/)), networking constructors ([`%utils.network.uds.new`](../network/uds/)), temp-dir access ([`%utils.tmp`](../script-context.md#tmp) — each access returns a fresh dirjail; auto-deletes on out-of-scope), and common helpers (`%utils.now`, `%utils.rand.uuid`, `%utils.timer`, `%utils.timeout`, `%utils.json.parse`, etc.). Returns `null` if the engine did not grant it. Everything coming out of `%utils` is owned by the `utils` role. See `%utils.timer`, `%utils.timeout`, and `%utils.json` sections below. |
| `%stdout` | Standard output handle. **Always present** — never null. The engine decides what it points at; if no destination was granted, it's a dev/null handle that accepts writes and discards them (with a [nanny warning](https://puck.uno/documentation/overview#no-nanny-code), silenceable via `no_writers_ok`). Capture and tee are methods on the handle — see the `%stdout` / `%stderr` section below. |
| `%stderr` | Standard error handle. Same shape and rules as `%stdout`, for error output. |

---

<a id="shorthands"></a>
## Shorthands

~~~vibecode
{"vibecode": {
	"section": "shorthands",
	"mappings": {
		"@foo": "%bucket['foo']",
		"self": "%self",
		"%['foo.com/bar']": "%puck['https://foo.com/bar']",
		"%vibecode <<EOF": "%documentation <<EOF('vibecode')",
		"%documentation <<EOF('text')": "%documentation <<EOF('text/plain')",
		"%documentation <<EOF('markdown')": "%documentation <<EOF('text/markdown')"
	}
}}
~~~

Several system methods have shorthands used so frequently that the long form is rarely
written:

| Shorthand | Expands to |
|-----------|------------|
| `@foo` | `%bucket['foo']` |
| `self` | `%self` |
| `%['foo.com/bar']` | `%puck['https://foo.com/bar']` |
| `%vibecode <<EOF...EOF` | `%documentation <<EOF('vibecode')...EOF` → `%documentation <<EOF('text/vibecode')...EOF` |
| `%documentation <<EOF('text')...EOF` | `%documentation <<EOF('text/plain')...EOF` |
| `%documentation <<EOF('markdown')...EOF` | `%documentation <<EOF('text/markdown')...EOF` |

The `%[...]` form is sugar for `%puck[...]`. Puck lookup is by far
the most-typed system call, and no other system method uses
bracket-indexing syntax, so a bare `%[...]` is unambiguous. Both
forms are valid; the long form is fine for clarity, the short form
for the hot path.

---

<a id="stdout-and-stderr"></a>
## `%stdout` and `%stderr`

`%stdout` and `%stderr` are handles to standard output and standard
error. They are **always present** — code can write to them
without null checks or guards.

What they point at depends on the engine:

- The **CLI engine** wires both to the terminal by default. Writes
  appear on stdout/stderr as expected.
- **Server, sandboxed, or microservice engines** typically leave
  them unwired. In that case the handle is a **dev/null** — it
  accepts writes and discards them.
- The **nanny warns** about writes to a stdout/stderr handle that
  has no destination, surfacing the common misconfiguration of
  forgetting to wire them up. Silenceable per handle with
  `no_writers_ok = true` for cases where discarding is
  intentional.

The benefit: `%stdout.write('debug: about to do thing X')` works
in any deployment — CLI, server, sandbox, microservice. The
handle is always there; whether the bytes go anywhere depends on
the engine's configuration. Debug-style writes can be sprinkled
in without context-specific guards.

<a id="capture"></a>
### Capture

Any process with the handle can capture output written through it:

```
$text = %stdout.capture do
    %stdout.write('hello')
    %stdout.write(' world')
end
# $text == 'hello world'
```

The block runs; writes through `%stdout` are diverted into the
capture buffer; the captured text is the value of the block.
Capture is just a method on the handle — no separate engine grant
required beyond `%stdout` itself being granted.

<a id="tee-mode-engine-only"></a>
### Tee mode (engine-only)

The engine can optionally configure `%stdout` / `%stderr` so that
captured bytes flow to *both* the capture buffer and the original
destination. This is useful for CLI tools where the operator
wants the script to print to the terminal *and* have output
collected for logging.

**Tee is an engine decision, not a Caspian-level option.** Scripts
can't choose; the engine operator does, at the same point they
decide whether to grant the handles at all. From inside Caspian,
`%stdout.capture` always behaves the same way — bytes go into the
buffer; whether the terminal also sees them depends on the
engine's tee configuration.

**Possible future feature:** a Caspian-level tee option on the
capture call (e.g., `%stdout.capture(tee: true) do ... end`),
giving scripts control over whether captured output is also
visible at the original destination. Not in v1; flagged if demand
surfaces.

<a id="security-posture"></a>
### Security posture

The engine is the policy point: it grants `%stdout` / `%stderr`,
or it doesn't. Once granted, the handle is fully usable —
writing, capturing, tee-ing. No additional restrictions.

That means **untrusted code with `%stdout` granted can capture
output its parent wrote**. Engines that don't want that should
not grant the handle to untrusted code in the first place. For
the common cases (CLI tools where the developer is the user;
server contexts where handlers don't get stdout) this is a clean
boundary.

---

<a id="utilstimer"></a>
## `%utils.timer`

Times a block and returns the elapsed time in seconds.

```caspian
$seconds = %utils.timer do
    # work to be timed
end
```

The returned value is a float at Lua's native time precision.
The block's return value is ignored — `timer` only reports
duration.

If the block throws, the exception unwinds normally and the
assignment never happens. Callers that need a partial-duration
reading on failure should wrap the block themselves with
`begin`/`ensure`.

`%utils.timer` is `null` if the engine did not grant `%utils`.
Guard with `if %utils` if the caller can't assume the namespace
is granted.

---

<a id="utilstimeout"></a>
## `%utils.timeout`

Wraps a block with a time limit. When the deadline hits, the
timeout fires a **two-stage** flag sequence:

1. **Inside the block:** a `puck.uno/timeout_handle`
   is raised. It does not unwind — `begin`/`ensure` blocks inside
   the timeout do not run, no Caspian-level cleanup is attempted
   inside. It bubbles up to the `%utils.timeout` boundary,
   ignoring all user-level `catch` and `ensure` along the way.
2. **At the boundary:** the timeout mechanism intercepts the
   `timeout_handle` and re-raises a
   `puck.uno/error/timeout` in the
   caller's scope. This is a normal catchable error — the caller
   can `catch` it (or any ancestor like `exception` or `error`)
   and handle it cleanly.

```caspian
catch('puck.uno/error/timeout')
    %utils.timeout(10) do
        # work that must finish within 10 seconds
    end
end
```

Whole-second granularity. The two-stage model is intentional: a
runaway block could also write runaway cleanup code, which would
defeat the timeout. By making `timeout_handle` un-catchable
inside the block, the timeout is genuinely unstoppable from
inside. By making the caller-side flag a normal error, the
caller gets familiar `catch`/`ensure` semantics.

<a id="the-unwind-option"></a>
### The `unwind:` option

For cooperative code that wants the timeout to behave like a
polite "time's up — clean up and exit," pass `unwind: true`:

```caspian
%utils.timeout(3600, unwind: true) do
    # run for an hour, then exit gracefully
end
```

With `unwind: true`, the two-stage mechanism collapses to one:
when the deadline fires, a `puck.uno/error/timeout`
is raised **directly inside the block**, unwinds the stack like
any normal exception, runs `begin`/`ensure`, and propagates
outward. No `timeout_handle` is involved.

**This is not a security boundary.** Code inside the block can
`catch('puck.uno/error/timeout')` and keep running.
That's the point — cooperative code is trusted to honor the
timeout. The default (`unwind: false`, or omitted) is the
security-boundary form, with `timeout_handle` doing the
uncatchable bubble-up.

| Mode | Inside the block | Caller's scope |
|---|---|---|
| Default | `timeout_handle` (uncatchable, no unwind) | `error/timeout` (catchable) |
| `unwind: true` | `error/timeout` (catchable, unwinds) | propagates from the block |

<a id="the-form-utilstimeout"></a>
### The `?` form: `%utils.timeout?`

`%utils.timeout?` (with the `?` suffix) is the **tolerant form**
that returns the timeout flag as a value instead of raising it
at the boundary:

```caspian
$timeout = %utils.timeout?(5) do
    &slow_thing
end

if $timeout
    # timed out — $timeout is the flag object (id, bucket, etc.)
else
    # block completed normally
end
```

On normal completion, `%utils.timeout?` returns `null`. The
block's own return value is not preserved through `%utils.timeout?`
— if the caller needs it, assign it to a variable inside the
block.

The `?` form is sugar for what would otherwise be `catch(...)`
boilerplate around `%utils.timeout`. It compresses the common
pattern "try for N seconds; if it works great, otherwise move on"
into the method name itself. This follows the language-wide
[`?` suffix convention](../index.md#the-suffix):
falsey on the happy path, truthy (the flag itself) on the failure
path.

The `?` form combines with the `unwind:` kwarg cleanly:

| Form | `unwind:` | Behavior |
|---|---|---|
| `%utils.timeout(N)` | (omitted) | `timeout_handle` inside (no `ensure`); `error/timeout` raised in caller scope |
| `%utils.timeout(N, unwind: true)` | `true` | `error/timeout` inside (catchable, `ensure` runs); propagates out of the block normally |
| `%utils.timeout?(N)` | (omitted) | `timeout_handle` inside (no `ensure`); boundary catches and **returns** the timeout flag |
| `%utils.timeout?(N, unwind: true)` | `true` | `error/timeout` inside (catchable, `ensure` runs); if it escapes the block, boundary catches and **returns** it |

In the `%utils.timeout?(N, unwind: true)` case: if the block
itself catches the timeout, `%utils.timeout?` returns `null`
(nothing escaped). If the block doesn't catch, the `?` form
converts the escaping timeout to a return value. The developer
can choose to handle it inside the block or outside.

<a id="nested-timeouts"></a>
### Nested timeouts

Nested `%utils.timeout` calls budget against their parent:
`effective_timeout = min(requested, remaining_parent_budget)`.
An inner `%utils.timeout(20)` inside an outer `%utils.timeout(5)`
is bound by the outer's remaining 5 seconds.

The `unwind:` kwarg is per-block — each timeout honors its own
mode. **The stricter parent always wins** at the moment its
deadline fires. If an outer `unwind: false` deadline fires while
execution is inside an inner `unwind: true` block, the outer's
`timeout_handle` bubbles up uncatchably and bypasses the inner's
`begin`/`ensure`. The inner's mode applies only when the inner's
own deadline fires.

<a id="availability"></a>
### Availability

`%utils.timeout` is `null` if the engine did not grant `%utils`.
Guard with `if %utils` if the caller can't assume the namespace
is granted.

---

<a id="utilsjson"></a>
## `%utils.json`

JSON parsing helpers. Two variants:

<a id="utilsjsonparsestring"></a>
### `%utils.json.parse(string)`

Strict parser. Returns the parsed value (hash, array, string,
number, boolean, or `puck.uno/null`) on success. Raises
`puck.uno/error/json_parse` on bad syntax.

```caspian
$data = %utils.json.parse('{"name": "Picard", "rank": "Captain"}')
$data['name']    # 'Picard'
```

<a id="utilsjsonparsestring-1"></a>
### `%utils.json.parse?(string)`

Tolerant parser. Same as `parse` on success. **Returns null
instead of raising** when the string isn't valid JSON.

```caspian
$data = %utils.json.parse?($maybe_json)
if $data
    # use $data
else
    # not valid JSON; handle the fallback case
end
```

The `?` suffix follows the language-wide
[`?` suffix convention](../index.md#the-suffix):
truthy on success, falsey on failure, never throws on the
failure path. Use `parse?` when bad input is expected (parsing
user-supplied query strings, optional config blobs, etc.); use
`parse` when bad input indicates a bug.

**Note on the null-vs-null ambiguity.** Both `parse?('null')`
(a valid JSON document containing literal null) and `parse?('garbage')`
(invalid JSON) return null. A caller that needs to distinguish
the two cases can use the strict `parse` and `catch` the
exception, or check the input ahead of time. The simpler null
return is the trade-off for the cleaner API; richer disambiguation
(via null flavors) is filed as a possible refinement but not in
v1.

<a id="availability-1"></a>
### Availability

`%utils.json.parse` and `%utils.json.parse?` are `null` if the
engine did not grant `%utils`. Guard with `if %utils` if the
caller can't assume the namespace is granted.
