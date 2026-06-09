# Global methods

~~~vibecode
{"vibecode": {
	"doc": "global_methods",
	"role": "catalog of Caspian's global methods — the %-prefixed surfaces every script reaches for. Includes capability sugar (%net, %utils, %puck, %stdout, %stderr, %chain) plus a few language constructs. Companion to the %engine catalog in script-context.md, which documents the engine-only slots underneath.",
	"audience": "Caspian developers asking 'what global methods can I use?'",
	"organization": "single index pointing to per-method docs in this directory",
	"key_concepts": ["global_methods_catalog",
		"capability_sugar_over_percent_engine_slots",
		"reachable_from_any_role_with_capability",
		"single_flat_list_with_links_to_details"]
}}
~~~

`%`-prefixed methods reachable from user code at the top level. Most are **global forms** of user-only `%engine.X` slots — `%net` is sugar over `%engine.network`, `%utils.tmp` is sugar over `%engine.tmp`, etc. — and are reachable from any role (subject to that role having been granted the capability). A few are language constructs (`%self`, `%scope`, `%bucket`, `%call`) rather than capability surfaces.

For the user-only engine-slot view, see [script-context.md](../script-context.md).

For the syntactic spec of the `%` prefix (what it means, how shorthands like `%[url]` work), see [syntax/system-methods.md](../syntax/system-methods.md).

---

<a id="catalog"></a>
## Catalog

### Capability surfaces

These are the global forms of `%engine.X` slots. Reachable from any role.

| Method | Purpose | Docs |
|---|---|---|
| `%net` | Networking — HTTP client, raw sockets, fetch | [utils/](utils/#utilsnetwork), [../network/](../network/) |
| `%utils` | Convenience utilities — forks, broadcast, tmp, timer, random, encryption, etc. | [utils/](utils/) |
| `%puck` | Library lookup and class registration (URL → class) | [../puck/](../puck/) |
| `%chain` | Ambient logging chain; nested call-frame tree | [../packages/jasmine/caspian.md](../packages/jasmine/caspian.md) |
| `%stdout` / `%stderr` | Output and error streams | [../script-context.md#streams](../script-context.md#streams) |
| `%stdin` | Input stream | [../script-context.md#streams](../script-context.md#streams) |

### Shorthand forms

| Shorthand | Expands to |
|---|---|
| `%[url]` / `%puck[url]` | Library lookup by URL |
| `%vibecode <<EOF ... EOF` | `%documentation <<EOF('vibecode') ... EOF` |

### Language constructs

These are `%`-prefixed but aren't capability surfaces — they're language-level globals. Full catalog at [syntax/system-methods.md](../syntax/system-methods.md).

| Method | Purpose |
|---|---|
| `%self` | The current object instance (`self` is the bare-word shorthand) |
| `%bucket` | The current object's private data hash (`@foo` is the bare-word shorthand) |
| `%scope` | (Post-V1) Reflective lexical-scope access — see [ideas/caspian/scope.md](../../../ideas/caspian/scope.md) |
| `%call` | The current call object — function/closure, dispatcher, blocks, return |
| `%role` | The currently-executing role |
| `%process` | Process control — `.exit`, `.abort` |
| `%documentation` / `%vibecode` | Save a documentation block in CaspianJ (pre-V1.0 not available to running scripts) |
| `%engine` | **User-only**, top-level only — gateway to host resources. See [script-context.md](../script-context.md) |

---

## See also

- [script-context.md](../script-context.md) — what `%engine.*` provides to user code; the engine-only view.
- [syntax/system-methods.md](../syntax/system-methods.md) — the `%` prefix as syntax; shorthands; full method catalog.
- [roles.md](../roles.md) — why capabilities differ across roles.
