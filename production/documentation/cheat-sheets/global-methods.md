# Cheat sheet: global methods

~~~vibecode
{"vibecode": {
	"doc": "cheat_sheets_global_methods",
	"role": "one-view reference table for every %X-prefixed global — the standalone system namespaces (%self, %bucket, %platter, %call, %chain, %engine, %fs) and the bare-%X chain-mediated shortcuts (%import, %stdout, %stderr, %stdin). Each row links to the canonical spec and calls out where the surface is available and any role/grant constraint. Clock and randomness are downloadable core objects, not globals — see the 'not global methods' section. Not spec-authoritative — see the linked docs for the full surface of each global.",
	"status": "cheat sheet — table plus short prose; canonical spec lives per-global on the linked pages",
	"audience": "developers writing Caspian who want a single-page answer to 'what are all the % globals?'"
}}
~~~

Every `%X`-prefixed name in Caspian, in one table. For the full surface of any entry, follow the link — this page is a lookup, not a spec.

## The table

Sorted alphabetically.

| Global | Where it works | Default granted? | Purpose |
|---|---|---|---|
| [`%bucket`](https://puck.uno/requirements/built-in-classes/object/structure/) | Method body | — | The receiver's shared top-level bucket (a hash). `@foo` is shorthand for `%bucket['foo']`. |
| [`%call`](https://puck.uno/requirements/global-methods/call/) | Any function / closure / method body | — | The current call object. Exposes `%call.role`, `%call.return`, `%call.blocks`, `%call.method_class`. |
| [`%chain`](https://puck.uno/requirements/chain/) | Anywhere | — | The ambient call-frame chain. Grants and revokes ride here. <!-- STALE: %chain.X syntax being reworked --> |
| [`%engine`](https://puck.uno/requirements/engine/) | Anywhere | **User role only** | Host-resource gateway. Non-user code raises on any `%engine` access. Populates the chain slots at bootstrap. |
| [`%import`](https://puck.uno/requirements/import) | Anywhere | Yes | Object download by URL. `%(url)` is the further shorthand. <!-- STALE: %chain.X syntax being reworked --> |
| [`%fs`](https://puck.uno/requirements/global-methods/fs) | Anywhere | **User role only** | Filesystem namespace. `%fs.root` returns the root dir handle (a dirjail). Non-user code has NO `%fs` — a role-level hard rule, not chain-mediated. |
| [`%platter`](https://puck.uno/requirements/built-in-classes/object/structure/) | Method body (platter-scoped) | — | The current platter's own bucket. No `@`-style shorthand; write `%platter['foo']` explicitly. |
| [`%self`](https://puck.uno/requirements/global-methods/#self) | Method body | — | The current object instance. Bare `self` is shorthand. Not available in bare functions, closures, or top-level code (unless a closure captures an enclosing method's `%self`). |
| [`%stderr`](https://puck.uno/requirements/chain/methods/stdout-and-stderr) | Anywhere | No | Diagnostic-output channel. Grant to non-user code with `%chain.grant :stderr`. <!-- STALE: %chain.X syntax being reworked --> |
| [`%stdin`](https://puck.uno/requirements/chain/methods/stdin) | Anywhere | No | Input channel. Grant to non-user code with `%chain.grant :stdin`. <!-- STALE: %chain.X syntax being reworked --> |
| [`%stdout`](https://puck.uno/requirements/chain/methods/stdout-and-stderr) | Anywhere | No | Primary output channel. Grant to non-user code with `%chain.grant :stdout`. <!-- STALE: %chain.X syntax being reworked --> |

## Shortcuts and shorthands

- **`@foo`** — shorthand for `%bucket['foo']`. Method body only.
- **`%(url)`** — shorthand for `%import(url)`.

## Not global methods

A few names look global-shaped but aren't:

- **`documentation`, `vibecode`, `puts`, `print`, `field`, `method`, `private`, `inherits`, `abstract`** — bareword commands (bwcs), a separate parser category. Have no `%` prefix.
- **`%engine.X` slots** (`%engine.puck`, `%engine.stdout`, etc.) — properties on `%engine`, not standalone globals. Reach the same underlying resource as the bare-`%X` shortcut; the difference is which role can access which form.
- **Clock and randomness are downloadable objects**, not globals — reach them via `%('core:now')` and `%('core:random')` (`%(...)` is the shorthand for `%import(...)`). Each call returns a fresh object; capture and use.
