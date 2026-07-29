# `%amber` — the ambient hash

~~~vibecode
{"vibecode": {
	"doc": "documentation_amber",
	"role": "user-facing introduction to %amber, Caspian's ambient-hash surface. Explains the concept, motivates it with everyday use cases, contextualizes it against prior art in other languages, and points at the requirements spec for the precise rules. No implementation details, no per-operation rule enumeration — that lives in the spec.",
	"status": "user doc — accompanies (does not duplicate) the spec at ideas/ambient-hash (soon to be promoted to requirements/amber)",
	"audience": "Caspian programmers who want to know what %amber is for and when to reach for it"
}}
~~~

## What it is

`%amber` is Caspian's **ambient hash** — a place to put values that any code called downstream of yours can read, without having to pass them as arguments through every intermediate call. Things like "the request ID for this HTTP request I'm serving," "the tenant this operation belongs to," "the log level for this run" — cross-cutting data that isn't the point of any function but is relevant to many.

Reads and writes look like a normal hash:

~~~caspian
%amber.init('example.com/my-app')
%amber['example.com/my-app']['request_id'] = 'req-4c9f'

# ...many function calls later, deep in some helper...

$id = %amber['example.com/my-app']['request_id']    # 'req-4c9f' — no arg-threading needed
~~~

The `.init` call is required — every ambient hash is a named namespace under a domain you control (like `example.com/my-app`). No unqualified keys, no global namespace to collide in.

## What makes it useful

Three patterns come up over and over:

**Cross-cutting context.** A web handler sets `request_id`, `tenant_id`, `user_id` when a request lands. Every log line, every database call, every downstream service call needs those values. Without ambient state, they get threaded through every function signature — annoying, invasive, easy to drop. With `%amber`, they're set once at the top and readable anywhere below.

**Test hooks and mock injection.** A test wants to inject a fake clock, or capture what a subroutine writes, or set a "fail this specific call" flag deep in the stack. Ambient state lets the test set the hook without the subroutine being aware it's being tested. No dependency injection, no constructor plumbing.

**Feature flags at runtime.** A code path checks `%amber['example.com/app']['use_new_algorithm']` to decide which implementation to run. The flag is set at request-time (per-request A/B) or session-time (per-session gate) without threading it through the call graph.

## The trust model

Ambient values don't leak to code you don't trust. Cross a role boundary (calling into a downloaded library, an untrusted subroutine, an agent) and the callee sees an empty `%amber` — none of your namespaces are visible. To share, you explicitly grant a specific namespace for the duration of a block:

~~~caspian
%amber['example.com/my-app'].grant(read: true) do
	&third_party_library.render($html)
end
~~~

Inside the block the third-party code sees the namespace read-only; outside, it doesn't. Grants cross one role boundary at a time — if that library calls further into yet another untrusted role and wants the namespace visible there too, it has to grant again explicitly.

## Prior art

`%amber` sits in a small but well-explored corner of language design. The bidirectional-within-scope + block-scoped-lifetime + role-boundary-isolation combination is a Caspian-specific mix, but each ingredient has ancestors:

- **Common Lisp special variables** (with `let` and `setq`). `(let ((*foo* 'x)) ...)` is `%amber.init` in a block; `setq` mutates the binding visible to ancestors. Very close in shape, minus the trust boundary.
- **Racket parameters** (`make-parameter` + `parameterize`). Named ambient slots with block-scoped bindings; usually used one-way (immutable while in scope).
- **Python `contextvars`, JavaScript `AsyncLocalStorage`, Kotlin CoroutineContext.** Modern one-way-downward ambient context designed for async safety. Values are visible to downstream code but writes don't propagate back up.
- **Go `context.Context`.** The explicit variant — every function takes a `ctx` as its first parameter. Same intent as ambient context, opposite ergonomics.
- **Erlang process dictionary, Ruby `Thread.current[]`.** Bidirectional but unscoped; one bag per process/thread. Discouraged in idiomatic use because collisions and lifetime issues are unmanaged.
- **React Context** (JavaScript UI framework). Component-tree ambient values with one-way-downward propagation. Same "ambient trumps arg-threading" motivation, applied at the UI layer.
- **Java package naming, npm scoped packages, iOS bundle IDs.** Same collision-prevention pattern (`com.company.myapp`, `@company/pkg`) that `%amber` uses for namespaces — domain-shaped names.

The closest single match is Common Lisp specials with `setq`. If you already know that model, `%amber` is "specials with named namespaces and role-boundary trust isolation."

## What `%amber` isn't

- **Not a global variable.** Values are scoped to the frame that init'd them; when the frame exits, the namespace disappears. Not a place to stash "always-available config."
- **Not thread-safe by construction.** Caspian is single-threaded by default; forked children get their own `%amber`. Concurrent access isn't a design consideration here.
- **Not a substitute for arguments.** If a value is central to what a function does, pass it as an argument. `%amber` is for the ambient stuff that many functions need but few actually care about.
- **Not for secrets.** Values in `%amber` are readable by anyone in the same role. If you need actual credential storage, use [protected memory](https://puck.uno/requirements/protected/) — different mechanism, different guarantees.

## For the exact rules

This doc is the intro. For the precise semantics — init failure modes, grant permission arrays, block-form vs plain form, the `.remove` / `.clear` / `.has_key?` operations, the aggregate-hash mechanism underneath — see the spec at [`ideas/ambient-hash`](https://puck.uno/ideas/ambient-hash) (soon promoted to `requirements/amber`).
