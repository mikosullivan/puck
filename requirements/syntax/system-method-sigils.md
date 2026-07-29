# System-method sigils
<!--index: 11-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_syntax_system_method_sigils",
	"role": "spec for the syntax-level rules governing %-prefixed system methods — the % prefix, the always-available / not-user-definable rules, and the canonical-vs-bare shortcut structure. The catalog of which sigils exist and what each one does lives at global-methods/.",
	"audience": "developers writing Caspian; parser/lexer implementers"
}}
~~~

System methods start with `%`. They are always available (subject to grants and role), and they cannot be user-defined — the `%` prefix is reserved.

Two syntactic shapes appear:

- **Canonical namespace form** — `%X` or `%X.Y`. Standalone namespaces (`%self`, `%call`, `%chain`, `%engine`) and chain-mediated capabilities in their full `%chain.X` form.
- **Bare-`%X` shortcut** — a short form for a small set of chain-mediated capabilities (`%fetch`, `%stdin`, `%stdout`, `%stderr`). Each bare form resolves to its `%chain.X` canonical equivalent; the canonical form is the one `.grant`/`.revoke` operates on.

Other globals on `%chain` (`%chain.net`, `%chain.timer`, `%chain.timeout`, etc.) have no bare shortcut and are only reachable through the canonical form.

For the catalog of every sigil, per-sigil semantics, and which bare shortcuts exist, see [global-methods](https://puck.uno/requirements/global-methods/). Chain-mediated methods have their canonical specs under [chain/methods/](https://puck.uno/requirements/chain/methods/).

## Testing

- **`%self` parses and resolves inside a method** — a method body reading `%self` returns the current instance.
- **`%self` outside a method raises** — `%self` at top-level raises (no self in that scope).
- **`%call` parses and resolves inside a method** — a method body reading `%call` returns the current call object.
- **`%call` outside a method raises** — top-level `%call` raises.
- **`%chain` parses and resolves anywhere** — top-level `%chain` returns the chain object.
- **`%chain.X` resolves the named chain-mediated capability** — `%chain.puck` returns the object-download surface.
- **`%engine` parses at the top level** — a top-level `%engine.X` call resolves (subject to role).
- **`%engine` inside user-code role raises** — invoking `%engine` from a role that does not permit engine access raises.
- **Bare `%fetch` shortcut resolves to `%chain.puck`** — both yield the same value.
- **Bare `%stdin` shortcut resolves to `%chain.stdin`** — both yield the same value.
- **Bare `%stdout` shortcut resolves to `%chain.stdout`** — both yield the same value.
- **Bare `%stderr` shortcut resolves to `%chain.stderr`** — both yield the same value.
- **`%chain.net` has no bare shortcut** — `%net` as a standalone form raises (no such bare shortcut); `%chain.net` works.
- **`%chain.timer` has no bare shortcut** — bare `%timer` raises; `%chain.timer` works.
- **`%chain.timeout` has no bare shortcut** — bare `%timeout` raises; `%chain.timeout` works.
- **`.grant` operates on canonical `%chain.X` form** — granting `%chain.stdout` also grants the bare `%stdout`.
- **`.revoke` on `%chain.X` revokes the bare form** — after revoking `%chain.stdout`, both `%stdout` and `%chain.stdout` raise "not granted".
- **User cannot define new `%X`** — attempting `%foo = 1` fails to parse.
- **Unknown `%X` name raises** — `%bogus` raises (surface not defined), not returning `null`.
- **`%X` on missing role raises with a "not granted" message** — the raise names the specific surface that was denied.
- **`%X.Y` chain access parses** — `%chain.puck` and `%engine.something` both parse in the two-dot form.
