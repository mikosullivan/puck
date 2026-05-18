# Charlie++

<a id="status"></a>
## 1 Status

```
vibecode: {
	"section": "status"
}
```

**Retired.** Charlie++ has been merged into Charlie. Forking is now a standard Charlie
feature, engine-granted via `%forks` and `%tmp`. There is no longer a separate Charlie++
language variant.

<a id="lua-implementation-note"></a>
## 2 Lua Implementation Note

Lua has no native fork support. When implementing forking in the Lua reference
implementation, prefer an existing Lua library over writing a C extension from scratch.
The goal is to avoid reimplementing Puck in C just to handle forking.

---

<a id="overview"></a>
## 3 Overview

Forking is now a standard Charlie feature. The engine grants it by providing non-null
`%forks` and `%tmp` globals. A script that doesn't use forking is unaffected — both
globals are `null` by default.

See [threads.md](threads.md) for the full `%forks` and `%tmp` API.

---

<a id="hives"></a>
## 4 Hives

Hives are implemented in Charlie — a mikobase is a useful local object store on its own.
Charlie++ adds the ability to share a mikobase between forked processes, making it the
coordination mechanism for concurrent forks.

See [mikobase.md](../../mikobase/mikobase.md) for the full mikobase design.

---

<a id="security-extensions"></a>
## 5 Security Extensions

Charlie++ extends Charlie's core security model for the forking context:

- `%role` — identity and context store passed down the call chain. Probably a Charlie++
  feature. See [roles.md](roles.md) for the full design.
- A forked process can be restricted from spawning its own child forks. This is the
  primary mechanism for preventing untrusted code from escaping its sandbox through
  forking.
- Further security design is TBD.

---

<a id="what-stays-in-charlie"></a>
## 6 What Stays in Charlie

The following are Charlie features, not Charlie++:

- All language primitives, classes, functions, closures, exceptions, warnings
- `untrusted()`, `%chain` sandboxing
- The core security model
- Single-threaded execution context
- Hives as local object stores, including file-backed (`puck.uno/mikobase/sqlite`)
