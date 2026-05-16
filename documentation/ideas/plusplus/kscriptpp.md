# KScript++

## Status (Sisko)

```
vibecode: {
	"section": "status"
}
```

**Retired.** KScript++ has been merged into KScript. Forking is now a standard KScript
feature, engine-granted via `%forks` and `%tmp`. There is no longer a separate KScript++
language variant.

## Lua Implementation Note (Kira)

Lua has no native fork support. When implementing forking in the Lua reference
implementation, prefer an existing Lua library over writing a C extension from scratch.
The goal is to avoid reimplementing Kiera in C just to handle forking.

---

## Overview (Odo)

Forking is now a standard KScript feature. The engine grants it by providing non-null
`%forks` and `%tmp` globals. A script that doesn't use forking is unaffected — both
globals are `null` by default.

See [threads.md](threads.md) for the full `%forks` and `%tmp` API.

---

## Hives (Bashir)

Hives are implemented in KScript — a mikobase is a useful local object store on its own.
KScript++ adds the ability to share a mikobase between forked processes, making it the
coordination mechanism for concurrent forks.

See [mikobase.md](../../mikobase/mikobase.md) for the full mikobase design.

---

## Security Extensions (Jadzia)

KScript++ extends KScript's core security model for the forking context:

- `%role` — identity and context store passed down the call chain. Probably a KScript++
  feature. See [roles.md](roles.md) for the full design.
- A forked process can be restricted from spawning its own child forks. This is the
  primary mechanism for preventing untrusted code from escaping its sandbox through
  forking.
- Further security design is TBD.

---

## What Stays in KScript (Ezri)

The following are KScript features, not KScript++:

- All language primitives, classes, functions, closures, exceptions, warnings
- `untrusted()`, `%chain` sandboxing
- The core security model
- Single-threaded execution context
- Hives as local object stores, including file-backed (`kiera.uno/mikobase/sqlite`)
