# Caspian++

<a id="status"></a>
## Status

~~~json
{"vibecode": {
	"section": "status"
}}
~~~

**Retired.** Caspian++ has been merged into Caspian. Forking is now a standard Caspian
feature, engine-granted via `%forks` and `%tmp`. There is no longer a separate Caspian++
language variant.

<a id="lua-implementation-note"></a>
## Lua Implementation Note

Lua has no native fork support. When implementing forking in the Lua reference
implementation, prefer an existing Lua library over writing a C extension from scratch.
The goal is to avoid reimplementing Puck in C just to handle forking.

---

<a id="overview"></a>
## Overview

Forking is now a standard Caspian feature. The engine grants it by providing non-null
`%forks` and `%tmp` globals. A script that doesn't use forking is unaffected — both
globals are `null` by default.

See [threads.md](threads.md) for the full `%forks` and `%tmp` API.

---

<a id="hives"></a>
## Hives

Hives are implemented in Caspian — a mikobase is a useful local object store on its own.
Caspian++ adds the ability to share a mikobase between forked processes, making it the
coordination mechanism for concurrent forks.

See [mikobase.md](../../mikobase/mikobase.md) for the full mikobase design.

---

<a id="security-extensions"></a>
## Security Extensions

Caspian++ extends Caspian's core security model for the forking context:

- `%role` — identity and context store passed down the call chain. Probably a Caspian++
  feature. See [roles.md](roles.md) for the full design.
- A forked process can be restricted from spawning its own child forks. This is the
  primary mechanism for preventing untrusted code from escaping its sandbox through
  forking.
- Further security design is TBD.

---

<a id="what-stays-in-caspian"></a>
## What Stays in Caspian

The following are Caspian features, not Caspian++:

- All language primitives, classes, functions, closures, exceptions, warnings
- `untrusted()`, `%chain` sandboxing
- The core security model
- Single-threaded execution context
- Hives as local object stores, including file-backed (`puck.uno/mikobase/sqlite`)
