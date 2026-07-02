# System-method sigils
<!--index: 12-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_system_method_sigils",
	"role": "spec for the %-prefixed system methods at the syntax level — the four standalone namespaces (%self, %call, %chain, %engine) and the six bare-%X shortcuts (%now, %puck, %random, %stdin, %stdout, %stderr). Per-method semantics live under global-methods/ and chain/methods/.",
	"audience": "developers writing Caspian; parser/lexer implementers"
}}
~~~

System methods start with `%`. They are always available (subject to grants and role), and they cannot be user-defined. Four are canonical namespaces on their own:

- **`%self`** — the current instance inside a method. `self` bare is a shorthand.
- **`%call`** — the current call object; owned by the caller. Used to inspect the caller and for early-exit (`%call.return`).
- **`%chain`** — the call-frame chain; hosts grants, ambient values, and most globals in canonical form (`%chain.X`).
- **`%engine`** — the host-resource gateway; reachable only from user-role code.

Every global capability lives on `%chain` in canonical form. A small set has bare-`%X` shortcuts:

| Bare form | Canonical | Purpose |
|---|---|---|
| `%now` | `%chain.now` | Current timestamp |
| `%puck` | `%chain.puck` | Object download by URL (also `%[url]` short form) |
| `%random` | `%chain.random` | Random-value primitives |
| `%stdin` | `%chain.stdin` | Program input |
| `%stdout` | `%chain.stdout` | Primary output |
| `%stderr` | `%chain.stderr` | Diagnostic output |

Other globals (`%chain.net`, `%chain.timer`, `%chain.timeout`, etc.) are reached only through the canonical `%chain.X` form.

For per-method semantics see [global-methods](https://puck.uno/documentation/requirements/caspian/global-methods/) and [chain/methods/](https://puck.uno/documentation/requirements/caspian/chain/methods/).
